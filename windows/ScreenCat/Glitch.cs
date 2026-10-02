using System;
using System.Collections.Generic;
using System.Linq;

namespace ScreenCat;

// Crawler mode's "hack" effects. Everything here is paint on the cat's own
// overlay: the app underneath is never touched, it only looks broken for a few
// seconds and then "reboots".
//
// All of it is drawn in the cat's surface-local space (y up). `u` is the
// screen's scale (1 at 100%), applied to the fixed sizes that the Mac code
// gives in points.

/// The look of one breach. Picked at random each time, so a long crawl does
/// not repeat itself.
public enum GlitchStyle
{
    /// Cracks, RGB slices, scrolling hacker code, "SYSTEM BREACHED".
    Breach,
    /// Columns of falling characters.
    Matrix,
    /// A crash screen: ":(", "SYSTEM HALTED" and a counting percentage.
    BlueScreen,
    /// TV static, colour bars and "NO SIGNAL".
    NoSignal,
    /// The window melts down in drips of colour.
    Melt,
}

/// One window the cat has broken, in the same coordinates as the cat.
public struct Breach
{
    public RectD Rect;
    /// Where the zap landed. The cracks spread out from here.
    public Vec Touch;
    public uint Seed;
    public GlitchStyle Style;
    /// Index into `Glitch.Accents`.
    public int AccentIndex;
    public double Age;
    public const double Duration = 4.2;

    public bool Finished => Age >= Duration;
    public Rgba Accent => Glitch.Accents[AccentIndex % Glitch.Accents.Length];

    /// A breach in a random style and colour.
    public static Breach Random(RectD rect, Vec touch) => new()
    {
        Rect = rect,
        Touch = touch,
        Seed = Rng.Seed(),
        Style = (GlitchStyle)Rng.Int(0, 5),
        AccentIndex = Rng.Int(0, Glitch.Accents.Length),
    };
}

/// Anything that has breaches and a zap to paint: both crawl routines.
public interface IBreachSource
{
    IReadOnlyList<Breach> Breaches { get; }
    Zap? Zap { get; }
    /// The glow while the cat powers up, if it is.
    Aura? Aura { get; }
}

/// Rings pulsing out from the cat while it grows.
public readonly record struct Aura(Vec Center, double Size, double Progress, double Age, int AccentIndex)
{
    public RectD Bounds => new(Center.X - Size * 2, Center.Y - Size * 2, Size * 4, Size * 4);
}

/// The bolt from the cat's head to the window, while it is "hacking" it.
public readonly record struct Zap(Vec From, Vec To, double Age, int AccentIndex)
{
    public Rgba Accent => Glitch.Accents[AccentIndex % Glitch.Accents.Length];

    public RectD Bounds => RectD.FromEdges(Math.Min(From.X, To.X), Math.Min(From.Y, To.Y),
        Math.Max(From.X, To.X), Math.Max(From.Y, To.Y)).Inset(-24, -24);
}

public static class Glitch
{
    /// The colours a breach can come in.
    public static readonly Rgba[] Accents =
    {
        new(0.22, 1.0, 0.48),  // green
        new(0.2, 0.9, 1.0),    // cyan
        new(1.0, 0.3, 0.85),   // magenta
        new(1.0, 0.75, 0.2),   // amber
        new(1.0, 0.27, 0.3),   // red
        new(0.7, 0.5, 1.0),    // purple
    };

    private static readonly Rgba AlarmRed = new(1.0, 0.23, 0.36);

    /// Three rings expanding and fading, with a flicker of sparks.
    public static void DrawAura(Aura a, Canvas ctx, double u)
    {
        var accent = Accents[a.AccentIndex % Accents.Length];
        ctx.Save();
        for (int k = 0; k < 3; k++)
        {
            double phase = (a.Age * 1.6 + k / 3.0) % 1;
            double radius = a.Size * (0.4 + phase * 1.5);
            var ring = new PathD();
            ring.AddOval(new RectD(a.Center.X - radius, a.Center.Y - radius, radius * 2, radius * 2));
            ctx.Stroke(ring, accent.WithAlpha((1 - phase) * 0.8), 3 * u);
        }
        var sparks = new GlitchRandom(Seeds.Add(Seeds.Of(a.Age / 0.06), 99));
        for (int i = 0; i < 14; i++)
        {
            double angle = sparks.Range(0, Math.PI * 2), d = a.Size * sparks.Range(0.5, 1.6);
            ctx.FillRect(new RectD(a.Center.X + Math.Cos(angle) * d - 2 * u, a.Center.Y + Math.Sin(angle) * d - 2 * u, 4 * u, 4 * u), accent);
        }
        ctx.Restore();
    }

    /// Fictional, harmless "hacker" lines for the scrolling code.
    private static readonly string[] FakeCode =
    {
        "> connecting to 185.220.101.47:22 ...",
        "$ nmap -sS -p- 10.0.0.0/24 --open",
        "PORT     STATE SERVICE",
        "22/tcp   open  ssh",
        "443/tcp  open  https",
        "$ ssh -i id_rsa root@10.0.0.14",
        "Permission denied (publickey).",
        "$ hydra -l admin -P rockyou.txt ssh://10.0.0.14",
        "[22][ssh] login: admin  password: ********",
        "bypassing firewall ... rule 0x1F dropped",
        "decrypt(0x3F2A9C) -> ok",
        "dumping /etc/shadow ...",
        "root:$6$Zx9Q...:19622:0:99999:7:::",
        "privilege escalation: CVE-20XX-0000 ... ok",
        "uid=0(root) gid=0(root)",
        "$ curl -s http://10.0.0.14/admin.php?id=1' OR '1'='1",
        "injecting payload stage2.bin (48 KB)",
        "spawning reverse shell -> 185.220.101.47:4444",
        "keylogger attached to pid 4127",
        "exfiltrating /Users/*/Documents (2.3 GB)",
        "wiping logs: /var/log/*.log",
        "kernel: segfault at 0x00007ffd in libsystem",
        "ERROR 0xDEAD: process not responding",
        "rerouting traffic through 7 proxies",
        "hash cracked: 5f4dcc3b5aa765d61d8327deb882cf99",
        "AES-256 key found: 9b2e...c41f",
        "mounting /dev/disk2s1 /mnt/target",
        "GET /api/v1/users  200 OK",
        "0101 1100 0011 1010 1110",
        "establishing persistence: launchd.plist",
    };

    /// Paints a breach in its style. Every style fades in, darkens the window,
    /// does its thing, then shows "REBOOTING..." and fades back to the real app.
    public static void DrawBreach(Breach b, Canvas ctx, double u)
    {
        double fadeIn = Math.Min(1, b.Age / 0.25);
        double fadeOut = Math.Min(1, Math.Max(0, (Breach.Duration - b.Age) / 0.6));
        double envelope = fadeIn * fadeOut;
        if (envelope <= 0.01) return;
        var r = b.Rect;
        var flicker = new GlitchRandom(Seeds.Add(b.Seed, Seeds.Of(b.Age / 0.07)));

        ctx.Save();
        ctx.SetAlpha(envelope);
        ctx.ClipTo(r);

        // Falling code only reads against near black.
        ctx.FillRect(r, Rgba.White(0, b.Style == GlitchStyle.Matrix ? 0.88 : 0.55));

        switch (b.Style)
        {
            case GlitchStyle.Breach:
                DrawScanlines(r, ctx, u);
                DrawSlices(r, ref flicker, ctx, u);
                DrawCracks(b, ctx, u);
                DrawCode(b, r, ctx, u);
                DrawBanner(b, r, ref flicker, ctx, new[] { "SYSTEM BREACHED", "HACKED!" }, AlarmRed, u);
                break;
            case GlitchStyle.Matrix:
                DrawMatrix(b, r, ctx, u);
                DrawBanner(b, r, ref flicker, ctx, new[] { "ACCESS GRANTED", "ACCESS OK" }, b.Accent, u);
                break;
            case GlitchStyle.BlueScreen:
                DrawBlueScreen(b, r, ctx, u);
                DrawBanner(b, r, ref flicker, ctx, Array.Empty<string>(), b.Accent, u);
                break;
            case GlitchStyle.NoSignal:
                DrawNoSignal(b, r, ref flicker, ctx, u);
                DrawBanner(b, r, ref flicker, ctx, new[] { "NO SIGNAL", "NO SIGNAL" }, b.Accent, u);
                break;
            case GlitchStyle.Melt:
                DrawMelt(b, r, ctx, u);
                DrawScanlines(r, ctx, u);
                DrawBanner(b, r, ref flicker, ctx, new[] { "MELTDOWN", "MELT" }, b.Accent, u);
                break;
        }

        // A flickering border, like a target lock.
        var border = new PathD();
        border.AddRect(r.Inset(1.5 * u, 1.5 * u));
        ctx.Stroke(border, b.Accent.WithAlpha(flicker.Range(0.5, 1)), 3 * u, miter: true);
        ctx.Restore();
    }

    private static void DrawScanlines(RectD r, Canvas ctx, double u)
    {
        var c = Rgba.White(0, 0.3);
        for (double y = r.MinY; y < r.MaxY; y += 4 * u)
        {
            ctx.FillRect(new RectD(r.MinX, y, r.Width, 1 * u), c);
        }
    }

    /// Sliced, shifted bars in the two halves of an RGB split.
    private static void DrawSlices(RectD r, ref GlitchRandom flicker, Canvas ctx, double u)
    {
        Rgba[] tints = { new(1, 0, 0.6, 0.28), new(0, 0.9, 1, 0.28), Rgba.White(1, 0.12) };
        for (int i = 0; i < 10; i++)
        {
            double h = flicker.Range(3, 24) * u;
            ctx.FillRect(new RectD(r.MinX + flicker.Range(-50, 50) * u, flicker.Range(r.MinY, r.MaxY - h),
                r.Width * flicker.Range(0.3, 1.05), h), tints[i % tints.Length]);
        }
    }

    /// Jagged cracks from the touch point. Their shape comes from the seed alone,
    /// so they grow without wobbling.
    private static void DrawCracks(Breach b, Canvas ctx, double u)
    {
        double grow = Math.Min(1, Math.Max(0, (b.Age - 0.15) / 0.9));
        double eased = 1 - Math.Pow(1 - grow, 3);
        if (eased <= 0) return;
        double reach = Math.Max(b.Rect.Width, b.Rect.Height) * 0.55 * eased;
        var shape = new GlitchRandom(b.Seed);
        double baseAngle = shape.Range(0, Math.PI * 2);
        const int count = 7;
        for (int k = 0; k < count; k++)
        {
            var path = new PathD();
            path.MoveTo(b.Touch);
            double angle = baseAngle + k * Math.PI * 2 / count + shape.Range(-0.3, 0.3);
            var point = b.Touch;
            const int segments = 7;
            for (int s = 0; s < segments; s++)
            {
                angle += shape.Range(-0.5, 0.5);
                double step = reach / segments * shape.Range(0.6, 1.3);
                point = new Vec(point.X + Math.Cos(angle) * step, point.Y + Math.Sin(angle) * step);
                path.LineTo(point);
            }
            ctx.Stroke(path, Rgba.White(0, 0.7), 3.5 * u, miter: true);
            ctx.Stroke(path, Rgba.White(1, 0.9), 1.2 * u, miter: true);
        }
    }

    /// Code scrolling up the left side, newest line at the bottom, typed out.
    private static void DrawCode(Breach b, RectD r, Canvas ctx, double u)
    {
        double lineHeight = 15 * u;
        int rows = (int)((r.Height - 20 * u) / lineHeight);
        if (rows <= 0 || b.Age <= 0.3) return;
        double typed = (b.Age - 0.3) * 11;
        int shown = Math.Min(rows, (int)typed + 1);
        int first = (int)(b.Seed % (uint)FakeCode.Length);
        for (int row = 0; row < shown; row++)
        {
            int index = (int)typed - row;
            string text = FakeCode[(first + Math.Max(0, index)) % FakeCode.Length];
            if (row == 0)
            {
                // The newest line types itself out, cursor and all.
                int chars = (int)((typed - Math.Floor(typed)) * text.Length);
                text = text.Substring(0, Math.Min(chars, text.Length)) + "_";
            }
            var colour = b.Accent.WithAlpha(row == 0 ? 1 : Math.Max(0.35, 0.95 - row * 0.03));
            ctx.DrawText(text, r.MinX + 14 * u, r.MinY + 10 * u + row * lineHeight, colour, 11 * u);
        }
    }

    private const string RainGlyphs = "01アイウエオカキクケコサシスセソタチツテト$#@*<>=+ABCDEFXYZ";

    /// Columns of falling characters, bright at the head and fading up the trail.
    private static void DrawMatrix(Breach b, RectD r, Canvas ctx, double u)
    {
        double colW = Math.Max(16 * u, r.Width / 60);
        double rowH = 18 * u;
        int cols = (int)(r.Width / colW);
        var columnRandom = new GlitchRandom(b.Seed);
        uint charTick = Seeds.Of(b.Age / 0.09);
        for (int c = 0; c < cols; c++)
        {
            double speed = columnRandom.Range(140, 420) * u;
            double start = columnRandom.Range(0, r.Height);
            int trail = (int)columnRandom.Range(5, 13);
            double span = r.Height + trail * rowH;
            double headY = r.MaxY - (b.Age * speed + start) % span;
            var chars = new GlitchRandom(Seeds.Add(Seeds.Add(b.Seed, Seeds.Mul((uint)c, 977)), charTick));
            double x = r.MinX + c * colW;
            for (int k = 0; k < trail; k++)
            {
                double y = headY + k * rowH;
                if (y <= r.MinY - rowH || y >= r.MaxY) continue;
                char ch = RainGlyphs[(int)(chars.Unit() * (RainGlyphs.Length - 1))];
                bool isHead = k == 0;
                var colour = isHead ? Rgba.WhiteColor : b.Accent;
                double alpha = isHead ? 1 : Math.Max(0.15, 1 - (double)k / trail);
                ctx.DrawText(ch.ToString(), x + 2 * u, y + 1 * u, colour.WithAlpha(alpha), 14 * u, bold: true);
            }
        }
    }

    /// A pixel-font crash screen that counts its way up to "100%".
    private static void DrawBlueScreen(Breach b, RectD r, Canvas ctx, double u)
    {
        ctx.FillRect(r, new Rgba(0.08, 0.33, 0.82));
        int percent = Math.Min(100, (int)(Math.Max(0, b.Age - 0.4) / 2.6 * 100));
        string[] lines = { "SYSTEM HALTED", "STOP CODE: 0XC000021A", $"DUMPING MEMORY {percent}%" };
        double widest = lines.Max(l => PixelFont.Width(l));
        double pixel = Math.Max(2 * u, Math.Min(6 * u, Math.Floor(r.Width * 0.8 / widest)));
        double left = r.MinX + Math.Max(12 * u, r.Width * 0.08);
        double y = r.MaxY - Math.Max(20 * u, r.Height * 0.18);
        double face = pixel * 3;
        y -= PixelFont.Height * face;
        PixelFont.Draw(":(", new Vec(left, y), face, Rgba.WhiteColor, ctx);
        y -= pixel * 6;
        foreach (var line in lines)
        {
            y -= PixelFont.Height * pixel + pixel * 3;
            if (y <= r.MinY + 6 * u || PixelFont.Width(line) * pixel >= r.Width - 12 * u) continue;
            PixelFont.Draw(line, new Vec(left, y), pixel, Rgba.WhiteColor, ctx);
        }
    }

    /// The seven colour bars, the ones macOS calls its system colours.
    public static readonly Rgba[] Bars =
    {
        Rgba.White(0.8),
        Rgba.Hex(0xFFCC00), // yellow
        Rgba.Hex(0x30B0C7), // teal
        Rgba.Hex(0x34C759), // green
        Rgba.Hex(0xFF2D55), // pink
        Rgba.Hex(0xFF3B30), // red
        Rgba.Hex(0x007AFF), // blue
    };

    /// TV static with a band of colour bars and a rolling bright bar.
    private static void DrawNoSignal(Breach b, RectD r, ref GlitchRandom flicker, Canvas ctx, double u)
    {
        double block = Math.Max(10 * u, r.Width / 70);
        for (double y = r.MinY; y < r.MaxY; y += block)
        {
            for (double x = r.MinX; x < r.MaxX; x += block)
            {
                if (flicker.Unit() < 0.45)
                {
                    ctx.FillRect(new RectD(x, y, block, block), Rgba.White(flicker.Range(0.15, 0.9), 0.85));
                }
            }
        }
        var band = new RectD(r.MinX, r.MidY - r.Height * 0.15, r.Width, r.Height * 0.3);
        double barW = band.Width / Bars.Length;
        double shift = flicker.Range(-12, 12) * u;
        for (int i = 0; i < Bars.Length; i++)
        {
            ctx.FillRect(new RectD(band.MinX + i * barW + shift, band.MinY, barW + 1, band.Height), Bars[i].WithAlpha(0.85));
        }
        double roll = r.MinY + (b.Age * r.Height * 0.6) % r.Height;
        ctx.FillRect(new RectD(r.MinX, roll, r.Width, Math.Max(8 * u, r.Height * 0.05)), Rgba.White(1, 0.18));
    }

