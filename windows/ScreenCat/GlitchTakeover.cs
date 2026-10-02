using System;
using System.Collections.Generic;
using System.Linq;

namespace ScreenCat;

// The full-screen glitch for the idle crawl. Fifty named styles, each a stack
// of effect layers in its own colours. One style plays for about a minute,
// then the next takes over. It is all paint on the overlay; no app is touched.
//
// It renders at half resolution into a bitmap shown with nearest-neighbour
// scaling: chunky pixels suit a glitch, and it keeps a full-screen effect
// cheap enough to run for as long as you are away.
//
// Drawing happens in y-up logical pixels (physical pixels divided by the
// screen's scale), the same space the Mac draws in, so every size and
// position below is the Mac's own number.

public enum LayerKind
{
    Scanlines, Slices, StaticNoise, ColorBars, RollingBar, Tint, Tears,
    Matrix,
    HexWall, CodeWall, BlueScreen, Melt, PixelSort, Vhs, Blocks, Cracks,
    Popups, Radar, Tunnel, Warp, Scope, Heartbeat, GridFloor, Waves, Checker,
    Loading, Virus, DataStream,
    /// Big pixel-font words. "#" counts down from 10.
    BigText,
    /// A word tiled over the whole screen in scrolling rows.
    Tiled,
}

/// One effect. A style stacks a few of these.
public sealed record TakeoverLayer(LayerKind Kind, string Text = "", string[]? Options = null)
{
    public static readonly TakeoverLayer Scanlines = new(LayerKind.Scanlines);
    public static readonly TakeoverLayer Slices = new(LayerKind.Slices);
    public static readonly TakeoverLayer StaticNoise = new(LayerKind.StaticNoise);
    public static readonly TakeoverLayer ColorBars = new(LayerKind.ColorBars);
    public static readonly TakeoverLayer RollingBar = new(LayerKind.RollingBar);
    public static readonly TakeoverLayer Tint = new(LayerKind.Tint);
    public static readonly TakeoverLayer Tears = new(LayerKind.Tears);
    public static readonly TakeoverLayer HexWall = new(LayerKind.HexWall);
    public static readonly TakeoverLayer CodeWall = new(LayerKind.CodeWall);
    public static readonly TakeoverLayer BlueScreen = new(LayerKind.BlueScreen);
    public static readonly TakeoverLayer Melt = new(LayerKind.Melt);
    public static readonly TakeoverLayer PixelSort = new(LayerKind.PixelSort);
    public static readonly TakeoverLayer Vhs = new(LayerKind.Vhs);
    public static readonly TakeoverLayer Blocks = new(LayerKind.Blocks);
    public static readonly TakeoverLayer Cracks = new(LayerKind.Cracks);
    public static readonly TakeoverLayer Popups = new(LayerKind.Popups);
    public static readonly TakeoverLayer Radar = new(LayerKind.Radar);
    public static readonly TakeoverLayer Tunnel = new(LayerKind.Tunnel);
    public static readonly TakeoverLayer Warp = new(LayerKind.Warp);
    public static readonly TakeoverLayer Scope = new(LayerKind.Scope);
    public static readonly TakeoverLayer Heartbeat = new(LayerKind.Heartbeat);
    public static readonly TakeoverLayer GridFloor = new(LayerKind.GridFloor);
    public static readonly TakeoverLayer Waves = new(LayerKind.Waves);
    public static readonly TakeoverLayer Checker = new(LayerKind.Checker);
    public static readonly TakeoverLayer Loading = new(LayerKind.Loading);
    public static readonly TakeoverLayer Virus = new(LayerKind.Virus);
    public static readonly TakeoverLayer DataStream = new(LayerKind.DataStream);

    public static TakeoverLayer Matrix(string chars) => new(LayerKind.Matrix, chars);
    public static TakeoverLayer BigText(params string[] options) => new(LayerKind.BigText, "", options);
    public static TakeoverLayer Tiled(string word) => new(LayerKind.Tiled, word);
}

public sealed record GlitchRecipe(string Name, double Dim, TakeoverLayer[] Layers, Rgba[] Palette);

public static class Takeover
{
    private static Rgba H(uint v) => Rgba.Hex(v);

    // Danger colours only: blood red, terminal green, warning amber, white on
    // black. Each palette is [main, highlight, deep].
    private static readonly Rgba[] Toxic = { H(0x00FF41), H(0xB6FF3B), H(0x003B10) };
    private static readonly Rgba[] Ice = { H(0x00FF41), H(0xFFFFFF), H(0x0A2A0A) };
    private static readonly Rgba[] HotPink = { H(0xFF0033), H(0x00FF41), H(0x2A0008) };
    private static readonly Rgba[] Amber = { H(0xFFB000), H(0xFF3B00), H(0x2B1600) };
    private static readonly Rgba[] Blood = { H(0xFF0033), H(0xFF5C5C), H(0x4D0000) };
    private static readonly Rgba[] Synth = { H(0xFF0033), H(0xFFFFFF), H(0x00FF41) };
    private static readonly Rgba[] Ghost = { H(0xFFFFFF), H(0xFF0033), H(0x333333) };
    private static readonly Rgba[] Royal = { H(0xFF0033), H(0xFFB000), H(0x1A0000) };
    private static readonly Rgba[] Sunset = { H(0xFF3B00), H(0xFFB000), H(0x2B0A00) };
    private static readonly Rgba[] Void = { H(0xFF0033), H(0x8B0000), H(0x0D0000) };

    private const string Kana = "アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789";

    private static GlitchRecipe R(string name, double dim, Rgba[] palette, params TakeoverLayer[] layers) => new(name, dim, layers, palette);

    private static readonly TakeoverLayer Scanlines = TakeoverLayer.Scanlines;
    private static readonly TakeoverLayer Slices = TakeoverLayer.Slices;
    private static readonly TakeoverLayer StaticNoise = TakeoverLayer.StaticNoise;
    private static readonly TakeoverLayer ColorBars = TakeoverLayer.ColorBars;
    private static readonly TakeoverLayer RollingBar = TakeoverLayer.RollingBar;
    private static readonly TakeoverLayer Tint = TakeoverLayer.Tint;
    private static readonly TakeoverLayer Tears = TakeoverLayer.Tears;

