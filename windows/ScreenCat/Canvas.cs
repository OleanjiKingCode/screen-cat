using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace ScreenCat;

/// A device-space rectangle in whole pixels, y pointing down.
public struct RectI
{
    public int X0, Y0, X1, Y1;

    public RectI(int x0, int y0, int x1, int y1) { X0 = x0; Y0 = y0; X1 = x1; Y1 = y1; }

    public int Width => X1 - X0;
    public int Height => Y1 - Y0;
    public bool IsEmpty => X1 <= X0 || Y1 <= Y0;

    public RectI Intersect(RectI o) => new(Math.Max(X0, o.X0), Math.Max(Y0, o.Y0), Math.Min(X1, o.X1), Math.Min(Y1, o.Y1));

    public RectI Union(RectI o)
    {
        if (IsEmpty) return o;
        if (o.IsEmpty) return this;
        return new(Math.Min(X0, o.X0), Math.Min(Y0, o.Y0), Math.Max(X1, o.X1), Math.Max(Y1, o.Y1));
    }

    public static RectI Around(RectD r)
    {
        if (r.IsNull) return default;
        return new((int)Math.Floor(r.MinX), (int)Math.Floor(r.MinY), (int)Math.Ceiling(r.MaxX), (int)Math.Ceiling(r.MaxY));
    }

    public Rectangle ToRectangle() => new(X0, Y0, Math.Max(0, Width), Math.Max(0, Height));
}

/// A path in user space: lines, rectangles, ovals and pie wedges. Turned into
/// a GDI+ path when it is drawn.
public sealed class PathD
{
    internal readonly GraphicsPath Gp = new();
    private Vec current;
    private bool open;

    public void MoveTo(Vec p) { Gp.StartFigure(); current = p; open = true; }
    public void MoveTo(double x, double y) => MoveTo(new Vec(x, y));

    public void LineTo(Vec p)
    {
        if (!open) { MoveTo(p); return; }
        Gp.AddLine((float)current.X, (float)current.Y, (float)p.X, (float)p.Y);
        current = p;
    }

    public void LineTo(double x, double y) => LineTo(new Vec(x, y));

    public void Close() { Gp.CloseFigure(); open = false; }

    public void AddRect(RectD r)
    {
        Gp.StartFigure();
        Gp.AddRectangle(new RectangleF((float)r.X, (float)r.Y, (float)r.Width, (float)r.Height));
        open = false;
    }

    public void AddOval(RectD r)
    {
        Gp.StartFigure();
        Gp.AddEllipse((float)r.X, (float)r.Y, (float)r.Width, (float)r.Height);
        open = false;
    }

    /// A pie slice from `startDeg` to `endDeg`, counter-clockwise in y-up space.
    public void AddWedge(Vec centre, double radius, double startDeg, double endDeg)
    {
        Gp.StartFigure();
        Gp.AddPie((float)(centre.X - radius), (float)(centre.Y - radius), (float)(radius * 2), (float)(radius * 2),
            (float)startDeg, (float)(endDeg - startDeg));
        open = false;
    }
}

/// A 32-bit premultiplied drawing surface. It mirrors the bits of CGContext the
/// Mac code uses: a current transform, a global alpha, a rectangular clip and a
/// save/restore stack. Axis-aligned fills and text go straight into the pixel
/// buffer, which is far faster than GDI+ for the thousands of small blocks a
/// glitch draws; curves, strokes and images go through GDI+.
public sealed unsafe class Canvas : IDisposable
{
    public readonly int Width;
    public readonly int Height;
    public readonly int Stride;
    public readonly IntPtr Bits;
    public readonly Bitmap Bitmap;
    public readonly Graphics G;
    private readonly bool ownsMemory;
    private bool gdiPending;

    private struct State
    {
        public Affine Ctm;
        public double Alpha;
        public RectI Clip;
        public bool Smooth;
    }

    private State s;
    private readonly Stack<State> stack = new();

    /// A canvas with its own memory.
    public Canvas(int width, int height) : this(width, height, IntPtr.Zero, 0) { }