    /// Drips of colour sliding down from the top edge, each at its own pace.
    private static void DrawMelt(Breach b, RectD r, Canvas ctx, double u)
    {
        double colW = Math.Max(8 * u, r.Width / 60);
        int cols = (int)Math.Ceiling(r.Width / colW);
        double progress = Math.Min(1, b.Age / (Breach.Duration - 1.2));
        double eased = 1 - Math.Pow(1 - progress, 2);
        var columns = new GlitchRandom(b.Seed);
        var dark = b.Accent.Blend(0.45, Rgba.Black);
        for (int c = 0; c < cols; c++)
        {
            double length = r.Height * eased * columns.Range(0.25, 1.05);
            double x = r.MinX + c * colW;
            ctx.FillRect(new RectD(x, r.MaxY - length, colW + 0.5, length), dark.WithAlpha(0.9));
            ctx.FillRect(new RectD(x, r.MaxY - length, colW + 0.5, Math.Min(length, colW * 0.6)), b.Accent);
            // A drop falling ahead of the drip now and then.
            if (columns.Unit() < 0.3)
            {
                double fall = (b.Age * 260 * u * columns.Range(0.6, 1.4)) % r.Height;
                ctx.FillRect(new RectD(x + colW * 0.25, r.MaxY - length - fall, colW * 0.5, colW * 0.8), b.Accent.WithAlpha(0.8));
            }
        }
    }

    /// The style's banner in the pixel font, then "REBOOTING..." before it clears.
    /// Empty `options` shows only the rebooting part.
    private static void DrawBanner(Breach b, RectD r, ref GlitchRandom flicker, Canvas ctx, string[] options, Rgba colour, double u)
    {
        bool rebooting = b.Age > Breach.Duration - 1.1;
        if (b.Age <= 0.6) return;
        if (!rebooting && options.Length == 0) return;
        // Blink on and off now and then, the way a warning does.
        if (!rebooting && flicker.Unit() < 0.12) return;
        // The long wording when it fits at the smallest pixel size, else a short one.
        var choices = rebooting ? new[] { "REBOOTING...", "REBOOT" } : options;
        string text = choices.FirstOrDefault(c => (PixelFont.Width(c) + 6) * 2 * u <= r.Width * 0.9) ?? choices[^1];
        var tint = rebooting ? b.Accent : colour;
        double widthPx = PixelFont.Width(text);
        double pixel = Math.Max(2 * u, Math.Min(5 * u, Math.Floor(r.Width * 0.6 / widthPx)));
        double w = widthPx * pixel, h = PixelFont.Height * pixel;
        var box = new RectD(r.MidX - w / 2 - pixel * 3, r.MidY - h / 2 - pixel * 3, w + pixel * 6, h + pixel * 6);
        ctx.FillRect(box, Rgba.White(0, 0.85));
        var frame = new PathD();
        frame.AddRect(box.Inset(pixel / 2, pixel / 2));
        ctx.Stroke(frame, tint, pixel, miter: true);
        PixelFont.Draw(text, new Vec(Math.Round(r.MidX - w / 2), Math.Round(r.MidY - h / 2)), pixel, tint, ctx);
    }

    /// A jittery bolt from the cat to the window it is hacking.
    public static void DrawZap(Zap z, Canvas ctx, double u)
    {
        var jitter = new GlitchRandom(Seeds.Add(Seeds.Of(z.Age / 0.05), 7));
        var path = new PathD();
        path.MoveTo(z.From);
        const int segments = 9;
        double dx = z.To.X - z.From.X, dy = z.To.Y - z.From.Y;
        double len = Math.Max(1, Vec.Hypot(dx, dy));
        double nx = -dy / len, ny = dx / len;
        for (int i = 1; i < segments; i++)
        {
            double t = (double)i / segments;
            double off = jitter.Range(-8, 8) * u;
            path.LineTo(new Vec(z.From.X + dx * t + nx * off, z.From.Y + dy * t + ny * off));
        }
        path.LineTo(z.To);
        ctx.Save();
        ctx.Stroke(path, z.Accent.WithAlpha(0.3), 7 * u);
        ctx.Stroke(path, z.Accent, 2 * u);
        // Sparks where it lands.
        for (int i = 0; i < 6; i++)
        {
            double a = jitter.Range(0, Math.PI * 2), d = jitter.Range(3, 14) * u;
            ctx.FillRect(new RectD(z.To.X + Math.Cos(a) * d - 1.5 * u, z.To.Y + Math.Sin(a) * d - 1.5 * u, 3 * u, 3 * u), z.Accent);
        }
        ctx.Restore();
    }
}
