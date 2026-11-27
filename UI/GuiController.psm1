Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:UiState = @{
    Window                = $null
    Controls              = @{}
    Brushes               = @{}
    Config                = $null
    PresetsCatalog        = $null
    SuppressEvents        = $false
    IsClosing             = $false
    LastVisualEnabled     = $null
    LastActivePresetId    = $null
    NotifyIcon            = $null
    TrayIconHandle        = $null
    TrayRawHIcon          = [IntPtr]::Zero
    TrayToggleItem        = $null
    HotkeySink            = $null
    HotkeysRegistered     = $false
    HeartbeatTimer        = $null
    SaveTimer             = $null
    DisplayChangedHandler = $null
    SingleInstanceMutex   = $null
    WakeEvent             = $null
}

function Initialize-StaticUiBrushes {
    [CmdletBinding()]
    param()

    if ($script:UiState.Brushes.Count -gt 0) {
        return
    }

    $palette = @{
        ActiveBadgeBg      = '#052E16'
        ActiveBadgeBorder  = '#16A34A'
        ActiveBadgeText    = '#4ADE80'
        PausedBadgeBg      = '#271710'
        PausedBadgeBorder  = '#D97706'
        PausedBadgeText    = '#FBBF24'
        PowerOnText        = '#93C5FD'
        PowerOffText       = '#94A3B8'
        PresetIdleBg       = '#161D29'
        PresetIdleBorder   = '#263042'
        PresetActiveBg     = '#17253B'
        PresetActiveBorder = '#38BDF8'
        FeedbackOk         = '#4ADE80'
        FeedbackErr        = '#F87171'
        FeedbackMuted      = '#64748B'
    }

    foreach ($key in $palette.Keys) {
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($palette[$key])
        $brush = New-Object System.Windows.Media.SolidColorBrush($color)
        $brush.Freeze()
        $script:UiState.Brushes[$key] = $brush
    }
}

function New-ShadeVeilTrayIcon {
    [CmdletBinding()]
    param()

    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)

        $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 15, 23, 42))
        $g.FillEllipse($bgBrush, 2, 2, 28, 28)
        $bgBrush.Dispose()

        $ringPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 56, 189, 248), 2.5)
        $g.DrawEllipse($ringPen, 3, 3, 26, 26)
        $ringPen.Dispose()

        $moonBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 248, 250, 252))
        $g.FillEllipse($moonBrush, 9, 8, 13, 15)
        $moonBrush.Dispose()

        $cutBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 15, 23, 42))
        $g.FillEllipse($cutBrush, 14, 7, 12, 14)
        $cutBrush.Dispose()

        $hIcon = $bmp.GetHicon()
        $script:UiState.TrayRawHIcon = $hIcon
        return [System.Drawing.Icon]::FromHandle($hIcon)
    }
    finally {
        $g.Dispose()
        $bmp.Dispose()
    }
}

function Get-OpacityComfortDescription {
    [CmdletBinding()]
    param(
        [int]$OpacityPercent
    )

    if ($OpacityPercent -le 20) {
        return 'Brillo apenas suavizado · Ideal de dia'
    }
    if ($OpacityPercent -le 45) {
        return 'Lectura comoda · Los clics siguen funcionando normal'
    }
    if ($OpacityPercent -le 70) {
        return 'Privacidad equilibrada · Reduce visibilidad lateral'
    }
    if ($OpacityPercent -le 85) {
        return 'Oscurecimiento profundo · Ideal para noche o cine'
    }
    return 'Maxima privacidad · Pulsa Ctrl+Alt+D si deseas pausar'
}

function Update-DisplayCountLabel {
    [CmdletBinding()]
    param()

    $inv = Get-DisplayInventory
    $count = @($inv.Displays).Count
    $lbl = $script:UiState.Controls['MonitorCountText']
    if ($null -ne $lbl) {
        if ($count -eq 1) {
            $lbl.Text = '1 pantalla detectada'
        }
        else {
            $lbl.Text = "$count pantallas detectadas"
        }
    }

    $secRadio = $script:UiState.Controls['RadioScopeSecondary']
    if ($null -ne $secRadio) {
        $hasSecondary = ($count -gt 1)
        $secRadio.IsEnabled = $hasSecondary
        $secRadio.ToolTip = if ($hasSecondary) {
            'Oscurecer unicamente las pantallas adicionales'
        }
        else {
            'Conecta una segunda pantalla para habilitar esta opcion'
        }
    }
}

