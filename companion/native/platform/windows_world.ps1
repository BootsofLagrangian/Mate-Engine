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
using System.Diagnostics;
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
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x,y; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public UIntPtr wParam; public IntPtr lParam; public uint time; public POINT pt; public uint lPrivate; }
    delegate void EventProc(IntPtr hook,uint kind,IntPtr hwnd,int objectId,int childId,uint threadId,uint eventTime);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr module,EventProc callback,uint pid,uint thread,uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern bool PeekMessage(out MSG message,IntPtr hwnd,uint min,uint max,uint remove);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG message);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG message);
    [DllImport("user32.dll")] static extern uint MsgWaitForMultipleObjectsEx(uint count,IntPtr handles,uint timeout,uint wakeMask,uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hwnd,uint flags);
    static readonly Stopwatch Clock=Stopwatch.StartNew();
    static readonly List<IntPtr> Hooks=new List<IntPtr>();
    static readonly HashSet<IntPtr> OwnedWindows=new HashSet<IntPtr>();
    static readonly HashSet<IntPtr> ExternalWindows=new HashSet<IntPtr>();
    static EventProc Callback;
    static GCHandle CallbackHandle;
    static int Owner,Helper;
    static bool Dirty;
    static long LastCapture=-10000,Events,IgnoredOwner,Captures;
    public const int MinimumCaptureMsec=125;
    public static int StartEvents(int ownerPid,int helperPid) {
        Owner=ownerPid;Helper=helperPid;
        Callback=OnEvent;
        CallbackHandle=GCHandle.Alloc(Callback);
        // OUTOFCONTEXT | SKIPOWNPROCESS. Delivery occurs on this pumping thread.
        // Foreground; move/size start/end; minimize start/end; destroy/show/hide/
        // reorder; location change. Object notifications are filtered to HWNDs.
        // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setwineventhook
        foreach (uint[] range in new uint[][] {new uint[]{3,3},new uint[]{10,11},new uint[]{22,23},new uint[]{0x8001,0x8004},new uint[]{0x800B,0x800B}}) {
            IntPtr hook=SetWinEventHook(range[0],range[1],IntPtr.Zero,Callback,0,0,2);
            if(hook!=IntPtr.Zero) Hooks.Add(hook);
        }
        return Hooks.Count;
    }
    static void OnEvent(IntPtr hook,uint kind,IntPtr hwnd,int objectId,int childId,uint threadId,uint eventTime) {
        if(hwnd==IntPtr.Zero || (kind>=0x8000 && (objectId!=0 || childId!=0))) return;
        uint pid;GetWindowThreadProcessId(hwnd,out pid);
        if(pid==Owner || pid==Helper || (pid==0 && OwnedWindows.Contains(hwnd))) {
            IgnoredOwner++;
            if(kind==0x8001) OwnedWindows.Remove(hwnd);else OwnedWindows.Add(hwnd);
            return;
        }
        // Destroyed HWNDs no longer resolve a PID/root: use last captured identity.
        if(pid==0) {if(kind!=0x8001 || !ExternalWindows.Contains(hwnd)) return;}
        else if(GetAncestor(hwnd,2)!=hwnd) return;
        Events++;Dirty=true;
    }
    public static void StopEvents() {
        foreach(IntPtr hook in Hooks) UnhookWinEvent(hook);
        Hooks.Clear();
        if(CallbackHandle.IsAllocated) CallbackHandle.Free();
        Callback=null;OwnedWindows.Clear();ExternalWindows.Clear();
    }
    public static void WaitForCapture(int heartbeatMsec) {
        // Pump queued hook callbacks while waiting. No polling process or busy loop.
        while(true) {
            MSG message;
            while(PeekMessage(out message,IntPtr.Zero,0,0,1)) {TranslateMessage(ref message);DispatchMessage(ref message);}
            long elapsed=Clock.ElapsedMilliseconds-LastCapture;
            long due=Dirty ? MinimumCaptureMsec : heartbeatMsec;
            if(elapsed>=due) return;
            // QS_ALLINPUT and MWMO_INPUTAVAILABLE wake for queued callbacks.
            MsgWaitForMultipleObjectsEx(0,IntPtr.Zero,(uint)Math.Max(1,due-elapsed),0x04FF,4);
        }
    }
    public sealed class MonitorGeometry {
        public string id; public int x,y,width,height,work_x,work_y,work_width,work_height;
    }
    public sealed class WindowGeometry { public string id, class_name; public int x,y,width,height,z; }
    public sealed class Snapshot {
        public int version=1; public long timestamp_msec, capture_us, capture_count, event_count, ignored_owner_events; public int event_hook_count, minimum_capture_msec=MinimumCaptureMsec;
        public List<MonitorGeometry> monitors=new List<MonitorGeometry>();
        public List<WindowGeometry> windows=new List<WindowGeometry>();
        public List<WindowGeometry> taskbars=new List<WindowGeometry>();
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
        LastCapture=Clock.ElapsedMilliseconds;Dirty=false;Captures++;
        ExternalWindows.Clear();
        var timer=System.Diagnostics.Stopwatch.StartNew();
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
            if (pid==ownerPid || pid==helperPid) {OwnedWindows.Add(hwnd);return true;}
            int cloaked; if (DwmInt(hwnd,14,out cloaked,4)==0 && cloaked!=0) return true;
            StringBuilder cls=new StringBuilder(256); GetClassName(hwnd,cls,cls.Capacity);
            string name=cls.ToString();
            if (name=="Shell_TrayWnd" || name=="Shell_SecondaryTrayWnd") {
                RECT bar;
                if (!GetWindowRect(hwnd,out bar)) return true;
                foreach (MonitorGeometry m in result.monitors) {
                    int left=Math.Max(bar.Left,m.x), top=Math.Max(bar.Top,m.y);
                    int right=Math.Min(bar.Right,m.x+m.width), bottom=Math.Min(bar.Bottom,m.y+m.height);
                    // Hidden auto-hide bars leave a thin activation strip, not a seat.
                    if (right-left<8 || bottom-top<8) continue;
                    ExternalWindows.Add(hwnd);
                    result.taskbars.Add(new WindowGeometry { id=pid.ToString()+":"+hwnd.ToInt64().ToString("X")+":"+m.id,
                        class_name=name,x=left,y=top,width=right-left,height=bottom-top,z=order });
                }
                return true;
            }
            long style=IntPtr.Size==8 ? GetWindowLongPtr64(hwnd,-20).ToInt64() : GetWindowLong32(hwnd,-20);
            // Tool and click-through overlay windows are not usable platforms.
            if ((style & (0x80L | 0x20L))!=0) return true;
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
            ExternalWindows.Add(hwnd);
            result.windows.Add(new WindowGeometry { id=pid.ToString()+":"+hwnd.ToInt64().ToString("X"),
                x=r.Left,y=r.Top,width=r.Right-r.Left,height=r.Bottom-r.Top,z=order });
            return true;
        },IntPtr.Zero);
        result.capture_count=Captures;result.event_count=Events;result.ignored_owner_events=IgnoredOwner;result.event_hook_count=Hooks.Count;
        result.capture_us=timer.ElapsedTicks*1000000L/System.Diagnostics.Stopwatch.Frequency;
        return result;
    }
}
'@
$owner = Get-Process -Id $OwnerPid -ErrorAction Stop
$ownerStart = $owner.StartTime.ToUniversalTime().Ticks
$tempPath = $OutputPath + '.tmp'
$stopPath = $OutputPath + '.stop'
try {
    if (-not $Once) { [void][MateDesktopGeometry]::StartEvents($OwnerPid, $PID) }
    do {
        $currentOwner = Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue
        if ($null -eq $currentOwner -or $currentOwner.StartTime.ToUniversalTime().Ticks -ne $ownerStart -or (Test-Path -LiteralPath $stopPath)) { break }
        $snapshot = [MateDesktopGeometry]::Capture($OwnerPid, $PID)
        $json = ConvertTo-Json -InputObject $snapshot -Depth 6 -Compress
        [MateDesktopGeometry]::Publish($OutputPath, $json)
        if ($Once) { break }
        [MateDesktopGeometry]::WaitForCapture($IntervalMsec)
    } while ($true)
} finally {
    [MateDesktopGeometry]::StopEvents()
    if ([IO.File]::Exists($tempPath)) { [IO.File]::Delete($tempPath) }
}
