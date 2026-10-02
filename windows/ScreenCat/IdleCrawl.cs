using System;
using System.Collections.Generic;
using System.Linq;

namespace ScreenCat;

/// The crawl that runs while you are away, in any mode. It starts after a
/// stretch with no mouse or keyboard input and only ends when the app stops it,
/// which it does on the first touch or key press.
///
/// The order is: the cat walks in on a normal screen, stops and grows to
/// `growScale` while you watch, then the whole screen turns into a glitch. One
/// style plays for `glitchStyleSeconds`, then the next takes over. The cat
/// roams the screen on top of it, up, down and sideways, zapping windows. At
/// the edge it brings the next app's window forward. The glitch drops for that
/// moment, so the new app is seen normally while the cat walks in, then a new
/// style takes it over.
///
/// The cat roams the whole screen here, not just its floor. Like "follow me",
/// that is only allowed because two things stand in for the floor: it shrinks
/// as it goes up, so up reads as further away, and it never moves steeper than
/// `maxSlope`, zig-zagging up anything steeper instead of rising straight.
public sealed class IdleCrawlBehavior : IBehavior, IBreachSource
{
    private enum Stage
    {
        Countdown, Entering, Growing, Moving, Zapping, Resting, Switching, Arriving, Exiting,
        // Mr. Robot only: glitch on, then hop to a random app.
        Hacking, Hopping,
    }
    private Stage stage = Stage.Entering;
    /// For the self-test and the log.
    public string StageName => stage.ToString().ToLowerInvariant();

    private readonly struct Stop
    {
        public readonly Vec Point;
        /// The window to zap there, if it is a window and not just a waypoint.
        public readonly RectD? Window;
        public Stop(Vec point, RectD? window) { Point = point; Window = window; }
    }

    private List<Stop> stops = new();
    private int current;
    private Vec goal = Vec.Zero;
    /// True while heading for the edge rather than a stop.
    private bool leaving;
    private double direction = 1;
    private double legDirection = 1;
    private double timer;
    private double growTime;
    private readonly double baseSize;
    private double GrowDuration => Speed > 1 ? 1 : 3;

    /// 1 for the idle crawl. Mr. Robot runs at 4: glitches animate and change
    /// four times as fast, and the cat moves twice as fast and hops apps
    /// after one stop instead of wandering each one.
    public readonly double Speed;
    /// Ends by itself after this many seconds (Mr. Robot's three minutes).
    public readonly double? MaxDuration;
    /// Mr. Robot: no cat at all. The screen glitches and jumps between apps
    /// in random order, with bursts of flashes and a new style on every hop.
    public readonly bool Catless;
    private double burstTimer;
    /// Jump to a random app, a few places left or right. True if it did.
    public Func<bool>? RequestRandomApp;
    private double elapsed;
    /// Seconds left on the "starting in" countdown, so the click that started
    /// it is over before any touch can end it.
    public double CountdownLeft { get; private set; }
    private double exitTime;
    private double exitStartSize;
    public bool IsExiting => stage == Stage.Exiting;

    public IReadOnlyList<Breach> Breaches => Array.Empty<Breach>();
    public Zap? Zap { get; private set; }
    public Aura? Aura { get; private set; }

    // The full-screen glitch.
    private bool takeoverOn;
    public double TakeoverOpacity { get; private set; }
    public int RecipeIndex { get; private set; } = Rng.Int(0, Takeover.Recipes.Length);
    public double StyleTime { get; private set; }
    public uint StyleSeed { get; private set; } = Rng.Seed();
    public double Pulse { get; private set; }

    /// Fresh windows for the screen as it is now, in surface-local coordinates.
    public Func<List<RectD>>? RequestTargets;
    /// Bring the next app forward in this direction. True if it did.
    public Func<double, bool>? RequestNextApp;

    /// Kept so `BeginExit` can be called from outside an update.
    private double sceneCatSize;

    public IdleCrawlBehavior(Scene scene, List<RectD> targets, double speed = 1, double? maxDuration = null, double countdown = 0,
        bool catless = false)
    {
        Speed = speed;
        MaxDuration = maxDuration;
        Catless = catless;
        var cat = scene.Cat;
        baseSize = cat.Size;
        sceneCatSize = cat.Size;
        var start = Helpers.EntryPoint(scene, cat.Size);
        cat.Pos = start;
        cat.Visible = true;
        direction = start.X < scene.Stage.MidX ? 1 : -1;
        WalkIn(scene);
        if (countdown > 0)
        {
            CountdownLeft = countdown;
            cat.Visible = false;
            stage = Stage.Countdown;
        }
    }