    /// The fifty styles.
    public static readonly GlitchRecipe[] Recipes =
    {
        R("Green Breach", 0.7, Toxic, Scanlines, Slices, TakeoverLayer.CodeWall, TakeoverLayer.Cracks, TakeoverLayer.BigText("SYSTEM BREACHED", "BREACHED")),
        R("Digital Rain", 0.92, Toxic, TakeoverLayer.Matrix(Kana), RollingBar),
        R("Binary Rain", 0.92, Ice, TakeoverLayer.Matrix("01"), Scanlines),
        R("Blood Rain", 0.92, HotPink, TakeoverLayer.Matrix(Kana), Tint),
        R("Kernel Panic", 1, Ice, TakeoverLayer.BlueScreen),
        R("No Signal", 0.7, Ghost, StaticNoise, ColorBars, RollingBar, TakeoverLayer.BigText("NO SIGNAL")),
        R("Amber Static", 0.75, Amber, StaticNoise, Scanlines, Tint),
        R("Meltdown", 0.7, Blood, TakeoverLayer.Melt, Scanlines, TakeoverLayer.BigText("MELTDOWN")),
        R("Pixel Sort", 0.78, Synth, TakeoverLayer.PixelSort, Tears),
        R("VHS Rewind", 0.85, Sunset, ColorBars, TakeoverLayer.Waves, TakeoverLayer.Vhs, Tears, Scanlines),
        R("Corrupt Blocks", 0.72, Synth, TakeoverLayer.Blocks, Slices, Scanlines),
        R("Shatter", 0.78, Ghost, TakeoverLayer.Cracks, Tears, Tint),
        R("Error Storm", 0.62, Royal, TakeoverLayer.Popups, Scanlines),
        R("Radar Lock", 0.92, Toxic, TakeoverLayer.Radar, Scanlines),
        R("Tunnel", 0.88, HotPink, TakeoverLayer.Tunnel, Scanlines),
        R("Warp Speed", 0.96, Ice, TakeoverLayer.Warp),
        R("Oscilloscope", 0.92, Toxic, TakeoverLayer.Scope, Scanlines),
        R("Flatline", 0.94, Blood, TakeoverLayer.Heartbeat, Scanlines),
        R("Grid Runner", 0.96, Synth, TakeoverLayer.GridFloor, Scanlines),
        R("RGB Waves", 0.78, Synth, TakeoverLayer.Waves, Slices),
        R("Checker Panic", 0.72, Blood, TakeoverLayer.Checker, TakeoverLayer.BigText("ALERT")),
        R("Root Wall", 0.88, Royal, TakeoverLayer.Tiled("ROOT ACCESS"), Scanlines),
        R("Hacked Wall", 0.88, Toxic, TakeoverLayer.Tiled("HACKED"), Slices),
        R("Download Everything", 0.92, Amber, TakeoverLayer.HexWall, TakeoverLayer.Loading),
        R("Worm Outbreak", 0.85, Toxic, TakeoverLayer.Virus, TakeoverLayer.BigText("WORM SPREADING", "INFECTED")),
        R("Hex Dump", 0.94, Amber, TakeoverLayer.HexWall, RollingBar),
        R("Root Shell", 0.94, Toxic, TakeoverLayer.CodeWall, Scanlines),
        R("Data Stream", 0.92, Ice, TakeoverLayer.DataStream, Scanlines),
        R("Red Haze", 0.8, Void, TakeoverLayer.Waves, Tint, StaticNoise),
        R("Ghost Signal", 0.78, Ghost, StaticNoise, Tears, TakeoverLayer.BigText("WE ARE INSIDE", "INSIDE")),
        R("Red Alert", 0.82, Blood, RollingBar, TakeoverLayer.Checker, TakeoverLayer.BigText("SELF DESTRUCT IN #", "BOOM IN #")),
        R("Firewall Melt", 0.72, Sunset, TakeoverLayer.Melt, TakeoverLayer.Waves),
        R("Breach Tunnel", 0.92, Synth, TakeoverLayer.Tunnel, TakeoverLayer.Warp),
        R("Matrix Breach", 0.88, Toxic, TakeoverLayer.Matrix(Kana), TakeoverLayer.Cracks, TakeoverLayer.BigText("ACCESS GRANTED", "GRANTED")),
        R("Static Rain", 0.85, Ghost, StaticNoise, TakeoverLayer.Matrix("01")),
        R("Glitch Mosaic", 0.72, Royal, TakeoverLayer.Blocks, TakeoverLayer.Checker),
        R("Broken Display", 0.72, Ghost, Tears, ColorBars, Slices, TakeoverLayer.Cracks),
        R("Radar Rain", 0.92, Ice, TakeoverLayer.Radar, TakeoverLayer.Matrix("01")),
        R("Signal Intercept", 0.96, Synth, TakeoverLayer.GridFloor, TakeoverLayer.Scope),
        R("Access Denied", 0.75, Blood, TakeoverLayer.Tiled("ACCESS DENIED"), TakeoverLayer.Popups),
        R("Infection", 0.85, HotPink, TakeoverLayer.Virus, TakeoverLayer.CodeWall),
        R("Deep Sort", 0.75, Void, TakeoverLayer.PixelSort, RollingBar, Scanlines),
        R("Ransomware", 0.9, Amber, TakeoverLayer.Tiled("PAY 5 BTC"), TakeoverLayer.DataStream, TakeoverLayer.BigText("YOUR FILES ARE ENCRYPTED", "ENCRYPTED")),
        R("Heartbeat Grid", 0.94, Toxic, TakeoverLayer.GridFloor, TakeoverLayer.Heartbeat),
        R("Lockdown", 0.78, Ice, TakeoverLayer.Checker, Tint, TakeoverLayer.Cracks),
        R("Fatal Exception", 1, Blood, TakeoverLayer.BlueScreen, Tears),
        R("Signal Lost", 0.75, Amber, TakeoverLayer.Vhs, StaticNoise, TakeoverLayer.BigText("SIGNAL LOST", "LOST")),
        R("Laser Grid", 0.94, Blood, TakeoverLayer.GridFloor, TakeoverLayer.Radar),
        R("Hyperdrive", 0.96, Void, TakeoverLayer.Warp, TakeoverLayer.Tunnel),
        R("Total Chaos", 0.72, Synth, TakeoverLayer.Blocks, Slices, Tears, TakeoverLayer.Popups, TakeoverLayer.Cracks),
    };

