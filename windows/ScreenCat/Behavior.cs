using System;
using System.Collections.Generic;
using System.Linq;

namespace ScreenCat;

public sealed class Scene
{
    public readonly CatState Cat = new();
    public BallState Ball;
    /// Which edge the cat is treating as the floor this time.
    public Surface Surface = Surface.Bottom;
    /// The screen the routine plays out on, in Windows screen pixels (y down).
    public RectD ScreenRect = RectD.Zero;
    /// The walking area in surface-local coordinates. All behaviour maths, and
    /// `Cat.Pos`, are in this space; the surface transform maps it to the screen.
    public RectD Stage = RectD.Zero;
    /// How far from the floor the cat may stray, in local units.
    public double RoamBand;
    public Config Config = new();
    /// Windows for crawler mode to break, in surface-local coordinates.
    public List<RectD> CrawlTargets = new();
    /// Pixels per logical pixel on the cat's screen (1 at 100%, 1.5 at 150%).
    /// Fixed sizes from the Mac code, such as line widths, are scaled by it.
    public double Ui = 1;

    /// Local (y up) to screen (y down).
    public Affine ToScreen => Surface.Transform(ScreenRect);

    /// Lay out the local walking space for a surface on a screen.
    public void SetStage(Surface surface, RectD screen, double catSize)
    {
        Surface = surface;
        ScreenRect = screen;
        Stage = surface.LocalRect(screen);
        // The band is measured off the shorter screen edge, so a wall gets the
        // same sensible depth as the floor instead of half the screen width.
        double reference = Math.Min(screen.Width, screen.Height);
        RoamBand = Math.Max(0, Math.Min(Stage.Height, reference * Config.RoamHeight) - catSize);
    }

    /// Depth over the whole screen rather than the narrow floor band, used
    /// while following the pointer and while roaming in the idle crawl. The
    /// shrink is what makes moving up read as walking away into the room
    /// instead of taking off.
    public void ApplyDepthOverFullStage(double strength)
    {
        if (Stage.Height <= 1) { Cat.Depth = 1; return; }
        double t = Math.Clamp((Cat.Pos.Y - Stage.MinY) / Stage.Height, 0, 1);
        Cat.Depth = 1 - strength * t;
    }

    /// A cat further from the floor is further away, so it draws slightly
    /// smaller. Without this, drifting off the floor just looks like lift-off.
    public void ApplyDepth()
    {
        if (RoamBand <= 1) { Cat.Depth = 1; return; }
        double t = Math.Clamp((Cat.Pos.Y - Stage.MinY) / RoamBand, 0, 1);
        Cat.Depth = 1 - Config.DepthShrink * t;
    }
}

public interface IBehavior
{
    /// Returns true once the routine is finished.
    bool Update(double dt, Scene scene);
}

// Scripted behaviours ------------------------------------------------------

public abstract record CatAction
{
    /// Walk along a gentle arc to a point. `Bend` curves the path so it is not
    /// a straight line; the arc is a single sweep, never a bob.
    public sealed record WalkTo(Vec Point, double Pace, double Bend) : CatAction;
    public sealed record RunTo(Vec Point, double Pace) : CatAction;
    public sealed record Hold(Clip Clip, double Seconds) : CatAction;
    /// Play a one-shot clip through to its last frame.
    public sealed record Play(Clip Clip) : CatAction;
    public sealed record Face(double Facing) : CatAction;
}

public sealed class ScriptedBehavior : IBehavior
{
    private readonly List<CatAction> actions;
    /// Which action is playing now. Equal to the count once the script is done.
    public int Index { get; private set; }
    private bool started;

    // Path state
    private readonly List<Vec> samples = new();
    private readonly List<double> cumulative = new();
    private double total;
    private double travelled;
    private double pace = 1;
    private bool running;
    private double paceSeed;
    private double timer;
    private double maxSlope = 0.45;

    public ScriptedBehavior(IEnumerable<CatAction> actions) { this.actions = actions.ToList(); }

    public bool Update(double dt, Scene scene)
    {
        if (Index < actions.Count)
        {
            if (!started) { Begin(actions[Index], scene); started = true; }
            if (Step(actions[Index], dt, scene))
            {
                Index++;
                started = false;
                return Index >= actions.Count;
            }
            return false;
        }
        return true;
    }