    /// A canvas over memory owned by someone else, such as a DIB section.
    public Canvas(int width, int height, IntPtr bits, int stride)
    {
        Width = Math.Max(1, width);
        Height = Math.Max(1, height);
        if (bits == IntPtr.Zero)
        {
            Stride = Width * 4;
            Bits = Marshal.AllocHGlobal(Stride * Height);
            ownsMemory = true;
            new Span<byte>((void*)Bits, Stride * Height).Clear();
        }
        else
        {
            Bits = bits;
            Stride = stride;
        }
        Bitmap = new Bitmap(Width, Height, Stride, PixelFormat.Format32bppPArgb, Bits);
        G = Graphics.FromImage(Bitmap);
        G.InterpolationMode = InterpolationMode.NearestNeighbor;
        G.PixelOffsetMode = PixelOffsetMode.Half;
        G.CompositingQuality = CompositingQuality.HighSpeed;
        s = new State { Ctm = Affine.Identity, Alpha = 1, Clip = new RectI(0, 0, Width, Height), Smooth = true };
    }

    public void Dispose()
    {
        G.Dispose();
        Bitmap.Dispose();
        if (ownsMemory) Marshal.FreeHGlobal(Bits);
    }

    // State -------------------------------------------------------------

    public Affine Ctm => s.Ctm;

    public void Save() => stack.Push(s);

    public void Restore()
    {
        if (stack.Count > 0) s = stack.Pop();
    }

    /// Resets the transform, alpha and clip, and empties the stack.
    public void ResetState()
    {
        stack.Clear();
        s = new State { Ctm = Affine.Identity, Alpha = 1, Clip = new RectI(0, 0, Width, Height), Smooth = true };
    }

    /// `t` runs first, then the current transform.
    public void Concat(Affine t) => s.Ctm = s.Ctm.Then(t);
    public void Translate(double x, double y) => Concat(Affine.Translation(x, y));
    public void Scale(double sx, double sy) => Concat(Affine.Scaling(sx, sy));
    public void Rotate(double radians) => Concat(new Affine(Math.Cos(radians), Math.Sin(radians), -Math.Sin(radians), Math.Cos(radians), 0, 0));

    /// Like CGContext.setAlpha: replaces the global alpha.
    public void SetAlpha(double a) => s.Alpha = Rgba.Clamp01(a);
    public double Alpha => s.Alpha;

    public void SetSmooth(bool on) => s.Smooth = on;

    /// Narrows the clip to `r`, in user space.
    public void ClipTo(RectD r)
    {
        var d = r.Apply(s.Ctm);
        var ri = new RectI((int)Math.Round(d.MinX), (int)Math.Round(d.MinY), (int)Math.Round(d.MaxX), (int)Math.Round(d.MaxY));
        s.Clip = s.Clip.Intersect(ri);
    }

    /// Narrows the clip to a device rectangle.
    public void ClipToDevice(RectI r) => s.Clip = s.Clip.Intersect(r);

    // Pixels ------------------------------------------------------------

    private void FlushGdi()
    {
        if (!gdiPending) return;
        G.Flush(FlushIntention.Sync);
        gdiPending = false;
    }

    /// Sets every pixel in `r` (device space) to transparent.
    public void ClearDevice(RectI r)
    {
        FlushGdi();
        r = r.Intersect(new RectI(0, 0, Width, Height));
        if (r.IsEmpty) return;
        for (int y = r.Y0; y < r.Y1; y++)
        {
            new Span<uint>((void*)(Bits + y * Stride + r.X0 * 4), r.Width).Clear();
        }
    }

    /// A filled axis-aligned rectangle in user space, no antialiasing.
    public void FillRect(RectD r, Rgba c)
    {
        double a = c.A * s.Alpha;
        if (a <= 0.002 || r.Width <= 0 || r.Height <= 0) return;
        var d = r.Apply(s.Ctm);
        int x0 = (int)Math.Round(d.MinX), x1 = (int)Math.Round(d.MaxX);
        int y0 = (int)Math.Round(d.MinY), y1 = (int)Math.Round(d.MaxY);
        // A sliver thinner than a pixel still shows, as one pixel.
        if (x1 == x0 && d.Width > 0.2) x1 = x0 + 1;
        if (y1 == y0 && d.Height > 0.2) y1 = y0 + 1;
        FillDevice(new RectI(x0, y0, x1, y1), c, a);
    }

