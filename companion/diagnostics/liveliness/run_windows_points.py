#!/usr/bin/env python3
"""Opt-in real-Windows runner for native/tools/probe_windows_points.gd (root runs this; never CI).

Starts the Windows Godot editor binary (or the packaged MateCompanion.exe with --packaged) with the
probe script against the live backend, waits for <output>/ready.json, verifies that the window under
the pin's grab point belongs to the probe process and has the reported rectangle, then performs ONE
left-button drag of that pin with a temporary PowerShell/C# user32 helper (SetCursorPos +
mouse_event) and restores the original cursor position. It never captures desktop pixels and never
clicks anything that is not the probe's own marker window. --no-input skips the drag entirely.

Usage (Windows PowerShell, from the repo root):
    py companion\\diagnostics\\liveliness\\run_windows_points.py [--packaged] [--no-input]
        [--drag-dx 160 --drag-dy -90] [--wait-seconds 60] [--output companion\\logs\\windows-points]
From WSL the same command works with python3 (powershell.exe / the Windows exe via interop).
Exit status: the probe's (0 = every CHECK passed); 3 = runner-side failure (no ready.json, wrong
window under the pin, drag helper error).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
COMPANION = os.path.abspath(os.path.join(HERE, "..", ".."))
NATIVE = os.path.join(COMPANION, "native")
IS_WSL = sys.platform != "win32" and hasattr(os, "uname") and "microsoft" in os.uname().release.lower()

DRAG_PS1 = r"""
param([int]$OwnerPid, [int]$GrabX, [int]$GrabY, [int]$Dx, [int]$Dy, [int]$RectX, [int]$RectY, [int]$RectW, [int]$RectH, [switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class MatePinDrag {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
    public static string Describe(int x, int y) {
        POINT p; p.X = x; p.Y = y;
        IntPtr h = WindowFromPoint(p);
        uint pid; GetWindowThreadProcessId(h, out pid);
        RECT r; GetWindowRect(h, out r);
        return pid + " " + r.Left + " " + r.Top + " " + (r.Right - r.Left) + " " + (r.Bottom - r.Top);
    }
}
"@
[void][MatePinDrag]::SetProcessDPIAware()
# Godot normalizes the virtual desktop origin; user32 uses raw Win32 pixels.
$virtualX = [MatePinDrag]::GetSystemMetrics(76)
$virtualY = [MatePinDrag]::GetSystemMetrics(77)
$GrabX += $virtualX; $RectX += $virtualX
$GrabY += $virtualY; $RectY += $virtualY
$desc = [MatePinDrag]::Describe($GrabX, $GrabY).Split(' ')
$owner = [int]$desc[0]
if ($owner -ne $OwnerPid) { Write-Output "VERIFY_FAIL owner_pid=$owner expected=$OwnerPid"; exit 4 }
if ([int]$desc[1] -ne $RectX -or [int]$desc[2] -ne $RectY -or [int]$desc[3] -ne $RectW -or [int]$desc[4] -ne $RectH) {
    Write-Output "VERIFY_FAIL rect=$($desc[1..4] -join ',') expected=$RectX,$RectY,$RectW,$RectH"; exit 5 }
Write-Output "VERIFY_OK pid=$owner rect=$($desc[1..4] -join ',')"
if ($VerifyOnly) { exit 0 }
$orig = New-Object MatePinDrag+POINT
[void][MatePinDrag]::GetCursorPos([ref]$orig)
try {
    [void][MatePinDrag]::SetCursorPos($GrabX, $GrabY); Start-Sleep -Milliseconds 120
    [MatePinDrag]::mouse_event([MatePinDrag]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 120
    $steps = 24
    for ($i = 1; $i -le $steps; $i++) {
        [void][MatePinDrag]::SetCursorPos($GrabX + [int]([math]::Round($Dx * $i / $steps)), $GrabY + [int]([math]::Round($Dy * $i / $steps)))
        Start-Sleep -Milliseconds 16
    }
    [void][MatePinDrag]::SetCursorPos($GrabX + $Dx, $GrabY + $Dy); Start-Sleep -Milliseconds 120
    [MatePinDrag]::mouse_event([MatePinDrag]::LEFTUP, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 120
} finally {
    [MatePinDrag]::mouse_event([MatePinDrag]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
    [void][MatePinDrag]::SetCursorPos($orig.X, $orig.Y)
}
Write-Output "DRAG_DONE"
"""


def win_path(path):
    """Path as the Windows side sees it (WSL interop needs wslpath -w)."""
    if IS_WSL:
        return subprocess.check_output(["wslpath", "-w", path], text=True).strip()
    return path


def powershell():
    for name in ("powershell.exe", "powershell", "pwsh.exe", "pwsh"):
        if shutil.which(name):
            return name
    raise RuntimeError("PowerShell not found on PATH")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default=os.path.join(COMPANION, "tools", "Godot_v4.5.2-stable_win64_console.exe"))
    ap.add_argument("--packaged", action="store_true", help="run native/build/MateCompanion.exe --script instead of the editor binary")
    ap.add_argument("--exe", default=os.path.join(NATIVE, "build", "MateCompanion.exe"))
    ap.add_argument("--no-input", action="store_true", help="never synthesize input; probe only verifies geometry/signals")
    ap.add_argument("--drag-dx", type=int, default=160)
    ap.add_argument("--drag-dy", type=int, default=-90)
    ap.add_argument("--wait-seconds", type=float, default=60.0)
    ap.add_argument("--ready-timeout", type=float, default=120.0)
    ap.add_argument("--output", default=os.path.join(COMPANION, "logs", "windows-points"))
    args = ap.parse_args()

    out = os.path.abspath(args.output)
    os.makedirs(out, exist_ok=True)
    for stale in ("ready.json", "report.json"):
        try:
            os.remove(os.path.join(out, stale))
        except FileNotFoundError:
            pass
    probe_args = ["--", "--test-root", win_path(COMPANION), "--output", win_path(out),
                  "--drag-dx", str(args.drag_dx), "--drag-dy", str(args.drag_dy), "--wait-seconds", str(args.wait_seconds)]
    if args.no_input:
        probe_args.append("--no-input")
    if args.packaged:
        cmd = [args.exe, "--script", win_path(os.path.join(NATIVE, "tools", "probe_windows_points.gd"))] + probe_args
    else:
        cmd = [args.godot, "--path", win_path(NATIVE), "--script", "tools/probe_windows_points.gd"] + probe_args
    print("launch:", " ".join(cmd), flush=True)
    log = open(os.path.join(out, "godot.log"), "w", encoding="utf-8")
    proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)

    ready_path = os.path.join(out, "ready.json")
    deadline = time.time() + args.ready_timeout
    ready = None
    while time.time() < deadline and proc.poll() is None:
        if os.path.exists(ready_path):
            try:
                with open(ready_path, encoding="utf-8") as f:
                    ready = json.load(f)
                break
            except (OSError, ValueError):
                pass
        time.sleep(0.25)
    if ready is None:
        print("runner: ready.json did not appear (process alive=%s); see %s" % (proc.poll() is None, log.name))
        if proc.poll() is None:
            proc.wait(timeout=args.wait_seconds + 60)
        return 3
    print("ready:", json.dumps(ready), flush=True)
    owner_pid = int(ready.get("pid", -1))
    # Linux and Windows PID namespaces can coincide numerically by chance.
    # WSL always requires executable and unique probe-command verification.
    owned = not IS_WSL and owner_pid == proc.pid
    if not owned and 0 < owner_pid < 2**32:
        # Interop has separate Linux/Windows PID namespaces. Check the reported
        # Windows process executable and unique probe command before any input.
        query = (f"Get-CimInstance Win32_Process -Filter 'ProcessId={owner_pid}' | "
                 "Select-Object ExecutablePath,CommandLine | ConvertTo-Json -Compress")
        identity = subprocess.run([powershell(), "-NoProfile", "-Command", query],
                                  capture_output=True, text=True, errors="replace", timeout=15)
        try:
            actual = json.loads(identity.stdout)
            expected = win_path(os.path.abspath(args.exe if args.packaged else args.godot))
            expected_paths = {expected.casefold()}
            if expected.casefold().endswith("_console.exe"):
                expected_paths.add(expected[:-len("_console.exe")].casefold() + ".exe")
            owned = (str(actual.get("ExecutablePath", "")).casefold() in expected_paths
                     and "probe_windows_points.gd" in str(actual.get("CommandLine", ""))
                     and win_path(out) in str(actual.get("CommandLine", "")))
        except (ValueError, AttributeError):
            owned = False
        with open(os.path.join(out, "process-identity.json"), "w", encoding="utf-8") as identity_log:
            json.dump({"windows_pid": owner_pid, "launcher_pid": proc.pid, "verified": owned,
                       "response": identity.stdout, "stderr": identity.stderr}, identity_log, indent=2)
    if not owned:
        print("runner: probe pid %s is not the launched process %s; refusing to drive input" % (ready.get("pid"), proc.pid))
        proc.wait(timeout=args.wait_seconds + 60)
        return 3

    status = 0
    if not args.no_input:
        marker = ready["marker"]
        gx, gy = marker["grab"]
        rect = marker["rect"]
        with tempfile.TemporaryDirectory(prefix="mate-pin-drag-") as tmp:
            ps1 = os.path.join(tmp, "drag_pin.ps1")
            with open(ps1, "w", encoding="utf-8") as f:
                f.write(DRAG_PS1)
            ps_cmd = [powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", win_path(ps1),
                      "-OwnerPid", str(ready["pid"]), "-GrabX", str(gx), "-GrabY", str(gy),
                      "-Dx", str(args.drag_dx), "-Dy", str(args.drag_dy),
                      "-RectX", str(rect["x"]), "-RectY", str(rect["y"]), "-RectW", str(rect["w"]), "-RectH", str(rect["h"])]
            time.sleep(0.5)  # let the pin window settle before touching it
            drag = subprocess.run(ps_cmd, capture_output=True, text=True, errors="replace", timeout=20)
            print("drag helper:", drag.stdout.strip(), drag.stderr.strip(), flush=True)
            if drag.returncode != 0:
                print("runner: refused/failed to drag (exit %d); the probe will time out on point_placed" % drag.returncode)
                status = 3
    proc.wait(timeout=args.wait_seconds + 120)
    log.close()
    report_path = os.path.join(out, "report.json")
    if os.path.exists(report_path):
        with open(report_path, encoding="utf-8") as f:
            report = json.load(f)
        failed = [c["label"] for c in report.get("checks", []) if not c.get("ok")]
        print("probe: %d checks, %d failures" % (len(report.get("checks", [])), report.get("failures", -1)))
        for label in failed:
            print("  FAIL:", label)
        if report.get("tip_shift") is not None:
            print("tip shift:", report["tip_shift"])
    else:
        print("runner: no report.json written; see", log.name)
        return 3 if status == 0 else status
    return proc.returncode if status == 0 else status


if __name__ == "__main__":
    sys.exit(main())
