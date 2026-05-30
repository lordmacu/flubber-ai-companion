using SkiaSharp;
using Flubber.Core.AI;

namespace Flubber.App.Rendering;

public readonly struct Skin
{
    public readonly SKColor Body, BodyDark, BodyLight, Shine;
    public Skin(SKColor body, SKColor dark, SKColor light, SKColor shine)
    { Body = body; BodyDark = dark; BodyLight = light; Shine = shine; }
}

/// <summary>Paleta del slime (skins + colores de cara). Puerto de Pal/Skin (main.swift).</summary>
public static class Palette
{
    private static SKColor C(double r, double g, double b, double a = 1) =>
        new((byte)(r * 255), (byte)(g * 255), (byte)(b * 255), (byte)(a * 255));

    public static readonly Skin[] Skins =
    {
        new(C(0.36, 0.85, 0.55), C(0.20, 0.62, 0.40), C(0.62, 0.96, 0.72), C(0.92, 1.00, 0.95)), // verde
        new(C(0.42, 0.66, 0.98), C(0.24, 0.42, 0.78), C(0.68, 0.84, 1.00), C(0.90, 0.95, 1.00)), // azul
        new(C(0.78, 0.55, 0.96), C(0.55, 0.34, 0.74), C(0.90, 0.76, 1.00), C(0.97, 0.93, 1.00)), // morado
        new(C(0.99, 0.62, 0.78), C(0.85, 0.40, 0.58), C(1.00, 0.80, 0.89), C(1.00, 0.95, 0.97)), // rosa
    };

    public static readonly Skin Sick = new(C(0.62, 0.74, 0.45), C(0.42, 0.54, 0.30), C(0.78, 0.86, 0.60), C(0.92, 0.96, 0.80));
    public static readonly Skin Ghost = new(C(0.82, 0.82, 0.82, 0.85), C(0.55, 0.55, 0.55, 0.85), C(0.95, 0.95, 0.95, 0.85), SKColors.White);

    public static readonly SKColor Eye = C(0.10, 0.16, 0.18);
    public static readonly SKColor EyeWhite = SKColors.White;
    public static readonly SKColor Mouth = C(0.15, 0.40, 0.28);
    public static readonly SKColor Blush = C(1.00, 0.62, 0.62, 0.55);
    public static readonly SKColor Heart = C(1.00, 0.36, 0.52);
    public static readonly SKColor Egg1 = C(0.96, 0.93, 0.84);
    public static readonly SKColor Egg2 = C(0.85, 0.80, 0.68);

    public static int Index { get; set; }
    private static Skin? _aiSkin;

    public static Skin Current => _aiSkin ?? Skins[Math.Clamp(Index, 0, Skins.Length - 1)];

    public static void SetAiSkin(Skin s) => _aiSkin = s;
    public static void ClearAiSkin() => _aiSkin = null;

    public static Skin? FromSpec(SkinSpec spec)
    {
        if (TryHex(spec.Body, out var b) && TryHex(spec.Dark, out var d) &&
            TryHex(spec.Light, out var l) && TryHex(spec.Shine, out var s))
            return new Skin(b, d, l, s);
        return null;
    }

    private static bool TryHex(string hex, out SKColor color)
    {
        color = SKColors.Black;
        var h = hex.StartsWith("#") ? hex[1..] : hex;
        if (h.Length != 6) return false;
        try
        {
            var r = Convert.ToByte(h[..2], 16);
            var g = Convert.ToByte(h.Substring(2, 2), 16);
            var b = Convert.ToByte(h.Substring(4, 2), 16);
            color = new SKColor(r, g, b);
            return true;
        }
        catch { return false; }
    }
}
