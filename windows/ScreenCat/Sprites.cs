using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;

namespace ScreenCat;

// Sprite art: "Cat Pack" (free tier) by Glem / octopusINKUS.
// https://octopusinkus.itch.io/cat-pack , see Assets/CREDIT.txt.
//
// The sheet is 384x288: a 12 x 9 grid of 32x32 frames. Frames are bottom
// aligned, with the ground line at row 30 and a standing cat about 27px tall.
// Side-view rows face right and are mirrored to walk left.

public enum Clip
{
    /// Sitting, front on, tail swishing, blinks.
    SitIdle,
    /// Standing, front on.
    StandIdle,
    /// Sit, then settle down.
    SitDown,
    /// Low crouch, front on.
    Crouch,
    /// Drop from standing to lying.
    LieDown,
    /// Lying, slow breathing.
    Sleep,
    /// Walking toward the viewer.
    FrontWalk,
    /// Walking in profile.
    SideWalk,
    /// Lying on its side batting the yarn ball.
    BallPlay,
    /// Profile pounce / run.
    Run,
}

public readonly struct ClipInfo
{
    public readonly int Row;
    public readonly int Start;
    public readonly int Count;
    public readonly double Fps;
    public readonly bool Loops;
    /// Side-view clips mirror when the cat faces left; front-view ones never do.
    public readonly bool Mirrors;
    /// Frame index is driven by distance travelled, not by the clock, so the
    /// paws do not skate along the ground.
    public readonly bool StrideDriven;

    public ClipInfo(int row, int start, int count, double fps, bool loops, bool mirrors, bool strideDriven)
    {
        Row = row; Start = start; Count = count; Fps = fps; Loops = loops; Mirrors = mirrors; StrideDriven = strideDriven;
    }
}

public static class ClipTable
{
    public static ClipInfo Info(this Clip clip) => clip switch
    {
        Clip.SitIdle => new ClipInfo(row: 0, start: 0, count: 9, fps: 7, loops: true, mirrors: false, strideDriven: false),
        Clip.StandIdle => new ClipInfo(row: 1, start: 0, count: 11, fps: 7, loops: true, mirrors: false, strideDriven: false),
        Clip.SitDown => new ClipInfo(row: 2, start: 0, count: 11, fps: 10, loops: false, mirrors: false, strideDriven: false),
        Clip.Crouch => new ClipInfo(row: 3, start: 0, count: 6, fps: 7, loops: true, mirrors: false, strideDriven: false),
        Clip.LieDown => new ClipInfo(row: 4, start: 0, count: 4, fps: 7, loops: false, mirrors: false, strideDriven: false),
        Clip.Sleep => new ClipInfo(row: 4, start: 4, count: 6, fps: 3, loops: true, mirrors: false, strideDriven: false),
        Clip.FrontWalk => new ClipInfo(row: 5, start: 0, count: 10, fps: 10, loops: true, mirrors: false, strideDriven: true),
        Clip.SideWalk => new ClipInfo(row: 6, start: 0, count: 10, fps: 10, loops: true, mirrors: true, strideDriven: true),
        Clip.BallPlay => new ClipInfo(row: 7, start: 0, count: 11, fps: 12, loops: true, mirrors: true, strideDriven: false),
        Clip.Run => new ClipInfo(row: 8, start: 0, count: 6, fps: 14, loops: true, mirrors: true, strideDriven: true),
        _ => new ClipInfo(1, 0, 11, 7, true, false, false),
    };

    public static readonly Clip[] All = (Clip[])Enum.GetValues(typeof(Clip));
}

/// Loads the sheet, recolours it once, and hands out frames.
public sealed class SpriteSheet : IDisposable
{
    public const int FrameSize = 32;
    /// Row 30 of each frame is where the paws meet the ground.
    public const double GroundRow = 30;
    /// A standing cat measures about this many pixels, used to map the
    /// configured cat height onto a pixel scale.
    public const double StandHeight = 27;

    public Bitmap? Sheet { get; private set; }
    public Bitmap? Ball { get; private set; }
    public Bitmap? Shadow { get; private set; }
    private readonly Dictionary<int, Bitmap> frames = new();
    /// The unrecoloured sheet's pixels (straight RGBA), kept to find the face
    /// in each frame.
    private byte[] raw = Array.Empty<byte>();
    private int rawWidth;
    private readonly Dictionary<int, Bitmap?> accessoryFrames = new();

