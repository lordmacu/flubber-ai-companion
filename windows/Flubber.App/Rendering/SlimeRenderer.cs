using SkiaSharp;

namespace Flubber.App.Rendering;

public enum SlimeState { Egg, Idle, Looking, Happy, Sleeping, Dragging, Dancing, Walking, Rolling, Falling, StuckWall, Dead }
public enum Expr { Normal, Sad, Sick }

/// <summary>Estado de animación que consume el renderer (lo calcula PetWindow cada frame).</summary>
public sealed class SlimeView
{
    public SlimeState State = SlimeState.Idle;
    public Expr Expr = Expr.Normal;
    public Skin Skin = Palette.Skins[0];
    public double ScaleX = 1, ScaleY = 1;
    public double SizeScale = 1;
    public int Tick;
    public int LookX, LookY;     // -1..1 / -1..2
    public bool Blink;
    public int Facing = 1;       // 1 derecha, -1 izquierda
    public double BodyOffsetX;   // para pasear
    public bool Listening;       // escuchando una reunión: orejitas + ondas de sonido
}

/// <summary>
/// Dibuja el slime pixel-art en una grilla 32x32 (origen abajo-izquierda, como AppKit),
/// volteada a coordenadas de Skia. Puerto de drawSlime/drawFace/drawEgg.
/// </summary>
public sealed class SlimeRenderer
{
    private const int GW = 32, GH = 32;

    private SKCanvas _canvas = null!;
    private float _px, _ox, _h;
    private readonly SKPaint _paint = new() { IsAntialias = false, Style = SKPaintStyle.Fill };

    public void Draw(SKCanvas canvas, int widthPx, int heightPx, SlimeView v)
    {
        _canvas = canvas;
        _px = widthPx / (float)GW;
        _ox = (widthPx - GW * _px) / 2f;
        _h = heightPx;

        canvas.Clear(SKColors.Transparent);

        switch (v.State)
        {
            case SlimeState.Egg: DrawEgg(v); break;
            case SlimeState.Dead: DrawSlime(v, Palette.Ghost, ghost: true); break;
            default: DrawSlime(v, v.Expr == Expr.Sick ? Palette.Sick : v.Skin, ghost: false); break;
        }
    }

    private void Fill(int gx, int gy, SKColor c)
    {
        if (gx < 0 || gx >= GW || gy < 0 || gy >= GH) return;
        _paint.Color = c;
        var x = _ox + gx * _px;
        var y = _h - (gy + 1) * _px;          // voltea: gy crece hacia arriba (como AppKit)
        _canvas.DrawRect(x, y, _px + 0.5f, _px + 0.5f, _paint);
    }

    private void DrawSlime(SlimeView v, Skin skin, bool ghost)
    {
        var sx = v.ScaleX * v.SizeScale;
        var sy = v.ScaleY * v.SizeScale;
        double baseHalf = 11, baseHeight = 17;
        var halfW = baseHalf * sx;
        var height = baseHeight * sy;
        var cx = GW / 2.0 + v.BodyOffsetX;
        const int footY = 3;
        var jig = v.State is SlimeState.Dragging or SlimeState.Dancing or SlimeState.Walking
            or SlimeState.Rolling or SlimeState.Falling or SlimeState.StuckWall ? 2.0 : 1.0;

        var h = (int)Math.Max(1, height);
        for (var gy = 0; gy < h; gy++)
        {
            var t = gy / height;
            var w = halfW * Math.Sqrt(Math.Max(0, 1 - Math.Pow(t, 2.2)));
            w += Math.Sin(v.Tick * 0.12 + t * 3) * 0.25 * jig;
            var xw = (int)Math.Round(w);
            var y = footY + gy;
            for (var dx = -xw; dx <= xw; dx++)
            {
                var gx = (int)cx + dx;
                var edge = dx <= -xw + 1 || dx >= xw - 1 || gy == 0 || gy >= (int)height - 1;
                if (edge) Fill(gx, y, skin.BodyDark);
                else if (dx < 0 && t > 0.45 && t < 0.85 && dx > -xw + 3) Fill(gx, y, skin.BodyLight);
                else Fill(gx, y, skin.Body);
            }
        }

        var shineY = footY + (int)(height * 0.72);
        Fill((int)cx - 4, shineY, skin.Shine);
        Fill((int)cx - 5, shineY, skin.Shine);
        Fill((int)cx - 4, shineY - 1, skin.Shine);

        DrawFace(v, (int)cx, height, footY, ghost);

        if (v.Listening && !ghost) DrawListening(v, (int)cx, height, footY, skin);
    }