    public void FillRect(double x, double y, double w, double h, Rgba c) => FillRect(new RectD(x, y, w, h), c);

    private void FillDevice(RectI r, Rgba c, double a)
    {
        r = r.Intersect(s.Clip);
        if (r.IsEmpty) return;
        FlushGdi();
        uint sa = (uint)Math.Round(Rgba.Clamp01(a) * 255);
        if (sa == 0) return;
        uint sr = (uint)Math.Round(Rgba.Clamp01(c.R) * a * 255);
        uint sg = (uint)Math.Round(Rgba.Clamp01(c.G) * a * 255);
        uint sb = (uint)Math.Round(Rgba.Clamp01(c.B) * a * 255);
        uint packed = (sa << 24) | (sr << 16) | (sg << 8) | sb;
        uint inv = 255 - sa;
        for (int y = r.Y0; y < r.Y1; y++)
        {
            uint* row = (uint*)(Bits + y * Stride) + r.X0;
            int n = r.Width;
            if (sa == 255)
            {
                new Span<uint>(row, n).Fill(packed);
                continue;
            }
            for (int i = 0; i < n; i++)
            {
                uint d = row[i];
                uint da = d >> 24, dr = (d >> 16) & 0xFF, dg = (d >> 8) & 0xFF, db = d & 0xFF;
                da = sa + (da * inv + 127) / 255;
                dr = sr + (dr * inv + 127) / 255;
                dg = sg + (dg * inv + 127) / 255;
                db = sb + (db * inv + 127) / 255;
                row[i] = (da << 24) | (dr << 16) | (dg << 8) | db;
            }
        }
    }

    // GDI+ --------------------------------------------------------------

    private void PrepareGdi()
    {
        G.ResetTransform();
        G.SetClip(s.Clip.ToRectangle());
        var m = s.Ctm;
        G.Transform = new Matrix((float)m.A, (float)m.B, (float)m.C, (float)m.D, (float)m.E, (float)m.F);
        G.SmoothingMode = s.Smooth ? SmoothingMode.AntiAlias : SmoothingMode.None;
        gdiPending = true;
    }

    public void Fill(PathD path, Rgba c)
    {
        if (c.A * s.Alpha <= 0.002) return;
        PrepareGdi();
        using var brush = new SolidBrush(c.ToColor(s.Alpha));
        G.FillPath(brush, path.Gp);
    }

    public void Stroke(PathD path, Rgba c, double width, bool miter = false)
    {
        if (c.A * s.Alpha <= 0.002) return;
        PrepareGdi();
        using var pen = new Pen(c.ToColor(s.Alpha), (float)width);
        pen.LineJoin = miter ? LineJoin.Miter : LineJoin.Round;
        G.DrawPath(pen, path.Gp);
    }

    public void FillOval(RectD r, Rgba c)
    {
        var p = new PathD();
        p.AddOval(r);
        Fill(p, c);
    }

    /// An oval filled with a gradient running from `bottom` up to `top`, in
    /// y-up user space (NSGradient at 90 degrees).
    public void FillOvalGradient(RectD r, Rgba bottom, Rgba top)
    {
        PrepareGdi();
        using var brush = new LinearGradientBrush(
            new PointF((float)r.MidX, (float)r.MinY - 0.5f), new PointF((float)r.MidX, (float)r.MaxY + 0.5f),
            bottom.ToColor(s.Alpha), top.ToColor(s.Alpha));
        G.FillEllipse(brush, (float)r.X, (float)r.Y, (float)r.Width, (float)r.Height);
    }

