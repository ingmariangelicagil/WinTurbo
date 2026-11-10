# Prueba de WinTurbo. Ejecútala con Windows PowerShell 5.1 sin permisos de administrador:
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Escenarios.ps1
$ErrorActionPreference = 'Continue'
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Cond, [string]$Info = '') {
    if ($Cond) { $script:Pass++; Write-Output "  OK    $Name" } else { $script:Fail++; Write-Output "  FALLO $Name $Info" }
}
. (Join-Path (Split-Path $PSScriptRoot) 'WinTurbo.ps1') -LibraryMode
$tmp = Join-Path $env:TEMP ('wt-esc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
$script:BackupDir = $tmp
$script:LogFile = $null

Write-Output '== E1 Argumentos de relanzamiento'
$script:ScriptPath = 'C:\Ruta con espacios\WinTurbo.ps1'
$script:Bound = @{}
$a = Get-RelaunchArgumentString
Check 'GUI por defecto: -STA y sin -NoExit' ($a -match '-STA' -and $a -notmatch '-NoExit') $a
$script:Bound = @{ Preset = 'Gaming' }
Check 'Preset en consola: -NoExit' ((Get-RelaunchArgumentString) -match '-NoExit')
$script:Bound = @{ Preset = 'Basico'; Silent = [switch]$true }
Check 'Silencioso: sin -NoExit' ((Get-RelaunchArgumentString) -notmatch '-NoExit')
$script:Bound = @{ ConfigFile = 'C:\mis cosas\cfg.json' }
Check 'Ruta con espacios entre comillas' ((Get-RelaunchArgumentString) -match '-ConfigFile "C:\\mis cosas\\cfg.json"')
$script:Bound = @{ DisableUpdates = [switch]$true; KeepStore = [switch]$true }
$a = Get-RelaunchArgumentString
Check 'Bloqueo con Tienda conserva ambos switches' ($a -match '-DisableUpdates' -and $a -match '-KeepStore') $a

Write-Output '== E2 Selecciones del menú de consola'
Check 'Vacío' ((ConvertFrom-Selection -Text '' -Max 10).Count -eq 0)
Check 'Cero y fuera de rango' ((ConvertFrom-Selection -Text '0,11,99' -Max 10).Count -eq 0)
Check 'Rango invertido 5-3' ((ConvertFrom-Selection -Text '5-3' -Max 10) -join ',' -eq '5,4,3')
Check 'Duplicados y comas dobles' ((ConvertFrom-Selection -Text '1,,1, 2' -Max 10) -join ',' -eq '1,2')
Check 'Texto basura' ((ConvertFrom-Selection -Text 'abc;-' -Max 10).Count -eq 0)

Write-Output '== E3 Presets en distintos equipos'
$profiles = @(
    [pscustomobject]@{ N = 'Portátil Win11 8GB SSD'; Build = 26300; IsWin11 = $true; RamGB = 8; IsLaptop = $true; IsVM = $false; SystemDisk = 'SSD'; IsSSD = $true; IsHome = $true }
    [pscustomobject]@{ N = 'Sobremesa Win10 4GB HDD'; Build = 19045; IsWin11 = $false; RamGB = 4; IsLaptop = $false; IsVM = $false; SystemDisk = 'HDD'; IsSSD = $false; IsHome = $false }
    [pscustomobject]@{ N = 'Máquina virtual Win11'; Build = 22631; IsWin11 = $true; RamGB = 16; IsLaptop = $false; IsVM = $true; SystemDisk = 'Desconocido'; IsSSD = $false; IsHome = $false }
    [pscustomobject]@{ N = 'Win10 1809 antiguo'; Build = 17763; IsWin11 = $false; RamGB = 6; IsLaptop = $true; IsVM = $false; SystemDisk = 'HDD'; IsSSD = $false; IsHome = $true }
)
foreach ($p in $profiles) {
    $script:HW = $p
    $line = foreach ($pr in 'Basico', 'Equilibrado', 'Gaming', 'Maximo') {
        $ids = @(Get-PresetIds $pr)
        $skip = @($script:Tweaks | Where-Object { $ids -contains $_.Id -and $_.Condition -and -not (& $_.Condition) }).Count
        "$pr $($ids.Count - $skip)/$($ids.Count)"
    }
    Write-Output "  $($p.N): $($line -join ' · ')"
}
$script:HW = $profiles[1]
Check 'HDD 4GB incluye efectos visuales en Equilibrado' ((Get-PresetIds 'Equilibrado') -contains 'EfectosVisuales')
Check 'Básico nunca añade ajustes automáticos' (-not ((Get-PresetIds 'Basico') -contains 'EfectosVisuales'))
$script:HW = $profiles[2]
Check 'HAGS no aplica en máquina virtual' (-not (& (Get-Tweak 'HAGS').Condition))
$script:HW = $profiles[3]
Check 'Almacenamiento reservado no aplica en 1809' (-not (& (Get-Tweak 'AlmacenamientoReservado').Condition))
Check 'Menú clásico no aplica en Windows 10' (-not (& (Get-Tweak 'MenuClasico').Condition))

Write-Output '== E4 Registro: idempotencia y deshacer con todos los tipos'
$k = 'HKCU:\Software\WinTurboEscenarios'
Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue
New-Item $k -Force | Out-Null
New-ItemProperty $k -Name D -Value 5 -PropertyType DWord | Out-Null
New-ItemProperty $k -Name S -Value 'hola' -PropertyType String | Out-Null
New-ItemProperty $k -Name X -Value '%TEMP%\a' -PropertyType ExpandString | Out-Null
New-ItemProperty $k -Name M -Value @('uno', 'dos') -PropertyType MultiString | Out-Null
New-ItemProperty $k -Name B -Value ([byte[]](1, 2, 3)) -PropertyType Binary | Out-Null
New-ItemProperty $k -Name Q -Value ([int64]5000000000) -PropertyType QWord | Out-Null
$script:IsDryRun = $false
Start-Journal -Label 'E4'
Set-RegValue $k 'D' 0
Set-RegValue $k 'S' 'adios' 'String'
Set-RegValue $k 'X' 'nuevo' 'ExpandString'
Set-RegValue $k 'M' @('tres') 'MultiString'
Set-RegValue $k 'B' @(9) 'Binary'
Set-RegValue $k 'Q' ([int64]1) 'QWord'
Set-RegValue $k 'N' 0xffffffff
Set-RegValue "$k\Sub\Profunda" 'Z' 1
$j1 = $script:JournalPath
Check 'Diario con 8 cambios' ($script:Journal.Entries.Count -eq 8) "$($script:Journal.Entries.Count)"
Start-Journal -Label 'E4 repetido'
Set-RegValue $k 'D' 0
Set-RegValue $k 'N' 0xffffffff
Set-RegValue $k 'B' @(9) 'Binary'
Check 'Repetir lo ya aplicado no genera cambios' ($script:Journal.Entries.Count -eq 0) "$($script:Journal.Entries.Count)"
Invoke-UndoJournal -Path $j1 6>$null
$v = Get-Item $k
Check 'DWord restaurado' ($v.GetValue('D') -eq 5)
Check 'String restaurado' ($v.GetValue('S') -eq 'hola')
Check 'ExpandString restaurado sin expandir' ($v.GetValue('X', $null, 'DoNotExpandEnvironmentNames') -eq '%TEMP%\a' -and $v.GetValueKind('X') -eq 'ExpandString')
Check 'MultiString restaurado' ((@($v.GetValue('M')) -join '|') -eq 'uno|dos')
Check 'Binary restaurado' ((@($v.GetValue('B')) -join ',') -eq '1,2,3')
Check 'QWord restaurado' ($v.GetValue('Q') -eq 5000000000)
Check 'Valor nuevo eliminado' (-not ($v.GetValueNames() -contains 'N'))
Check 'Diario marcado como deshecho' (Test-Path ($j1 -replace '\.json$', '.deshecho.json'))
Remove-Item $k -Recurse -Force

Write-Output '== E5 Diarios dañados'
'{ esto no es json' | Set-Content (Join-Path $tmp 'respaldo-20990101-000000-000.json')
$threw = $false
try { Invoke-UndoJournal -Path (Join-Path $tmp 'respaldo-20990101-000000-000.json') 6>$null } catch { $threw = $true }
Check 'Deshacer un diario dañado lanza un error controlable' $threw
$js = Get-GuiJournals
Check 'La lista de respaldos tolera archivos dañados' (@($js | Where-Object { $_.Etiqueta -eq '(ilegible)' }).Count -eq 1)
Check 'Numeración correlativa #0001..' ((@($js | Sort-Object Numero)[0]).Numero -eq '#0001')

Write-Output '== E6 Script SYSTEM de bloqueo (simulado)'
$global:WTMock = New-Object System.Collections.ArrayList
$enfDir = Join-Path $tmp 'enf'; New-Item -ItemType Directory $enfDir | Out-Null
$enf = Join-Path $enfDir 'BloqueoWU.ps1'
Set-Content -Path $enf -Value $script:WUEnforcerScript -Encoding UTF8
$mocks = {
    function global:sc.exe { [void]$global:WTMock.Add("sc $($args -join ' ')"); $global:LASTEXITCODE = 0 }
    function global:Stop-Service { param($Name) [void]$global:WTMock.Add("stop $Name") }
    function global:Start-Service { param($Name) [void]$global:WTMock.Add("start $($Name -join ',')") }
    function global:Test-Path { param($Path) if ($Path -like 'HKLM:*Services*') { $Path -notmatch 'sedsvc' } else { [System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path) } }
    function global:Set-ItemProperty { param($Path, $Name, $Value) [void]$global:WTMock.Add("reg $(Split-Path $Path -Leaf) $Name=$Value") }
    function global:Get-Acl { throw 'sin acl en prueba' }
    function global:Get-ScheduledTask { param($TaskPath) if ($TaskPath -like '*UpdateOrchestrator*') { @([pscustomobject]@{ TaskPath = $TaskPath; TaskName = 'Schedule Scan'; State = $global:TaskState }, [pscustomobject]@{ TaskPath = $TaskPath; TaskName = 'USO_UxBroker'; State = $global:TaskState }) } }
    function global:Disable-ScheduledTask { param($TaskPath, $TaskName) [void]$global:WTMock.Add("disable $TaskName") }
    function global:Enable-ScheduledTask { param($TaskPath, $TaskName) [void]$global:WTMock.Add("enable $TaskName") }
    function global:Get-MpComputerStatus { [pscustomobject]@{ AntivirusSignatureAge = 3 } }
    function global:Update-MpSignature { param($UpdateSource) [void]$global:WTMock.Add("defender $UpdateSource") }
}
. $mocks
$global:TaskState = 'Ready'
& $enf -Mode Block
Check 'Block: wuauserv deshabilitado' ($global:WTMock -contains 'reg wuauserv Start=4')
Check 'Block: WaaSMedic deshabilitado' ($global:WTMock -contains 'reg WaaSMedicSvc Start=4')
Check 'Block: tareas desactivadas' ($global:WTMock -contains 'disable Schedule Scan')
Check 'Block: Defender actualiza por MMPC' ($global:WTMock -contains 'defender MMPC')
Check 'Block: omite servicios inexistentes' (-not ($global:WTMock -match 'sedsvc'))
$global:WTMock.Clear()
& $enf -Mode BlockStore
Check 'BlockStore: wuauserv en Manual' ($global:WTMock -contains 'reg wuauserv Start=3')
Check 'BlockStore: no detiene wuauserv (descargas de la Tienda)' (-not ($global:WTMock -contains 'stop wuauserv'))
Check 'BlockStore: UsoSvc deshabilitado' ($global:WTMock -contains 'reg UsoSvc Start=4')
$global:WTMock.Clear()
$global:TaskState = 'Disabled'
@{ Services = @{ wuauserv = @{ Start = 3; Delayed = 0 }; UsoSvc = @{ Start = 4; Delayed = 0 }; WaaSMedicSvc = @{ Start = 3; Delayed = 0 } }; Tasks = @('\Microsoft\Windows\UpdateOrchestrator\Schedule Scan') } |
    ConvertTo-Json -Depth 4 | Set-Content (Join-Path $enfDir 'wu-estado-original.json') -Encoding UTF8
& $enf -Mode Unblock
Check 'Unblock: original 4 se ignora y usa el valor por defecto (UsoSvc automático)' ($global:WTMock -contains 'reg UsoSvc Start=2')
Check 'Unblock: solo reactiva las tareas que estaban activas' (($global:WTMock -contains 'enable Schedule Scan') -and -not ($global:WTMock -contains 'enable USO_UxBroker'))
Check 'Unblock: arranca los servicios' ($global:WTMock -contains 'start UsoSvc,wuauserv')
foreach ($f in 'sc.exe', 'Stop-Service', 'Start-Service', 'Test-Path', 'Set-ItemProperty', 'Get-Acl', 'Get-ScheduledTask', 'Disable-ScheduledTask', 'Enable-ScheduledTask', 'Get-MpComputerStatus', 'Update-MpSignature') { Remove-Item -Path ("Function:\" + $f) -ErrorAction SilentlyContinue }

Write-Output '== E7 Estado de Windows Update en modo Tienda (simulado)'
function Get-ScheduledTask {
    param($TaskPath, $TaskName)
    if ($TaskName -eq $script:WUGuardTask) { return [pscustomobject]@{ State = 'Ready'; Actions = @([pscustomobject]@{ Arguments = '-File "x" -Mode BlockStore' }) } }
    if ($TaskPath) { return @([pscustomobject]@{ TaskName = 'Schedule Scan'; State = 'Disabled' }) }
}
$st = Get-WUBlockStatus
Check 'Detecta el modo Tienda' ($st.Modo -eq 'Tienda')
$wu = $st.Detalle | Where-Object { $_.Elemento -eq 'Servicio wuauserv' }
Check 'wuauserv en Manual cuenta como correcto en modo Tienda' ($wu.Bloqueado -eq ([int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv').Start -eq 3))
Remove-Item function:Get-ScheduledTask
$st2 = Get-WUBlockStatus
$tr = $st2.Detalle | Where-Object { $_.Elemento -like 'Tareas*' }
Check 'Sin permisos no afirma que las tareas estén bloqueadas' (-not $tr.Bloqueado) $tr.Detalle

Write-Output '== E8 Adaptadores de red reales'
$ad = @(Get-ActiveAdapters)
Write-Output "  Detectados: $(($ad | ForEach-Object { $_.Name }) -join ', ')"
Check 'Excluye adaptadores virtuales (Npcap, VPN, Hyper-V)' (-not ($ad | Where-Object { $_.InterfaceDescription -match 'Npcap|Loopback|Virtual' }))

Write-Output '== E9 Estado original de Windows Update tras WinUtil (simulado)'
$script:WUStatePath = Join-Path $tmp 'estado.json'
function Get-ItemProperty { param($Path, $Name) if ($Path -like '*Services*') { [pscustomobject]@{ Start = 4; DelayedAutostart = 0 } } }
Save-WUOriginalState
Remove-Item function:Get-ItemProperty
$saved = Get-Content $script:WUStatePath -Raw | ConvertFrom-Json
Check 'Un servicio ya deshabilitado se guarda con el valor por defecto' ($saved.Services.wuauserv.Start -eq 3 -and $saved.Services.UsoSvc.Start -eq 2)
Save-WUOriginalState
Check 'No se sobrescribe el estado original en un segundo bloqueo' ((Get-Content $script:WUStatePath -Raw | ConvertFrom-Json).Fecha -eq $saved.Fecha)

Write-Output '== E10 Simulación (DryRun) no escribe nada'
$script:IsDryRun = $true
$k2 = 'HKCU:\Software\WinTurboEscenariosDry'
Start-Journal -Label 'dry'
Set-RegValue $k2 'A' 1 6>$null
Check 'DryRun no crea la clave' (-not (Test-Path $k2))
Check 'DryRun no anota en el respaldo' ($script:Journal.Entries.Count -eq 0)

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "RESULTADO: $script:Pass correctas, $script:Fail fallidas"

