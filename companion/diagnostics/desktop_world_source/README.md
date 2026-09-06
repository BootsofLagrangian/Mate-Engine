# Windows desktop geometry source

`DesktopWorldSource` supplies read-only geometry for desktop movement and platforms. It does not move or interact with windows. Root integration owns pet movement, sitting, scaling and the main scene.

Before implementing, inspected the original Unity sources:

- `Assets/MATE ENGINE - Scripts/AvatarHandlers/AvatarWindowHandler.cs`: `UpdateCachedWindows`, `IsSitEligibleWindow`, `IsCloaked`, and z-order occlusion. Reused the EnumWindows / visibility / own-process / minimized / cloaked / shell filtering pattern. Did not reuse title-length checks: this helper never calls GetWindowText or GetWindowTextLength.
- `Assets/MATE ENGINE - Scripts/Settings/MonitorHelper.cs`: `GetTaskbarRectForWindow` obtains rcMonitor and rcWork and identifies the reserved edge. The adapter exports both rectangles so the consumer can use the same approach, including taskbars on other edges.
- `Assets/MATE ENGINE - Scripts/AvatarHandlers/AvatarLocomotionController.cs`: monitor bounds and actual own-HWND locomotion are useful references for the movement consumer.
- `Assets/MATE ENGINE - Packages/Kirurobo/UniWindowController/Runtime/Scripts/LowLevel/UniWinCore.cs` and bundled `LibUniWinC.dll` concern Unity's own window integration. They are not needed for this isolated geometry source; Windows PowerShell and built-in Win32 APIs avoid a new binary dependency.

## Integration

```gdscript
var desktop_source := DesktopWorldSource.new()
add_child(desktop_source)
desktop_source.snapshot_changed.connect(autonomy.set_world_snapshot)
desktop_source.configure(true)
# Disable when desktop interaction is disabled; exit_tree also stops automatically.
desktop_source.configure(false)
```

`start() -> bool` reports whether a worker launched, not whether the first snapshot has arrived. `available`, `last_error`, and `snapshot` expose current state. Linux returns unavailable without starting any child. Enable only with the desktop-world feature. The Windows export must include `*.ps1` so `res://platform/windows_world.ps1` is present in the PCK.

One hidden PowerShell child remains alive while enabled, compiles the small C# Win32 declarations once, and publishes once per second. Godot reads the small local snapshot once per second, never launches a process per frame. The helper uses atomic file replacement and checks that its owner PID still has the same process start time. A normal node stop kills only its created child PID and removes its uniquely named cache directory. A `.stop` sentinel is also supported for standalone helper callers. If the owner crashes the helper exits after its next owner check; that crash path can leave the small cache directory behind.

Successful new timestamps emit `snapshot_changed` even if geometry is unchanged. Dead helper, malformed snapshot, stale timestamp older than five seconds, or disable clears the previous snapshot and emits `{}`. The consumer should retain only its fallback monitor floor when source geometry is unavailable. An unexpected helper exit does not trigger a process restart loop; explicit re-enable retries.

## Version 1 contract

```json
{"version":1,"timestamp_msec":1788700000000,"monitors":[{"id":"\\\\.\\DISPLAY1","x":0,"y":0,"width":1920,"height":1080,"work_x":0,"work_y":0,"work_width":1920,"work_height":1040}],"windows":[{"id":"1234:ABC","x":200,"y":120,"width":700,"height":500,"z":3}]}
```

The helper JSON uses physical Win32 desktop pixels. The Godot signal uses DisplayServer desktop pixels: the source subtracts the componentwise minimum of zero and every monitor origin from all monitor/window/workarea positions. This matches Godot 4.5.2 Windows `_get_screens_origin`, including monitors left of or above the primary. See [Godot Windows display source](https://raw.githubusercontent.com/godotengine/godot/4.5.2-stable/platform/windows/display_server_windows.cpp). The helper requests per-monitor DPI awareness before enumeration. DWM extended-frame bounds omit invisible resize borders; classic windows fall back to GetWindowRect. Monitor IDs use the OS display-device name. Window IDs combine owning PID with hexadecimal HWND and stay stable during a live window's lifetime; Windows can recycle handles after destruction, so they are not durable application identities. `z` is the EnumWindows order: smaller means nearer the foreground; filtered windows can leave gaps.

Shell/taskbar windows, owner/helper windows, minimized, invisible, cloaked, tool and click-through windows, tiny rectangles, and rectangles outside all monitors are excluded. Workarea boundaries represent the taskbar/reserved desktop edge instead. No window title, text, pixels, input, screenshots or process names are returned. Class names are read only for shell filtering and are not included in output. A window may disappear or move between one-second snapshots; the consumer must handle invalidated supports.

## Verification (2026-09-06)

- Linux Godot 4.5.2: valid negative-origin geometry accepted and translated for left/above-primary layouts without mutating raw input; missing fields, negative size and NaN rejected; unavailable OS starts no child.
- Actual Windows PowerShell: created one dedicated nonactivating WinForms window; measured DWM rectangle `(127,120,346,233)`; moved only that fixture by `(80,60)` and received `(207,180,346,233)` with the same window ID. Minimized fixture disappeared. Two monitor records received. Timestamp advanced; owner/helper IDs absent; stop sentinel terminated worker. The fixture was closed/disposed and test directory removed. `windows_geometry_result.json` contains only the fixture geometry and aggregate checks, not other windows' geometry.
- Actual Windows Godot 4.5.2: native node receives repeated snapshots, validates monitor geometry, terminates its owned child, and removes its cache on stop. An additional hidden Windows DisplayServer probe compares every published workarea against screen_get_usable_rect. `windows_source_result.log` retains the result.

An initial Windows run exposed PowerShell converting a `$null` File.Replace backup argument into an invalid empty path. Publishing now calls C# File.Replace with a real null; both Windows tests passed after this fix. Independent review additionally found the raw Win32/Godot origin mismatch; the source now translates at its boundary and tests both synthetic negative-origin layouts and actual DisplayServer workareas. Cloaked filtering and mixed-DPI behavior are source-inspected, not separately exercised using a cloaked or mixed-DPI fixture.

From `companion` on Linux:

```sh
./tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path native --script "$PWD/diagnostics/desktop_world_source/probe_source.gd"
```

From `companion` in Windows PowerShell:

```powershell
& .\tools\Godot_v4.5.2-stable_win64_console.exe --headless --path native --script "$PWD\diagnostics\desktop_world_source\probe_source.gd"
& .\tools\Godot_v4.5.2-stable_win64_console.exe --display-driver windows --rendering-method gl_compatibility --position "-10000,-10000" --resolution 32x32 --path native --script "$PWD\diagnostics\desktop_world_source\probe_source.gd"
& .\diagnostics\desktop_world_source\test_geometry.ps1 -HelperPath "$PWD\native\platform\windows_world.ps1" -FixturePath "$PWD\diagnostics\desktop_world_source\test_window.ps1" -ResultPath "$PWD\diagnostics\desktop_world_source\windows_geometry_result.json"
```

The DisplayServer command hides its own offscreen test root. The last command briefly shows its own test fixture; neither manipulates existing user windows.

Independent review: **APPROVED** by astra_backend after the coordinate-origin correction. The reviewer independently reran the Linux probe and checked the actual Windows DisplayServer and lifecycle artifacts. No blocking source findings remain.