    /// Draws `image` into `r`, upright in y-up user space, nearest-neighbour.
    /// `mirrored` flips it left to right about the rect's middle.
    public void DrawImage(Bitmap image, RectD r, bool mirrored = false, double alpha = 1)
    {
        double a = alpha * s.Alpha;
        if (a <= 0.002 || r.Width <= 0 || r.Height <= 0) return;
        Save();
        if (mirrored)
        {
            Translate(r.MidX, 0);
            Scale(-1, 1);
            Translate(-r.MidX, 0);
        }
        Translate(r.X, r.MaxY);
        Scale(r.Width / image.Width, -r.Height / image.Height);
        PrepareGdi();
        Restore();
        var dest = new Rectangle(0, 0, image.Width, image.Height);
        if (a >= 0.999)
        {
            G.DrawImage(image, dest, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel);
            return;
        }
        using var attrs = new ImageAttributes();
        var cm = new ColorMatrix { Matrix33 = (float)a };
        attrs.SetColorMatrix(cm);
        G.DrawImage(image, dest, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, attrs);
    }

    // Text --------------------------------------------------------------

    /// Monospaced text with the bottom-left of its line at (x, y) in y-up user
    /// space, always upright on screen. Glyphs are rendered once per size and
    /// then blitted, because GDI+ text every frame is far too slow for a
    /// screenful of hex.
    public void DrawText(string text, double x, double y, Rgba c, double size, bool bold = false)
    {
        double a = c.A * s.Alpha;
        if (a <= 0.01 || string.IsNullOrEmpty(text)) return;
        int px = Math.Max(4, (int)Math.Round(size * s.Ctm.ScaleFactor));
        var atlas = GlyphAtlas.Get(px, bold);
        var origin = s.Ctm.Apply(x, y);
        int penX = (int)Math.Round(origin.X);
        int top = (int)Math.Round(origin.Y) - atlas.LineHeight;
        FlushGdi();
        foreach (char ch in text)
        {
            var glyph = atlas.Glyph(ch);
            if (glyph != null) BlitMask(glyph, penX, top, c, a);
            penX += atlas.Advance;
        }
    }

    /// Width of `text` in user units at `size`.
    public double TextWidth(string text, double size, bool bold = false)
    {
        int px = Math.Max(4, (int)Math.Round(size * s.Ctm.ScaleFactor));
        return text.Length * GlyphAtlas.Get(px, bold).Advance / Math.Max(0.0001, s.Ctm.ScaleFactor);
    }

    private void BlitMask(GlyphMask g, int left, int top, Rgba c, double a)
    {
        var area = new RectI(left, top, left + g.Width, top + g.Height).Intersect(s.Clip);
        if (area.IsEmpty) return;
        double cr = Rgba.Clamp01(c.R) * 255, cg = Rgba.Clamp01(c.G) * 255, cb = Rgba.Clamp01(c.B) * 255;
        for (int y = area.Y0; y < area.Y1; y++)
        {
            uint* row = (uint*)(Bits + y * Stride);
            int my = y - top;
            for (int x = area.X0; x < area.X1; x++)
            {
                byte m = g.Alpha[my * g.Width + (x - left)];
                if (m == 0) continue;
                double k = m / 255.0 * a;
                uint sa = (uint)(k * 255 + 0.5);
                if (sa == 0) continue;
                uint sr = (uint)(cr * k + 0.5), sg = (uint)(cg * k + 0.5), sb = (uint)(cb * k + 0.5);
                uint inv = 255 - sa;
                uint d = row[x];
                uint da = sa + ((d >> 24) * inv + 127) / 255;
                uint dr = sr + (((d >> 16) & 0xFF) * inv + 127) / 255;
                uint dg = sg + (((d >> 8) & 0xFF) * inv + 127) / 255;
                uint db = sb + ((d & 0xFF) * inv + 127) / 255;
                row[x] = (Math.Min(255u, da) << 24) | (Math.Min(255u, dr) << 16) | (Math.Min(255u, dg) << 8) | Math.Min(255u, db);
            }
        }
    }

    // Images ------------------------------------------------------------

