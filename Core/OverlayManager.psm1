Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$script:OverlayState = @{
    Windows            = New-Object System.Collections.ArrayList
    BrushCache         = @{}
    CurrentOpacity     = 0.45
    CurrentTintHex     = '#000000'
    CurrentScope       = 'AllScreens'
    IsEnabled          = $false
    MainWindow         = $null
    KeepPanelAbove     = $true
    LastForegroundHwnd = [IntPtr]::Zero
}

function Set-OverlayHostContext {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$MainWindow,
        [bool]$KeepPanelAbove = $true
    )

    $script:OverlayState.MainWindow = $MainWindow
    $script:OverlayState.KeepPanelAbove = $KeepPanelAbove
}

function Resolve-SolidBrush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HexColor
    )

    $safeHex = '#000000'
    if ($HexColor -match '^#[0-9A-Fa-f]{6}$') {
        $safeHex = $HexColor.ToUpperInvariant()
    }

    if ($script:OverlayState.BrushCache.ContainsKey($safeHex)) {
        return $script:OverlayState.BrushCache[$safeHex]
    }

    $color = [System.Windows.Media.ColorConverter]::ConvertFromString($safeHex)
    $brush = New-Object System.Windows.Media.SolidColorBrush($color)
    $brush.Freeze()
    $script:OverlayState.BrushCache[$safeHex] = $brush
    return $brush
}

function Get-TargetScreens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MonitorScope
    )

    $all = @([System.Windows.Forms.Screen]::AllScreens)
    if (@($all).Count -eq 0) {
        return @()
    }

    switch ($MonitorScope) {
        'PrimaryOnly' {
            $filtered = @($all | Where-Object { $_.Primary })
            if (@($filtered).Count -gt 0) { return $filtered }
            return $all
        }
        'SecondaryOnly' {
            $filtered = @($all | Where-Object { -not $_.Primary })
            if (@($filtered).Count -gt 0) { return $filtered }
            return $all
        }
        default {
            return $all
        }
    }
}

function Get-PanelInsertAfterHandle {
    [CmdletBinding()]
    param()

    $mainWin = $script:OverlayState.MainWindow
    if ($null -eq $mainWin) {
        return [IntPtr]::Zero
    }

    if (-not $script:OverlayState.KeepPanelAbove) {
        return [IntPtr]::Zero
    }

    if ($mainWin.IsVisible -and $mainWin.WindowState -ne [System.Windows.WindowState]::Minimized) {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($mainWin)
        if ($helper.Handle -ne [IntPtr]::Zero) {
            return $helper.Handle
        }
    }

    return [IntPtr]::Zero
}

function Clear-Overlays {
    [CmdletBinding()]
    param()

    foreach ($entry in @($script:OverlayState.Windows)) {
        try {
            if ($null -ne $entry.Window) {
                $entry.Window.Close()
            }
        }
        catch {
            # Ignore already closed windows
        }
    }
    $script:OverlayState.Windows.Clear()
    $script:OverlayState.LastForegroundHwnd = [IntPtr]::Zero
}

function Initialize-Overlays {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MonitorScope,

        [Parameter(Mandatory = $true)]
        [string]$TintHex,

        [Parameter(Mandatory = $true)]
        [double]$OpacityFraction
    )

    Clear-Overlays

    $script:OverlayState.CurrentScope = $MonitorScope
    $script:OverlayState.CurrentTintHex = $TintHex
    $script:OverlayState.CurrentOpacity = $OpacityFraction

    $brush = Resolve-SolidBrush -HexColor $TintHex
    $screens = @(Get-TargetScreens -MonitorScope $MonitorScope)

    foreach ($scr in $screens) {
        $win = New-Object System.Windows.Window
        $win.Title = 'ShadeVeilOverlay'
        $win.WindowStyle = [System.Windows.WindowStyle]::None
        $win.ResizeMode = [System.Windows.ResizeMode]::NoResize
        $win.AllowsTransparency = $true
        $win.ShowInTaskbar = $false
        $win.ShowActivated = $false
        $win.Focusable = $false
        $win.IsHitTestVisible = $false
        $win.Topmost = $true
        $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
        $win.Background = $brush
        $win.Opacity = $OpacityFraction

        # Initial DIP fallback before HWND exists
        $win.Left = [double]$scr.Bounds.X
        $win.Top = [double]$scr.Bounds.Y
        $win.Width = [double]$scr.Bounds.Width
        $win.Height = [double]$scr.Bounds.Height

        $win.Add_SourceInitialized({
            param($sender, $e)
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($sender)).Handle
            Enable-WindowClickThrough -WindowHandle $hwnd
        })

        [void]$script:OverlayState.Windows.Add([PSCustomObject]@{
            Window = $win
            Screen = $scr
        })
    }
}

