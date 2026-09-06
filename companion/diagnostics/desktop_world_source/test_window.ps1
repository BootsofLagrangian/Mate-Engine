param([string]$Directory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System.Windows.Forms;
public sealed class MateGeometryTestForm:Form { protected override bool ShowWithoutActivation { get { return true; } } }
'@ -ReferencedAssemblies System.Windows.Forms
$form=New-Object MateGeometryTestForm
$form.StartPosition='Manual'
$form.SetBounds(120,120,360,240)
$form.Text='Mate geometry test fixture'
$form.Show()
@{pid=$PID; id=('{0}:{1:X}' -f $PID,$form.Handle.ToInt64())} | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $Directory 'fixture.json')
try {
    while (-not (Test-Path -LiteralPath (Join-Path $Directory 'fixture.stop'))) {
        $command=Join-Path $Directory 'fixture.command'
        if (Test-Path -LiteralPath $command) {
            $action=[IO.File]::ReadAllText($command).Trim()
            Remove-Item -LiteralPath $command
            switch ($action) {
                'move' { $form.SetBounds(200,180,360,240) }
                'minimize' { $form.WindowState='Minimized' }
                'hide' { $form.Hide() }
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
} finally { $form.Close(); $form.Dispose() }