    /// A copy of the canvas as a standalone bitmap, for saving to PNG.
    public Bitmap Snapshot()
    {
        FlushGdi();
        var copy = new Bitmap(Width, Height, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(copy);
        g.DrawImageUnscaled(Bitmap, 0, 0);
        return copy;
    }

    public void Flush() => FlushGdi();
}

/// One character as an 8-bit coverage mask.
public sealed class GlyphMask
{
    public int Width;
    public int Height;
    public byte[] Alpha = Array.Empty<byte>();
}

/// Monospaced glyphs at one pixel size, rendered on first use.
public sealed class GlyphAtlas
{
    private static readonly Dictionary<(int, bool), GlyphAtlas> Atlases = new();
    private static string? monoFamily;
    private static string? kanaFamily;
    private static bool familiesChecked;

    private readonly Dictionary<char, GlyphMask?> glyphs = new();
    private readonly Font font;
    private readonly Font? kanaFont;
    public readonly int Advance;
    public readonly int LineHeight;
    private readonly int cellWidth;

    public static GlyphAtlas Get(int px, bool bold)
    {
        if (!Atlases.TryGetValue((px, bold), out var atlas))
        {
            atlas = new GlyphAtlas(px, bold);
            Atlases[(px, bold)] = atlas;
        }
        return atlas;
    }

    private static void FindFamilies()
    {
        if (familiesChecked) return;
        familiesChecked = true;
        var installed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var fonts = new InstalledFontCollection();
            foreach (var f in fonts.Families) installed.Add(f.Name);
        }
        catch { }
        foreach (var name in new[] { "Consolas", "Cascadia Mono", "Lucida Console", "Courier New" })
        {
            if (installed.Contains(name)) { monoFamily = name; break; }
        }
        // The falling-code styles use katakana, which the code fonts lack.
        foreach (var name in new[] { "Yu Gothic", "Meiryo", "MS Gothic", "Yu Gothic UI", "Meiryo UI" })
        {
            if (installed.Contains(name)) { kanaFamily = name; break; }
        }
    }

    private GlyphAtlas(int px, bool bold)
    {
        FindFamilies();
        var style = bold ? FontStyle.Bold : FontStyle.Regular;
        font = new Font(monoFamily ?? FontFamily.GenericMonospace.Name, px, style, GraphicsUnit.Pixel);
        if (kanaFamily != null) kanaFont = new Font(kanaFamily, px, style, GraphicsUnit.Pixel);
        using var probe = new Bitmap(4, 4);
        using var g = Graphics.FromImage(probe);
        var size = g.MeasureString("0000000000", font, PointF.Empty, StringFormat.GenericTypographic);
        Advance = Math.Max(2, (int)Math.Round(size.Width / 10));
        LineHeight = Math.Max(4, (int)Math.Ceiling(font.GetHeight(g)));
        cellWidth = Advance * 2 + 2;
    }

    public GlyphMask? Glyph(char ch)
    {
        if (ch == ' ') return null;
        if (glyphs.TryGetValue(ch, out var hit)) return hit;
        var mask = Render(ch);
        glyphs[ch] = mask;
        return mask;
    }

    private GlyphMask? Render(char ch)
    {
        var useFont = ch >= 0x2E80 && kanaFont != null ? kanaFont : font;
        int w = cellWidth, h = LineHeight + 2;
        using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            g.TextRenderingHint = TextRenderingHint.AntiAlias;
            g.DrawString(ch.ToString(), useFont, Brushes.White, 0, 0, StringFormat.GenericTypographic);
        }
        var mask = new GlyphMask { Width = w, Height = h, Alpha = new byte[w * h] };
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            unsafe
            {
                bool any = false;
                for (int y = 0; y < h; y++)
                {
                    byte* row = (byte*)data.Scan0 + y * data.Stride;
                    for (int x = 0; x < w; x++)
                    {
                        byte a = row[x * 4 + 3];
                        mask.Alpha[y * w + x] = a;
                        if (a != 0) any = true;
                    }
                }
                if (!any) return null;
            }
        }
        finally
        {
            bmp.UnlockBits(data);
        }
        return mask;
    }
}
