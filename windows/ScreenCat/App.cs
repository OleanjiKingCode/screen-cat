using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ScreenCat;

/// The running app: the tray icon, the overlay, the schedule and the frame
/// loop. The Windows twin of the Mac's AppDelegate.
public sealed class App : IDisposable
{
    public readonly ApplicationContext Context = new();

    private readonly OverlayWindow overlay;
    private readonly Scene scene = new();
    private SpriteSheet? sheet;
    /// The idle crawl's full-screen glitch, under the cat.
    private readonly TakeoverRenderer takeover = new();
    private int takeoverFrame;
    private int shownRecipe = -1;
    private double shownTakeoverOpacity;
    private RectI takeoverArea;
    private bool takeoverDirty;

    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu;
    private ToolStripMenuItem statusItem = null!;
    private ToolStripMenuItem pauseItem = null!;
    private ToolStripMenuItem captureItem = null!;
    private ToolStripMenuItem loginItem = null!;
    private ToolStripMenuItem normalItem = null!;
    private ToolStripMenuItem crawlerItem = null!;

    private IBehavior? behavior;
    private readonly FrameClock clock;
    private readonly System.Windows.Forms.Timer scheduleTimer = new();
    private readonly System.Windows.Forms.Timer idleTimer = new();
    private readonly Stopwatch time = Stopwatch.StartNew();
    private double lastTick;
    private RectI lastDirty;
    private bool paused;
    /// `--demo` runs the routines back to back so you can see all of them now.
    private readonly bool demo;
    private readonly Queue<Routine> demoQueue = new();
    private string loadedPaletteKey = "";
    private double watchCheck = 0.5;
    private Screen? currentScreen;
    /// A menu pick. It skips the blocked-app check for the whole routine, not
    /// just at the start, or the cat would leave again half a second later.
    private bool forced;
    /// Screen off, locked, asleep, or another user switched in. Nobody can see
    /// the cat then, so it stays in and the frame clock does not run for nothing.
    private bool away;
    private DateTime? nextVisitAt;

    // Petting: rest the pointer on the cat and it stops, sits and shows hearts.
    private double petDwell;
    private double petLeft;
    private double petTime;
    /// Must leave the cat before it can be petted again, so a parked pointer
    /// does not hold it still forever.
    private bool petArmed = true;
    private Clip? clipBeforePet;

    // The idle crawl: starts after `idleCrawlSeconds` without input, ends on
    // the first touch or key.
    private double idleCrawlStarted;
    private long idleCrawlStartedTick;
    /// Ignore input this soon after a menu start, or the click that chose it
    /// would end it at once.
    private double idleCrawlGrace;
    /// The window in front when it began, to go back to when you return.
    private IntPtr windowBeforeCrawl;
    private bool switchedApps;
    /// The shrink-away exit has already put you back in your app.
    private bool exitHandled;
    private readonly InputWatch input = new();

    // What the overlay draws besides the cat.
    private Vec? bowlAt;
    private Vec? bubbleTip;
    private double? heartsTime;
    private IReadOnlyList<Breach> breaches = Array.Empty<Breach>();
    private Zap? zap;
    private Aura? aura;
    /// The OK button and the rest-to-accept area, in screen pixels, as last drawn.
    private RectD? okButton;
    private RectD? acceptArea;
    private bool okHovered;
    private double dwellProgress;

    public App(bool demo)
    {
        this.demo = demo;
        Config.WriteDefaultFileIfMissing();
        scene.Config = Config.Load();

        overlay = new OverlayWindow(OverlayWindow.VirtualScreen());
        overlay.Clicked += () =>
        {
            if (behavior is PlayBehavior play && okButton is RectD button && button.Contains(CursorPos())) play.Accepted = true;
        };
        overlay.DisplaysChanged += ScreensChanged;
        overlay.DisplayPower += on =>
        {
            ActivityLog.Shared.DisplayPower(on);
            if (on) ComeBack(); else GoAway();
        };
        LoadSprites();
        ApplyConfig();

        var ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        clock = new FrameClock(ui, Tick);

        menu = BuildMenu();
        tray = new NotifyIcon
        {
            Text = "Screen Cat",
            Icon = MakeTrayIcon(),
            ContextMenuStrip = menu,
            Visible = true,
        };
        // The Mac menu opens on a plain click, so the left button opens it too.
        tray.MouseUp += (_, e) =>
        {
            if (e.Button != MouseButtons.Left) return;
            typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic)?.Invoke(tray, null);
        };

        if (scene.Config.ActivityLog)
        {
            ActivityLog.Shared.CatStatus = CatReport;
            ActivityLog.Shared.Start((int)scene.Config.ActivityLogDays);
        }

        SystemEvents.PowerModeChanged += OnPowerMode;
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.DisplaySettingsChanged += (_, _) => ScreensChanged();

        scheduleTimer.Tick += (_, _) =>
        {
            scheduleTimer.Stop();
            nextVisitAt = null;
            StartRandom();
        };
        idleTimer.Interval = 1000;
        idleTimer.Tick += (_, _) => CheckIdleCrawl();
        idleTimer.Start();

