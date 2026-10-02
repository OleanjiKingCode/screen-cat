using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Text;

namespace ScreenCat;

/// `--selftest <folder>`: checks what can be checked without a person at the
/// screen, and writes pictures of it. Used by CI, where nobody can watch the
/// cat, and handy after changing colours or styles.
///
///  - the sprites load and the recolour finds the pack's colours;
///  - every routine runs to the end on every edge it may use, the walks never
///    climb and never go steeper than `maxSlope`;
///  - all fifty glitch styles render, with their timings;
///  - the overlay window can be made and updated, and capture exclusion is
///    accepted (reported, not failed, since CI has no real desktop).
///
/// Writes preview.png, glitches.png, takeover.png, trail.png and report.txt.
public static class SelfTest
{
    private static readonly StringBuilder Report = new();
    private static int failures;

    private static void Line(string text) => Report.AppendLine(text);

    private static void Check(bool ok, string what)
    {
        Line($"{(ok ? "ok  " : "FAIL")}  {what}");
        if (!ok) failures++;
    }

    public static int Run(string folder)
    {
        Directory.CreateDirectory(folder);
        Line($"Screen Cat self-test, {DateTime.Now:yyyy-MM-dd HH:mm:ss}, {Environment.OSVersion.VersionString}");
        Line("");
        try { Settings(); } catch (Exception e) { Check(false, $"settings threw {e}"); }
        SpriteSheet? sheet = null;
        try { sheet = Sprites(); } catch (Exception e) { Check(false, $"sprites threw {e}"); }
        if (sheet != null)
        {
            try { Preview(sheet, Path.Combine(folder, "preview.png")); } catch (Exception e) { Check(false, $"preview threw {e}"); }
            try { Routines(sheet, Path.Combine(folder, "trail.png")); } catch (Exception e) { Check(false, $"routines threw {e}"); }
        }
        try { Glitches(Path.Combine(folder, "glitches.png")); } catch (Exception e) { Check(false, $"glitches threw {e}"); }
        try { TakeoverSheet(Path.Combine(folder, "takeover.png")); } catch (Exception e) { Check(false, $"takeover threw {e}"); }
        if (sheet != null)
        {
            try { OverlaySmoke(sheet); } catch (Exception e) { Line($"note  overlay smoke test threw {e.GetType().Name}: {e.Message}"); }
        }
        Line("");
        Line(failures == 0 ? "PASSED" : $"FAILED: {failures} check(s)");
        File.WriteAllText(Path.Combine(folder, "report.txt"), Report.ToString());
        sheet?.Dispose();
        return failures == 0 ? 0 : 1;
    }

    // Settings ---------------------------------------------------------------

    private static void Settings()
    {
        var d = Config.Parse(Config.DefaultJson());
        Check(d.SizeDivisor == 24 && d.MinGapSeconds == 3 && d.MaxGapSeconds == 15 && d.MaxSlope == 0.45
              && d.GlitchStyleSeconds == 60 && d.IdleCrawlSeconds == 120 && d.GrowScale == 2,
            "default settings round-trip with the Mac defaults");
        var odd = Config.Parse("{\"sizeDivisor\": 500, \"napSecondsMin\": 50, \"napSecondsMax\": 10, \"idleCrawlSeconds\": 1, \"mode\": \"crawler\", }");
        Check(odd.SizeDivisor == 60 && odd.NapSecondsMax >= odd.NapSecondsMin && odd.IdleCrawlSeconds == 15 && odd.Mode == "crawler",
            "hand-edited settings are clamped and trailing commas are accepted");
        Check(Config.Parse("not json").SizeDivisor == 24, "a broken settings file falls back to defaults");
    }

    // Sprites ----------------------------------------------------------------

    private static SpriteSheet? Sprites()
    {
        var sheet = new SpriteSheet(new Config().SpritePalette);
        Check(sheet.IsLoaded && sheet.Ball != null && sheet.Shadow != null, "the three sprite PNGs load from the embedded resources");
        Check(sheet.Sheet?.Width == 384 && sheet.Sheet?.Height == 288, "the sheet is 384x288 (12 x 9 frames of 32x32)");
        Check(sheet.RecolouredPixels > 1000, $"the coat recolour matched {sheet.RecolouredPixels} pixels of the pack's exact colours");
        int missing = 0, faces = 0;
        foreach (var clip in ClipTable.All)
        {
            for (int i = 0; i < clip.Info().Count; i++)
            {
                if (sheet.Frame(clip, i) == null) missing++;
                if (sheet.Accessory(Accessory.Glasses, clip, i) != null) faces++;
            }
        }
        Check(missing == 0, "every frame of every clip crops out");
        Check(faces > 60, $"the face is found in {faces} frames for the accessories");
        return sheet.IsLoaded ? sheet : null;
    }

