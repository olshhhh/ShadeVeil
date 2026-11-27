Set-StrictMode -Version Latest

$script:AppDataRoot = Join-Path $env:LOCALAPPDATA 'ShadeVeil'
$script:SettingsPath = Join-Path $script:AppDataRoot 'settings.json'

function Get-SafeJsonProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        $DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($PropertyName)) {
            return $InputObject[$PropertyName]
        }
        return $DefaultValue
    }

    if ($null -ne $InputObject.PSObject.Properties[$PropertyName]) {
        return $InputObject.PSObject.Properties[$PropertyName].Value
    }

    return $DefaultValue
}

function Get-DefaultShadeConfig {
    [CmdletBinding()]
    param()

    return [ordered]@{
        IsEnabled        = $true
        Opacity          = 45
        TintHex          = '#000000'
        MonitorScope     = 'AllScreens'
        EnableHotkeys    = $true
        KeepPanelAbove   = $true
        KeepAboveTaskbar = $true
        StartMinimized   = $false
        ActivePresetId   = 'custom'
    }
}

function Test-ValidHexColor {
    [CmdletBinding()]
    param(
        [string]$Hex
    )

    if ([string]::IsNullOrWhiteSpace($Hex)) {
        return $false
    }
    return ($Hex.Trim() -match '^#[0-9A-Fa-f]{6}$')
}

function Resolve-NormalizedHexColor {
    [CmdletBinding()]
    param(
        [string]$Hex
    )

    if ([string]::IsNullOrWhiteSpace($Hex)) {
        return $null
    }

    $trimmed = $Hex.Trim()
    if (-not $trimmed.StartsWith('#')) {
        $trimmed = '#' + $trimmed
    }

    if ($trimmed -match '^#[0-9A-Fa-f]{6}$') {
        return $trimmed.ToUpperInvariant()
    }

    return $null
}

function Get-ShadeConfig {
    [CmdletBinding()]
    param()

    $defaults = Get-DefaultShadeConfig
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return $defaults
    }

    try {
        $raw = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $defaults
        }
        $parsed = $raw | ConvertFrom-Json

        $isEnabled = [bool](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'IsEnabled' -DefaultValue $defaults.IsEnabled)
        $opacityRaw = [int](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'Opacity' -DefaultValue $defaults.Opacity)
        if ($opacityRaw -lt 5) { $opacityRaw = 5 }
        if ($opacityRaw -gt 95) { $opacityRaw = 95 }

        $tintHex = [string](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'TintHex' -DefaultValue $defaults.TintHex)
        $normalizedTint = Resolve-NormalizedHexColor -Hex $tintHex
        if ($null -eq $normalizedTint) {
            $normalizedTint = $defaults.TintHex
        }

        $scope = [string](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'MonitorScope' -DefaultValue $defaults.MonitorScope)
        if ($scope -notin @('AllScreens', 'PrimaryOnly', 'SecondaryOnly')) {
            $scope = $defaults.MonitorScope
        }

        $enableHotkeys = [bool](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'EnableHotkeys' -DefaultValue $defaults.EnableHotkeys)
        $keepPanelAbove = [bool](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'KeepPanelAbove' -DefaultValue $defaults.KeepPanelAbove)
        $keepAboveTaskbar = [bool](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'KeepAboveTaskbar' -DefaultValue $defaults.KeepAboveTaskbar)
        $startMinimized = [bool](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'StartMinimized' -DefaultValue $defaults.StartMinimized)
        $presetId = [string](Get-SafeJsonProperty -InputObject $parsed -PropertyName 'ActivePresetId' -DefaultValue 'custom')

        return [ordered]@{
            IsEnabled        = $isEnabled
            Opacity          = $opacityRaw
            TintHex          = $normalizedTint
            MonitorScope     = $scope
            EnableHotkeys    = $enableHotkeys
            KeepPanelAbove   = $keepPanelAbove
            KeepAboveTaskbar = $keepAboveTaskbar
            StartMinimized   = $startMinimized
            ActivePresetId   = $presetId
        }
    }
    catch {
        return $defaults
    }
}

function Save-ShadeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Config
    )

    try {
        if (-not (Test-Path -LiteralPath $script:AppDataRoot)) {
            [void](New-Item -Path $script:AppDataRoot -ItemType Directory -Force)
        }
        $json = $Config | ConvertTo-Json -Depth 4
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($script:SettingsPath, $json, $utf8NoBom)
    }
    catch {
        Write-Verbose "No se pudo guardar la configuracion: $($_.Exception.Message)"
    }
}

function Get-ShadePresetsCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory
    )

    $presetFile = Join-Path $DataDirectory 'presets.json'
    $fallback = [PSCustomObject]@{
        presets = @(
            [PSCustomObject]@{ id = 'reading'; name = 'Lectura Nocturna'; description = 'Atenuacion calida suave.'; opacity = 35; tintHex = '#1C0F00'; tintName = 'Ambar Nocturno' },
            [PSCustomObject]@{ id = 'privacy'; name = 'Privacidad Oficina'; description = 'Privacidad visual rapida.'; opacity = 60; tintHex = '#0B111E'; tintName = 'Pizarra Privacidad' },
            [PSCustomObject]@{ id = 'focus'; name = 'Focus Profundo'; description = 'Velo oscuro equilibrado.'; opacity = 75; tintHex = '#000000'; tintName = 'Negro Puro' },
            [PSCustomObject]@{ id = 'stealth'; name = 'Velo Maximo'; description = 'Maxima discrecion visual.'; opacity = 88; tintHex = '#000000'; tintName = 'Negro Puro' }
        )
        tints = @(
            [PSCustomObject]@{ id = 'pure-black'; name = 'Negro Puro'; hex = '#000000'; previewHex = '#111318' },
            [PSCustomObject]@{ id = 'warm-amber'; name = 'Ambar Nocturno'; hex = '#1C0F00'; previewHex = '#92400E' },
            [PSCustomObject]@{ id = 'slate-privacy'; name = 'Pizarra Privacidad'; hex = '#0B111E'; previewHex = '#1E3A8A' },
            [PSCustomObject]@{ id = 'soft-sepia'; name = 'Sepia Suave'; hex = '#141008'; previewHex = '#786238' }
        )
    }

    if (-not (Test-Path -LiteralPath $presetFile)) {
        return $fallback
    }

    try {
        $raw = Get-Content -LiteralPath $presetFile -Raw -Encoding UTF8
        $parsed = $raw | ConvertFrom-Json
        $presets = Get-SafeJsonProperty -InputObject $parsed -PropertyName 'presets' -DefaultValue $fallback.presets
        $tints = Get-SafeJsonProperty -InputObject $parsed -PropertyName 'tints' -DefaultValue $fallback.tints
        return [PSCustomObject]@{
            presets = @($presets)
            tints   = @($tints)
        }
    }
    catch {
        return $fallback
    }
}

function Get-SettingsDirectoryPath {
    [CmdletBinding()]
    param()

    return $script:AppDataRoot
}

function Get-SettingsFilePath {
    [CmdletBinding()]
    param()

    return $script:SettingsPath
}

Export-ModuleMember -Function @(
    'Get-SafeJsonProperty',
    'Get-DefaultShadeConfig',
    'Test-ValidHexColor',
    'Resolve-NormalizedHexColor',
    'Get-ShadeConfig',
    'Save-ShadeConfig',
    'Get-ShadePresetsCatalog',
    'Get-SettingsDirectoryPath',
    'Get-SettingsFilePath'
)