function Update-ActivePresetHighlight {
    [CmdletBinding()]
    param()

    $activeId = [string]$script:UiState.Config.ActivePresetId
    if ($script:UiState.LastActivePresetId -eq $activeId) {
        return
    }
    $script:UiState.LastActivePresetId = $activeId

    $brushes = $script:UiState.Brushes
    foreach ($btnName in @('BtnPresetReading', 'BtnPresetPrivacy', 'BtnPresetFocus', 'BtnPresetStealth')) {
        $btn = $script:UiState.Controls[$btnName]
        if ($null -eq $btn) { continue }
        if ([string]$btn.Tag -eq $activeId) {
            $btn.Background = $brushes['PresetActiveBg']
            $btn.BorderBrush = $brushes['PresetActiveBorder']
        }
        else {
            $btn.Background = $brushes['PresetIdleBg']
            $btn.BorderBrush = $brushes['PresetIdleBorder']
        }
    }
}

function Update-VisualStatus {
    [CmdletBinding()]
    param()

    $cfg = $script:UiState.Config
    $controls = $script:UiState.Controls
    $brushes = $script:UiState.Brushes

    $opacityText = $controls['OpacityPercentText']
    if ($null -ne $opacityText) {
        $opacityText.Text = "$($cfg.Opacity)%"
    }

    $levelLbl = $controls['OpacityLevelLabel']
    if ($null -ne $levelLbl) {
        $levelLbl.Text = Get-OpacityComfortDescription -OpacityPercent ([int]$cfg.Opacity)
    }

    Update-ActivePresetHighlight

    $enabledNow = [bool]$cfg.IsEnabled
    if ($script:UiState.LastVisualEnabled -ne $enabledNow) {
        $script:UiState.LastVisualEnabled = $enabledNow

        $badge = $controls['StatusBadge']
        $badgeText = $controls['StatusBadgeText']
        $powerLabel = $controls['PowerLabel']

        if ($enabledNow) {
            if ($null -ne $badge) {
                $badge.Background = $brushes['ActiveBadgeBg']
                $badge.BorderBrush = $brushes['ActiveBadgeBorder']
            }
            if ($null -ne $badgeText) {
                $badgeText.Text = 'ACTIVO'
                $badgeText.Foreground = $brushes['ActiveBadgeText']
            }
            if ($null -ne $powerLabel) {
                $powerLabel.Text = 'Velo ON'
                $powerLabel.Foreground = $brushes['PowerOnText']
            }
            if ($null -ne $script:UiState.TrayToggleItem) {
                $script:UiState.TrayToggleItem.Text = 'Pausar Velo (Ctrl+Alt+D)'
            }
        }
        else {
            if ($null -ne $badge) {
                $badge.Background = $brushes['PausedBadgeBg']
                $badge.BorderBrush = $brushes['PausedBadgeBorder']
            }
            if ($null -ne $badgeText) {
                $badgeText.Text = 'EN PAUSA'
                $badgeText.Foreground = $brushes['PausedBadgeText']
            }
            if ($null -ne $powerLabel) {
                $powerLabel.Text = 'Velo OFF'
                $powerLabel.Foreground = $brushes['PowerOffText']
            }
            if ($null -ne $script:UiState.TrayToggleItem) {
                $script:UiState.TrayToggleItem.Text = 'Activar Velo (Ctrl+Alt+D)'
            }
        }
    }

    if ($null -ne $script:UiState.NotifyIcon) {
        $stateStr = if ($enabledNow) { "Activo ($($cfg.Opacity)%)" } else { 'En pausa' }
        $script:UiState.NotifyIcon.Text = "ShadeVeil - $stateStr"
    }
}

function Request-DeferredSave {
    [CmdletBinding()]
    param()

    $saveTimer = $script:UiState.SaveTimer
    if ($null -ne $saveTimer) {
        $saveTimer.Stop()
        $saveTimer.Start()
    }
    else {
        Save-ShadeConfig -Config $script:UiState.Config
    }
}