    /// The "starting in" screen before Zero Day. `n` is the seconds left.
    public static GlitchRecipe CountdownRecipe(int n) =>
        R("Countdown", 0.6, Toxic, Scanlines, Tears, TakeoverLayer.BigText($"ZERO DAY IN {n}", $"{n}"));

    // Rendering ----------------------------------------------------------

    /// Paints one frame of `recipe`, `t` seconds in, filling `r` (y up).
    /// `pulse` (0 to 1) flashes the screen when the cat zaps something.
    public static void Render(GlitchRecipe recipe, RectD r, double t, uint seed, double pulse, Canvas ctx)
    {
        ctx.Save();
        ctx.SetSmooth(false);
        ctx.ClipTo(r);
        ctx.FillRect(r, Rgba.White(0, recipe.Dim));
        var pal = recipe.Palette;
        foreach (var layer in recipe.Layers)
        {
            var f = new GlitchRandom(Seeds.Add(seed, Seeds.Of(Math.Max(0, t) * 20)));
            switch (layer.Kind)
            {
                case LayerKind.Scanlines: DrawScanlines(r, ctx); break;
                case LayerKind.Slices: DrawSlices(r, pal, ref f, ctx); break;
                case LayerKind.StaticNoise: DrawStatic(r, pal, ref f, ctx); break;
                case LayerKind.ColorBars: DrawColorBars(r, ref f, ctx); break;
                case LayerKind.RollingBar: DrawRollingBar(r, t, ctx); break;
                case LayerKind.Tint: ctx.FillRect(r, pal[0].WithAlpha(0.14)); break;
                case LayerKind.Tears: DrawTears(r, pal, ref f, ctx); break;
                case LayerKind.Matrix: DrawMatrix(r, t, pal, seed, layer.Text, ctx); break;
                case LayerKind.HexWall: DrawHexWall(r, t, pal, seed, ctx); break;
                case LayerKind.CodeWall: DrawCodeWall(r, t, pal, seed, ctx); break;
                case LayerKind.BlueScreen: DrawBlueScreen(r, t, pal, ctx); break;
                case LayerKind.Melt: DrawMelt(r, t, pal, seed, ctx); break;
                case LayerKind.PixelSort: DrawPixelSort(r, t, pal, seed, ctx); break;
                case LayerKind.Vhs: DrawVhs(r, t, pal, ref f, ctx); break;
                case LayerKind.Blocks: DrawBlocks(r, pal, ref f, ctx); break;
                case LayerKind.Cracks: DrawCracks(r, t, seed, ctx); break;
                case LayerKind.Popups: DrawPopups(r, t, pal, seed, ctx); break;
                case LayerKind.Radar: DrawRadar(r, t, pal, seed, ctx); break;
                case LayerKind.Tunnel: DrawTunnel(r, t, pal, ctx); break;
                case LayerKind.Warp: DrawWarp(r, t, pal, seed, ctx); break;
                case LayerKind.Scope: DrawScope(r, t, pal, ctx); break;
                case LayerKind.Heartbeat: DrawHeartbeat(r, t, pal, ref f, ctx); break;
                case LayerKind.GridFloor: DrawGridFloor(r, t, pal, ctx); break;
                case LayerKind.Waves: DrawWaves(r, t, pal, ctx); break;
                case LayerKind.Checker: DrawChecker(r, t, pal, ref f, ctx); break;
                case LayerKind.Loading: DrawLoading(r, t, pal, ctx); break;
                case LayerKind.Virus: DrawVirus(r, t, pal, seed, ref f, ctx); break;
                case LayerKind.DataStream: DrawDataStream(r, t, pal, seed, ctx); break;
                case LayerKind.BigText: DrawBigText(r, t, pal, layer.Options ?? Array.Empty<string>(), ref f, ctx); break;
                case LayerKind.Tiled: DrawTiled(r, t, pal, layer.Text, ctx); break;
            }
        }
        // Flashes are alarm red, with now and then a white one.
        if (pulse > 0.01)
        {
            var flash = seed % 4 == 0 ? Rgba.WhiteColor : new Rgba(1, 0, 0.2);
            ctx.FillRect(r, flash.WithAlpha(0.4 * pulse));
        }
        ctx.Restore();
    }

    private static void Stroke(PathD path, Rgba colour, double width, Canvas ctx, bool glow = false)
    {
        if (glow) ctx.Stroke(path, colour.WithAlpha(0.25), width * 4);
        ctx.Stroke(path, colour, width);
    }

    private static void DrawScanlines(RectD r, Canvas ctx)
    {
        var c = Rgba.White(0, 0.35);
        for (double y = r.MinY; y < r.MaxY; y += 6) ctx.FillRect(new RectD(r.MinX, y, r.Width, 2), c);
    }

    private static void DrawSlices(RectD r, Rgba[] pal, ref GlitchRandom f, Canvas ctx)
    {
        for (int i = 0; i < 16; i++)
        {
            double h = f.Range(4, 40);
            ctx.FillRect(new RectD(r.MinX + f.Range(-80, 80), f.Range(r.MinY, r.MaxY - h), r.Width * f.Range(0.3, 1.1), h),
                pal[i % pal.Length].WithAlpha(0.3));
        }
    }