    private void Begin(CatAction action, Scene scene)
    {
        var cat = scene.Cat;
        maxSlope = scene.Config.MaxSlope;
        switch (action)
        {
            case CatAction.WalkTo w:
                BuildPath(cat.Pos, w.Point, w.Bend);
                pace = w.Pace; running = false;
                paceSeed = Rng.Range(0, Math.PI * 2);
                travelled = 0;
                break;
            case CatAction.RunTo r:
                BuildPath(cat.Pos, r.Point, 0);
                pace = r.Pace; running = true;
                travelled = 0;
                cat.SetClip(Clip.Run);
                break;
            case CatAction.Hold h:
                timer = h.Seconds;
                cat.SetClip(h.Clip);
                break;
            case CatAction.Play p:
                cat.SetClip(p.Clip);
                break;
            case CatAction.Face f:
                cat.Facing = f.Facing;
                break;
        }
    }

    /// Samples a quadratic arc so the walk can be advanced by real distance.
    private void BuildPath(Vec a, Vec bRaw, double bend)
    {
        // Two rules, both about not looking airborne:
        //  - never climb: the sheet has no back view, and a side-on cat drifting
        //    upward reads as levitating;
        //  - never drop faster than maxSlope: a steep or vertical descent looks
        //    like the cat fell rather than walked.
        double drop = Math.Abs(bRaw.X - a.X) * maxSlope;
        var b = new Vec(bRaw.X, Math.Min(Math.Max(bRaw.Y, a.Y - drop), a.Y));
        double dx = b.X - a.X, dy = b.Y - a.Y;
        double len = Math.Max(1, Vec.Hypot(dx, dy));
        var perp = new Vec(-dy / len, dx / len);
        // Cap the arc too. A perpendicular bulge on a level path is vertical
        // movement by another name, so keep it to a gentle sweep.
        double lean = Math.Min(bend, len * 0.08) * (Rng.Bool() ? 1 : -1);
        var control = new Vec((a.X + b.X) / 2 + perp.X * lean, (a.Y + b.Y) / 2 + perp.Y * lean);

        samples.Clear();
        cumulative.Clear();
        const int steps = 32;
        for (int i = 0; i <= steps; i++)
        {
            double t = (double)i / steps;
            double u = 1 - t;
            samples.Add(new Vec(u * u * a.X + 2 * u * t * control.X + t * t * b.X,
                                u * u * a.Y + 2 * u * t * control.Y + t * t * b.Y));
        }
        double run = 0;
        cumulative.Add(0);
        for (int i = 1; i < samples.Count; i++)
        {
            run += Vec.Hypot(samples[i].X - samples[i - 1].X, samples[i].Y - samples[i - 1].Y);
            cumulative.Add(run);
        }
        total = Math.Max(1, run);
    }

    private (Vec point, Vec tangent) PointAt(double distance)
    {
        double d = Math.Clamp(distance, 0, total);
        int i = 1;
        while (i < cumulative.Count - 1 && cumulative[i] < d) i++;
        double seg = Math.Max(0.0001, cumulative[i] - cumulative[i - 1]);
        double t = (d - cumulative[i - 1]) / seg;
        var a = samples[i - 1];
        var b = samples[i];
        var p = new Vec(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);
        double len = Math.Max(0.0001, Vec.Hypot(b.X - a.X, b.Y - a.Y));
        return (p, new Vec((b.X - a.X) / len, (b.Y - a.Y) / len));
    }

    private bool Step(CatAction action, double dt, Scene scene)
    {
        var cat = scene.Cat;
        switch (action)
        {
            case CatAction.WalkTo:
            case CatAction.RunTo:
            {
                double baseSpeed = running ? scene.Config.RunSpeed : scene.Config.WalkSpeed;
                // Gentle drift in pace, so the walk is never metronomic.
                double wobble = running ? 1 : 1 + 0.2 * Math.Sin(travelled / (cat.DrawnSize * 2.4) + paceSeed);
                double speed = cat.DrawnSize * baseSpeed * pace * wobble;
                travelled += speed * dt;

                var (p, tangent) = PointAt(travelled);
                cat.Pos = p;
                scene.ApplyDepth();

                // Sideways travel uses the profile walk; travel toward the viewer
                // uses the front-on walk. There is no away-facing sprite, so an
                // upward tangent falls back to the profile.
                if (Math.Abs(tangent.X) >= Math.Abs(tangent.Y) || tangent.Y > 0)
                {
                    cat.SetClip(running ? Clip.Run : Clip.SideWalk);
                    if (Math.Abs(tangent.X) > 0.05) cat.Facing = tangent.X > 0 ? 1 : -1;
                }
                else
                {
                    cat.SetClip(running ? Clip.Run : Clip.FrontWalk);
                }
                cat.Stride += speed * dt;
                return travelled >= total;
            }
            case CatAction.Hold:
                timer -= dt;
                return timer <= 0;
            case CatAction.Play:
                return cat.FinishedOnce;
            default:
                return true;
        }
    }
}

