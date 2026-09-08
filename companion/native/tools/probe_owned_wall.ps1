param([Parameter(Mandatory=$true)][string]$ControlPath,
      [Parameter(Mandatory=$true)][string]$ReadyPath)
# Only this owned fixture window is moved. No external window input or captures.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MateWallDpi {
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
[void][MateWallDpi]::SetThreadDpiAwarenessContext([IntPtr](-4))
$form=New-Object System.Windows.Forms.Form
$form.Text='Mate wall-contact test fixture'
$form.StartPosition='Manual'
$form.Size=New-Object System.Drawing.Size(360,420)
$form.Location=New-Object System.Drawing.Point(100,100)
$form.TopMost=$false
$form.BackColor=[System.Drawing.Color]::FromArgb(45,57,70)
$script:sequence=-1
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=100
$timer.Add_Tick({
    try {
        if(-not(Test-Path -LiteralPath $ControlPath)){return}
        $command=Get-Content -LiteralPath $ControlPath -Raw|ConvertFrom-Json
        if([int]$command.sequence -eq $script:sequence){return}
        $script:sequence=[int]$command.sequence
        if($command.close){$form.Close();return}
        $form.Location=New-Object System.Drawing.Point([int]$command.x,[int]$command.y)
        $form.Size=New-Object System.Drawing.Size([int]$command.width,[int]$command.height)
        $data=@{process_id=$PID;hwnd=$form.Handle.ToInt64().ToString();sequence=$script:sequence}
        [System.IO.File]::WriteAllText($ReadyPath,($data|ConvertTo-Json),(New-Object System.Text.UTF8Encoding($false)))
    } catch { }
})
$form.Add_Shown({$timer.Start()})
try {[System.Windows.Forms.Application]::Run($form)} finally {$timer.Stop();$timer.Dispose();$form.Dispose()}