    /// Every clip, with and without the outfit, plus the bubble, bowl and ball.
    private static void Preview(SpriteSheet sheet, string path)
    {
        const double size = 96;
        int maxFrames = ClipTable.All.Max(c => c.Info().Count);
        int cell = 130;
        int w = cell * maxFrames + 20, h = cell * (ClipTable.All.Length + 2) + 260;
        using var canvas = new Canvas(w, h);
        canvas.FillRect(new RectD(0, 0, w, h), Rgba.White(0.18));
        // y up, like the overlay.
        canvas.Concat(new Affine(1, 0, 0, -1, 0, h));
        var palette = new Config().Extras;
        var cat = new CatState { Size = size, Visible = true };
        int row = 0;
        foreach (var clip in ClipTable.All)
        {
            for (int i = 0; i < clip.Info().Count; i++)
            {
                cat.Clip = clip;
                cat.Wearing = row % 2 == 0 ? new HashSet<Accessory> { Accessory.Chain, Accessory.Glasses } : new HashSet<Accessory> { Accessory.Chain };
                // Drive the frame directly by feeding the clock or the stride.
                var info = clip.Info();
                cat.ClipTime = info.StrideDriven ? 0 : (i + 0.5) / info.Fps;
                cat.Stride = info.StrideDriven ? (i + 0.5) / info.Count * cat.CycleDistance : 0;
                cat.Pos = new Vec(20 + cell * i + cell / 2.0, h - (row + 1) * cell + 10);
                CatArt.DrawCat(cat, sheet, true, palette, canvas);
            }
            row++;
        }
        // The play invite at the real on-screen scale, the bowl and the ball.
        double baseY = h - (row + 1) * cell - 120;
        var bubble = new SpeechBubble("LET'S PLAY", "OK");
        bubble.Draw(new Vec(200, baseY + 110), Math.Max(2, Math.Round(size / 14)), palette, false, 0.4, canvas);
        cat.Clip = Clip.SitIdle; cat.ClipTime = 0; cat.Pos = new Vec(200, baseY);
        CatArt.DrawCat(cat, sheet, true, palette, canvas);
        CatArt.DrawHearts(cat, 0.9, palette, canvas);
        CatArt.DrawFoodBowl(new Vec(420, baseY), cat.PixelScale, palette, 1, canvas);
        CatArt.DrawBall(new BallState { Pos = new Vec(560, baseY + 20), Size = size * 0.42, Rotation = 0.6, Visible = true }, sheet, canvas);
        PixelFont.Draw("0123456789 :()-%/ ABCXYZ'!?.", new Vec(700, baseY), 4, Rgba.WhiteColor, canvas);
        Save(canvas, path);
        Line($"wrote {Path.GetFileName(path)}");
    }

    // Routines ---------------------------------------------------------------

    private static void Routines(SpriteSheet sheet, string trailPath)
    {
        var screen = new RectD(0, 0, 1920, 1040);
        var trail = new List<Vec>();
        foreach (var routine in new[] { Routine.Stroll, Routine.Nap, Routine.Ball, Routine.Hungry, Routine.Play, Routine.Crawl, Routine.IdleCrawl, Routine.MrRobot })
        {
            var surfaces = routine is Routine.Stroll or Routine.Nap or Routine.Ball
                ? new[] { Surface.Bottom, Surface.Left, Surface.Right }
                : new[] { Surface.Bottom };
            foreach (var surface in surfaces)
            {
                for (int run = 0; run < 3; run++)
                {
                    var r = Simulate(routine, surface, screen, routine == Routine.Stroll && surface == Surface.Bottom && run == 0 ? trail : null);
                    if (r.error != null)
                    {
                        Check(false, $"{routine.Name()} on the {surface.Name()} threw {r.error}");
                        goto nextRoutine;
                    }
                    bool scripted = routine is Routine.Stroll or Routine.Nap or Routine.Hungry or Routine.Crawl;
                    if (!r.finished)
                    {
                        Check(false, $"{routine.Name()} on the {surface.Name()} did not finish in {r.seconds:0}s");
                        goto nextRoutine;
                    }
                    // Legs never end higher than they start; the only rise
                    // allowed is the gentle arc, at most half its capped bend.
                    if (scripted && r.climbed > r.size * 0.35 + 1)
                    {
                        Check(false, $"{routine.Name()} on the {surface.Name()} rose {r.climbed:0.0}px above where it came in");
                        goto nextRoutine;
                    }
                    // Roaming the whole screen holds the steepest allowed slope
                    // and zig-zags beyond it.
                    if (routine is Routine.IdleCrawl or Routine.MrRobot && r.steepest > new Config().MaxSlope + 0.01)
                    {
                        Check(false, $"{routine.Name()} on the {surface.Name()} went {r.steepest:0.00} steep");
                        goto nextRoutine;
                    }
                }
            }
            Check(true, $"{routine.Name()} runs to the end on {string.Join(", ", surfaces.Select(s => s.Name()))}, never climbs, never steeper than maxSlope");
            nextRoutine:;
        }

        // Where a stroll went, drawn as dots on a scaled-down screen.
        using var canvas = new Canvas(960, 520);
        canvas.FillRect(new RectD(0, 0, 960, 520), Rgba.White(0.15));
        canvas.Concat(new Affine(0.5, 0, 0, -0.5, 0, 520));
        foreach (var p in trail) canvas.FillRect(new RectD(p.X - 3, p.Y - 3, 6, 6), new Rgba(1, 0.8, 0.3));
        Save(canvas, trailPath);
        Line($"wrote {Path.GetFileName(trailPath)}");
    }