// Ball chase ---------------------------------------------------------------

public sealed class BallBehavior : IBehavior
{
    private enum Stage { Chase, Pounce, Play, BatAway, FollowOff }
    private Stage stage = Stage.Chase;
    private Vec ballVel = Vec.Zero;
    private double friction = 0.55;
    private double timer;
    private Vec exit = Vec.Zero;
    private bool setUp;
    private double heading = 1;
    private double playFor;

    public bool Update(double dt, Scene scene)
    {
        var cat = scene.Cat;
        var rect = scene.Stage;
        if (!setUp) { Configure(scene); setUp = true; }

        if (scene.Ball.Visible)
        {
            scene.Ball.Pos.X += ballVel.X * dt;
            scene.Ball.Pos.Y += ballVel.Y * dt;
            double keep = Math.Pow(friction, dt);
            ballVel.X *= keep; ballVel.Y *= keep;
            double speed = Vec.Hypot(ballVel.X, ballVel.Y);
            if (speed < 6 * scene.Ui) ballVel = Vec.Zero;
            scene.Ball.Rotation -= (ballVel.X >= 0 ? 1 : -1) * (speed * dt) / Math.Max(1, scene.Ball.Size * 0.5);
        }

        switch (stage)
        {
            case Stage.Chase:
            {
                double dx = scene.Ball.Pos.X - cat.Pos.X;
                double dy = (scene.Ball.Pos.Y - scene.Ball.Size * 0.5) - cat.Pos.Y;
                double dist = Vec.Hypot(dx, dy);
                RunCat(cat, dx, dy, dist, cat.DrawnSize * scene.Config.RunSpeed, dt);
                scene.ApplyDepth();
                if ((dist < cat.DrawnSize * 0.8 && Vec.Hypot(ballVel.X, ballVel.Y) < cat.DrawnSize * 1.2)
                    || cat.ClipTime > 25)
                {
                    stage = Stage.Pounce;
                    timer = 0.25;
                    cat.SetClip(Clip.Run);
                }
                break;
            }
            case Stage.Pounce:
                timer -= dt;
                if (timer <= 0)
                {
                    // The play animation draws its own yarn ball, so park the cat on
                    // the ball's spot and hide the loose one.
                    cat.Pos = new Vec(scene.Ball.Pos.X, scene.Ball.Pos.Y - scene.Ball.Size * 0.5);
                    scene.ApplyDepth();
                    scene.Ball.Visible = false;
                    ballVel = Vec.Zero;
                    cat.SetClip(Clip.BallPlay);
                    playFor = Rng.Range(scene.Config.PlaySecondsMin, scene.Config.PlaySecondsMax);
                    stage = Stage.Play;
                }
                break;
            case Stage.Play:
                playFor -= dt;
                if (playFor <= 0)
                {
                    // Bat it away, off the far side.
                    exit = new Vec(heading > 0 ? rect.MaxX + cat.DrawnSize * 2.2 : rect.MinX - cat.DrawnSize * 2.2,
                        Math.Min(Math.Max(cat.Pos.Y + Rng.Range(-rect.Height * 0.08, 0), rect.MinY + cat.DrawnSize * 0.1),
                            rect.MinY + rect.Height * 0.75));
                    scene.Ball.Pos = new Vec(cat.Pos.X + heading * cat.DrawnSize * 0.4, cat.Pos.Y + scene.Ball.Size * 0.5);
                    scene.Ball.Visible = true;
                    var d = new Vec(exit.X - scene.Ball.Pos.X, exit.Y - scene.Ball.Pos.Y);
                    double len = Math.Max(1, d.Length);
                    double kick = cat.DrawnSize * 8;
                    ballVel = new Vec(d.X / len * kick, d.Y / len * kick);
                    friction = 0.92;
                    cat.Facing = d.X >= 0 ? 1 : -1;
                    cat.SetClip(Clip.StandIdle);
                    stage = Stage.BatAway;
                    // A beat watching it go.
                    timer = 0.7;
                }
                break;
            case Stage.BatAway:
                timer -= dt;
                if (timer <= 0) { stage = Stage.FollowOff; cat.SetClip(Clip.Run); }
                break;
            case Stage.FollowOff:
            {
                double dx = exit.X - cat.Pos.X, dy = exit.Y - cat.Pos.Y;
                double dist = Vec.Hypot(dx, dy);
                RunCat(cat, dx, dy, dist, cat.DrawnSize * scene.Config.RunSpeed, dt);
                scene.ApplyDepth();
                if (scene.Ball.Pos.X < rect.MinX - cat.DrawnSize * 2 || scene.Ball.Pos.X > rect.MaxX + cat.DrawnSize * 2)
                {
                    scene.Ball.Visible = false;
                }
                if (dist < cat.DrawnSize * 0.4) return true;
                break;
            }
        }
        return false;
    }

