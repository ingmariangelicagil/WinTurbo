#Requires -Version 5.1
<#
.SYNOPSIS
    WinTurbo - Optimizador integral de Windows 10/11 (rendimiento, privacidad, limpieza y reparación).

.DESCRIPTION
    Inspirado en Chris Titus Tech WinUtil y en Sophia Script, Win11Debloat, Optimizer,
    privacy.sexy y O&O ShutUp10++. Mejoras clave respecto a WinUtil:
      * Detección de hardware (portátil/sobremesa, SSD/HDD, RAM, VM) que adapta los ajustes.
      * Respaldo propio de CADA cambio (registro, servicios, tareas, DNS, plan de energía)
        en un diario JSON con deshacer completo, además del punto de restauración.
      * Modo simulación (-DryRun): muestra lo que haría sin tocar nada.
      * Niveles de riesgo por ajuste (Seguro / Moderado / Avanzado) y presets adaptativos.
      * Estado actual de cada ajuste ([aplicado]) y medición antes/después
        (tiempo de arranque real, RAM, procesos, apps de inicio, espacio libre).
      * Gestor de programas de inicio, limpieza segura, reparación en el orden correcto
        (DISM -> SFC -> CHKDSK), benchmark de DNS, Windows Update y apps con winget.

.PARAMETER Preset
    Aplica un preset sin menú: Basico, Equilibrado, Gaming o Maximo.
.PARAMETER ConfigFile
    Aplica los ajustes listados en un JSON exportado desde el menú personalizado.
.PARAMETER DryRun
    Simulación: muestra los cambios sin aplicarlos.
.PARAMETER Silent
    No pide confirmaciones (útil con -Preset o -ConfigFile).
.PARAMETER Undo
    Abre directamente el menú para deshacer cambios.
.PARAMETER Report
    Muestra y guarda un informe del sistema y sale.
.PARAMETER NoRestorePoint
    No crea punto de restauración antes de aplicar.
.PARAMETER DisableUpdates
    Desactiva Windows Update de forma persistente (bloqueo como SYSTEM + tarea guardiana).
.PARAMETER KeepStore
    Con -DisableUpdates: deja el motor de descarga en Manual para que Microsoft Store siga funcionando.
.PARAMETER Console
    Abre el menú de texto en lugar de la interfaz gráfica.
.PARAMETER LibraryMode
    Uso interno de la interfaz: carga las funciones sin abrir ningún menú.
.PARAMETER EnableUpdates
    Reactiva Windows Update y deshace bloqueos de WinTurbo, WinUtil y herramientas similares.

.EXAMPLE
    .\WinTurbo.ps1
.EXAMPLE
    .\WinTurbo.ps1 -Preset Equilibrado -Silent
.EXAMPLE
    .\WinTurbo.ps1 -Preset Gaming -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('Basico', 'Equilibrado', 'Gaming', 'Maximo')]
    [string]$Preset,
    [string]$ConfigFile,
    [switch]$DryRun,
    [switch]$Silent,
    [switch]$Undo,
    [switch]$Report,
    [switch]$NoRestorePoint,
    [switch]$DisableUpdates,
    [switch]$KeepStore,
    [switch]$EnableUpdates,
    [switch]$Console,
    [switch]$LibraryMode
)

$script:Version    = '1.0.0'
$script:ScriptPath = $PSCommandPath
$script:Bound      = @{} + $PSBoundParameters
$script:DataDir    = Join-Path $env:ProgramData 'WinTurbo'
$script:BackupDir  = Join-Path $script:DataDir 'Respaldos'
$script:LogDir     = Join-Path $script:DataDir 'Logs'
$script:IsDryRun   = [bool]$DryRun
$ProgressPreference = 'Continue'

#region ===================== Arranque: elevación y edición de PowerShell =====================

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RelaunchArgumentString {
    # -STA: WPF necesita un hilo de apartamento único.
    $parts = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass')
    # Sin -NoExit la ventana de consola elevada se cerraría al terminar y no se podría leer el resultado.
    # En modo interfaz gráfica no hace falta: el resultado se ve en la ventana.
    $actionKeys = @('Preset', 'ConfigFile', 'Undo', 'Report', 'DisableUpdates', 'EnableUpdates', 'Console')
    $isConsoleRun = @($script:Bound.Keys | Where-Object { $actionKeys -contains $_ }).Count -gt 0
    if ($isConsoleRun -and -not $script:Bound.ContainsKey('Silent')) { $parts += '-NoExit' }
    $parts += @('-File', ('"{0}"' -f $script:ScriptPath))
    foreach ($key in $script:Bound.Keys) {
        $val = $script:Bound[$key]
        if ($val -is [System.Management.Automation.SwitchParameter]) {
            if ($val.IsPresent) { $parts += "-$key" }
        } else {
            $parts += "-$key"
            $parts += ('"{0}"' -f $val)
        }
    }
    return ($parts -join ' ')
}

# Se necesita Windows PowerShell 5.1 (Checkpoint-Computer y módulos de Appx) y permisos de administrador.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host "PowerShell está en modo '$($ExecutionContext.SessionState.LanguageMode)' (AppLocker/WDAC o directiva de la empresa)." -ForegroundColor Red
    Write-Host 'WinTurbo necesita FullLanguage para modificar el sistema de forma segura. Pide al administrador una excepción.' -ForegroundColor Red
    return
}

# Un PowerShell de 32 bits en Windows de 64 bits escribiría el registro en WOW6432Node y los ajustes no tendrían efecto.
$script:Is32On64 = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess

if (-not $LibraryMode -and ($PSVersionTable.PSEdition -eq 'Core' -or -not (Test-IsAdmin) -or $script:Is32On64)) {
    if (-not $script:ScriptPath) {
        Write-Host 'Guarda este script como WinTurbo.ps1 y ejecútalo desde Windows PowerShell (64 bits) como Administrador.' -ForegroundColor Red
        return
    }
    # Sysnative es la única ruta que llega al PowerShell de 64 bits desde un proceso de 32 bits.
    $psExe = if ($script:Is32On64) { "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    $startArgs = @{
        FilePath     = $psExe
        ArgumentList = (Get-RelaunchArgumentString)
    }
    if (-not (Test-IsAdmin)) { $startArgs['Verb'] = 'RunAs' }
    try {
        Start-Process @startArgs
    } catch {
        Write-Host 'Se necesitan permisos de administrador para continuar.' -ForegroundColor Red
    }
    return
}

#endregion

#region ===================== Utilidades generales =====================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'STEP')]
        [string]$Level = 'INFO'
    )
    $style = @{
        INFO  = @('   ', 'Gray')
        OK    = @(' + ', 'Green')
        WARN  = @(' ! ', 'Yellow')
        ERROR = @(' x ', 'Red')
        DRY   = @(' ~ ', 'Cyan')
        STEP  = @(' > ', 'White')
    }[$Level]
    $prefix = $style[0]
    if ($Level -eq 'DRY') { $prefix = ' [simulación] ' }
    Write-Host ($prefix + $Message) -ForegroundColor $style[1]
    if ($script:LogFile) {
        try {
            Add-Content -Path $script:LogFile -Value ('{0} [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message) -Encoding UTF8 -ErrorAction Stop
        } catch {
            # Un fallo puntual (antivirus, archivo bloqueado) no debe romper la acción ni apagar el registro:
            # esa línea se pierde y las siguientes se vuelven a intentar.
        }
    }
}

function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * $Text.Length)) -ForegroundColor DarkCyan
}

function Confirm-Action {
    param([string]$Question)
    if ($Silent) { return $true }
    $answer = Read-Host ("  $Question (S/N)")
    return ($answer -match '^[sSyY]')
}

function Wait-Enter {
    if (-not $Silent) { [void](Read-Host '  Pulsa Enter para continuar') }
}

function ConvertFrom-Selection {
    # Convierte "1,3,5-7" en una lista de números válidos entre 1 y $Max.
    param([string]$Text, [int]$Max)
    $result = New-Object System.Collections.Generic.List[int]
    foreach ($part in ($Text -split '[,\s]+')) {
        if ($part -match '^(\d+)-(\d+)$') {
            foreach ($n in ([int]$Matches[1])..([int]$Matches[2])) {
                if ($n -ge 1 -and $n -le $Max -and -not $result.Contains($n)) { $result.Add($n) }
            }
        } elseif ($part -match '^\d+$') {
            $n = [int]$part
            if ($n -ge 1 -and $n -le $Max -and -not $result.Contains($n)) { $result.Add($n) }
        }
    }
    return , $result.ToArray()
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    if (-not $sum) { return 0 }
    return [math]::Round($sum / 1MB, 1)
}

function Get-FreeSpaceGB {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    return [math]::Round($disk.FreeSpace / 1GB, 2)
}

function Test-InteractiveUserMatch {
    # Si el administrador que eleva no es el usuario que tiene la sesión abierta,
    # los ajustes de HKCU se aplicarían a la cuenta equivocada.
    try {
        $session = (Get-Process -Id $PID).SessionId
        $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$session" | Select-Object -First 1
        if (-not $explorer) { return $true }
        $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
        return ($owner.User -eq $env:USERNAME)
    } catch {
        return $true
    }
}

#endregion

#region ===================== Detección de hardware y salud del sistema =====================

function Get-HardwareProfile {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cs  = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpu = Get-CimInstance Win32_VideoController |
           Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Mirror|Indirect' } |
           Select-Object -ExpandProperty Name
    $cv  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $laptopChassis = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $isLaptop = $hasBattery -or [bool]($chassis | Where-Object { $laptopChassis -contains $_ })

    $media = 'Desconocido'
    try {
        $diskNumber = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq [string]$diskNumber } | Select-Object -First 1
        if ($pd) {
            $media = [string]$pd.MediaType
            if ($pd.BusType -eq 'NVMe') { $media = 'SSD' }
        }
    } catch { }

    $build = [int]$os.BuildNumber
    $isVM = ($cs.Model -match 'Virtual|VMware|KVM|QEMU|VirtualBox|Hyper-V') -or
            ($cs.Manufacturer -match 'QEMU|VMware|innotek|Xen|Parallels')

    return [pscustomobject]@{
        OSName     = $os.Caption
        Version    = $cv.DisplayVersion
        Build      = $build
        IsWin11    = ($build -ge 22000)
        Edition    = $cv.EditionID
        IsHome     = ($cv.EditionID -match 'Core')
        CPU        = ([string]$cpu.Name).Trim()
        Cores      = $cpu.NumberOfCores
        Threads    = $cpu.NumberOfLogicalProcessors
        # RAM física instalada (TotalPhysicalMemory descuenta la reservada por la gráfica integrada).
        RamGB      = $(
            $installed = (Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum).Sum
            if (-not $installed) { $installed = $cs.TotalPhysicalMemory }
            [math]::Round($installed / 1GB, 1)
        )
        GPU        = ($gpu -join ', ')
        IsLaptop   = $isLaptop
        SystemDisk = $media
        IsSSD      = ($media -eq 'SSD')
        IsVM       = $isVM
    }
}

function Get-StartupItems {
    $items = New-Object System.Collections.ArrayList
    $sources = @(
        @{ Origen = 'Usuario';       Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';
           Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
        @{ Origen = 'Equipo';        Run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';
           Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
        @{ Origen = 'Equipo (32b)';  Run = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';
           Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
    )
    foreach ($src in $sources) {
        if (-not (Test-Path -LiteralPath $src.Run)) { continue }
        $key = Get-Item -LiteralPath $src.Run
        $approved = $null
        if (Test-Path -LiteralPath $src.Approved) { $approved = Get-Item -LiteralPath $src.Approved }
        foreach ($name in $key.GetValueNames()) {
            if ([string]::IsNullOrEmpty($name)) { continue }
            $enabled = $true
            if ($approved -and ($approved.GetValueNames() -contains $name)) {
                $bytes = $approved.GetValue($name)
                if ($bytes -and ($bytes[0] -band 1)) { $enabled = $false }
            }
            [void]$items.Add([pscustomobject]@{
                Nombre   = $name
                Origen   = $src.Origen
                Comando  = [string]$key.GetValue($name)
                Enabled  = $enabled
                Approved = $src.Approved
            })
        }
    }
    $folders = @(
        @{ Origen = 'Carpeta usuario'; Path = [Environment]::GetFolderPath('Startup');
           Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' },
        @{ Origen = 'Carpeta común';   Path = [Environment]::GetFolderPath('CommonStartup');
           Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    )
    foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path -LiteralPath $f.Path)) { continue }
        $approved = $null
        if (Test-Path -LiteralPath $f.Approved) { $approved = Get-Item -LiteralPath $f.Approved }
        foreach ($file in (Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
            $enabled = $true
            if ($approved -and ($approved.GetValueNames() -contains $file.Name)) {
                $bytes = $approved.GetValue($file.Name)
                if ($bytes -and ($bytes[0] -band 1)) { $enabled = $false }
            }
            [void]$items.Add([pscustomobject]@{
                Nombre   = $file.Name
                Origen   = $f.Origen
                Comando  = $file.FullName
                Enabled  = $enabled
                Approved = $f.Approved
            })
        }
    }
    return $items
}

function Get-LastBootTimeMs {
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
        $xml = [xml]$ev.ToXml()
        $node = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }
        if ($node) { return [int]$node.'#text' }
    } catch { }
    return $null
}

function Get-HealthSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem
    $ramPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
    $uptime = (Get-Date) - $os.LastBootUpTime
    return [pscustomobject]@{
        Fecha            = (Get-Date).ToString('s')
        ArranqueMs       = Get-LastBootTimeMs
        Procesos         = @(Get-Process).Count
        ServiciosActivos = @(Get-Service | Where-Object { $_.Status -eq 'Running' }).Count
        RamUsadaPct      = $ramPct
        AppsInicio       = @(Get-StartupItems | Where-Object { $_.Enabled }).Count
        TempMB           = (Get-FolderSizeMB $env:TEMP) + (Get-FolderSizeMB "$env:SystemRoot\Temp")
        LibreSistemaGB   = Get-FreeSpaceGB
        HorasEncendido   = [math]::Round($uptime.TotalHours, 1)
    }
}

function Show-SnapshotComparison {
    param($Before, $After, [string]$BeforeLabel = 'Antes', [string]$AfterLabel = 'Ahora')
    $metrics = @(
        @{ Key = 'ArranqueMs';       Label = 'Tiempo de arranque (ms)';  HigherIsBetter = $false },
        @{ Key = 'Procesos';         Label = 'Procesos en ejecución';    HigherIsBetter = $false },
        @{ Key = 'ServiciosActivos'; Label = 'Servicios activos';        HigherIsBetter = $false },
        @{ Key = 'RamUsadaPct';      Label = 'RAM usada (%)';            HigherIsBetter = $false },
        @{ Key = 'AppsInicio';       Label = 'Apps de inicio activas';   HigherIsBetter = $false },
        @{ Key = 'TempMB';           Label = 'Archivos temporales (MB)'; HigherIsBetter = $false },
        @{ Key = 'LibreSistemaGB';   Label = 'Espacio libre (GB)';       HigherIsBetter = $true }
    )
    Write-Host ''
    Write-Host ('  {0,-28} {1,12} {2,12}' -f 'Métrica', $BeforeLabel, $AfterLabel) -ForegroundColor White
    foreach ($m in $metrics) {
        $b = $Before.($m.Key)
        $a = $After.($m.Key)
        $color = 'Gray'
        if ($null -ne $a -and $null -ne $b -and $a -ne $b) {
            $better = if ($m.HigherIsBetter) { $a -gt $b } else { $a -lt $b }
            $color = if ($better) { 'Green' } else { 'Yellow' }
        }
        $bt = if ($null -eq $b) { 'n/d' } else { [string]$b }
        $at = if ($null -eq $a) { 'n/d' } else { [string]$a }
        Write-Host ('  {0,-28} {1,12} {2,12}' -f $m.Label, $bt, $at) -ForegroundColor $color
    }
    Write-Host '  (El tiempo de arranque se actualiza tras reiniciar.)' -ForegroundColor DarkGray
}

function Save-BaselineIfMissing {
    $path = Join-Path $script:DataDir 'linea-base.json'
    if (-not (Test-Path $path)) {
        Get-HealthSnapshot | ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
        Write-Log "Línea base guardada para comparar más adelante: $path"
    }
}

#endregion

#region ===================== Diario de cambios (respaldo y deshacer) =====================

function Start-Journal {
    param([string]$Label)
    New-Item -ItemType Directory -Force -Path $script:BackupDir | Out-Null
    $script:Journal = [pscustomobject]@{
        Label    = $Label
        Created  = (Get-Date).ToString('s')
        Computer = $env:COMPUTERNAME
        User     = $env:USERNAME
        Entries  = New-Object System.Collections.ArrayList
    }
    $script:JournalKeys = @{}
    $script:JournalPath = Join-Path $script:BackupDir ('respaldo-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}

function Save-Journal {
    if ($script:Journal -and $script:Journal.Entries.Count -gt 0) {
        $script:Journal | ConvertTo-Json -Depth 6 | Set-Content -Path $script:JournalPath -Encoding UTF8
    }
}

function Add-JournalEntry {
    param([hashtable]$Entry, [string]$Key)
    if ($script:IsDryRun -or -not $script:Journal) { return }
    if ($Key) {
        if ($script:JournalKeys.ContainsKey($Key)) { return }   # se conserva el valor ORIGINAL
        $script:JournalKeys[$Key] = $true
    }
    [void]$script:Journal.Entries.Add([pscustomobject]$Entry)
    Save-Journal
}

function Register-RegistryOriginal {
    param([string]$Path, [string]$Name)
    $existed = $false; $old = $null; $oldType = $null
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path
        if ($item.GetValueNames() -contains $Name) {
            $existed = $true
            $old = $item.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            $oldType = $item.GetValueKind($Name).ToString()
            if ($old -is [byte[]]) { $old = [int[]]$old }
        }
    }
    Add-JournalEntry -Key "REG|$Path|$Name" -Entry @{ Type = 'Reg'; Path = $Path; Name = $Name; Existed = $existed; Value = $old; ValueType = $oldType }
}

function Test-RegValueEqual {
    # Compara valores de registro por su contenido real. Un DWORD 0xffffffff puede llegar como -1 (Int32)
    # o como 4294967295 (Int64) según cómo se escriba el literal: se comparan los 32 bits.
    param($Current, $Desired, [string]$Type)
    switch ($Type) {
        'Binary'      { return ((@($Current) -join ',') -eq (@($Desired) -join ',')) }
        'MultiString' { return ((@($Current) -join "`n") -eq (@($Desired) -join "`n")) }
        'DWord' {
            try {
                $a = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int64]$Current), 0)
                $b = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int64]$Desired), 0)
                return ($a -eq $b)
            } catch { return ([string]$Current -eq [string]$Desired) }
        }
        'QWord' { try { return ([int64]$Current -eq [int64]$Desired) } catch { return $false } }
        default { return ([string]$Current -eq [string]$Desired) }
    }
}

function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    # Idempotente: si el valor ya es el deseado no se escribe ni se anota en el respaldo.
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path
        if ($item.GetValueNames() -contains $Name -and $item.GetValueKind($Name).ToString() -eq $Type) {
            $cur = $item.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            if (Test-RegValueEqual -Current $cur -Desired $Value -Type $Type) { return }
        }
    }
    if ($script:IsDryRun) { Write-Log "Registro: $Path\$Name = $Value ($Type)" DRY; return }
    Register-RegistryOriginal -Path $Path -Name $Name
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Type -eq 'Binary') { $Value = [byte[]]$Value }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
}

function Remove-RegValue {
    param([string]$Path, [string]$Name)
    if ($script:IsDryRun) { Write-Log "Registro: eliminar $Path\$Name" DRY; return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Register-RegistryOriginal -Path $Path -Name $Name
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
}

$script:ScStart = @{ 'Automatic' = 'auto'; 'AutomaticDelayedStart' = 'delayed-auto'; 'Manual' = 'demand'; 'Disabled' = 'disabled'; 'Boot' = 'boot'; 'System' = 'system' }

function Get-ServiceStartMode {
    param([string]$Name)
    $reg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -ErrorAction SilentlyContinue
    if (-not $reg) { return $null }
    switch ([int]$reg.Start) {
        0 { return 'Boot' }
        1 { return 'System' }
        2 { if ($reg.DelayedAutostart -eq 1) { return 'AutomaticDelayedStart' } else { return 'Automatic' } }
        3 { return 'Manual' }
        4 { return 'Disabled' }
    }
    return $null
}

function Set-ServiceStartup {
    param([string]$Name, [string]$StartupType)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Log "Servicio '$Name' no existe en este equipo; se omite."; return }
    $current = Get-ServiceStartMode -Name $Name
    if ($current -eq $StartupType) { return }
    if ($script:IsDryRun) { Write-Log "Servicio: $Name $current -> $StartupType" DRY; return }
    Add-JournalEntry -Key "SVC|$Name" -Entry @{ Type = 'Svc'; Name = $Name; StartupType = $current }
    $out = & sc.exe config $Name start= $script:ScStart[$StartupType] 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sc.exe no pudo cambiar '$Name' ($($out -join ' '))" }
    if ($StartupType -eq 'Disabled') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
}

function Disable-TaskTracked {
    param([string]$FullName)
    $idx = $FullName.LastIndexOf('\')
    $taskPath = $FullName.Substring(0, $idx + 1)
    $taskName = $FullName.Substring($idx + 1)
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task -or $task.State -eq 'Disabled') { return }
    if ($script:IsDryRun) { Write-Log "Tarea programada: desactivar $FullName" DRY; return }
    Add-JournalEntry -Key "TASK|$FullName" -Entry @{ Type = 'Task'; TaskPath = $taskPath; TaskName = $taskName }
    Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
}

function Get-ActiveSchemeGuid {
    $out = (powercfg /getactivescheme) | Out-String
    if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1] }
    return $null
}

function Set-PowerPlan {
    param([ValidateSet('High', 'Ultimate')][string]$Mode)
    $guidRegex = '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
    $base = if ($Mode -eq 'Ultimate') { 'e9a42b02-d5df-448d-aa00-03f14749eb61' } else { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
    if ($script:IsDryRun) { Write-Log "Plan de energía: activar $Mode" DRY; return }
    $original = Get-ActiveSchemeGuid
    if ($original) { Add-JournalEntry -Key 'POWER' -Entry @{ Type = 'Power'; Guid = $original } }

    & powercfg /setactive $base 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { return }

    # El plan está oculto: se duplica una sola vez y se recuerda su GUID para no crear copias en cada ejecución.
    $stateKey = 'HKLM:\SOFTWARE\WinTurbo'
    $valueName = "Plan$Mode"
    $stored = (Get-ItemProperty -Path $stateKey -Name $valueName -ErrorAction SilentlyContinue).$valueName
    $list = (powercfg /list) | Out-String
    if (-not $stored -or $list -notmatch [regex]::Escape($stored)) {
        $dup = (powercfg /duplicatescheme $base) | Out-String
        if ($dup -notmatch $guidRegex) { throw 'Este equipo no permite ese plan de energía (Modern Standby).' }
        $stored = $Matches[1]
        if (-not (Test-Path $stateKey)) { New-Item -Path $stateKey -Force | Out-Null }
        Set-ItemProperty -Path $stateKey -Name $valueName -Value $stored
    }
    & powercfg /setactive $stored 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'powercfg no pudo activar el plan.' }
}

#endregion

#region ===================== Catálogo de ajustes =====================

function RegItem {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    return @{ Path = $Path; Name = $Name; Value = $Value; Type = $Type }
}

# Presets: B = Básico, E = Equilibrado, G = Gaming, M = Máximo
# Riesgo: Seguro / Moderado / Avanzado
$script:Categories = @('Privacidad', 'Rendimiento', 'Juegos', 'Energía', 'Servicios y sistema', 'Interfaz', 'Navegador Edge')

