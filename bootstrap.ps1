[CmdletBinding()]
param(
    [string]$RepoOwner = 'olshhhh',
    [string]$RepoName = 'ShadeVeil',
    [string]$Branch = 'main',
    [string]$BaseUrl = '',
    [switch]$Cli,
    [string]$Profile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}
catch {
    # Ignore if overridden by machine/user GPO
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$appName = 'ShadeVeil'
$logDir = Join-Path (Join-Path $env:LOCALAPPDATA $appName) 'Logs'
$lastErrorLog = Join-Path $logDir 'last_error.log'

$manifestFiles = @(
    'ShadeVeil.ps1',
    'Core/Win32Interop.psm1',
    'Core/ConfigManager.psm1',
    'Core/OverlayManager.psm1',
    'UI/MainWindow.xaml',
    'UI/GuiController.psm1',
    'UI/CliController.psm1',
    'Data/presets.json'
)

$resolvedBaseUrl = if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"
}
else {
    $BaseUrl.TrimEnd('/')
}

$volatileRoot = Join-Path $env:TEMP ("$appName`_" + [Guid]::NewGuid().ToString('N'))

try {
    Write-Host ''
    Write-Host "[$appName] Preparando entorno temporal Zero-Install..." -ForegroundColor Cyan

    [void](New-Item -Path $volatileRoot -ItemType Directory -Force)

    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8

    try {
        $cacheBust = [DateTime]::UtcNow.Ticks
        foreach ($relPath in $manifestFiles) {
            $normalizedRel = $relPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $destPath = Join-Path $volatileRoot $normalizedRel
            $destDir = Split-Path -Path $destPath -Parent
            if (-not (Test-Path -LiteralPath $destDir)) {
                [void](New-Item -Path $destDir -ItemType Directory -Force)
            }

            $downloadUrl = "$resolvedBaseUrl/$relPath`?cb=$cacheBust"
            $webClient.Headers.Clear()
            $webClient.Headers.Add('Cache-Control', 'no-cache')
            $content = $webClient.DownloadString($downloadUrl)

            $ext = [System.IO.Path]::GetExtension($relPath).ToLowerInvariant()
            $encoding = if ($ext -in @('.ps1', '.psm1')) { $utf8WithBom } else { $utf8NoBom }
            [System.IO.File]::WriteAllText($destPath, $content, $encoding)
        }
    }
    finally {
        $webClient.Dispose()
    }

    $orchestratorPath = Join-Path $volatileRoot 'ShadeVeil.ps1'
    if (-not (Test-Path -LiteralPath $orchestratorPath)) {
        throw "No se pudo verificar el orquestador descargado en: $orchestratorPath"
    }

    $launchArgs = @(
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy', 'Bypass',
        '-File', $orchestratorPath
    )

    if ($Cli) {
        $launchArgs += '-Cli'
    }
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $launchArgs += @('-Profile', $Profile)
    }

    Write-Host "[$appName] Iniciando aplicacion..." -ForegroundColor Green
    & powershell.exe @launchArgs

    if ($LASTEXITCODE -ne 0) {
        throw "ShadeVeil finalizo con codigo de salida inesperado: $LASTEXITCODE"
    }
}
catch {
    $errMessage = $_.Exception.Message
    $errStack = $_.ScriptStackTrace

    try {
        if (-not (Test-Path -LiteralPath $logDir)) {
            [void](New-Item -Path $logDir -ItemType Directory -Force)
        }
        $logBody = @(
            "Timestamp: $(Get-Date -Format 'o')"
            "BaseUrl: $resolvedBaseUrl"
            "Error: $errMessage"
            "StackTrace:"
            "$errStack"
        ) -join [Environment]::NewLine
        $utf8Log = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($lastErrorLog, $logBody, $utf8Log)
    }
    catch {
        # Best effort logging
    }

    Write-Host ''
    Write-Host "[$appName] ERROR CRITICO: $errMessage" -ForegroundColor Red
    Write-Host "Detalle registrado en: $lastErrorLog" -ForegroundColor Yellow
    [void](Read-Host 'Presiona ENTER para cerrar')
}
finally {
    if (Test-Path -LiteralPath $volatileRoot) {
        Remove-Item -LiteralPath $volatileRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