    private static void RunCat(CatState cat, double dx, double dy, double dist, double speed, double dt)
    {
        cat.SetClip(Clip.Run);
        if (dist <= 1) return;
        double stepLen = Math.Min(speed * dt, dist);
        cat.Pos.X += dx / dist * stepLen;
        cat.Pos.Y += dy / dist * stepLen;
        if (Math.Abs(dx) > dist * 0.15) cat.Facing = dx > 0 ? 1 : -1;
        cat.Stride += stepLen;
    }

    private void Configure(Scene scene)
    {
        var cat = scene.Cat;
        var rect = scene.Stage;
        double size = cat.Size;

        // The ball rolls across the screen, so it enters from a side edge and
        // stops well inside the far half.
        heading = Rng.Bool() ? 1 : -1;
        double lane = Helpers.GroundY(scene, size);
        var start = new Vec(heading > 0 ? rect.MinX - size * 0.8 : rect.MaxX + size * 0.8, lane);
        double travel = rect.Width * Rng.Range(0.5, 0.75);
        var aim = new Vec(start.X + heading * travel, lane);

        var d = new Vec(aim.X - start.X, aim.Y - start.Y);
        double len = Math.Max(1, d.Length);

        scene.Ball.Size = size * 0.42;
        scene.Ball.Pos = new Vec(start.X, start.Y + scene.Ball.Size * 0.5);
        scene.Ball.Rotation = 0;
        scene.Ball.Visible = true;
        // Keeping 55% of speed per second means the ball coasts about 1.67x its
        // first second, so this launch speed lands it near `aim`.
        friction = 0.55;
        double roll = len * 0.62;
        ballVel = new Vec(d.X / len * roll, d.Y / len * roll);

        cat.Pos = new Vec(start.X - d.X / len * size * 1.8, start.Y);
        cat.Facing = heading;
        cat.SetClip(Clip.Run);
        cat.Visible = true;
        scene.ApplyDepth();
    }
}

// Hungry (needs a food bowl drawn beside the cat) --------------------------

public sealed class HungryBehavior : IBehavior
{
    private readonly ScriptedBehavior inner;
    public Vec? BowlAt { get; private set; }
    private readonly Vec spot;
    /// Seconds since the cat started walking away, to lift the bowl a beat later.
    private double leftFor;

    public HungryBehavior(Scene scene)
    {
        var cat = scene.Cat;
        var rect = scene.Stage;
        double size = cat.Size;
        var start = Helpers.EntryPoint(scene, size);
        cat.Pos = start;
        cat.Visible = true;

        // Beg down on the bottom band, level with or below where it came in.
        var target = new Vec(Rng.Range(rect.MinX + rect.Width * 0.2, rect.MaxX - rect.Width * 0.2),
            Math.Min(start.Y, Helpers.GroundY(scene, size)));
        spot = target;
        double beg = Rng.Range(scene.Config.BegSecondsMin, scene.Config.BegSecondsMax);

        inner = new ScriptedBehavior(new CatAction[]
        {
            new CatAction.WalkTo(target, 1.0, size * 0.5),
            new CatAction.Hold(Clip.StandIdle, 0.6),
            new CatAction.Hold(Clip.SitIdle, beg),
            new CatAction.Hold(Clip.Crouch, 1.2),
            new CatAction.WalkTo(Helpers.ExitPoint(rect, target, size), 1.1, size * 0.35),
        });
    }