    /// <summary>Orejitas que se inclinan (twitch) + ondas de sonido que pulsan.</summary>
    private void DrawListening(SlimeView v, int cx, double height, int footY, Skin skin)
    {
        var topY = footY + (int)height - 1;
        var tw = (v.Tick / 9 % 2 == 0) ? 0 : 1;   // movimiento de la punta

        void Ear(int x0, int lean)
        {
            for (var oy = 0; oy < 4; oy++)
            {
                var lx = x0 + (oy >= 2 ? lean : 0);
                Fill(lx, topY + oy, skin.BodyDark);                                  // borde
                Fill(lx + 1, topY + oy, oy is 1 or 2 ? Palette.Heart : skin.Body);   // interior rosita
            }
        }
        Ear(cx - 6, -tw);   // izquierda
        Ear(cx + 4, tw);    // derecha

        // ondas de sonido ")))" a la derecha de la cabeza, pulsando
        var wx = cx + 9;
        var wy = footY + (int)(height * 0.52);
        var phase = v.Tick / 7 % 3;   // 1..3 ondas visibles
        for (var i = 0; i <= phase; i++)
        {
            // un arco ")" simple
            Fill(wx + i * 2, wy + 1, Palette.EyeWhite);
            Fill(wx + i * 2 + 1, wy, Palette.EyeWhite);
            Fill(wx + i * 2, wy - 1, Palette.EyeWhite);
        }
    }