    /// Any touch, or the end of Mr. Robot: the glitch goes at once, and the
    /// cat shrinks away to nothing where it stands.
    public void BeginExit()
    {
        if (stage == Stage.Exiting) return;
        stage = Stage.Exiting;
        takeoverOn = false;
        TakeoverOpacity = 0;
        Zap = null;
        Aura = null;
        exitTime = 0;
        exitStartSize = sceneCatSize;
    }

    /// From off the side to a spot a quarter of the way in, on a normal screen.
    private void WalkIn(Scene scene)
    {
        var s = scene.Stage;
        goal = new Vec(direction > 0 ? s.MinX + s.Width * 0.25 : s.MaxX - s.Width * 0.25,
            Math.Min(scene.Cat.Pos.Y, s.MaxY - scene.Cat.Size * 1.3));
        leaving = false;
    }

    /// The next style, never the one just shown.
    private void NextStyle()
    {
        int next = Rng.Int(0, Takeover.Recipes.Length);
        if (next == RecipeIndex) next = (next + 1) % Takeover.Recipes.Length;
        RecipeIndex = next;
        StyleTime = 0;
        StyleSeed = Rng.Seed();
        Pulse = 1;
    }

    /// Where to go on this screen: each window, plus a couple of open spots so
    /// it wanders the whole screen, in walking order.
    private void PlanStops(List<RectD> windows, Scene scene)
    {
        var s = scene.Stage;
        double top = s.MaxY - scene.Cat.Size * 1.3;
        // Mr. Robot hops apps fast: one window, no wandering.
        if (Speed > 1) windows = windows.Take(1).ToList();
        var list = windows.Select(w =>
        {
            double inset = Math.Min(scene.Cat.Size, w.Width / 3);
            double lo = w.MinX + inset, hi = Math.Max(lo, w.MaxX - inset);
            return new Stop(new Vec(Rng.Range(lo, hi), Math.Min(Math.Max(w.MinY, s.MinY), top)), w);
        }).ToList();
        int extra = Speed > 1 ? (windows.Count == 0 ? 1 : 0) : Rng.IntIn(2, 3);
        for (int i = 0; i < extra; i++)
        {
            list.Add(new Stop(new Vec(Rng.Range(s.MinX + s.Width * 0.1, s.MaxX - s.Width * 0.1),
                Rng.Range(s.MinY, Math.Max(s.MinY, top))), null));
        }
        stops = direction > 0 ? list.OrderBy(p => p.Point.X).ToList() : list.OrderByDescending(p => p.Point.X).ToList();
        current = 0;
        NextGoal(scene);
    }

    private void NextGoal(Scene scene)
    {
        var s = scene.Stage;
        stage = Stage.Moving;
        if (current < stops.Count)
        {
            goal = stops[current].Point;
            leaving = false;
        }
        else
        {
            double top = s.MaxY - scene.Cat.Size * 1.3;
            goal = new Vec(direction > 0 ? s.MaxX - scene.Cat.Size * 0.6 : s.MinX + scene.Cat.Size * 0.6,
                Math.Min(Math.Max(scene.Cat.Pos.Y + Rng.Range(-0.2, 0.2) * s.Height, s.MinY), top));
            leaving = true;
        }
    }