    public bool Update(double dt, Scene scene)
    {
        bool done = inner.Update(dt, scene);
        // Keyed to the script, not to a guessed walk time: pace wobble, depth
        // and the arc all change how long the walk in takes.
        if (inner.Index >= 4) leftFor += dt;
        BowlAt = inner.Index >= 1 && leftFor < 1.0
            ? new Vec(spot.X + scene.Cat.DrawnSize * 0.75, spot.Y)
            : null;
        return done;
    }
}

// Asking to play -----------------------------------------------------------

/// Walks on, sits, and asks for a game with a speech bubble. If the OK button is
/// clicked inside the invite window, the cat follows your pointer for a while.
/// Otherwise it gives up and wanders off.
public sealed class PlayBehavior : IBehavior
{
    private enum Stage { Arriving, Asking, Following, Leaving }
    private Stage stage = Stage.Arriving;
    private readonly ScriptedBehavior script;
    private ScriptedBehavior? leaving;
    private double waited;
    private double followed;
    private double fidget;
    /// Which way the cat is zig-zagging while it climbs toward the pointer.
    private double legDirection = 1;
    /// Where the pointer is, in screen pixels. Set by the app; a test can
    /// replace it with a stand-in.
    public static Func<Vec>? PointerSource;
    private readonly Vec spot;

    /// Set while the invite is up, in surface-local coordinates.
    public Vec? BubbleTip { get; private set; }
    /// Flipped by the app when the OK button is clicked.
    public bool Accepted;
    /// Set by the app each frame: is the pointer resting on the bubble or cat?
    public bool PointerResting;
    /// How much of the required dwell has been served, 0...1, for the button fill.
    public double DwellProgress { get; private set; }
    private double dwell;

    public PlayBehavior(Scene scene)
    {
        var cat = scene.Cat;
        var rect = scene.Stage;
        double size = cat.Size;
        var start = Helpers.EntryPoint(scene, size);
        cat.Pos = start;
        cat.Visible = true;
        // Well inside the screen, so the bubble has room and does not hang off.
        spot = new Vec(Rng.Range(rect.MinX + rect.Width * 0.25, rect.MaxX - rect.Width * 0.25),
            Math.Min(start.Y, Helpers.GroundY(scene, size)));
        script = new ScriptedBehavior(new CatAction[]
        {
            new CatAction.WalkTo(spot, 1.1, size * 0.3),
            new CatAction.Hold(Clip.StandIdle, 0.4),
        });
    }

    public bool Update(double dt, Scene scene)
    {
        var cat = scene.Cat;
        switch (stage)
        {
            case Stage.Arriving:
                if (script.Update(dt, scene))
                {
                    stage = Stage.Asking;
                    cat.SetClip(Clip.SitIdle);
                    BubbleTip = new Vec(cat.Pos.X, cat.Pos.Y + cat.DrawnSize * 1.05);
                }
                break;

            case Stage.Asking:
            {
                waited += dt;
                BubbleTip = new Vec(cat.Pos.X, cat.Pos.Y + cat.DrawnSize * 1.05);

                // Resting the pointer on the cat or its bubble counts as saying yes,
                // so you never have to hit a small target. Moving away resets it,
                // otherwise a pointer parked at the bottom of the screen would
                // accept by accident.
                double needed = Math.Max(0.5, scene.Config.DwellSeconds);
                dwell = PointerResting ? dwell + dt : 0;
                DwellProgress = Math.Min(dwell / needed, 1);
                if (dwell >= needed) Accepted = true;
                // Shift about a little so it does not look frozen for three minutes.
                fidget -= dt;
                if (fidget <= 0)
                {
                    fidget = Rng.Range(4, 11);
                    cat.SetClip(Rng.Pick(new[] { Clip.SitIdle, Clip.SitIdle, Clip.StandIdle, Clip.Crouch }));
                }
                if (Accepted)
                {
                    BubbleTip = null;
                    followed = 0;
                    stage = Stage.Following;
                    cat.SetClip(Clip.StandIdle);
                }
                else if (waited >= scene.Config.InviteSeconds)
                {
                    BubbleTip = null;
                    stage = Stage.Leaving;
                    leaving = new ScriptedBehavior(new CatAction[]
                    {
                        new CatAction.Hold(Clip.Crouch, 0.8),
                        new CatAction.WalkTo(Helpers.ExitPoint(scene.Stage, cat.Pos, cat.Size), 1.0, cat.Size * 0.3),
                    });
                }
                break;
            }

            case Stage.Following:
                followed += dt;
                Follow(scene, dt);
                if (followed >= scene.Config.FollowSeconds)
                {
                    stage = Stage.Leaving;
                    leaving = new ScriptedBehavior(new CatAction[]
                    {
                        new CatAction.Hold(Clip.SitIdle, 1.4),
                        new CatAction.WalkTo(Helpers.ExitPoint(scene.Stage, cat.Pos, cat.Size), 1.0, cat.Size * 0.3),
                    });
                }
                break;

            case Stage.Leaving:
                return leaving?.Update(dt, scene) ?? true;
        }
        return false;
    }