$script:Tweaks = @(
    # ------------------------------ Privacidad ------------------------------
    @{
        Id = 'Telemetria'; Category = 'Privacidad'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M')
        Name = 'Telemetría y diagnósticos - Desactivar'
        Description = 'Reduce el envío de datos a Microsoft: política de telemetría, ID de publicidad, experiencias personalizadas, recogida de escritura, servicio DiagTrack y tareas de recopilación (CEIP, Appraiser).'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
            RegItem 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
            RegItem 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
            RegItem 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
            RegItem 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
            RegItem 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0
        )
        Services = @(
            @{ Name = 'DiagTrack'; Startup = 'Disabled' }
        )
        Tasks = @(
            '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
            '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
            '\Microsoft\Windows\Feedback\Siuf\DmClient'
            '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
        )
        Script = {
            [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
            [Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1', 'Machine')
        }
        UndoScript = {
            [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', $null, 'Machine')
            [Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', $null, 'Machine')
        }
    }
    @{
        Id = 'Actividad'; Category = 'Privacidad'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M')
        Name = 'Historial de actividad - Desactivar'
        Description = 'Impide que Windows registre y suba el historial de aplicaciones y documentos abiertos.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
        )
    }
    @{
        Id = 'Publicidad'; Category = 'Privacidad'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M'); Explorer = $true
        Name = 'Anuncios, sugerencias y apps promocionadas - Desactivar'
        Description = 'Evita la instalación silenciosa de apps patrocinadas, sugerencias en Inicio/Configuración, consejos en la pantalla de bloqueo y el aviso "Terminemos de configurar el dispositivo".'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
        )
    }
    @{
        Id = 'WPBT'; Category = 'Privacidad'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M')
        Name = 'Software del fabricante desde firmware (WPBT) - Bloquear'
        Description = 'Impide que la BIOS/UEFI inyecte programas del fabricante en Windows en cada arranque.'
        Registry = @(
            RegItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1
        )
    }
    @{
        Id = 'Metadatos'; Category = 'Privacidad'; Risk = 'Seguro'; Presets = @('E', 'G', 'M')
        Name = 'Apps complementarias de dispositivos - No instalar automáticamente'
        Description = 'Evita que Windows descargue apps y metadatos de fabricantes al conectar periféricos.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
        )
    }
    @{
        Id = 'BingInicio'; Category = 'Privacidad'; Risk = 'Seguro'; Presets = @('E', 'G', 'M'); Explorer = $true
        Name = 'Búsqueda web (Bing) en el menú Inicio - Desactivar'
        Description = 'La búsqueda de Inicio solo busca en el equipo: más rápida y sin enviar lo que escribes.'
        Registry = @(
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
            RegItem 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
        )
    }
    @{
        Id = 'CopilotRecall'; Category = 'Privacidad'; Risk = 'Moderado'; Presets = @('E', 'G', 'M'); Explorer = $true
        Name = 'Copilot y Recall (IA de Windows) - Desactivar'
        Description = 'Desactiva Copilot de Windows y las capturas de Recall mediante políticas. No desinstala apps (para eso usa el módulo de bloatware).'
        Registry = @(
            RegItem 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
        )
    }
    @{
        Id = 'Ubicacion'; Category = 'Privacidad'; Risk = 'Moderado'; Presets = @('G', 'M')
        Name = 'Rastreo de ubicación - Desactivar'
        Description = 'Bloquea la ubicación para todas las apps. Ojo: la zona horaria automática y Mapas dejarán de detectarte.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' 'SensorPermissionState' 0
            RegItem 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled' 0
        )
        Services = @(
            @{ Name = 'lfsvc'; Startup = 'Disabled' }
        )
    }
    @{
        Id = 'InformesError'; Category = 'Privacidad'; Risk = 'Moderado'; Presets = @('M')
        Name = 'Informe de errores de Windows - Desactivar'
        Description = 'No envía informes de bloqueos a Microsoft y deja de acumular volcados en ProgramData.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
        )
        Services = @(
            @{ Name = 'WerSvc'; Startup = 'Disabled' }
        )
    }

    # ------------------------------ Rendimiento ------------------------------
    @{
        Id = 'RetrasoInicio'; Category = 'Rendimiento'; Risk = 'Seguro'; Presets = @('E', 'G', 'M')
        Name = 'Retraso artificial de apps de inicio - Eliminar'
        Description = 'Windows espera unos segundos antes de lanzar las apps de inicio; esto lo elimina para que el escritorio esté listo antes (recomendado con SSD).'
        Registry = @(
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'WaitForIdleState' 0
        )
    }
    @{
        Id = 'AnimacionesLigeras'; Category = 'Rendimiento'; Risk = 'Seguro'; Presets = @('E'); Explorer = $true
        Name = 'Menús y animaciones más rápidos'
        Description = 'Reduce la espera de los menús (400 a 100 ms) y quita las animaciones de minimizar y de la barra de tareas, manteniendo el aspecto de Windows.'
        Registry = @(
            RegItem 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '100' 'String'
            RegItem 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
        )
    }
    @{
        Id = 'EfectosVisuales'; Category = 'Rendimiento'; Risk = 'Moderado'; Presets = @('M'); Explorer = $true
        AutoInclude = { $script:HW.RamGB -lt 8 }
        Name = 'Efectos visuales - Máximo rendimiento'
        Description = 'Desactiva transparencias, sombras, animaciones y Aero Peek. Útil en equipos con poca RAM o GPU integrada antigua (se incluye automáticamente con menos de 8 GB). Requiere cerrar sesión.'
        Registry = @(
            RegItem 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String'
            RegItem 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '100' 'String'
            RegItem 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
            RegItem 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' @(144, 18, 3, 128, 16, 0, 0, 0) 'Binary'
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
            RegItem 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
        )
    }
    @{
        Id = 'AppsSegundoPlano'; Category = 'Rendimiento'; Risk = 'Moderado'; Presets = @('G', 'M')
        AutoInclude = { $script:HW.RamGB -lt 8 }
        Name = 'Apps de la Tienda en segundo plano - Desactivar'
        Description = 'Las apps UWP no se ejecutan en segundo plano. Ahorra RAM y CPU; algunas (Correo, Teléfono) solo notificarán estando abiertas.'
        Registry = @(
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
        )
    }
    @{
        Id = 'NTFSUltimoAcceso'; Category = 'Rendimiento'; Risk = 'Seguro'; Presets = @('E', 'G', 'M')
        Name = 'NTFS: no actualizar la fecha de último acceso'
        Description = 'Evita una escritura en disco cada vez que se lee un archivo. Mejora la E/S, sobre todo en HDD.'
        Script     = { & fsutil.exe behavior set disablelastaccess 1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'fsutil falló' } }
        UndoScript = { & fsutil.exe behavior set disablelastaccess 2 | Out-Null }
    }
    @{
        Id = 'SensorAlmacenamiento'; Category = 'Rendimiento'; Risk = 'Seguro'; Presets = @('E', 'G', 'M')
        Name = 'Sensor de almacenamiento semanal - Activar'
        Description = 'Mantenimiento automático: Windows borra temporales y vacía la papelera antigua cada semana, sin programas de terceros.'
        Registry = @(
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '04' 1
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '2048' 7
        )
    }
    @{
        Id = 'Widgets'; Category = 'Rendimiento'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M'); Explorer = $true
        Name = 'Widgets / Noticias e intereses - Desactivar'
        Description = 'Quita el panel de noticias y su proceso WebView en segundo plano.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
        )
    }
    @{
        Id = 'OptimizacionEntrega'; Category = 'Rendimiento'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M')
        Name = 'Compartir actualizaciones P2P (Optimización de distribución) - Desactivar'
        Description = 'Windows deja de usar tu conexión para subir actualizaciones a otros equipos de Internet.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
        )
    }

    # ------------------------------ Juegos ------------------------------
    @{
        Id = 'GameDVR'; Category = 'Juegos'; Risk = 'Seguro'; Presets = @('E', 'G', 'M')
        Name = 'Grabación en segundo plano (Game DVR) - Desactivar y Modo Juego - Activar'
        Description = 'La captura continua de Game Bar consume GPU y disco. El Modo Juego prioriza el juego en primer plano.'
        Registry = @(
            RegItem 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
            RegItem 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
            RegItem 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
        )
    }
    @{
        Id = 'HAGS'; Category = 'Juegos'; Risk = 'Moderado'; Presets = @('G'); Reboot = $true
        Condition = { $script:HW.Build -ge 19041 -and -not $script:HW.IsVM }; ConditionText = 'requiere Windows 10 2004+ y equipo físico'
        Name = 'Programación de GPU acelerada por hardware (HAGS) - Activar'
        Description = 'Reduce latencia y uso de CPU con GPU y drivers compatibles (NVIDIA 10xx+, AMD RX 5000+, Intel Arc). Requiere reiniciar.'
        Registry = @(
            RegItem 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
        )
    }
    @{
        Id = 'PrioridadJuegos'; Category = 'Juegos'; Risk = 'Moderado'; Presets = @('G', 'M'); Reboot = $true
        Name = 'Planificador multimedia (MMCSS) - Prioridad a juegos'
        Description = 'Reserva menos CPU a tareas de fondo (20% a 10%) y da prioridad alta de GPU/CPU a los juegos registrados en MMCSS.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'String'
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'SFIO Priority' 'High' 'String'
        )
    }
    @{
        Id = 'LimiteRed'; Category = 'Juegos'; Risk = 'Avanzado'; Presets = @('G'); Reboot = $true
        Name = 'Limitación de red durante multimedia - Quitar'
        Description = 'Windows limita el tráfico de red mientras reproduce multimedia. Quitarlo puede reducir picos de ping en juegos online.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xffffffff
        )
    }
    @{
        Id = 'AceleracionRaton'; Category = 'Juegos'; Risk = 'Seguro'; Presets = @('G')
        Name = 'Aceleración del ratón ("Mejorar precisión del puntero") - Desactivar'
        Description = 'Movimiento del ratón 1:1, más predecible para apuntar en juegos. Requiere cerrar sesión.'
        Registry = @(
            RegItem 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
            RegItem 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
            RegItem 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
        )
    }
    @{
        Id = 'TeclasEspeciales'; Category = 'Juegos'; Risk = 'Seguro'; Presets = @('G', 'M')
        Name = 'Atajo de Teclas especiales (5x Mayús) - Desactivar'
        Description = 'Evita que pulsar Mayús 5 veces saque al escritorio en mitad de una partida.'
        Registry = @(
            RegItem 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
        )
    }

    # ------------------------------ Energía ------------------------------
    @{
        Id = 'PlanAlto'; Category = 'Energía'; Risk = 'Seguro'; Presets = @('E')
        Condition = { -not $script:HW.IsLaptop }; ConditionText = 'solo equipos de sobremesa'
        Name = 'Plan de energía Alto rendimiento - Activar'
        Description = 'La CPU no baja tanto de frecuencia; mejor respuesta. En portátiles se omite para no gastar batería.'
        Script = { Set-PowerPlan -Mode High }
    }
    @{
        Id = 'PlanMaximo'; Category = 'Energía'; Risk = 'Moderado'; Presets = @('G', 'M')
        Condition = { -not $script:HW.IsLaptop }; ConditionText = 'solo equipos de sobremesa'
        Name = 'Plan de energía Máximo rendimiento (Ultimate) - Activar'
        Description = 'Elimina micro-latencias de gestión de energía. Más consumo eléctrico. Solo sobremesa.'
        Script = { Set-PowerPlan -Mode Ultimate }
    }
    @{
        Id = 'LimitacionEnergia'; Category = 'Energía'; Risk = 'Moderado'; Presets = @('G', 'M'); Reboot = $true
        Condition = { -not $script:HW.IsLaptop }; ConditionText = 'solo equipos de sobremesa'
        Name = 'Power Throttling - Desactivar'
        Description = 'Windows deja de limitar la CPU de procesos en segundo plano (renders, compilaciones, streaming).'
        Registry = @(
            RegItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
        )
    }
    @{
        Id = 'Hibernacion'; Category = 'Energía'; Risk = 'Moderado'; Presets = @('E', 'G', 'M')
        Condition = { -not $script:HW.IsLaptop }; ConditionText = 'solo equipos de sobremesa'
        Name = 'Hibernación e Inicio rápido - Desactivar'
        Description = 'Libera hiberfil.sys (tantos GB como RAM) y fuerza arranques limpios, lo que evita muchos fallos de drivers tras "apagar".'
        Script     = { & powercfg.exe /hibernate off | Out-Null }
        UndoScript = { & powercfg.exe /hibernate on | Out-Null }
    }

    # ------------------------------ Servicios y sistema ------------------------------
    @{
        Id = 'Servicios'; Category = 'Servicios y sistema'; Risk = 'Moderado'; Presets = @('E', 'G', 'M')
        Name = 'Servicios innecesarios - Pasar a manual (lista conservadora)'
        Description = 'Solo servicios que no rompen nada al quedar en manual (arrancan si se necesitan): Mapas, demo de tienda, seguimiento de vínculos, asistente de compatibilidad, actualizador de Edge.'
        Services = @(
            @{ Name = 'MapsBroker';  Startup = 'Manual' }
            @{ Name = 'RetailDemo';  Startup = 'Disabled' }
            @{ Name = 'TrkWks';      Startup = 'Manual' }
            @{ Name = 'PcaSvc';      Startup = 'Manual' }
            @{ Name = 'edgeupdate';  Startup = 'Manual' }
            @{ Name = 'edgeupdatem'; Startup = 'Manual' }
        )
    }
    @{
        Id = 'Indexacion'; Category = 'Servicios y sistema'; Risk = 'Avanzado'; Presets = @('M')
        Name = 'Indexación de búsqueda de Windows - Desactivar'
        Description = 'Elimina la actividad de disco del indexador. La búsqueda de archivos será más lenta (alternativa: Everything).'
        Services = @(
            @{ Name = 'WSearch'; Startup = 'Disabled' }
        )
    }
    @{
        Id = 'AlmacenamientoReservado'; Category = 'Servicios y sistema'; Risk = 'Avanzado'; Presets = @('M')
        Condition = { $script:HW.Build -ge 18362 }; ConditionText = 'requiere Windows 10 1903+'
        Name = 'Almacenamiento reservado (~7 GB) - Desactivar'
        Description = 'Recupera el espacio que Windows reserva para actualizaciones. Si hay una actualización pendiente fallará: reinicia y repite.'
        Script = {
            & dism.exe /Online /Set-ReservedStorageState /State:Disabled /Quiet | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "DISM devolvió $LASTEXITCODE (¿actualización pendiente?)" }
        }
        UndoScript = { & dism.exe /Online /Set-ReservedStorageState /State:Enabled /Quiet | Out-Null }
    }

    # ------------------------------ Interfaz ------------------------------
    @{
        Id = 'FinalizarTarea'; Category = 'Interfaz'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M'); Explorer = $true
        Name = '"Finalizar tarea" en la barra de tareas (clic derecho) - Activar'
        Description = 'Cierra apps colgadas sin abrir el Administrador de tareas (Windows 11 23H2+).'
        Registry = @(
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1
        )
    }
    @{
        Id = 'Extensiones'; Category = 'Interfaz'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M'); Explorer = $true
        Name = 'Mostrar extensiones de archivo'
        Description = 'Mejora la seguridad: permite distinguir "factura.pdf.exe" de un PDF real.'
        Registry = @(
            RegItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0
        )
    }
    @{
        Id = 'MenuClasico'; Category = 'Interfaz'; Risk = 'Moderado'; Presets = @('M'); Explorer = $true
        Condition = { $script:HW.IsWin11 }; ConditionText = 'solo Windows 11'
        Name = 'Menú contextual clásico (sin "Mostrar más opciones")'
        Description = 'Recupera el menú de clic derecho completo de Windows 10, que abre más rápido.'
        Script     = { & reg.exe add 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /f /ve | Out-Null }
        UndoScript = { & reg.exe delete 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' /f | Out-Null }
    }
    @{
        Id = 'AutoDescubrimiento'; Category = 'Interfaz'; Risk = 'Moderado'; Presets = @('M'); Explorer = $true; NoUndo = $true
        Name = 'Explorador: detección automática de tipo de carpeta - Desactivar'
        Description = 'Evita que carpetas grandes de descargas se abran lentas al "detectar" fotos o música. Borra vistas personalizadas de carpetas (sin deshacer).'
        Script = {
            $bags = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags'
            $bagMRU = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU'
            Remove-Item -Path $bags -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction SilentlyContinue
            $allFolders = "$bags\AllFolders\Shell"
            New-Item -Path $allFolders -Force | Out-Null
            New-ItemProperty -Path $allFolders -Name 'FolderType' -Value 'NotSpecified' -PropertyType String -Force | Out-Null
        }
    }

    # ------------------------------ Edge ------------------------------
    @{
        Id = 'EdgeFondo'; Category = 'Navegador Edge'; Risk = 'Seguro'; Presets = @('B', 'E', 'G', 'M')
        Name = 'Edge: arranque anticipado y ejecución en segundo plano - Desactivar'
        Description = 'Edge deja de precargarse al iniciar Windows y de quedarse abierto tras cerrarlo (RAM y arranque).'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
        )
    }
    @{
        Id = 'EdgeLimpio'; Category = 'Navegador Edge'; Risk = 'Moderado'; Presets = @('M')
        Name = 'Edge: barra lateral, compras, recomendaciones y telemetría - Desactivar'
        Description = 'Quita elementos promocionales y de seguimiento de Edge mediante políticas oficiales.'
        Registry = @(
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeShoppingAssistantEnabled' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ShowRecommendationsEnabled' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'PersonalizationReportingEnabled' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'UserFeedbackAllowed' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DiagnosticData' 0
            RegItem 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeCollectionsEnabled' 0
        )
    }
)

$script:PresetInfo = [ordered]@{
    Basico      = 'Solo cambios seguros de privacidad y bloatware. Ideal para cualquier PC o equipos de trabajo.'
    Equilibrado = 'Recomendado. Privacidad + rendimiento sin perder funciones. Se adapta a portátil/sobremesa.'
    Gaming      = 'Equilibrado + HAGS, prioridad a juegos, ratón sin aceleración y plan de máximo rendimiento.'
    Maximo      = 'Todo lo anterior + ajustes avanzados (indexación, almacenamiento reservado, efectos visuales).'
}

function Get-Tweak {
    param([string]$Id)
    return ($script:Tweaks | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Get-PresetIds {
    param([string]$PresetName)
    $letter = $PresetName.Substring(0, 1).ToUpper()
    $ids = foreach ($t in $script:Tweaks) {
        $inPreset = $t.Presets -contains $letter
        if (-not $inPreset -and $t.AutoInclude -and $PresetName -ne 'Basico') { $inPreset = [bool](& $t.AutoInclude) }
        if ($inPreset) { $t.Id }
    }
    return @($ids)
}

function Test-TweakState {
    # $true = aplicado, $false = no aplicado, $null = no comprobable (solo script)
    param($Tweak)
    if (-not $Tweak.Registry) { return $null }
    foreach ($r in $Tweak.Registry) {
        try {
            if (-not (Test-Path -LiteralPath $r.Path)) { return $false }
            $item = Get-Item -LiteralPath $r.Path
            if ($item.GetValueNames() -notcontains $r.Name) { return $false }
            $cur = $item.GetValue($r.Name, $null, 'DoNotExpandEnvironmentNames')
            if (-not (Test-RegValueEqual -Current $cur -Desired $r.Value -Type $r.Type)) { return $false }
        } catch {
            return $false
        }
    }
    return $true
}

#endregion

#region ===================== Motor de aplicación de ajustes =====================

function New-SystemRestorePoint {
    param([string]$Description)
    if ($script:IsDryRun -or $NoRestorePoint) { return }
    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Write-Log 'Creando punto de restauración del sistema...' STEP
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # Windows solo permite un punto cada 24 h; se levanta el límite temporalmente.
        Set-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Log 'Punto de restauración creado.' OK
    } catch {
        Write-Log "No se pudo crear el punto de restauración: $($_.Exception.Message)" WARN
        Write-Log 'El respaldo propio de WinTurbo (menú Deshacer) seguirá disponible.'
    } finally {
        if ($null -eq $old) {
            Remove-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -Value $old -Type DWord
        }
    }
}

function Invoke-Tweak {
    param($Tweak)
    foreach ($r in $Tweak.Registry) { Set-RegValue -Path $r.Path -Name $r.Name -Value $r.Value -Type $r.Type }
    foreach ($s in $Tweak.Services) { Set-ServiceStartup -Name $s.Name -StartupType $s.Startup }
    foreach ($t in $Tweak.Tasks)    { Disable-TaskTracked -FullName $t }
    if ($Tweak.Script) {
        if ($script:IsDryRun) {
            Write-Log "Ejecutar acción: $($Tweak.Name)" DRY
        } else {
            & $Tweak.Script
            if ($Tweak.UndoScript) { Add-JournalEntry -Key "UNDO|$($Tweak.Id)" -Entry @{ Type = 'TweakUndo'; Id = $Tweak.Id } }
        }
    }
}

function Restart-Explorer {
    if ($script:IsDryRun) { return }
    Write-Log 'Reiniciando el Explorador de Windows...' STEP
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

function Invoke-TweakSet {
    param([string[]]$Ids, [string]$Label)
    $tweaks = @($script:Tweaks | Where-Object { $Ids -contains $_.Id })
    if ($tweaks.Count -eq 0) { Write-Log 'No hay ajustes seleccionados.' WARN; return }

    Write-Title "Se aplicarán $($tweaks.Count) ajustes ($Label)"
    foreach ($t in $tweaks) {
        $color = @{ Seguro = 'Green'; Moderado = 'Yellow'; Avanzado = 'Red' }[$t.Risk]
        $note = ''
        if ($t.Condition -and -not (& $t.Condition)) { $note = "  -> se omitirá: $($t.ConditionText)"; $color = 'DarkGray' }
        Write-Host ('   [{0,-8}] {1}{2}' -f $t.Risk, $t.Name, $note) -ForegroundColor $color
    }
    $advanced = @($tweaks | Where-Object { $_.Risk -eq 'Avanzado' }).Count
    if ($advanced -gt 0) { Write-Log "$advanced ajuste(s) avanzados: revisa la descripción antes de continuar." WARN }
    if ($script:IsDryRun) { Write-Log 'MODO SIMULACIÓN: no se cambiará nada.' DRY }
    if (-not (Confirm-Action '¿Continuar?')) { return }

    if (-not $script:IsDryRun) { Save-BaselineIfMissing }
    $before = Get-HealthSnapshot
    New-SystemRestorePoint -Description "WinTurbo: $Label"
    Start-Journal -Label $Label

    $ok = 0; $skipped = 0; $failed = 0; $i = 0
    $needExplorer = $false; $needReboot = $false
    foreach ($t in $tweaks) {
        $i++
        Write-Progress -Activity 'WinTurbo - aplicando ajustes' -Status $t.Name -PercentComplete ([int](100 * $i / $tweaks.Count))
        if ($t.Condition -and -not (& $t.Condition)) {
            $skipped++
            Write-Log "Omitido ($($t.ConditionText)): $($t.Name)"
            continue
        }
        try {
            Invoke-Tweak -Tweak $t | Out-Null
            $ok++
            if ($t.Explorer) { $needExplorer = $true }
            if ($t.Reboot)   { $needReboot = $true }
            if (-not $script:IsDryRun) { Write-Log $t.Name OK }
        } catch {
            $failed++
            Write-Log "Error en '$($t.Name)': $($_.Exception.Message)" ERROR
        }
    }
    Write-Progress -Activity 'WinTurbo - aplicando ajustes' -Completed
    Save-Journal

    Write-Title 'Resultado'
    $verb = if ($script:IsDryRun) { 'Se aplicarían' } else { 'Aplicados' }
    Write-Log "${verb}: $ok   Omitidos: $skipped   Errores: $failed" $(if ($failed) { 'WARN' } else { 'OK' })
    if (-not $script:IsDryRun -and $script:Journal.Entries.Count -gt 0) {
        Write-Log "Respaldo para deshacer: $script:JournalPath"
    }
    if (-not $script:IsDryRun) {
        Show-SnapshotComparison -Before $before -After (Get-HealthSnapshot)
        if ($needExplorer -and (Confirm-Action '¿Reiniciar el Explorador ahora para ver los cambios de interfaz?')) { Restart-Explorer }
        if ($needReboot -or $ok -gt 0) { Write-Log 'Reinicia el equipo para que todos los cambios surtan efecto.' WARN }
    }
}

#endregion

#region ===================== Deshacer =====================

function Invoke-UndoJournal {
    param([string]$Path)
    $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($j.Entries)
    [array]::Reverse($entries)
    $ok = 0; $failed = 0
    foreach ($e in $entries) {
        try {
            switch ($e.Type) {
                'Reg' {
                    if ($e.Existed) {
                        $v = $e.Value
                        switch ($e.ValueType) {
                            'Binary'      { $v = [byte[]]@($e.Value) }
                            'MultiString' { $v = [string[]]@($e.Value) }
                            'DWord'       { $v = [int]$e.Value }
                            'QWord'       { $v = [int64]$e.Value }
                        }
                        if (-not (Test-Path -LiteralPath $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
                        New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $v -PropertyType $e.ValueType -Force -ErrorAction Stop | Out-Null
                    } elseif (Test-Path -LiteralPath $e.Path) {
                        Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -ErrorAction SilentlyContinue
                    }
                }
                'Svc' {
                    if ($e.StartupType -and $script:ScStart.ContainsKey($e.StartupType)) {
                        & sc.exe config $e.Name start= $script:ScStart[$e.StartupType] | Out-Null
                    }
                }
                'Task'      { Enable-ScheduledTask -TaskPath $e.TaskPath -TaskName $e.TaskName -ErrorAction Stop | Out-Null }
                'Power'     { & powercfg.exe /setactive $e.Guid | Out-Null }
                'TweakUndo' { $t = Get-Tweak -Id $e.Id; if ($t -and $t.UndoScript) { & $t.UndoScript } }
                'DNS' {
                    # El índice de interfaz cambia tras reinstalar drivers: se busca primero por nombre.
                    $idx = $e.Index
                    $byName = Get-NetAdapter -Name $e.Alias -ErrorAction SilentlyContinue
                    if ($byName) { $idx = $byName.ifIndex }
                    if ($e.WasDhcp) {
                        Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop
                    } else {
                        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses (($e.Servers -split '[,\s]+') | Where-Object { $_ }) -ErrorAction Stop
                    }
                }
            }
            $ok++
        } catch {
            $failed++
            Write-Log "No se pudo revertir $($e.Type) $($e.Path)$($e.Name)$($e.TaskName): $($_.Exception.Message)" WARN
        }
    }
    Write-Log "Revertidos: $ok   Con error: $failed" OK
    Rename-Item -LiteralPath $Path -NewName ((Split-Path $Path -Leaf) -replace '\.json$', '.deshecho.json') -ErrorAction SilentlyContinue
    Write-Log 'Reinicia el equipo para completar la restauración.' WARN
}

function Show-UndoMenu {
    while ($true) {
        Clear-Host
        Write-Title 'Deshacer cambios'
        $files = @(Get-ChildItem -Path $script:BackupDir -Filter 'respaldo-*.json' -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -notmatch 'deshecho' } | Sort-Object LastWriteTime -Descending)
        if ($files.Count -eq 0) { Write-Log 'No hay respaldos de WinTurbo pendientes de deshacer.' }
        $n = 0
        foreach ($f in $files) {
            $n++
            try {
                $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                Write-Host ('   {0,2}. {1}  {2,-30} {3} cambios' -f $n, $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $j.Label, @($j.Entries).Count)
            } catch {
                Write-Host ('   {0,2}. {1} (ilegible)' -f $n, $f.Name) -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        Write-Host '    R. Abrir Restaurar sistema (puntos de restauración de Windows)'
        Write-Host '    0. Volver'
        $c = Read-Host '  Elige un respaldo para deshacer'
        if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
        if ($c -match '^[rR]$') { Start-Process rstrui.exe; continue }
        if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $files.Count) {
            $f = $files[[int]$c - 1]
            Write-Log 'Consejo: deshaz primero los respaldos más recientes.' INFO
            if (Confirm-Action "¿Revertir todos los cambios de $($f.Name)?") { Invoke-UndoJournal -Path $f.FullName }
            Wait-Enter
        }
    }
}

#endregion

#region ===================== Menú de ajustes personalizados =====================

function Show-CustomTweaksMenu {
    param([string[]]$Preselect = @())
    $ordered = @(foreach ($cat in $script:Categories) { $script:Tweaks | Where-Object { $_.Category -eq $cat } })
    $selected = @{}
    foreach ($id in $Preselect) { $selected[$id] = $true }
    while ($true) {
        Clear-Host
        Write-Title 'Ajustes personalizados'
        Write-Host '  [x] seleccionado   (aplicado) ya está activo en este equipo   Riesgo: ' -NoNewline
        Write-Host 'Seguro ' -ForegroundColor Green -NoNewline
        Write-Host 'Moderado ' -ForegroundColor Yellow -NoNewline
        Write-Host 'Avanzado' -ForegroundColor Red
        $n = 0; $lastCat = ''
        foreach ($t in $ordered) {
            $n++
            if ($t.Category -ne $lastCat) { Write-Host ''; Write-Host ("  == $($t.Category) ==") -ForegroundColor Cyan; $lastCat = $t.Category }
            $mark = if ($selected[$t.Id]) { '[x]' } else { '[ ]' }
            $state = Test-TweakState -Tweak $t
            $stateText = if ($state -eq $true) { '(aplicado)' } else { '' }
            $color = @{ Seguro = 'Green'; Moderado = 'Yellow'; Avanzado = 'Red' }[$t.Risk]
            if ($t.Condition -and -not (& $t.Condition)) { $color = 'DarkGray'; $stateText = "(no aplica: $($t.ConditionText))" }
            Write-Host ('  {0} {1,2}. ' -f $mark, $n) -NoNewline
            Write-Host ('{0,-68}' -f $t.Name) -ForegroundColor $color -NoNewline
            Write-Host (' ' + $stateText) -ForegroundColor DarkGreen
        }
        Write-Host ''
        Write-Host '  Números (ej. 1,4,7-9) = marcar/desmarcar   ? N = ver descripción'
        Write-Host '  P = cargar preset   T = todos   L = limpiar   E = exportar   I = importar   A = APLICAR   0 = volver'
        $c = Read-Host '  Opción'
        switch -Regex ($c) {
            '^0$' { return }
            '^[aA]$' {
                $ids = @($ordered | Where-Object { $selected[$_.Id] } | ForEach-Object { $_.Id })
                Invoke-TweakSet -Ids $ids -Label 'Personalizado'
                Wait-Enter
            }
            '^[tT]$' { foreach ($t in $ordered) { $selected[$t.Id] = $true } }
            '^[lL]$' { $selected = @{} }
            '^[pP]$' {
                $p = Read-Host '  Preset (Basico/Equilibrado/Gaming/Maximo)'
                if ($script:PresetInfo.Contains($p)) { $selected = @{}; foreach ($id in (Get-PresetIds $p)) { $selected[$id] = $true } }
            }
            '^[eE]$' {
                $file = Join-Path ([Environment]::GetFolderPath('Desktop')) 'WinTurbo-config.json'
                @{ Version = $script:Version; Tweaks = @($ordered | Where-Object { $selected[$_.Id] } | ForEach-Object { $_.Id }) } |
                    ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
                Write-Log "Configuración exportada: $file" OK
                Write-Log "Úsala en otro PC con:  .\WinTurbo.ps1 -ConfigFile `"$file`""
                Wait-Enter
            }
            '^[iI]$' {
                $file = Read-Host '  Ruta del JSON'
                try {
                    $cfg = Get-Content -LiteralPath $file.Trim('"') -Raw | ConvertFrom-Json
                    $selected = @{}; foreach ($id in $cfg.Tweaks) { $selected[[string]$id] = $true }
                } catch { Write-Log "No se pudo leer: $($_.Exception.Message)" ERROR; Wait-Enter }
            }
            '^\?\s*\d+$' {
                $idx = [int]($c -replace '[^\d]', '')
                if ($idx -ge 1 -and $idx -le $ordered.Count) {
                    $t = $ordered[$idx - 1]
                    Write-Host ''
                    Write-Host ("  $($t.Name)") -ForegroundColor White
                    Write-Host ("  Riesgo: $($t.Risk)   Presets: $(($t.Presets) -join ',')") -ForegroundColor Gray
                    Write-Host ("  $($t.Description)")
                    if ($t.NoUndo) { Write-Host '  Este ajuste no se puede deshacer automáticamente.' -ForegroundColor Yellow }
                    Wait-Enter
                }
            }
            default {
                foreach ($idx in (ConvertFrom-Selection -Text $c -Max $ordered.Count)) {
                    $id = $ordered[$idx - 1].Id
                    $selected[$id] = -not $selected[$id]
                }
            }
        }
    }
}

#endregion

#region ===================== Bloatware (apps preinstaladas) =====================

$script:AppxProtected = @(
    'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.WindowsCalculator',
    'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad', 'Microsoft.Paint', 'Microsoft.ScreenSketch', 'Microsoft.SecHealthUI',
    'Microsoft.WindowsTerminal', 'Microsoft.VCLibs*', 'Microsoft.UI.Xaml*', 'Microsoft.NET.*', 'Microsoft.XboxIdentityProvider',
    'Microsoft.HEIFImageExtension', 'Microsoft.WebpImageExtension', 'Microsoft.VP9VideoExtensions', 'Microsoft.HEVCVideoExtension',
    'Microsoft.WebMediaExtensions', 'Microsoft.AV1VideoExtension', 'Microsoft.WindowsAppRuntime*', 'Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost', 'Microsoft.AAD.BrokerPlugin', 'Microsoft.AccountsControl', 'windows.immersivecontrolpanel',
    'Microsoft.LanguageExperiencePack*', 'MicrosoftWindows.Client.*', 'Microsoft.WindowsCamera'
)

$script:AppxGroups = [ordered]@{
    'Recomendado (sin uso para la mayoría)' = @(
        'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.BingFinance', 'Microsoft.BingSports',
        'Microsoft.BingTravel', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.GetHelp',
        'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People',
        'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
        'Microsoft.ZuneVideo', 'Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10', 'Microsoft.MixedReality.Portal',
        'Microsoft.SkypeApp', 'Microsoft.Windows.DevHome', 'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.Microsoft3DViewer',
        'Microsoft.Print3D', 'Microsoft.Wallet', 'Microsoft.Messaging', 'Microsoft.OneConnect', 'Microsoft.StartExperiencesApp'
    )
    'Juegos y apps patrocinadas' = @(
        '*CandyCrush*', '*BubbleWitch*', '*MarchofEmpires*', '*Disney*', '*TikTok*', '*Facebook*', '*Instagram*',
        '*Twitter*', '*LinkedIn*', '*Royal Revolt*', '*Hidden City*', '*FarmVille*', '*king.com*'
    )
    'Copilot, Teams y nuevo Outlook' = @(
        'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider', 'MicrosoftTeams', 'MSTeams', 'Microsoft.OutlookForWindows'
    )
    'Xbox (solo si NO juegas en PC)' = @(
        'Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay',
        'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI'
    )
    'Correo/Calendar antiguo y Vincular teléfono' = @(
        'microsoft.windowscommunicationsapps', 'Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice'
    )
}

function Test-AppxProtected {
    param([string]$Name)
    foreach ($p in $script:AppxProtected) { if ($Name -like $p) { return $true } }
    return $false
}

function Remove-AppxSet {
    param([string[]]$Patterns)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    $removed = 0
    foreach ($pattern in $Patterns) {
        $pkgs = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue)
        foreach ($pkg in $pkgs) {
            if (Test-AppxProtected $pkg.Name) { continue }
            if ($script:IsDryRun) { Write-Log "Quitar app: $($pkg.Name)" DRY; continue }
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                $removed++
                Write-Log "Eliminada: $($pkg.Name)" OK
            } catch {
                Write-Log "No se pudo eliminar $($pkg.Name): $($_.Exception.Message)" WARN
            }
        }
        # Evita que la app se reinstale para usuarios nuevos o tras una actualización de funciones.
        foreach ($prov in ($provisioned | Where-Object { $_.DisplayName -like $pattern })) {
            if (Test-AppxProtected $prov.DisplayName) { continue }
            if ($script:IsDryRun) { Write-Log "Quitar aprovisionamiento: $($prov.DisplayName)" DRY; continue }
            try { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -AllUsers -ErrorAction Stop | Out-Null } catch { }
        }
    }
    Write-Log "Apps eliminadas: $removed. Se pueden reinstalar desde Microsoft Store si las necesitas."
}

function Show-BloatwareMenu {
    while ($true) {
        Clear-Host
        Write-Title 'Quitar bloatware (apps preinstaladas)'
        Write-Log 'Nunca se tocan: Tienda, winget, Calculadora, Fotos, Bloc de notas, Paint, Recortes, Cámara, Seguridad, códecs.'
        $groupNames = @($script:AppxGroups.Keys)
        $installedAll = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $groupNames.Count; $i++) {
            $patterns = $script:AppxGroups[$groupNames[$i]]
            $count = @($installedAll | Where-Object { $n = $_.Name; ($patterns | Where-Object { $n -like $_ }) }).Count
            Write-Host ('    {0}. {1,-45} {2} instaladas' -f ($i + 1), $groupNames[$i], $count)
        }
        Write-Host ''
        Write-Host '    L. Elegir apps una por una de la lista de instaladas'
        Write-Host '    O. Desinstalar OneDrive (tus archivos locales NO se borran)'
        Write-Host '    0. Volver'
        $c = Read-Host '  Grupos a eliminar (ej. 1,2) o letra'
        if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
        if ($c -match '^[lL]$') {
            $apps = @($installedAll | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' -and -not (Test-AppxProtected $_.Name) } |
                      Sort-Object Name -Unique)
            for ($i = 0; $i -lt $apps.Count; $i++) { Write-Host ('   {0,3}. {1}' -f ($i + 1), $apps[$i].Name) }
            $sel = ConvertFrom-Selection -Text (Read-Host '  Números a eliminar') -Max $apps.Count
            if ($sel.Count -gt 0 -and (Confirm-Action "¿Eliminar $($sel.Count) apps?")) {
                Remove-AppxSet -Patterns @($sel | ForEach-Object { $apps[$_ - 1].Name })
            }
            Wait-Enter; continue
        }
        if ($c -match '^[oO]$') {
            if (Confirm-Action 'OneDrive dejará de sincronizar. ¿Desinstalarlo?') { Remove-OneDriveSafe }
            Wait-Enter; continue
        }
        $sel = ConvertFrom-Selection -Text $c -Max $groupNames.Count
        if ($sel.Count -eq 0) { continue }
        $patterns = @(foreach ($s in $sel) { $script:AppxGroups[$groupNames[$s - 1]] })
        if (Confirm-Action '¿Eliminar las apps de los grupos elegidos para todos los usuarios?') { Remove-AppxSet -Patterns $patterns }
        Wait-Enter
    }
}

function Remove-OneDriveSafe {
    if ($script:IsDryRun) { Write-Log 'Desinstalar OneDrive' DRY; return }
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    $done = $false
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        & winget.exe uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements 2>&1 | Out-Null
        $done = ($LASTEXITCODE -eq 0)
    }
    if (-not $done) {
        foreach ($setup in @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")) {
            if (Test-Path $setup) { Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait; $done = $true; break }
        }
    }
    if ($done) { Write-Log 'OneDrive desinstalado. La carpeta OneDrive con tus archivos se conserva.' OK }
    else { Write-Log 'No se encontró el desinstalador de OneDrive.' WARN }
}

#endregion

#region ===================== Programas de inicio =====================

function Set-StartupItemState {
    param($Item, [bool]$Enable)
    $bytes = if ($Enable) { @(2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) } else { @(3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
    Set-RegValue -Path $Item.Approved -Name $Item.Nombre -Value $bytes -Type Binary
}

function Show-StartupMenu {
    while ($true) {
        Clear-Host
        Write-Title 'Programas que se inician con Windows'
        Write-Log 'Igual que el Administrador de tareas: desactivar no desinstala nada y se puede reactivar.'
        $items = @(Get-StartupItems)
        for ($i = 0; $i -lt $items.Count; $i++) {
            $it = $items[$i]
            $state = if ($it.Enabled) { 'ACTIVO  ' } else { 'inactivo' }
            $color = if ($it.Enabled) { 'White' } else { 'DarkGray' }
            $cmd = $it.Comando
            if ($cmd.Length -gt 60) { $cmd = $cmd.Substring(0, 57) + '...' }
            Write-Host ('   {0,2}. {1} {2,-28} {3,-15} {4}' -f ($i + 1), $state, $it.Nombre, $it.Origen, $cmd) -ForegroundColor $color
        }
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' -and ($_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
        })
        if ($tasks.Count -gt 0) {
            Write-Host ''
            Write-Host "   Además hay $($tasks.Count) tareas programadas de terceros al iniciar sesión:" -ForegroundColor DarkYellow
            foreach ($t in $tasks) { Write-Host ("      - $($t.TaskPath)$($t.TaskName)") -ForegroundColor DarkGray }
            Write-Host '     (para revisarlas a fondo, Sysinternals Autoruns es la mejor herramienta: menú Apps)' -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host '  Números = cambiar activo/inactivo   0 = volver'
        $c = Read-Host '  Opción'
        if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
        $sel = ConvertFrom-Selection -Text $c -Max $items.Count
        if ($sel.Count -eq 0) { continue }
        Start-Journal -Label 'Programas de inicio'
        foreach ($s in $sel) {
            $it = $items[$s - 1]
            try {
                Set-StartupItemState -Item $it -Enable (-not $it.Enabled)
                if (-not $script:IsDryRun) {
                    Write-Log ("{0}: {1}" -f $it.Nombre, $(if ($it.Enabled) { 'desactivado' } else { 'activado' })) OK
                }
            } catch { Write-Log "Error con $($it.Nombre): $($_.Exception.Message)" ERROR }
        }
        Save-Journal
        Wait-Enter
    }
}

#endregion

#region ===================== Limpieza =====================

function Clear-FolderSafe {
    # Borra contenido con más de $MinAgeHours de antigüedad, para no romper instaladores en curso.
    param([string]$Path, [int]$MinAgeHours = 24)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $limit = (Get-Date).AddHours(-$MinAgeHours)
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limit } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

$script:CleanupTasks = @(
    @{ Name = 'Archivos temporales (usuario y Windows, >24 h)'; Default = $true
       Size = { (Get-FolderSizeMB $env:TEMP) + (Get-FolderSizeMB "$env:SystemRoot\Temp") }
       Run  = { Clear-FolderSafe $env:TEMP; Clear-FolderSafe "$env:SystemRoot\Temp" } }
    @{ Name = 'Caché de descargas de Windows Update'; Default = $true
       Size = { Get-FolderSizeMB "$env:SystemRoot\SoftwareDistribution\Download" }
       Run  = {
           Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
           Clear-FolderSafe "$env:SystemRoot\SoftwareDistribution\Download" 0
           Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
       } }
    @{ Name = 'Caché de Optimización de distribución'; Default = $true
       Size = { Get-FolderSizeMB "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" }
       Run  = { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue } }
    @{ Name = 'Informes de errores y volcados de memoria'; Default = $true
       Size = { (Get-FolderSizeMB "$env:ProgramData\Microsoft\Windows\WER") + (Get-FolderSizeMB "$env:SystemRoot\Minidump") }
       Run  = {
           Clear-FolderSafe "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" 0
           Clear-FolderSafe "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" 0
           Clear-FolderSafe "$env:SystemRoot\Minidump" 0
       } }
    @{ Name = 'Papelera de reciclaje'; Default = $true
       Size = { $null }
       Run  = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } }
    @{ Name = 'Caché de miniaturas del Explorador'; Default = $false
       Size = { Get-FolderSizeMB "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" }
       Run  = { Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue } }
    @{ Name = 'Almacén de componentes WinSxS (DISM, lento)'; Default = $false
       Size = { $null }
       Run  = { & dism.exe /Online /Cleanup-Image /StartComponentCleanup } }
    @{ Name = 'Liberador de espacio de Windows (todas las categorías)'; Default = $false
       Size = { $null }
       Run  = {
           $vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
           Get-ChildItem $vc -ErrorAction SilentlyContinue | ForEach-Object {
               New-ItemProperty -Path $_.PSPath -Name 'StateFlags0777' -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
           }
           Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -Wait
       } }
)

function Invoke-Cleanup {
    param([int[]]$Indexes)
    $freeBefore = Get-FreeSpaceGB
    foreach ($i in $Indexes) {
        $task = $script:CleanupTasks[$i - 1]
        if ($script:IsDryRun) { Write-Log "Limpiar: $($task.Name)" DRY; continue }
        Write-Log $task.Name STEP
        try { & $task.Run } catch { Write-Log $_.Exception.Message WARN }
    }
    if (-not $script:IsDryRun) {
        $freed = [math]::Round(((Get-FreeSpaceGB) - $freeBefore) * 1024, 0)
        Write-Log "Espacio recuperado: $freed MB (libre ahora: $(Get-FreeSpaceGB) GB)" OK
    }
}

function Show-CleanupMenu {
    Clear-Host
    Write-Title 'Limpieza de disco'
    Write-Log 'Calculando tamaños...'
    $defaults = @()
    for ($i = 0; $i -lt $script:CleanupTasks.Count; $i++) {
        $t = $script:CleanupTasks[$i]
        $size = & $t.Size
        $sizeText = if ($null -eq $size) { '' } else { "$size MB" }
        $mark = if ($t.Default) { '*' } else { ' ' }
        if ($t.Default) { $defaults += ($i + 1) }
        Write-Host ('   {0} {1}. {2,-55} {3,10}' -f $mark, ($i + 1), $t.Name, $sizeText)
    }
    Write-Host ''
    Write-Host '  Enter = recomendadas (*)   Números = elegir   0 = volver'
    $c = Read-Host '  Opción'
    if ($c -eq '0') { return }
    $sel = if ([string]::IsNullOrWhiteSpace($c)) { $defaults } else { ConvertFrom-Selection -Text $c -Max $script:CleanupTasks.Count }
    if ($sel.Count -gt 0) { Invoke-Cleanup -Indexes $sel }
    Wait-Enter
}

#endregion

#region ===================== Reparación y mantenimiento =====================

function Invoke-ExternalStep {
    param([string]$Label, [string]$File, [string]$Arguments, [int[]]$OkCodes = @(0))
    if ($script:IsDryRun) { Write-Log "$Label -> $File $Arguments" DRY; return $true }
    Write-Log $Label STEP
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    if ($OkCodes -contains $p.ExitCode) { Write-Log "${Label}: correcto (código $($p.ExitCode))" OK; return $true }
    Write-Log "${Label}: terminó con código $($p.ExitCode)" WARN
    return $false
}

function Invoke-SystemRepair {
    # Orden correcto: DISM repara primero el almacén de componentes del que SFC obtiene los archivos buenos.
    [void](Invoke-ExternalStep -Label '1/3 Reparando imagen de Windows (DISM)' -File 'dism.exe' -Arguments '/Online /Cleanup-Image /RestoreHealth' -OkCodes @(0, 3010))
    [void](Invoke-ExternalStep -Label '2/3 Comprobando archivos del sistema (SFC)' -File 'sfc.exe' -Arguments '/scannow')
    [void](Invoke-ExternalStep -Label '3/3 Comprobando el disco en línea (CHKDSK)' -File 'chkdsk.exe' -Arguments "$env:SystemDrive /scan" -OkCodes @(0, 1, 2))
    Write-Log "Registro detallado de SFC: $env:SystemRoot\Logs\CBS\CBS.log"
}

function Invoke-DriveOptimization {
    foreach ($v in (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.FileSystem -match 'NTFS|ReFS' })) {
        if ($script:IsDryRun) { Write-Log "Optimizar unidad $($v.DriveLetter):" DRY; continue }
        Write-Log "Optimizando $($v.DriveLetter): (TRIM en SSD, desfragmentación en HDD)" STEP
        try { Optimize-Volume -DriveLetter $v.DriveLetter -ErrorAction Stop; Write-Log "$($v.DriveLetter): optimizada" OK }
        catch { Write-Log "$($v.DriveLetter): $($_.Exception.Message)" WARN }
    }
}

function Reset-NetworkStack {
    if ($script:IsDryRun) { Write-Log 'Restablecer red (DNS, Winsock, TCP/IP)' DRY; return }
    & ipconfig.exe /flushdns | Out-Null
    & netsh.exe winsock reset | Out-Null
    & netsh.exe int ip reset | Out-Null
    & ipconfig.exe /release | Out-Null
    & ipconfig.exe /renew | Out-Null
    Write-Log 'Pila de red restablecida. Reinicia el equipo.' OK
}

function Reset-WindowsUpdate {
    if ($script:IsDryRun) { Write-Log 'Restablecer componentes de Windows Update' DRY; return }
    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver'
    Stop-Service -Name $svcs -Force -ErrorAction SilentlyContinue
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    foreach ($dir in @("$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2")) {
        if (Test-Path $dir) { Rename-Item -Path $dir -NewName ((Split-Path $dir -Leaf) + ".old$stamp") -ErrorAction SilentlyContinue }
    }
    Start-Service -Name $svcs -ErrorAction SilentlyContinue
    Write-Log 'Windows Update restablecido (carpetas antiguas renombradas a *.old). Busca actualizaciones de nuevo.' OK
}

function Sync-SystemTime {
    if ($script:IsDryRun) { Write-Log 'Sincronizar hora con pool.ntp.org' DRY; return }
    & w32tm.exe /config /manualpeerlist:'pool.ntp.org,0x8 time.windows.com,0x8' /syncfromflags:manual /update | Out-Null
    Restart-Service w32time -Force -ErrorAction SilentlyContinue
    & w32tm.exe /resync /force | Out-Null
    Write-Log "Hora sincronizada: $(Get-Date)" OK
}

function Repair-Winget {
    if ($script:IsDryRun) { Write-Log 'Reparar winget' DRY; return }
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
        Write-Log 'winget (Instalador de aplicación) re-registrado.' OK
    } catch {
        Write-Log 'No se pudo re-registrar. Instala "Instalador de aplicación" desde Microsoft Store.' WARN
        Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
    }
}

function Show-RepairMenu {
    while ($true) {
        Clear-Host
        Write-Title 'Reparación y mantenimiento'
        Write-Host '    1. Reparar Windows (DISM -> SFC -> CHKDSK)          [20-40 min]'
        Write-Host '    2. Optimizar unidades (TRIM SSD / desfragmentar HDD)'
        Write-Host '    3. Restablecer red (DNS, Winsock, TCP/IP)'
        Write-Host '    4. Restablecer Windows Update (si no descarga/instala)'
        Write-Host '    5. Sincronizar la hora del sistema'
        Write-Host '    6. Reparar winget'
        Write-Host '    7. Reconstruir caché de iconos'
        Write-Host '    0. Volver'
        switch (Read-Host '  Opción') {
            '1' { Invoke-SystemRepair; Wait-Enter }
            '2' { Invoke-DriveOptimization; Wait-Enter }
            '3' { if (Confirm-Action 'Se cortará la conexión unos segundos. ¿Continuar?') { Reset-NetworkStack }; Wait-Enter }
            '4' { Reset-WindowsUpdate; Wait-Enter }
            '5' { Sync-SystemTime; Wait-Enter }
            '6' { Repair-Winget; Wait-Enter }
            '7' {
                if (-not $script:IsDryRun) {
                    & ie4uinit.exe -show
                    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                    Restart-Explorer
                    Write-Log 'Caché de iconos reconstruida.' OK
                }
                Wait-Enter
            }
            '0' { return }
        }
    }
}

#endregion

#region ===================== Red y DNS =====================

$script:DnsProviders = @(
    @{ Name = 'Cloudflare';                       Servers = @('1.1.1.1', '1.0.0.1') }
    @{ Name = 'Cloudflare (bloquea malware)';     Servers = @('1.1.1.2', '1.0.0.2') }
    @{ Name = 'Cloudflare (malware + adultos)';   Servers = @('1.1.1.3', '1.0.0.3') }
    @{ Name = 'Google';                           Servers = @('8.8.8.8', '8.8.4.4') }
    @{ Name = 'Quad9 (bloquea malware)';          Servers = @('9.9.9.9', '149.112.112.112') }
    @{ Name = 'OpenDNS';                          Servers = @('208.67.222.222', '208.67.220.220') }
    @{ Name = 'AdGuard (bloquea anuncios)';       Servers = @('94.140.14.14', '94.140.15.15') }
    @{ Name = 'AdGuard Familiar';                 Servers = @('94.140.14.15', '94.140.15.16') }
)

function Get-ActiveAdapters {
    # -Physical incluye adaptadores virtuales que se declaran físicos (Npcap Loopback, VPN TAP, etc.): se excluyen por nombre.
    # No se exige puerta de enlace: un adaptador con IP fija sin gateway también debe poder volver a DNS automático.
    $virtual = 'Loopback|Npcap|Virtual|VMware|VirtualBox|Hyper-V|TAP-|Wintun|WireGuard|Tailscale|ZeroTier|Bluetooth|Teredo|Pseudo'
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch $virtual -and $_.Name -notmatch $virtual
    })
}

function Measure-DnsProviders {
    $results = Get-DnsBenchmark
    Write-Host ''
    $results | Format-Table -AutoSize | Out-String | Write-Host
    if ($results.Count -gt 0 -and $results[0].MedianaMs) { Write-Log "Más rápido desde tu conexión: $($results[0].Proveedor) ($($results[0].MedianaMs) ms)" OK }
}

function Get-DnsBenchmark {
    $domains = 'google.com', 'microsoft.com', 'wikipedia.org', 'amazon.com', 'github.com', 'youtube.com'
    $results = foreach ($p in $script:DnsProviders) {
        $ip = $p.Servers[0]
        Write-Host ("   Probando $($p.Name) ($ip)...") -ForegroundColor DarkGray
        $times = New-Object System.Collections.Generic.List[double]
        $fails = 0
        foreach ($round in 1..2) {
            foreach ($d in $domains) {
                try {
                    $ms = (Measure-Command { Resolve-DnsName -Name $d -Server $ip -Type A -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop | Out-Null }).TotalMilliseconds
                    $times.Add($ms)
                } catch { $fails++ }
            }
        }
        $median = $null
        if ($times.Count -gt 0) {
            $sorted = @($times | Sort-Object)
            $median = [math]::Round($sorted[[int][math]::Floor($sorted.Count / 2)], 1)
        }
        [pscustomobject]@{ Proveedor = $p.Name; Servidor = $ip; MedianaMs = $median; Fallos = $fails }
    }
    return , @($results | Sort-Object @{ Expression = { if ($null -eq $_.MedianaMs) { 99999 } else { $_.MedianaMs } } })
}

function Set-DnsForActiveAdapters {
    param([string[]]$Servers, [string]$Label)
    $adapters = Get-ActiveAdapters
    if ($adapters.Count -eq 0) { Write-Log 'No hay adaptadores de red físicos conectados.' WARN; return }
    Start-Journal -Label "DNS: $Label"
    foreach ($a in $adapters) {
        if ($script:IsDryRun) { Write-Log "DNS de '$($a.Name)' -> $($Servers -join ', ')" DRY; continue }
        $ifReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)" -ErrorAction SilentlyContinue
        $static = [string]$ifReg.NameServer
        Add-JournalEntry -Key "DNS|$($a.ifIndex)" -Entry @{ Type = 'DNS'; Index = $a.ifIndex; Alias = $a.Name; WasDhcp = [string]::IsNullOrWhiteSpace($static); Servers = $static }
        try {
            if ($Servers) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $Servers -ErrorAction Stop }
            else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop }
            Write-Log "DNS de '$($a.Name)': $Label" OK
        } catch { Write-Log "Error en '$($a.Name)': $($_.Exception.Message)" ERROR }
    }
    Save-Journal
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Show-DnsMenu {
    while ($true) {
        Clear-Host
        Write-Title 'Red y DNS'
        foreach ($a in (Get-ActiveAdapters)) {
            $cur = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
            Write-Host ("   $($a.Name): $cur") -ForegroundColor Gray
        }
        Write-Host ''
        for ($i = 0; $i -lt $script:DnsProviders.Count; $i++) {
            $p = $script:DnsProviders[$i]
            Write-Host ('    {0}. {1,-34} {2}' -f ($i + 1), $p.Name, ($p.Servers -join ', '))
        }
        Write-Host ''
        Write-Host '    B. Medir qué DNS es más rápido desde tu conexión'
        Write-Host '    D. Volver a DNS automático (del router/proveedor)'
        Write-Host '    0. Volver'
        $c = Read-Host '  Opción'
        if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
        if ($c -match '^[bB]$') { Measure-DnsProviders; Wait-Enter; continue }
        if ($c -match '^[dD]$') { Set-DnsForActiveAdapters -Servers @() -Label 'automático (DHCP)'; Wait-Enter; continue }
        if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $script:DnsProviders.Count) {
            $p = $script:DnsProviders[[int]$c - 1]
            Set-DnsForActiveAdapters -Servers $p.Servers -Label $p.Name
            Wait-Enter
        }
    }
}

#endregion

#region ===================== Bloqueo persistente de Windows Update =====================
<#
  Por qué el método de WinUtil (Invoke-WPFUpdatesdisable) se revierte solo:
   1. No desactiva WaaSMedicSvc (Servicio Medic de Windows Update), cuya única función es
      reparar Windows Update: vuelve a poner wuauserv/UsoSvc/BITS en marcha y reactiva las tareas.
   2. Las tareas de UpdateOrchestrator y WaaSMedic solo las puede modificar SYSTEM. Como
      administrador, Disable-ScheduledTask da "Acceso denegado", y -ErrorAction SilentlyContinue
      oculta el fallo, así que la interfaz lo marca como hecho sin haberlo hecho.
   3. Ignora uhssvc (Microsoft Update Health Tools) y sedsvc/rempl (Remediation), que también
      restauran la configuración de Windows Update.
   4. Es de un solo uso: nada vuelve a aplicar el bloqueo cuando una actualización acumulativa
      o el Medic restauran los servicios.
   5. No comprueba el resultado.
   6. En Windows Home las políticas NoAutoUpdate/AUOptions se ignoran, así que solo quedan los
      servicios, que el Medic restaura.
  Solución de WinTurbo: el bloqueo se ejecuta como SYSTEM; una tarea guardiana lo vuelve a aplicar
  al arrancar y cada hora; se verifica el estado real; Defender sigue actualizando sus firmas por
  su propio canal (MMPC); y la reactivación restaura el estado ORIGINAL guardado.
#>

$script:WUSecureDir    = Join-Path $script:DataDir 'Seguro'
$script:WUEnforcerPath = Join-Path $script:WUSecureDir 'BloqueoWU.ps1'
$script:WUStatePath    = Join-Path $script:WUSecureDir 'wu-estado-original.json'
$script:WUTaskPath     = '\WinTurbo\'
$script:WUGuardTask    = 'Bloqueo de Windows Update'
$script:WUServices     = @('wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'uhssvc', 'sedsvc')
$script:WUTaskFolders  = @('\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\',
                           '\Microsoft\Windows\WaaSMedic\', '\Microsoft\Windows\UpdateAssistant\', '\Microsoft\Windows\rempl\')
# Valores por defecto de Windows: Start (2 automático, 3 manual) y DelayedAutostart.
$script:WUDefaults     = @{ wuauserv = @(3, 0); UsoSvc = @(2, 1); WaaSMedicSvc = @(3, 0); uhssvc = @(2, 1); sedsvc = @(3, 0) }

# Script que se ejecuta como SYSTEM. Se guarda en una carpeta en la que solo pueden escribir SYSTEM y
# Administradores, para que ningún usuario estándar pueda modificar código que corre como SYSTEM.
$script:WUEnforcerScript = @'
param([ValidateSet('Block', 'BlockStore', 'Unblock')][string]$Mode = 'Block')
$ErrorActionPreference = 'Continue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $base 'bloqueo-wu.log'
function Write-WULog([string]$m) {
    try { Add-Content -Path $log -Value ('{0} [{1}] {2}' -f (Get-Date -Format s), $Mode, $m) -Encoding UTF8 } catch { }
}
$services = @('wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'uhssvc', 'sedsvc')
$taskFolders = @('\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\',
                 '\Microsoft\Windows\WaaSMedic\', '\Microsoft\Windows\UpdateAssistant\', '\Microsoft\Windows\rempl\')
$defaults = @{ wuauserv = @(3, 0); UsoSvc = @(2, 1); WaaSMedicSvc = @(3, 0); uhssvc = @(2, 1); sedsvc = @(3, 0) }

function Set-WUServiceStart([string]$Name, [int]$Start, [int]$Delayed) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path $key)) { return }
    $scArg = @{ 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }[$Start]
    if ($Start -eq 2 -and $Delayed -eq 1) { $scArg = 'delayed-auto' }
    & sc.exe config $Name start= $scArg | Out-Null
    try {
        Set-ItemProperty -Path $key -Name Start -Value $Start -Type DWord -ErrorAction Stop
        Set-ItemProperty -Path $key -Name DelayedAutostart -Value $Delayed -Type DWord -ErrorAction SilentlyContinue
        Write-WULog ('Servicio {0}: Start={1}' -f $Name, $Start)
    } catch {
        Write-WULog ('Servicio {0}: no se pudo escribir el registro ({1})' -f $Name, $_.Exception.Message)
    }
}

if ($Mode -ne 'Unblock') {
    foreach ($s in $services) {
        if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$s")) { continue }
        if ($Mode -eq 'BlockStore' -and $s -eq 'wuauserv') {
            # Modo compatible con Microsoft Store: wuauserv queda en Manual para que la Tienda pueda
            # arrancarlo al descargar apps. No se detiene para no cortar una descarga en curso.
            Set-WUServiceStart -Name $s -Start 3 -Delayed 0
            continue
        }
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        Set-WUServiceStart -Name $s -Start 4 -Delayed 0
    }
    foreach ($folder in $taskFolders) {
        foreach ($t in @(Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' })) {
            try {
                Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
                Write-WULog ('Tarea desactivada: {0}{1}' -f $t.TaskPath, $t.TaskName)
            } catch {
                Write-WULog ('Tarea {0}{1}: {2}' -f $t.TaskPath, $t.TaskName, $_.Exception.Message)
            }
        }
    }
    # Defender no depende de Windows Update: actualiza sus firmas desde Microsoft Malware Protection Center.
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.AntivirusSignatureAge -ge 1) {
            Update-MpSignature -UpdateSource MMPC -ErrorAction Stop
            Write-WULog 'Firmas de Defender actualizadas desde MMPC.'
        }
    } catch {
        Write-WULog ('Defender: {0}' -f $_.Exception.Message)
    }
} else {
    $state = $null
    $statePath = Join-Path $base 'wu-estado-original.json'
    if (Test-Path $statePath) { try { $state = Get-Content $statePath -Raw | ConvertFrom-Json } catch { } }

    foreach ($s in $services) {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        if (-not (Test-Path $key)) { continue }
        # Quita reglas "Denegar a SYSTEM" que ponen otras herramientas para bloquear los servicios.
        try {
            $acl = Get-Acl -Path $key -ErrorAction Stop
            $deny = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) |
                      Where-Object { $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Value -eq 'S-1-5-18' })
            if ($deny.Count -gt 0) {
                foreach ($r in $deny) { [void]$acl.RemoveAccessRule($r) }
                Set-Acl -Path $key -AclObject $acl -ErrorAction Stop
                Write-WULog ('Quitadas reglas de denegacion en {0}' -f $s)
            }
        } catch { }
        $start = $defaults[$s][0]; $delayed = $defaults[$s][1]
        if ($state -and $state.Services.$s) {
            $orig = [int]$state.Services.$s.Start
            if ($orig -ge 2 -and $orig -le 3) { $start = $orig; $delayed = [int]$state.Services.$s.Delayed }
        }
        Set-WUServiceStart -Name $s -Start $start -Delayed $delayed
    }
    $enableList = $null
    if ($state -and $state.Tasks) { $enableList = @($state.Tasks) }
    foreach ($folder in $taskFolders) {
        foreach ($t in @(Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Disabled' })) {
            $full = $t.TaskPath + $t.TaskName
            if ($enableList -and ($enableList -notcontains $full)) { continue }
            try {
                Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
                Write-WULog ('Tarea reactivada: {0}' -f $full)
            } catch {
                Write-WULog ('Tarea {0}: {1}' -f $full, $_.Exception.Message)
            }
        }
    }
    Start-Service -Name UsoSvc, wuauserv -ErrorAction SilentlyContinue
}
Write-WULog 'Fin.'
'@

function Initialize-WUSecureDir {
    New-Item -ItemType Directory -Force -Path $script:WUSecureDir | Out-Null
    # Solo SYSTEM y Administradores pueden escribir; Usuarios solo leen. SIDs para no depender del idioma.
    $out = & icacls.exe $script:WUSecureDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "No se pudieron proteger los permisos de $($script:WUSecureDir): $out" }
    Set-Content -Path $script:WUEnforcerPath -Value $script:WUEnforcerScript -Encoding UTF8
}

function Save-WUOriginalState {
    # Solo la primera vez: si ya existe, el estado guardado es el anterior al bloqueo y no debe pisarse.
    if (Test-Path $script:WUStatePath) { return }
    $svc = [ordered]@{}
    foreach ($s in $script:WUServices) {
        $reg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$s" -ErrorAction SilentlyContinue
        if (-not $reg) { continue }
        $start = [int]$reg.Start
        $delayed = [int]$reg.DelayedAutostart
        # Si ya estaba bloqueado (por ejemplo por WinUtil), se guarda el valor por defecto de Windows.
        if ($start -eq 4) { $start = $script:WUDefaults[$s][0]; $delayed = $script:WUDefaults[$s][1] }
        $svc[$s] = @{ Start = $start; Delayed = $delayed }
    }
    $tasks = foreach ($f in $script:WUTaskFolders) {
        Get-ScheduledTask -TaskPath $f -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' } |
            ForEach-Object { $_.TaskPath + $_.TaskName }
    }
    $fallback = $null
    try { $fallback = (Get-MpPreference -ErrorAction Stop).SignatureFallbackOrder } catch { }
    @{ Fecha = (Get-Date).ToString('s'); Services = $svc; Tasks = @($tasks); DefenderFallback = $fallback } |
        ConvertTo-Json -Depth 4 | Set-Content -Path $script:WUStatePath -Encoding UTF8
}

function Wait-ScheduledTaskRun {
    param([string]$TaskName, [string]$TaskPath, [int]$TimeoutSec = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        Start-Sleep -Seconds 2
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        $info = Get-ScheduledTaskInfo -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        # 267011 = la tarea aún no se ha ejecutado; 267009 = en ejecución.
        $done = $task -and $task.State -ne 'Running' -and $info -and $info.LastTaskResult -ne 267011 -and $info.LastTaskResult -ne 267009
    } while (-not $done -and (Get-Date) -lt $deadline)
    if (-not $done) { return $null }
    return $info.LastTaskResult
}

function New-WUTaskAction {
    param([string]$Mode)
    return New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode {1}' -f $script:WUEnforcerPath, $Mode)
}

function Invoke-WUEnforcerOnce {
    param([ValidateSet('Block', 'Unblock')][string]$Mode)
    $name = "Windows Update $Mode (una vez)"
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskPath $script:WUTaskPath -TaskName $name -Action (New-WUTaskAction $Mode) -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskPath $script:WUTaskPath -TaskName $name
    $result = Wait-ScheduledTaskRun -TaskPath $script:WUTaskPath -TaskName $name
    Unregister-ScheduledTask -TaskPath $script:WUTaskPath -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    if ($null -eq $result) { Write-Log 'La acción como SYSTEM no terminó a tiempo; se verificará igualmente.' WARN }
    elseif ($result -ne 0) { Write-Log "La acción como SYSTEM terminó con código $result." WARN }
}

function Register-WUGuard {
    param([ValidateSet('Block', 'BlockStore')][string]$Mode = 'Block')
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $triggers = @(
        (New-ScheduledTaskTrigger -AtStartup),
        # Duración explícita: sin ella, algunas versiones de Windows limitan la repetición en lugar de dejarla indefinida.
        (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650))
    )
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath $script:WUTaskPath -TaskName $script:WUGuardTask -Action (New-WUTaskAction $Mode) `
        -Trigger $triggers -Principal $principal -Settings $settings -Force `
        -Description 'WinTurbo: mantiene Windows Update desactivado (al arrancar y cada hora) y actualiza las firmas de Defender. Para quitarlo usa WinTurbo > Windows Update > Reactivar.' | Out-Null
}

function Get-WUBlockStatus {
    $guard = Get-ScheduledTask -TaskPath $script:WUTaskPath -TaskName $script:WUGuardTask -ErrorAction SilentlyContinue
    $storeMode = [bool]($guard -and (@($guard.Actions)[0].Arguments -match '-Mode BlockStore'))
    $rows = foreach ($s in $script:WUServices) {
        $reg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$s" -ErrorAction SilentlyContinue
        if (-not $reg) { continue }
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        $blocked = ([int]$reg.Start -eq 4)
        $detail = "Start=$($reg.Start) ($($svc.Status))"
        if ($storeMode -and $s -eq 'wuauserv') {
            # En modo Tienda, wuauserv en Manual es el estado esperado.
            $blocked = ([int]$reg.Start -eq 3)
            $detail += ' - manual para Microsoft Store'
        }
        [pscustomobject]@{ Elemento = "Servicio $s"; Bloqueado = $blocked; Desconocido = $false; Detalle = $detail }
    }
    $allTasks = @(foreach ($f in $script:WUTaskFolders) { Get-ScheduledTask -TaskPath $f -ErrorAction SilentlyContinue })
    $enabled = @($allTasks | Where-Object { $_.State -ne 'Disabled' })
    if ($allTasks.Count -eq 0 -or -not (Test-IsAdmin)) {
        # Sin permisos de administrador Windows oculta estas tareas: no se puede afirmar que estén bloqueadas.
        $tasksRow = [pscustomobject]@{ Elemento = 'Tareas programadas de actualización'; Bloqueado = $false; Desconocido = $true; Detalle = 'no se pudieron leer (se necesitan permisos de administrador)' }
    } else {
        $tasksRow = [pscustomobject]@{ Elemento = 'Tareas programadas de actualización'; Bloqueado = ($enabled.Count -eq 0); Desconocido = $false
                                       Detalle = "$($enabled.Count) de $($allTasks.Count) activas" + $(if ($enabled.Count) { ': ' + (($enabled | Select-Object -First 3 | ForEach-Object { $_.TaskName }) -join ', ') } else { '' }) }
    }
    $rows = @($rows) + $tasksRow
    $guardDetail = if (-not $guard) { 'no existe' } elseif ($storeMode) { "$($guard.State) - modo compatible con la Tienda" } else { "$($guard.State) - bloqueo total" }
    $rows += [pscustomobject]@{ Elemento = 'Tarea guardiana (SYSTEM)'; Bloqueado = [bool]$guard; Desconocido = $false; NoExiste = (-not $guard); Detalle = $guardDetail }

    $core = @($rows | Where-Object { $_.Elemento -in @('Servicio wuauserv', 'Servicio UsoSvc', 'Tareas programadas de actualización', 'Tarea guardiana (SYSTEM)') })
    $estado = if (@($core | Where-Object { -not $_.Bloqueado }).Count -eq 0) { 'BLOQUEADO' }
              elseif (@($rows | Where-Object { $_.Bloqueado }).Count -eq 0) { 'ACTIVO' }
              else { 'PARCIAL' }
    $modo = if (-not $guard) { $null } elseif ($storeMode) { 'Tienda' } else { 'Total' }
    return [pscustomobject]@{ Estado = $estado; Modo = $modo; Detalle = $rows }
}

function Show-WUBlockStatus {
    $st = Get-WUBlockStatus
    foreach ($r in $st.Detalle) {
        $mark = if ($r.Bloqueado) { 'bloqueado' } else { 'ACTIVO   ' }
        $color = if ($r.Bloqueado) { 'Green' } else { 'Yellow' }
        Write-Host ('   {0}  {1,-38} {2}' -f $mark, $r.Elemento, $r.Detalle) -ForegroundColor $color
    }
    return $st
}

function Disable-WindowsUpdateFull {
    # -KeepStore: bloquea las actualizaciones automáticas del sistema pero deja wuauserv en Manual,
    # porque Microsoft Store lo usa para descargar apps (si está Deshabilitado da el error 0x80070422).
    param([switch]$KeepStore)
    $guardMode = if ($KeepStore) { 'BlockStore' } else { 'Block' }
    if ($KeepStore) {
        Write-Title 'Desactivar Windows Update manteniendo Microsoft Store'
        Write-Host '  Windows dejará de buscar e instalar actualizaciones por su cuenta (nada las programa).' -ForegroundColor Yellow
        Write-Host '  El motor de descarga queda en Manual para que la Tienda pueda instalar y actualizar apps.' -ForegroundColor Yellow
        Write-Host '  La página de Windows Update de Configuración puede mostrar un error: es esperado.' -ForegroundColor Yellow
    } else {
        Write-Title 'Desactivar Windows Update por completo'
        Write-Host '  Sin Windows Update no recibirás parches de seguridad. Defender seguirá actualizando sus' -ForegroundColor Yellow
        Write-Host '  firmas por su canal propio. Reactívalo de vez en cuando para instalar parches críticos.' -ForegroundColor Yellow
        Write-Host '  Microsoft Store no podrá descargar apps en este modo (usa el modo compatible con la Tienda).' -ForegroundColor Yellow
    }
    if ($script:IsDryRun) {
        if ($KeepStore) { Write-Log 'wuauserv quedará en Manual (para Microsoft Store); el resto se desactiva.' DRY }
        Write-Log "Guardar estado original en $script:WUStatePath" DRY
        Write-Log "Crear $script:WUEnforcerPath (carpeta solo para SYSTEM/Administradores)" DRY
        Write-Log "Políticas: NoAutoUpdate=1, AUOptions=1, DisableOSUpgrade=1" DRY
        Write-Log "Como SYSTEM: desactivar $($script:WUServices -join ', ') y las tareas de $($script:WUTaskFolders -join ', ')" DRY
        Write-Log "Tarea guardiana '$script:WUTaskPath$script:WUGuardTask': al arrancar y cada hora" DRY
        Write-Log 'Defender: firmas desde MMPC' DRY
        return
    }
    if (-not (Confirm-Action '¿Desactivar Windows Update de forma persistente?')) { return }

    New-SystemRestorePoint -Description 'WinTurbo: antes de desactivar Windows Update'
    try {
        Write-Log 'Guardando el estado original de los servicios y tareas...' STEP
        Initialize-WUSecureDir
        Save-WUOriginalState

        Start-Journal -Label 'Windows Update: bloqueo'
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DisableOSUpgrade' 1
        Save-Journal

        try { Set-MpPreference -SignatureFallbackOrder 'MMPC|MicrosoftUpdateServer' -ErrorAction Stop } catch {
            Write-Log 'Defender no está activo (¿otro antivirus?); se omite su configuración.'
        }

        Write-Log 'Aplicando el bloqueo como SYSTEM (servicios protegidos y tareas de UpdateOrchestrator/WaaSMedic)...' STEP
        Register-WUGuard -Mode $guardMode
        Start-ScheduledTask -TaskPath $script:WUTaskPath -TaskName $script:WUGuardTask
        $result = Wait-ScheduledTaskRun -TaskPath $script:WUTaskPath -TaskName $script:WUGuardTask
        if ($null -eq $result) { Write-Log 'El bloqueo tarda más de lo normal; se verificará igualmente.' WARN }
    } catch {
        Write-Log "Error: $($_.Exception.Message)" ERROR
    }

    Write-Title 'Verificación real del estado'
    $st = Show-WUBlockStatus
    switch ($st.Estado) {
        'BLOQUEADO' {
            Write-Log 'Windows Update está bloqueado y la tarea guardiana lo mantendrá así tras reinicios y reparaciones.' OK
            if ($KeepStore) { Write-Log 'Comprueba la Tienda instalando o actualizando una app: debe funcionar.' }
        }
        default     { Write-Log 'El bloqueo no es completo. Revisa el registro: ' WARN; Write-Log (Join-Path $script:WUSecureDir 'bloqueo-wu.log') }
    }
    $medic = $st.Detalle | Where-Object { $_.Elemento -eq 'Servicio WaaSMedicSvc' }
    if ($medic -and -not $medic.Bloqueado) {
        Write-Log 'Windows protege el servicio Medic en esta versión; su tarea está desactivada y la guardiana revierte cualquier reparación cada hora.' WARN
    }
    Write-Log 'Reinicia el equipo para completar el bloqueo.' WARN
}

function Enable-WindowsUpdateFull {
    Write-Title 'Reactivar Windows Update'
    if ($script:IsDryRun) {
        Write-Log "Eliminar la tarea guardiana y restaurar como SYSTEM servicios y tareas desde $script:WUStatePath" DRY
        Write-Log 'Quitar políticas de bloqueo (WinTurbo, WinUtil y similares)' DRY
        return
    }
    if (-not (Confirm-Action '¿Reactivar Windows Update?')) { return }
    try {
        Unregister-ScheduledTask -TaskPath $script:WUTaskPath -TaskName $script:WUGuardTask -Confirm:$false -ErrorAction SilentlyContinue
        if (-not (Test-Path $script:WUEnforcerPath)) { Initialize-WUSecureDir }
        Write-Log 'Restaurando servicios y tareas como SYSTEM...' STEP
        Invoke-WUEnforcerOnce -Mode Unblock

        # También limpia los bloqueos que dejan WinUtil y otras herramientas.
        Start-Journal -Label 'Windows Update: reactivar'
        $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        foreach ($n in 'NoAutoUpdate', 'AUOptions', 'UseWUServer') { Remove-RegValue "$wu\AU" $n }
        foreach ($n in 'DisableOSUpgrade', 'DisableWindowsUpdateAccess', 'DoNotConnectToWindowsUpdateInternetLocations', 'SetDisableUXWUAccess') { Remove-RegValue $wu $n }
        $wuServer = (Get-ItemProperty -Path $wu -Name WUServer -ErrorAction SilentlyContinue).WUServer
        if ($wuServer -match 'localhost|127\.0\.0\.1') { Remove-RegValue $wu 'WUServer'; Remove-RegValue $wu 'WUStatusServer' }
        Remove-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode'
        $exp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        if ((Get-ItemProperty -Path $exp -Name SettingsPageVisibility -ErrorAction SilentlyContinue).SettingsPageVisibility -match 'windowsupdate') {
            Remove-RegValue $exp 'SettingsPageVisibility'
        }
        Save-Journal
        # BITS lo desactiva WinUtil; se devuelve a manual si está deshabilitado.
        if ((Get-ServiceStartMode -Name 'BITS') -eq 'Disabled') { & sc.exe config BITS start= demand | Out-Null }

        $fallback = 'MicrosoftUpdateServer|MMPC'
        if (Test-Path $script:WUStatePath) {
            $state = Get-Content $script:WUStatePath -Raw | ConvertFrom-Json
            if ($state.DefenderFallback) { $fallback = $state.DefenderFallback }
        }
        try { Set-MpPreference -SignatureFallbackOrder $fallback -ErrorAction Stop } catch { }
    } catch {
        Write-Log "Error: $($_.Exception.Message)" ERROR
    }

    Write-Title 'Verificación real del estado'
    $st = Show-WUBlockStatus
    if ($st.Estado -eq 'ACTIVO') {
        Write-Log 'Windows Update está activo de nuevo.' OK
        Remove-Item -Path $script:WUStatePath -Force -ErrorAction SilentlyContinue
        # En modo silencioso (interfaz o -Silent) no se abre ninguna ventana sin que nadie lo pida.
        if (-not $Silent -and (Confirm-Action '¿Abrir Windows Update para buscar actualizaciones ahora?')) { Start-Process 'ms-settings:windowsupdate' }
    } else {
        Write-Log "Estado: $($st.Estado). Revisa $(Join-Path $script:WUSecureDir 'bloqueo-wu.log') y reinicia." WARN
    }
}

#endregion

#region ===================== Windows Update =====================

$script:WUPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

function Set-WUStableMode {
    $wu = $script:WUPolicyKey
    Start-Journal -Label 'Windows Update: modo estable'
    Set-RegValue $wu 'DeferFeatureUpdates' 1
    Set-RegValue $wu 'DeferFeatureUpdatesPeriodInDays' 365
    Set-RegValue $wu 'DeferQualityUpdates' 1
    Set-RegValue $wu 'DeferQualityUpdatesPeriodInDays' 4
    Set-RegValue "$wu\AU" 'NoAutoRebootWithLoggedOnUsers' 1
    Save-Journal
    Write-Log 'Modo estable aplicado.' OK
}

function Set-WUNoDrivers {
    Start-Journal -Label 'Windows Update: sin drivers'
    Set-RegValue $script:WUPolicyKey 'ExcludeWUDriversInQualityUpdate' 1
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
    Save-Journal
    Write-Log 'Windows Update ya no instalará drivers. Actualízalos desde la web del fabricante.' OK
}

function Reset-WUPolicies {
    $wu = $script:WUPolicyKey
    Start-Journal -Label 'Windows Update: por defecto'
    foreach ($n in 'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays', 'DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays', 'ExcludeWUDriversInQualityUpdate') {
        Remove-RegValue $wu $n
    }
    Remove-RegValue "$wu\AU" 'NoAutoRebootWithLoggedOnUsers'
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 1
    Save-Journal
    Write-Log 'Windows Update vuelve a su comportamiento por defecto.' OK
}

function Show-UpdateMenu {
    while ($true) {
        Clear-Host
        Write-Title 'Windows Update'
        $wuState = (Get-WUBlockStatus).Estado
        $stateColor = @{ BLOQUEADO = 'Red'; PARCIAL = 'Yellow'; ACTIVO = 'Green' }[$wuState]
        Write-Host "  Estado actual de Windows Update: $wuState" -ForegroundColor $stateColor
        if ($script:HW.IsHome) { Write-Log 'Edición Home: Windows ignora los aplazamientos (opciones 1-2); el bloqueo (5) sí funciona.' WARN }
        Write-Host '    1. Modo estable: seguridad a los 4 días, versiones nuevas de Windows 1 año después'
        Write-Host '       y sin reinicios automáticos con la sesión abierta (recomendado)'
        Write-Host '    2. No instalar drivers por Windows Update (útil si rompe tu driver de GPU/audio)'
        Write-Host '    3. Restaurar configuración por defecto de Windows Update'
        Write-Host '    4. Abrir Windows Update'
        Write-Host '    5. DESACTIVAR Windows Update por completo (persistente, no se reactiva solo)' -ForegroundColor Red
        Write-Host '    6. Reactivar Windows Update (también deshace bloqueos de WinUtil y similares)' -ForegroundColor Green
        Write-Host '    7. Ver el estado detallado del bloqueo'
        Write-Host '    8. Desactivar Windows Update MANTENIENDO Microsoft Store (recomendado si usas la Tienda)' -ForegroundColor Yellow
        Write-Host '    0. Volver'
        switch (Read-Host '  Opción') {
            '1' { Set-WUStableMode; Wait-Enter }
            '2' { Set-WUNoDrivers; Wait-Enter }
            '3' { Reset-WUPolicies; Wait-Enter }
            '4' { Start-Process 'ms-settings:windowsupdate' }
            '5' { Disable-WindowsUpdateFull; Wait-Enter }
            '6' { Enable-WindowsUpdateFull; Wait-Enter }
            '7' { Write-Title 'Estado del bloqueo de Windows Update'; [void](Show-WUBlockStatus); Wait-Enter }
            '8' { Disable-WindowsUpdateFull -KeepStore; Wait-Enter }
            '0' { return }
        }
    }
}

#endregion

#region ===================== Aplicaciones (winget) =====================

$script:WingetApps = @(
    @{ Cat = 'Navegadores';  Name = 'Mozilla Firefox';              Id = 'Mozilla.Firefox' }
    @{ Cat = 'Navegadores';  Name = 'Google Chrome';                Id = 'Google.Chrome' }
    @{ Cat = 'Navegadores';  Name = 'Brave';                        Id = 'Brave.Brave' }
    @{ Cat = 'Utilidades';   Name = '7-Zip';                        Id = '7zip.7zip' }
    @{ Cat = 'Utilidades';   Name = 'Everything (búsqueda instantánea)'; Id = 'voidtools.Everything' }
    @{ Cat = 'Utilidades';   Name = 'Microsoft PowerToys';          Id = 'Microsoft.PowerToys' }
    @{ Cat = 'Utilidades';   Name = 'Notepad++';                    Id = 'Notepad++.Notepad++' }
    @{ Cat = 'Utilidades';   Name = 'ShareX (capturas)';            Id = 'ShareX.ShareX' }
    @{ Cat = 'Utilidades';   Name = 'SumatraPDF';                   Id = 'SumatraPDF.SumatraPDF' }
    @{ Cat = 'Mantenimiento'; Name = 'Sysinternals Autoruns';       Id = 'Microsoft.Sysinternals.Autoruns' }
    @{ Cat = 'Mantenimiento'; Name = 'Sysinternals Process Explorer'; Id = 'Microsoft.Sysinternals.ProcessExplorer' }
    @{ Cat = 'Mantenimiento'; Name = 'Bulk Crap Uninstaller';       Id = 'Klocman.BulkCrapUninstaller' }
    @{ Cat = 'Mantenimiento'; Name = 'WizTree (uso de disco)';      Id = 'AntibodySoftware.WizTree' }
    @{ Cat = 'Mantenimiento'; Name = 'CrystalDiskInfo (salud disco)'; Id = 'CrystalDewWorld.CrystalDiskInfo' }
    @{ Cat = 'Mantenimiento'; Name = 'HWiNFO (sensores)';           Id = 'REALiX.HWiNFO' }
    @{ Cat = 'Mantenimiento'; Name = 'O&O ShutUp10++ (privacidad)'; Id = 'OO-Software.ShutUp10' }
    @{ Cat = 'Multimedia';   Name = 'VLC';                          Id = 'VideoLAN.VLC' }
    @{ Cat = 'Multimedia';   Name = 'OBS Studio';                   Id = 'OBSProject.OBSStudio' }
    @{ Cat = 'Juegos';       Name = 'Steam';                        Id = 'Valve.Steam' }
    @{ Cat = 'Juegos';       Name = 'Discord';                      Id = 'Discord.Discord' }
    @{ Cat = 'Desarrollo';   Name = 'Visual Studio Code';           Id = 'Microsoft.VisualStudioCode' }
    @{ Cat = 'Desarrollo';   Name = 'Git';                          Id = 'Git.Git' }
    @{ Cat = 'Desarrollo';   Name = 'PowerShell 7';                 Id = 'Microsoft.PowerShell' }
    @{ Cat = 'Desarrollo';   Name = 'Windows Terminal';             Id = 'Microsoft.WindowsTerminal' }
    @{ Cat = 'Runtimes';     Name = 'Visual C++ 2015-2022 x64';     Id = 'Microsoft.VCRedist.2015+.x64' }
    @{ Cat = 'Runtimes';     Name = '.NET Desktop Runtime 8';       Id = 'Microsoft.DotNet.DesktopRuntime.8' }
    @{ Cat = 'Runtimes';     Name = 'DirectX End-User Runtime';     Id = 'Microsoft.DirectX' }
)

function Show-AppsMenu {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Log 'winget no está disponible. Usa Reparación > Reparar winget.' WARN
        Wait-Enter; return
    }
    while ($true) {
        Clear-Host
        Write-Title 'Instalar y actualizar aplicaciones (winget)'
        $lastCat = ''
        for ($i = 0; $i -lt $script:WingetApps.Count; $i++) {
            $a = $script:WingetApps[$i]
            if ($a.Cat -ne $lastCat) { Write-Host ("  == $($a.Cat) ==") -ForegroundColor Cyan; $lastCat = $a.Cat }
            Write-Host ('   {0,2}. {1}' -f ($i + 1), $a.Name)
        }
        Write-Host ''
        Write-Host '  Números = instalar (ej. 1,4,10-12)   U = actualizar TODO lo instalado   0 = volver'
        $c = Read-Host '  Opción'
        if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
        if ($c -match '^[uU]$') {
            if ($script:IsDryRun) { Write-Log 'winget upgrade --all' DRY }
            else { & winget.exe upgrade --all --silent --accept-source-agreements --accept-package-agreements --include-unknown }
            Wait-Enter; continue
        }
        foreach ($s in (ConvertFrom-Selection -Text $c -Max $script:WingetApps.Count)) {
            $a = $script:WingetApps[$s - 1]
            if ($script:IsDryRun) { Write-Log "winget install $($a.Id)" DRY; continue }
            Write-Log "Instalando $($a.Name)..." STEP
            & winget.exe install --id $a.Id -e --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) { Write-Log "$($a.Name) instalado" OK } else { Write-Log "$($a.Name): winget devolvió $LASTEXITCODE (puede que ya estuviera instalado)" WARN }
        }
        Wait-Enter
    }
}

#endregion

#region ===================== Informe =====================

function Show-Report {
    Clear-Host
    Write-Title 'Informe del sistema'
    $hw = $script:HW
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("WinTurbo $script:Version - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $lines.Add("Sistema : $($hw.OSName) $($hw.Version) (build $($hw.Build), $($hw.Edition))")
    $lines.Add("CPU     : $($hw.CPU) - $($hw.Cores) núcleos / $($hw.Threads) hilos")
    $lines.Add("RAM     : $($hw.RamGB) GB")
    $lines.Add("GPU     : $($hw.GPU)")
    $lines.Add("Disco   : $($hw.SystemDisk)   Tipo de equipo: $(if ($hw.IsLaptop) { 'Portátil' } else { 'Sobremesa' })$(if ($hw.IsVM) { ' (máquina virtual)' })")
    $lines.Add('')
    foreach ($l in $lines) { Write-Host "  $l" }

    $now = Get-HealthSnapshot
    $basePath = Join-Path $script:DataDir 'linea-base.json'
    if (Test-Path $basePath) {
        $base = Get-Content $basePath -Raw | ConvertFrom-Json
        Write-Host "  Comparación con la línea base del $($base.Fecha):" -ForegroundColor White
        Show-SnapshotComparison -Before $base -After $now -BeforeLabel 'Línea base' -AfterLabel 'Ahora'
    } else {
        Write-Host '  Estado actual:' -ForegroundColor White
        $now | Format-List | Out-String | Write-Host
    }

    Write-Host ''
    Write-Host '  Ajustes aplicados por categoría:' -ForegroundColor White
    foreach ($cat in $script:Categories) {
        $ts = @($script:Tweaks | Where-Object { $_.Category -eq $cat -and $_.Registry })
        $applied = @($ts | Where-Object { Test-TweakState $_ }).Count
        Write-Host ('   {0,-22} {1}/{2}' -f $cat, $applied, $ts.Count)
        $lines.Add(('{0,-22} {1}/{2} ajustes aplicados' -f $cat, $applied, $ts.Count))
    }

    $tips = New-Object System.Collections.Generic.List[string]
    if ($now.LibreSistemaGB -lt 20) { $tips.Add('Poco espacio libre en el disco del sistema: usa Limpieza y WizTree.') }
    if ($now.AppsInicio -gt 8)      { $tips.Add("Tienes $($now.AppsInicio) apps de inicio activas: revisa el menú Programas de inicio.") }
    if ($hw.SystemDisk -eq 'HDD')    { $tips.Add('El sistema está en un disco duro mecánico: cambiar a SSD es la mejora más grande posible.') }
    if ($hw.RamGB -lt 8)             { $tips.Add('Menos de 8 GB de RAM: usa el preset Equilibrado (incluye efectos visuales ligeros) y evita muchas pestañas.') }
    if ($now.HorasEncendido -gt 168) { $tips.Add('Más de 7 días sin reiniciar: reiniciar libera memoria y aplica actualizaciones.') }
    if ($tips.Count -gt 0) {
        Write-Host ''
        Write-Host '  Recomendaciones:' -ForegroundColor Yellow
        foreach ($t in $tips) { Write-Host "   - $t" -ForegroundColor Yellow; $lines.Add("Recomendación: $t") }
    }

    $file = Join-Path $script:LogDir ("informe-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    ($lines + ($now | Format-List | Out-String)) | Set-Content -Path $file -Encoding UTF8
    Write-Host ''
    Write-Log "Informe guardado en: $file"
}

#endregion

#region ===================== Menú principal =====================

function Show-Header {
    Clear-Host
    $hw = $script:HW
    Write-Host ''
    Write-Host '   ==============================================' -ForegroundColor Cyan
    Write-Host '     W I N T U R B O   -   Optimizador de Windows' -ForegroundColor Cyan
    Write-Host '   ==============================================' -ForegroundColor Cyan
    Write-Host "   v$script:Version  |  $($hw.OSName) $($hw.Version)" -ForegroundColor DarkGray
    Write-Host ("   {0} | {1} GB RAM | disco {2} | {3}" -f $hw.CPU, $hw.RamGB, $hw.SystemDisk, $(if ($hw.IsLaptop) { 'Portátil' } else { 'Sobremesa' })) -ForegroundColor DarkGray
    if ($script:IsDryRun) { Write-Host '   MODO SIMULACIÓN ACTIVO: no se cambiará nada' -ForegroundColor Cyan }
    if (-not $script:UserMatch) {
        Write-Host '   AVISO: ejecutas como otro administrador; los ajustes de usuario se aplicarán a ESA cuenta.' -ForegroundColor Yellow
    }
}

function Show-MainMenu {
    while ($true) {
        Show-Header
        Write-Host ''
        Write-Host '    1. Optimización rápida recomendada (Equilibrado + limpieza)' -ForegroundColor Green
        Write-Host '    2. Aplicar un preset (Básico / Equilibrado / Gaming / Máximo)'
        Write-Host '    3. Ajustes personalizados (elegir uno a uno)'
        Write-Host '    4. Quitar bloatware y apps preinstaladas'
        Write-Host '    5. Programas de inicio'
        Write-Host '    6. Limpieza de disco'
        Write-Host '    7. Reparación y mantenimiento'
        Write-Host '    8. Red y DNS'
        Write-Host '    9. Windows Update'
        Write-Host '   10. Instalar / actualizar aplicaciones (winget)'
        Write-Host '   11. Informe y comparación antes/después'
        Write-Host '   12. Deshacer cambios' -ForegroundColor Yellow
        Write-Host ''
        Write-Host ("    S. Modo simulación: {0}" -f $(if ($script:IsDryRun) { 'ACTIVADO' } else { 'desactivado' }))
        Write-Host '    0. Salir'
        $c = Read-Host '  Elige una opción'
        switch ($c) {
            '1' {
                Invoke-TweakSet -Ids (Get-PresetIds 'Equilibrado') -Label 'Optimización rápida'
                Write-Title 'Limpieza recomendada'
                if (Confirm-Action '¿Limpiar temporales, caché de Windows Update, de distribución e informes de error?') {
                    Invoke-Cleanup -Indexes @(1, 2, 3, 4)
                }
                Wait-Enter
            }
            '2' {
                Clear-Host
                Write-Title 'Presets'
                $names = @($script:PresetInfo.Keys)
                for ($i = 0; $i -lt $names.Count; $i++) {
                    $count = @(Get-PresetIds $names[$i]).Count
                    Write-Host ('    {0}. {1,-12} ({2} ajustes) {3}' -f ($i + 1), $names[$i], $count, $script:PresetInfo[$names[$i]])
                }
                Write-Host '    Escribe el número seguido de V para revisarlo antes (ej. 3V)'
                $p = Read-Host '  Preset'
                if ($p -match '^([1-4])([vV]?)$') {
                    $name = $names[[int]$Matches[1] - 1]
                    if ($Matches[2]) { Show-CustomTweaksMenu -Preselect (Get-PresetIds $name) }
                    else { Invoke-TweakSet -Ids (Get-PresetIds $name) -Label "Preset $name"; Wait-Enter }
                }
            }
            '3'  { Show-CustomTweaksMenu }
            '4'  { Show-BloatwareMenu }
            '5'  { Show-StartupMenu }
            '6'  { Show-CleanupMenu }
            '7'  { Show-RepairMenu }
            '8'  { Show-DnsMenu }
            '9'  { Show-UpdateMenu }
            '10' { Show-AppsMenu }
            '11' { Show-Report; Wait-Enter }
            '12' { Show-UndoMenu }
            { $_ -match '^[sS]$' } { $script:IsDryRun = -not $script:IsDryRun }
            '0'  { return }
        }
    }
}

#endregion

#region ===================== Interfaz gráfica: ventana, estilos y motor =====================

$script:GuiXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinTurbo" Width="1360" Height="860" MinWidth="960" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="#E9EBEE" FontFamily="Segoe UI" FontSize="14"
        Foreground="#16181D" UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
    <Style x:Key="BtnBase" TargetType="Button">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="Foreground" Value="#16181D"/>
      <Setter Property="BorderBrush" Value="#A9AEB8"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="Ring" CornerRadius="8" BorderThickness="2" BorderBrush="Transparent" Margin="-3"/>
              <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Ring" Property="BorderBrush" Value="#1F6FEB"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#F1F3F5"/></Trigger>
        <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="#E4E7EB"/></Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="#F1F3F5"/><Setter Property="Foreground" Value="#5B616B"/><Setter Property="BorderBrush" Value="#D5D8DE"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="Button" BasedOn="{StaticResource BtnBase}"/>
    <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="#1F6FEB"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#1F6FEB"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#1A5FCC"/></Trigger>
        <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="#164FA8"/></Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="#E9EBEE"/><Setter Property="Foreground" Value="#5B616B"/><Setter Property="BorderBrush" Value="#D5D8DE"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Foreground" Value="#B42318"/>
      <Setter Property="BorderBrush" Value="#C42B2B"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#FDECEC"/></Trigger>
        <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="#F9D7D7"/></Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="#F1F3F5"/><Setter Property="Foreground" Value="#5B616B"/><Setter Property="BorderBrush" Value="#D5D8DE"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="NavItem" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#C9CCD3"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="GroupName" Value="Nav"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Margin" Value="0,0,0,2"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bg" Background="Transparent" CornerRadius="6" Padding="8,8,10,8" BorderThickness="1" BorderBrush="Transparent">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="6"/><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="Pill" Width="3" Height="16" CornerRadius="1.5" Background="#1F6FEB" Visibility="Hidden" HorizontalAlignment="Left"/>
                <TextBlock Grid.Column="1" Text="{TemplateBinding Tag}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" VerticalAlignment="Center"/>
                <ContentPresenter Grid.Column="2" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bg" Property="Background" Value="#22262D"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bg" Property="Background" Value="#2B2F37"/>
                <Setter TargetName="Pill" Property="Visibility" Value="Visible"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bg" Property="BorderBrush" Value="#1F6FEB"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="18" Height="18" CornerRadius="3" BorderThickness="1.5" BorderBrush="#7D828C" Background="#FFFFFF" VerticalAlignment="Center">
                <Path x:Name="Mark" Data="M 3.5,8.5 L 7,12 L 13.5,4.5" Stroke="#FFFFFF" StrokeThickness="2.2" Visibility="Collapsed"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
              </Border>
              <ContentPresenter x:Name="Cp" Margin="10,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="Content" Value="{x:Null}"><Setter TargetName="Cp" Property="Margin" Value="0"/></Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="#16181D"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="#1F6FEB"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="#1F6FEB"/>
                <Setter TargetName="Mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="#0B3D91"/><Setter TargetName="Box" Property="BorderThickness" Value="2.5"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Grid Width="18" Height="18" VerticalAlignment="Center">
                <Ellipse x:Name="Ring" Stroke="#7D828C" StrokeThickness="1.5" Fill="#FFFFFF"/>
                <Ellipse x:Name="Dot" Width="8" Height="8" Fill="#FFFFFF" Visibility="Collapsed"/>
              </Grid>
              <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ring" Property="Stroke" Value="#16181D"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Ring" Property="Fill" Value="#1F6FEB"/><Setter TargetName="Ring" Property="Stroke" Value="#1F6FEB"/>
                <Setter TargetName="Dot" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Ring" Property="Stroke" Value="#0B3D91"/><Setter TargetName="Ring" Property="StrokeThickness" Value="2.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="RailSwitch" TargetType="CheckBox">
      <Setter Property="Foreground" Value="#C9CCD3"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="Bg" Background="Transparent" CornerRadius="6" Padding="10,8" BorderThickness="1" BorderBrush="Transparent">
              <DockPanel>
                <Border x:Name="Track" DockPanel.Dock="Right" Width="38" Height="20" CornerRadius="10" Background="#2B2F37" BorderBrush="#6B717C" BorderThickness="1">
                  <Ellipse x:Name="Knob" Width="12" Height="12" Fill="#C9CCD3" HorizontalAlignment="Left" Margin="4,0,0,0"/>
                </Border>
                <ContentPresenter VerticalAlignment="Center"/>
              </DockPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bg" Property="Background" Value="#22262D"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#1F6FEB"/><Setter TargetName="Track" Property="BorderBrush" Value="#1F6FEB"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/><Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
                <Setter TargetName="Knob" Property="Fill" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bg" Property="BorderBrush" Value="#1F6FEB"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="PART_Track" Background="#2B2F37" CornerRadius="3"/>
              <Border x:Name="PART_Indicator" Background="#1F6FEB" CornerRadius="3" HorizontalAlignment="Left"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border Background="#9EA4AE" CornerRadius="4" Margin="2"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track">
                  <Track.Thumb>
                    <Thumb>
                      <Thumb.Template>
                        <ControlTemplate TargetType="Thumb"><Border Background="#9EA4AE" CornerRadius="4" Margin="2"/></ControlTemplate>
                      </Thumb.Template>
                    </Thumb>
                  </Track.Thumb>
                </Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="232"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="150"/></Grid.RowDefinitions>
    <Border Grid.RowSpan="2" Background="#16181D">
      <DockPanel Margin="12,20,12,14">
        <StackPanel x:Name="BrandHost" DockPanel.Dock="Top" Orientation="Horizontal" Margin="8,0,0,24"/>
        <StackPanel DockPanel.Dock="Bottom">
          <Border Height="1" Background="#2B2F37" Margin="0,0,0,10"/>
          <CheckBox x:Name="SimToggle" Style="{StaticResource RailSwitch}" Content="Modo simulación"
                    ToolTip="Muestra lo que se haría sin cambiar nada en el equipo"/>
          <TextBlock x:Name="RailInfo" Foreground="#8A8F99" FontSize="12" Margin="10,10,4,0" TextWrapping="Wrap"/>
        </StackPanel>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Focusable="False">
          <StackPanel x:Name="NavHost"/>
        </ScrollViewer>
      </DockPanel>
    </Border>
    <ContentControl x:Name="PageHost" Grid.Column="1" Focusable="False"/>
    <Border Grid.Row="1" Grid.Column="1" Background="#1C1F25">
      <Grid Margin="24,12,24,12">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="340"/></Grid.ColumnDefinitions>
        <RichTextBox x:Name="LogBox" IsReadOnly="True" Background="Transparent" BorderThickness="0" Foreground="#C9CCD3"
                     FontFamily="Consolas" FontSize="12.5" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                     AutomationProperties.Name="Registro de actividad"/>
        <StackPanel Grid.Column="1" Margin="24,2,0,0">
          <TextBlock x:Name="JobTitle" Foreground="#F0F3F6" FontWeight="SemiBold" Text="Sin tareas en curso" TextWrapping="Wrap" MaxHeight="40" TextTrimming="CharacterEllipsis"/>
          <ProgressBar x:Name="JobProgress" Margin="0,10,0,8" Maximum="100" Value="0"/>
          <TextBlock x:Name="JobStatus" Foreground="#A9AEB8" FontSize="12.5" TextWrapping="Wrap" MaxHeight="52"/>
          <TextBlock x:Name="JobBackup" Foreground="#8A8F99" FontSize="12" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$script:Gui = @{}
$script:GuiJobs = New-Object System.Collections.ArrayList
$script:GuiBusy = $false
$script:GuiSel = @{}
$script:GuiPreset = 'Equilibrado'
$script:PresetDisplay = @{ Basico = 'Básico'; Equilibrado = 'Equilibrado'; Gaming = 'Gaming'; Maximo = 'Máximo' }

# Tonos de cinta con contraste AA para letra pequeña (texto blanco salvo en ámbar).
$script:TapeColors = @{
    Blue  = @('#1F6FEB', '#FFFFFF'); Green = @('#1A7F37', '#FFFFFF'); Amber = @('#D29922', '#16181D')
    Red   = @('#C42B2B', '#FFFFFF'); Black = @('#2B2F37', '#FFFFFF'); Grey  = @('#6B717C', '#FFFFFF')
}
$script:LogColors = @{
    Green = '#56D364'; Yellow = '#E3B341'; Red = '#FF7B72'; Cyan = '#79C0FF'; White = '#F0F3F6'
    Gray = '#C9CCD3'; DarkGray = '#8A8F99'; DarkYellow = '#D29922'; DarkCyan = '#58A6FF'
}

function ConvertTo-GuiBrush {
    param([string]$Hex)
    $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $b.Freeze()
    return $b
}

function New-GuiText {
    param([string]$Text, [double]$Size = 14, [string]$Weight = 'Normal', [string]$Color = '#16181D', [switch]$Wrap, [switch]$Tabular)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.FontWeight = $Weight
    $t.Foreground = ConvertTo-GuiBrush $Color
    $t.VerticalAlignment = 'Center'
    if ($Wrap) { $t.TextWrapping = 'Wrap' } else { $t.TextTrimming = 'CharacterEllipsis' }
    if ($Tabular) { [System.Windows.Documents.Typography]::SetNumeralAlignment($t, 'Tabular') }
    return $t
}

function New-GuiTape {
    # La firma visual: cinta rotuladora en relieve. Solo marca estado o riesgo, nunca decora.
    param([string]$Text, [string]$Color = 'Blue', [double]$Size = 11)
    $c = $script:TapeColors[$Color]
    $b = New-Object System.Windows.Controls.Border
    $b.Background = ConvertTo-GuiBrush $c[0]
    $b.BorderBrush = ConvertTo-GuiBrush '#40FFFFFF'
    $b.BorderThickness = '0,1,0,0'
    $b.CornerRadius = 2
    $b.Padding = '7,2,7,2'
    $b.HorizontalAlignment = 'Left'
    $b.VerticalAlignment = 'Center'
    $t = New-Object System.Windows.Controls.TextBlock
    # WPF no tiene espaciado entre letras: se intercala un espacio fino (U+200A).
    $t.Text = ($Text.ToUpper().ToCharArray() -join [char]0x200A)
    $t.FontFamily = 'Bahnschrift SemiBold Condensed, Bahnschrift, Segoe UI'
    $t.FontStretch = 'Condensed'
    $t.FontWeight = 'SemiBold'
    $t.FontSize = $Size
    $t.Foreground = ConvertTo-GuiBrush $c[1]
    # Una cinta nunca se sale de su contenedor: si no cabe, se recorta con puntos suspensivos.
    $t.TextTrimming = 'CharacterEllipsis'
    $b.Child = $t
    [System.Windows.Automation.AutomationProperties]::SetName($b, $Text)
    return $b
}

function New-GuiButton {
    param([string]$Text, [string]$Kind = 'Secondary', [scriptblock]$OnClick, $Tag, [string]$ToolTip)
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $Text
    if ($Kind -eq 'Primary') { $btn.Style = $script:Gui.Window.FindResource('BtnPrimary') }
    elseif ($Kind -eq 'Danger') { $btn.Style = $script:Gui.Window.FindResource('BtnDanger') }
    $btn.Margin = '0,0,10,0'
    if ($null -ne $Tag) { $btn.Tag = $Tag }
    if ($ToolTip) { $btn.ToolTip = $ToolTip }
    if ($OnClick) { $btn.Add_Click($OnClick) }
    return $btn
}

function New-GuiSurface {
    param([string]$Padding = '20,16')
    $b = New-Object System.Windows.Controls.Border
    $b.Background = ConvertTo-GuiBrush '#FFFFFF'
    $b.BorderBrush = ConvertTo-GuiBrush '#D5D8DE'
    $b.BorderThickness = 1
    $b.CornerRadius = 8
    $b.Padding = $Padding
    return $b
}

function New-GuiHeading {
    param([string]$Text, [string]$Margin = '0,0,0,10')
    $t = New-GuiText -Text $Text -Size 15 -Weight 'SemiBold'
    $t.Margin = $Margin
    return $t
}

function New-GuiRow {
    # Grid con columnas definidas por anchos: '*', 'Auto' o un número.
    param([string[]]$Columns)
    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in $Columns) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = New-Object System.Windows.GridLength 1, 'Star' }
        elseif ($w -match '^(\d+)\*$') { $cd.Width = New-Object System.Windows.GridLength ([double]$Matches[1]), 'Star' }
        elseif ($w -eq 'Auto') { $cd.Width = [System.Windows.GridLength]::Auto }
        else { $cd.Width = New-Object System.Windows.GridLength ([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    return $g
}

function Add-GuiCell {
    param($Grid, $Element, [int]$Column, [int]$Row = 0)
    [System.Windows.Controls.Grid]::SetColumn($Element, $Column)
    [System.Windows.Controls.Grid]::SetRow($Element, $Row)
    [void]$Grid.Children.Add($Element)
}

function New-GuiPage {
    # Estructura común: encabezado (título, subtítulo, acciones) y cuerpo desplazable.
    param([string]$Title, [string]$Subtitle, [object[]]$Actions = @())
    $root = New-Object System.Windows.Controls.DockPanel
    $head = New-GuiRow -Columns @('*', 'Auto')
    $head.Margin = '32,24,32,16'
    [System.Windows.Controls.DockPanel]::SetDock($head, 'Top')
    $titles = New-Object System.Windows.Controls.StackPanel
    $titles.Children.Add((New-GuiText -Text $Title -Size 24 -Weight 'SemiBold')) | Out-Null
    if ($Subtitle) {
        $s = New-GuiText -Text $Subtitle -Size 13.5 -Color '#565C67' -Wrap
        $s.Margin = '0,4,0,0'
        $titles.Children.Add($s) | Out-Null
    }
    if ($script:IsDryRun) {
        $sim = New-GuiTape -Text 'Modo simulación · no se cambiará nada' -Color 'Blue'
        $sim.Margin = '0,10,0,0'
        $titles.Children.Add($sim) | Out-Null
    }
    Add-GuiCell $head $titles 0
    $acts = New-Object System.Windows.Controls.StackPanel
    $acts.Orientation = 'Horizontal'
    $acts.VerticalAlignment = 'Top'
    foreach ($a in $Actions) { $acts.Children.Add($a) | Out-Null }
    if ($acts.Children.Count -gt 0) { $acts.Children[$acts.Children.Count - 1].Margin = '0' }
    Add-GuiCell $head $acts 1
    $root.Children.Add($head) | Out-Null
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.HorizontalScrollBarVisibility = 'Disabled'
    $scroll.Focusable = $false
    $body = New-Object System.Windows.Controls.StackPanel
    $body.Margin = '32,0,32,28'
    $scroll.Content = $body
    $root.Children.Add($scroll) | Out-Null
    return [pscustomobject]@{ Root = $root; Body = $body; Head = $head }
}

function Show-GuiConfirm {
    param([string]$Text, [string]$Title = 'WinTurbo', [string]$Icon = 'Question')
    if ($script:IsDryRun) { $Text += "`n`nModo simulación: solo se mostrará lo que se haría." }
    $r = [System.Windows.MessageBox]::Show($script:Gui.Window, $Text, $Title, 'YesNo', $Icon)
    return ($r -eq 'Yes')
}

function Show-GuiInfo {
    param([string]$Text, [string]$Icon = 'Information')
    [void][System.Windows.MessageBox]::Show($script:Gui.Window, $Text, 'WinTurbo', 'OK', $Icon)
}

function Add-GuiLog {
    param([string]$Text, [string]$Color = 'Gray')
    $doc = $script:Gui.LogBox.Document
    $p = New-Object System.Windows.Documents.Paragraph
    $p.Margin = '0'
    $run = New-Object System.Windows.Documents.Run $Text
    $hex = $script:LogColors[$Color]
    if (-not $hex) { $hex = '#C9CCD3' }
    $run.Foreground = ConvertTo-GuiBrush $hex
    $p.Inlines.Add($run)
    $doc.Blocks.Add($p)
    while ($doc.Blocks.Count -gt 600) { $doc.Blocks.Remove($doc.Blocks.FirstBlock) }
    $script:Gui.LogBox.ScrollToEnd()
}

function Format-GuiDuration {
    param([int]$Seconds)
    if ($Seconds -lt 60) { return "≈ $Seconds s" }
    return ('≈ {0} min' -f [math]::Ceiling($Seconds / 60))
}

function Start-GuiJob {
    # Ejecuta funciones de WinTurbo en un hilo aparte para que la ventana no se congele.
    # $Quiet = tarea de solo lectura (cargar datos): no bloquea otras acciones ni escribe en el registro.
    param([string]$Title, [string]$Script, [hashtable]$Vars = @{}, [scriptblock]$OnDone, [switch]$Quiet)
    # Devuelve $true si la tarea arrancó, para que quien la llama no deje la interfaz en un estado de "cargando".
    if (-not $Quiet) {
        if ($script:GuiBusy) { Show-GuiInfo 'Ya hay una tarea en curso. Espera a que termine; su progreso está en el panel inferior.'; return $false }
        $script:GuiBusy = $true
        Set-GuiLogExpanded $true
        $script:Gui.JobTitle.Text = $Title
        $script:Gui.JobTitle.ToolTip = $Title
        $script:Gui.JobStatus.Text = 'Preparando…'
        $script:Gui.JobProgress.Value = 0
        $script:Gui.JobProgress.Visibility = 'Visible'
        $script:GuiLastSummary = $null
        Add-GuiLog ("> $Title" + $(if ($script:IsDryRun) { ' (simulación)' } else { '' })) 'White'
    }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('WT_HW', $script:HW)
    foreach ($k in $Vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $Vars[$k]) }
    $flags = '-LibraryMode -Silent'
    if ($script:IsDryRun) { $flags += ' -DryRun' }
    # La ruta se escapa como comodín: con [ o ] en la carpeta, PowerShell no encontraría el script.
    $safePath = [System.Management.Automation.WildcardPattern]::Escape($script:ScriptPath).Replace("'", "''")
    $boot = @"
`$ErrorActionPreference = 'Continue'
. '$safePath' $flags
function Clear-Host { }
$Script
"@
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($boot)
    $job = [pscustomobject]@{
        PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); OnDone = $OnDone; Quiet = [bool]$Quiet
        Title = $Title; Info = 0; Warn = 0; Err = 0; Started = Get-Date
    }
    [void]$script:GuiJobs.Add($job)
    return $true
}

function Set-GuiLogExpanded {
    # En reposo el registro es una franja; se despliega al empezar una tarea y queda abierto para leer el resultado.
    param([bool]$Expanded)
    $row = $script:Gui.Window.Content.RowDefinitions[1]
    $h = if (-not $Expanded) { 64 } elseif ($script:Gui.Window.ActualHeight -gt 0 -and $script:Gui.Window.ActualHeight -lt 720) { 112 } else { 150 }
    $script:GuiLogExpanded = $Expanded
    if ($row.Height.Value -ne $h) { $row.Height = New-Object System.Windows.GridLength $h }
    $script:Gui.LogBox.VerticalScrollBarVisibility = if ($Expanded) { 'Auto' } else { 'Hidden' }
}

function Sync-GuiJobStreams {
    param($Job)
    $info = $Job.PS.Streams.Information
    while ($Job.Info -lt $info.Count) {
        $rec = $info[$Job.Info]; $Job.Info++
        if ($Job.Quiet) { continue }
        $msg = $rec.MessageData
        $text = if ($msg -is [System.Management.Automation.HostInformationMessage]) { $msg.Message } else { [string]$msg }
        $color = if ($msg -is [System.Management.Automation.HostInformationMessage] -and $null -ne $msg.ForegroundColor) { [string]$msg.ForegroundColor } else { 'Gray' }
        if ($text -match 'Respaldo para deshacer: (.+)$') { $script:Gui.JobBackup.Text = 'Respaldo: ' + (Split-Path $Matches[1] -Leaf) }
        if ($text -match '(Aplicados|Se aplicarían): (\d+)\s+Omitidos: (\d+)\s+Errores: (\d+)') {
            $script:GuiLastSummary = '{0} {1} · {2} omitidos · {3} errores' -f $Matches[2], $(if ($Matches[1] -eq 'Aplicados') { 'aplicados' } else { 'se aplicarían' }), $Matches[3], $Matches[4]
        }
        if ($text -match 'Espacio recuperado: (.+?) \(') { $script:GuiLastSummary = "Espacio recuperado: $($Matches[1])" }
        foreach ($line in ($text -split "`r?`n")) { if ($line.Trim()) { Add-GuiLog $line $color } }
    }
    $warn = $Job.PS.Streams.Warning
    while ($Job.Warn -lt $warn.Count) {
        $w = $warn[$Job.Warn]; $Job.Warn++
        if (-not $Job.Quiet) { Add-GuiLog (' ! ' + $w.Message) 'Yellow' }
    }
    $errs = $Job.PS.Streams.Error
    while ($Job.Err -lt $errs.Count) {
        $e = $errs[$Job.Err]; $Job.Err++
        if (-not $Job.Quiet) { Add-GuiLog (' x ' + $e.Exception.Message) 'Red' }
    }
    if (-not $Job.Quiet) {
        $prog = $Job.PS.Streams.Progress
        $elapsed = (Get-Date) - $Job.Started
        $clock = '{0}:{1:00}' -f [int][math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        if ($prog.Count -gt 0) {
            $last = $prog[$prog.Count - 1]
            if ($last.RecordType -eq 'Completed') {
                $script:Gui.JobStatus.Text = "En curso · $clock"
            } else {
                if ($last.PercentComplete -ge 0) { $script:Gui.JobProgress.Value = $last.PercentComplete }
                $script:Gui.JobStatus.Text = "$($last.StatusDescription) · $clock"
            }
        } else {
            $script:Gui.JobStatus.Text = "En curso · $clock"
        }
    }
}

function Invoke-GuiTick {
    foreach ($job in @($script:GuiJobs)) {
        try { Sync-GuiJobStreams -Job $job } catch { }
        if (-not $job.Handle.IsCompleted) { continue }
        $out = $null; $err = $null
        try { $out = $job.PS.EndInvoke($job.Handle) } catch { $err = $_ }
        try { Sync-GuiJobStreams -Job $job } catch { }
        $job.PS.Dispose()
        $job.RS.Close()
        $script:GuiJobs.Remove($job)
        if (-not $job.Quiet) {
            $script:GuiBusy = $false
            $script:Gui.JobProgress.Visibility = 'Collapsed'
            $elapsed = (Get-Date) - $job.Started
            $clock = '{0}:{1:00}' -f [int][math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
            if ($err) {
                Add-GuiLog (' x ' + $err.Exception.Message) 'Red'
                $script:Gui.JobTitle.Text = "Error · $($job.Title)"
                $script:Gui.JobStatus.Text = $err.Exception.Message
            } else {
                $script:Gui.JobTitle.Text = "Terminado · $($job.Title)"
                $script:Gui.JobStatus.Text = if ($script:GuiLastSummary) { "$($script:GuiLastSummary) · $clock" } else { "Completado en $clock" }
            }
            $script:Gui.JobTitle.ToolTip = $script:Gui.JobTitle.Text
            Update-GuiRail
        }
        if ($job.OnDone) {
            try { & $job.OnDone $out $err } catch { Add-GuiLog (' x Interfaz: ' + $_.Exception.Message) 'Red' }
        }
    }
}

$script:GuiNav = @(
    @{ Id = 'Panel';         Label = 'Panel';               Icon = [string][char]0xE80F }
    @{ Id = 'Ajustes';       Label = 'Ajustes';             Icon = [string][char]0xE713 }
    @{ Id = 'Bloatware';     Label = 'Bloatware';           Icon = [string][char]0xE74D }
    @{ Id = 'Inicio';        Label = 'Programas de inicio'; Icon = [string][char]0xE7E8 }
    @{ Id = 'Limpieza';      Label = 'Limpieza';            Icon = [string][char]0xE894 }
    @{ Id = 'Mantenimiento'; Label = 'Mantenimiento';       Icon = [string][char]0xE90F }
    @{ Id = 'Red';           Label = 'Red y DNS';           Icon = [string][char]0xE774 }
    @{ Id = 'Update';        Label = 'Windows Update';      Icon = [string][char]0xE895 }
    @{ Id = 'Apps';          Label = 'Apps';                Icon = [string][char]0xE719 }
    @{ Id = 'Deshacer';      Label = 'Deshacer';            Icon = [string][char]0xE7A7 }
)

function Get-GuiJournals {
    # Respaldos pendientes con su número correlativo (por orden de creación, el más antiguo es #0001).
    $all = @(Get-ChildItem -Path $script:BackupDir -Filter 'respaldo-*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    $i = 0
    $list = foreach ($f in $all) {
        $i++
        $label = '(ilegible)'; $count = 0
        try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; $label = $j.Label; $count = @($j.Entries).Count } catch { }
        [pscustomobject]@{ Numero = ('#{0:0000}' -f $i); Archivo = $f.FullName; Fecha = $f.LastWriteTime; Etiqueta = $label
                           Cambios = $count; Deshecho = ($f.Name -match 'deshecho') }
    }
    return , @($list | Sort-Object Fecha -Descending)
}

function Update-GuiRail {
    $counts = @{
        Ajustes  = @($script:Tweaks | Where-Object { Test-TweakState $_ }).Count
        Inicio   = @(Get-StartupItems | Where-Object { $_.Enabled }).Count
        Deshacer = @((Get-GuiJournals) | Where-Object { -not $_.Deshecho }).Count
    }
    foreach ($item in $script:GuiNav) {
        $label = $script:Gui.NavCounts[$item.Id]
        if (-not $label) { continue }
        $label.Text = if (-not $counts.ContainsKey($item.Id)) { '' }
                      elseif ($item.Id -eq 'Ajustes') { "$($counts.Ajustes)/$(@($script:Tweaks).Count)" }
                      else { [string]$counts[$item.Id] }
        $label.ToolTip = switch ($item.Id) { 'Ajustes' { 'Ajustes ya aplicados en este equipo' } 'Inicio' { 'Programas que arrancan con Windows' } 'Deshacer' { 'Respaldos pendientes de deshacer' } default { $null } }
    }
    $hw = $script:HW
    $script:Gui.RailInfo.Text = '{0} · {1} GB · {2}' -f $(if ($hw.IsLaptop) { 'Portátil' } else { 'Sobremesa' }), $hw.RamGB, $hw.SystemDisk
}

function Show-GuiPage {
    param([string]$Id)
    $script:GuiCurrentPage = $Id
    try {
        $page = & "Build-GuiPage$Id"
        $script:Gui.PageHost.Content = $page
    } catch {
        Add-GuiLog (" x No se pudo abrir '$Id': " + $_.Exception.Message) 'Red'
    }
}

#endregion

#region ===================== Interfaz gráfica: secciones =====================

function Build-GuiPagePanel {
    $hw = $script:HW
    $basePath = Join-Path $script:DataDir 'linea-base.json'
    $base = $null
    if (Test-Path $basePath) { try { $base = Get-Content $basePath -Raw | ConvertFrom-Json } catch { } }
    $sub = if ($base) { 'Línea base del ' + ([datetime]$base.Fecha).ToString('dd/MM/yyyy HH:mm') } else { 'Sin línea base: se guarda automáticamente antes de la primera optimización' }

    $optimize = New-GuiButton -Text "Optimizar · $($script:PresetDisplay[$script:GuiPreset])" -Kind Primary -OnClick {
        $ids = Get-PresetIds $script:GuiPreset
        $skipped = @($script:Tweaks | Where-Object { $ids -contains $_.Id -and $_.Condition -and -not (& $_.Condition) }).Count
        $text = "Se aplicará el preset $($script:GuiPreset): $($ids.Count - $skipped) ajustes ($skipped no aplican a este equipo) y la limpieza recomendada.`n`n" +
                "Antes se crea un punto de restauración y un respaldo para deshacer. El Explorador puede reiniciarse.`n`nDuración estimada: $(Format-GuiDuration (30 + 5 * $ids.Count + 60))."
        if (-not (Show-GuiConfirm $text "Optimizar · $($script:GuiPreset)")) { return }
        Start-GuiJob -Title "Optimizar · $($script:GuiPreset)" -Vars @{ WT_Ids = $ids; WT_Label = "Optimización $($script:GuiPreset)" } -Script @'
Invoke-TweakSet -Ids $WT_Ids -Label $WT_Label
Invoke-Cleanup -Indexes @(1, 2, 3, 4)
'@ -OnDone { if ($script:GuiCurrentPage -eq 'Panel') { Show-GuiPage 'Panel' } }
    }
    $script:Gui.OptimizeButton = $optimize
    $report = New-GuiButton -Text 'Guardar informe' -OnClick {
        Start-GuiJob -Title 'Informe del sistema' -Script 'Show-Report'
    }
    $page = New-GuiPage -Title ("{0} · {1} {2}" -f $env:COMPUTERNAME, ($hw.OSName -replace '^Microsoft ', ''), $hw.Version) -Subtitle $sub -Actions @($report, $optimize)

    if (-not $script:UserMatch) {
        $warn = New-GuiSurface -Padding '16,12'
        $warn.Background = ConvertTo-GuiBrush '#FFF6DD'
        $warn.BorderBrush = ConvertTo-GuiBrush '#D29922'
        $warn.Margin = '0,0,0,16'
        $warn.Child = New-GuiText -Text 'Estás ejecutando WinTurbo con otra cuenta de administrador: los ajustes de usuario se aplicarán a esa cuenta, no a la sesión abierta.' -Wrap -Color '#5C4400'
        $page.Body.Children.Add($warn) | Out-Null
    }

    $top = New-GuiRow -Columns @('2*', '20', '3*')
    # Ficha del equipo
    $fichaBox = New-GuiSurface
    $ficha = New-Object System.Windows.Controls.StackPanel
    $ficha.Children.Add((New-GuiHeading 'Equipo')) | Out-Null
    $facts = @(
        @('CPU', "$($hw.CPU) · $($hw.Cores) núcleos / $($hw.Threads) hilos"),
        @('RAM', "$($hw.RamGB) GB"),
        @('GPU', $hw.GPU),
        @('Disco', "$($hw.SystemDisk) · $(Get-FreeSpaceGB) GB libres"),
        @('Tipo', $(if ($hw.IsLaptop) { 'Portátil' } else { 'Sobremesa' }) + $(if ($hw.IsVM) { ' (máquina virtual)' } else { '' })),
        @('Edición', $hw.Edition)
    )
    foreach ($f in $facts) {
        $r = New-GuiRow -Columns @('84', '*')
        $r.Margin = '0,0,0,8'
        Add-GuiCell $r (New-GuiText -Text $f[0] -Color '#565C67') 0
        $v = New-GuiText -Text $f[1] -Wrap
        Add-GuiCell $r $v 1
        $ficha.Children.Add($r) | Out-Null
    }
    # La firma: cada cambio aplicado lleva su cinta, del color de su riesgo, y el último respaldo su número.
    $ficha.Children.Add((New-GuiHeading -Text 'Aplicado en este equipo' -Margin '0,12,0,10')) | Out-Null
    $tapes = New-Object System.Windows.Controls.WrapPanel
    $script:Gui.PanelTapes = $tapes
    $pending = @((Get-GuiJournals) | Where-Object { -not $_.Deshecho })
    if ($pending.Count -gt 0) {
        $last = $pending[0]
        $jt = New-GuiTape -Text "$($last.Numero) · $($last.Etiqueta)" -Color 'Black' -Size 12
        $jt.Margin = '0,0,6,6'
        $jt.ToolTip = "Último respaldo: $($last.Cambios) cambios del $($last.Fecha.ToString('dd/MM/yyyy HH:mm')). Se puede deshacer en Deshacer."
        $tapes.Children.Add($jt) | Out-Null
    }
    # Se priorizan los cambios de más riesgo (son los que el técnico debe recordar) y se limitan a 6
    # para que los presets sigan en la primera pantalla; el resto se ve en Ajustes.
    $appliedTweaks = @($script:Tweaks | Where-Object { (Test-TweakState $_) -eq $true } |
                       Sort-Object { @{ Avanzado = 0; Moderado = 1; Seguro = 2 }[$_.Risk] })
    foreach ($t in ($appliedTweaks | Select-Object -First 6)) {
        $short = ($t.Name -split ' - ')[0] -replace '\s*\(.*?\)', ''
        $tape = New-GuiTape -Text $short -Color (@{ Seguro = 'Green'; Moderado = 'Amber'; Avanzado = 'Red' }[$t.Risk]) -Size 12
        $tape.Margin = '0,0,6,6'
        $tape.MaxWidth = 300
        $tape.ToolTip = "$($t.Name) · riesgo $($t.Risk.ToLower())"
        $tapes.Children.Add($tape) | Out-Null
    }
    if ($appliedTweaks.Count -gt 6) {
        $more = New-GuiButton -Text "+$($appliedTweaks.Count - 6) más · ver en Ajustes" -OnClick { $script:Gui.NavButtons['Ajustes'].IsChecked = $true }
        $more.Padding = '8,2'
        $more.FontWeight = 'Normal'
        $more.FontSize = 12.5
        $more.Margin = '0,0,6,6'
        $tapes.Children.Add($more) | Out-Null
    }
    if ($appliedTweaks.Count -eq 0 -and $pending.Count -eq 0) {
        $tapes.Children.Add((New-GuiText -Text 'Todavía no se ha aplicado ningún ajuste en este equipo.' -Color '#565C67' -Wrap)) | Out-Null
    }
    $ficha.Children.Add($tapes) | Out-Null
    $catLine = foreach ($cat in $script:Categories) {
        $ts = @($script:Tweaks | Where-Object { $_.Category -eq $cat -and $_.Registry })
        if ($ts.Count -eq 0) { continue }
        '{0} {1}/{2}' -f $cat, @($ts | Where-Object { Test-TweakState $_ }).Count, $ts.Count
    }
    $cl = New-GuiText -Text ($catLine -join ' · ') -Size 12.5 -Color '#565C67' -Wrap -Tabular
    $cl.Margin = '0,4,0,0'
    $ficha.Children.Add($cl) | Out-Null
    # El estado de Windows Update consulta tareas programadas (lento): se carga aparte para no congelar la ventana.
    # Cada construcción del Panel tiene su número: una respuesta de una construcción anterior se descarta
    # (si no, al reconstruir rápido aparecerían cintas de Windows Update duplicadas).
    $script:GuiPanelGen = [int]$script:GuiPanelGen + 1
    $null = Start-GuiJob -Title 'Estado de Windows Update' -Quiet -Vars @{ WT_Gen = $script:GuiPanelGen } -Script '[pscustomobject]@{ Gen = $WT_Gen; State = (Get-WUBlockStatus) }' -OnDone {
        param($out, $err)
        if ($script:GuiCurrentPage -ne 'Panel' -or -not $out -or $out[0].Gen -ne $script:GuiPanelGen) { return }
        $wuState = $out[0].State
        if ($wuState.Estado -eq 'ACTIVO') { return }
        $wuText = if ($wuState.Modo -eq 'Tienda') { 'Update bloqueado · Tienda activa' } else { "Update $($wuState.Estado.ToLower())" }
        $t = New-GuiTape -Text $wuText -Color $(if ($wuState.Estado -eq 'BLOQUEADO') { 'Red' } else { 'Amber' }) -Size 12
        $t.Margin = '0,0,6,6'
        $script:Gui.PanelTapes.Children.Insert(0, $t)
    }
    $fichaBox.Child = $ficha
    Add-GuiCell $top $fichaBox 0

    # Antes · después en columnas espejo
    $mirrorBox = New-GuiSurface
    $mirror = New-Object System.Windows.Controls.StackPanel
    $mirror.Children.Add((New-GuiHeading 'Antes · después')) | Out-Null
    $grid = New-Object System.Windows.Controls.StackPanel
    $mirror.Children.Add($grid) | Out-Null
    $loading = New-GuiText -Text 'Midiendo el estado actual del equipo…' -Color '#565C67'
    $grid.Children.Add($loading) | Out-Null
    $mirrorBox.Child = $mirror
    Add-GuiCell $top $mirrorBox 2
    $page.Body.Children.Add($top) | Out-Null
    $script:Gui.MirrorGrid = $grid
    $script:Gui.MirrorBase = $base

    # Presets
    $presetHead = New-GuiHeading -Text 'Presets' -Margin '0,24,0,10'
    $page.Body.Children.Add($presetHead) | Out-Null
    $presets = New-GuiRow -Columns @('*', '12', '*', '12', '*', '12', '*')
    $col = 0
    foreach ($name in $script:PresetInfo.Keys) {
        $ids = @(Get-PresetIds $name)
        $skip = @($script:Tweaks | Where-Object { $ids -contains $_.Id -and $_.Condition -and -not (& $_.Condition) }).Count
        $card = New-GuiSurface -Padding '16,14'
        $card.Cursor = 'Hand'
        $card.Tag = $name
        $card.Focusable = $true
        [System.Windows.Automation.AutomationProperties]::SetName($card, "Preset $name")
        if ($name -eq $script:GuiPreset) { $card.BorderBrush = ConvertTo-GuiBrush '#1F6FEB'; $card.BorderThickness = 2; $card.Padding = '15,13' }
        $sp = New-Object System.Windows.Controls.StackPanel
        $display = @{ Basico = 'Básico'; Equilibrado = 'Equilibrado'; Gaming = 'Gaming'; Maximo = 'Máximo' }[$name]
        # Número de ajustes y duración junto al título: lo primero que se lee, y siempre visible.
        $titleRow = New-GuiRow -Columns @('*', 'Auto')
        Add-GuiCell $titleRow (New-GuiText -Text $display -Size 16 -Weight 'SemiBold') 0
        Add-GuiCell $titleRow (New-GuiText -Text (Format-GuiDuration (30 + 5 * $ids.Count)) -Size 12.5 -Color '#565C67' -Tabular) 1
        $sp.Children.Add($titleRow) | Out-Null
        $metaText = "$($ids.Count - $skip) ajustes" + $(if ($skip) { " · $skip no aplican aquí" } else { '' })
        $m = New-GuiText -Text $metaText -Size 12.5 -Weight 'SemiBold' -Color '#3D424B' -Tabular
        $m.Margin = '0,2,0,0'
        $sp.Children.Add($m) | Out-Null
        $d = New-GuiText -Text $script:PresetInfo[$name] -Size 13 -Color '#565C67' -Wrap
        $d.Margin = '0,6,0,0'
        $sp.Children.Add($d) | Out-Null
        $card.Child = $sp
        $card.Add_MouseLeftButtonUp({ Select-GuiPreset $this.Tag })
        $card.Add_KeyDown({ if ($_.Key -eq 'Enter' -or $_.Key -eq 'Space') { Select-GuiPreset $this.Tag } })
        if (-not $script:Gui.PresetCards -or $col -eq 0) { $script:Gui.PresetCards = New-Object System.Collections.ArrayList }
        [void]$script:Gui.PresetCards.Add($card)
        Add-GuiCell $presets $card $col
        $col += 2
    }
    $page.Body.Children.Add($presets) | Out-Null
    $review = New-GuiButton -Text "Revisar el preset en Ajustes" -OnClick {
        $script:GuiSel = @{}
        foreach ($id in (Get-PresetIds $script:GuiPreset)) { $script:GuiSel[$id] = $true }
        $script:Gui.NavButtons['Ajustes'].IsChecked = $true
    }
    $review.HorizontalAlignment = 'Left'
    $review.Margin = '0,12,0,0'
    $page.Body.Children.Add($review) | Out-Null

    $recs = New-Object System.Windows.Controls.StackPanel
    $recs.Margin = '0,24,0,0'
    $page.Body.Children.Add($recs) | Out-Null
    $script:Gui.PanelRecs = $recs

    $null = Start-GuiJob -Title 'Medir estado' -Quiet -Script 'Get-HealthSnapshot' -OnDone {
        param($out, $err)
        if ($script:GuiCurrentPage -ne 'Panel' -or -not $out) { return }
        Update-GuiMirror -Now $out[0] -Base $script:Gui.MirrorBase
    }
    return $page.Root
}

function Select-GuiPreset {
    # Cambia el preset elegido sin reconstruir la página (antes relanzaba dos consultas en segundo plano por clic).
    param([string]$Name)
    $script:GuiPreset = $Name
    foreach ($c in $script:Gui.PresetCards) {
        $on = ($c.Tag -eq $Name)
        $c.BorderBrush = ConvertTo-GuiBrush $(if ($on) { '#1F6FEB' } else { '#D5D8DE' })
        $c.BorderThickness = if ($on) { 2 } else { 1 }
        $c.Padding = if ($on) { '15,13' } else { '16,14' }
    }
    if ($script:Gui.OptimizeButton) { $script:Gui.OptimizeButton.Content = "Optimizar · $($script:PresetDisplay[$Name])" }
}

function Update-GuiMirror {
    param($Now, $Base)
    $grid = $script:Gui.MirrorGrid
    $grid.Children.Clear()
    $rows = @(
        @{ K = 'ArranqueMs';       L = 'Tiempo de arranque'; F = { param($v) if ($null -eq $v) { 'n/d' } else { '{0:N1} s' -f ($v / 1000) } }; Up = $false }
        @{ K = 'RamUsadaPct';      L = 'RAM usada';          F = { param($v) '{0:N1} %' -f $v }; Up = $false }
        @{ K = 'Procesos';         L = 'Procesos';           F = { param($v) [string]$v }; Up = $false }
        @{ K = 'ServiciosActivos'; L = 'Servicios activos';  F = { param($v) [string]$v }; Up = $false }
        @{ K = 'AppsInicio';       L = 'Apps de inicio';     F = { param($v) [string]$v }; Up = $false }
        @{ K = 'TempMB';           L = 'Temporales';         F = { param($v) '{0:N0} MB' -f $v }; Up = $false }
        @{ K = 'LibreSistemaGB';   L = 'Espacio libre';      F = { param($v) '{0:N1} GB' -f $v }; Up = $true }
    )
    $head = New-GuiRow -Columns @('*', '110', '2', '110', '80')
    Add-GuiCell $head (New-GuiText -Text 'Métrica' -Size 12 -Color '#565C67') 0
    $hb = New-GuiText -Text $(if ($Base) { 'Línea base' } else { 'Sin línea base' }) -Size 12 -Color '#565C67'; $hb.HorizontalAlignment = 'Right'; $hb.Margin = '0,0,14,0'
    Add-GuiCell $head $hb 1
    $hn = New-GuiText -Text 'Ahora' -Size 12 -Color '#565C67'; $hn.Margin = '14,0,0,0'
    Add-GuiCell $head $hn 3
    $hd = New-GuiText -Text 'Cambio' -Size 12 -Color '#565C67'; $hd.HorizontalAlignment = 'Right'
    Add-GuiCell $head $hd 4
    $head.Margin = '0,0,0,6'
    $grid.Children.Add($head) | Out-Null
    foreach ($r in $rows) {
        $row = New-GuiRow -Columns @('*', '110', '2', '110', '80')
        $row.MinHeight = 32
        $b = if ($Base) { $Base.($r.K) } else { $null }
        $a = $Now.($r.K)
        $lbl = New-GuiText -Text $r.L -Wrap
        $lbl.Margin = '0,4,8,4'
        Add-GuiCell $row $lbl 0
        $bt = New-GuiText -Text $(if ($Base) { & $r.F $b } else { '—' }) -Color '#565C67' -Tabular
        $bt.HorizontalAlignment = 'Right'; $bt.Margin = '0,0,14,0'
        Add-GuiCell $row $bt 1
        $axis = New-Object System.Windows.Controls.Border
        $axis.Background = ConvertTo-GuiBrush '#16181D'
        Add-GuiCell $row $axis 2
        $at = New-GuiText -Text (& $r.F $a) -Weight 'SemiBold' -Tabular
        $at.Margin = '14,0,0,0'
        Add-GuiCell $row $at 3
        $delta = ''
        $color = '#565C67'
        if ($Base -and $null -ne $a -and $null -ne $b) {
            $diff = [double]$a - [double]$b
            if ([math]::Abs($diff) -gt 0.0001) {
                $better = if ($r.Up) { $diff -gt 0 } else { $diff -lt 0 }
                $color = if ($better) { '#1A7F37' } else { '#9A6700' }
                # El porcentaje solo tiene sentido con línea base distinta de 0; si no, se muestra la diferencia absoluta.
                $delta = if (($r.K -eq 'ArranqueMs' -or $r.K -eq 'TempMB') -and [double]$b -ne 0) { '{0:+0;−0} %' -f (100 * $diff / [double]$b) }
                         elseif ($r.K -eq 'ArranqueMs') { '{0:+0.0;−0.0} s' -f ($diff / 1000) }
                         elseif ($r.K -eq 'TempMB') { '{0:+0;−0} MB' -f $diff }
                         elseif ($r.K -eq 'RamUsadaPct') { '{0:+0.0;−0.0} pts' -f $diff }
                         elseif ($r.K -eq 'LibreSistemaGB') { '{0:+0.0;−0.0} GB' -f $diff }
                         else { '{0:+0;−0}' -f $diff }
            }
        }
        $dt = New-GuiText -Text $delta -Weight 'SemiBold' -Color $color -Tabular
        $dt.HorizontalAlignment = 'Right'
        Add-GuiCell $row $dt 4
        $line = New-Object System.Windows.Controls.Border
        $line.BorderBrush = ConvertTo-GuiBrush '#ECEEF1'
        $line.BorderThickness = '0,0,0,1'
        $line.Child = $row
        $grid.Children.Add($line) | Out-Null
    }
    $note = New-GuiText -Text 'El tiempo de arranque se actualiza después de reiniciar.' -Size 12 -Color '#565C67' -Wrap
    $note.Margin = '0,10,0,0'
    $grid.Children.Add($note) | Out-Null

    # Recomendaciones derivadas de la medición
    $recs = $script:Gui.PanelRecs
    if (-not $recs) { return }
    $recs.Children.Clear()
    $tips = New-Object System.Collections.Generic.List[string]
    if ($Now.LibreSistemaGB -lt 20) { $tips.Add('Queda poco espacio libre en el disco del sistema. Ejecuta Limpieza y, si sigue bajo, revisa qué ocupa espacio con WizTree (sección Apps).') }
    if ($Now.AppsInicio -gt 8) { $tips.Add("Hay $($Now.AppsInicio) programas que arrancan con Windows. Desactiva en Programas de inicio los que el cliente no use a diario.") }
    if ($script:HW.SystemDisk -eq 'HDD') { $tips.Add('Windows está en un disco duro mecánico. Pasar a un SSD es la mejora más grande posible y ningún ajuste la iguala.') }
    if ($script:HW.RamGB -lt 8) { $tips.Add('El equipo tiene menos de 8 GB de RAM. El preset Equilibrado ya incluye los efectos visuales mínimos; ampliar a 16 GB es la siguiente mejora.') }
    if ($Now.HorasEncendido -gt 168) { $tips.Add('Lleva más de 7 días sin reiniciar. Reiniciar libera memoria y completa actualizaciones pendientes.') }
    if ($Now.RamUsadaPct -gt 85) { $tips.Add('La RAM está por encima del 85 %. Revisa en el Administrador de tareas qué proceso la consume antes de aplicar ajustes.') }
    if ($tips.Count -eq 0) { return }
    $recs.Children.Add((New-GuiHeading 'Recomendaciones para este equipo')) | Out-Null
    $box = New-GuiSurface
    $list = New-Object System.Windows.Controls.StackPanel
    foreach ($t in $tips) {
        $tt = New-GuiText -Text $t -Wrap
        $tt.Margin = '0,0,0,8'
        $list.Children.Add($tt) | Out-Null
    }
    $box.Child = $list
    $recs.Children.Add($box) | Out-Null
}

function Update-GuiTweakSummary {
    $ids = @($script:Tweaks | Where-Object { $script:GuiSel[$_.Id] } | ForEach-Object { $_.Id })
    $adv = @($script:Tweaks | Where-Object { $script:GuiSel[$_.Id] -and $_.Risk -eq 'Avanzado' }).Count
    $text = "$($ids.Count) seleccionados · $(Format-GuiDuration (30 + 5 * $ids.Count))"
    if ($adv) { $text += $(if ($adv -eq 1) { ' · 1 avanzado' } else { " · $adv avanzados" }) }
    if ($script:Gui.TweakSummary) { $script:Gui.TweakSummary.Text = $text }
    if ($script:Gui.TweakApply) { $script:Gui.TweakApply.IsEnabled = ($ids.Count -gt 0) }
}

function Show-GuiTweakDetail {
    param($Tweak)
    $panel = $script:Gui.TweakDetail
    if (-not $panel) { return }
    $panel.Children.Clear()
    $panel.Children.Add((New-GuiText -Text $Tweak.Name -Size 16 -Weight 'SemiBold' -Wrap)) | Out-Null
    $tags = New-Object System.Windows.Controls.WrapPanel
    $tags.Margin = '0,10,0,12'
    $riskColor = @{ Seguro = 'Green'; Moderado = 'Amber'; Avanzado = 'Red' }[$Tweak.Risk]
    $t1 = New-GuiTape -Text $Tweak.Risk -Color $riskColor; $t1.Margin = '0,0,6,6'; $tags.Children.Add($t1) | Out-Null
    $state = Test-TweakState $Tweak
    if ($state -eq $true) { $t2 = New-GuiTape -Text 'Aplicado' -Color 'Green'; $t2.Margin = '0,0,6,6'; $tags.Children.Add($t2) | Out-Null }
    if ($Tweak.NoUndo) { $t3 = New-GuiTape -Text 'Sin deshacer' -Color 'Red'; $t3.Margin = '0,0,6,6'; $tags.Children.Add($t3) | Out-Null }
    if ($Tweak.Reboot) { $t4 = New-GuiTape -Text 'Reiniciar' -Color 'Black'; $t4.Margin = '0,0,6,6'; $tags.Children.Add($t4) | Out-Null }
    $panel.Children.Add($tags) | Out-Null
    $panel.Children.Add((New-GuiText -Text $Tweak.Description -Wrap)) | Out-Null
    if ($Tweak.Condition -and -not (& $Tweak.Condition)) {
        $c = New-GuiText -Text "No se aplicará en este equipo: $($Tweak.ConditionText)." -Wrap -Color '#9A6700'
        $c.Margin = '0,12,0,0'
        $panel.Children.Add($c) | Out-Null
    }
    $presetNames = @{ B = 'Básico'; E = 'Equilibrado'; G = 'Gaming'; M = 'Máximo' }
    $inPresets = (@($Tweak.Presets) | ForEach-Object { $presetNames[$_] }) -join ', '
    $p = New-GuiText -Text "Incluido en: $inPresets" -Size 13 -Color '#565C67' -Wrap
    $p.Margin = '0,14,0,0'
    $panel.Children.Add($p) | Out-Null
    $what = @()
    $n = @($Tweak.Registry).Count; if ($Tweak.Registry) { $what += $(if ($n -eq 1) { '1 valor de registro' } else { "$n valores de registro" }) }
    $n = @($Tweak.Services).Count; if ($Tweak.Services) { $what += $(if ($n -eq 1) { '1 servicio' } else { "$n servicios" }) }
    $n = @($Tweak.Tasks).Count; if ($Tweak.Tasks) { $what += $(if ($n -eq 1) { '1 tarea programada' } else { "$n tareas programadas" }) }
    if ($Tweak.Script) { $what += 'una acción del sistema' }
    $w = New-GuiText -Text ('Cambia: ' + ($what -join ', ')) -Size 13 -Color '#565C67' -Wrap
    $w.Margin = '0,4,0,0'
    $panel.Children.Add($w) | Out-Null
}

function Build-GuiPageAjustes {
    $presetBox = New-Object System.Windows.Controls.ComboBox
    $presetBox.Width = 190
    $presetBox.Margin = '0,0,10,0'
    $presetBox.VerticalContentAlignment = 'Center'
    $presetBox.Padding = '8,6'
    [void]$presetBox.Items.Add('Cargar un preset…')
    foreach ($n in $script:PresetInfo.Keys) { [void]$presetBox.Items.Add($n) }
    $presetBox.SelectedIndex = 0
    $presetBox.Add_SelectionChanged({
        if ($this.SelectedIndex -le 0) { return }
        $script:GuiSel = @{}
        foreach ($id in (Get-PresetIds ([string]$this.SelectedItem))) { $script:GuiSel[$id] = $true }
        Show-GuiPage 'Ajustes'
    })
    $all = New-GuiButton -Text 'Todo' -OnClick { foreach ($t in $script:Tweaks) { $script:GuiSel[$t.Id] = $true }; Show-GuiPage 'Ajustes' }
    $none = New-GuiButton -Text 'Nada' -OnClick { $script:GuiSel = @{}; Show-GuiPage 'Ajustes' }
    $import = New-GuiButton -Text 'Importar' -ToolTip 'Cargar una selección exportada desde otro equipo' -OnClick {
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Configuración de WinTurbo (*.json)|*.json'
        if (-not $dlg.ShowDialog($script:Gui.Window)) { return }
        try {
            $cfg = Get-Content -LiteralPath $dlg.FileName -Raw | ConvertFrom-Json
            $script:GuiSel = @{}
            foreach ($id in $cfg.Tweaks) { $script:GuiSel[[string]$id] = $true }
            Add-GuiLog " + Selección importada de $($dlg.FileName)" 'Green'
            Show-GuiPage 'Ajustes'
        } catch { Show-GuiInfo "No se pudo leer el archivo: $($_.Exception.Message)" 'Error' }
    }
    $export = New-GuiButton -Text 'Exportar' -ToolTip 'Guardar la selección para aplicarla en otros equipos' -OnClick {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = 'Configuración de WinTurbo (*.json)|*.json'
        $dlg.FileName = 'WinTurbo-config.json'
        if (-not $dlg.ShowDialog($script:Gui.Window)) { return }
        @{ Version = $script:Version; Tweaks = @($script:Tweaks | Where-Object { $script:GuiSel[$_.Id] } | ForEach-Object { $_.Id }) } |
            ConvertTo-Json | Set-Content -Path $dlg.FileName -Encoding UTF8
        Add-GuiLog " + Selección exportada: $($dlg.FileName)" 'Green'
        Add-GuiLog "   En otro equipo: .\WinTurbo.ps1 -ConfigFile `"$($dlg.FileName)`" -Silent" 'Gray'
    }
    $export.Margin = '0'
    $applied = @($script:Tweaks | Where-Object { Test-TweakState $_ }).Count
    $page = New-GuiPage -Title 'Ajustes' -Subtitle "$($script:Tweaks.Count) ajustes · $applied ya aplicados en este equipo. Selecciona un ajuste para ver qué hace y qué se pierde." -Actions @($presetBox, $all, $none, $import, $export)

    $sideWidth = if ($script:Gui.Window.ActualWidth -gt 0 -and $script:Gui.Window.ActualWidth -lt 1200) { '260' } else { '320' }
    $layout = New-GuiRow -Columns @('*', '20', $sideWidth)
    $listBox = New-GuiSurface -Padding '6,6'
    $list = New-Object System.Windows.Controls.StackPanel
    foreach ($cat in $script:Categories) {
        $items = @($script:Tweaks | Where-Object { $_.Category -eq $cat })
        if ($items.Count -eq 0) { continue }
        $h = New-GuiText -Text $cat -Size 13 -Weight 'SemiBold' -Color '#565C67'
        $h.Margin = '12,14,0,6'
        $list.Children.Add($h) | Out-Null
        foreach ($t in $items) {
            $row = New-GuiRow -Columns @('34', '*', 'Auto', '96')
            $row.MinHeight = 34
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Tag = $t.Id
            $cb.IsChecked = [bool]$script:GuiSel[$t.Id]
            [System.Windows.Automation.AutomationProperties]::SetName($cb, $t.Name)
            $cb.Add_Click({ $script:GuiSel[$this.Tag] = [bool]$this.IsChecked; Update-GuiTweakSummary })
            Add-GuiCell $row $cb 0
            $nameColor = '#16181D'
            $na = ($t.Condition -and -not (& $t.Condition))
            if ($na) { $nameColor = '#6B717C' }
            # Los nombres se ajustan en varias líneas: en un portátil al 125 % no caben y el técnico debe leer qué marca.
            $name = New-GuiText -Text $t.Name -Color $nameColor -Wrap
            $name.Margin = '0,4,10,4'
            Add-GuiCell $row $name 1
            $stateEl = $null
            if ($na) { $stateEl = New-GuiText -Text 'No aplica' -Size 12 -Color '#565C67'; $stateEl.ToolTip = $t.ConditionText }
            elseif ((Test-TweakState $t) -eq $true) { $stateEl = New-GuiTape -Text 'Aplicado' -Color 'Green' }
            if ($stateEl) { $stateEl.Margin = '0,0,10,0'; Add-GuiCell $row $stateEl 2 }
            $risk = New-GuiTape -Text $t.Risk -Color (@{ Seguro = 'Green'; Moderado = 'Amber'; Avanzado = 'Red' }[$t.Risk])
            $risk.HorizontalAlignment = 'Right'
            Add-GuiCell $row $risk 3
            $wrap = New-Object System.Windows.Controls.Border
            $wrap.Padding = '8,3,10,3'
            $wrap.CornerRadius = 4
            $wrap.Background = [System.Windows.Media.Brushes]::Transparent
            $wrap.Child = $row
            $wrap.Tag = $t.Id
            $wrap.Add_MouseEnter({ $this.Background = ConvertTo-GuiBrush '#F1F3F5' })
            $wrap.Add_MouseLeave({ if ($script:GuiDetailId -ne $this.Tag) { $this.Background = [System.Windows.Media.Brushes]::Transparent } })
            $wrap.Add_MouseLeftButtonUp({
                $script:GuiDetailId = $this.Tag
                foreach ($w in $script:Gui.TweakRows) { $w.Background = [System.Windows.Media.Brushes]::Transparent }
                $this.Background = ConvertTo-GuiBrush '#E8F0FD'
                Show-GuiTweakDetail (Get-Tweak $this.Tag)
            })
            $cb.Add_GotKeyboardFocus({ $script:GuiDetailId = $this.Tag; Show-GuiTweakDetail (Get-Tweak $this.Tag) })
            $list.Children.Add($wrap) | Out-Null
        }
    }
    $listBox.Child = $list
    Add-GuiCell $layout $listBox 0

    $side = New-Object System.Windows.Controls.StackPanel
    $detailBox = New-GuiSurface
    $detail = New-Object System.Windows.Controls.StackPanel
    $detail.Children.Add((New-GuiText -Text 'Selecciona un ajuste de la lista para ver qué hace, su riesgo y en qué presets está.' -Color '#565C67' -Wrap)) | Out-Null
    $detailBox.Child = $detail
    $side.Children.Add($detailBox) | Out-Null
    $script:Gui.TweakDetail = $detail

    $applyBox = New-GuiSurface
    $applyBox.Margin = '0,16,0,0'
    $ap = New-Object System.Windows.Controls.StackPanel
    $sum = New-GuiText -Text '' -Weight 'SemiBold' -Tabular -Wrap
    $ap.Children.Add($sum) | Out-Null
    $script:Gui.TweakSummary = $sum
    $note = New-GuiText -Text 'Se crea un punto de restauración y un respaldo con el valor original de cada cambio.' -Size 12.5 -Color '#565C67' -Wrap
    $note.Margin = '0,6,0,12'
    $ap.Children.Add($note) | Out-Null
    $apply = New-GuiButton -Text 'Aplicar selección' -Kind Primary -OnClick {
        $ids = @($script:Tweaks | Where-Object { $script:GuiSel[$_.Id] } | ForEach-Object { $_.Id })
        $adv = @($script:Tweaks | Where-Object { $script:GuiSel[$_.Id] -and $_.Risk -eq 'Avanzado' } | ForEach-Object { '• ' + $_.Name })
        $text = "Se aplicarán $($ids.Count) ajustes. Antes se crea un punto de restauración y un respaldo para deshacer."
        if (@($script:Tweaks | Where-Object { $script:GuiSel[$_.Id] -and $_.Explorer }).Count) { $text += "`nEl Explorador se reiniciará para mostrar los cambios de interfaz." }
        if ($adv.Count) { $text += "`n`nAjustes avanzados incluidos:`n" + ($adv -join "`n") }
        if (-not (Show-GuiConfirm $text 'Aplicar ajustes' 'Warning')) { return }
        Start-GuiJob -Title "Aplicar $($ids.Count) ajustes" -Vars @{ WT_Ids = $ids } -Script 'Invoke-TweakSet -Ids $WT_Ids -Label ''Personalizado''' -OnDone {
            if ($script:GuiCurrentPage -eq 'Ajustes') { Show-GuiPage 'Ajustes' }
        }
    }
    $apply.HorizontalAlignment = 'Stretch'
    $apply.Margin = '0'
    $ap.Children.Add($apply) | Out-Null
    $script:Gui.TweakApply = $apply
    $applyBox.Child = $ap
    $side.Children.Add($applyBox) | Out-Null
    Add-GuiCell $layout $side 2
    $page.Body.Children.Add($layout) | Out-Null
    $script:Gui.TweakRows = New-Object System.Collections.ArrayList
    foreach ($child in $list.Children) { if ($child -is [System.Windows.Controls.Border]) { [void]$script:Gui.TweakRows.Add($child) } }
    Update-GuiTweakSummary
    if ($script:GuiDetailId) { $d = Get-Tweak $script:GuiDetailId; if ($d) { Show-GuiTweakDetail $d } }
    return $page.Root
}

function New-GuiCheckRow {
    # Fila de lista con casilla, texto principal, texto secundario a la derecha y separador.
    param([string]$Text, [string]$Right, $Tag, [bool]$Checked, [string]$Sub)
    $row = New-GuiRow -Columns @('34', '*', 'Auto')
    $row.MinHeight = 34
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Tag = $Tag
    $cb.IsChecked = $Checked
    [System.Windows.Automation.AutomationProperties]::SetName($cb, $Text)
    Add-GuiCell $row $cb 0
    $texts = New-Object System.Windows.Controls.StackPanel
    $texts.VerticalAlignment = 'Center'
    $texts.Children.Add((New-GuiText -Text $Text)) | Out-Null
    if ($Sub) { $texts.Children.Add((New-GuiText -Text $Sub -Size 12.5 -Color '#565C67')) | Out-Null }
    Add-GuiCell $row $texts 1
    $r = New-GuiText -Text $Right -Color '#565C67' -Tabular
    $r.Margin = '12,0,0,0'
    Add-GuiCell $row $r 2
    $wrap = New-GuiListRow -Child $row
    return [pscustomobject]@{ Element = $wrap; Check = $cb; Right = $r }
}

function New-GuiListRow {
    # Fila de lista con separador inferior de 1 px: la misma en todas las secciones.
    param($Child, [string]$Padding = '4')
    $wrap = New-Object System.Windows.Controls.Border
    $wrap.BorderBrush = ConvertTo-GuiBrush '#ECEEF1'
    $wrap.BorderThickness = '0,0,0,1'
    $wrap.Padding = $Padding
    $wrap.Child = $Child
    return $wrap
}

function Build-GuiPageBloatware {
    $removeGroups = New-GuiButton -Text 'Eliminar grupos marcados' -Kind Primary -OnClick {
        $patterns = @(); $names = @()
        foreach ($c in $script:Gui.BloatGroupChecks) { if ($c.IsChecked) { $patterns += $script:AppxGroups[$c.Tag]; $names += $c.Tag } }
        if ($patterns.Count -eq 0) { Show-GuiInfo 'Marca al menos un grupo.'; return }
        if (-not (Show-GuiConfirm ("Se eliminarán para todos los usuarios las apps de:`n• " + ($names -join "`n• ") + "`n`nSe pueden reinstalar desde Microsoft Store.") 'Quitar bloatware' 'Warning')) { return }
        Start-GuiJob -Title 'Quitar bloatware' -Vars @{ WT_Patterns = $patterns } -Script 'Remove-AppxSet -Patterns $WT_Patterns' -OnDone { if ($script:GuiCurrentPage -eq 'Bloatware') { Show-GuiPage 'Bloatware' } }
    }
    $onedrive = New-GuiButton -Text 'Desinstalar OneDrive' -Kind Danger -OnClick {
        if (-not (Show-GuiConfirm "OneDrive dejará de sincronizar. Los archivos de la carpeta OneDrive se conservan.`n`n¿Desinstalarlo?" 'OneDrive' 'Warning')) { return }
        Start-GuiJob -Title 'Desinstalar OneDrive' -Script 'Remove-OneDriveSafe'
    }
    $onedrive.Margin = '0'
    $script:Gui.BloatRemoveGroups = $removeGroups
    $page = New-GuiPage -Title 'Bloatware' -Subtitle 'Nunca se tocan: Tienda, winget, Calculadora, Fotos, Bloc de notas, Paint, Recortes, Cámara, Seguridad de Windows ni los códecs.' -Actions @($removeGroups, $onedrive)

    $page.Body.Children.Add((New-GuiHeading 'Grupos')) | Out-Null
    $gbox = New-GuiSurface -Padding '12,6'
    $glist = New-Object System.Windows.Controls.StackPanel
    $script:Gui.BloatGroupChecks = New-Object System.Collections.ArrayList
    $script:Gui.BloatGroupCounts = @{}
    foreach ($g in $script:AppxGroups.Keys) {
        $r = New-GuiCheckRow -Text $g -Right 'contando…' -Tag $g -Checked:($g -like 'Recomendado*')
        [void]$script:Gui.BloatGroupChecks.Add($r.Check)
        $script:Gui.BloatGroupCounts[$g] = $r.Right
        $glist.Children.Add($r.Element) | Out-Null
    }
    $gbox.Child = $glist
    $page.Body.Children.Add($gbox) | Out-Null

    $appsHead = New-GuiRow -Columns @('*', 'Auto')
    $appsHead.Margin = '0,24,0,10'
    Add-GuiCell $appsHead (New-GuiHeading -Text 'Apps instaladas, una por una' -Margin '0') 0
    $removeApps = New-GuiButton -Text 'Eliminar apps marcadas' -OnClick {
        $names = @($script:Gui.BloatAppChecks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
        if ($names.Count -eq 0) { Show-GuiInfo 'Marca al menos una app.'; return }
        if (-not (Show-GuiConfirm ("Se eliminarán $($names.Count) apps:`n• " + ($names -join "`n• ")) 'Eliminar apps' 'Warning')) { return }
        Start-GuiJob -Title "Eliminar $($names.Count) apps" -Vars @{ WT_Patterns = $names } -Script 'Remove-AppxSet -Patterns $WT_Patterns' -OnDone { if ($script:GuiCurrentPage -eq 'Bloatware') { Show-GuiPage 'Bloatware' } }
    }
    $removeApps.Margin = '0'
    Add-GuiCell $appsHead $removeApps 1
    $page.Body.Children.Add($appsHead) | Out-Null
    $abox = New-GuiSurface -Padding '12,6'
    $alist = New-Object System.Windows.Controls.StackPanel
    $alist.Children.Add((New-GuiText -Text 'Cargando la lista de apps…' -Color '#565C67')) | Out-Null
    $abox.Child = $alist
    $page.Body.Children.Add($abox) | Out-Null
    $script:Gui.BloatAppList = $alist

    $null = Start-GuiJob -Title 'Leer apps' -Quiet -Script @'
$all = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
$counts = @{}
foreach ($g in $script:AppxGroups.Keys) {
    $p = $script:AppxGroups[$g]
    $counts[$g] = @($all | Where-Object { $n = $_.Name; ($p | Where-Object { $n -like $_ }) } | Select-Object -ExpandProperty Name -Unique).Count
}
$apps = @($all | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' -and -not (Test-AppxProtected $_.Name) } |
          Select-Object -ExpandProperty Name -Unique | Sort-Object)
[pscustomobject]@{ Counts = $counts; Apps = $apps; Readable = ((Test-IsAdmin) -and $all.Count -gt 0) }
'@ -OnDone {
        param($out, $err)
        if ($script:GuiCurrentPage -ne 'Bloatware' -or -not $out) { return }
        $data = $out[0]
        if (-not $data.Readable) {
            # Sin permisos Get-AppxPackage -AllUsers no devuelve nada: decir "0 instaladas" sería falso.
            foreach ($g in $script:Gui.BloatGroupCounts.Keys) { $script:Gui.BloatGroupCounts[$g].Text = 'sin datos' }
            $script:Gui.BloatRemoveGroups.IsEnabled = $false
            $script:Gui.BloatAppList.Children.Clear()
            $script:Gui.BloatAppList.Children.Add((New-GuiText -Text 'No se pudo leer la lista de apps. WinTurbo necesita permisos de administrador para verla.' -Color '#565C67' -Wrap)) | Out-Null
            return
        }
        foreach ($g in $script:Gui.BloatGroupCounts.Keys) { $script:Gui.BloatGroupCounts[$g].Text = "$($data.Counts[$g]) instaladas" }
        $list = $script:Gui.BloatAppList
        $list.Children.Clear()
        $script:Gui.BloatAppChecks = New-Object System.Collections.ArrayList
        if (@($data.Apps).Count -eq 0) { $list.Children.Add((New-GuiText -Text 'No hay apps eliminables (o faltan permisos para leerlas).' -Color '#565C67')) | Out-Null; return }
        foreach ($a in $data.Apps) {
            $r = New-GuiCheckRow -Text $a -Right '' -Tag $a -Checked:$false
            [void]$script:Gui.BloatAppChecks.Add($r.Check)
            $list.Children.Add($r.Element) | Out-Null
        }
    }
    return $page.Root
}

function Build-GuiPageInicio {
    $items = @(Get-StartupItems)
    $apply = New-GuiButton -Text 'Aplicar cambios' -Kind Primary -OnClick {
        $changes = @()
        foreach ($c in $script:Gui.StartupChecks) {
            $it = $c.Tag
            if ([bool]$c.IsChecked -ne [bool]$it.Enabled) {
                $changes += [pscustomobject]@{ Nombre = $it.Nombre; Approved = $it.Approved; Enable = [bool]$c.IsChecked }
            }
        }
        if ($changes.Count -eq 0) { Show-GuiInfo 'No hay cambios que aplicar.'; return }
        Start-GuiJob -Title "Programas de inicio: $($changes.Count) cambios" -Vars @{ WT_Changes = $changes } -Script @'
Start-Journal -Label 'Programas de inicio'
foreach ($c in $WT_Changes) {
    Set-StartupItemState -Item $c -Enable $c.Enable
    Write-Log ("{0}: {1}" -f $c.Nombre, $(if ($c.Enable) { 'activado' } else { 'desactivado' })) OK
}
Save-Journal
if ($script:JournalPath -and (Test-Path $script:JournalPath)) { Write-Log "Respaldo para deshacer: $script:JournalPath" }
'@ -OnDone { if ($script:GuiCurrentPage -eq 'Inicio') { Show-GuiPage 'Inicio' } }
    }
    $apply.Margin = '0'
    $enabled = @($items | Where-Object { $_.Enabled }).Count
    $page = New-GuiPage -Title 'Programas de inicio' -Subtitle "$enabled de $($items.Count) arrancan con Windows. Desactivar no desinstala nada y se puede reactivar, igual que en el Administrador de tareas." -Actions @($apply)
    $box = New-GuiSurface -Padding '12,6'
    $list = New-Object System.Windows.Controls.StackPanel
    $head = New-GuiRow -Columns @('64', '2*', '130', '3*')
    $head.Margin = '4,8,4,6'
    Add-GuiCell $head (New-GuiText -Text 'Activo' -Size 12 -Color '#565C67') 0
    Add-GuiCell $head (New-GuiText -Text 'Nombre' -Size 12 -Color '#565C67') 1
    Add-GuiCell $head (New-GuiText -Text 'Origen' -Size 12 -Color '#565C67') 2
    Add-GuiCell $head (New-GuiText -Text 'Comando' -Size 12 -Color '#565C67') 3
    $list.Children.Add($head) | Out-Null
    $script:Gui.StartupChecks = New-Object System.Collections.ArrayList
    if ($items.Count -eq 0) { $list.Children.Add((New-GuiText -Text 'No hay programas configurados para arrancar con Windows.' -Color '#565C67')) | Out-Null }
    foreach ($it in $items) {
        $row = New-GuiRow -Columns @('64', '2*', '130', '3*')
        $row.MinHeight = 34
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = $it.Enabled
        $cb.Tag = $it
        [System.Windows.Automation.AutomationProperties]::SetName($cb, $it.Nombre)
        [void]$script:Gui.StartupChecks.Add($cb)
        Add-GuiCell $row $cb 0
        $n = New-GuiText -Text $it.Nombre -Weight $(if ($it.Enabled) { 'SemiBold' } else { 'Normal' })
        $n.Margin = '0,0,12,0'
        Add-GuiCell $row $n 1
        Add-GuiCell $row (New-GuiText -Text $it.Origen -Color '#565C67') 2
        $cmd = New-GuiText -Text $it.Comando -Size 12.5 -Color '#565C67'
        $cmd.FontFamily = 'Consolas'
        $cmd.ToolTip = $it.Comando
        Add-GuiCell $row $cmd 3
        $list.Children.Add((New-GuiListRow -Child $row)) | Out-Null
    }
    $box.Child = $list
    $page.Body.Children.Add($box) | Out-Null
    $tip = New-GuiText -Text 'Para revisar también tareas programadas, servicios y extensiones de terceros, instala Sysinternals Autoruns desde la sección Apps.' -Size 13 -Color '#565C67' -Wrap
    $tip.Margin = '0,12,0,0'
    $page.Body.Children.Add($tip) | Out-Null
    return $page.Root
}

function Build-GuiPageLimpieza {
    $clean = New-GuiButton -Text 'Limpiar seleccionados' -Kind Primary -OnClick {
        $idx = @($script:Gui.CleanChecks | Where-Object { $_.IsChecked } | ForEach-Object { [int]$_.Tag })
        if ($idx.Count -eq 0) { Show-GuiInfo 'Marca al menos una categoría.'; return }
        $slow = @($idx | Where-Object { $_ -ge 7 }).Count
        $text = "Se limpiarán $($idx.Count) categorías." + $(if ($slow) { "`n`nIncluye tareas lentas (DISM o el Liberador de espacio): pueden tardar varios minutos." } else { '' })
        if (-not (Show-GuiConfirm $text 'Limpieza')) { return }
        Start-GuiJob -Title 'Limpieza de disco' -Vars @{ WT_Idx = $idx } -Script 'Invoke-Cleanup -Indexes $WT_Idx' -OnDone { if ($script:GuiCurrentPage -eq 'Limpieza') { Show-GuiPage 'Limpieza' } }
    }
    $clean.Margin = '0'
    $page = New-GuiPage -Title 'Limpieza' -Subtitle "Los temporales solo se borran si tienen más de 24 horas, para no romper instalaciones en curso. Libre ahora: $(Get-FreeSpaceGB) GB." -Actions @($clean)
    $box = New-GuiSurface -Padding '12,6'
    $list = New-Object System.Windows.Controls.StackPanel
    $script:Gui.CleanChecks = New-Object System.Collections.ArrayList
    $script:Gui.CleanSizes = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $script:CleanupTasks.Count; $i++) {
        $t = $script:CleanupTasks[$i]
        $r = New-GuiCheckRow -Text $t.Name -Right 'midiendo…' -Tag ($i + 1) -Checked:([bool]$t.Default)
        [void]$script:Gui.CleanChecks.Add($r.Check)
        [void]$script:Gui.CleanSizes.Add($r.Right)
        $list.Children.Add($r.Element) | Out-Null
    }
    $box.Child = $list
    $page.Body.Children.Add($box) | Out-Null
    $null = Start-GuiJob -Title 'Medir limpieza' -Quiet -Script 'foreach ($t in $script:CleanupTasks) { $s = & $t.Size; if ($null -eq $s) { -1 } else { [double]$s } }' -OnDone {
        param($out, $err)
        if ($script:GuiCurrentPage -ne 'Limpieza' -or -not $out) { return }
        for ($i = 0; $i -lt $out.Count -and $i -lt $script:Gui.CleanSizes.Count; $i++) {
            $v = [double]$out[$i]
            $script:Gui.CleanSizes[$i].Text = if ($v -lt 0) { '' } elseif ($v -ge 1024) { '{0:N1} GB' -f ($v / 1024) } else { '{0:N0} MB' -f $v }
        }
    }
    return $page.Root
}

$script:GuiMaintenance = @(
    @{ Title = 'Reparar Windows'; Text = 'DISM repara la imagen del sistema, SFC los archivos protegidos y CHKDSK comprueba el disco, en ese orden.'; Time = '20–40 min'; Cmd = 'Invoke-SystemRepair'; Confirm = 'La reparación tarda entre 20 y 40 minutos y usa mucho disco. ¿Empezar?' }
    @{ Title = 'Optimizar unidades'; Text = 'TRIM en SSD y desfragmentación en discos duros, según el tipo de cada unidad.'; Time = '1–10 min'; Cmd = 'Invoke-DriveOptimization'; Confirm = $null }
    @{ Title = 'Restablecer la red'; Text = 'Vacía la caché DNS y restablece Winsock y TCP/IP. Corta la conexión unos segundos y pide reiniciar.'; Time = '≈ 1 min'; Cmd = 'Reset-NetworkStack'; Confirm = 'La conexión se cortará unos segundos y habrá que reiniciar. ¿Continuar?' }
    @{ Title = 'Restablecer Windows Update'; Text = 'Para cuando no descarga o no instala: renombra las cachés y reinicia sus servicios.'; Time = '≈ 1 min'; Cmd = 'Reset-WindowsUpdate'; Confirm = $null }
    @{ Title = 'Sincronizar la hora'; Text = 'Ajusta el reloj con pool.ntp.org y time.windows.com.'; Time = 'segundos'; Cmd = 'Sync-SystemTime'; Confirm = $null }
    @{ Title = 'Reparar winget'; Text = 'Vuelve a registrar el Instalador de aplicación si winget no responde.'; Time = 'segundos'; Cmd = 'Repair-Winget'; Confirm = $null }
    @{ Title = 'Reconstruir caché de iconos'; Text = 'Arregla iconos en blanco o equivocados. Reinicia el Explorador.'; Time = 'segundos'; Cmd = "if (-not `$script:IsDryRun) { & ie4uinit.exe -show; Get-ChildItem `"`$env:LOCALAPPDATA\Microsoft\Windows\Explorer`" -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue; Restart-Explorer; Write-Log 'Caché de iconos reconstruida.' OK } else { Write-Log 'Reconstruir caché de iconos' DRY }"; Confirm = $null }
)

function Build-GuiPageMantenimiento {
    $page = New-GuiPage -Title 'Mantenimiento' -Subtitle 'Reparaciones y mantenimiento de Windows. Cada acción muestra su progreso en el panel inferior.'
    $box = New-GuiSurface -Padding '20,6'
    $list = New-Object System.Windows.Controls.StackPanel
    foreach ($m in $script:GuiMaintenance) {
        $row = New-GuiRow -Columns @('*', '110', 'Auto')
        $row.Margin = '0,12,0,12'
        $texts = New-Object System.Windows.Controls.StackPanel
        $texts.Children.Add((New-GuiText -Text $m.Title -Weight 'SemiBold')) | Out-Null
        $d = New-GuiText -Text $m.Text -Size 13 -Color '#565C67' -Wrap
        $d.Margin = '0,3,16,0'
        $texts.Children.Add($d) | Out-Null
        Add-GuiCell $row $texts 0
        Add-GuiCell $row (New-GuiText -Text $m.Time -Size 13 -Color '#565C67' -Tabular) 1
        $btn = New-GuiButton -Text 'Ejecutar' -Tag $m -OnClick {
            $m = $this.Tag
            if ($m.Confirm -and -not (Show-GuiConfirm $m.Confirm $m.Title)) { return }
            Start-GuiJob -Title $m.Title -Script $m.Cmd
        }
        $btn.Margin = '0'
        $btn.VerticalAlignment = 'Center'
        Add-GuiCell $row $btn 2
        $list.Children.Add((New-GuiListRow -Child $row -Padding '0')) | Out-Null
    }
    $box.Child = $list
    $page.Body.Children.Add($box) | Out-Null
    return $page.Root
}

function Build-GuiPageRed {
    $bench = New-GuiButton -Text 'Medir velocidad' -ToolTip 'Mide cuánto tarda cada proveedor en responder desde esta conexión' -OnClick {
        $started = Start-GuiJob -Title 'Benchmark de DNS' -Script 'Get-DnsBenchmark' -OnDone {
            param($out, $err)
            if ($script:GuiCurrentPage -ne 'Red' -or -not $out) { return }
            $res = @($out[0])
            foreach ($r in $res) {
                $lbl = $script:Gui.DnsTimes[$r.Proveedor]
                if ($lbl) { $lbl.Text = if ($null -eq $r.MedianaMs) { 'sin respuesta' } else { '{0:N1} ms' -f $r.MedianaMs } }
            }
            if ($res.Count -gt 0 -and $null -ne $res[0].MedianaMs) {
                $host_ = $script:Gui.DnsFastHost[$res[0].Proveedor]
                if ($host_) { $host_.Children.Clear(); $host_.Children.Add((New-GuiTape -Text 'Más rápido' -Color 'Green')) | Out-Null }
                Add-GuiLog " + Más rápido desde esta conexión: $($res[0].Proveedor) ($($res[0].MedianaMs) ms)" 'Green'
            }
        }
        # Solo se marca "midiendo" si la tarea arrancó de verdad (si había otra en curso, no arranca).
        if ($started) { foreach ($t in $script:Gui.DnsTimes.Values) { $t.Text = 'midiendo…' } }
    }
    $applyDns = New-GuiButton -Text 'Aplicar DNS' -Kind Primary -OnClick {
        $sel = $script:Gui.DnsRadios | Where-Object { $_.IsChecked } | Select-Object -First 1
        if (-not $sel) { Show-GuiInfo 'Elige un proveedor.'; return }
        $p = $sel.Tag
        if (-not (Show-GuiConfirm "Los adaptadores conectados usarán $($p.Name) ($($p.Servers -join ', ')). Se guarda la configuración anterior para deshacer." 'DNS')) { return }
        Start-GuiJob -Title "DNS: $($p.Name)" -Vars @{ WT_Servers = $p.Servers; WT_Label = $p.Name } -Script 'Set-DnsForActiveAdapters -Servers $WT_Servers -Label $WT_Label' -OnDone { if ($script:GuiCurrentPage -eq 'Red') { Show-GuiPage 'Red' } }
    }
    $auto = New-GuiButton -Text 'Volver a automático' -OnClick {
        if (-not (Show-GuiConfirm 'Los adaptadores conectados volverán a usar el DNS del router o del proveedor.' 'DNS')) { return }
        Start-GuiJob -Title 'DNS automático' -Script 'Set-DnsForActiveAdapters -Servers @() -Label ''automático (DHCP)''' -OnDone { if ($script:GuiCurrentPage -eq 'Red') { Show-GuiPage 'Red' } }
    }
    $auto.Margin = '0'
    $page = New-GuiPage -Title 'Red y DNS' -Subtitle 'Solo se cambia el DNS IPv4 de los adaptadores físicos conectados. El IPv6 queda como está.' -Actions @($bench, $applyDns, $auto)

    $cur = New-GuiSurface
    $cs = New-Object System.Windows.Controls.StackPanel
    $cs.Children.Add((New-GuiHeading 'Ahora')) | Out-Null
    $adapters = @(Get-ActiveAdapters)
    if ($adapters.Count -eq 0) { $cs.Children.Add((New-GuiText -Text 'No hay adaptadores físicos conectados.' -Color '#565C67')) | Out-Null }
    foreach ($a in $adapters) {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
        $r = New-GuiRow -Columns @('220', '*')
        $r.Margin = '0,0,0,6'
        Add-GuiCell $r (New-GuiText -Text $a.Name -Weight 'SemiBold') 0
        Add-GuiCell $r (New-GuiText -Text $(if ($dns) { $dns } else { 'automático' }) -Tabular) 1
        $cs.Children.Add($r) | Out-Null
    }
    $cur.Child = $cs
    $page.Body.Children.Add($cur) | Out-Null

    $page.Body.Children.Add((New-GuiHeading -Text 'Proveedores' -Margin '0,24,0,10')) | Out-Null
    $box = New-GuiSurface -Padding '12,6'
    $list = New-Object System.Windows.Controls.StackPanel
    $script:Gui.DnsRadios = New-Object System.Collections.ArrayList
    $script:Gui.DnsTimes = @{}
    $script:Gui.DnsFastHost = @{}
    foreach ($p in $script:DnsProviders) {
        $row = New-GuiRow -Columns @('*', '220', '110', '120')
        $row.MinHeight = 36
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.GroupName = 'Dns'
        $rb.Tag = $p
        $rb.Content = $p.Name
        [void]$script:Gui.DnsRadios.Add($rb)
        Add-GuiCell $row $rb 0
        Add-GuiCell $row (New-GuiText -Text ($p.Servers -join ', ') -Color '#565C67' -Tabular) 1
        $time = New-GuiText -Text '' -Tabular
        $time.HorizontalAlignment = 'Right'
        $time.Margin = '0,0,16,0'
        $script:Gui.DnsTimes[$p.Name] = $time
        Add-GuiCell $row $time 2
        $fast = New-Object System.Windows.Controls.StackPanel
        $fast.VerticalAlignment = 'Center'
        $script:Gui.DnsFastHost[$p.Name] = $fast
        Add-GuiCell $row $fast 3
        $list.Children.Add((New-GuiListRow -Child $row)) | Out-Null
    }
    $box.Child = $list
    $page.Body.Children.Add($box) | Out-Null
    return $page.Root
}

function Build-GuiPageUpdate {
    $st = $null
    try { $st = Get-WUBlockStatus } catch { }
    $page = New-GuiPage -Title 'Windows Update' -Subtitle 'El bloqueo se aplica como SYSTEM y una tarea guardiana lo mantiene: no se reactiva solo como el de WinUtil.'

    $statusBox = New-GuiSurface
    $ss = New-Object System.Windows.Controls.StackPanel
    $hr = New-GuiRow -Columns @('Auto', '*')
    $hr.Margin = '0,0,0,12'
    Add-GuiCell $hr (New-GuiHeading -Text 'Estado real' -Margin '0,0,12,0') 0
    if ($st) {
        $label = switch ($st.Estado) { 'BLOQUEADO' { if ($st.Modo -eq 'Tienda') { 'Bloqueado · Tienda activa' } else { 'Bloqueado' } } 'PARCIAL' { 'Parcial' } default { 'Activo' } }
        $color = switch ($st.Estado) { 'BLOQUEADO' { 'Red' } 'PARCIAL' { 'Amber' } default { 'Green' } }
        $tape = New-GuiTape -Text $label -Color $color -Size 12
        Add-GuiCell $hr $tape 1
    }
    $ss.Children.Add($hr) | Out-Null
    if ($st) {
        foreach ($r in $st.Detalle) {
            $row = New-GuiRow -Columns @('300', '120', '*')
            $row.MinHeight = 30
            Add-GuiCell $row (New-GuiText -Text $r.Elemento) 0
            # Un color por estado en toda la pantalla: rojo bloqueado, verde activo, gris sin datos o inexistente.
            $t = if ($r.Desconocido) { New-GuiTape -Text 'Sin datos' -Color 'Grey' }
                 elseif ($r.NoExiste) { New-GuiTape -Text 'No existe' -Color 'Grey' }
                 elseif ($r.Bloqueado) { New-GuiTape -Text 'Bloqueado' -Color 'Red' }
                 else { New-GuiTape -Text 'Activo' -Color 'Green' }
            Add-GuiCell $row $t 1
            Add-GuiCell $row (New-GuiText -Text $r.Detalle -Size 13 -Color '#565C67') 2
            $ss.Children.Add($row) | Out-Null
        }
    }
    if ($script:HW.IsHome) {
        $h = New-GuiText -Text 'Windows Home ignora los aplazamientos del modo estable. El bloqueo sí funciona porque actúa sobre servicios y tareas.' -Size 13 -Color '#9A6700' -Wrap
        $h.Margin = '0,10,0,0'
        $ss.Children.Add($h) | Out-Null
    }
    $statusBox.Child = $ss
    $page.Body.Children.Add($statusBox) | Out-Null

    $actions = @(
        @{ Title = 'Desactivar manteniendo Microsoft Store'; Text = 'Windows deja de buscar e instalar actualizaciones por su cuenta. El motor de descarga queda en Manual para que la Tienda siga instalando y actualizando apps.'; Kind = 'Primary'; Button = 'Desactivar'
           Cmd = 'Disable-WindowsUpdateFull -KeepStore'; Confirm = "Windows dejará de actualizarse solo; la Tienda seguirá funcionando.`nLa página de Windows Update de Configuración puede mostrar un error: es esperado.`n`nSe crea un punto de restauración. ¿Continuar?" }
        @{ Title = 'Desactivar por completo'; Text = 'Bloqueo total: la Tienda no podrá descargar apps (error 0x80070422). Defender sigue actualizando sus firmas por su canal propio.'; Kind = 'Danger'; Button = 'Desactivar todo'
           Cmd = 'Disable-WindowsUpdateFull'; Confirm = "Sin Windows Update no llegan parches de seguridad y la Tienda dejará de descargar apps.`n`n¿Desactivarlo por completo?" }
        @{ Title = 'Reactivar Windows Update'; Text = 'Restaura el estado original guardado y limpia los bloqueos de WinUtil y de herramientas parecidas.'; Kind = 'Secondary'; Button = 'Reactivar'
           Cmd = 'Enable-WindowsUpdateFull'; Confirm = '¿Reactivar Windows Update?' }
        @{ Title = 'Modo estable'; Text = 'Parches de seguridad a los 4 días, versiones nuevas de Windows un año después y sin reinicios automáticos con la sesión abierta.'; Kind = 'Secondary'
           Cmd = 'Set-WUStableMode'; Confirm = $null; Button = 'Aplicar' }
        @{ Title = 'No instalar drivers'; Text = 'Útil cuando Windows Update instala un driver de gráfica o audio que da problemas.'; Kind = 'Secondary'
           Cmd = 'Set-WUNoDrivers'; Confirm = $null; Button = 'Aplicar' }
        @{ Title = 'Restaurar políticas por defecto'; Text = 'Quita los aplazamientos y la exclusión de drivers.'; Kind = 'Secondary'
           Cmd = 'Reset-WUPolicies'; Confirm = $null; Button = 'Restaurar' }
    )
    $page.Body.Children.Add((New-GuiHeading -Text 'Acciones' -Margin '0,24,0,10')) | Out-Null
    $box = New-GuiSurface -Padding '20,6'
    $list = New-Object System.Windows.Controls.StackPanel
    foreach ($a in $actions) {
        $row = New-GuiRow -Columns @('*', 'Auto')
        $row.Margin = '0,12,0,12'
        $texts = New-Object System.Windows.Controls.StackPanel
        $texts.Children.Add((New-GuiText -Text $a.Title -Weight 'SemiBold')) | Out-Null
        $d = New-GuiText -Text $a.Text -Size 13 -Color '#565C67' -Wrap
        $d.Margin = '0,3,24,0'
        $texts.Children.Add($d) | Out-Null
        Add-GuiCell $row $texts 0
        $btn = New-GuiButton -Text $a.Button -Kind $a.Kind -Tag $a -OnClick {
            $a = $this.Tag
            if ($a.Confirm -and -not (Show-GuiConfirm $a.Confirm $a.Title 'Warning')) { return }
            Start-GuiJob -Title $a.Title -Script $a.Cmd -OnDone { if ($script:GuiCurrentPage -eq 'Update') { Show-GuiPage 'Update' } }
        }
        $btn.Margin = '0'
        $btn.VerticalAlignment = 'Center'
        Add-GuiCell $row $btn 1
        $list.Children.Add((New-GuiListRow -Child $row -Padding '0')) | Out-Null
    }
    $box.Child = $list
    $page.Body.Children.Add($box) | Out-Null
    $open = New-GuiButton -Text 'Abrir Windows Update' -OnClick { Start-Process 'ms-settings:windowsupdate' }
    $open.HorizontalAlignment = 'Left'
    $open.Margin = '0,12,0,0'
    $page.Body.Children.Add($open) | Out-Null
    return $page.Root
}

function Build-GuiPageApps {
    $hasWinget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
    $install = New-GuiButton -Text 'Instalar seleccionadas' -Kind Primary -OnClick {
        $ids = @($script:Gui.AppChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($ids.Count -eq 0) { Show-GuiInfo 'Marca al menos una app.'; return }
        Start-GuiJob -Title "Instalar $($ids.Count) apps" -Vars @{ WT_Apps = $ids } -Script @'
foreach ($a in $WT_Apps) {
    if ($script:IsDryRun) { Write-Log "winget install $($a.Id)" DRY; continue }
    Write-Log "Instalando $($a.Name)..." STEP
    & winget.exe install --id $a.Id -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Log "$($a.Name) instalado" OK }
    elseif ($LASTEXITCODE -eq -1978335189) { Write-Log "$($a.Name) ya estaba instalado y al día" OK }
    else { Write-Log "$($a.Name): winget devolvió $LASTEXITCODE" WARN }
}
'@
    }
    $upgrade = New-GuiButton -Text 'Actualizar todo' -OnClick {
        if (-not (Show-GuiConfirm 'winget actualizará todas las aplicaciones que tengan versión nueva. Puede tardar varios minutos.' 'Actualizar apps')) { return }
        Start-GuiJob -Title 'Actualizar todas las apps' -Script @'
if ($script:IsDryRun) { Write-Log 'winget upgrade --all' DRY; return }
& winget.exe upgrade --all --silent --accept-source-agreements --accept-package-agreements --include-unknown --disable-interactivity | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Log 'Aplicaciones actualizadas.' OK } else { Write-Log "winget devolvió $LASTEXITCODE (alguna app no se pudo actualizar)." WARN }
'@
    }
    $upgrade.Margin = '0'
    if (-not $hasWinget) { $install.IsEnabled = $false; $upgrade.IsEnabled = $false }
    $sub = if ($hasWinget) { 'Se instalan con winget, en silencio y desde la fuente oficial de cada fabricante.' } else { 'winget no está disponible en este equipo. Repáralo en Mantenimiento › Reparar winget.' }
    $page = New-GuiPage -Title 'Apps' -Subtitle $sub -Actions @($install, $upgrade)
    $cols = New-GuiRow -Columns @('*', '20', '*')
    $left = New-Object System.Windows.Controls.StackPanel
    $right = New-Object System.Windows.Controls.StackPanel
    $script:Gui.AppChecks = New-Object System.Collections.ArrayList
    $cats = @($script:WingetApps | ForEach-Object { $_.Cat } | Select-Object -Unique)
    $half = [math]::Ceiling($cats.Count / 2)
    for ($i = 0; $i -lt $cats.Count; $i++) {
        $target = if ($i -lt $half) { $left } else { $right }
        $target.Children.Add((New-GuiHeading -Text $cats[$i] -Margin '0,0,0,8')) | Out-Null
        $box = New-GuiSurface -Padding '12,4'
        $box.Margin = '0,0,0,18'
        $sp = New-Object System.Windows.Controls.StackPanel
        foreach ($a in @($script:WingetApps | Where-Object { $_.Cat -eq $cats[$i] })) {
            $r = New-GuiCheckRow -Text $a.Name -Right '' -Tag ([pscustomobject]@{ Id = $a.Id; Name = $a.Name }) -Checked:$false -Sub $a.Id
            [void]$script:Gui.AppChecks.Add($r.Check)
            $sp.Children.Add($r.Element) | Out-Null
        }
        $box.Child = $sp
        $target.Children.Add($box) | Out-Null
    }
    Add-GuiCell $cols $left 0
    Add-GuiCell $cols $right 2
    $page.Body.Children.Add($cols) | Out-Null
    return $page.Root
}

function Build-GuiPageDeshacer {
    $restore = New-GuiButton -Text 'Abrir Restaurar sistema' -OnClick { Start-Process rstrui.exe }
    $folder = New-GuiButton -Text 'Abrir carpeta de respaldos' -OnClick { Start-Process explorer.exe $script:BackupDir }
    $folder.Margin = '0'
    $page = New-GuiPage -Title 'Deshacer' -Subtitle 'Cada respaldo guarda el valor ORIGINAL de cada cambio. Deshaz primero los más recientes.' -Actions @($restore, $folder)
    $journals = @(Get-GuiJournals)
    $box = New-GuiSurface -Padding '12,6'
    $list = New-Object System.Windows.Controls.StackPanel
    if ($journals.Count -eq 0) {
        $list.Children.Add((New-GuiText -Text 'Todavía no hay respaldos. Se crean automáticamente al aplicar cualquier cambio.' -Color '#565C67')) | Out-Null
    }
    foreach ($j in $journals) {
        $row = New-GuiRow -Columns @('80', '150', '*', '110', 'Auto')
        $row.MinHeight = 40
        Add-GuiCell $row (New-GuiTape -Text $j.Numero -Color $(if ($j.Deshecho) { 'Grey' } else { 'Black' })) 0
        Add-GuiCell $row (New-GuiText -Text $j.Fecha.ToString('dd/MM/yyyy HH:mm') -Color '#565C67' -Tabular) 1
        Add-GuiCell $row (New-GuiText -Text $j.Etiqueta -Weight $(if ($j.Deshecho) { 'Normal' } else { 'SemiBold' }) -Color $(if ($j.Deshecho) { '#6B717C' } else { '#16181D' })) 2
        Add-GuiCell $row (New-GuiText -Text "$($j.Cambios) cambios" -Color '#565C67' -Tabular) 3
        if ($j.Deshecho) {
            Add-GuiCell $row (New-GuiTape -Text 'Deshecho' -Color 'Grey') 4
        } else {
            $btn = New-GuiButton -Text 'Deshacer' -Tag $j -OnClick {
                $j = $this.Tag
                if (-not (Show-GuiConfirm "Se revertirán los $($j.Cambios) cambios de $($j.Numero) «$($j.Etiqueta)» a su valor original." 'Deshacer' 'Warning')) { return }
                Start-GuiJob -Title "Deshacer $($j.Numero)" -Vars @{ WT_File = $j.Archivo } -Script 'Invoke-UndoJournal -Path $WT_File' -OnDone { if ($script:GuiCurrentPage -eq 'Deshacer') { Show-GuiPage 'Deshacer' } }
            }
            $btn.Margin = '0'
            Add-GuiCell $row $btn 4
        }
        $list.Children.Add((New-GuiListRow -Child $row -Padding '4,6')) | Out-Null
    }
    $box.Child = $list
    $page.Body.Children.Add($box) | Out-Null
    return $page.Root
}

function Initialize-WinTurboGui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $win = [System.Windows.Markup.XamlReader]::Parse($script:GuiXaml)
    $script:Gui.Window = $win
    foreach ($n in 'BrandHost', 'NavHost', 'SimToggle', 'RailInfo', 'PageHost', 'LogBox', 'JobTitle', 'JobProgress', 'JobStatus', 'JobBackup') {
        $script:Gui[$n] = $win.FindName($n)
    }
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Width = [math]::Min(1360, $wa.Width - 24)
    $win.Height = [math]::Min(860, $wa.Height - 24)
    # En pantallas bajas (portátil 1366x768 con escalado) el registro cede espacio al contenido.
    $win.Add_SizeChanged({ Set-GuiLogExpanded ([bool]$script:GuiLogExpanded) })

    $brand = New-GuiTape -Text 'WinTurbo' -Color 'Blue' -Size 15
    $brand.Padding = '10,4,10,4'
    $script:Gui.BrandHost.Children.Add($brand) | Out-Null
    $ver = New-GuiText -Text $script:Version -Size 12 -Color '#8A8F99'
    $ver.Margin = '10,0,0,0'
    $script:Gui.BrandHost.Children.Add($ver) | Out-Null

    $script:Gui.NavButtons = @{}
    $script:Gui.NavCounts = @{}
    foreach ($item in $script:GuiNav) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $win.FindResource('NavItem')
        $rb.Tag = $item.Icon
        $content = New-GuiRow -Columns @('*', 'Auto')
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $item.Label
        Add-GuiCell $content $lbl 0
        $cnt = New-Object System.Windows.Controls.TextBlock
        $cnt.Foreground = ConvertTo-GuiBrush '#8A8F99'
        $cnt.FontSize = 12
        [System.Windows.Documents.Typography]::SetNumeralAlignment($cnt, 'Tabular')
        Add-GuiCell $content $cnt 1
        $rb.Content = $content
        [System.Windows.Automation.AutomationProperties]::SetName($rb, $item.Label)
        $rb.Add_Checked([scriptblock]::Create("Show-GuiPage '$($item.Id)'"))
        $script:Gui.NavButtons[$item.Id] = $rb
        $script:Gui.NavCounts[$item.Id] = $cnt
        $script:Gui.NavHost.Children.Add($rb) | Out-Null
    }

    $script:Gui.SimToggle.IsChecked = $script:IsDryRun
    $script:Gui.SimToggle.Add_Click({
        $script:IsDryRun = [bool]$this.IsChecked
        $script:Gui.Window.Title = if ($script:IsDryRun) { 'WinTurbo · modo simulación' } else { 'WinTurbo' }
        Add-GuiLog $(if ($script:IsDryRun) { ' ~ Modo simulación activado: no se cambiará nada.' } else { ' + Modo simulación desactivado: los cambios se aplicarán.' }) $(if ($script:IsDryRun) { 'Cyan' } else { 'Green' })
        Show-GuiPage $script:GuiCurrentPage
    })
    if ($script:IsDryRun) { $win.Title = 'WinTurbo · modo simulación' }

    $script:Gui.LogBox.Document.PagePadding = '0'
    $script:Gui.LogBox.Document.Blocks.Clear()
    # Dos líneas cortas: caben sin ajuste en la franja plegada incluso a tamaño de portátil.
    Add-GuiLog ("WinTurbo $($script:Version) · $($env:COMPUTERNAME) · build $($script:HW.Build)") 'DarkGray'
    Add-GuiLog "Respaldos: $($script:BackupDir)" 'DarkGray'
    $script:Gui.JobProgress.Visibility = 'Collapsed'
    $script:Gui.JobStatus.Text = 'El registro se despliega al empezar una tarea.'
    Set-GuiLogExpanded $false

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({ Invoke-GuiTick })
    $timer.Start()
    $script:Gui.Timer = $timer

    $win.Add_Closing({
        param($sender, $e)
        if ($script:GuiBusy) {
            $r = [System.Windows.MessageBox]::Show($script:Gui.Window, 'Hay una tarea en curso. Si cierras ahora, puede quedar a medias. ¿Cerrar igualmente?', 'WinTurbo', 'YesNo', 'Warning')
            if ($r -ne 'Yes') { $e.Cancel = $true; return }
        }
        $script:Gui.Timer.Stop()
        foreach ($j in @($script:GuiJobs)) { try { $j.PS.Stop(); $j.PS.Dispose(); $j.RS.Close() } catch { } }
    })

    Update-GuiRail
    $script:Gui.NavButtons['Panel'].IsChecked = $true
    return $win
}

function Show-WinTurboGui {
    # Una sola ventana a la vez: dos instancias podrían aplicar y deshacer cambios cruzados.
    $created = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Global\WinTurboGui', [ref]$created)
    if (-not $created) {
        Add-Type -AssemblyName PresentationFramework
        [void][System.Windows.MessageBox]::Show('WinTurbo ya está abierto en este equipo.', 'WinTurbo', 'OK', 'Information')
        $mutex.Dispose()
        return
    }
    try {
        $win = Initialize-WinTurboGui
    # La consola queda minimizada mientras la ventana está abierta.
    try {
        if (-not ('WinTurboNative' -as [type])) {
            Add-Type -Name WinTurboNative -Namespace '' -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
        }
        $hwnd = [WinTurboNative]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) { [void][WinTurboNative]::ShowWindow($hwnd, 6) }
    } catch { }
    [void]$win.ShowDialog()
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

#endregion

#region ===================== Punto de entrada =====================

New-Item -ItemType Directory -Force -Path $script:DataDir, $script:BackupDir, $script:LogDir | Out-Null
$script:LogFile = Join-Path $script:LogDir ("winturbo-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
if (-not $LibraryMode) { try { $Host.UI.RawUI.WindowTitle = "WinTurbo $script:Version (Administrador)" } catch { } }

if (-not $LibraryMode) { Write-Host '  Analizando el equipo...' -ForegroundColor DarkGray }
# En modo librería la interfaz pasa el perfil ya calculado ($WT_HW) para no repetir las consultas CIM en cada tarea.
if ($LibraryMode -and $WT_HW) { $script:HW = $WT_HW } else { $script:HW = Get-HardwareProfile }
if ($LibraryMode) { $script:UserMatch = $true } else { $script:UserMatch = Test-InteractiveUserMatch }

# Modo librería: la interfaz gráfica carga aquí las funciones en sus hilos de trabajo y no abre ningún menú.
if ($LibraryMode) { return }

Write-Log ("Inicio WinTurbo {0} en {1} ({2}, build {3})" -f $script:Version, $env:COMPUTERNAME, $script:HW.OSName, $script:HW.Build) | Out-Null

if ($DisableUpdates) { Disable-WindowsUpdateFull -KeepStore:$KeepStore; return }
if ($EnableUpdates)  { Enable-WindowsUpdateFull; return }
if ($Undo)   { Show-UndoMenu; return }
if ($Report) { Show-Report; return }

if ($Preset) {
    Invoke-TweakSet -Ids (Get-PresetIds $Preset) -Label "Preset $Preset"
    return
}

if ($ConfigFile) {
    try {
        $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
        Invoke-TweakSet -Ids @($cfg.Tweaks | ForEach-Object { [string]$_ }) -Label "Config $(Split-Path $ConfigFile -Leaf)"
    } catch {
        Write-Log "No se pudo leer $ConfigFile : $($_.Exception.Message)" ERROR
    }
    return
}

if ($Console -or -not $script:ScriptPath) {
    # Sin ruta de archivo (por ejemplo, ejecutado con irm | iex) la interfaz no puede lanzar sus tareas en segundo plano.
    if (-not $Console) { Write-Log 'Ejecutado sin archivo .ps1: se usa el menú de consola. Guarda el script para tener la interfaz gráfica.' WARN }
    Show-MainMenu
} else {
    try {
        Show-WinTurboGui
    } catch {
        Write-Log "No se pudo abrir la interfaz gráfica: $($_.Exception.Message)" ERROR
        Write-Log 'Se abre el menú de consola.' WARN
        Show-MainMenu
    }
}
Write-Log 'WinTurbo finalizado.'

#endregion

# SIG # Begin signature block
# MIIdiAYJKoZIhvcNAQcCoIIdeTCCHXUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAWLVKXrob8tE9y
# 4Tdz0e73RrcBMqNdLy56QVxV1ha8c6CCF04wggQQMIICeKADAgECAhBxLBZn55Hy
# gk1xJuVa1jCNMA0GCSqGSIb3DQEBCwUAMCAxHjAcBgNVBAMMFVdpblR1cmJvIENv
# ZGUgU2lnbmluZzAeFw0yNjExMDkyMjU5MDlaFw0zMTExMDkyMzA5MDlaMCAxHjAc
# BgNVBAMMFVdpblR1cmJvIENvZGUgU2lnbmluZzCCAaIwDQYJKoZIhvcNAQEBBQAD
# ggGPADCCAYoCggGBAJx9BBMQqRMM5FxJpMMpplhfkjW3sVCMV/Z74mGK7UFIorG3
# z5elzsIqhzfyuLCz+qfoW0e2ddIMmgxrRoVsHNDsjrS4ekUZPGfNQGGB2loBQj3R
# KlLVoF6QA/yy1tpM9c1oEKZ072pQW6trbD0D982Eq5p7894LhasYtJk5n1TsTCFD
# nWhWUVLu93V4W3rmB3mK8O8B5R+sTZNpQJPAxWWP5yR46JxJo9Kma12Y7mkz71u4
# uaz/OpNn8k5d7NMXah9Nuph3HgFaOD5Qo/6drKE5CLevBJAWFuEOsE40BAUJSIGl
# 6H66Q3MQJoSbDNlN4xcCWip8ycr+qdR2KOFyLdKEe1T4tVneKAaFfMzZZtrqpPuf
# jZ0pK9Sv11jka6KPNsD7am5N0m+xRFH6fPLOylN5XHo0vDsPyCEZMxjuBdJn73JV
# 7lAGe2cZ2/vJqxqM7uCBPMDa/Ws7zyi4hgLM60IA/Nv7lWsEQUlK0viSpvVEFc1g
# JImggZt4bKFkiqRwrQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAww
# CgYIKwYBBQUHAwMwHQYDVR0OBBYEFCJqoSng571+YU2QtMJTrsZLsqnwMA0GCSqG
# SIb3DQEBCwUAA4IBgQA+2NThCgc6NkjZoDsDcWVdM8mRe4WDPFn71d3Lf8rxHQA6
# ukvKLnyX7TKDFOWYpVa9FWmQjGLB+YIFRhNuw7glzcTaUv5exn9URZtCpkTKIDn3
# PUS5QjVnAAVJ7ulSEKa2QF/8K62rfcCLROHluC9XJYw2+B/PA8/FA7v8idwabuky
# LGzdR76WWupfII6L7GOIi9EIp1AkrI0MG69aakAIHFWgyIT9jgDo+kezkNr0TPaW
# xDgPBz5DFIE+E/iNuSqwpGdwzEyGXgELaHMqCPIRsh8zrXISNwV4tF9q0DGaqC0i
# WKDfttnvVqz/XJlxulczVv8pofAkch9CtRVLzXkXjIXbQBDJ9bySQCWYn6r3lgQz
# 7qz5bnaEv231d5IXFPr1Rcbh6GGScuqjdBR2ntQPCbUGXTdvhI5Lok7EK5EONSJx
# JbmxsINYkpy6LSDcuJsmbymIa35SyKcYKQbazZ8lXjedboDkskat3kHj/9vxUQHy
# bNs4wdiCZjMMlgwhTywwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0G
# CSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0
# IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5
# NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQg
# Um9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvk
# XUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdt
# HauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu
# 34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0
# QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2
# kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM
# 1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmI
# dph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZ
# K37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72
# gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqs
# X40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyh
# HsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8E
# BTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAW
# gBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUH
# AQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYI
# KwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAE
# CjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX
# 979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offy
# ct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3
# J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0
# d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6ts
# ds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQw
# gga0MIIEnKADAgECAhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBH
# NDAeFw0yNTA1MDcwMDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1
# c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0Zo
# dLRRF51NrY0NlLWZloMsVO1DahGPNRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi
# 6wuim5bap+0lgloM2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNg
# xVBdJkf77S2uPoCj7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiF
# cMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJ
# m/s80FiocSk1VYLZlDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvS
# GmhgaTzVyhYn4p0+8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1
# ZlAeSpQl92QOMeRxykvq6gbylsXQskBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9
# MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7
# Yk/ehb//Wx+5kMqIMRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bG
# RinZbI4OLu9BMIFm1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6
# X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAd
# BgNVHQ4EFgQU729TSunkBnx6yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJx
# XWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUF
# BwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGln
# aWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJo
# dHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNy
# bDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQEL
# BQADggIBABfO+xaAHP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxj
# aaFdleMM0lBryPTQM2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0
# hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0
# F8HABBgr0UdqirZ7bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnT
# mpfeQh35k5zOCPmSNq1UH410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKf
# ZxAvBAKqMVuqte69M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzE
# wlvzZiiyfTPjLbnFRsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbh
# OhZ3ZRDUphPvSRmMThi0vw9vODRzW6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOX
# gpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EO
# LLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wG
# WqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZsq8WhbaM2tszWkPZPubdcMIIG7TCCBNWg
# AwIBAgIQCE/cM09+RU7bww+P+ZIYNTANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQG
# EwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0
# IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0Ex
# MB4XDTI2MDgwNTAwMDAwMFoXDTM3MTEwNDIzNTk1OVowYzELMAkGA1UEBhMCVVMx
# FzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEy
# NTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVyIDIwMjYgMTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBALZ7pvLJ/s1K+NSbTGWz/TjGMPh8CQ6RucZC
# Lv5anHzWJjF/NWJrFIhy24fcpKXlgRiky4WAawDfU3YP0BMxt9l3Dm5oCG5Z69Aq
# EN1kgHg2epx+l+lZBcmJCcN0ASURML5uFIS80sZsDwO3BSkUxDjLJhBI+qiZP3ai
# xAC/qEGLjsBNlLol9VZ7pfGEXiMlneJIC5/YKuizVzNFKZZEeoy/0B8Zm+nzKBgS
# WG52lCO1w+nCg6XpCtklTJXeIg283hw7TmmsZXR+SMbjbrEOvZ3fP2VxIgeR28Y9
# 0ZStd3F9VuA5RVynb/whITPAo9b75Zr4Ta6Mj3URm26QZYMn/FnbuTegcoRcFEZ9
# FOqM5T6MTdtr/n74lIT/ug0eeOzmZ6QTFg33otX+bFRsIolvykE1jive4PuESaT8
# zzVeFWDAMDtozNgLctkGD1ZjkEyZtJrLl5ya0m5doH/ScpaZCZVl6pNUOCybMc/k
# xC6EAmSJY24L0yYKD1Nkddsnb/ItVKi/2nXpQNMu1PT5prW83vV8d67WowuUs0Hd
# Y4H8AMLGvdL/WHEj3ZnqMqAQQP9u3Ai9t+5eQ02GDwy0ODjdzi0xlp70W+ow63/0
# ++YDEX1M0iwgUHwbrJvfpklkZQvw3+kv3vUPItdwroczk9icflf55W1zOEKAcJVA
# IXpcMCU9AgMBAAGjggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBQUyWOK
# MC7USvtulPPm40B+9ezN4jAfBgNVHSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezL
# TjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsG
# AQUFBwEBBIGIMIGFMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5j
# b20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNy
# dDBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5j
# cmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEB
# CwUAA4ICAQCNxTphHp1SCt+ZrAmAfn0oQLFr0mLywSLaDXQIENoyKqxrFbJblzCV
# P/pkXmwXOdrOpWygLzlT12os5ipDCy35RBCg2UMeApEtrfGhz45F4Wt4WGdNdIbR
# Wt3YTYJmpR+b7lr4d7Uwn+H600u4D7RnOGf8Wj4UNgAdZkfHhHv1mx9EVh71SJel
# cEN/oORSjXzdjfw1iZH9d8Nh/thn6hH23d+VsPAr6GAYyzSA02nXD1nYLI7Ijmiv
# +xLCiYC41DSFYL3GhTiy0PxpawPtGRyaBVGzq+UiTfM8pD7KVyF5aQyWP4KhVGUU
# Tnmm/RlYJoW3TiXA/+t0YcT2oRVBm3JETjajHug2AL+v5jhtKVnd3D0rbHXEu27o
# +Q8p4sEWPMqKDB+qbceb6T/6WcwTwXmQ9lOCLLYcsQeSWmvKqzpAec9etE14jOQA
# zLKWdE3w/TCaKtLRaRT7LCkRYVnhA2D73FLje1O5b3HR5eHs0NzU/+xX7NbEdcof
# y0W3Wdwd1XOqtlpg/JgwtKfZM5dqO94lbUveOiJBI+xZEbGRsMNbXmMREUTgu+Oc
# a7Y73MPWcslIx2VhkSKSXjDbD6rgg39H5Mh7QfieAIjWagkJNt68Yfim6cjEzVSi
# LSeZfdkr5dtFPTW6jATlWJdYeeDRGCyatf8R1hSjzSvdN8yWQPT9gzGCBZAwggWM
# AgEBMDQwIDEeMBwGA1UEAwwVV2luVHVyYm8gQ29kZSBTaWduaW5nAhBxLBZn55Hy
# gk1xJuVa1jCNMA0GCWCGSAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKA
# AKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPQkN76tbauGteU44138rUkN
# sex5tBCoIOlvHIpIZ0NzMA0GCSqGSIb3DQEBAQUABIIBgId3w/DsOIknnBunvvwP
# PRaYq48Xx8+vEErLZQimMU0oZoTBjSbijqkoMd+aI8aEiBDxz8YcpQXL2j76mzJW
# sz8CIAbFBw2TTeSDNy18AlSXXXCbBxMYj1tsoBPgRSS45o1I7EII9Ah3AT+getWi
# YQavbDAX3lCPa+/+3VJ29HHauXeyQz5coyxIR87u2OAlS+tYPHrKExVVPV2qwCY+
# v0YjLU2rDMGiDn8OkxSqFS/EykaIXogz8nhBqVz8ZNq9NAbk+BCZauVjWt9QeaUx
# DFacWDHpZn3yAaf3SgJRPNhcqFW7VnjSxSbUAj19eo48xqRm3cU5IGwcPs6Q0vL5
# tetMDAZRm44v0XLn2y/hkxuqOySoQtmghmWL651IOl5qaamUAW31PzEGUh4yuweW
# 1mjGjQxyiO/47DDWQf722Qfwuxmq8JrxRzYISINBIjOjl8u3NTI7kO+9Rda82Cpe
# mVIvMJW7SVQUpHFF7UKxADJfDPfFXIyvsdZC8Zh8nE7gnKGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjExMDkyMzA5MzRaMC8GCSqGSIb3DQEJBDEiBCAg2V/h6Dvn
# 3gv7oEVjalozg97aMYLGYdGoCOevdFrWLTANBgkqhkiG9w0BAQEFAASCAgBGBkdO
# f09UxFxdp0sMJfvf5wPBCk+0jbpm44SV2x4sW3tSy+2erAPOl0UcZ2ahu2M+yEuw
# rl4QFL2Mr1Q9BJ5mrXk/4OOj6LQrL4/+Efn3qgctbzzTl8ZUm1Z7nUyrPFUWveNI
# lrJ9iWK9GMqQLUVr0fMKin/w3Oq7Oi7WWRENKu0gmjUGUcjnsDVhltEIImqRZF0d
# gWw0UwAXQNFsorsbWV1JdQLlkG8aDevvgwzd86TKo9J3/9r/PhQGNOG+cZfSHtyl
# PB0thrhoSsF/UqZKd/k9ga4uq/3uRrMkQkz/wi+CLs4B8bWOEXf73XPeikl3tMpr
# C2MeSiIY0C7iuD2duvdenOYlT6Dgun/eLTlewnYzgyL2v8u3VnGtCfIlOwOY/PTF
# ZbV9juJmVacGue2qqfeC4E429P0Gbzxw17Gq01W+raAuXYOi0GpEVwCUP0Kd2UIg
# m06zc6bjTyrjy/U9RkvAIQcIk7sL8weDGSklB0H/vFayeZqH+bqsnXR+3hgUp2Rf
# 5uupzhTeLXGxInqzN/huO01SFEbB0yPsL69Y0WUyvo2PYthF2iFfzCIZmbbdctIy
# RvC6SuaLEzhefA03QP+nbf8jH7VKabnCUWXtm868ndJPpmNpI8y+gLko6aQVqTNL
# A25ZBACCM6WPYsJOotDSuZYEeru4sLYEsTkkrw==
# SIG # End signature block
