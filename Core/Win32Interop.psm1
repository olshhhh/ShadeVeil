Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('ShadeVeil.NativeMethods' -as [type])) {
    $winFormsAsm = [System.Windows.Forms.NativeWindow].Assembly.Location
    $nativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ShadeVeil
{
    public sealed class HotkeyPressedEventArgs : EventArgs
    {
        public int HotkeyId { get; private set; }

        public HotkeyPressedEventArgs(int hotkeyId)
        {
            HotkeyId = hotkeyId;
        }
    }

    public sealed class HotkeyMessageWindow : NativeWindow, IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        public event EventHandler<HotkeyPressedEventArgs> HotkeyPressed;

        public HotkeyMessageWindow()
        {
            CreateParams cp = new CreateParams();
            cp.Caption = "ShadeVeilHotkeySink";
            CreateHandle(cp);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                EventHandler<HotkeyPressedEventArgs> handler = HotkeyPressed;
                if (handler != null)
                {
                    handler(this, new HotkeyPressedEventArgs(m.WParam.ToInt32()));
                }
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            if (Handle != IntPtr.Zero)
            {
                DestroyHandle();
            }
        }
    }

    public static class NativeMethods
    {
        public const int GWL_EXSTYLE = -20;
        public const int WS_EX_TOPMOST = 0x00000008;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_TOOLWINDOW = 0x00000080;
        public const int WS_EX_LAYERED = 0x00080000;
        public const int WS_EX_NOACTIVATE = 0x08000000;

        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOZORDER = 0x0004;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;

        public const uint MOD_ALT = 0x0001;
        public const uint MOD_CONTROL = 0x0002;
        public const uint MOD_SHIFT = 0x0004;
        public const uint MOD_NOREPEAT = 0x4000;

        [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
        private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
        private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
        private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetWindowPos(
            IntPtr hWnd,
            IntPtr hWndInsertAfter,
            int X,
            int Y,
            int cx,
            int cy,
            uint uFlags
        );

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DestroyIcon(IntPtr hIcon);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

        public static void EnableDpiAwarenessSafe()
        {
            try
            {
                // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
                if (SetProcessDpiAwarenessContext(new IntPtr(-4)))
                {
                    return;
                }
            }
            catch
            {
                // Older Windows 10 builds without SetProcessDpiAwarenessContext
            }

            try
            {
                SetProcessDPIAware();
            }
            catch
            {
                // Ignore if already configured
            }
        }

        private static long GetWindowLongSafe(IntPtr hWnd, int nIndex)
        {
            if (IntPtr.Size == 8)
            {
                return GetWindowLongPtr64(hWnd, nIndex).ToInt64();
            }
            return (long)GetWindowLong32(hWnd, nIndex);
        }

        private static void SetWindowLongSafe(IntPtr hWnd, int nIndex, long dwNewLong)
        {
            if (IntPtr.Size == 8)
            {
                SetWindowLongPtr64(hWnd, nIndex, new IntPtr(dwNewLong));
            }
            else
            {
                SetWindowLong32(hWnd, nIndex, unchecked((int)dwNewLong));
            }
        }

        public static bool IsWindowTopMost(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero)
            {
                return false;
            }
            long style = GetWindowLongSafe(hWnd, GWL_EXSTYLE);
            return (style & WS_EX_TOPMOST) != 0;
        }

        public static void EnableClickThrough(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero)
            {
                return;
            }
            long currentStyle = GetWindowLongSafe(hWnd, GWL_EXSTYLE);
            long targetFlags = WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
            if ((currentStyle & targetFlags) == targetFlags)
            {
                return;
            }
            SetWindowLongSafe(hWnd, GWL_EXSTYLE, currentStyle | targetFlags);
        }

        public static void SetOverlayBoundsAndZOrder(IntPtr hWnd, IntPtr insertAfter, int x, int y, int width, int height)
        {
            if (hWnd == IntPtr.Zero)
            {
                return;
            }
            IntPtr targetZ = insertAfter == IntPtr.Zero ? HWND_TOPMOST : insertAfter;
            SetWindowPos(hWnd, targetZ, x, y, width, height, SWP_NOACTIVATE);
        }

        public static void EnsureTopMost(IntPtr hWnd, IntPtr insertAfter)
        {
            if (hWnd == IntPtr.Zero)
            {
                return;
            }
            IntPtr targetZ = insertAfter == IntPtr.Zero ? HWND_TOPMOST : insertAfter;
            SetWindowPos(hWnd, targetZ, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }
}
'@

    Add-Type -TypeDefinition $nativeSource -ReferencedAssemblies @($winFormsAsm) -ErrorAction Stop
}

