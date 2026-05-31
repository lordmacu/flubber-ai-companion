using System.Runtime.InteropServices;

namespace Flubber.App.Interop;

/// <summary>P/Invoke for the few Win32 APIs we need (stealth, styles, cursor).</summary>
internal static class Native
{
    // --- Stealth: exclude from captures/recordings/screen sharing ---
    public const uint WDA_NONE = 0x0;
    public const uint WDA_EXCLUDEFROMCAPTURE = 0x11;   // Windows 10 2004+

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint dwAffinity);

    // --- Extended window styles ---
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;   // outside the Alt-Tab list
    public const int WS_EX_NOACTIVATE = 0x08000000;   // don't steal focus

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    // --- Global cursor (so the slime "looks" at the pointer) ---
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    public static (int X, int Y) CursorPos()
    {
        return GetCursorPos(out var p) ? (p.X, p.Y) : (0, 0);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    // --- Window enumeration (to capture a specific app) ---
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);   // minimized

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);   // release the HICON from GetHicon()
}