    private static (bool finished, double seconds, double climbed, double steepest, double size, string? error) Simulate(
        Routine routine, Surface surface, RectD screen, List<Vec>? trail)
    {
        var scene = new Scene { Config = new Config() };
        scene.Cat.Size = Math.Max(24, screen.Height / scene.Config.SizeDivisor);
        scene.SetStage(surface, screen, scene.Cat.Size);
        scene.CrawlTargets = new List<RectD>
        {
            new(200, 300, 600, 400),
            new(900, 200, 700, 500),
        };
        // A pointer parked high on the screen: the case that used to look like levitating.
        var pointer = scene.ToScreen.Apply(new Vec(scene.Stage.Width * 0.7, scene.Stage.Height * 0.8));
        PlayBehavior.PointerSource = () => pointer;
        var behavior = Helpers.MakeBehavior(routine, scene);
        if (behavior is IdleCrawlBehavior idle)
        {
            idle.RequestTargets = () => new List<RectD>(scene.CrawlTargets);
            int hops = 0;
            idle.RequestNextApp = _ => ++hops % 2 == 1;
        }
        scene.Cat.Visible = true;
        const double dt = 1.0 / 60;
        double t = 0, steepest = 0;
        var last = scene.Cat.Pos;
        double startY = scene.Cat.Pos.Y, highest = startY;
        double size = scene.Cat.Size;
        double limit = routine is Routine.Play ? 400 : 300;
        try
        {
            while (t < limit)
            {
                if (behavior is PlayBehavior play && t > 20) play.Accepted = true;
                if (behavior is IdleCrawlBehavior ic && t > 40) ic.BeginExit();
                scene.Cat.Advance(dt);
                bool done = behavior.Update(dt, scene);
                t += dt;
                var p = scene.Cat.Pos;
                if (double.IsNaN(p.X) || double.IsNaN(p.Y)) return (false, t, 0, 0, size, "a NaN position");
                double dx = Math.Abs(p.X - last.X), dy = p.Y - last.Y;
                // Only real moves count; a teleport (a new entry point) is not a step.
                if (dx + Math.Abs(dy) > 0.01 && dx + Math.Abs(dy) < scene.Cat.Size)
                {
                    if (dx > 0.05) steepest = Math.Max(steepest, Math.Abs(dy) / dx);
                    highest = Math.Max(highest, p.Y);
                }
                if (trail != null && ((int)(t * 60)) % 6 == 0) trail.Add(scene.ToScreen.Apply(p));
                last = p;
                if (done) return (true, t, highest - startY, steepest, size, null);
            }
        }
        catch (Exception e)
        {
            return (false, t, highest - startY, steepest, size, $"{e.GetType().Name}: {e.Message}");
        }
        return (false, t, highest - startY, steepest, size, null);
    }

    // Glitches ---------------------------------------------------------------

    /// The five short per-window glitches of crawler mode, part way through.
    private static void Glitches(string path)
    {
        int w = 5 * 420 + 20, h = 300;
        using var canvas = new Canvas(w, h);
        canvas.FillRect(new RectD(0, 0, w, h), Rgba.White(0.85));
        canvas.Concat(new Affine(1, 0, 0, -1, 0, h));
        for (int i = 0; i < 5; i++)
        {
            var rect = new RectD(20 + i * 420, 20, 400, 260);
            var b = new Breach
            {
                Rect = rect,
                Touch = new Vec(rect.MidX, rect.MinY + 30),
                Seed = (uint)(11 + i),
                Style = (GlitchStyle)i,
                AccentIndex = i,
                Age = 1.8,
            };
            Glitch.DrawBreach(b, canvas, 1);
        }
        Glitch.DrawZap(new Zap(new Vec(100, 10), new Vec(140, 120), 0.1, 0), canvas, 1);
        Save(canvas, path);
        Check(true, "all 5 crawler glitch styles render");
        Line($"wrote {Path.GetFileName(path)}");
    }

