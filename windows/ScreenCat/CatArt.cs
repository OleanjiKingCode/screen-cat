using System;
using System.Collections.Generic;

namespace ScreenCat;

/// Everything the renderer needs to know about the cat right now.
public sealed class CatState
{
    /// Surface-local coordinates of the point under the cat's paws, y up.
    public Vec Pos = Vec.Zero;
    /// 1 = facing right, -1 = facing left. Only side-view clips use it.
    public double Facing = 1;
    public Clip Clip = Clip.StandIdle;
    public double ClipTime;
    /// Distance walked in the current clip, used to drive walk and run frames.
    public double Stride;
    /// Standing height in pixels, before perspective.
    public double Size = 120;
    /// Shrinks the cat slightly as it moves up the screen, so travelling "up"
    /// reads as walking away rather than levitating.
    public double Depth = 1;
    public bool Visible;
    /// What it has on for this visit. Picked when a routine starts.
    public HashSet<Accessory> Wearing = new();

    public void SetClip(Clip c)
    {
        if (c == Clip) return;
        Clip = c;
        ClipTime = 0;
        Stride = 0;
    }

    public double DrawnSize => Size * Depth;
    public double PixelScale => DrawnSize / SpriteSheet.StandHeight;

    /// How far the cat travels per full cycle of the current walk or run.
    public double CycleDistance => Clip switch
    {
        Clip.Run => DrawnSize * 2.0,
        Clip.FrontWalk => DrawnSize * 0.9,
        _ => DrawnSize * 1.15,
    };

    public int FrameIndex
    {
        get
        {
            var info = Clip.Info();
            if (info.StrideDriven)
            {
                double cycles = Stride / Math.Max(1, CycleDistance);
                return (int)(cycles * info.Count) % Math.Max(1, info.Count);
            }
            int i = (int)(ClipTime * info.Fps);
            return info.Loops ? i % Math.Max(1, info.Count) : Math.Min(i, info.Count - 1);
        }
    }

    public bool FinishedOnce
    {
        get
        {
            var info = Clip.Info();
            return !info.Loops && ClipTime * info.Fps >= info.Count;
        }
    }

    public void Advance(double dt) => ClipTime += dt;

    /// Generous bounding box in local coordinates, for dirty-rect redraws.
    public RectD Bounds
    {
        get
        {
            double s = PixelScale * SpriteSheet.FrameSize;
            return new RectD(Pos.X - s, Pos.Y - s * 0.35, s * 2, s * 2.2);
        }
    }
}

/// Colours used by the bits that are drawn rather than blitted.
public readonly struct Palette
{
    public readonly Rgba Outline;
    public readonly Rgba Inner;

    public Palette(Rgba outline, Rgba inner) { Outline = outline; Inner = inner; }
}

public struct BallState
{
    public Vec Pos;
    /// Drawn width in pixels.
    public double Size;
    public double Rotation;
    public bool Visible;

    public RectD Bounds => new(Pos.X - Size, Pos.Y - Size, Size * 2, Size * 2);
}

public static class CatArt
{
    /// Draws `image` as crisp pixel art: nearest-neighbour, snapped to whole pixels
    /// so the sprite never shimmers as it moves.
    public static void DrawPixelImage(System.Drawing.Bitmap image, Canvas ctx, RectD rect, bool mirrored, double alpha)
    {
        var snapped = new RectD(Math.Round(rect.X), Math.Round(rect.Y), Math.Round(rect.Width), Math.Round(rect.Height));
        ctx.DrawImage(image, snapped, mirrored, alpha);
    }

    public static void DrawCat(CatState c, SpriteSheet sheet, bool drawShadow, Palette palette, Canvas ctx)
    {
        var frame = sheet.Frame(c.Clip, c.FrameIndex);
        if (frame == null) return;
        double ps = c.PixelScale;
        double side = SpriteSheet.FrameSize * ps;
        // The frame's ground line is row 30 of 32, so the sprite sits two source
        // pixels below the paws.
        var rect = new RectD(c.Pos.X - side / 2, c.Pos.Y - (SpriteSheet.FrameSize - SpriteSheet.GroundRow) * ps, side, side);

        if (drawShadow && sheet.Shadow != null)
        {
            var shadow = sheet.Shadow;
            double w = side * 0.72;
            double h = w * shadow.Height / shadow.Width;
            DrawPixelImage(shadow, ctx, new RectD(c.Pos.X - w / 2, c.Pos.Y - h * 0.45, w, h), false, 0.35);
        }

        bool mirrored = c.Clip.Info().Mirrors && c.Facing < 0;
        DrawPixelImage(frame, ctx, rect, mirrored, 1);
        // Chain first, so the glasses win anywhere the two overlap.
        foreach (var item in new[] { Accessory.Chain, Accessory.Glasses })
        {
            if (!c.Wearing.Contains(item)) continue;
            var overlay = sheet.Accessory(item, c.Clip, c.FrameIndex);
            if (overlay != null) DrawPixelImage(overlay, ctx, rect, mirrored, 1);
        }

        if (c.Clip == Clip.Sleep) DrawZzz(c, palette, ctx);
    }

    // Pixel extras the sprite pack does not include ---------------------