function Update-OverlayAppearance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$IsEnabled,

        [Parameter(Mandatory = $true)]
        [int]$OpacityPercent,

        [Parameter(Mandatory = $true)]
        [string]$TintHex,

        [Parameter(Mandatory = $true)]
        [string]$MonitorScope,

        [bool]$RebuildScreens = $false
    )

    if ($OpacityPercent -lt 0) { $OpacityPercent = 0 }
    if ($OpacityPercent -gt 95) { $OpacityPercent = 95 }
    $fraction = [Math]::Round(($OpacityPercent / 100.0), 3)

    $scopeChanged = ($script:OverlayState.CurrentScope -ne $MonitorScope)
    $countZero = ($script:OverlayState.Windows.Count -eq 0)
    $didRebuild = ($RebuildScreens -or $scopeChanged -or $countZero)

    if ($didRebuild) {
        Initialize-Overlays -MonitorScope $MonitorScope -TintHex $TintHex -OpacityFraction $fraction
    }

    $tintChanged = ($script:OverlayState.CurrentTintHex -ne $TintHex)
    $brush = $null
    if ($tintChanged) {
        $brush = Resolve-SolidBrush -HexColor $TintHex
        $script:OverlayState.CurrentTintHex = $TintHex
    }

    $script:OverlayState.CurrentOpacity = $fraction
    $script:OverlayState.IsEnabled = $IsEnabled
    $insertAfter = Get-PanelInsertAfterHandle

    foreach ($entry in @($script:OverlayState.Windows)) {
        $win = $entry.Window
        $scr = $entry.Screen
        if ($null -eq $win) { continue }

        if ($null -ne $brush) {
            $win.Background = $brush
        }

        if ($win.Opacity -ne $fraction) {
            $win.Opacity = $fraction
        }

        if ($IsEnabled -and $OpacityPercent -gt 0) {
            $wasHidden = (-not $win.IsVisible)
            if ($wasHidden) {
                $win.Show()
            }

            if ($didRebuild -or $wasHidden) {
                $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
                if ($hwnd -ne [IntPtr]::Zero) {
                    Enable-WindowClickThrough -WindowHandle $hwnd
                    Set-OverlayWindowBounds -WindowHandle $hwnd `
                        -InsertAfterHandle $insertAfter `
                        -X ([int]$scr.Bounds.X) `
                        -Y ([int]$scr.Bounds.Y) `
                        -Width ([int]$scr.Bounds.Width) `
                        -Height ([int]$scr.Bounds.Height)
                }
            }
        }
        else {
            if ($win.IsVisible) {
                $win.Hide()
            }
        }
    }
}

function Sync-OverlayZOrder {
    [CmdletBinding()]
    param(
        [bool]$Force = $false
    )

    if (-not $script:OverlayState.IsEnabled) {
        return
    }

    $fg = Get-ForegroundWindowHandle
    $fgChanged = ($fg -ne $script:OverlayState.LastForegroundHwnd)
    $script:OverlayState.LastForegroundHwnd = $fg

    $insertAfter = Get-PanelInsertAfterHandle
    foreach ($entry in @($script:OverlayState.Windows)) {
        $win = $entry.Window
        if ($null -ne $win -and $win.IsVisible) {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
            if ($hwnd -ne [IntPtr]::Zero) {
                $needsSync = $Force -or $fgChanged -or (-not (Test-WindowIsTopMost -WindowHandle $hwnd))
                if ($needsSync) {
                    Set-OverlayTopMost -WindowHandle $hwnd -InsertAfterHandle $insertAfter
                }
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Set-OverlayHostContext',
    'Clear-Overlays',
    'Update-OverlayAppearance',
    'Sync-OverlayZOrder'
)
