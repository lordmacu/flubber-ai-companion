using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using Flubber.App.Interop;

namespace Flubber.App.Rendering;

/// <summary>
/// Icono de la bandeja. Carga trayicon.png (embebido), que es EXACTAMENTE el mismo
/// render pixel-art que el icono de macOS (icon/make-icon.swift) → icono idéntico
/// en ambas plataformas. Se regenera con windows/gen-icon.sh.
/// </summary>
public static class IconFactory
{
    public static Icon SlimeTrayIcon(int size = 32)
    {
        try
        {
            var asm = typeof(IconFactory).Assembly;
            using var stream = asm.GetManifestResourceStream("Flubber.App.trayicon.png")
                ?? throw new InvalidOperationException("trayicon.png no embebido");
            using var src = new Bitmap(stream);
            using var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(src, new Rectangle(0, 0, size, size));
            }
            var hicon = bmp.GetHicon();
            try { return (Icon)Icon.FromHandle(hicon).Clone(); }
            finally { Native.DestroyIcon(hicon); }
        }
        catch
        {
            return SystemIcons.Application;
        }
    }
}
