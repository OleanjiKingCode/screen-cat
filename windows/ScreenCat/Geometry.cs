using System;
using System.Collections.Generic;

namespace ScreenCat;

/// A point or a direction. Behaviour maths runs in doubles, like CGFloat on the Mac.
public struct Vec
{
    public double X;
    public double Y;

    public Vec(double x, double y) { X = x; Y = y; }

    public static readonly Vec Zero = new(0, 0);

    public static Vec operator +(Vec a, Vec b) => new(a.X + b.X, a.Y + b.Y);
    public static Vec operator -(Vec a, Vec b) => new(a.X - b.X, a.Y - b.Y);
    public static Vec operator *(Vec a, double s) => new(a.X * s, a.Y * s);

    public double Length => Math.Sqrt(X * X + Y * Y);

    public static double Hypot(double x, double y) => Math.Sqrt(x * x + y * y);

    public override string ToString() => $"{X:0},{Y:0}";
}

/// An axis-aligned rectangle. It has no built-in "up": the behaviour code uses
/// it with y pointing up (like AppKit), the window code with y pointing down.
public struct RectD
{
    public double X;
    public double Y;
    public double Width;
    public double Height;

    public RectD(double x, double y, double w, double h) { X = x; Y = y; Width = w; Height = h; }

    public static readonly RectD Zero = new(0, 0, 0, 0);
    public static readonly RectD Null = new(double.PositiveInfinity, double.PositiveInfinity, 0, 0);

    public bool IsNull => double.IsInfinity(X) || double.IsInfinity(Y);
    public bool IsEmpty => IsNull || Width <= 0 || Height <= 0;

    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
    public double MidX => X + Width / 2;
    public double MidY => Y + Height / 2;

    public static RectD FromEdges(double minX, double minY, double maxX, double maxY)
        => new(minX, minY, maxX - minX, maxY - minY);

    public bool Contains(Vec p) => p.X >= MinX && p.X < MaxX && p.Y >= MinY && p.Y < MaxY;
    public bool Contains(double x, double y) => Contains(new Vec(x, y));

    public bool Intersects(RectD o) => !IsNull && !o.IsNull && MinX < o.MaxX && o.MinX < MaxX && MinY < o.MaxY && o.MinY < MaxY;

    public RectD Inset(double dx, double dy) => new(X + dx, Y + dy, Width - dx * 2, Height - dy * 2);
    public RectD Offset(double dx, double dy) => new(X + dx, Y + dy, Width, Height);

    public RectD Union(RectD o)
    {
        if (IsNull) return o;
        if (o.IsNull) return this;
        return FromEdges(Math.Min(MinX, o.MinX), Math.Min(MinY, o.MinY), Math.Max(MaxX, o.MaxX), Math.Max(MaxY, o.MaxY));
    }

    public RectD Intersection(RectD o)
    {
        if (IsNull || o.IsNull) return Null;
        double x0 = Math.Max(MinX, o.MinX), y0 = Math.Max(MinY, o.MinY);
        double x1 = Math.Min(MaxX, o.MaxX), y1 = Math.Min(MaxY, o.MaxY);
        if (x1 < x0 || y1 < y0) return Null;
        return FromEdges(x0, y0, x1, y1);
    }

    /// The bounding box of this rectangle after `t`.
    public RectD Apply(Affine t)
    {
        if (IsNull) return this;
        var a = t.Apply(MinX, MinY);
        var b = t.Apply(MaxX, MaxY);
        var c = t.Apply(MinX, MaxY);
        var d = t.Apply(MaxX, MinY);
        double x0 = Math.Min(Math.Min(a.X, b.X), Math.Min(c.X, d.X));
        double x1 = Math.Max(Math.Max(a.X, b.X), Math.Max(c.X, d.X));
        double y0 = Math.Min(Math.Min(a.Y, b.Y), Math.Min(c.Y, d.Y));
        double y1 = Math.Max(Math.Max(a.Y, b.Y), Math.Max(c.Y, d.Y));
        return FromEdges(x0, y0, x1, y1);
    }

    public override string ToString() => $"({X:0},{Y:0} {Width:0}x{Height:0})";
}

/// A 2D affine transform with the same layout as CGAffineTransform:
/// x' = A*x + C*y + E, y' = B*x + D*y + F.
public struct Affine
{
    public double A, B, C, D, E, F;

    public Affine(double a, double b, double c, double d, double e, double f)
    {
        A = a; B = b; C = c; D = d; E = e; F = f;
    }

    public static readonly Affine Identity = new(1, 0, 0, 1, 0, 0);

    public static Affine Translation(double x, double y) => new(1, 0, 0, 1, x, y);
    public static Affine Scaling(double sx, double sy) => new(sx, 0, 0, sy, 0, 0);

    public Vec Apply(double x, double y) => new(A * x + C * y + E, B * x + D * y + F);
    public Vec Apply(Vec p) => Apply(p.X, p.Y);

    /// `inner` runs first, then this. Same as CGContext.concatenate(inner).
    public Affine Then(Affine inner)
    {
        return new Affine(
            A * inner.A + C * inner.B,
            B * inner.A + D * inner.B,
            A * inner.C + C * inner.D,
            B * inner.C + D * inner.D,
            A * inner.E + C * inner.F + E,
            B * inner.E + D * inner.F + F);
    }