function Set-DpiAwarenessSafe {
    [CmdletBinding()]
    param()

    [ShadeVeil.NativeMethods]::EnableDpiAwarenessSafe()
}

function Enable-WindowClickThrough {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle
    )

    [ShadeVeil.NativeMethods]::EnableClickThrough($WindowHandle)
}

function Set-OverlayWindowBounds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [IntPtr]$InsertAfterHandle = [IntPtr]::Zero,

        [Parameter(Mandatory = $true)]
        [int]$X,

        [Parameter(Mandatory = $true)]
        [int]$Y,

        [Parameter(Mandatory = $true)]
        [int]$Width,

        [Parameter(Mandatory = $true)]
        [int]$Height
    )

    [ShadeVeil.NativeMethods]::SetOverlayBoundsAndZOrder($WindowHandle, $InsertAfterHandle, $X, $Y, $Width, $Height)
}

function Set-OverlayTopMost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [IntPtr]$InsertAfterHandle = [IntPtr]::Zero
    )

    [ShadeVeil.NativeMethods]::EnsureTopMost($WindowHandle, $InsertAfterHandle)
}

function Test-WindowIsTopMost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle
    )

    return [ShadeVeil.NativeMethods]::IsWindowTopMost($WindowHandle)
}

function Get-ForegroundWindowHandle {
    [CmdletBinding()]
    param()

    return [ShadeVeil.NativeMethods]::GetForegroundWindow()
}

function Invoke-DestroyNativeIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$IconHandle
    )

    if ($IconHandle -ne [IntPtr]::Zero) {
        [void][ShadeVeil.NativeMethods]::DestroyIcon($IconHandle)
    }
}

function New-HotkeySink {
    [CmdletBinding()]
    param()

    return New-Object ShadeVeil.HotkeyMessageWindow
}

function Register-GlobalHotkey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [int]$HotkeyId,

        [Parameter(Mandatory = $true)]
        [uint32]$Modifiers,

        [Parameter(Mandatory = $true)]
        [uint32]$VirtualKey
    )

    return [ShadeVeil.NativeMethods]::RegisterHotKey($WindowHandle, $HotkeyId, $Modifiers, $VirtualKey)
}

function Unregister-GlobalHotkey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [int]$HotkeyId
    )

    return [ShadeVeil.NativeMethods]::UnregisterHotKey($WindowHandle, $HotkeyId)
}

function Get-DisplayInventory {
    [CmdletBinding()]
    param()

    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    $gpuNames = @()
    try {
        $controllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue)
        foreach ($gpu in $controllers) {
            if ($null -ne $gpu.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$gpu.Name)) {
                $gpuNames += [string]$gpu.Name
            }
        }
    }
    catch {
        $gpuNames = @()
    }

    $result = @()
    $index = 1
    foreach ($scr in $screens) {
        $result += [PSCustomObject]@{
            Index        = $index
            DeviceName   = $scr.DeviceName
            Primary      = [bool]$scr.Primary
            X            = [int]$scr.Bounds.X
            Y            = [int]$scr.Bounds.Y
            Width        = [int]$scr.Bounds.Width
            Height       = [int]$scr.Bounds.Height
            ScreenObject = $scr
        }
        $index++
    }

    return [PSCustomObject]@{
        Displays = $result
        Gpus     = $gpuNames
    }
}

Export-ModuleMember -Function @(
    'Set-DpiAwarenessSafe',
    'Enable-WindowClickThrough',
    'Set-OverlayWindowBounds',
    'Set-OverlayTopMost',
    'Test-WindowIsTopMost',
    'Get-ForegroundWindowHandle',
    'Invoke-DestroyNativeIcon',
    'New-HotkeySink',
    'Register-GlobalHotkey',
    'Unregister-GlobalHotkey',
    'Get-DisplayInventory'
)