    /// Trots after the pointer across the whole screen.
    ///
    /// Following in y as well as x means giving up the "never leave the floor"
    /// rule, so two mechanisms replace it: the screen is treated as a floor
    /// receding away from you, and the cat shrinks as it moves up it; and it
    /// still never travels steeply. When the pointer is somewhere it cannot
    /// reach on one shallow diagonal, the cat switchbacks up instead.
    private void Follow(Scene scene, double dt)
    {
        var cat = scene.Cat;
        var inverse = scene.ToScreen.Inverted();
        var pointer = inverse.Apply(PointerSource?.Invoke() ?? Vec.Zero);
        double margin = cat.DrawnSize * 0.6;
        var target = new Vec(
            Math.Min(Math.Max(pointer.X, scene.Stage.MinX + margin), scene.Stage.MaxX - margin),
            Math.Min(Math.Max(pointer.Y, scene.Stage.MinY), scene.Stage.MaxY - cat.DrawnSize * 1.3));

        double dx = target.X - cat.Pos.X;
        double dy = target.Y - cat.Pos.Y;
        double distance = Vec.Hypot(dx, dy);
        // Settle beside the pointer rather than jittering underneath it.
        double comfort = cat.DrawnSize * 0.8;
        if (distance <= comfort)
        {
            cat.SetClip(Clip.SitIdle);
            return;
        }

        double slope = Math.Max(0.05, scene.Config.MaxSlope);
        bool hurrying = distance > cat.DrawnSize * 5;
        double pace = cat.DrawnSize * (hurrying ? scene.Config.RunSpeed : scene.Config.WalkSpeed);
        double step = pace * dt;
        double vx, vy;

        if (Math.Abs(dy) <= slope * Math.Abs(dx))
        {
            // Shallow enough to head straight for it.
            vx = dx / distance;
            vy = dy / distance;
            legDirection = dx >= 0 ? 1 : -1;
            step = Math.Min(step, distance - comfort);
        }
        else
        {
            // Too steep. Hold the steepest allowed diagonal and turn at the
            // ends of each leg, so it climbs by zig-zagging.
            double reach = cat.DrawnSize * 2.5;
            bool leavingStage = legDirection > 0
                ? cat.Pos.X + step > scene.Stage.MaxX - margin
                : cat.Pos.X - step < scene.Stage.MinX + margin;
            bool pastTarget = (cat.Pos.X - target.X) * legDirection > reach;
            if (leavingStage || pastTarget) legDirection = -legDirection;
            double length = Math.Sqrt(1 + slope * slope);
            vx = legDirection / length;
            vy = (dy > 0 ? slope : -slope) / length;
        }

        cat.Pos.X += vx * step;
        cat.Pos.Y += vy * step;
        cat.Pos.Y = Math.Min(Math.Max(cat.Pos.Y, scene.Stage.MinY), scene.Stage.MaxY - cat.DrawnSize * 1.3);
        if (Math.Abs(vx) > 0.05) cat.Facing = vx > 0 ? 1 : -1;
        cat.SetClip(hurrying ? Clip.Run : Clip.SideWalk);
        cat.Stride += step;
        scene.ApplyDepthOverFullStage(scene.Config.FollowDepthShrink);
    }
}

// Crawler ------------------------------------------------------------------

/// Crawler mode: walks under each target window in turn, zaps it from its head
/// and watches it "break". The breaking is drawn on the overlay; the windows
/// themselves are never touched. Movement keeps every rule the other routines
/// keep: in from the side, level or downhill, out the side. It never climbs to
/// a window; the zap goes up instead.
public sealed class CrawlBehavior : IBehavior, IBreachSource
{
    private enum Stage { Walking, Zapping, Watching, Leaving }
    private Stage stage = Stage.Walking;
    private readonly List<RectD> targets;
    private int current;
    private ScriptedBehavior? walk;
    private double timer;
    private readonly List<Breach> breaches = new();
    public IReadOnlyList<Breach> Breaches => breaches;
    public Zap? Zap { get; private set; }
    public Aura? Aura => null;