    private static void DrawStatic(RectD r, Rgba[] pal, ref GlitchRandom f, Canvas ctx)
    {
        double block = Math.Max(10, r.Width / 90);
        for (double y = r.MinY; y < r.MaxY; y += block)
        {
            for (double x = r.MinX; x < r.MaxX; x += block)
            {
                double roll = f.Unit();
                if (roll < 0.4)
                {
                    ctx.FillRect(new RectD(x, y, block, block), Rgba.White(f.Range(0.1, 0.95), 0.85));
                }
                else if (roll < 0.46)
                {
                    ctx.FillRect(new RectD(x, y, block, block), pal[(int)(f.Unit() * 2.99)].WithAlpha(0.8));
                }
            }
        }
    }

    private static readonly Rgba[] TakeoverBars =
    {
        Rgba.White(0.85), H(0xFF0033), Rgba.Black, H(0x00FF41), H(0xFFB000), H(0x8B0000), Rgba.Black,
    };

    private static void DrawColorBars(RectD r, ref GlitchRandom f, Canvas ctx)
    {
        var bars = TakeoverBars;
        var band = new RectD(r.MinX, r.MidY - r.Height * 0.18, r.Width, r.Height * 0.36);
        double w = band.Width / bars.Length;
        double shift = f.Range(-20, 20);
        for (int i = 0; i < bars.Length; i++)
        {
            ctx.FillRect(new RectD(band.MinX + i * w + shift, band.MinY, w + 1, band.Height), bars[i].WithAlpha(0.85));
        }
    }

    private static void DrawRollingBar(RectD r, double t, Canvas ctx)
    {
        double y = r.MinY + (t * r.Height * 0.35) % r.Height;
        ctx.FillRect(new RectD(r.MinX, y, r.Width, Math.Max(12, r.Height * 0.06)), Rgba.White(1, 0.16));
    }

    private static void DrawTears(RectD r, Rgba[] pal, ref GlitchRandom f, Canvas ctx)
    {
        for (int i = 0; i < 28; i++)
        {
            double y = f.Range(r.MinY, r.MaxY);
            double x = r.MinX + f.Range(-40, r.Width * 0.5);
            var colour = i % 3 == 0 ? Rgba.WhiteColor : pal[i % pal.Length];
            double a = f.Range(0.35, 0.8);
            ctx.FillRect(new RectD(x, y, r.Width * f.Range(0.2, 0.9), f.Range(1, 4)), colour.WithAlpha(a));
        }
    }

    private static void DrawMatrix(RectD r, double t, Rgba[] pal, uint seed, string chars, Canvas ctx)
    {
        double colW = Math.Max(18, r.Width / 80);
        const double rowH = 20;
        var columns = new GlitchRandom(seed);
        uint tick = Seeds.Of(t / 0.1);
        int cols = (int)(r.Width / colW);
        for (int c = 0; c < cols; c++)
        {
            double speed = columns.Range(120, 420);
            double start = columns.Range(0, r.Height);
            int trail = (int)columns.Range(8, 22);
            double span = r.Height + trail * rowH;
            double head = r.MaxY - (t * speed + start) % span;
            var glyphs = new GlitchRandom(Seeds.Add(Seeds.Add(seed, Seeds.Mul((uint)c, 977)), tick));
            double x = r.MinX + c * colW;
            for (int k = 0; k < trail; k++)
            {
                double y = head + k * rowH;
                if (y <= r.MinY - rowH || y >= r.MaxY) { glyphs.Unit(); continue; }
                char ch = chars[(int)(glyphs.Unit() * (chars.Length - 1))];
                var colour = k == 0 ? Rgba.WhiteColor : pal[k % 7 == 3 ? 1 : 0];
                double alpha = k == 0 ? 1 : Math.Max(0.12, 1 - (double)k / trail);
                ctx.DrawText(ch.ToString(), x + 2, y + 1, colour.WithAlpha(alpha), 15, bold: true);
            }
        }
    }

    private static void DrawHexWall(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        const double lineH = 16;
        int scroll = (int)(t * 7);
        int rows = (int)(r.Height / lineH) + 1;
        int highlight = (scroll / 5) % Math.Max(1, rows);
        var sb = new System.Text.StringBuilder(96);
        for (int row = 0; row < rows; row++)
        {
            var g = new GlitchRandom(Seeds.Mul(Seeds.Add(seed, (uint)(row + scroll)), 131));
            sb.Clear();
            sb.Append(((row + scroll) * 16).ToString("X8")).Append("  ");
            for (int i = 0; i < 16; i++) sb.Append(((int)(g.Unit() * 255)).ToString("X2")).Append(' ');
            sb.Append(' ');
            for (int i = 0; i < 12; i++) sb.Append((char)(33 + (int)(g.Unit() * 90)));
            string line = sb.ToString();
            var colour = row == highlight ? pal[1] : pal[0].WithAlpha(0.55 + 0.4 * g.Unit());
            for (double x = r.MinX + 12; x < r.MaxX; x += 560)
            {
                ctx.DrawText(line, x, r.MaxY - (row + 1) * lineH, colour, 12);
            }
        }
    }

    private static readonly string[] WallCode =
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

    private static void DrawCodeWall(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        const double lineH = 16;
        const double colW = 420;
        int columns = Math.Max(1, (int)(r.Width / colW));
        int rows = (int)(r.Height / lineH);
        double typed = t * 9;
        for (int c = 0; c < columns; c++)
        {
            int offset = (int)(seed % 97) + c * 7;
            for (int row = 0; row < rows; row++)
            {
                int index = (int)typed - row + offset + c * 3;
                string text = WallCode[((index % WallCode.Length) + WallCode.Length) % WallCode.Length];
                if (row == 0)
                {
                    int n = (int)((typed - Math.Floor(typed)) * text.Length);
                    text = text.Substring(0, Math.Min(n, text.Length)) + "_";
                }
                var colour = row == 0 ? pal[1] : pal[0].WithAlpha(Math.Max(0.3, 1 - (double)row / rows));
                ctx.DrawText(text, r.MinX + 16 + c * colW, r.MinY + 12 + row * lineH, colour, 12);
            }
        }
    }

