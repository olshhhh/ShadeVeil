[CmdletBinding()]
param(
    [switch]$Cli,
    [string]$Profile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure STA apartment when running GUI directly from an MTA host
if (-not $Cli -and ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA)) {
    $relaunchArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $relaunchArgs += @('-Profile', $Profile)
    }
    $shellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $shellExe)) { $shellExe = 'powershell.exe' }
    $proc = Start-Process -FilePath $shellExe -ArgumentList $relaunchArgs -NoNewWindow -Wait -PassThru
    exit $proc.ExitCode
}

$scriptRoot = $PSScriptRoot
$coreDir = Join-Path $scriptRoot 'Core'
$uiDir = Join-Path $scriptRoot 'UI'
$dataDir = Join-Path $scriptRoot 'Data'

Import-Module (Join-Path $coreDir 'Win32Interop.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $coreDir 'ConfigManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $coreDir 'OverlayManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $uiDir 'GuiController.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $uiDir 'CliController.psm1') -Force -DisableNameChecking

if (-not $Cli) {
    Set-DpiAwarenessSafe
}

$config = Get-ShadeConfig
$catalog = Get-ShadePresetsCatalog -DataDirectory $dataDir

if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    $matchedPreset = $catalog.presets | Where-Object {
        $_.id -ieq $Profile -or $_.name -ieq $Profile
    } | Select-Object -First 1

    if ($null -ne $matchedPreset) {
        $config.Opacity = [int]$matchedPreset.opacity
        $config.TintHex = ([string]$matchedPreset.tintHex).ToUpperInvariant()
        $config.IsEnabled = $true
        $config.ActivePresetId = [string]$matchedPreset.id
    }
    else {
        $numericOpacity = 0
        if ([int]::TryParse($Profile, [ref]$numericOpacity)) {
            if ($numericOpacity -lt 5) { $numericOpacity = 5 }
            if ($numericOpacity -gt 95) { $numericOpacity = 95 }
            $config.Opacity = $numericOpacity
            $config.IsEnabled = $true
            $config.ActivePresetId = 'custom'
        }
    }
}

if ($Cli) {
    $cliOutcome = Start-ShadeVeilCli -Config $config -PresetsCatalog $catalog
    if ($cliOutcome -ne 'LaunchGui') {
        exit 0
    }
    Set-DpiAwarenessSafe
}

$xamlPath = Join-Path $uiDir 'MainWindow.xaml'
Start-ShadeVeilGui -XamlPath $xamlPath -InitialConfig $config -PresetsCatalog $catalog
