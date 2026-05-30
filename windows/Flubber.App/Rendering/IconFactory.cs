using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Flubber.App.Interop;
using SkiaSharp;

namespace Flubber.App.Rendering;

/// <summary>Renderiza el slime a un System.Drawing.Icon para la bandeja del sistema.</summary>
public static class IconFactory
{
    public static Icon SlimeTrayIcon(int size = 32)
    {
        try
        {
            var view = new SlimeView { State = SlimeState.Happy, Skin = Palette.Skins[0], SizeScale = 1 };
            var info = new SKImageInfo(size, size, SKColorType.Bgra8888, SKAlphaType.Unpremul);
            using var sk = new SKBitmap(info);
            using (var canvas = new SKCanvas(sk))
                new SlimeRenderer().Draw(canvas, size, size, view);

            using var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            var rect = new Rectangle(0, 0, size, size);
            var bd = bmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            Marshal.Copy(sk.Bytes, 0, bd.Scan0, sk.Bytes.Length);
            bmp.UnlockBits(bd);

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
