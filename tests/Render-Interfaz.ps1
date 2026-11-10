# Prueba de WinTurbo. Ejecútala con Windows PowerShell 5.1 sin permisos de administrador:
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Render-Interfaz.ps1
param([string]$OutDir, [string[]]$Pages = @('Panel', 'Ajustes', 'Bloatware', 'Inicio', 'Limpieza', 'Mantenimiento', 'Red', 'Update', 'Apps', 'Deshacer'))
$ErrorActionPreference = 'Continue'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PSScriptRoot) '.impeccable\review' }
. (Join-Path (Split-Path $PSScriptRoot) 'WinTurbo.ps1') -LibraryMode
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$win = Initialize-WinTurboGui
$win.WindowStartupLocation = 'Manual'
$win.Left = -32000; $win.Top = 0
$win.ShowActivated = $false
$win.ShowInTaskbar = $false
$win.Show()

function Pump([int]$Ms) {
    $end = (Get-Date).AddMilliseconds($Ms)
    while ((Get-Date) -lt $end) {
        $win.Dispatcher.Invoke([Action]{ }, 'Background')
        Invoke-GuiTick
        Start-Sleep -Milliseconds 100
        if ($script:GuiJobs.Count -eq 0 -and $Ms -le 1500) { break }
    }
    $win.Dispatcher.Invoke([Action]{ }, 'Background')
}
function Snap([string]$Name) {
    $win.UpdateLayout()
    $w = [int]$win.ActualWidth; $h = [int]$win.ActualHeight
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($win)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $OutDir "$Name.png")); $enc.Save($fs); $fs.Close()
    "captura: $Name ($w x $h)"
}

$win.Width = 1360; $win.Height = 860
foreach ($id in $Pages) {
    $script:Gui.NavButtons[$id].IsChecked = $true
    $wait = 1500
    while ($script:GuiJobs.Count -gt 0 -and $wait -lt 25000) { Pump 500; $wait += 500 }
    Pump 600
    Snap "desktop-$id"
}
# Portátil 1366x768 al 125 %: área útil ~1093 x 614 DIP
$win.Width = 1093; $win.Height = 614
foreach ($id in @('Panel', 'Ajustes', 'Update')) {
    $script:Gui.NavButtons[$id].IsChecked = $true
    $wait = 0
    while ($script:GuiJobs.Count -gt 0 -and $wait -lt 25000) { Pump 500; $wait += 500 }
    Pump 600
    Snap "laptop-$id"
}
# Estados: selección de ajuste, simulación activa y tarea en curso
$script:GuiSel = @{}; foreach ($i in (Get-PresetIds 'Gaming')) { $script:GuiSel[$i] = $true }
$script:GuiDetailId = 'HAGS'
$script:IsDryRun = $true
$win.Width = 1360; $win.Height = 860
$script:Gui.SimToggle.IsChecked = $true
$script:Gui.NavButtons['Panel'].IsChecked = $true
$script:Gui.NavButtons['Ajustes'].IsChecked = $true
Pump 800
Snap 'state-ajustes-sim'
Start-GuiJob -Title 'Aplicar preset Equilibrado (simulación)' -Vars @{ WT_Ids = (Get-PresetIds 'Equilibrado') } -Script 'Invoke-TweakSet -Ids $WT_Ids -Label ''Prueba'''
$n = 0; while ($script:GuiJobs.Count -gt 0 -and $n -lt 60) { Pump 500; $n++ }
Snap 'state-job-done'
$win.Close()
'Errores de PowerShell en la sesión:'
$Error | Select-Object -First 15 | ForEach-Object { ' - ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber }
