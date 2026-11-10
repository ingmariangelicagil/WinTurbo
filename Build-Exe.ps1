#Requires -Version 5.1
<#
.SYNOPSIS
    Compila WinTurbo.exe: un único ejecutable con WinTurbo.ps1 embebido.
.DESCRIPTION
    Usa el compilador de C# que trae Windows (.NET Framework 4), sin descargar nada.
    Vuelve a ejecutarlo cada vez que cambies WinTurbo.ps1 para regenerar el .exe.
.PARAMETER CertThumbprint
    Huella del certificado de firma de código (Cert:\CurrentUser\My o Cert:\LocalMachine\My).
    Si no se indica, se usa el certificado "CN=WinTurbo Code Signing" si existe.
    Para quitar el aviso de SmartScreen en equipos de clientes hace falta un certificado comercial (OV/EV).
.PARAMETER TimestampServer
    Servidor de sellado de tiempo: la firma sigue siendo válida aunque el certificado caduque.
    Solo se le envía el hash del archivo.
.PARAMETER NoSign
    Compila sin firmar.
.EXAMPLE
    .\Build-Exe.ps1
.EXAMPLE
    .\Build-Exe.ps1 -CertThumbprint 0123ABCD...   # con un certificado comercial
#>
[CmdletBinding()]
param(
    [string]$Output,
    [string]$CertThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [switch]$NoSign
)

$ErrorActionPreference = 'Stop'
# En PowerShell 5.1 $PSScriptRoot no está disponible en los valores por defecto de param().
if (-not $Output) { $Output = Join-Path $PSScriptRoot 'dist\WinTurbo.exe' }
$root = $PSScriptRoot
$script = Join-Path $root 'WinTurbo.ps1'
$build = Join-Path $root 'build'
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'No se encontró csc.exe (.NET Framework 4). Viene con Windows 10/11.' }

# 1. El script debe ser válido antes de embeberlo.
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "WinTurbo.ps1 tiene $($errors.Count) errores de sintaxis; corrígelos antes de compilar." }

# 1b. Certificado de firma.
$cert = $null
if (-not $NoSign) {
    $stores = 'Cert:\CurrentUser\My', 'Cert:\LocalMachine\My'
    $cert = if ($CertThumbprint) {
        $stores | ForEach-Object { Get-ChildItem $_ -CodeSigningCert -ErrorAction SilentlyContinue } | Where-Object { $_.Thumbprint -eq $CertThumbprint } | Select-Object -First 1
    } else {
        Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -eq 'CN=WinTurbo Code Signing' -and $_.NotAfter -gt (Get-Date) } |
            Sort-Object NotAfter -Descending | Select-Object -First 1
    }
    if (-not $cert) { throw 'No se encontró el certificado de firma. Indica -CertThumbprint o compila con -NoSign.' }
    if (-not $cert.HasPrivateKey) { throw "El certificado $($cert.Thumbprint) no tiene clave privada en este equipo." }
    Write-Host "Firmando con: $($cert.Subject) ($($cert.Thumbprint))"
}

function Invoke-Sign {
    param([string]$Path)
    # Con sello de tiempo si el servidor responde; si no, se firma igualmente y se avisa.
    $sig = Set-AuthenticodeSignature -FilePath $Path -Certificate $cert -HashAlgorithm SHA256 -TimestampServer $TimestampServer -ErrorAction SilentlyContinue
    if (-not $sig -or -not $sig.SignerCertificate) {
        Write-Warning "Sin respuesta de $TimestampServer : se firma sin sello de tiempo (la firma caducará con el certificado)."
        $sig = Set-AuthenticodeSignature -FilePath $Path -Certificate $cert -HashAlgorithm SHA256
    }
    if (-not $sig.SignerCertificate) { throw "No se pudo firmar $Path : $($sig.StatusMessage)" }
    Write-Host ("  firmado: {0}  [{1}]" -f (Split-Path $Path -Leaf), $(if ($sig.TimeStamperCertificate) { 'con sello de tiempo' } else { 'sin sello de tiempo' }))
}

# 1c. Firmar el script ANTES de embeberlo: el .ps1 que extrae el .exe también va firmado.
if ($cert) { Invoke-Sign -Path $script }

# 2. Icono: la cinta azul de la marca con «WT» (se genera una vez).
$icon = Join-Path $build 'WinTurbo.ico'
if (-not (Test-Path $icon)) {
    Add-Type -AssemblyName System.Drawing
    $sizes = 16, 32, 48, 256
    $pngs = foreach ($s in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap $s, $s
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $g.Clear([System.Drawing.Color]::Transparent)
        $pad = [math]::Max(1, [int]($s * 0.06))
        $rect = New-Object System.Drawing.Rectangle $pad, ([int]($s * 0.22)), ($s - 2 * $pad), ([int]($s * 0.56))
        $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 31, 111, 235))), $rect)
        $gloss = New-Object System.Drawing.Rectangle $rect.X, $rect.Y, $rect.Width, ([math]::Max(1, [int]($s / 32)))
        $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 255, 255, 255))), $gloss)
        $fontName = if ((New-Object System.Drawing.Text.InstalledFontCollection).Families.Name -contains 'Bahnschrift') { 'Bahnschrift' } else { 'Segoe UI' }
        $font = New-Object System.Drawing.Font $fontName, ([float]($s * 0.36)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
        $g.DrawString('WT', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF $rect.X, $rect.Y, $rect.Width, $rect.Height), $fmt)
        $g.Dispose()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        , $ms.ToArray()
    }
    # Contenedor ICO con imágenes PNG (admitido desde Windows Vista).
    $fs = [System.IO.File]::Create($icon)
    $bw = New-Object System.IO.BinaryWriter $fs
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]; $len = $pngs[$i].Length
        $bw.Write([byte]($s % 256)); $bw.Write([byte]($s % 256)); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
        $offset += $len
    }
    foreach ($p in $pngs) { $bw.Write($p) }
    $bw.Close()
}

# 3. Compilar.
New-Item -ItemType Directory -Force -Path (Split-Path $Output) | Out-Null
$cscArgs = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
    "/out:$Output",
    "/win32manifest:$(Join-Path $build 'app.manifest')",
    "/win32icon:$icon",
    "/resource:$script,WinTurbo.ps1",
    '/reference:System.Windows.Forms.dll',
    (Join-Path $build 'Launcher.cs')
)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "csc.exe falló con código $LASTEXITCODE." }

# 4. Firmar el ejecutable y exportar el certificado público (para marcarlo como de confianza en tus equipos).
if ($cert) {
    Invoke-Sign -Path $Output
    $cer = Join-Path (Split-Path $Output) 'WinTurbo-firma.cer'
    [IO.File]::WriteAllBytes($cer, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    Write-Host "  certificado público: $cer"
}

$hash = (Get-FileHash $Output -Algorithm SHA256).Hash
Set-Content -Path "$Output.sha256" -Value "$hash  $(Split-Path $Output -Leaf)" -Encoding ASCII
Write-Host "Listo: $Output ($([math]::Round((Get-Item $Output).Length / 1KB)) KB)" -ForegroundColor Green
Write-Host "SHA-256: $hash"