    public Affine Inverted()
    {
        double det = A * D - B * C;
        if (Math.Abs(det) < 1e-12) return Identity;
        double ia = D / det, ib = -B / det, ic = -C / det, id = A / det;
        return new Affine(ia, ib, ic, id, -(ia * E + ic * F), -(ib * E + id * F));
    }

    /// How much this scales lengths, ignoring rotation and flips.
    public double ScaleFactor => Math.Sqrt(Math.Abs(A * D - B * C));
}

/// A colour with straight (not premultiplied) alpha, 0 to 1 per channel.
public struct Rgba
{
    public double R, G, B, A;

    public Rgba(double r, double g, double b, double a = 1) { R = r; G = g; B = b; A = a; }

    public static Rgba Hex(uint v) => new(((v >> 16) & 0xFF) / 255.0, ((v >> 8) & 0xFF) / 255.0, (v & 0xFF) / 255.0);
    public static Rgba White(double w, double a = 1) => new(w, w, w, a);

    public static readonly Rgba Black = new(0, 0, 0);
    public static readonly Rgba WhiteColor = new(1, 1, 1);

    public Rgba WithAlpha(double a) => new(R, G, B, a);

    /// Same as NSColor.blended(withFraction:of:).
    public Rgba Blend(double t, Rgba other) => new(
        R + (other.R - R) * t, G + (other.G - G) * t, B + (other.B - B) * t, A + (other.A - A) * t);

    public uint Rgb24 => ((uint)Math.Round(Clamp01(R) * 255) << 16) | ((uint)Math.Round(Clamp01(G) * 255) << 8) | (uint)Math.Round(Clamp01(B) * 255);

    /// The colour as a GDI+ colour, with an extra alpha multiplier.
    public System.Drawing.Color ToColor(double alpha = 1)
    {
        int a = (int)Math.Round(Clamp01(A * alpha) * 255);
        return System.Drawing.Color.FromArgb(a, (int)Math.Round(Clamp01(R) * 255),
            (int)Math.Round(Clamp01(G) * 255), (int)Math.Round(Clamp01(B) * 255));
    }

    public static double Clamp01(double v) => v < 0 ? 0 : v > 1 ? 1 : v;

    /// "#RRGGBB" or "#RRGGBBAA", like the Mac's NSColor(hex:).
    public static Rgba? FromHex(string? hex)
    {
        if (hex == null) return null;
        var s = hex.Trim();
        if (s.StartsWith("#")) s = s.Substring(1);
        if ((s.Length != 6 && s.Length != 8) || !uint.TryParse(s, System.Globalization.NumberStyles.HexNumber, null, out var v))
            return null;
        bool hasAlpha = s.Length == 8;
        double r = ((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0;
        double g = ((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0;
        double b = ((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0;
        double a = hasAlpha ? (v & 0xFF) / 255.0 : 1;
        return new Rgba(r, g, b, a);
    }
}

/// Random helpers shaped like Swift's `random(in:)`.
public static class Rng
{
    private static readonly Random R = new();

    /// A double in a...b.
    public static double Range(double a, double b) => a + (b - a) * R.NextDouble();

    /// An int in a..<b.
    public static int Int(int a, int bExclusive) => R.Next(a, bExclusive);

    /// An int in a...b.
    public static int IntIn(int a, int bInclusive) => R.Next(a, bInclusive + 1);

    public static bool Bool() => R.Next(2) == 0;

    public static double Unit() => R.NextDouble();

    public static uint Seed() => (uint)R.NextInt64(1, uint.MaxValue);

    public static T Pick<T>(IReadOnlyList<T> list) => list[R.Next(list.Count)];

    public static void Shuffle<T>(IList<T> list)
    {
        for (int i = list.Count - 1; i > 0; i--)
        {
            int j = R.Next(i + 1);
            (list[i], list[j]) = (list[j], list[i]);
        }
    }
}

/// Small deterministic random source. Seeded from the breach plus a time
/// bucket, so the glitch flickers a few times a second but each frame is stable.
public struct GlitchRandom
{
    private ulong state;

    public GlitchRandom(uint seed)
    {
        // SplitMix64 scramble, so neighbouring seeds (column 1, column 2, ...)
        // start far apart instead of drawing near-identical first numbers.
        unchecked
        {
            ulong z = seed + 0x9E3779B97F4A7C15UL;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            state = z ^ (z >> 31);
        }
    }

    public double Unit()
    {
        unchecked { state = state * 6364136223846793005UL + 1442695040888963407UL; }
        return ((state >> 33) & 0xFFFFFF) / (double)0xFFFFFF;
    }

    public double Range(double a, double b) => a + (b - a) * Unit();
}

/// Swift-style seed arithmetic that wraps instead of throwing.
public static class Seeds
{
    public static uint Of(double v) => v <= 0 ? 0u : v >= uint.MaxValue ? uint.MaxValue : (uint)v;
    public static uint Add(uint a, uint b) => unchecked(a + b);
    public static uint Mul(uint a, uint b) => unchecked(a * b);
}
