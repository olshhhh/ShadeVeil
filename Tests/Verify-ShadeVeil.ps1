[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$failures = New-Object System.Collections.Generic.List[string]
$passes = 0

function Add-CheckPass {
    param([string]$Message)
    $script:passes++
    Write-Host "  [PASS] $Message" -ForegroundColor Green
}

function Add-CheckFail {
    param([string]$Message)
    [void]$script:failures.Add($Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

Write-Host '=== Verificacion de solo lectura: ShadeVeil ===' -ForegroundColor Cyan

# 1. AST Syntax & Static Safety Rules
$psFiles = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
    $_.Extension -in @('.ps1', '.psm1')
})

foreach ($file in $psFiles) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        Add-CheckFail "Error AST en $($file.Name): $($parseErrors[0].Message)"
    }
    else {
        Add-CheckPass "Sintaxis AST valida: $($file.Name)"
    }

    if ($file.Name -ne 'Verify-ShadeVeil.ps1') {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        if ($raw -match '\bGet-WmiObject\b') {
            Add-CheckFail "Uso prohibido de Get-WmiObject en $($file.Name)"
        }
        if ($raw -match '\.GetNewClosure\s*\(') {
            Add-CheckFail "Uso prohibido de .GetNewClosure() en $($file.Name)"
        }
    }
}

# 2. JSON Integrity Check
$presetsPath = Join-Path $repoRoot 'Data\presets.json'
if (-not (Test-Path -LiteralPath $presetsPath)) {
    Add-CheckFail 'No existe Data\presets.json'
}
else {
    try {
        $jsonObj = (Get-Content -LiteralPath $presetsPath -Raw -Encoding UTF8) | ConvertFrom-Json
        $presetCount = @($jsonObj.presets).Count
        $tintCount = @($jsonObj.tints).Count
        if ($presetCount -ge 4 -and $tintCount -ge 4) {
            Add-CheckPass "JSON Data\presets.json valido ($presetCount presets, $tintCount tintes)"
        }
        else {
            Add-CheckFail 'Data\presets.json incompleto'
        }
    }
    catch {
        Add-CheckFail "JSON invalido en Data\presets.json: $($_.Exception.Message)"
    }
}

# 3. XAML Integrity & Strict Rules
$xamlPath = Join-Path $repoRoot 'UI\MainWindow.xaml'
if (-not (Test-Path -LiteralPath $xamlPath)) {
    Add-CheckFail 'No existe UI\MainWindow.xaml'
}
else {
    try {
        $xamlRaw = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
        [void][xml]$xamlRaw
        if ($xamlRaw -match 'x:Class|mc:Ignorable|DropShadowEffect|BlurEffect') {
            Add-CheckFail 'UI\MainWindow.xaml contiene atributos o efectos pesados prohibidos'
        }
        else {
            Add-CheckPass 'XML y reglas de rendimiento verificadas en UI\MainWindow.xaml'
        }

        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA) {
            Add-Type -AssemblyName PresentationFramework
            $parsedWin = [System.Windows.Markup.XamlReader]::Parse($xamlRaw)
            if ($null -ne $parsedWin) {
                Add-CheckPass 'XamlReader.Parse() exitoso en modo STA'
            }
        }
    }
    catch {
        Add-CheckFail "Error validando UI\MainWindow.xaml: $($_.Exception.Message)"
    }
}

# 4. Module Import & Pure Logic Checks under Set-StrictMode -Version Latest
try {
    Import-Module (Join-Path $repoRoot 'Core\Win32Interop.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'Core\ConfigManager.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'Core\OverlayManager.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'UI\GuiController.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'UI\CliController.psm1') -Force -DisableNameChecking
    Add-CheckPass 'Importacion de todos los modulos exitosa bajo Set-StrictMode -Version Latest'

    $normOk = (Resolve-NormalizedHexColor -Hex '1c0f00') -eq '#1C0F00'
    $normBad = $null -eq (Resolve-NormalizedHexColor -Hex 'ZZZZZZ')
    $defCfg = Get-DefaultShadeConfig
    if ($normOk -and $normBad -and $defCfg.Opacity -eq 45) {
        Add-CheckPass 'Pruebas unitarias de ConfigManager superadas'
    }
    else {
        Add-CheckFail 'Fallo prueba unitaria de ConfigManager'
    }
}
catch {
    Add-CheckFail "Error importando o probando modulos: $($_.Exception.Message)"
}

# 5. Manifest Sync Check in bootstrap.ps1
$bootstrapPath = Join-Path $repoRoot 'bootstrap.ps1'
if (Test-Path -LiteralPath $bootstrapPath) {
    $bsRaw = Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8
    $blockMatch = [regex]::Match($bsRaw, '\$manifestFiles\s*=\s*@\(([\s\S]*?)\)')
    $blockText = if ($blockMatch.Success) { $blockMatch.Groups[1].Value } else { '' }
    $matches = [regex]::Matches($blockText, "'([A-Za-z0-9_./-]+\.(?:ps1|psm1|xaml|json))'")
    $missing = @()
    foreach ($m in $matches) {
        $rel = $m.Groups[1].Value.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $full = Join-Path $repoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            $missing += $m.Groups[1].Value
        }
    }
    if (@($missing).Count -eq 0 -and $matches.Count -ge 8) {
        Add-CheckPass "Manifiesto de bootstrap.ps1 sincronizado ($($matches.Count) archivos verificados)"
    }
    else {
        Add-CheckFail ("Archivos faltantes o manifiesto invalido: " + ($missing -join ', '))
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host ("Resultado: {0} aprobadas, {1} fallidas." -f $passes, $failures.Count) -ForegroundColor Red
    exit 1
}

Write-Host ("Resultado: Todas las verificaciones ({0}) superadas con exito." -f $passes) -ForegroundColor Green
exit 0
