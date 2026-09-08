param([Parameter(Mandatory=$true)][string]$HelperPath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MateOwnedFixture {
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int z,uint flags);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int command);
}
'@
$directory=Join-Path ([IO.Path]::GetTempPath()) ('mate-event-probe-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($directory)|Out-Null
$localHelper=Join-Path $directory 'helper.ps1'
Copy-Item -LiteralPath $HelperPath -Destination $localHelper
$snapshotPath=Join-Path $directory 'snapshot.json'
$fixturePath=Join-Path $directory 'fixture.ps1'
$handlePath=Join-Path $directory 'handle.txt'
$stopFixture=Join-Path $directory 'fixture.stop'
@'
param($HandlePath,$StopPath)
Add-Type -AssemblyName System.Windows.Forms
$form=New-Object Windows.Forms.Form
$form.Text='Mate owned geometry fixture'
$form.FormBorderStyle='None';$form.StartPosition='Manual';$form.Location=New-Object Drawing.Point(200,160);$form.Size=New-Object Drawing.Size(220,160)
$timer=New-Object Windows.Forms.Timer;$timer.Interval=100
$timer.Add_Tick({if(Test-Path -LiteralPath $StopPath){$form.Close()}})
$form.Add_Shown({[IO.File]::WriteAllText($HandlePath,$form.Handle.ToInt64().ToString());$timer.Start()})
[Windows.Forms.Application]::Run($form)
'@ | Set-Content -LiteralPath $fixturePath -Encoding UTF8
$owner=New-Object Windows.Forms.Form
$owner.Text='Mate ignored owner fixture';$owner.FormBorderStyle='None';$owner.StartPosition='Manual';$owner.Location=New-Object Drawing.Point(40,40);$owner.Size=New-Object Drawing.Size(120,90);$owner.Show()
$helper=$null;$fixture=$null;$reads=0;$captures=@();$lastStamp=0
function Pump { [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10 }
function Snapshot {
 try {
  $parsed=[IO.File]::ReadAllText($snapshotPath)|ConvertFrom-Json
  if($parsed.timestamp_msec -ne $script:lastStamp){$script:lastStamp=$parsed.timestamp_msec;$script:captures+=,$parsed.timestamp_msec}
  return $parsed
 } catch {return $null}
}
function Period([int]$duration,[bool]$moveOwner) {
 $begin=[Environment]::TickCount;$i=0
 while([Environment]::TickCount-$begin -lt $duration) {
  if($moveOwner){[void][MateOwnedFixture]::SetWindowPos($owner.Handle,[IntPtr]::Zero,40+($i%40),40,0,0,0x15);$i++}
  $null=Snapshot;Pump
 }
}
try {
 $helper=Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$localHelper,'-OutputPath',$snapshotPath,'-OwnerPid',$PID,'-IntervalMsec',1000) -WindowStyle Hidden -PassThru
 $deadline=[Environment]::TickCount+10000
 while(!(Test-Path -LiteralPath $snapshotPath) -and [Environment]::TickCount -lt $deadline){Pump}
 if(!(Test-Path -LiteralPath $snapshotPath)){throw 'Helper did not publish'}
 $null=Snapshot
 Period 1200 $false
 $idleBefore=Snapshot;$helper.Refresh();$cpuBefore=$helper.TotalProcessorTime.TotalMilliseconds;$capBefore=$captures.Count
 Period 3000 $false
 $helper.Refresh();$idleCpu=$helper.TotalProcessorTime.TotalMilliseconds-$cpuBefore;$idleCaptures=$captures.Count-$capBefore
 $ownerBefore=Snapshot;$capBefore=$captures.Count
 Period 2000 $true
 $ownerAfter=Snapshot;$ownerCaptures=$captures.Count-$capBefore
 $fixture=Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$fixturePath,'-HandlePath',$handlePath,'-StopPath',$stopFixture) -WindowStyle Hidden -PassThru
 $deadline=[Environment]::TickCount+10000
 while(!(Test-Path -LiteralPath $handlePath) -and [Environment]::TickCount -lt $deadline){Pump}
 if(!(Test-Path -LiteralPath $handlePath)){throw 'Owned external fixture did not show'}
 $handle=[IntPtr]([long][IO.File]::ReadAllText($handlePath));$id=$fixture.Id.ToString()+':'+$handle.ToInt64().ToString('X')
 Period 300 $false
 $latencies=@();$matched=0
 foreach($i in 0..5){
  $x=240+$i*31;$y=170+$i*13
  $started=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  [void][MateOwnedFixture]::SetWindowPos($handle,[IntPtr]::Zero,$x,$y,0,0,0x15)
  $deadline=[Environment]::TickCount+1500;$found=$false
  while([Environment]::TickCount -lt $deadline){
   $s=Snapshot
   $record=@($s.windows|Where-Object {$_.id -eq $id})
   if($record.Count -eq 1 -and $record[0].x -eq $x -and $record[0].y -eq $y){$latencies+=([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$started);$found=$true;$matched++;break}
   Pump
  }
  if(!$found){$latencies+=-1}
  Period 70 $false
 }
 $capBefore=$captures.Count;$helper.Refresh();$burstCpuBefore=$helper.TotalProcessorTime.TotalMilliseconds
 $start=[Environment]::TickCount;$i=0
 while([Environment]::TickCount-$start -lt 2000){[void][MateOwnedFixture]::SetWindowPos($handle,[IntPtr]::Zero,500+($i%60),250,0,0,0x15);$i++;$null=Snapshot;Pump}
 $helper.Refresh();$burstCpu=$helper.TotalProcessorTime.TotalMilliseconds-$burstCpuBefore;$burstCaptures=$captures.Count-$capBefore
 $lifecycle=@()
 foreach($action in @('hide','show','destroy')){
  $started=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($action -eq 'destroy'){[IO.File]::WriteAllText($stopFixture,'stop')}
  else {[void][MateOwnedFixture]::ShowWindow($handle, $(if($action -eq 'hide'){0}else{8}))}
  $deadline=[Environment]::TickCount+1800;$found=$false
  while([Environment]::TickCount -lt $deadline){
   $s=Snapshot;$present=@($s.windows|Where-Object {$_.id -eq $id}).Count -eq 1
   if($present -eq ($action -eq 'show')){$found=$true;break};Pump
  }
  $lifecycle+=@{action=$action;matched=$found;latency_ms=([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$started)}
 }
 $end=Snapshot
 $gaps=@();for($i=1;$i -lt $captures.Count;$i++){$gaps+=($captures[$i]-$captures[$i-1])}
 $result=[ordered]@{scope='Owned WinForms windows only; native helper transport observations, not Mate render latency';helper_sha256=(Get-FileHash -LiteralPath $localHelper -Algorithm SHA256).Hash;hook_count=$end.event_hook_count;matched_moves=$matched;move_latency_ms=$latencies;lifecycle=$lifecycle;idle_seconds=3;idle_capture_count=$idleCaptures;idle_cpu_ms=$idleCpu;owner_motion_seconds=2;owner_motion_capture_count=$ownerCaptures;ignored_owner_events=$end.ignored_owner_events;external_burst_seconds=2;external_burst_capture_count=$burstCaptures;external_burst_cpu_ms=$burstCpu;minimum_observed_capture_gap_ms=($gaps|Measure-Object -Minimum).Minimum;capture_count=$captures.Count;event_count=$end.event_count}
 $checks=@{all_moves_observed=($matched -eq 6);all_lifecycle_observed=(@($lifecycle|Where-Object {!$_.matched}).Count -eq 0);capture_rate_bounded=($result.minimum_observed_capture_gap_ms -ge 124 -and $burstCaptures -le 17)}
 if($end.event_hook_count -gt 0){$checks['owner_motion_does_not_drive_capture']=($ownerCaptures -le 3 -and $end.ignored_owner_events -gt 0)}
 $result['checks']=$checks
 $json=$result|ConvertTo-Json -Depth 6
 [IO.File]::WriteAllText($OutputPath,$json)
 $json
 if(@($checks.Values|Where-Object {!$_}).Count -gt 0){throw "Owned window event verification failed"}
} finally {
 [IO.File]::WriteAllText($snapshotPath+'.stop','stop');[IO.File]::WriteAllText($stopFixture,'stop')
 $owner.Close();$owner.Dispose()
 foreach($child in @($helper,$fixture)){if($null -ne $child){if(!$child.WaitForExit(3000)){$child.Kill()};$child.Dispose()}}
 Remove-Item -LiteralPath $directory -Recurse -Force
}