function Apply-ShadeState {
    [CmdletBinding()]
    param(
        [bool]$RebuildScreens = $false,
        [bool]$PersistImmediate = $false,
        [bool]$PersistDeferred = $true
    )

    $cfg = $script:UiState.Config
    $win = $script:UiState.Window

    $desiredTop = [bool]$cfg.KeepPanelAbove
    if ($win.Topmost -ne $desiredTop) {
        $win.Topmost = $desiredTop
    }

    Set-OverlayHostContext -MainWindow $win -KeepPanelAbove $desiredTop

    Update-OverlayAppearance `
        -IsEnabled ([bool]$cfg.IsEnabled) `
        -OpacityPercent ([int]$cfg.Opacity) `
        -TintHex ([string]$cfg.TintHex) `
        -MonitorScope ([string]$cfg.MonitorScope) `
        -RebuildScreens $RebuildScreens

    Update-VisualStatus

    if ($PersistImmediate) {
        if ($null -ne $script:UiState.SaveTimer) {
            $script:UiState.SaveTimer.Stop()
        }
        Save-ShadeConfig -Config $cfg
    }
    elseif ($PersistDeferred) {
        Request-DeferredSave
    }
}

function Sync-ControlsFromConfig {
    [CmdletBinding()]
    param()

    $cfg = $script:UiState.Config
    $controls = $script:UiState.Controls

    $script:UiState.SuppressEvents = $true
    try {
        $controls['PowerToggle'].IsChecked = [bool]$cfg.IsEnabled
        $controls['OpacitySlider'].Value = [double]$cfg.Opacity
        $controls['ChkEnableHotkeys'].IsChecked = [bool]$cfg.EnableHotkeys
        $controls['ChkKeepPanelAbove'].IsChecked = [bool]$cfg.KeepPanelAbove
        $controls['ChkKeepAboveTaskbar'].IsChecked = [bool]$cfg.KeepAboveTaskbar
        $controls['ChkStartMinimized'].IsChecked = [bool]$cfg.StartMinimized

        $matchedPresetTint = $false
        foreach ($tintName in @('RadioTintBlack', 'RadioTintAmber', 'RadioTintSlate', 'RadioTintSepia')) {
            $rb = $controls[$tintName]
            if ($null -ne $rb) {
                $isMatch = ([string]$rb.Tag -eq [string]$cfg.TintHex)
                $rb.IsChecked = $isMatch
                if ($isMatch) { $matchedPresetTint = $true }
            }
        }

        $txtCustom = $controls['TxtCustomHex']
        $preview = $controls['CustomHexPreview']
        if ($null -ne $txtCustom) {
            $txtCustom.Text = [string]$cfg.TintHex
        }
        if ($null -ne $preview) {
            $pColor = [System.Windows.Media.ColorConverter]::ConvertFromString([string]$cfg.TintHex)
            $pBrush = New-Object System.Windows.Media.SolidColorBrush($pColor)
            $pBrush.Freeze()
            $preview.Background = $pBrush
        }

        if (-not $matchedPresetTint) {
            $fb = $controls['CustomHexFeedback']
            if ($null -ne $fb) {
                $fb.Text = 'Tono personalizado activo'
                $fb.Foreground = $script:UiState.Brushes['FeedbackOk']
            }
        }

        foreach ($scopeName in @('RadioScopeAll', 'RadioScopePrimary', 'RadioScopeSecondary')) {
            $rb = $controls[$scopeName]
            if ($null -ne $rb) {
                $rb.IsChecked = ([string]$rb.Tag -eq [string]$cfg.MonitorScope)
            }
        }
    }
    finally {
        $script:UiState.SuppressEvents = $false
    }
}

function Set-ShadeOpacityValue {
    [CmdletBinding()]
    param(
        [int]$NewOpacity,
        [bool]$EnableIfChanged = $false,
        [bool]$PersistImmediate = $false
    )

    if ($NewOpacity -lt 5) { $NewOpacity = 5 }
    if ($NewOpacity -gt 95) { $NewOpacity = 95 }

    $script:UiState.Config.Opacity = $NewOpacity
    $script:UiState.Config.ActivePresetId = 'custom'
    if ($EnableIfChanged) {
        $script:UiState.Config.IsEnabled = $true
    }

    Sync-ControlsFromConfig
    Apply-ShadeState -PersistImmediate $PersistImmediate -PersistDeferred (-not $PersistImmediate)
}

function Update-HotkeyRegistration {
    [CmdletBinding()]
    param(
        [bool]$Enable
    )

    $sink = $script:UiState.HotkeySink
    $statusLbl = $script:UiState.Controls['HotkeyStatusText']

    if ($null -eq $sink -or $sink.Handle -eq [IntPtr]::Zero) {
        return
    }

    if ($script:UiState.HotkeysRegistered) {
        [void](Unregister-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 1)
        [void](Unregister-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 2)
        [void](Unregister-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 3)
        $script:UiState.HotkeysRegistered = $false
    }

    if ($Enable) {
        [uint32]$mods = 0x0002 -bor 0x0001 -bor 0x4000
        $ok1 = Register-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 1 -Modifiers $mods -VirtualKey 0x44
        $ok2 = Register-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 2 -Modifiers $mods -VirtualKey 0x26
        $ok3 = Register-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 3 -Modifiers $mods -VirtualKey 0x28
        $script:UiState.HotkeysRegistered = ($ok1 -or $ok2 -or $ok3)

        if ($null -ne $statusLbl) {
            if ($ok1 -and $ok2 -and $ok3) {
                $statusLbl.Text = 'Todos los atajos globales estan activos'
                $statusLbl.Foreground = $script:UiState.Brushes['FeedbackOk']
            }
            elseif ($script:UiState.HotkeysRegistered) {
                $statusLbl.Text = 'Algunos atajos estan ocupados por otra aplicacion'
                $statusLbl.Foreground = $script:UiState.Brushes['FeedbackErr']
            }
            else {
                $statusLbl.Text = 'No se pudieron registrar (ocupados por otro programa)'
                $statusLbl.Foreground = $script:UiState.Brushes['FeedbackErr']
            }
        }
    }
    else {
        if ($null -ne $statusLbl) {
            $statusLbl.Text = 'Atajos globales desactivados'
            $statusLbl.Foreground = $script:UiState.Brushes['FeedbackMuted']
        }
    }
}

function Show-ShadeControlPanel {
    [CmdletBinding()]
    param()

    $win = $script:UiState.Window
    if ($null -eq $win) { return }

    if (-not $win.IsVisible) {
        $win.Show()
    }
    if ($win.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $win.WindowState = [System.Windows.WindowState]::Normal
    }
    $win.Activate() | Out-Null
    Sync-OverlayZOrder -Force $true
}

function Hide-ShadeControlPanelToTray {
    [CmdletBinding()]
    param()

    $win = $script:UiState.Window
    if ($null -ne $win) {
        $win.Hide()
        Sync-OverlayZOrder -Force $true
    }
}

function Initialize-SystemTray {
    [CmdletBinding()]
    param()

    $icon = New-ShadeVeilTrayIcon
    $script:UiState.TrayIconHandle = $icon

    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = $icon
    $tray.Text = 'ShadeVeil'
    $tray.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $itemShow = New-Object System.Windows.Forms.ToolStripMenuItem('Mostrar Panel de Control')
    $itemShow.Add_Click({
        Show-ShadeControlPanel
    })

    $itemToggle = New-Object System.Windows.Forms.ToolStripMenuItem('Pausar Velo (Ctrl+Alt+D)')
    $itemToggle.Add_Click({
        $script:UiState.Config.IsEnabled = -not [bool]$script:UiState.Config.IsEnabled
        Sync-ControlsFromConfig
        Apply-ShadeState -PersistImmediate $true
    })
    $script:UiState.TrayToggleItem = $itemToggle

    $item25 = New-Object System.Windows.Forms.ToolStripMenuItem('Opacidad 25% (Suave)')
    $item25.Add_Click({ Set-ShadeOpacityValue -NewOpacity 25 -EnableIfChanged $true -PersistImmediate $true })

    $item50 = New-Object System.Windows.Forms.ToolStripMenuItem('Opacidad 50% (Privacidad)')
    $item50.Add_Click({ Set-ShadeOpacityValue -NewOpacity 50 -EnableIfChanged $true -PersistImmediate $true })

    $item75 = New-Object System.Windows.Forms.ToolStripMenuItem('Opacidad 75% (Oscuro)')
    $item75.Add_Click({ Set-ShadeOpacityValue -NewOpacity 75 -EnableIfChanged $true -PersistImmediate $true })

    $itemExit = New-Object System.Windows.Forms.ToolStripMenuItem('Salir de ShadeVeil')
    $itemExit.Add_Click({
        if ($null -ne $script:UiState.Window) {
            $script:UiState.Window.Close()
        }
    })

    [void]$menu.Items.Add($itemShow)
    [void]$menu.Items.Add($itemToggle)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add($item25)
    [void]$menu.Items.Add($item50)
    [void]$menu.Items.Add($item75)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add($itemExit)

    $tray.ContextMenuStrip = $menu
    $tray.Add_MouseClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $win = $script:UiState.Window
            if ($null -ne $win -and $win.IsVisible -and $win.WindowState -ne [System.Windows.WindowState]::Minimized) {
                Hide-ShadeControlPanelToTray
            }
            else {
                Show-ShadeControlPanel
            }
        }
    })

    $script:UiState.NotifyIcon = $tray
}

function Start-ShadeVeilGui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$XamlPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$InitialConfig,

        [Parameter(Mandatory = $true)]
        $PresetsCatalog
    )

    # Single-instance protection so beginners never stack duplicate dark veils
    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\ShadeVeil_SingleInstance_v1', [ref]$createdNew)
    if (-not $createdNew) {
        try {
            $existingEvt = [System.Threading.EventWaitHandle]::OpenExisting('Local\ShadeVeil_ShowPanel_v1')
            [void]$existingEvt.Set()
            $existingEvt.Dispose()
        }
        catch {
            # Ignore if primary instance is still initializing
        }
        $mutex.Dispose()
        Write-Host '[ShadeVeil] Ya hay una instancia ejecutandose. Mostrando panel existente...' -ForegroundColor Yellow
        return
    }

    $wakeEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\ShadeVeil_ShowPanel_v1')
    $script:UiState.SingleInstanceMutex = $mutex
    $script:UiState.WakeEvent = $wakeEvent

    if (-not (Test-Path -LiteralPath $XamlPath)) {
        throw "No se encontro el archivo de interfaz XAML: $XamlPath"
    }

    Initialize-StaticUiBrushes

    $xamlContent = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8
    $window = [System.Windows.Markup.XamlReader]::Parse($xamlContent)

    $script:UiState.Window = $window
    $script:UiState.Config = $InitialConfig
    $script:UiState.PresetsCatalog = $PresetsCatalog
    $script:UiState.IsClosing = $false
    $script:UiState.LastVisualEnabled = $null
    $script:UiState.LastActivePresetId = $null

    $controlNames = @(
        'StatusBadge', 'StatusBadgeText', 'PowerLabel', 'PowerToggle',
        'OpacityPercentText', 'OpacityLevelLabel', 'OpacitySlider',
        'BtnDecreaseOpacity', 'BtnIncreaseOpacity',
        'BtnPresetReading', 'BtnPresetPrivacy', 'BtnPresetFocus', 'BtnPresetStealth',
        'RadioTintBlack', 'RadioTintAmber', 'RadioTintSlate', 'RadioTintSepia',
        'MonitorCountText', 'RadioScopeAll', 'RadioScopePrimary', 'RadioScopeSecondary',
        'TxtCustomHex', 'BtnApplyCustomHex', 'CustomHexPreview', 'CustomHexFeedback',
        'ChkEnableHotkeys', 'HotkeyStatusText', 'ChkKeepPanelAbove', 'ChkKeepAboveTaskbar',
        'ChkStartMinimized', 'BtnOpenSettingsFolder', 'BtnReset', 'BtnMinimizeToTray'
    )

    $script:UiState.Controls = @{}
    foreach ($name in $controlNames) {
        $script:UiState.Controls[$name] = $window.FindName($name)
    }

    # Debounced disk save timer (prevents HDD stutter during rapid drags/scrolls)
    $saveTimer = New-Object System.Windows.Threading.DispatcherTimer
    $saveTimer.Interval = [TimeSpan]::FromMilliseconds(350)
    $saveTimer.Add_Tick({
        param($sender, $e)
        $sender.Stop()
        if ($null -ne $script:UiState.Config) {
            Save-ShadeConfig -Config $script:UiState.Config
        }
    })
    $script:UiState.SaveTimer = $saveTimer

    Initialize-SystemTray
    Update-DisplayCountLabel
    Sync-ControlsFromConfig

    # Slider intuitive control
    $slider = $script:UiState.Controls['OpacitySlider']
    $slider.Add_ValueChanged({
        param($sender, $e)
        if ($script:UiState.SuppressEvents) { return }
        $val = [int][Math]::Round($sender.Value)
        $script:UiState.Config.Opacity = $val
        $script:UiState.Config.ActivePresetId = 'custom'
        Apply-ShadeState -PersistImmediate $false -PersistDeferred $true
    })

    $slider.Add_PreviewMouseLeftButtonUp({
        Request-DeferredSave
    })

    $slider.Add_PreviewMouseWheel({
        param($sender, $e)
        $e.Handled = $true
        $step = if ($e.Delta -gt 0) { 2 } else { -2 }
        $next = [int]$script:UiState.Config.Opacity + $step
        Set-ShadeOpacityValue -NewOpacity $next -EnableIfChanged $false
    })

    # Stepper buttons
    $script:UiState.Controls['BtnDecreaseOpacity'].Add_Click({
        Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity - 5) -EnableIfChanged $false
    })

    $script:UiState.Controls['BtnIncreaseOpacity'].Add_Click({
        Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity + 5) -EnableIfChanged $false
    })

    # Master power switch
    $powerToggle = $script:UiState.Controls['PowerToggle']
    $powerToggle.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.IsEnabled = $true
        Apply-ShadeState -PersistImmediate $true
    })
    $powerToggle.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.IsEnabled = $false
        Apply-ShadeState -PersistImmediate $true
    })

    # Preset buttons
    foreach ($btnName in @('BtnPresetReading', 'BtnPresetPrivacy', 'BtnPresetFocus', 'BtnPresetStealth')) {
        $btn = $script:UiState.Controls[$btnName]
        $btn.Add_Click({
            param($sender, $e)
            $presetId = [string]$sender.Tag
            $match = $script:UiState.PresetsCatalog.presets | Where-Object { $_.id -eq $presetId } | Select-Object -First 1
            if ($null -ne $match) {
                $script:UiState.Config.Opacity = [int]$match.opacity
                $script:UiState.Config.TintHex = ([string]$match.tintHex).ToUpperInvariant()
                $script:UiState.Config.IsEnabled = $true
                $script:UiState.Config.ActivePresetId = $presetId
                $fb = $script:UiState.Controls['CustomHexFeedback']
                if ($null -ne $fb) { $fb.Text = '' }
                Sync-ControlsFromConfig
                Apply-ShadeState -PersistImmediate $true
            }
        })
    }

    # Tint RadioButtons
    foreach ($tintName in @('RadioTintBlack', 'RadioTintAmber', 'RadioTintSlate', 'RadioTintSepia')) {
        $rb = $script:UiState.Controls[$tintName]
        $rb.Add_Checked({
            param($sender, $e)
            if ($script:UiState.SuppressEvents) { return }
            $script:UiState.Config.TintHex = ([string]$sender.Tag).ToUpperInvariant()
            $script:UiState.Config.ActivePresetId = 'custom'
            $fb = $script:UiState.Controls['CustomHexFeedback']
            if ($null -ne $fb) { $fb.Text = '' }
            Sync-ControlsFromConfig
            Apply-ShadeState -PersistImmediate $true
        })
    }

    # Custom Hex Color Apply
    $script:UiState.Controls['BtnApplyCustomHex'].Add_Click({
        $txtBox = $script:UiState.Controls['TxtCustomHex']
        $fb = $script:UiState.Controls['CustomHexFeedback']
        $normalized = Resolve-NormalizedHexColor -Hex ([string]$txtBox.Text)
        if ($null -eq $normalized) {
            if ($null -ne $fb) {
                $fb.Text = 'Usa formato #RRGGBB'
                $fb.Foreground = $script:UiState.Brushes['FeedbackErr']
            }
            return
        }

        $script:UiState.Config.TintHex = $normalized
        $script:UiState.Config.ActivePresetId = 'custom'
        Sync-ControlsFromConfig
        Apply-ShadeState -PersistImmediate $true
        if ($null -ne $fb) {
            $fb.Text = "Aplicado ($normalized)"
            $fb.Foreground = $script:UiState.Brushes['FeedbackOk']
        }
    })

    # Monitor scope RadioButtons
    foreach ($scopeName in @('RadioScopeAll', 'RadioScopePrimary', 'RadioScopeSecondary')) {
        $rb = $script:UiState.Controls[$scopeName]
        $rb.Add_Checked({
            param($sender, $e)
            if ($script:UiState.SuppressEvents) { return }
            $script:UiState.Config.MonitorScope = [string]$sender.Tag
            Apply-ShadeState -RebuildScreens $true -PersistImmediate $true
        })
    }

    # Behavior CheckBoxes
    $chkHotkeys = $script:UiState.Controls['ChkEnableHotkeys']
    $chkHotkeys.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.EnableHotkeys = $true
        Update-HotkeyRegistration -Enable $true
        Request-DeferredSave
    })
    $chkHotkeys.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.EnableHotkeys = $false
        Update-HotkeyRegistration -Enable $false
        Request-DeferredSave
    })

    $chkTop = $script:UiState.Controls['ChkKeepPanelAbove']
    $chkTop.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.KeepPanelAbove = $true
        Apply-ShadeState -PersistImmediate $true
    })
    $chkTop.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.KeepPanelAbove = $false
        Apply-ShadeState -PersistImmediate $true
    })

    $chkTaskbar = $script:UiState.Controls['ChkKeepAboveTaskbar']
    $chkTaskbar.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.KeepAboveTaskbar = $true
        Sync-OverlayZOrder -Force $true
        Request-DeferredSave
    })
    $chkTaskbar.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.KeepAboveTaskbar = $false
        Request-DeferredSave
    })

    $chkMin = $script:UiState.Controls['ChkStartMinimized']
    $chkMin.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.StartMinimized = $true
        Request-DeferredSave
    })
    $chkMin.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.StartMinimized = $false
        Request-DeferredSave
    })

    # Open settings directory in Explorer
    $script:UiState.Controls['BtnOpenSettingsFolder'].Add_Click({
        $dir = Get-SettingsDirectoryPath
        if (-not (Test-Path -LiteralPath $dir)) {
            [void](New-Item -Path $dir -ItemType Directory -Force)
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList $dir
    })

    # Footer Buttons
    $script:UiState.Controls['BtnReset'].Add_Click({
        $def = Get-DefaultShadeConfig
        $script:UiState.Config.IsEnabled = $def.IsEnabled
        $script:UiState.Config.Opacity = $def.Opacity
        $script:UiState.Config.TintHex = $def.TintHex
        $script:UiState.Config.MonitorScope = $def.MonitorScope
        $script:UiState.Config.KeepPanelAbove = $def.KeepPanelAbove
        $script:UiState.Config.KeepAboveTaskbar = $def.KeepAboveTaskbar
        $script:UiState.Config.ActivePresetId = 'custom'
        $fb = $script:UiState.Controls['CustomHexFeedback']
        if ($null -ne $fb) { $fb.Text = '' }
        Sync-ControlsFromConfig
        Apply-ShadeState -RebuildScreens $true -PersistImmediate $true
    })

    $script:UiState.Controls['BtnMinimizeToTray'].Add_Click({
        Hide-ShadeControlPanelToTray
    })

    # Intuitive local keyboard shortcuts when control window has focus
    $window.Add_KeyDown({
        param($sender, $e)
        $focused = [System.Windows.Input.Keyboard]::FocusedElement
        if ($focused -is [System.Windows.Controls.TextBox]) {
            return
        }

        switch ($e.Key) {
            ([System.Windows.Input.Key]::Escape) {
                if ([bool]$script:UiState.Config.IsEnabled) {
                    $script:UiState.Config.IsEnabled = $false
                    Sync-ControlsFromConfig
                    Apply-ShadeState -PersistImmediate $true
                    $e.Handled = $true
                }
            }
            ([System.Windows.Input.Key]::Add) {
                Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity + 5) -EnableIfChanged $false
                $e.Handled = $true
            }
            ([System.Windows.Input.Key]::OemPlus) {
                Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity + 5) -EnableIfChanged $false
                $e.Handled = $true
            }
            ([System.Windows.Input.Key]::Subtract) {
                Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity - 5) -EnableIfChanged $false
                $e.Handled = $true
            }
            ([System.Windows.Input.Key]::OemMinus) {
                Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity - 5) -EnableIfChanged $false
                $e.Handled = $true
            }
        }
    })

    # Global Hotkey sink
    $sink = New-HotkeySink
    $sink.add_HotkeyPressed({
        param($sender, $e)
        switch ($e.HotkeyId) {
            1 {
                $script:UiState.Config.IsEnabled = -not [bool]$script:UiState.Config.IsEnabled
                Sync-ControlsFromConfig
                Apply-ShadeState
            }
            2 {
                Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity + 5) -EnableIfChanged $true
            }
            3 {
                Set-ShadeOpacityValue -NewOpacity ([int]$script:UiState.Config.Opacity - 5) -EnableIfChanged $true
            }
        }
    })
    $script:UiState.HotkeySink = $sink

    # Unified ultra-light 1s heartbeat: checks single-instance wake & idle-free Z-order
    $heartbeat = New-Object System.Windows.Threading.DispatcherTimer
    $heartbeat.Interval = [TimeSpan]::FromMilliseconds(1000)
    $heartbeat.Add_Tick({
        if ($script:UiState.IsClosing) { return }

        if ($null -ne $script:UiState.WakeEvent -and $script:UiState.WakeEvent.WaitOne(0)) {
            Show-ShadeControlPanel
        }

        if ([bool]$script:UiState.Config.IsEnabled -and [bool]$script:UiState.Config.KeepAboveTaskbar) {
            Sync-OverlayZOrder -Force $false
        }
    })
    $script:UiState.HeartbeatTimer = $heartbeat

    # Monitor topology change listener
    $dispHandler = [System.EventHandler]{
        param($sender, $e)
        if (-not $script:UiState.IsClosing -and $null -ne $script:UiState.Window) {
            [void]$script:UiState.Window.Dispatcher.BeginInvoke([Action]{
                if (-not $script:UiState.IsClosing) {
                    Update-DisplayCountLabel
                    Apply-ShadeState -RebuildScreens $true -PersistDeferred $false
                }
            })
        }
    }
    $script:UiState.DisplayChangedHandler = $dispHandler
    [Microsoft.Win32.SystemEvents]::add_DisplaySettingsChanged($dispHandler)

    $window.Add_Loaded({
        Update-HotkeyRegistration -Enable ([bool]$script:UiState.Config.EnableHotkeys)
        Apply-ShadeState -RebuildScreens $true -PersistDeferred $false
        $script:UiState.HeartbeatTimer.Start()

        if ([bool]$script:UiState.Config.StartMinimized) {
            Hide-ShadeControlPanelToTray
        }
    })

    $window.Add_StateChanged({
        if (-not $script:UiState.IsClosing) {
            Sync-OverlayZOrder -Force $true
        }
    })

    $window.Add_Closed({
        $script:UiState.IsClosing = $true

        try {
            if ($null -ne $script:UiState.HeartbeatTimer) { $script:UiState.HeartbeatTimer.Stop() }
            if ($null -ne $script:UiState.SaveTimer) { $script:UiState.SaveTimer.Stop() }
        }
        catch { }

        try {
            if ($null -ne $script:UiState.DisplayChangedHandler) {
                [Microsoft.Win32.SystemEvents]::remove_DisplaySettingsChanged($script:UiState.DisplayChangedHandler)
            }
        }
        catch { }

        try {
            Update-HotkeyRegistration -Enable $false
            if ($null -ne $script:UiState.HotkeySink) {
                $script:UiState.HotkeySink.Dispose()
            }
        }
        catch { }

        try {
            Clear-Overlays
        }
        catch { }

        try {
            if ($null -ne $script:UiState.NotifyIcon) {
                $script:UiState.NotifyIcon.Visible = $false
                $script:UiState.NotifyIcon.Dispose()
            }
            if ($null -ne $script:UiState.TrayIconHandle) {
                $script:UiState.TrayIconHandle.Dispose()
            }
            if ($script:UiState.TrayRawHIcon -ne [IntPtr]::Zero) {
                Invoke-DestroyNativeIcon -IconHandle $script:UiState.TrayRawHIcon
                $script:UiState.TrayRawHIcon = [IntPtr]::Zero
            }
        }
        catch { }

        try {
            if ($null -ne $script:UiState.WakeEvent) {
                $script:UiState.WakeEvent.Dispose()
            }
            if ($null -ne $script:UiState.SingleInstanceMutex) {
                $script:UiState.SingleInstanceMutex.ReleaseMutex()
                $script:UiState.SingleInstanceMutex.Dispose()
            }
        }
        catch { }

        if ($null -ne $script:UiState.Config) {
            Save-ShadeConfig -Config $script:UiState.Config
        }
    })

    [void]$window.ShowDialog()
}

Export-ModuleMember -Function @(
    'Start-ShadeVeilGui'
)