    public CrawlBehavior(Scene scene, List<RectD> targets)
    {
        var cat = scene.Cat;
        var start = Helpers.EntryPoint(scene, cat.Size);
        cat.Pos = start;
        cat.Visible = true;
        // Visit them in walking order from whichever side it came in.
        bool fromLeft = start.X < scene.Stage.MidX;
        this.targets = fromLeft ? targets.OrderBy(t => t.MidX).ToList() : targets.OrderByDescending(t => t.MidX).ToList();
        BeginWalk(scene);
    }

    private void BeginWalk(Scene scene)
    {
        var cat = scene.Cat;
        if (current >= targets.Count)
        {
            stage = Stage.Leaving;
            walk = new ScriptedBehavior(new CatAction[]
            {
                new CatAction.WalkTo(Helpers.ExitPoint(scene.Stage, cat.Pos, cat.Size), 1.15, cat.Size * 0.3),
            });
            return;
        }
        var t = targets[current];
        double margin = cat.Size;
        double x = Math.Min(Math.Max(t.MidX + Rng.Range(-0.2, 0.2) * t.Width, scene.Stage.MinX + margin), scene.Stage.MaxX - margin);
        double y = Math.Min(cat.Pos.Y, Helpers.GroundY(scene, cat.Size));
        walk = new ScriptedBehavior(new CatAction[]
        {
            new CatAction.WalkTo(new Vec(x, y), 1.25, cat.Size * 0.3),
            new CatAction.Hold(Clip.StandIdle, 0.3),
        });
        stage = Stage.Walking;
    }

    public bool Update(double dt, Scene scene)
    {
        for (int i = 0; i < breaches.Count; i++)
        {
            var b = breaches[i];
            b.Age += dt;
            breaches[i] = b;
        }
        breaches.RemoveAll(b => b.Finished);
        if (Zap is Zap z) Zap = z with { Age = z.Age + dt };
        var cat = scene.Cat;
        double u = scene.Ui;

        switch (stage)
        {
            case Stage.Walking:
                if (walk?.Update(dt, scene) ?? true)
                {
                    var t = targets[current];
                    var head = new Vec(cat.Pos.X, cat.Pos.Y + cat.DrawnSize * 0.75);
                    var to = new Vec(Math.Min(Math.Max(head.X, t.MinX + 10 * u), t.MaxX - 10 * u),
                        Math.Min(Math.Max(t.MinY + 10 * u, head.Y + cat.DrawnSize * 0.6), t.MaxY - 10 * u));
                    Zap = new Zap(head, to, 0, Rng.Int(0, Glitch.Accents.Length));
                    cat.SetClip(Clip.Crouch);
                    timer = 0.8;
                    stage = Stage.Zapping;
                }
                break;
            case Stage.Zapping:
                timer -= dt;
                if (timer <= 0 && Zap is Zap zap)
                {
                    var breach = Breach.Random(targets[current], zap.To);
                    breach.AccentIndex = zap.AccentIndex;
                    breaches.Add(breach);
                    Zap = null;
                    cat.SetClip(Clip.SitIdle);
                    timer = 1.8;
                    stage = Stage.Watching;
                }
                break;
            case Stage.Watching:
                timer -= dt;
                if (timer <= 0)
                {
                    current++;
                    BeginWalk(scene);
                }
                break;
            case Stage.Leaving:
            {
                bool gone = walk?.Update(dt, scene) ?? true;
                return gone && breaches.Count == 0;
            }
        }
        return false;
    }
}

// Behaviour factory --------------------------------------------------------

public enum Routine
{
    Stroll,
    Nap,
    Ball,
    Hungry,
    Play,
    Crawl,
    /// The nonstop crawl that runs while you are away from the PC.
    IdleCrawl,
    /// Three minutes of the idle crawl at four times the pace.
    MrRobot,
}

public static class Helpers
{
    public static string Name(this Routine r) => r switch
    {
        Routine.Stroll => "stroll",
        Routine.Nap => "nap",
        Routine.Ball => "ball",
        Routine.Hungry => "hungry",
        Routine.Play => "play",
        Routine.Crawl => "crawl",
        Routine.IdleCrawl => "idlecrawl",
        _ => "mrrobot",
    };

