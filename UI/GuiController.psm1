Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:UiState = @{
    Window               = $null
    Controls             = @{}
    Config               = $null
    PresetsCatalog       = $null
    SuppressEvents       = $false
    NotifyIcon           = $null
    TrayIconHandle       = $null
    TrayToggleItem       = $null
    HotkeySink           = $null
    HotkeysRegistered    = $false
    ZOrderTimer          = $null
    DisplayChangedHandler = $null
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
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        return $icon
    }
    finally {
        $g.Dispose()
        $bmp.Dispose()
    }
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
}

function Update-VisualStatus {
    [CmdletBinding()]
    param()

    $cfg = $script:UiState.Config
    $controls = $script:UiState.Controls

    $badge = $controls['StatusBadge']
    $badgeText = $controls['StatusBadgeText']
    $powerLabel = $controls['PowerLabel']
    $opacityText = $controls['OpacityPercentText']

    if ($null -ne $opacityText) {
        $opacityText.Text = "$($cfg.Opacity)%"
    }

    if ($cfg.IsEnabled) {
        if ($null -ne $badge) {
            $bBg = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#052E16')))
            $bBr = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#16A34A')))
            $bBg.Freeze(); $bBr.Freeze()
            $badge.Background = $bBg
            $badge.BorderBrush = $bBr
        }
        if ($null -ne $badgeText) {
            $tFg = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#4ADE80')))
            $tFg.Freeze()
            $badgeText.Text = 'ACTIVO'
            $badgeText.Foreground = $tFg
        }
        if ($null -ne $powerLabel) {
            $pFg = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#93C5FD')))
            $pFg.Freeze()
            $powerLabel.Text = 'Velo ON'
            $powerLabel.Foreground = $pFg
        }
        if ($null -ne $script:UiState.TrayToggleItem) {
            $script:UiState.TrayToggleItem.Text = 'Pausar Velo (Ctrl+Alt+D)'
        }
    }
    else {
        if ($null -ne $badge) {
            $bBg = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#271710')))
            $bBr = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#D97706')))
            $bBg.Freeze(); $bBr.Freeze()
            $badge.Background = $bBg
            $badge.BorderBrush = $bBr
        }
        if ($null -ne $badgeText) {
            $tFg = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#FBBF24')))
            $tFg.Freeze()
            $badgeText.Text = 'EN PAUSA'
            $badgeText.Foreground = $tFg
        }
        if ($null -ne $powerLabel) {
            $pFg = New-Object System.Windows.Media.SolidColorBrush(([System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')))
            $pFg.Freeze()
            $powerLabel.Text = 'Velo OFF'
            $powerLabel.Foreground = $pFg
        }
        if ($null -ne $script:UiState.TrayToggleItem) {
            $script:UiState.TrayToggleItem.Text = 'Activar Velo (Ctrl+Alt+D)'
        }
    }

    if ($null -ne $script:UiState.NotifyIcon) {
        $stateStr = if ($cfg.IsEnabled) { "Activo ($($cfg.Opacity)%)" } else { 'En pausa' }
        $script:UiState.NotifyIcon.Text = "ShadeVeil - $stateStr"
    }
}

function Apply-ShadeState {
    [CmdletBinding()]
    param(
        [bool]$RebuildScreens = $false,
        [bool]$Persist = $true
    )

    $cfg = $script:UiState.Config
    $win = $script:UiState.Window

    $win.Topmost = [bool]$cfg.KeepPanelAbove
    Set-OverlayHostContext -MainWindow $win -KeepPanelAbove ([bool]$cfg.KeepPanelAbove)

    Update-OverlayAppearance `
        -IsEnabled ([bool]$cfg.IsEnabled) `
        -OpacityPercent ([int]$cfg.Opacity) `
        -TintHex ([string]$cfg.TintHex) `
        -MonitorScope ([string]$cfg.MonitorScope) `
        -RebuildScreens $RebuildScreens

    Update-VisualStatus

    if ($Persist) {
        Save-ShadeConfig -Config $cfg
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
        $controls['ChkStartMinimized'].IsChecked = [bool]$cfg.StartMinimized

        foreach ($tintName in @('RadioTintBlack', 'RadioTintAmber', 'RadioTintSlate', 'RadioTintSepia')) {
            $rb = $controls[$tintName]
            if ($null -ne $rb) {
                $rb.IsChecked = ([string]$rb.Tag -eq [string]$cfg.TintHex)
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
        [bool]$EnableIfChanged = $false
    )

    if ($NewOpacity -lt 5) { $NewOpacity = 5 }
    if ($NewOpacity -gt 95) { $NewOpacity = 95 }

    $script:UiState.Config.Opacity = $NewOpacity
    if ($EnableIfChanged) {
        $script:UiState.Config.IsEnabled = $true
    }

    Sync-ControlsFromConfig
    Apply-ShadeState
}

function Update-HotkeyRegistration {
    [CmdletBinding()]
    param(
        [bool]$Enable
    )

    $sink = $script:UiState.HotkeySink
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
        # Ctrl + Alt + NoRepeat
        [uint32]$mods = 0x0002 -bor 0x0001 -bor 0x4000
        $ok1 = Register-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 1 -Modifiers $mods -VirtualKey 0x44 # D
        $ok2 = Register-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 2 -Modifiers $mods -VirtualKey 0x26 # Up
        $ok3 = Register-GlobalHotkey -WindowHandle $sink.Handle -HotkeyId 3 -Modifiers $mods -VirtualKey 0x28 # Down
        $script:UiState.HotkeysRegistered = ($ok1 -or $ok2 -or $ok3)
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
    Sync-OverlayZOrder
}

function Hide-ShadeControlPanelToTray {
    [CmdletBinding()]
    param()

    $win = $script:UiState.Window
    if ($null -ne $win) {
        $win.Hide()
        Sync-OverlayZOrder
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
    $itemShow.Font = New-Object System.Drawing.Font($itemShow.Font, [System.Drawing.FontStyle]::Bold)
    $itemShow.Add_Click({
        Show-ShadeControlPanel
    })

    $itemToggle = New-Object System.Windows.Forms.ToolStripMenuItem('Pausar Velo (Ctrl+Alt+D)')
    $itemToggle.Add_Click({
        $script:UiState.Config.IsEnabled = -not [bool]$script:UiState.Config.IsEnabled
        Sync-ControlsFromConfig
        Apply-ShadeState
    })
    $script:UiState.TrayToggleItem = $itemToggle

    $item25 = New-Object System.Windows.Forms.ToolStripMenuItem('Opacidad 25% (Suave)')
    $item25.Add_Click({ Set-ShadeOpacityValue -NewOpacity 25 -EnableIfChanged $true })

    $item50 = New-Object System.Windows.Forms.ToolStripMenuItem('Opacidad 50% (Privacidad)')
    $item50.Add_Click({ Set-ShadeOpacityValue -NewOpacity 50 -EnableIfChanged $true })

    $item75 = New-Object System.Windows.Forms.ToolStripMenuItem('Opacidad 75% (Oscuro)')
    $item75.Add_Click({ Set-ShadeOpacityValue -NewOpacity 75 -EnableIfChanged $true })

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
    $tray.Add_DoubleClick({
        Show-ShadeControlPanel
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

    if (-not (Test-Path -LiteralPath $XamlPath)) {
        throw "No se encontro el archivo de interfaz XAML: $XamlPath"
    }

    $xamlContent = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8
    $window = [System.Windows.Markup.XamlReader]::Parse($xamlContent)

    $script:UiState.Window = $window
    $script:UiState.Config = $InitialConfig
    $script:UiState.PresetsCatalog = $PresetsCatalog

    $controlNames = @(
        'StatusBadge', 'StatusBadgeText', 'PowerLabel', 'PowerToggle',
        'OpacityPercentText', 'OpacitySlider', 'BtnDecreaseOpacity', 'BtnIncreaseOpacity',
        'BtnPresetReading', 'BtnPresetPrivacy', 'BtnPresetFocus', 'BtnPresetStealth',
        'RadioTintBlack', 'RadioTintAmber', 'RadioTintSlate', 'RadioTintSepia',
        'MonitorCountText', 'RadioScopeAll', 'RadioScopePrimary', 'RadioScopeSecondary',
        'ChkEnableHotkeys', 'ChkKeepPanelAbove', 'ChkStartMinimized',
        'BtnReset', 'BtnMinimizeToTray'
    )

    $script:UiState.Controls = @{}
    foreach ($name in $controlNames) {
        $script:UiState.Controls[$name] = $window.FindName($name)
    }

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
        Apply-ShadeState -Persist $false
    })

    $slider.Add_PreviewMouseLeftButtonUp({
        Save-ShadeConfig -Config $script:UiState.Config
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
        Apply-ShadeState
    })
    $powerToggle.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.IsEnabled = $false
        Apply-ShadeState
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
                Sync-ControlsFromConfig
                Apply-ShadeState
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
            Apply-ShadeState
        })
    }

    # Monitor scope RadioButtons
    foreach ($scopeName in @('RadioScopeAll', 'RadioScopePrimary', 'RadioScopeSecondary')) {
        $rb = $script:UiState.Controls[$scopeName]
        $rb.Add_Checked({
            param($sender, $e)
            if ($script:UiState.SuppressEvents) { return }
            $script:UiState.Config.MonitorScope = [string]$sender.Tag
            Apply-ShadeState -RebuildScreens $true
        })
    }

    # Behavior CheckBoxes
    $chkHotkeys = $script:UiState.Controls['ChkEnableHotkeys']
    $chkHotkeys.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.EnableHotkeys = $true
        Update-HotkeyRegistration -Enable $true
        Save-ShadeConfig -Config $script:UiState.Config
    })
    $chkHotkeys.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.EnableHotkeys = $false
        Update-HotkeyRegistration -Enable $false
        Save-ShadeConfig -Config $script:UiState.Config
    })

    $chkTop = $script:UiState.Controls['ChkKeepPanelAbove']
    $chkTop.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.KeepPanelAbove = $true
        Apply-ShadeState
    })
    $chkTop.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.KeepPanelAbove = $false
        Apply-ShadeState
    })

    $chkMin = $script:UiState.Controls['ChkStartMinimized']
    $chkMin.Add_Checked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.StartMinimized = $true
        Save-ShadeConfig -Config $script:UiState.Config
    })
    $chkMin.Add_Unchecked({
        if ($script:UiState.SuppressEvents) { return }
        $script:UiState.Config.StartMinimized = $false
        Save-ShadeConfig -Config $script:UiState.Config
    })

    # Footer Buttons
    $script:UiState.Controls['BtnReset'].Add_Click({
        $def = Get-DefaultShadeConfig
        $script:UiState.Config.IsEnabled = $def.IsEnabled
        $script:UiState.Config.Opacity = $def.Opacity
        $script:UiState.Config.TintHex = $def.TintHex
        $script:UiState.Config.MonitorScope = $def.MonitorScope
        $script:UiState.Config.KeepPanelAbove = $def.KeepPanelAbove
        Sync-ControlsFromConfig
        Apply-ShadeState -RebuildScreens $true
    })

    $script:UiState.Controls['BtnMinimizeToTray'].Add_Click({
        Hide-ShadeControlPanelToTray
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

    # Periodic lightweight Z-Order guard (keeps veil above Windows Taskbar)
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1500)
    $timer.Add_Tick({
        Sync-OverlayZOrder
    })
    $script:UiState.ZOrderTimer = $timer

    # Monitor topology change listener
    $dispHandler = [System.EventHandler]{
        param($sender, $e)
        if ($null -ne $script:UiState.Window) {
            [void]$script:UiState.Window.Dispatcher.BeginInvoke([Action]{
                Update-DisplayCountLabel
                Apply-ShadeState -RebuildScreens $true -Persist $false
            })
        }
    }
    $script:UiState.DisplayChangedHandler = $dispHandler
    [Microsoft.Win32.SystemEvents]::add_DisplaySettingsChanged($dispHandler)

    $window.Add_Loaded({
        Update-HotkeyRegistration -Enable ([bool]$script:UiState.Config.EnableHotkeys)
        Apply-ShadeState -RebuildScreens $true -Persist $false
        $script:UiState.ZOrderTimer.Start()

        if ([bool]$script:UiState.Config.StartMinimized) {
            Hide-ShadeControlPanelToTray
        }
    })

    $window.Add_StateChanged({
        Sync-OverlayZOrder
    })

    $window.Add_Closed({
        try {
            if ($null -ne $script:UiState.ZOrderTimer) {
                $script:UiState.ZOrderTimer.Stop()
            }
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