        Schedule(demo ? 2 : scene.Config.FirstAppearanceDelay);
    }

    private double Now => time.Elapsed.TotalSeconds;

    private static Vec CursorPos()
    {
        Native.GetCursorPos(out var p);
        return new Vec(p.X, p.Y);
    }

    // Config ---------------------------------------------------------------

    private void ApplyConfig()
    {
        var c = scene.Config;
        overlay.SetOpacity(c.Opacity);
        // Excluded windows still show on the glass but not in screenshots,
        // recordings or anything being screen-shared.
        overlay.SetHiddenFromCapture(c.HideFromCapture);
    }

    private bool Topmost => !scene.Config.WindowLevel.Equals("floating", StringComparison.OrdinalIgnoreCase);

    /// The sheet is recoloured at load time, so it is only rebuilt when the
    /// colour settings actually change.
    private void LoadSprites()
    {
        var c = scene.Config;
        string key = string.Join("|", c.FurColor, c.FurShadeColor, c.OutlineColor, c.InnerColor, c.EyeColor, c.BallColor);
        if (key == loadedPaletteKey && sheet != null) return;
        var fresh = new SpriteSheet(c.SpritePalette);
        if (!fresh.IsLoaded) return;
        sheet?.Dispose();
        sheet = fresh;
        loadedPaletteKey = key;
    }

    private void ReloadConfig()
    {
        scene.Config = Config.Load();
        ApplyConfig();
        LoadSprites();
    }

    private void ScreensChanged()
    {
        overlay.Resize(OverlayWindow.VirtualScreen());
        // The stage was laid out for the old screen, which may be gone or have
        // moved. Send the cat home and let the next visit lay it out again.
        if (behavior != null)
        {
            StopBehavior();
            if (!paused && !away) Schedule(3);
        }
    }

    private void OnPowerMode(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend) GoAway();
        else if (e.Mode == PowerModes.Resume) ComeBack();
    }

    private void OnSessionSwitch(object? sender, SessionSwitchEventArgs e)
    {
        switch (e.Reason)
        {
            case SessionSwitchReason.SessionLock:
            case SessionSwitchReason.ConsoleDisconnect:
                GoAway();
                break;
            case SessionSwitchReason.SessionUnlock:
            case SessionSwitchReason.ConsoleConnect:
                ComeBack();
                break;
        }
    }

    private void GoAway()
    {
        if (away) return;
        if (behavior is IdleCrawlBehavior) EndIdleCrawl("screen went off");
        away = true;
        StopBehavior();
        scheduleTimer.Stop();
        nextVisitAt = null;
    }

    private void ComeBack()
    {
        if (!away) return;
        away = false;
        if (!paused) Schedule(scene.Config.FirstAppearanceDelay);
    }

    // Tray menu --------------------------------------------------------------

    private ContextMenuStrip BuildMenu()
    {
        var m = new ContextMenuStrip();
        statusItem = new ToolStripMenuItem("Waiting") { Enabled = false };
        m.Items.Add(statusItem);
        m.Items.Add(new ToolStripSeparator());
        // Menu picks force the routine: if you ask for the cat, you get the cat.
        m.Items.Add("Take a walk", null, (_, _) => Start(Routine.Stroll, force: true));
        m.Items.Add("Have a nap", null, (_, _) => Start(Routine.Nap, force: true));
        m.Items.Add("Chase a ball", null, (_, _) => Start(Routine.Ball, force: true));
        m.Items.Add("Beg for food", null, (_, _) => Start(Routine.Hungry, force: true));
        m.Items.Add("Ask to play", null, (_, _) => Start(Routine.Play, force: true));
        m.Items.Add("Break some apps (crawler)", null, (_, _) => Start(Routine.Crawl, force: true));
        m.Items.Add("Crawl until I touch something", null, (_, _) => BeginIdleCrawl(1.0));
        m.Items.Add(new ToolStripSeparator());

        var mode = new ToolStripMenuItem("Mode");
        normalItem = new ToolStripMenuItem("Normal", null, (_, _) => SetMode("normal"));
        crawlerItem = new ToolStripMenuItem("Crawler", null, (_, _) => SetMode("crawler"));
        // Mr. Robot is a show, not a lasting mode: it runs once and the saved
        // mode stays what it was.
        var robot = new ToolStripMenuItem("Mr. Robot (3 min hack, starts now)", null, (_, _) =>
        {
            ActivityLog.Shared.Cat("Mr. Robot started from the menu");
            BeginIdleCrawl(3.2, Routine.MrRobot);
        });
        mode.DropDownItems.AddRange(new ToolStripItem[] { normalItem, crawlerItem, robot });
        m.Items.Add(mode);
        m.Items.Add(new ToolStripSeparator());

        pauseItem = new ToolStripMenuItem("Pause", null, (_, _) => TogglePause());
        m.Items.Add(pauseItem);
        m.Items.Add(new ToolStripSeparator());
        captureItem = new ToolStripMenuItem("Show in screenshots && recordings", null, (_, _) => ToggleCapture());
        m.Items.Add(captureItem);
        loginItem = new ToolStripMenuItem("Open at login", null, (_, _) =>
        {
            LoginItem.SetEnabled(!LoginItem.IsEnabled);
            loginItem.Checked = LoginItem.IsEnabled;
        });
        m.Items.Add(loginItem);
        m.Items.Add(new ToolStripSeparator());
        m.Items.Add("Open today's activity log", null, (_, _) => OpenActivityLog());
        m.Items.Add("Show all activity logs", null, (_, _) => ShowActivityLogs());
        m.Items.Add(new ToolStripSeparator());
        m.Items.Add("Edit settings...", null, (_, _) => EditSettings());
        m.Items.Add("Reload settings", null, (_, _) => ReloadConfig());
        m.Items.Add(new ToolStripSeparator());
        m.Items.Add("Quit Screen Cat", null, (_, _) => Quit());
        m.Opening += (_, _) => MenuWillOpen();
        return m;
    }

    /// Refresh the top line each time the menu opens, so it is obvious why the
    /// cat is or is not showing up.
    private void MenuWillOpen()
    {
        scene.Config = Config.Load();
        captureItem.Checked = !scene.Config.HideFromCapture;
        loginItem.Checked = LoginItem.IsEnabled;
        normalItem.Checked = scene.Config.Mode != "crawler";
        crawlerItem.Checked = scene.Config.Mode == "crawler";
        if (paused)
        {
            statusItem.Text = "Paused";
        }
        else if (away)
        {
            statusItem.Text = "Away while the screen is off";
        }
        else if (Watching.Reason(scene.Config, ScreenRect(TargetScreen())) is string why)
        {
            statusItem.Text = char.ToUpperInvariant(why[0]) + why.Substring(1);
        }
        else if (behavior != null)
        {
            statusItem.Text = "Out and about";
        }
        else if (nextVisitAt is DateTime at)
        {
            statusItem.Text = $"Next visit in {Math.Max(1, (int)Math.Round((at - DateTime.Now).TotalSeconds))}s";
        }
        else
        {
            statusItem.Text = "Waiting for the next visit";
        }
    }

    /// One mode, saved to settings.
    private void SetMode(string mode)
    {
        scene.Config.Mode = mode;
        Config.Update("mode", mode);
        ActivityLog.Shared.Cat($"mode set to {mode}");
    }

    private void TogglePause()
    {
        paused = !paused;
        pauseItem.Text = paused ? "Resume" : "Pause";
        if (paused)
        {
            StopBehavior();
            scheduleTimer.Stop();
            nextVisitAt = null;
        }
        else if (!away)
        {
            Schedule(3);
        }
    }

    /// Ticked means the cat is visible to screen capture. Off, the default,
    /// keeps it out of screenshots, recordings and anything screen shared.
    private void ToggleCapture()
    {
        scene.Config.HideFromCapture = !scene.Config.HideFromCapture;
        Config.Update("hideFromCapture", scene.Config.HideFromCapture);
        ApplyConfig();
        captureItem.Checked = !scene.Config.HideFromCapture;
    }

    private static void OpenPath(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch
        {
            try { Process.Start(new ProcessStartInfo("notepad.exe", $"\"{path}\"") { UseShellExecute = true }); } catch { }
        }
    }

    private static void EditSettings()
    {
        Config.WriteDefaultFileIfMissing();
        // Notepad is always there; a .json file may have no app set up to open it.
        try { Process.Start(new ProcessStartInfo("notepad.exe", $"\"{Config.FilePath}\"") { UseShellExecute = true }); }
        catch { OpenPath(Config.FilePath); }
    }

    private static void OpenActivityLog()
    {
        if (!File.Exists(ActivityLog.TodayPath)) { ShowActivityLogs(); return; }
        OpenPath(ActivityLog.TodayPath);
    }

    private static void ShowActivityLogs()
    {
        try { Directory.CreateDirectory(ActivityLog.Folder); } catch { }
        OpenPath(ActivityLog.Folder);
    }

    private void Quit()
    {
        Dispose();
        Application.Exit();
    }

    /// The tray icon: the cat's first sitting frame, scaled up crisp.
    private Icon MakeTrayIcon()
    {
        var frame = sheet?.Frame(Clip.SitIdle, 0);
        if (frame == null) return SystemIcons.Application;
        int size = SystemInformation.SmallIconSize.Width >= 24 ? 32 : 16;
        using var bmp = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
            // The cat sits in the lower middle of its frame; crop to it.
            g.DrawImage(frame, new Rectangle(0, 0, size, size), new Rectangle(3, 4, 26, 26), GraphicsUnit.Pixel);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    // Screens --------------------------------------------------------------

    /// The screen the cat should use: the one the pointer is on.
    private static Screen TargetScreen()
    {
        var p = CursorPos();
        return Screen.FromPoint(new Point((int)p.X, (int)p.Y));
    }

    private static RectD ScreenRect(Screen s) => new(s.Bounds.X, s.Bounds.Y, s.Bounds.Width, s.Bounds.Height);
    private static RectD WorkRect(Screen s) => new(s.WorkingArea.X, s.WorkingArea.Y, s.WorkingArea.Width, s.WorkingArea.Height);

    /// Physical pixels per logical pixel on `s`: 1 at 100%, 1.5 at 150%.
    private static double ScaleOf(Screen s)
    {
        try
        {
            var mon = Native.MonitorFromPoint(new Native.POINT(s.Bounds.X + s.Bounds.Width / 2, s.Bounds.Y + s.Bounds.Height / 2),
                Native.MONITOR_DEFAULTTONEAREST);
            if (Native.GetDpiForMonitor(mon, 0, out uint dpi, out _) == 0 && dpi > 0) return dpi / 96.0;
        }
        catch { }
        return 1;
    }

    // Idle crawl -------------------------------------------------------------

    private static double SecondsSinceInput() => Native.MillisecondsSinceInput() / 1000.0;

    private void CheckIdleCrawl()
    {
        var c = scene.Config;
        if (!c.IdleCrawl || paused || away || behavior is IdleCrawlBehavior) return;
        if (SecondsSinceInput() < c.IdleCrawlSeconds) return;
        // Two quiet minutes in front of a film is watching, not away.
        if (Watching.Reason(c, ScreenRect(TargetScreen())) != null) return;
        BeginIdleCrawl(0);
    }

    private void BeginIdleCrawl(double grace, Routine routine = Routine.IdleCrawl)
    {
        windowBeforeCrawl = Native.GetForegroundWindow();
        switchedApps = false;
        exitHandled = false;
        idleCrawlStarted = Now;
        idleCrawlStartedTick = Environment.TickCount64;
        idleCrawlGrace = grace;
        ActivityLog.Shared.Cat("idle crawl started");
        Start(routine, force: grace > 0);
    }

    /// True once there has been real input since the crawl began.
    private bool TouchedSinceIdleCrawl()
    {
        double running = Now - idleCrawlStarted;
        if (running <= idleCrawlGrace) return false;
        if (input.Hooked)
        {
            return input.LastRealInput > idleCrawlStartedTick + (long)(idleCrawlGrace * 1000);
        }
        // No hooks (blocked by policy): fall back to the system's last input
        // time, skipping the moment the app tapped a key itself.
        uint ms = Native.MillisecondsSinceInput();
        long inputAt = Environment.TickCount64 - ms;
        if (Math.Abs(inputAt - input.LastInjected) < 300) return false;
        return ms / 1000.0 + 0.05 < running;
    }

    private void EndIdleCrawl(string reason)
    {
        ActivityLog.Shared.Cat($"idle crawl ended: {reason}");
        StopBehavior();
        ReturnToStartApp();
        if (!paused && !away) ScheduleNext();
    }

    /// Put you back in the window you left, if the crawl brought another forward.
    private void ReturnToStartApp()
    {
        if (switchedApps && windowBeforeCrawl != IntPtr.Zero && Native.IsWindow(windowBeforeCrawl))
        {
            BringForward(windowBeforeCrawl);
        }
        windowBeforeCrawl = IntPtr.Zero;
        switchedApps = false;
    }

    /// Brings `hwnd` to the front. Windows only lets the app the user is
    /// using do that, so it first borrows the foreground thread's input state,
    /// and if that is not enough, taps Alt (masked so no menu opens), which is
    /// what Windows itself treats as permission.
    private void BringForward(IntPtr hwnd)
    {
        if (Native.IsIconic(hwnd)) Native.ShowWindow(hwnd, Native.SW_RESTORE);
        var fg = Native.GetForegroundWindow();
        uint fgThread = fg != IntPtr.Zero ? Native.GetWindowThreadProcessId(fg, out _) : 0;
        uint me = Native.GetCurrentThreadId();
        bool attached = fgThread != 0 && fgThread != me && Native.AttachThreadInput(me, fgThread, true);
        try
        {
            Native.BringWindowToTop(hwnd);
            Native.SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attached) Native.AttachThreadInput(me, fgThread, false);
        }
        if (Native.GetForegroundWindow() == hwnd) return;
        input.LastInjected = Environment.TickCount64;
        Native.keybd_event(Native.VK_MENU, 0, 0, UIntPtr.Zero);
        Native.SetForegroundWindow(hwnd);
        // An unassigned key between Alt down and up stops the menu bar opening.
        Native.keybd_event(0xE8, 0, 0, UIntPtr.Zero);
        Native.keybd_event(0xE8, 0, Native.KEYEVENTF_KEYUP, UIntPtr.Zero);
        Native.keybd_event(Native.VK_MENU, 0, Native.KEYEVENTF_KEYUP, UIntPtr.Zero);
        input.LastInjected = Environment.TickCount64;
    }

    /// Apps the crawl may bring forward: each app's front window, visible,
    /// not minimised, not a tool window, not cloaked, not blocked, not tiny,
    /// in name order. Windows on the cat's own screen come first.
    private List<WindowInfo> SwitchableApps()
    {
        var area = ScreenRect(currentScreen ?? TargetScreen());
        var windows = Watching.AppWindows()
            .Where(w => w.Rect.Width >= 300 && w.Rect.Height >= 200 && !Watching.IsBlocked(w.Pid, scene.Config.BlockedApps))
            .ToList();
        var here = windows.Where(w => w.Rect.Intersects(area)).ToList();
        if (here.Count > 0) windows = here;
        // The front-most window of each app stands for the app.
        return windows.GroupBy(w => w.Pid).Select(g => g.First())
            .OrderBy(w => Watching.DisplayName(w.Pid), StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// The edge of the screen: brings the next app forward, in name order in
    /// the cat's direction.
    private bool SwitchToNextApp(double direction)
    {
        var apps = SwitchableApps();
        uint front = Watching.ForegroundPid();
        if (!apps.Any(a => a.Pid != front)) return false;
        WindowInfo? next;
        int i = apps.FindIndex(a => a.Pid == front);
        if (i < 0)
        {
            next = direction > 0 ? apps.First() : apps.Last();
        }
        else
        {
            int step = direction > 0 ? 1 : apps.Count - 1;
            var candidate = apps[(i + step) % apps.Count];
            next = candidate.Pid == front ? null : candidate;
        }
        if (next is not WindowInfo target) return false;
        BringForward(target.Handle);
        switchedApps = true;
        ActivityLog.Shared.Cat($"crawled over to {Watching.DisplayName(target.Pid)}");
        return true;
    }

    /// Mr. Robot's hop: a random app one to three places left or right of the
    /// one in front, so it jumps around rather than stepping through in order.
    private bool SwitchToRandomApp()
    {
        var apps = SwitchableApps();
        if (apps.Count < 2) return false;
        uint front = Watching.ForegroundPid();
        int i = Math.Max(0, apps.FindIndex(a => a.Pid == front));
        int side = Rng.Bool() ? 1 : -1;
        int places = Rng.IntIn(1, Math.Min(3, apps.Count - 1));
        var next = apps[((i + side * places) % apps.Count + apps.Count) % apps.Count];
        if (next.Pid == front) return false;
        BringForward(next.Handle);
        switchedApps = true;
        ActivityLog.Shared.Cat($"hopped to {Watching.DisplayName(next.Pid)} ({places} to the {(side > 0 ? "right" : "left")})");
        return true;
    }

    /// Puts the idle crawl's glitch over the whole of the cat's screen, taskbar
    /// included, and renders it every third frame (20 fps).
    private void UpdateTakeover(IdleCrawlBehavior idle)
    {
        var screen = currentScreen;
        if (screen == null) return;
        var b = screen.Bounds;
        takeoverArea = new RectI(b.Left - overlay.Bounds.X0, b.Top - overlay.Bounds.Y0, b.Right - overlay.Bounds.X0, b.Bottom - overlay.Bounds.Y0);
        if (idle.RecipeIndex != shownRecipe && idle.TakeoverOpacity > 0)
        {
            shownRecipe = idle.RecipeIndex;
            ActivityLog.Shared.Cat($"glitch style: {Takeover.Recipes[idle.RecipeIndex].Name}");
        }
        takeoverFrame++;
        if (takeoverFrame % 3 != 0) return;
        double ui = scene.Ui;
        if (idle.CountdownLeft > 0)
        {
            takeover.Render(Takeover.CountdownRecipe((int)Math.Ceiling(idle.CountdownLeft)), b.Width / ui, b.Height / ui,
                idle.CountdownLeft, 7, 0);
            shownTakeoverOpacity = 1;
            takeoverDirty = true;
            return;
        }
        if (idle.TakeoverOpacity <= 0.01)
        {
            if (takeover.HasFrame)
            {
                takeover.Clear();
                shownTakeoverOpacity = 0;
                takeoverDirty = true;
            }
            return;
        }
        takeover.Render(Takeover.Recipes[idle.RecipeIndex], b.Width / ui, b.Height / ui, idle.StyleTime, idle.StyleSeed, idle.Pulse);
        shownTakeoverOpacity = idle.TakeoverOpacity;
        takeoverDirty = true;
    }

    /// Windows on `screen` worth breaking, in surface-local coordinates: the
    /// ones you can mostly see, from apps not on the blocked list, up to four
    /// of them. Titles are never read.
    private List<RectD> CrawlTargets(Screen screen)
    {
        var area = WorkRect(screen);
        double u = scene.Ui;
        // Front to back. A window whose middle is under one in front of it is
        // mostly hidden, so breaking it would paint over the front one.
        var inFront = new List<RectD>();
        var picked = new List<RectD>();
        foreach (var w in Watching.AppWindows())
        {
            var rect = w.Rect.Intersection(area);
            bool blocked = Watching.IsBlocked(w.Pid, scene.Config.BlockedApps);
            var full = w.Rect;
            if (!blocked && !rect.IsNull && rect.Width >= 200 * u && rect.Height >= 120 * u
                && !inFront.Any(f => f.Contains(new Vec(rect.MidX, rect.MidY))))
            {
                picked.Add(rect);
            }
            inFront.Add(full);
        }
        Rng.Shuffle(picked);
        var toLocal = scene.ToScreen.Inverted();
        return picked.Take(4).Select(r => r.Apply(toLocal)).ToList();
    }

    /// For the activity log on every app switch: is the cat out, and is its
    /// window really shown and on top?
    private string? CatReport()
    {
        if (behavior == null) return null;
        int ex = Native.GetWindowLong(overlay.Handle, Native.GWL_EXSTYLE);
        bool top = (ex & Native.WS_EX_TOPMOST) != 0;
        return $"out on the {scene.Surface.Name()}; window visible: {(Native.IsWindowVisible(overlay.Handle) ? "yes" : "NO")}, topmost: {(top ? "yes" : "NO")}";
    }

    // Scheduling -------------------------------------------------------------

    private void Schedule(double seconds)
    {
        scheduleTimer.Stop();
        double delay = Math.Max(1, seconds);
        nextVisitAt = DateTime.Now.AddSeconds(delay);
        scheduleTimer.Interval = (int)(delay * 1000);
        scheduleTimer.Start();
    }

    private void ScheduleNext()
    {
        if (demo) { Schedule(2); return; }
        var c = scene.Config;
        Schedule(Rng.Range(c.MinGapSeconds, c.MaxGapSeconds));
    }

    private void StartRandom()
    {
        if (away || paused) return;
        // Never wander out over a film. Check again in a minute instead.
        scene.Config = Config.Load();
        if (Watching.Reason(scene.Config, ScreenRect(TargetScreen())) is string why)
        {
            ActivityLog.Shared.Cat($"stayed in: {why}");
            Schedule(60);
            return;
        }
        if (scene.Config.Mode == "crawler" && Rng.Unit() < scene.Config.CrawlChance)
        {
            Start(Routine.Crawl);
            return;
        }
        if (demo)
        {
            if (demoQueue.Count == 0)
            {
                foreach (var r in new[] { Routine.Stroll, Routine.Ball, Routine.Hungry, Routine.Nap }) demoQueue.Enqueue(r);
            }
            Start(demoQueue.Dequeue());
            return;
        }
        var c = scene.Config;
        var table = new (Routine, double)[]
        {
            (Routine.Stroll, Math.Max(0, c.WeightStroll)),
            (Routine.Nap, Math.Max(0, c.WeightNap)),
            (Routine.Ball, Math.Max(0, c.WeightBall)),
            (Routine.Hungry, Math.Max(0, c.WeightHungry)),
            (Routine.Play, Math.Max(0, c.WeightPlay)),
        };
        double total = table.Sum(t => t.Item2);
        if (total <= 0) { ScheduleNext(); return; }
        double roll = Rng.Range(0, total);
        foreach (var (routine, weight) in table)
        {
            roll -= weight;
            if (roll < 0) { Start(routine); return; }
        }
        Start(Routine.Stroll);
    }

    private void Start(Routine requested, bool force = false)
    {
        var routine = requested;
        // One cat at a time: whatever is out now leaves before the next arrives.
        StopBehavior();
        scheduleTimer.Stop();
        nextVisitAt = null;

        var screen = TargetScreen();
        if (!force && Watching.ShouldStayAway(Config.Load(), ScreenRect(screen)))
        {
            Schedule(60);
            return;
        }

        scene.Config = Config.Load();
        ApplyConfig();
        LoadSprites();
        if (sheet == null)
        {
            ScheduleNext();
            return;
        }

        currentScreen = screen;
        scene.Ui = ScaleOf(screen);
        // The working area, not the full bounds: a cat walking behind the
        // taskbar would be half hidden.
        var work = WorkRect(screen);
        scene.Cat.Size = Math.Max(24 * scene.Ui, work.Height / scene.Config.SizeDivisor);
        // Begging and the play invite both face you and need a clickable
        // bubble the right way up, so they stay on the bottom edge. So do the
        // crawls, which zap windows from below.
        bool mayUseWall = routine != Routine.Hungry && routine != Routine.Play && routine != Routine.Crawl
            && routine != Routine.IdleCrawl && routine != Routine.MrRobot
            && Rng.Unit() < scene.Config.WallChance;
        var surface = mayUseWall ? (Rng.Bool() ? Surface.Left : Surface.Right) : Surface.Bottom;
        scene.SetStage(surface, work, scene.Cat.Size);
        if (routine == Routine.IdleCrawl || routine == Routine.MrRobot) scene.CrawlTargets = CrawlTargets(screen);
        if (routine == Routine.Crawl)
        {
            scene.CrawlTargets = CrawlTargets(screen);
            // Nothing to break on this screen: just take a walk.
            if (scene.CrawlTargets.Count == 0) routine = Routine.Stroll;
        }
        scene.Cat.ClipTime = 0;
        scene.Cat.Stride = 0;
        scene.Cat.Depth = 1;
        scene.Ball.Visible = false;
        bowlAt = null;
        bubbleTip = null;

        PlayBehavior.PointerSource = CursorPos;
        behavior = Helpers.MakeBehavior(routine, scene);
        forced = force;
        scene.Cat.Wearing = PickOutfit(scene.Config);
        // A hacker wears shades.
        if (routine is Routine.Crawl or Routine.IdleCrawl or Routine.MrRobot) scene.Cat.Wearing.Add(Accessory.Glasses);
        if (behavior is IdleCrawlBehavior idle)
        {
            idle.RequestTargets = () => CrawlTargets(currentScreen ?? TargetScreen());
            idle.RequestNextApp = SwitchToNextApp;
            idle.RequestRandomApp = SwitchToRandomApp;
            input.Start();
        }
        scene.Cat.Visible = true;
        var outfit = string.Join(" + ", scene.Cat.Wearing.Select(a => a.ToString().ToLowerInvariant()).OrderBy(s => s));
        ActivityLog.Shared.Cat($"came out: {routine.Name()} on the {scene.Surface.Name()} of {screen.DeviceName.TrimStart('\\', '.')}"
            + (outfit.Length == 0 ? "" : $", wearing {outfit}") + (force ? " (menu pick)" : ""));

        overlay.ClearAll();
        overlay.Show(Topmost);
        overlay.SetHiddenFromCapture(scene.Config.HideFromCapture);
        lastDirty = default;
        lastTick = Now;
        watchCheck = 0.5;
        clock.Start();
    }

    private void StopBehavior()
    {
        if (behavior != null) ActivityLog.Shared.Cat("went in");
        clock.Stop();
        input.Stop();
        behavior = null;
        scene.Cat.Visible = false;
        scene.Ball.Visible = false;
        bowlAt = null;
        bubbleTip = null;
        okButton = null;
        acceptArea = null;
        okHovered = false;
        dwellProgress = 0;
        heartsTime = null;
        breaches = Array.Empty<Breach>();
        zap = null;
        aura = null;
        takeover.Clear();
        shownTakeoverOpacity = 0;
        shownRecipe = -1;
        petDwell = 0;
        petLeft = 0;
        petArmed = true;
        clipBeforePet = null;
        forced = false;
        overlay.SetClickThrough(true);
        overlay.ClearAll();
        overlay.Hide();
    }

    // Frame loop -------------------------------------------------------------

    private void Tick()
    {
        if (behavior == null) return;
        try
        {
            TickInner(behavior);
        }
        catch (Exception e)
        {
            // A bug in one routine should send the cat home, not kill the app.
            ActivityLog.Shared.Cat($"routine failed: {e.GetType().Name}: {e.Message}");
            StopBehavior();
            if (!paused && !away) ScheduleNext();
        }
    }

    private void TickInner(IBehavior current)
    {
        double now = Now;
        double dt = Math.Min(0.05, Math.Max(0.001, now - lastTick));
        lastTick = now;

        // A touch or key: the glitch goes at once and the cat shrinks away.
        // Mr. Robot ending on time takes the same exit.
        if (current is IdleCrawlBehavior crawling)
        {
            if (!crawling.IsExiting && TouchedSinceIdleCrawl())
            {
                ActivityLog.Shared.Cat("idle crawl ended: you are back");
                crawling.BeginExit();
            }
            if (crawling.IsExiting && !exitHandled)
            {
                exitHandled = true;
                input.Stop();
                takeover.Clear();
                shownTakeoverOpacity = 0;
                takeoverDirty = true;
                ReturnToStartApp();
            }
        }

        // If a video starts mid-routine, get out of the way at once.
        watchCheck -= dt;
        if (watchCheck <= 0 && !forced)
        {
            watchCheck = 0.5;
            var screen = currentScreen ?? TargetScreen();
            if (Watching.Reason(scene.Config, ScreenRect(screen)) is string why)
            {
                ActivityLog.Shared.Cat($"left early: {why}");
                bool wasIdle = current is IdleCrawlBehavior;
                StopBehavior();
                if (wasIdle) ReturnToStartApp();
                if (!paused) Schedule(60);
                return;
            }
        }

        scene.Cat.Advance(dt);
        bool finished = !UpdatePetting(dt) && current.Update(dt, scene);
        bowlAt = (current as HungryBehavior)?.BowlAt;
        bubbleTip = (current as PlayBehavior)?.BubbleTip;

        // Pointer tracking for the play invite. Resting on the cat or its
        // bubble accepts after a dwell; clicking OK accepts at once. Only the
        // button ever takes clicks, so nothing else is swallowed.
        if (current is PlayBehavior play && acceptArea is RectD area)
        {
            var mouse = CursorPos();
            play.PointerResting = area.Contains(mouse);
            dwellProgress = play.DwellProgress;
            bool overButton = okButton?.Contains(mouse) ?? false;
            okHovered = overButton;
            overlay.SetClickThrough(!overButton);
        }
        else if (okHovered || dwellProgress > 0 || !overlay.ClickThrough)
        {
            okHovered = false;
            dwellProgress = 0;
            overlay.SetClickThrough(true);
        }

        heartsTime = petLeft > 0 ? petTime : null;
        var crawl = current as IBreachSource;
        breaches = crawl?.Breaches ?? Array.Empty<Breach>();
        zap = crawl?.Zap;
        aura = crawl?.Aura;

        // Everything that changed, in local coordinates.
        double u = scene.Ui;
        var dirty = scene.Cat.Bounds;
        foreach (var b in breaches) dirty = dirty.Union(b.Rect.Inset(-6 * u, -6 * u));
        if (zap is Zap z) dirty = dirty.Union(z.Bounds.Inset(-8 * u, -8 * u));
        if (aura is Aura a) dirty = dirty.Union(a.Bounds.Inset(-8 * u, -8 * u));
        if (current is IdleCrawlBehavior idle) UpdateTakeover(idle);
        if (scene.Ball.Visible) dirty = dirty.Union(scene.Ball.Bounds);
        if (bubbleTip is Vec tip)
        {
            // The bubble is much taller than the cat, so it needs its own patch.
            dirty = dirty.Union(new RectD(tip.X - scene.Cat.Size * 4, tip.Y - 8 * u, scene.Cat.Size * 8, scene.Cat.Size * 5));
        }
        if (bowlAt is Vec bowl)
        {
            dirty = dirty.Union(new RectD(bowl.X - scene.Cat.DrawnSize, bowl.Y - 8 * u, scene.Cat.DrawnSize * 2, scene.Cat.DrawnSize));
        }
        // Local -> screen -> window, then repaint both the old and the new spot.
        var onScreen = dirty.Apply(scene.ToScreen).Offset(-overlay.Bounds.X0, -overlay.Bounds.Y0).Inset(-8 * u, -8 * u);
        var now2 = RectI.Around(onScreen);
        var region = now2.Union(lastDirty);
        if (takeoverDirty)
        {
            region = region.Union(takeoverArea);
            takeoverDirty = false;
        }
        Draw(region);
        lastDirty = now2;

        if (finished)
        {
            bool wasIdle = current is IdleCrawlBehavior;
            StopBehavior();
            if (wasIdle) ReturnToStartApp();
            if (!paused) ScheduleNext();
        }
    }

    /// Repaints `region` (window pixels) and pushes it to the screen.
    private void Draw(RectI region)
    {
        var canvas = overlay.Canvas;
        if (canvas == null || sheet == null) return;
        bool glitchOn = takeover.HasFrame && shownTakeoverOpacity > 0.01;
        overlay.PaintBase(region, glitchOn ? takeover.Frame : null, takeoverArea, shownTakeoverOpacity);

        double u = scene.Ui;
        var palette = scene.Config.Extras;
        canvas.ResetState();
        canvas.ClipToDevice(region);
        // Two hops: surface-local -> screen, then screen -> window pixels.
        canvas.Translate(-overlay.Bounds.X0, -overlay.Bounds.Y0);
        canvas.Concat(scene.ToScreen);

        foreach (var b in breaches) Glitch.DrawBreach(b, canvas, u);
        if (bowlAt is Vec bowl) CatArt.DrawFoodBowl(bowl, scene.Cat.PixelScale, palette, 1, canvas);
        if (scene.Ball.Visible) CatArt.DrawBall(scene.Ball, sheet, canvas);
        if (bubbleTip is Vec tip && scene.Cat.Visible)
        {
            var bubble = new SpeechBubble("LET'S PLAY", "OK");
            var drawn = bubble.Draw(tip, Math.Max(2, Math.Round(scene.Cat.Size / 14)), palette, okHovered, dwellProgress, canvas);
            // Drawn in local space; remembered in screen space so the pointer
            // checks do not have to redo the transform.
            okButton = drawn.button.Apply(scene.ToScreen);
            acceptArea = drawn.body.Apply(scene.ToScreen).Union(scene.Cat.Bounds.Apply(scene.ToScreen));
        }
        else
        {
            okButton = null;
            acceptArea = null;
        }
        if (scene.Cat.Visible)
        {
            CatArt.DrawCat(scene.Cat, sheet, scene.Config.Shadow, palette, canvas);
            if (heartsTime is double ht) CatArt.DrawHearts(scene.Cat, ht, palette, canvas);
            if (zap is Zap z) Glitch.DrawZap(z, canvas, u);
            if (aura is Aura a) Glitch.DrawAura(a, canvas, u);
        }
        overlay.Present(region);
    }

    /// Rest the pointer on the cat for `petSeconds` and it stops what it is
    /// doing, sits, and shows two hearts. A sleeping cat stays asleep and just
    /// gets the hearts. Returns true while the pet is on, and the routine is
    /// frozen for that time, ball included. Hover only: no click is taken.
    private bool UpdatePetting(double dt)
    {
        var cat = scene.Cat;
        if (petLeft > 0)
        {
            petLeft -= dt;
            petTime += dt;
            if (petLeft <= 0 && clipBeforePet is Clip before)
            {
                cat.SetClip(before);
                clipBeforePet = null;
            }
            return petLeft > 0;
        }
        // The play invite has its own dwell on the same pointer.
        if (scene.Config.PetSeconds <= 0 || !cat.Visible || behavior is PlayBehavior)
        {
            petDwell = 0;
            return false;
        }
        double size = cat.DrawnSize;
        var body = new RectD(cat.Pos.X - size * 0.6, cat.Pos.Y, size * 1.2, size);
        bool over = body.Apply(scene.ToScreen).Contains(CursorPos());
        if (!over)
        {
            petArmed = true;
            petDwell = 0;
            return false;
        }
        if (!petArmed) return false;
        petDwell += dt;
        if (petDwell < scene.Config.PetSeconds) return false;
        petDwell = 0;
        petArmed = false;
        petLeft = 2.6;
        petTime = 0;
        if (cat.Clip != Clip.Sleep && cat.Clip != Clip.BallPlay && cat.Clip != Clip.LieDown)
        {
            clipBeforePet = cat.Clip;
            cat.SetClip(Clip.SitIdle);
        }
        return true;
    }

    /// Rolls what the cat wears for one visit, so the glasses stay a surprise.
    public static HashSet<Accessory> PickOutfit(Config c)
    {
        var outfit = new HashSet<Accessory>();
        if (Rng.Unit() < c.ChainChance) outfit.Add(Accessory.Chain);
        if (Rng.Unit() < c.GlassesChance) outfit.Add(Accessory.Glasses);
        return outfit;
    }

    private bool disposed;

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        try { StopBehavior(); } catch { }
        ActivityLog.Shared.Stop();
        idleTimer.Stop();
        scheduleTimer.Stop();
        clock.Dispose();
        input.Dispose();
        SystemEvents.PowerModeChanged -= OnPowerMode;
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        tray.Visible = false;
        tray.Dispose();
        menu.Dispose();
        overlay.Dispose();
        takeover.Dispose();
        sheet?.Dispose();
    }
}