    private void DrawFace(SlimeView v, int cx, double height, int footY, bool ghost)
    {
        var faceY = footY + (int)(height * 0.45);
        const int eyeDX = 4;
        var leftX = cx - eyeDX + (v.Facing < 0 ? -1 : 0);
        var rightX = cx + eyeDX + (v.Facing < 0 ? -1 : 0);

        void EyeOpen(int ex)
        {
            for (var oy = 0; oy < 4; oy++) for (var ox = 0; ox < 3; ox++) Fill(ex + ox, faceY + oy, Palette.EyeWhite);
            var pxp = Math.Clamp(1 + v.LookX, 0, 1);
            var pyp = Math.Clamp(1 + v.LookY, 0, 2);
            for (var oy = 0; oy < 2; oy++) for (var ox = 0; ox < 2; ox++) Fill(ex + pxp + ox, faceY + pyp + oy, Palette.Eye);
        }
        void EyeClosed(int ex) { for (var ox = 0; ox < 3; ox++) Fill(ex + ox, faceY + 1, Palette.Eye); }
        void EyeHappy(int ex) { Fill(ex + 1, faceY + 2, Palette.Eye); Fill(ex, faceY + 1, Palette.Eye); Fill(ex + 2, faceY + 1, Palette.Eye); }
        void EyeSurprised(int ex)
        {
            for (var oy = 0; oy < 5; oy++) for (var ox = 0; ox < 3; ox++) Fill(ex + ox, faceY + oy, Palette.EyeWhite);
            for (var oy = 0; oy < 2; oy++) for (var ox = 0; ox < 2; ox++) Fill(ex + ox, faceY + 2 + oy, Palette.Eye);
        }
        void EyeSad(int ex)
        {
            for (var ox = 0; ox < 3; ox++) Fill(ex + ox, faceY + 3, Palette.Eye);
            for (var ox = 0; ox < 2; ox++) Fill(ex + ox, faceY + 1, Palette.Eye);
        }

        // ojos según estado / ánimo
        switch (v.State)
        {
            case SlimeState.Sleeping: EyeClosed(leftX); EyeClosed(rightX); break;
            case SlimeState.Happy: EyeHappy(leftX); EyeHappy(rightX); break;
            case SlimeState.Dragging:
            case SlimeState.Falling:
            case SlimeState.StuckWall: EyeSurprised(leftX); EyeSurprised(rightX); break;
            case SlimeState.Dancing:
                if (v.Tick / 14 % 2 == 0) { EyeHappy(leftX); EyeHappy(rightX); } else { EyeOpen(leftX); EyeOpen(rightX); }
                break;
            default:
                if (v.Blink) { EyeClosed(leftX); EyeClosed(rightX); }
                else if (v.Expr == Expr.Sad) { EyeSad(leftX); EyeSad(rightX); }
                else if (v.Expr == Expr.Sick) { EyeClosed(leftX); EyeClosed(rightX); }
                else { EyeOpen(leftX); EyeOpen(rightX); }
                break;
        }

        // boca
        if (v.State is SlimeState.Dragging or SlimeState.Falling or SlimeState.StuckWall)
        {
            for (var oy = 0; oy < 3; oy++) for (var ox = 0; ox < 2; ox++) Fill(cx - 1 + ox, faceY - 4 + oy, Palette.Mouth);
        }
        else if (v.State is SlimeState.Happy or SlimeState.Dancing)
        {
            for (var ox = -2; ox <= 2; ox++) Fill(cx + ox, faceY - 3, Palette.Mouth);
            for (var ox = -1; ox <= 1; ox++) Fill(cx + ox, faceY - 4, Palette.Mouth);
        }
        else if (v.State == SlimeState.Sleeping) { /* sin boca */ }
        else if (v.Expr is Expr.Sad or Expr.Sick)
        {
            Fill(cx, faceY - 3, Palette.Mouth); Fill(cx - 1, faceY - 4, Palette.Mouth); Fill(cx + 1, faceY - 4, Palette.Mouth);
        }
        else
        {
            Fill(cx - 1, faceY - 3, Palette.Mouth); Fill(cx, faceY - 4, Palette.Mouth); Fill(cx + 1, faceY - 3, Palette.Mouth);
        }

        // mejillas felices
        if (!ghost && v.Expr == Expr.Normal &&
            v.State is SlimeState.Idle or SlimeState.Looking or SlimeState.Happy or SlimeState.Dancing)
        {
            Fill(leftX - 1, faceY - 2, Palette.Blush);
            Fill(rightX + 2, faceY - 2, Palette.Blush);
        }
    }

    private void DrawEgg(SlimeView v)
    {
        var cx = GW / 2;
        var wob = Math.Sin(v.Tick * 0.06) * 1.0;
        const int chh = 11, cw = 8, baseY = 3;
        for (var gy = 0; gy < 2 * chh; gy++)
        {
            var t = (gy - (double)chh) / chh;
            var w = cw * Math.Sqrt(Math.Max(0, 1 - t * t)) * (gy < chh ? 1.05 : 0.92);
            var xw = (int)Math.Round(w);
            for (var dx = -xw; dx <= xw; dx++)
            {
                var gx = cx + dx + (int)wob;
                var edge = dx <= -xw + 1 || dx >= xw - 1;
                Fill(gx, baseY + gy, edge ? Palette.Egg2 : Palette.Egg1);
            }
        }
        foreach (var (sx, sy) in new[] { (-3, 6), (2, 10), (-1, 14), (4, 9) })
            Fill(cx + sx + (int)wob, baseY + sy, Palette.Egg2);
    }
}