    /// Pixel-font text, fitted to `maxWidth`. Returns the pixel size used.
    private static double PixelText(string text, Vec centre, double maxWidth, double maxPixel, Rgba colour, Canvas ctx, bool box = false)
    {
        double w = PixelFont.Width(text);
        double p = Math.Max(2, Math.Min(maxPixel, Math.Floor(maxWidth / Math.Max(1, w))));
        double width = w * p, height = PixelFont.Height * p;
        var origin = new Vec(Math.Round(centre.X - width / 2), Math.Round(centre.Y - height / 2));
        if (box)
        {
            var frame = new RectD(origin.X - p * 3, origin.Y - p * 3, width + p * 6, height + p * 6);
            ctx.FillRect(frame, Rgba.White(0, 0.85));
            var path = new PathD();
            path.AddRect(frame.Inset(p / 2, p / 2));
            ctx.Stroke(path, colour, p, miter: true);
        }
        PixelFont.Draw(text, origin, p, colour, ctx);
        return p;
    }

    private static void DrawBlueScreen(RectD r, double t, Rgba[] pal, Canvas ctx)
    {
        ctx.FillRect(r, pal[2].Blend(0.15, Rgba.Black));
        int percent = Math.Min(100, (int)(t * 1.7));
        string[] lines = { "YOUR SYSTEM HAS BEEN COMPROMISED", "KERNEL PANIC: NOT SYNCING", "STOP CODE: 0XC000021A", $"UPLOADING MEMORY DUMP {percent}%" };
        double widest = lines.Max(l => PixelFont.Width(l));
        double p = Math.Max(2, Math.Min(7, Math.Floor(r.Width * 0.75 / widest)));
        double left = r.MinX + r.Width * 0.1;
        double y = r.MaxY - r.Height * 0.2;
        y -= PixelFont.Height * p * 3;
        PixelFont.Draw(":(", new Vec(left, y), p * 3, Rgba.WhiteColor, ctx);
        y -= p * 8;
        foreach (var line in lines)
        {
            y -= PixelFont.Height * p + p * 4;
            PixelFont.Draw(line, new Vec(left, y), p, Rgba.WhiteColor, ctx);
        }
    }

    private static void DrawMelt(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        double colW = Math.Max(10, r.Width / 80);
        double phase = (t / 14) % 1;
        double eased = 1 - Math.Pow(1 - phase, 2);
        var cols = new GlitchRandom(seed);
        var dark = pal[2];
        int count = (int)Math.Ceiling(r.Width / colW);
        for (int c = 0; c < count; c++)
        {
            double length = r.Height * eased * cols.Range(0.3, 1.1);
            double x = r.MinX + c * colW;
            ctx.FillRect(new RectD(x, r.MaxY - length, colW + 0.5, length), dark.WithAlpha(0.9));
            ctx.FillRect(new RectD(x, r.MaxY - length, colW + 0.5, Math.Min(length, colW)), pal[0]);
            if (cols.Unit() < 0.35)
            {
                double fall = (t * 300 * cols.Range(0.6, 1.4)) % r.Height;
                ctx.FillRect(new RectD(x + colW * 0.25, r.MaxY - length - fall, colW * 0.5, colW), pal[1]);
            }
        }
    }

    private static void DrawPixelSort(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        double colW = Math.Max(6, r.Width / 140);
        var cols = new GlitchRandom(seed);
        int count = (int)(r.Width / colW);
        for (int c = 0; c < count; c++)
        {
            double x = r.MinX + c * colW;
            double baseY = cols.Range(r.MinY, r.MaxY);
            double speed = cols.Range(0.5, 2.5), phase = cols.Range(0, 6.28);
            double h = r.Height * (0.15 + 0.35 * (0.5 + 0.5 * Math.Sin(t * speed + phase)));
            var colour = pal[(int)(cols.Unit() * 2.99)];
            for (int s = 0; s < 5; s++)
            {
                ctx.FillRect(new RectD(x, baseY - s * h / 5, colW, h / 5), colour.WithAlpha(0.85 - s * 0.16));
            }
        }
    }

    private static void DrawVhs(RectD r, double t, Rgba[] pal, ref GlitchRandom f, Canvas ctx)
    {
        double bandH = r.Height * 0.12;
        double bandY = r.MaxY - (t * r.Height * 0.25) % (r.Height + bandH);
        for (double y = bandY; y < bandY + bandH; y += 5)
        {
            double w = f.Range(0.3, 1);
            ctx.FillRect(new RectD(r.MinX + f.Range(-30, 30), y, r.Width, 3), Rgba.White(w, 0.6));
        }
        int secs = (int)t % 60, mins = ((int)t / 60) % 60;
        PixelFont.Draw("PLAY", new Vec(r.MinX + 40, r.MaxY - 70), 5, Rgba.WhiteColor, ctx);
        PixelFont.Draw($"00:{mins:00}:{secs:00}", new Vec(r.MinX + 40, r.MinY + 40), 5, pal[0], ctx);
    }

    private static void DrawBlocks(RectD r, Rgba[] pal, ref GlitchRandom f, Canvas ctx)
    {
        for (int i = 0; i < 46; i++)
        {
            double w = f.Range(20, 180), h = f.Range(14, 120);
            var rect = new RectD(f.Range(r.MinX, r.MaxX - w), f.Range(r.MinY, r.MaxY - h), w, h);
            var colour = pal[(int)(f.Unit() * 2.99)];
            ctx.FillRect(rect, colour.WithAlpha(f.Range(0.4, 0.9)));
            if (f.Unit() < 0.4)
            {
                ctx.FillRect(new RectD(rect.MinX, rect.MidY, rect.Width, 2), Rgba.White(1, 0.5));
            }
        }
    }