    /// A 5x7 pixel "z". Big enough that a one-pixel halo reads as an outline rather
    /// than swallowing the letter.
    private static readonly string[] ZGlyph =
    {
        "#####",
        "....#",
        "...#.",
        "..#..",
        ".#...",
        "#....",
        "#####",
    };

    private static void DrawZzz(CatState c, Palette pal, Canvas ctx)
    {
        double ps = c.PixelScale;
        // The sleeping cat's head is at the front, so trail the z's off that side.
        double dir = c.Facing < 0 ? -1 : 1;
        double headX = c.Pos.X + dir * ps * 8;
        for (int i = 0; i < 3; i++)
        {
            const double cycle = 2.7;
            double local = ((c.ClipTime + i * cycle / 3) % cycle) / cycle;
            double alpha = Math.Sin(local * Math.PI);
            if (alpha <= 0.05) continue;
            double px = ps * (0.8 + local * 0.5);
            double x = headX + dir * local * ps * 7;
            double y = c.Pos.Y + ps * 13 + local * ps * 14;
            // White letter, dark outline: readable over light and dark wallpaper.
            DrawGlyph(ZGlyph, new Vec(x, y), px, Rgba.White(1, 0.95), pal.Outline, alpha, ctx);
        }
    }

    /// A 5x5 pixel heart, floated up over the cat while it is being petted.
    private static readonly string[] HeartGlyph =
    {
        ".#.#.",
        "#####",
        "#####",
        ".###.",
        "..#..",
    };

    /// Two hearts rising and fading, staggered. `time` is seconds into the pet.
    public static void DrawHearts(CatState c, double time, Palette pal, Canvas ctx)
    {
        double ps = c.PixelScale;
        for (int i = 0; i < 2; i++)
        {
            double local = (time - i * 0.5) / 1.6;
            if (local <= 0 || local >= 1) continue;
            double side = i == 0 ? -1 : 1;
            double x = c.Pos.X + side * ps * 5 - ps * 2.5;
            double y = c.Pos.Y + ps * 24 + local * ps * 10;
            DrawGlyph(HeartGlyph, new Vec(x, y), ps * 0.9, pal.Inner, pal.Outline, Math.Sin(local * Math.PI), ctx);
        }
    }

    /// A little pixel food bowl, so the begging routine reads as "hungry".
    private static readonly string[] BowlGlyph =
    {
        "..rrrrrrr..",
        ".rrrrrrrrr.",
        ".rbbbbbbbr.",
        "..bbbbbbb..",
        "...bbbbb...",
        "....bbb....",
    };

    public static void DrawFoodBowl(Vec point, double pixel, Palette pal, double alpha, Canvas ctx)
    {
        double w = BowlGlyph[0].Length * pixel;
        var origin = new Vec(point.X - w / 2, point.Y);
        ctx.Save();
        ctx.SetAlpha(alpha);
        for (int rowIndex = 0; rowIndex < BowlGlyph.Length; rowIndex++)
        {
            var row = BowlGlyph[BowlGlyph.Length - 1 - rowIndex];
            for (int colIndex = 0; colIndex < row.Length; colIndex++)
            {
                char ch = row[colIndex];
                if (ch == '.') continue;
                ctx.FillRect(new RectD(Math.Round(origin.X + colIndex * pixel), Math.Round(origin.Y + rowIndex * pixel),
                    Math.Round(pixel), Math.Round(pixel)), ch == 'r' ? pal.Inner : pal.Outline);
            }
        }
        ctx.Restore();
    }

    private static void DrawGlyph(string[] glyph, Vec point, double pixel, Rgba fill, Rgba halo, double alpha, Canvas ctx)
    {
        // Snap the pixel size and the origin to whole pixels first, so every cell
        // lands on the same grid instead of rounding independently into mush.
        double p = Math.Max(2, Math.Round(pixel));
        double ox = Math.Round(point.X), oy = Math.Round(point.Y);
        ctx.Save();
        ctx.SetAlpha(alpha);
        for (int dx = -1; dx <= 1; dx++)
        {
            for (int dy = -1; dy <= 1; dy++)
            {
                if (dx == 0 && dy == 0) continue;
                Paint(glyph, ox + dx * p, oy + dy * p, p, halo, ctx);
            }
        }
        Paint(glyph, ox, oy, p, fill, ctx);
        ctx.Restore();
    }

    private static void Paint(string[] glyph, double ox, double oy, double pixel, Rgba c, Canvas ctx)
    {
        for (int rowIndex = 0; rowIndex < glyph.Length; rowIndex++)
        {
            var row = glyph[glyph.Length - 1 - rowIndex];
            for (int colIndex = 0; colIndex < row.Length; colIndex++)
            {
                if (row[colIndex] == '.') continue;
                ctx.FillRect(new RectD(ox + colIndex * pixel, oy + rowIndex * pixel, pixel, pixel), c);
            }
        }
    }

    public static void DrawBall(BallState b, SpriteSheet sheet, Canvas ctx)
    {
        var img = sheet.Ball;
        if (img == null) return;
        ctx.Save();
        ctx.Translate(b.Pos.X, b.Pos.Y);
        ctx.Rotate(b.Rotation);
        double h = b.Size * img.Height / img.Width;
        ctx.DrawImage(img, new RectD(-b.Size / 2, -h / 2, b.Size, h));
        ctx.Restore();
    }
}
