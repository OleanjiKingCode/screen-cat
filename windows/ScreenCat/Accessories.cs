using System;
using System.Drawing;

namespace ScreenCat;

/// Things the cat can wear. Each one is baked into a 32x32 overlay per sprite
/// frame and drawn on top of that frame with the same rect and mirroring, so it
/// stays glued to the face through every walk cycle, blink and head bob.
public enum Accessory
{
    Chain = 0,
    Glasses = 1,
}

/// Where the face is in one frame, found from the eye pixels of the source sheet.
///
/// Designs are written in (u, v): u runs along the line joining the eyes, with
/// the eyes at u = -2 and +2, and v runs toward the chin, with v = 0 the bottom
/// row of the eyes. That one frame of reference covers the upright frames and
/// the ball-play frames, where the cat lies on its side and the face is turned
/// a quarter with the chin pointing left.
public readonly struct FaceAnchor
{
    public readonly int X;
    public readonly int Y;
    public readonly bool Upright;

    public FaceAnchor(int x, int y, bool upright) { X = x; Y = y; Upright = upright; }

    /// (u, v) to frame pixels, y counted down from the top.
    public (int x, int y) Point(int u, int v) => Upright ? (X + u, Y + v) : (X - v, Y + u);

    /// Finds the face in the frame at (col, row). Null when the eyes are fully
    /// shut, since there is then nothing to find.
    ///
    /// Eyes are the only pure white pixels on the sheet. They close from the
    /// top down, so the bottom row of an eye stays put through a blink and
    /// makes a steady anchor.
    public static FaceAnchor? Find(byte[] px, int sheetWidth, int col, int row)
    {
        int s = SpriteSheet.FrameSize;
        int minX = s, maxX = -1, minY = s, maxY = -1;
        for (int y = 0; y < s; y++)
        {
            for (int x = 0; x < s; x++)
            {
                int i = ((row * s + y) * sheetWidth + col * s + x) * 4;
                if (i + 3 >= px.Length) continue;
                if (px[i + 3] != 255 || px[i] != 255 || px[i + 1] != 255 || px[i + 2] != 255) continue;
                minX = Math.Min(minX, x); maxX = Math.Max(maxX, x);
                minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
            }
        }
        if (maxX < 0) return null;
        // Upright eyes sit side by side, four pixels apart. Stacked ones are
        // the ball-play frames, where the lids close toward -x.
        if (maxX - minX >= 4) return new FaceAnchor((minX + maxX) / 2, maxY, true);
        return new FaceAnchor(minX, (minY + maxY) / 2, false);
    }
}

public static class Accessories
{
    private static readonly uint GoldLight = 0xFFD34E;
    private static readonly uint GoldDark = 0xC98A1B;
    private static readonly uint GoldShine = 0xFFF4B0;
    private static readonly uint ShadesFrame = 0x111018;
    private static readonly uint ShadesLens = 0x2A2440;
    private static readonly uint ShadesGlint = 0xB8E4FF;

    /// Paints one accessory for one frame into a 32x32 image.
    /// `alpha(x, y)` is the frame's own opacity, used to keep the chain on the body.
    public static Bitmap Make(Accessory accessory, FaceAnchor anchor, Func<int, int, byte> alpha)
    {
        int s = SpriteSheet.FrameSize;
        var px = new byte[s * s * 4];

        void Put(int u, int v, uint c, bool onBodyOnly = false)
        {
            var p = anchor.Point(u, v);
            if (p.x < 0 || p.x >= s || p.y < 0 || p.y >= s) return;
            if (onBodyOnly && alpha(p.x, p.y) == 0) return;
            int i = (p.y * s + p.x) * 4;
            px[i] = (byte)((c >> 16) & 0xFF);
            px[i + 1] = (byte)((c >> 8) & 0xFF);
            px[i + 2] = (byte)(c & 0xFF);
            px[i + 3] = 255;
        }

        switch (accessory)
        {
            case Accessory.Chain:
            {
                // A U of links hanging under the chin, light and dark alternating so
                // it reads as a chain and not a line, with a small pendant at the
                // bottom. Clipped to the body so it never floats in the air.
                (int u, int v)[] links = { (-4, 2), (-3, 3), (-2, 4), (-1, 4), (0, 4), (1, 4), (2, 4), (3, 3), (4, 2) };
                foreach (var (u, v) in links)
                {
                    Put(u, v, (u & 1) == 0 ? GoldLight : GoldDark, onBodyOnly: true);
                }
                Put(-1, 5, GoldDark, onBodyOnly: true);
                Put(1, 5, GoldDark, onBodyOnly: true);
                Put(0, 5, GoldShine, onBodyOnly: true);
                Put(0, 6, GoldLight, onBodyOnly: true);
                break;
            }
            case Accessory.Glasses:
            {
                // Small shades, just over the eyes: a 3x3 lens per eye with a dark
                // top rim, a one-pixel bridge between them, and a glint top left.
                foreach (int e in new[] { -2, 2 })
                {
                    for (int u = e - 1; u <= e + 1; u++)
                    {
                        Put(u, -2, ShadesFrame);
                        Put(u, -1, ShadesLens);
                        Put(u, 0, ShadesLens);
                    }
                    Put(e - 1, -1, ShadesGlint);
                }
                Put(0, -2, ShadesFrame);
                break;
            }
        }
        return SpriteSheet.FromRgba(px, s, s);
    }
}
