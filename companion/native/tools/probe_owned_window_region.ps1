param([Parameter(Mandatory=$true)][string]$RequestPath,
      [Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference = 'Stop'
$result = @{ok=$false}
try {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MateRegionProbe {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetWindowRgn(IntPtr hwnd, IntPtr region);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd, ref POINT point);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int left,int top,int right,int bottom);
    [DllImport("gdi32.dll")] public static extern bool PtInRegion(IntPtr region,int x,int y);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
}
'@
    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    $hwnd = [IntPtr]([long]$request.hwnd)
    [uint32]$owner = 0
    [void][MateRegionProbe]::GetWindowThreadProcessId($hwnd,[ref]$owner)
    if ($owner -ne [uint32]$request.process_id) { throw 'HWND does not belong to requested process' }
    $title = New-Object System.Text.StringBuilder 512
    [void][MateRegionProbe]::GetWindowText($hwnd,$title,$title.Capacity)
    if ($title.ToString() -notmatch '^Mate ?Companion') { throw 'HWND title is not Mate Companion' }
    if (-not [MateRegionProbe]::IsWindowVisible($hwnd)) { throw 'Owned HWND is not visible' }
    $rect = New-Object MateRegionProbe+RECT
    if (-not [MateRegionProbe]::GetWindowRect($hwnd,[ref]$rect)) { throw 'GetWindowRect failed' }
    $region = [MateRegionProbe]::CreateRectRgn(0,0,0,0)
    if ($region -eq [IntPtr]::Zero) { throw 'CreateRectRgn failed' }
    try {
        $kind = [MateRegionProbe]::GetWindowRgn($hwnd,$region)
        if ($kind -lt 2) { throw "Owned HWND has no nonempty explicit region: $kind" }
        $samples = @()
        foreach ($sample in $request.points) {
            $point = New-Object MateRegionProbe+POINT
            $point.X = [int]$sample.x; $point.Y = [int]$sample.y
            if (-not [MateRegionProbe]::ClientToScreen($hwnd,[ref]$point)) { throw 'ClientToScreen failed' }
            $inside = [MateRegionProbe]::PtInRegion($region,$point.X-$rect.Left,$point.Y-$rect.Top)
            $samples += @{x=$sample.x;y=$sample.y;inside=$inside}
        }
        $rejected = @($samples | Where-Object { -not $_.inside }).Count
        $result = @{ok=($samples.Count -gt 0 -and $rejected -eq 0);process_id=$owner;
            hwnd=$request.hwnd;title=$title.ToString();region_kind=$kind;
            sampled=$samples.Count;rejected=$rejected;samples=$samples;
            scope='PID-owned HWND region inclusion of opaque viewport furniture pixels outside original character/UI region; no desktop capture or compositor colour claim'}
    } finally { [void][MateRegionProbe]::DeleteObject($region) }
} catch { $result = @{ok=$false;reason=$_.Exception.Message} }
[System.IO.File]::WriteAllText($ResultPath,($result | ConvertTo-Json -Depth 8),(New-Object System.Text.UTF8Encoding($false)))
if (-not $result.ok) { exit 1 }