    public static IBehavior MakeBehavior(Routine routine, Scene scene)
    {
        var cat = scene.Cat;
        var rect = scene.Stage;
        double size = cat.Size;

        switch (routine)
        {
            case Routine.Ball:
                return new BallBehavior();
            case Routine.Hungry:
                return new HungryBehavior(scene);
            case Routine.Play:
                return new PlayBehavior(scene);
            case Routine.Crawl:
                return new CrawlBehavior(scene, scene.CrawlTargets);
            case Routine.IdleCrawl:
                return new IdleCrawlBehavior(scene, scene.CrawlTargets);
            case Routine.MrRobot:
                return new IdleCrawlBehavior(scene, scene.CrawlTargets, speed: 4, maxDuration: 180, countdown: 3);
            case Routine.Nap:
            {
                // Naps happen at the sides, and the walk in and out is level, so the cat
                // never has to climb to its bed.
                bool onLeft = Rng.Bool();
                double y = GroundY(scene, size);
                var outside = new Vec(onLeft ? rect.MinX - size * 1.4 : rect.MaxX + size * 1.4, y);
                var inside = new Vec(onLeft ? rect.MinX + rect.Width * Rng.Range(0.12, 0.3)
                                            : rect.MaxX - rect.Width * Rng.Range(0.12, 0.3), y);
                cat.Pos = outside;
                cat.Visible = true;
                double nap = Rng.Range(scene.Config.NapSecondsMin, scene.Config.NapSecondsMax);
                return new ScriptedBehavior(new CatAction[]
                {
                    new CatAction.WalkTo(inside, 0.9, size * 0.15),
                    new CatAction.Hold(Clip.StandIdle, 0.7),
                    new CatAction.Play(Clip.LieDown),
                    new CatAction.Hold(Clip.Sleep, nap),
                    new CatAction.Hold(Clip.SitIdle, 2.2),
                    new CatAction.Hold(Clip.StandIdle, 0.8),
                    new CatAction.WalkTo(outside, 0.85, size * 0.12),
                });
            }
            default:
            {
                var start = EntryPoint(scene, size);
                cat.Pos = start;
                cat.Visible = true;
                var actions = new List<CatAction>();
                var previous = start;
                // Two to four legs. Each target is drawn from the bottom band and is
                // level with or below the last, and the path builder caps how steeply
                // the cat may descend, so the route is a series of shallow diagonals.
                int legs = Rng.IntIn(2, 4);
                for (int i = 0; i < legs; i++)
                {
                    double y = Math.Min(previous.Y, GroundY(scene, size));
                    var p = new Vec(Rng.Range(rect.MinX + size * 0.4, rect.MaxX - size * 0.4), y);
                    actions.Add(new CatAction.WalkTo(p, Rng.Range(0.75, 1.3), size * Rng.Range(0, 0.7)));
                    if (Rng.Bool() && Rng.Bool())
                    {
                        actions.Add(new CatAction.Hold(Rng.Bool() ? Clip.SitIdle : Clip.StandIdle, Rng.Range(1.5, 4.0)));
                    }
                    previous = p;
                }
                actions.Add(new CatAction.WalkTo(ExitPoint(rect, previous, size), Rng.Range(0.9, 1.2), size * 0.3));
                return new ScriptedBehavior(actions);
            }
        }
    }

    /// A standing spot, weighted toward the floor so the cat mostly pads along the
    /// edge it is walking on rather than drifting out into open screen.
    public static double GroundY(Scene scene, double size)
    {
        double u = Rng.Unit();
        return scene.Stage.MinY + scene.RoamBand * Math.Pow(u, scene.Config.GroundBias);
    }

    /// Cats come on from either end of the floor. Entering from "above" would mean
    /// a long descent, and a steep descent is exactly what looks like falling.
    public static Vec EntryPoint(Scene scene, double size)
    {
        var rect = scene.Stage;
        double y = GroundY(scene, size);
        return new Vec(Rng.Bool() ? rect.MinX - size * 1.4 : rect.MaxX + size * 1.4, y);
    }

    /// The nearest way out, always sideways and always level.
    public static Vec ExitPoint(RectD rect, Vec from, double size)
    {
        bool goLeft = (from.X - rect.MinX) <= (rect.MaxX - from.X);
        return new Vec(goLeft ? rect.MinX - size * 2.0 : rect.MaxX + size * 2.0, from.Y);
    }
}