    /// How many pixels the coat recolour changed, for the self-test.
    public int RecolouredPixels { get; private set; }

    public SpriteSheet(SpritePalette palette)
    {
        // The sheet gets the coat mapping only. The yarn colours are left alone
        // there because the cat's nose and mouth are drawn in them too, and
        // tinting those turns its face the colour of the ball.
        Sheet = Load("Cat_Sprite_Sheet.png", palette.Coat, out int changed);
        RecolouredPixels = changed;
        Ball = Load("Cat_Ball.png", palette.Yarn, out _);
        Shadow = Load("Cat_Shadow.png", new Dictionary<uint, uint>(), out _);
        LoadRaw("Cat_Sprite_Sheet.png");
    }

    public bool IsLoaded => Sheet != null;

    public void Dispose()
    {
        Sheet?.Dispose();
        Ball?.Dispose();
        Shadow?.Dispose();
        foreach (var f in frames.Values) f.Dispose();
        foreach (var f in accessoryFrames.Values) f?.Dispose();
    }

    public static Stream? Resource(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream(name);

    /// Reads a PNG into straight-alpha RGBA bytes.
    private static (byte[] px, int w, int h)? ReadRgba(string name)
    {
        using var stream = Resource(name);
        if (stream == null) return null;
        using var src = new Bitmap(stream);
        int w = src.Width, h = src.Height;
        using var argb = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(argb))
        {
            g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
            g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, w, h, GraphicsUnit.Pixel);
        }
        var data = argb.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var px = new byte[w * h * 4];
        try
        {
            unsafe
            {
                for (int y = 0; y < h; y++)
                {
                    byte* row = (byte*)data.Scan0 + y * data.Stride;
                    for (int x = 0; x < w; x++)
                    {
                        // GDI+ stores BGRA; keep RGBA like the Mac code.
                        int i = (y * w + x) * 4;
                        px[i] = row[x * 4 + 2];
                        px[i + 1] = row[x * 4 + 1];
                        px[i + 2] = row[x * 4];
                        px[i + 3] = row[x * 4 + 3];
                    }
                }
            }
        }
        finally
        {
            argb.UnlockBits(data);
        }
        return (px, w, h);
    }

    /// Straight RGBA bytes into a premultiplied bitmap, the fast format to draw.
    private static Bitmap ToBitmap(byte[] px, int w, int h)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        try
        {
            unsafe
            {
                for (int y = 0; y < h; y++)
                {
                    uint* row = (uint*)((byte*)data.Scan0 + y * data.Stride);
                    for (int x = 0; x < w; x++)
                    {
                        int i = (y * w + x) * 4;
                        uint a = px[i + 3];
                        uint r = px[i] * a / 255, g = px[i + 1] * a / 255, b = px[i + 2] * a / 255;
                        row[x] = (a << 24) | (r << 16) | (g << 8) | b;
                    }
                }
            }
        }
        finally
        {
            bmp.UnlockBits(data);
        }
        return bmp;
    }

    private static Bitmap? Load(string name, Dictionary<uint, uint> recolour, out int changed)
    {
        changed = 0;
        var read = ReadRgba(name);
        if (read == null) return null;
        var (px, w, h) = read.Value;
        if (recolour.Count > 0)
        {
            for (int i = 0; i < px.Length; i += 4)
            {
                if (px[i + 3] == 0) continue;
                // Straight alpha already, so the source colours compare
                // exactly against the palette table.
                uint key = ((uint)px[i] << 16) | ((uint)px[i + 1] << 8) | px[i + 2];
                if (!recolour.TryGetValue(key, out var to)) continue;
                px[i] = (byte)((to >> 16) & 0xFF);
                px[i + 1] = (byte)((to >> 8) & 0xFF);
                px[i + 2] = (byte)(to & 0xFF);
                changed++;
            }
        }
        return ToBitmap(px, w, h);
    }

    /// The eyes are found by their pure white, which the recolour replaces, so
    /// the search runs on the original pixels.
    private void LoadRaw(string name)
    {
        var read = ReadRgba(name);
        if (read == null) return;
        raw = read.Value.px;
        rawWidth = read.Value.w;
    }

    /// Frame `index` of `clip`, cropped out of the sheet and cached.
    public Bitmap? Frame(Clip clip, int index)
    {
        if (Sheet == null) return null;
        var info = clip.Info();
        int i = info.Count > 0 ? ((index % info.Count) + info.Count) % info.Count : 0;
        int col = info.Start + i;
        int key = info.Row * 100 + col;
        if (frames.TryGetValue(key, out var cached)) return cached;
        var rect = new Rectangle(col * FrameSize, info.Row * FrameSize, FrameSize, FrameSize);
        var img = Sheet.Clone(rect, PixelFormat.Format32bppPArgb);
        frames[key] = img;
        return img;
    }

    /// `accessory` for frame `index` of `clip`, built on first use and cached.
    /// A frame with the eyes shut borrows the face from the nearest earlier
    /// frame of the same clip that has them open.
    public Bitmap? Accessory(Accessory accessory, Clip clip, int index)
    {
        if (raw.Length == 0) return null;
        var info = clip.Info();
        int i = info.Count > 0 ? ((index % info.Count) + info.Count) % info.Count : 0;
        int key = (int)accessory * 10_000 + info.Row * 100 + info.Start + i;
        if (accessoryFrames.TryGetValue(key, out var cached)) return cached;

        int col = info.Start + i;
        int s = FrameSize;
        FaceAnchor? anchor = null;
        for (int back = 0; back < info.Count && anchor == null; back++)
        {
            int c = info.Start + ((i - back) % info.Count + info.Count) % info.Count;
            anchor = FaceAnchor.Find(raw, rawWidth, c, info.Row);
        }
        Bitmap? image = null;
        if (anchor != null)
        {
            int width = rawWidth;
            var px = raw;
            image = Accessories.Make(accessory, anchor.Value,
                (x, y) => px[((info.Row * s + y) * width + col * s + x) * 4 + 3]);
        }
        accessoryFrames[key] = image;
        return image;
    }

    /// Builds a premultiplied bitmap straight from RGBA bytes.
    public static Bitmap FromRgba(byte[] px, int w, int h) => ToBitmap(px, w, h);
}

