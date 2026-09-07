param(
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][int]$OwnerPid,
    [ValidateRange(1000,10000)][int]$IntervalMsec = 1000,
    [switch]$Once
)
# Persistent geometry-only worker. No window text, pixels, input or window mutations.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class MateDesktopGeometry {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MONITORINFOEX {
        public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szDevice;
    }
    public delegate bool WindowProc(IntPtr hwnd, IntPtr data);
    public delegate bool MonitorProc(IntPtr monitor, IntPtr dc, ref RECT rect, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(WindowProc proc, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorProc proc, IntPtr data);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder value, int capacity);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr64(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int GetWindowLong32(IntPtr hwnd, int index);
    [DllImport("dwmapi.dll", EntryPoint="DwmGetWindowAttribute")] static extern int DwmInt(IntPtr hwnd, int attribute, out int value, int size);
    [DllImport("dwmapi.dll", EntryPoint="DwmGetWindowAttribute")] static extern int DwmRect(IntPtr hwnd, int attribute, out RECT value, int size);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    public sealed class MonitorGeometry {
        public string id; public int x,y,width,height,work_x,work_y,work_width,work_height;
    }
    public sealed class WindowGeometry { public string id; public int x,y,width,height,z; }
    public sealed class Snapshot {
        public int version=1; public long timestamp_msec;
        public List<MonitorGeometry> monitors=new List<MonitorGeometry>();
        public List<WindowGeometry> windows=new List<WindowGeometry>();
    }
    public static void Publish(string path, string json) {
        string temporary=path+".tmp";
        System.IO.File.WriteAllText(temporary,json,new UTF8Encoding(false));
        if (System.IO.File.Exists(path)) System.IO.File.Replace(temporary,path,null);
        else System.IO.File.Move(temporary,path);
    }
    public static Snapshot Capture(int ownerPid, int helperPid) {
        try { SetThreadDpiAwarenessContext(new IntPtr(-4)); }
        catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
        Snapshot result=new Snapshot();
        result.timestamp_msec=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,delegate(IntPtr monitor, IntPtr dc, ref RECT rect, IntPtr data) {
            MONITORINFOEX info=new MONITORINFOEX(); info.cbSize=Marshal.SizeOf(typeof(MONITORINFOEX));
            if (GetMonitorInfo(monitor,ref info)) {
                RECT r=info.rcMonitor, w=info.rcWork;
                result.monitors.Add(new MonitorGeometry { id=info.szDevice, x=r.Left,y=r.Top,width=r.Right-r.Left,height=r.Bottom-r.Top,
                    work_x=w.Left,work_y=w.Top,work_width=w.Right-w.Left,work_height=w.Bottom-w.Top });
            }
            return true;
        },IntPtr.Zero);
        IntPtr shell=GetShellWindow(); int z=0;
        EnumWindows(delegate(IntPtr hwnd,IntPtr data) {
            int order=z++;
            if (hwnd==shell || !IsWindowVisible(hwnd) || IsIconic(hwnd)) return true;
            uint pid; GetWindowThreadProcessId(hwnd,out pid);
            if (pid==ownerPid || pid==helperPid) return true;
            int cloaked; if (DwmInt(hwnd,14,out cloaked,4)==0 && cloaked!=0) return true;
            long style=IntPtr.Size==8 ? GetWindowLongPtr64(hwnd,-20).ToInt64() : GetWindowLong32(hwnd,-20);
            // Tool and click-through overlay windows are not usable platforms.
            if ((style & (0x80L | 0x20L))!=0) return true;
            StringBuilder cls=new StringBuilder(256); GetClassName(hwnd,cls,cls.Capacity);
            string name=cls.ToString();
            if (name=="Progman" || name=="WorkerW" || name=="Shell_TrayWnd" || name=="Shell_SecondaryTrayWnd" ||
                name=="DV2ControlHost" || name=="MsgrIMEWindowClass" || name=="Windows.UI.Core.CoreWindow") return true;
            RECT r;
            // DWM visible frame bounds omit invisible resize borders; fallback for classic windows.
            if (DwmRect(hwnd,9,out r,Marshal.SizeOf(typeof(RECT)))!=0 && !GetWindowRect(hwnd,out r)) return true;
            if (r.Right-r.Left<80 || r.Bottom-r.Top<40) return true;
            bool intersects=false;
            foreach (MonitorGeometry m in result.monitors)
                if (r.Right>m.x && r.Left<m.x+m.width && r.Bottom>m.y && r.Top<m.y+m.height) { intersects=true; break; }
            if (!intersects) return true;
            result.windows.Add(new WindowGeometry { id=pid.ToString()+":"+hwnd.ToInt64().ToString("X"),
                x=r.Left,y=r.Top,width=r.Right-r.Left,height=r.Bottom-r.Top,z=order });
            return true;
        },IntPtr.Zero);
        return result;
    }
}
'@
$owner = Get-Process -Id $OwnerPid -ErrorAction Stop
$ownerStart = $owner.StartTime.ToUniversalTime().Ticks
$tempPath = $OutputPath + '.tmp'
$stopPath = $OutputPath + '.stop'
try {
    do {
        $currentOwner = Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue
        if ($null -eq $currentOwner -or $currentOwner.StartTime.ToUniversalTime().Ticks -ne $ownerStart -or (Test-Path -LiteralPath $stopPath)) { break }
        $snapshot = [MateDesktopGeometry]::Capture($OwnerPid, $PID)
        $json = ConvertTo-Json -InputObject $snapshot -Depth 6 -Compress
        [MateDesktopGeometry]::Publish($OutputPath, $json)
        if ($Once) { break }
        Start-Sleep -Milliseconds $IntervalMsec
    } while ($true)
} finally {
    if ([IO.File]::Exists($tempPath)) { [IO.File]::Delete($tempPath) }
}