    public bool Update(double dt, Scene scene)
    {
        if (Zap is Zap z) Zap = z with { Age = z.Age + dt };
        Pulse = Math.Max(0, Pulse - dt * 1.5);
        // Fades in over 1.2s (0.3s for Mr. Robot), out over 0.4s so the next
        // app shows promptly. While Mr. Robot hops it only dims, so the new
        // app is glimpsed through the glitch.
        double level = takeoverOn ? (stage == Stage.Hopping ? 0.25 : 1) : 0;
        double rise = Catless ? 0.3 : 1.2;
        TakeoverOpacity = TakeoverOpacity < level
            ? Math.Min(level, TakeoverOpacity + dt / rise)
            : Math.Max(level, TakeoverOpacity - dt / 0.4);
        if (TakeoverOpacity > 0)
        {
            StyleTime += dt * Speed;
            if (StyleTime >= scene.Config.GlitchStyleSeconds) NextStyle();
        }
        var cat = scene.Cat;
        sceneCatSize = cat.Size;
        elapsed += dt;
        if (MaxDuration is double max && elapsed >= max && stage != Stage.Exiting) BeginExit();

        if (Catless) cat.Visible = false;

        switch (stage)
        {
            case Stage.Countdown:
                CountdownLeft -= dt;
                if (CountdownLeft <= 0)
                {
                    CountdownLeft = 0;
                    if (Catless)
                    {
                        takeoverOn = true;
                        NextStyle();
                        timer = Rng.Range(4, 7);
                        stage = Stage.Hacking;
                    }
                    else
                    {
                        cat.Visible = true;
                        stage = Stage.Entering;
                    }
                }
                break;

            case Stage.Hacking:
                timer -= dt;
                burstTimer -= dt;
                if (burstTimer <= 0)
                {
                    Pulse = Rng.Range(0.5, 1);
                    burstTimer = Rng.Range(0.5, 1.5);
                }
                if (timer <= 0)
                {
                    if (RequestRandomApp?.Invoke() == true)
                    {
                        timer = 1.3;
                        stage = Stage.Hopping;
                    }
                    else
                    {
                        NextStyle();
                        timer = Rng.Range(4, 7);
                    }
                }
                break;

            case Stage.Hopping:
                timer -= dt;
                if (timer <= 0)
                {
                    NextStyle();
                    timer = Rng.Range(4, 7);
                    stage = Stage.Hacking;
                }
                break;

            case Stage.Exiting:
            {
                if (!cat.Visible || Catless) return true;
                exitTime += dt;
                double t = Math.Min(1, exitTime / 0.8);
                // Shrinks slowly, then fast, and is gone.
                cat.Size = Math.Max(1, exitStartSize * (1 - t * t));
                if (t >= 1)
                {
                    cat.Visible = false;
                    return true;
                }
                break;
            }

            case Stage.Entering:
            case Stage.Arriving:
                if (Roam(goal, scene, dt))
                {
                    if (stage == Stage.Entering)
                    {
                        stage = Stage.Growing;
                        growTime = 0;
                        cat.SetClip(Clip.StandIdle);
                    }
                    else
                    {
                        takeoverOn = true;
                        NextStyle();
                        PlanStops(RequestTargets?.Invoke() ?? new List<RectD>(), scene);
                    }
                }
                break;

            case Stage.Growing:
            {
                growTime += dt;
                double t = Math.Min(1, growTime / GrowDuration);
                // Grows in pulses that settle, so the change is easy to watch.
                double wobble = 1 + 0.08 * Math.Sin(t * Math.PI * 6) * (1 - t);
                double eased = t * t * (3 - 2 * t);
                cat.Size = baseSize * (1 + (scene.Config.GrowScale - 1) * eased) * wobble;
                cat.Pos.Y = Math.Min(cat.Pos.Y, scene.Stage.MaxY - cat.Size * 1.3);
                Aura = new Aura(new Vec(cat.Pos.X, cat.Pos.Y + cat.DrawnSize * 0.45), cat.DrawnSize, t, growTime,
                    (int)(growTime * 2) % Glitch.Accents.Length);
                if (t >= 1)
                {
                    cat.Size = baseSize * scene.Config.GrowScale;
                    Aura = null;
                    takeoverOn = true;
                    PlanStops(RequestTargets?.Invoke() ?? new List<RectD>(), scene);
                }
                break;
            }

            case Stage.Moving:
                if (!Roam(goal, scene, dt)) break;
                if (leaving)
                {
                    if (RequestNextApp?.Invoke(direction) == true)
                    {
                        // Off this side. The glitch drops so the next app is seen
                        // as it comes forward; give it a moment first.
                        cat.Visible = false;
                        takeoverOn = false;
                        timer = 1.4;
                        stage = Stage.Switching;
                    }
                    else
                    {
                        // Nowhere to go: turn round, with a new style.
                        direction = -direction;
                        NextStyle();
                        PlanStops(RequestTargets?.Invoke() ?? new List<RectD>(), scene);
                    }
                }
                else if (stops[current].Window is RectD window)
                {
                    double u = scene.Ui;
                    var head = new Vec(cat.Pos.X, cat.Pos.Y + cat.DrawnSize * 0.75);
                    var to = new Vec(
                        Math.Min(Math.Max(head.X + Rng.Range(-60, 60) * u, window.MinX + 10 * u), window.MaxX - 10 * u),
                        Math.Min(Math.Max(head.Y + cat.DrawnSize, window.MinY + 10 * u), window.MaxY - 10 * u));
                    Zap = new Zap(head, to, 0, Rng.Int(0, Glitch.Accents.Length));
                    cat.SetClip(Clip.Crouch);
                    timer = 0.7;
                    stage = Stage.Zapping;
                }
                else
                {
                    cat.SetClip(Rng.Bool() ? Clip.SitIdle : Clip.StandIdle);
                    timer = Rng.Range(0.6, 1.4);
                    stage = Stage.Resting;
                }
                break;

            case Stage.Zapping:
                timer -= dt;
                if (timer <= 0)
                {
                    Zap = null;
                    Pulse = 1;
                    cat.SetClip(Clip.SitIdle);
                    timer = 0.8;
                    stage = Stage.Resting;
                }
                break;

            case Stage.Resting:
                timer -= dt;
                if (timer <= 0)
                {
                    current++;
                    NextGoal(scene);
                }
                break;

            case Stage.Switching:
                timer -= dt;
                if (timer <= 0)
                {
                    // Come in from the side the app came in from, on a normal
                    // screen; the glitch comes back once it is in.
                    var s = scene.Stage;
                    cat.Pos = new Vec(direction > 0 ? s.MinX - cat.Size : s.MaxX + cat.Size,
                        Math.Min(cat.Pos.Y, s.MaxY - cat.Size * 1.3));
                    cat.Visible = true;
                    WalkIn(scene);
                    stage = Stage.Arriving;
                }
                break;
        }
        // Never finishes by itself; any input ends it.
        return false;
    }