/// Maps the pack's ten source colours onto the user's configured colours.
public sealed class SpritePalette
{
    // The exact palette of the original sheet.
    public const uint SrcOutline = 0x222034; // darkest, the outline
    public const uint SrcBody = 0x322B28;    // main coat
    public const uint SrcDark = 0x221C1A;    // deep shadow
    public const uint SrcShade1 = 0x45283C;  // mid shadow
    public const uint SrcShade2 = 0x422433;  // mid shadow
    public const uint SrcAccent = 0x793A80;  // paw pads / underside
    public const uint SrcEar = 0xE86A73;     // inner ear
    public const uint SrcEye = 0xFFFFFF;     // eyes
    public const uint SrcYarnA = 0xBC4A9B;   // yarn ball
    public const uint SrcYarnB = 0xD25A87;   // yarn ball highlight

    /// Coat, ears and eyes. Applied to the sheet.
    public readonly Dictionary<uint, uint> Coat;
    /// Yarn only. Applied to the loose ball sprite, never to the sheet.
    public readonly Dictionary<uint, uint> Yarn;

    public SpritePalette(Rgba fur, Rgba furShade, Rgba outline, Rgba inner, Rgba eye, Rgba ball)
    {
        // Same truncation as the Mac's UInt32(component * 255).
        static uint Rgb(Rgba c) => ((uint)(Rgba.Clamp01(c.R) * 255) << 16) | ((uint)(Rgba.Clamp01(c.G) * 255) << 8) | (uint)(Rgba.Clamp01(c.B) * 255);
        Coat = new Dictionary<uint, uint>
        {
            [SrcOutline] = Rgb(outline),
            [SrcBody] = Rgb(fur),
            [SrcDark] = Rgb(furShade.Blend(0.55, outline)),
            [SrcShade1] = Rgb(furShade),
            [SrcShade2] = Rgb(furShade.Blend(0.25, outline)),
            [SrcAccent] = Rgb(fur.Blend(0.45, furShade)),
            [SrcEar] = Rgb(inner),
            [SrcEye] = Rgb(eye),
        };
        Yarn = new Dictionary<uint, uint>
        {
            [SrcOutline] = Rgb(outline),
            [SrcYarnA] = Rgb(ball),
            [SrcYarnB] = Rgb(ball.Blend(0.32, Rgba.WhiteColor)),
            [SrcAccent] = Rgb(ball.Blend(0.28, Rgba.Black)),
        };
    }
}
