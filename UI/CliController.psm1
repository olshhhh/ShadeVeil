Set-StrictMode -Version Latest

function Start-ShadeVeilCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Config,

        [Parameter(Mandatory = $true)]
        $PresetsCatalog
    )

    $inv = Get-DisplayInventory
    $exitCli = $false

    while (-not $exitCli) {
        Clear-Host
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host '  ShadeVeil - Consola de Configuracion y Diagnostico' -ForegroundColor White
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host ("  Estado del velo       : {0}" -f $(if ($Config.IsEnabled) { 'ACTIVO' } else { 'EN PAUSA' })) -ForegroundColor Yellow
        Write-Host ("  Nivel de opacidad     : {0}%" -f $Config.Opacity) -ForegroundColor Green
        Write-Host ("  Color del tinte       : {0}" -f $Config.TintHex) -ForegroundColor Gray
        Write-Host ("  Alcance pantallas     : {0}" -f $Config.MonitorScope) -ForegroundColor Gray
        Write-Host ("  Proteger barra tareas : {0}" -f $(if ($Config.KeepAboveTaskbar) { 'Si' } else { 'No (Modo Eco)' })) -ForegroundColor Gray
        Write-Host ("  Archivo de ajustes    : {0}" -f (Get-SettingsFilePath)) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ("  Pantallas detectadas ({0}):" -f @($inv.Displays).Count) -ForegroundColor Cyan
        foreach ($d in $inv.Displays) {
            $prim = if ($d.Primary) { '[Principal]' } else { '[Secundaria]' }
            Write-Host ("    - #{0} {1} {2}x{3} @ ({4},{5}) {6}" -f $d.Index, $d.DeviceName, $d.Width, $d.Height, $d.X, $d.Y, $prim)
        }
        if (@($inv.Gpus).Count -gt 0) {
            Write-Host ("  GPU(s): {0}" -f ($inv.Gpus -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host '  Opciones:' -ForegroundColor White
        Write-Host '    [1] Ajustar opacidad (5% - 95%)'
        Write-Host '    [2] Aplicar un modo rapido (Preset)'
        Write-Host '    [3] Ingresar color hexadecimal personalizado (#RRGGBB)'
        Write-Host '    [4] Cambiar alcance de monitores'
        Write-Host '    [5] Alternar estado Activo / En Pausa'
        Write-Host '    [6] Restablecer valores predeterminados'
        Write-Host '    [7] Guardar ajustes y abrir interfaz grafica (GUI)'
        Write-Host '    [0] Guardar y salir'
        Write-Host ''

        $choice = Read-Host 'Selecciona una opcion'
        switch ($choice.Trim()) {
            '1' {
                $rawOp = Read-Host 'Ingresa opacidad deseada (5 a 95)'
                $parsedOp = 0
                if ([int]::TryParse($rawOp, [ref]$parsedOp)) {
                    if ($parsedOp -lt 5) { $parsedOp = 5 }
                    if ($parsedOp -gt 95) { $parsedOp = 95 }
                    $Config.Opacity = $parsedOp
                    $Config.ActivePresetId = 'custom'
                    Save-ShadeConfig -Config $Config
                }
            }
            '2' {
                Write-Host ''
                $i = 1
                foreach ($p in $PresetsCatalog.presets) {
                    Write-Host ("    [{0}] {1} ({2}%, {3})" -f $i, $p.name, $p.opacity, $p.tintName)
                    $i++
                }
                $pChoice = Read-Host 'Elige numero de preset'
                $pIdx = 0
                if ([int]::TryParse($pChoice, [ref]$pIdx) -and $pIdx -ge 1 -and $pIdx -le @($PresetsCatalog.presets).Count) {
                    $sel = $PresetsCatalog.presets[$pIdx - 1]
                    $Config.Opacity = [int]$sel.opacity
                    $Config.TintHex = ([string]$sel.tintHex).ToUpperInvariant()
                    $Config.IsEnabled = $true
                    $Config.ActivePresetId = [string]$sel.id
                    Save-ShadeConfig -Config $Config
                }
            }
            '3' {
                $rawHex = Read-Host 'Ingresa color hexadecimal (ej. #000000 o #1C0F00)'
                $norm = Resolve-NormalizedHexColor -Hex $rawHex
                if ($null -ne $norm) {
                    $Config.TintHex = $norm
                    $Config.ActivePresetId = 'custom'
                    Save-ShadeConfig -Config $Config
                }
            }
            '4' {
                Write-Host ''
                Write-Host '    [1] Todas las pantallas (AllScreens)'
                Write-Host '    [2] Solo pantalla principal (PrimaryOnly)'
                Write-Host '    [3] Solo pantallas secundarias (SecondaryOnly)'
                $sChoice = Read-Host 'Elige alcance'
                switch ($sChoice.Trim()) {
                    '1' { $Config.MonitorScope = 'AllScreens' }
                    '2' { $Config.MonitorScope = 'PrimaryOnly' }
                    '3' { $Config.MonitorScope = 'SecondaryOnly' }
                }
                Save-ShadeConfig -Config $Config
            }
            '5' {
                $Config.IsEnabled = -not [bool]$Config.IsEnabled
                Save-ShadeConfig -Config $Config
            }
            '6' {
                $def = Get-DefaultShadeConfig
                foreach ($k in $def.Keys) {
                    $Config[$k] = $def[$k]
                }
                Save-ShadeConfig -Config $Config
            }
            '7' {
                Save-ShadeConfig -Config $Config
                return 'LaunchGui'
            }
            '0' {
                Save-ShadeConfig -Config $Config
                $exitCli = $true
            }
        }
    }

    return 'Exit'
}

Export-ModuleMember -Function @(
    'Start-ShadeVeilCli'
)