    private static void DrawCracks(RectD r, double t, uint seed, Canvas ctx)
    {
        const double cycle = 8;
        uint round = Seeds.Of(t / cycle);
        double grow = Math.Min(1, (t % cycle) / 2.5);
        var shape = new GlitchRandom(Seeds.Add(seed, Seeds.Mul(round, 31)));
        double reach = Math.Max(r.Width, r.Height) * 0.35 * (1 - Math.Pow(1 - grow, 3));
        for (int o = 0; o < 4; o++)
        {
            var origin = new Vec(shape.Range(r.MinX, r.MaxX), shape.Range(r.MinY, r.MaxY));
            for (int k = 0; k < 8; k++)
            {
                var path = new PathD();
                path.MoveTo(origin);
                double angle = k * Math.PI / 4 + shape.Range(-0.3, 0.3);
                var p = origin;
                for (int s = 0; s < 7; s++)
                {
                    angle += shape.Range(-0.5, 0.5);
                    double step = reach / 7 * shape.Range(0.6, 1.3);
                    p = new Vec(p.X + Math.Cos(angle) * step, p.Y + Math.Sin(angle) * step);
                    path.LineTo(p);
                }
                Stroke(path, Rgba.White(0, 0.7), 4, ctx);
                Stroke(path, Rgba.White(1, 0.9), 1.5, ctx);
            }
        }
    }

    private static readonly string[] PopupMessages = { "ACCESS DENIED", "SEGMENTATION FAULT", "FIREWALL DISABLED", "DISK ENCRYPTED", "CONNECTION HIJACKED" };

    private static void DrawPopups(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        int shown = (int)(t * 1.6) + 2;
        int first = Math.Max(0, shown - 36);
        var ink = Rgba.White(0.15);
        for (int i = first; i < shown; i++)
        {
            var g = new GlitchRandom(Seeds.Add(seed, Seeds.Mul((uint)i, 7919)));
            double w = g.Range(220, 320), h = g.Range(100, 130);
            var box = new RectD(g.Range(r.MinX, r.MaxX - w), g.Range(r.MinY, r.MaxY - h), w, h);
            ctx.FillRect(box.Offset(6, -6), Rgba.White(0, 0.4));
            ctx.FillRect(box, Rgba.White(0.93));
            ctx.FillRect(new RectD(box.MinX, box.MaxY - 22, w, 22), pal[i % pal.Length]);
            PixelFont.Draw("ERROR", new Vec(box.MinX + 10, box.MaxY - 18), 2, Rgba.WhiteColor, ctx);
            PixelFont.Draw(PopupMessages[i % PopupMessages.Length], new Vec(box.MinX + 12, box.MidY - 6), 2, ink, ctx);
            var ok = new RectD(box.MaxX - 60, box.MinY + 10, 48, 22);
            ctx.FillRect(ok, Rgba.White(0.8));
            PixelFont.Draw("OK", new Vec(ok.MinX + 15, ok.MinY + 4), 2, ink, ctx);
        }
    }

    private static void DrawRadar(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        var c = new Vec(r.MidX, r.MidY);
        double radius = Math.Min(r.Width, r.Height) * 0.46;
        for (int i = 1; i <= 5; i++)
        {
            double rr = radius * i / 5;
            var ring = new PathD();
            ring.AddOval(new RectD(c.X - rr, c.Y - rr, rr * 2, rr * 2));
            Stroke(ring, pal[0].WithAlpha(0.45), 2, ctx);
        }
        var cross = new PathD();
        cross.MoveTo(c.X - radius, c.Y); cross.LineTo(c.X + radius, c.Y);
        cross.MoveTo(c.X, c.Y - radius); cross.LineTo(c.X, c.Y + radius);
        Stroke(cross, pal[0].WithAlpha(0.35), 1.5, ctx);
        double angle = t * 1.8;
        for (int k = 0; k < 24; k++)
        {
            double a0 = angle - k * 0.03;
            var wedge = new PathD();
            wedge.AddWedge(c, radius, (a0 - 0.03) * 180 / Math.PI, a0 * 180 / Math.PI);
            ctx.Fill(wedge, pal[0].WithAlpha(0.4 * (1 - k / 24.0)));
        }
        var blips = new GlitchRandom(seed);
        for (int i = 0; i < 10; i++)
        {
            double a = blips.Range(0, Math.PI * 2), d = blips.Range(0.15, 0.95) * radius;
            double since = (angle - a) % (Math.PI * 2);
            double fade = since < 0 ? 0 : Math.Max(0, 1 - since / 3);
            ctx.FillOval(new RectD(c.X + Math.Cos(a) * d - 6, c.Y + Math.Sin(a) * d - 6, 12, 12), pal[1].WithAlpha(fade));
        }
    }

    private static void DrawTunnel(RectD r, double t, Rgba[] pal, Canvas ctx)
    {
        var c = new Vec(r.MidX, r.MidY);
        for (int i = 0; i < 16; i++)
        {
            double z = (t * 0.35 + i / 16.0) % 1;
            double s = z * z;
            var rect = new RectD(c.X - r.Width * s * 0.6, c.Y - r.Height * s * 0.6, r.Width * s * 1.2, r.Height * s * 1.2);
            var path = new PathD();
            path.AddRect(rect);
            Stroke(path, pal[i % pal.Length].WithAlpha(z), 2 + 6 * z, ctx, glow: true);
        }
    }

    private static void DrawWarp(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        var c = new Vec(r.MidX, r.MidY);
        double maxR = Vec.Hypot(r.Width, r.Height) * 0.55;
        var stars = new GlitchRandom(seed);
        for (int i = 0; i < 240; i++)
        {
            double a = stars.Range(0, Math.PI * 2);
            double speed = stars.Range(0.15, 0.6);
            double z = (t * speed + stars.Unit()) % 1;
            double d = z * z * maxR;
            double tail = d * 0.82;
            var path = new PathD();
            path.MoveTo(c.X + Math.Cos(a) * tail, c.Y + Math.Sin(a) * tail);
            path.LineTo(c.X + Math.Cos(a) * d, c.Y + Math.Sin(a) * d);
            var colour = i % 4 == 0 ? pal[i % pal.Length] : Rgba.WhiteColor;
            Stroke(path, colour.WithAlpha(Math.Min(1, z * 1.6)), 1 + 3 * z, ctx);
        }
    }

