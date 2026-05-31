using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Text;
using Flubber.App.Interop;
using Flubber.Core.Platform;
using Flubber.Core.Util;

namespace Flubber.App.Platform;

/// <summary>
/// Screen capture with GDI (BitBlt via CopyFromScreen). If <c>appHint</c> matches
/// an app/window, captures ONLY that window's rect; otherwise the whole screen.
/// Equivalent to macOS's ScreenCapture.grab. The Flubber window is excluded by
/// its display-affinity (WDA_EXCLUDEFROMCAPTURE).
/// </summary>
public static class ScreenCapture
{
    private static readonly string[] Browsers =
        { "chrome", "msedge", "edge", "brave", "firefox", "opera", "vivaldi", "arc", "dia", "comet" };

    public static Task<(string? Base64, string? Path)> CaptureAsync(string? appHint) => Task.Run(() =>
    {
        try
        {
            Rectangle rect;
            var targeted = !string.IsNullOrWhiteSpace(appHint) ? FindWindowRect(appHint!) : (Rectangle?)null;
            if (targeted is { } r && r.Width > 8 && r.Height > 8) rect = r;
            else
            {
                var b = System.Windows.Forms.Screen.PrimaryScreen!.Bounds;
                rect = new Rectangle(b.X, b.Y, b.Width, b.Height);
            }

            using var full = new Bitmap(rect.Width, rect.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(full))
                g.CopyFromScreen(rect.X, rect.Y, 0, 0, rect.Size, CopyPixelOperation.SourceCopy);

            var (b64, bytes) = EncodeJpeg(full, 1000);
            if (b64 == null) return ((string?)null, (string?)null);

            string? path = null;
            try
            {
                path = System.IO.Path.Combine(Paths.ShotsDir, Guid.NewGuid().ToString("N") + ".jpg");
                System.IO.File.WriteAllBytes(path, bytes!);
            }
            catch { path = null; }

            return ((string?)b64, path);
        }
        catch (Exception e)
        {
            Log.Write("capture error: " + e.Message);
            return ((string?)null, (string?)null);
        }
    });

    private static (string? B64, byte[]? Bytes) EncodeJpeg(Bitmap src, int maxW)
    {
        var scale = Math.Min(1.0, maxW / (double)src.Width);
        var nw = Math.Max(1, (int)(src.Width * scale));
        var nh = Math.Max(1, (int)(src.Height * scale));

        using var resized = new Bitmap(nw, nh, PixelFormat.Format24bppRgb);
        using (var g = Graphics.FromImage(resized))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(src, new Rectangle(0, 0, nw, nh));
        }

        var codec = ImageCodecInfo.GetImageEncoders().FirstOrDefault(c => c.FormatID == ImageFormat.Jpeg.Guid);
        if (codec == null) return (null, null);
        using var ep = new EncoderParameters(1);
        ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 55L);
        using var ms = new MemoryStream();
        resized.Save(ms, codec, ep);
        var bytes = ms.ToArray();
        return (Convert.ToBase64String(bytes), bytes);
    }

    /// <summary>Finds the rect of the frontmost visible window matching the hint.</summary>
    private static Rectangle? FindWindowRect(string hint)
    {
        var h = hint.Trim().ToLowerInvariant();
        var wantBrowser = h.Contains("navegad") || h.Contains("browser");
        IntPtr found = IntPtr.Zero;

        Native.EnumWindows((hWnd, _) =>
        {
            if (!Native.IsWindowVisible(hWnd) || Native.IsIconic(hWnd)) return true;   // skip hidden/minimized
            var len = Native.GetWindowTextLength(hWnd);
            if (len == 0) return true;
            var sb = new StringBuilder(len + 1);
            Native.GetWindowText(hWnd, sb, sb.Capacity);
            var title = sb.ToString();
            if (string.IsNullOrWhiteSpace(title)) return true;

            string proc = "";
            try
            {
                Native.GetWindowThreadProcessId(hWnd, out var pid);
                proc = Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant();
            }
            catch { /* ignore */ }
            if (proc == "flubber") return true;

            var titleLo = title.ToLowerInvariant();
            var match = wantBrowser
                ? Browsers.Any(b => proc.Contains(b))
                : proc.Contains(h) || h.Contains(proc) || titleLo.Contains(h);
            if (match) { found = hWnd; return false; }   // EnumWindows goes front to back
            return true;
        }, IntPtr.Zero);

        if (found == IntPtr.Zero) return null;
        return Native.GetWindowRect(found, out var r)
            ? new Rectangle(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top)
            : null;
    }
}