    /// Every full-screen style as a thumbnail, ten seconds in, with timings.
    private static void TakeoverSheet(string path)
    {
        const int cellW = 302, cellH = 196, cols = 10;
        int rows = (Takeover.Recipes.Length + cols - 1) / cols;
        int boardW = cellW * cols, boardH = (cellH + 22) * rows;
        using var board = new Bitmap(boardW, boardH, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(board);
        g.Clear(Color.FromArgb(51, 51, 51));
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
        using var font = new Font("Segoe UI", 8.5f, FontStyle.Regular, GraphicsUnit.Point);
        var renderer = new TakeoverRenderer();
        double worst = 0;
        string worstName = "";
        var timings = new StringBuilder();
        for (int i = 0; i < Takeover.Recipes.Length; i++)
        {
            var recipe = Takeover.Recipes[i];
            // Render at a laptop screen's size, then shrink into the cell.
            var watch = Stopwatch.StartNew();
            for (int f = 0; f < 10; f++) renderer.Render(recipe, 1512, 982, 5 + f * 0.05, (uint)i, 0);
            double ms = watch.Elapsed.TotalMilliseconds / 10;
            timings.AppendLine($"      {i + 1,2} {recipe.Name,-22} {ms,6:0.0} ms");
            if (ms > worst) { worst = ms; worstName = recipe.Name; }
            renderer.Render(recipe, 1512, 982, 10, (uint)(100 + i), 0);
            var frame = renderer.Frame!;
            // Over a light backdrop, as it would sit over a light app.
            using var composed = new Bitmap(frame.Width, frame.Height, PixelFormat.Format32bppArgb);
            using (var cg = Graphics.FromImage(composed))
            {
                cg.Clear(Color.FromArgb(235, 235, 235));
                cg.DrawImageUnscaled(frame.Bitmap, 0, 0);
            }
            int col = i % cols, row = i / cols;
            int x = col * cellW, y = row * (cellH + 22);
            g.DrawImage(composed, new Rectangle(x + 4, y + 4, cellW - 8, cellH - 4));
            g.DrawString($"{i + 1}. {recipe.Name}", font, Brushes.White, x + 6, y + cellH + 2);
        }
        renderer.Dispose();
        board.Save(path, ImageFormat.Png);
        Check(Takeover.Recipes.Length == 50 && Takeover.Recipes.Select(r => r.Name).Distinct().Count() == 50,
            "50 full-screen glitch styles, all named differently");
        Check(true, "all 50 full-screen glitch styles render");
        Line($"note  slowest style: {worstName} {worst:0.0} ms a frame at half resolution (budget 50 ms for 20 fps)");
        Line("      per style:");
        Report.Append(timings);
        Line($"wrote {Path.GetFileName(path)}");
    }

    // The window ---------------------------------------------------------------

    /// Makes the real overlay, draws one cat and pushes it. CI runs as a
    /// service with no visible desktop, so this only reports.
    private static void OverlaySmoke(SpriteSheet sheet)
    {
        var bounds = OverlayWindow.VirtualScreen();
        Line($"note  virtual screen {bounds.Width}x{bounds.Height} at {bounds.X0},{bounds.Y0}");
        using var overlay = new OverlayWindow(bounds);
        overlay.Show(true);
        bool excluded = overlay.SetHiddenFromCapture(true);
        Line($"note  capture exclusion (WDA_EXCLUDEFROMCAPTURE) accepted: {(excluded ? "yes" : "no")}");
        var canvas = overlay.Canvas!;
        canvas.ResetState();
        canvas.Concat(new Affine(1, 0, 0, -1, 0, canvas.Height));
        var cat = new CatState { Size = 96, Visible = true, Pos = new Vec(200, 40), Clip = Clip.SitIdle };
        var watch = Stopwatch.StartNew();
        CatArt.DrawCat(cat, sheet, true, new Config().Extras, canvas);
        overlay.Present(new RectI(0, 0, canvas.Width, canvas.Height));
        Line($"note  overlay window made, one frame drawn and pushed in {watch.Elapsed.TotalMilliseconds:0.0} ms");
        overlay.Hide();
    }

    private static void Save(Canvas canvas, string path)
    {
        using var copy = canvas.Snapshot();
        copy.Save(path, ImageFormat.Png);
    }
}