    private static void DrawScope(RectD r, double t, Rgba[] pal, Canvas ctx)
    {
        var grid = Rgba.White(1, 0.06);
        for (double gx = r.MinX; gx < r.MaxX; gx += 60) ctx.FillRect(new RectD(gx, r.MinY, 1, r.Height), grid);
        for (double gy = r.MinY; gy < r.MaxY; gy += 60) ctx.FillRect(new RectD(r.MinX, gy, r.Width, 1), grid);
        for (int w = 0; w < 3; w++)
        {
            var path = new PathD();
            double amp = r.Height * (0.12 + 0.08 * w) * (1 + 0.3 * Math.Sin(t * 0.7 + w));
            double freq = 0.006 + 0.004 * w;
            double mid = r.MidY + (w - 1) * r.Height * 0.18;
            double x = r.MinX;
            path.MoveTo(x, mid);
            while (x <= r.MaxX)
            {
                path.LineTo(x, mid + amp * Math.Sin(x * freq + t * (2 + w)));
                x += 6;
            }
            Stroke(path, pal[w], 3, ctx, glow: true);
        }
    }

    private static double Ecg(double p)
    {
        if (p >= 0.40 && p < 0.44) return (p - 0.40) / 0.04 * 0.2;
        if (p >= 0.44 && p < 0.47) return 0.2 - (p - 0.44) / 0.03 * 0.5;
        if (p >= 0.47 && p < 0.50) return -0.3 + (p - 0.47) / 0.03 * 1.3;
        if (p >= 0.50 && p < 0.54) return 1.0 - (p - 0.50) / 0.04 * 1.0;
        if (p >= 0.62 && p < 0.70) return 0.15 * Math.Sin((p - 0.62) / 0.08 * Math.PI);
        return 0;
    }

    private static void DrawHeartbeat(RectD r, double t, Rgba[] pal, ref GlitchRandom f, Canvas ctx)
    {
        var path = new PathD();
        double x = r.MinX;
        double amp = r.Height * 0.28;
        path.MoveTo(x, r.MidY);
        while (x <= r.MaxX)
        {
            double p = ((x - r.MinX) / r.Width * 3 - t * 0.9) % 1;
            path.LineTo(x, r.MidY + Ecg(p < 0 ? p + 1 : p) * amp);
            x += 4;
        }
        Stroke(path, pal[0], 4, ctx, glow: true);
        int bpm = 180 + (int)(f.Unit() * 819);
        PixelFont.Draw($"BPM {bpm}", new Vec(r.MaxX - 360, r.MaxY - 90), 8, pal[1], ctx);
    }

    private static void DrawGridFloor(RectD r, double t, Rgba[] pal, Canvas ctx)
    {
        double horizon = r.MinY + r.Height * 0.42;
        double sunR = r.Height * 0.22;
        var sun = new RectD(r.MidX - sunR, horizon - sunR * 0.3, sunR * 2, sunR * 2);
        ctx.FillOvalGradient(sun, pal[2], pal[0]);
        var stripe = Rgba.White(0, 0.9);
        for (int i = 0; i < 6; i++)
        {
            double y = horizon + i * sunR * 0.18;
            ctx.FillRect(new RectD(sun.MinX, y, sun.Width, (i + 1) * 2), stripe);
        }
        ctx.FillRect(new RectD(r.MinX, r.MinY, r.Width, horizon - r.MinY), Rgba.Black);
        var lines = new PathD();
        for (int i = -20; i <= 20; i++)
        {
            lines.MoveTo(r.MidX + i * 30, horizon);
            lines.LineTo(r.MidX + i * r.Width * 0.12, r.MinY);
        }
        for (int k = 0; k < 14; k++)
        {
            double z = (k / 14.0 + t * 0.35) % 1;
            double y = horizon - (horizon - r.MinY) * z * z * z;
            lines.MoveTo(r.MinX, y);
            lines.LineTo(r.MaxX, y);
        }
        Stroke(lines, pal[1], 2, ctx, glow: true);
    }

    private static void DrawWaves(RectD r, double t, Rgba[] pal, Canvas ctx)
    {
        const int bands = 34;
        double h = r.Height / bands;
        for (int i = 0; i < bands; i++)
        {
            double y = r.MinY + i * h;
            double shift = Math.Sin(i * 0.45 + t * 3) * 70;
            ctx.FillRect(new RectD(r.MinX + shift, y, r.Width, h * 0.7), pal[i % pal.Length].WithAlpha(0.26));
        }
    }

    private static void DrawChecker(RectD r, double t, Rgba[] pal, ref GlitchRandom f, Canvas ctx)
    {
        double cell = r.Width / 18;
        int tick = (int)(t * 4);
        int j = 0;
        for (double y = r.MinY; y < r.MaxY; y += cell, j++)
        {
            int i = 0;
            for (double x = r.MinX; x < r.MaxX; x += cell, i++)
            {
                if ((i + j + tick) % 2 == 0 && f.Unit() < 0.7)
                {
                    ctx.FillRect(new RectD(x, y, cell, cell), pal[(i + j + tick / 2) % pal.Length].WithAlpha(0.38));
                }
            }
        }
    }

    private static readonly string[] LoadingLabels = { "COPYING KEYCHAIN", "UPLOADING FILES", "ENCRYPTING DISK", "CRACKING PASSWORDS", "WIPING BACKUPS", "DISABLING FIREWALL" };