    /// One frame of walking toward `target` anywhere on the screen. True on
    /// arrival. Shallow routes are taken straight; steeper ones zig-zag at the
    /// steepest allowed slope, turning at the ends of each leg.
    private bool Roam(Vec target, Scene scene, double dt)
    {
        var cat = scene.Cat;
        double dx = target.X - cat.Pos.X;
        double dy = target.Y - cat.Pos.Y;
        double distance = Vec.Hypot(dx, dy);
        if (distance <= Math.Max(2, cat.DrawnSize * 0.15)) return true;

        double slope = Math.Max(0.05, scene.Config.MaxSlope);
        bool hurrying = distance > cat.DrawnSize * 6;
        double boost = Speed > 1 ? 2 : 1;
        double pace = boost * cat.DrawnSize * (hurrying ? scene.Config.RunSpeed * 0.7 : scene.Config.WalkSpeed * 1.3);
        double step = pace * dt;
        double vx, vy;
        double margin = cat.DrawnSize * 0.6;
        if (Math.Abs(dy) <= slope * Math.Abs(dx))
        {
            vx = dx / distance;
            vy = dy / distance;
            legDirection = dx >= 0 ? 1 : -1;
            step = Math.Min(step, distance);
        }
        else
        {
            double reach = cat.DrawnSize * 2.5;
            bool offStage = legDirection > 0
                ? cat.Pos.X + step > scene.Stage.MaxX - margin
                : cat.Pos.X - step < scene.Stage.MinX + margin;
            bool pastTarget = (cat.Pos.X - target.X) * legDirection > reach;
            if (offStage || pastTarget) legDirection = -legDirection;
            double length = Math.Sqrt(1 + slope * slope);
            vx = legDirection / length;
            vy = (dy > 0 ? slope : -slope) / length;
        }
        cat.Pos.X += vx * step;
        cat.Pos.Y = Math.Min(Math.Max(cat.Pos.Y + vy * step, scene.Stage.MinY), scene.Stage.MaxY - cat.DrawnSize * 1.3);
        if (Math.Abs(vx) > 0.05) cat.Facing = vx > 0 ? 1 : -1;
        cat.SetClip(hurrying ? Clip.Run : Clip.SideWalk);
        cat.Stride += step;
        scene.ApplyDepthOverFullStage(scene.Config.FollowDepthShrink);
        return false;
    }
}