    private static void DrawLoading(RectD r, double t, Rgba[] pal, Canvas ctx)
    {
        double barW = Math.Min(r.Width * 0.6, 900);
        const double barH = 26;
        double x = r.MidX - barW / 2;
        double y = r.MidY + LoadingLabels.Length * 34;
        for (int i = 0; i < LoadingLabels.Length; i++)
        {
            double progress = (t * (0.05 + 0.03 * i) + i * 0.17) % 1;
            y -= 68;
            PixelFont.Draw($"{LoadingLabels[i]} {(int)(progress * 100)}%", new Vec(x, y + barH + 8), 3, pal[i % pal.Length], ctx);
            ctx.FillRect(new RectD(x, y, barW, barH), Rgba.White(0, 0.85));
            ctx.FillRect(new RectD(x + 3, y + 3, (barW - 6) * progress, barH - 6), pal[i % pal.Length]);
        }
    }

    private static void DrawVirus(RectD r, double t, Rgba[] pal, uint seed, ref GlitchRandom f, Canvas ctx)
    {
        double cell = r.Width / 48;
        double phase = (t / 20) % 1;
        var g = new GlitchRandom(Seeds.Add(seed, Seeds.Of(t / 20)));
        var seeds = new Vec[5];
        for (int i = 0; i < 5; i++) seeds[i] = new Vec(g.Range(r.MinX, r.MaxX), g.Range(r.MinY, r.MaxY));
        double radius = phase * Vec.Hypot(r.Width, r.Height) * 0.6;
        for (double y = r.MinY; y < r.MaxY; y += cell)
        {
            for (double x = r.MinX; x < r.MaxX; x += cell)
            {
                double d = double.PositiveInfinity;
                foreach (var s in seeds) d = Math.Min(d, Vec.Hypot(s.X - x, s.Y - y));
                if (d < radius)
                {
                    bool front = radius - d < cell * 2;
                    var colour = (front ? pal[1] : pal[0]).WithAlpha(front ? 0.9 : f.Range(0.25, 0.6));
                    ctx.FillRect(new RectD(x + 1, y + 1, cell - 2, cell - 2), colour);
                }
            }
        }
    }

    private static void DrawDataStream(RectD r, double t, Rgba[] pal, uint seed, Canvas ctx)
    {
        const int rows = 40;
        double h = r.Height / rows;
        var g = new GlitchRandom(seed);
        for (int row = 0; row < rows; row++)
        {
            double speed = g.Range(80, 600) * (row % 2 == 0 ? 1 : -1);
            double dash = g.Range(20, 140), gap = g.Range(10, 80);
            double period = dash + gap;
            double offset = (t * speed) % period;
            var colour = pal[row % pal.Length].WithAlpha(0.7);
            for (double x = r.MinX - period + offset; x < r.MaxX; x += period)
            {
                ctx.FillRect(new RectD(x, r.MinY + row * h + h * 0.3, dash, h * 0.35), colour);
            }
        }
    }

    private static void DrawBigText(RectD r, double t, Rgba[] pal, string[] options, ref GlitchRandom f, Canvas ctx)
    {
        if (options.Length == 0 || f.Unit() <= 0.12) return;
        string count = (10 - (int)t % 11).ToString();
        var texts = options.Select(o => o.Replace("#", count)).ToArray();
        double maxWidth = r.Width * 0.7;
        string text = texts.FirstOrDefault(s => PixelFont.Width(s) * 4 <= maxWidth) ?? texts[^1];
        var centre = new Vec(r.MidX + f.Range(-4, 4), r.MidY);
        PixelText(text, centre, maxWidth, 16, pal[0], ctx, box: true);
        // A shifted ghost copy, the RGB split look.
        PixelText(text, new Vec(centre.X + 5, centre.Y - 3), maxWidth, 16, pal[1].WithAlpha(0.45), ctx);
    }

    private static void DrawTiled(RectD r, double t, Rgba[] pal, string word, Canvas ctx)
    {
        double p = Math.Max(3, Math.Round(r.Width / 260));
        double unit = PixelFont.Width(word + "  ") * p;
        double rowH = (PixelFont.Height + 5) * p;
        int row = 0;
        for (double y = r.MinY; y < r.MaxY; y += rowH, row++)
        {
            double dir = row % 2 == 0 ? 1 : -1;
            double offset = (t * 40 * dir) % unit;
            var colour = pal[row % pal.Length].WithAlpha(0.6);
            for (double x = r.MinX - unit + offset; x < r.MaxX; x += unit)
            {
                PixelFont.Draw(word, new Vec(x, y), p, colour, ctx);
            }
        }
    }
}

/// Renders the takeover for one screen at half resolution. The overlay then
/// scales it up with nearest-neighbour sampling under the cat.
public sealed class TakeoverRenderer : IDisposable
{
    private Canvas? canvas;
    /// The screen size in logical pixels that the canvas was built for.
    private double logicalW, logicalH;

    public Canvas? Frame => canvas;
    public bool HasFrame { get; private set; }

    /// Renders one frame for a screen of `logicalW` x `logicalH` logical pixels.
    public void Render(GlitchRecipe recipe, double logicalWidth, double logicalHeight, double time, uint seed, double pulse)
    {
        int w = Math.Max(1, (int)Math.Ceiling(logicalWidth / 2));
        int h = Math.Max(1, (int)Math.Ceiling(logicalHeight / 2));
        if (canvas == null || canvas.Width != w || canvas.Height != h)
        {
            canvas?.Dispose();
            canvas = new Canvas(w, h);
        }
        logicalW = logicalWidth;
        logicalH = logicalHeight;
        canvas.ResetState();
        canvas.ClearDevice(new RectI(0, 0, w, h));
        // Half resolution, y up: (x, y) -> (x / 2, h - y / 2).
        canvas.Concat(new Affine(0.5, 0, 0, -0.5, 0, h));
        Takeover.Render(recipe, new RectD(0, 0, logicalW, logicalH), time, seed, pulse, canvas);
        canvas.Flush();
        HasFrame = true;
    }

    public void Clear() => HasFrame = false;

    public void Dispose() => canvas?.Dispose();
}
