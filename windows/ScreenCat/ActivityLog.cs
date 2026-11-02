using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace ScreenCat;

/// A plain-text diary of what happens on this PC, one file per day in
/// %LOCALAPPDATA%\ScreenCat\Logs. It records which app is in front and for how
/// long, apps and background programs starting and quitting, sleep, wake, lock
/// and idle, Bluetooth on or off, hourly lists of everything running, and what
/// the cat did, including whether it was really on screen when you switched
/// apps.
///
/// Nothing leaves the machine. No window titles, no keystrokes, no screen
/// contents: only app names, process names and times.
public sealed class ActivityLog
{
    public static readonly ActivityLog Shared = new();

    /// Asked on every app switch. Returns a line about the cat, or null when it
    /// is not out.
    public Func<string?>? CatStatus;

    private bool started;
    private string? lastBluetooth;
    private (string name, DateTime since)? frontmost;
    private DateTime? idleSince;
    private readonly List<System.Windows.Forms.Timer> timers = new();
    private const double IdleThreshold = 300;
    private IntPtr foregroundHook;
    private Native.WinEventProc? foregroundProc;
    private uint lastForegroundPid;
    /// Process ids seen last poll, and whether each had a window.
    private Dictionary<uint, (string name, bool windowed)> knownProcesses = new();
    private object? bluetoothRadio;

    public static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScreenCat", "Logs");

    public static string TodayPath => Path.Combine(Folder, $"activity-{DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)}.txt");

    public void Start(int keepDays)
    {
        if (started) return;
        started = true;
        try { Directory.CreateDirectory(Folder); } catch { }
        Prune(keepDays);
        Write("START", $"Screen Cat started ({Environment.OSVersion.VersionString})");

        SystemEvents.PowerModeChanged += OnPower;
        SystemEvents.SessionSwitch += OnSession;
        SystemEvents.SessionEnding += (_, _) => { CloseFrontmost(); Write("POWER", "shutting down, restarting or signing out"); };

        // Foreground changes arrive as they happen, so nothing polls for them.
        foregroundProc = (_, _, _, _, _, _, _) => ForegroundChanged();
        foregroundHook = Native.SetWinEventHook(Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND,
            IntPtr.Zero, foregroundProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);

        uint front = Watching.ForegroundPid();
        if (front != 0)
        {
            lastForegroundPid = front;
            frontmost = (Watching.DisplayName(front), DateTime.Now);
            Write("APP", $"in front: {Watching.DisplayName(front)}");
        }
        knownProcesses = ScanProcesses();
        Snapshot("at start");
        StartBluetooth();

        AddTimer(30_000, CheckIdle);
        // Listing processes takes a moment, so it runs off the UI thread and
        // never makes the cat stutter.
        AddTimer(3_600_000, () => InBackground(() => Snapshot("hourly")));
        AddTimer(5_000, () => InBackground(CheckProcesses));
    }

    private void AddTimer(int ms, Action action)
    {
        var t = new System.Windows.Forms.Timer { Interval = ms };
        t.Tick += (_, _) =>
        {
            try { action(); } catch { }
        };
        t.Start();
        timers.Add(t);
    }

    private int backgroundBusy;

    private void InBackground(Action work)
    {
        if (System.Threading.Interlocked.Exchange(ref backgroundBusy, 1) == 1) return;
        Task.Run(() =>
        {
            try { work(); }
            catch { }
            finally { System.Threading.Interlocked.Exchange(ref backgroundBusy, 0); }
        });
    }

    /// Something the cat did: came out, went in, or hid and why.
    public void Cat(string message)
    {
        if (!started) return;
        Write("CAT", message);
    }

    public void Stop()
    {
        if (!started) return;
        CloseFrontmost();
        Write("STOP", "Screen Cat quit");
        foreach (var t in timers) t.Stop();
        if (foregroundHook != IntPtr.Zero) Native.UnhookWinEvent(foregroundHook);
        SystemEvents.PowerModeChanged -= OnPower;
        SystemEvents.SessionSwitch -= OnSession;
    }

    // Apps ------------------------------------------------------------------

    private void ForegroundChanged()
    {
        uint pid = Watching.ForegroundPid();
        if (pid == 0 || pid == lastForegroundPid) return;
        lastForegroundPid = pid;
        string name = Watching.DisplayName(pid);
        string line = $"in front: {name}";
        if (frontmost is var (prevName, since) && prevName != name)
        {
            line += $"  (after {prevName} for {Duration(DateTime.Now - since)})";
        }
        if (Watching.IsFullscreen(pid)) line += "  [fullscreen]";
        frontmost = (name, DateTime.Now);
        Write("APP", line);
        if (CatStatus?.Invoke() is string cat) Write("CAT", cat);
    }

    private void CloseFrontmost()
    {
        if (frontmost is not var (name, since)) return;
        Write("APP", $"{name} was in front for {Duration(DateTime.Now - since)}");
    }

    /// Every process in this sign-in session, with whether it shows a window.
    /// System processes under the Windows folder are left out; there are
    /// dozens and they never change.
    private Dictionary<uint, (string name, bool windowed)> ScanProcesses()
    {
        var windowed = new HashSet<uint>(Watching.AppWindows(includeMinimised: true).Select(w => w.Pid));
        int session = Process.GetCurrentProcess().SessionId;
        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var result = new Dictionary<uint, (string, bool)>();
        foreach (var p in Process.GetProcesses())
        {
            try
            {
                uint pid = (uint)p.Id;
                if (pid == Environment.ProcessId || p.SessionId != session) continue;
                var path = Watching.ProcessPath(pid);
                bool isWindowed = windowed.Contains(pid);
                if (!isWindowed && (path == null || path.StartsWith(windows, StringComparison.OrdinalIgnoreCase))) continue;
                result[pid] = (Watching.DisplayName(pid), isWindowed);
            }
            catch
            {
                // Gone already, or not ours to read.
            }
            finally
            {
                p.Dispose();
            }
        }
        return result;
    }

    /// Logs apps and background programs as they start and quit.
    private void CheckProcesses()
    {
        var now = ScanProcesses();
        foreach (var (pid, info) in now)
        {
            if (!knownProcesses.TryGetValue(pid, out var before))
            {
                Write(info.windowed ? "OPENED" : "BG-START", info.name);
            }
            else if (info.windowed && !before.windowed)
            {
                Write("OPENED", info.name);
            }
        }
        foreach (var (pid, info) in knownProcesses)
        {
            if (!now.ContainsKey(pid)) Write(info.windowed ? "QUIT" : "BG-STOP", info.name);
        }
        knownProcesses = now;
    }

    // Sleep, lock, idle --------------------------------------------------------

    private void OnPower(object? sender, PowerModeChangedEventArgs e)
    {
        switch (e.Mode)
        {
            case PowerModes.Suspend:
                CloseFrontmost();
                Write("SLEEP", "PC going to sleep");
                break;
            case PowerModes.Resume:
                Write("WAKE", "PC woke up");
                uint front = Watching.ForegroundPid();
                if (front != 0) frontmost = (Watching.DisplayName(front), DateTime.Now);
                Snapshot("after wake");
                break;
        }
    }

    private void OnSession(object? sender, SessionSwitchEventArgs e)
    {
        switch (e.Reason)
        {
            case SessionSwitchReason.SessionLock: Write("LOCK", "screen locked"); break;
            case SessionSwitchReason.SessionUnlock: Write("LOCK", "screen unlocked"); break;
            case SessionSwitchReason.ConsoleDisconnect: Write("USER", "switched to another user"); break;
            case SessionSwitchReason.ConsoleConnect: Write("USER", "back to this user"); break;
            case SessionSwitchReason.RemoteConnect: Write("USER", "remote session connected"); break;
            case SessionSwitchReason.RemoteDisconnect: Write("USER", "remote session disconnected"); break;
        }
    }

    public void DisplayPower(bool on)
    {
        if (started) Write("DISPLAY", on ? "screen turned on" : "screen turned off");
    }

    /// No keyboard or mouse input for five minutes counts as idle.
    private void CheckIdle()
    {
        double idle = Native.MillisecondsSinceInput() / 1000.0;
        if (idle >= IdleThreshold && idleSince == null)
        {
            var since = DateTime.Now.AddSeconds(-idle);
            idleSince = since;
            Write("IDLE", $"no input since {since.ToString("HH:mm:ss", CultureInfo.InvariantCulture)}");
        }
        else if (idle < IdleThreshold && idleSince is DateTime s)
        {
            idleSince = null;
            Write("IDLE", $"back after {Duration(DateTime.Now - s)} away");
        }
    }

    // Bluetooth ---------------------------------------------------------------

    /// Reads the Bluetooth radio through Windows.Devices.Radios and logs it as
    /// it changes. PCs without a radio, or where Windows will not say, log
    /// that once instead.
    private async void StartBluetooth()
    {
        try
        {
            var radios = await Windows.Devices.Radios.Radio.GetRadiosAsync();
            var radio = radios.FirstOrDefault(r => r.Kind == Windows.Devices.Radios.RadioKind.Bluetooth);
            if (radio == null)
            {
                Write("BLUETOOTH", "not available on this PC");
                return;
            }
            bluetoothRadio = radio;
            ReportBluetooth(radio.State);
            var ui = System.Threading.SynchronizationContext.Current;
            radio.StateChanged += (r, _) =>
            {
                var state = r.State;
                if (ui != null) ui.Post(_ => ReportBluetooth(state), null);
                else ReportBluetooth(state);
            };
        }
        catch (Exception e)
        {
            Write("BLUETOOTH", $"unknown ({e.GetType().Name})");
        }
    }

    private void ReportBluetooth(Windows.Devices.Radios.RadioState state)
    {
        string text = state switch
        {
            Windows.Devices.Radios.RadioState.On => "on",
            Windows.Devices.Radios.RadioState.Off => "off",
            Windows.Devices.Radios.RadioState.Disabled => "disabled",
            _ => "unknown",
        };
        if (text == lastBluetooth) return;
        lastBluetooth = text;
        Write("BLUETOOTH", text);
    }

    // What is running ---------------------------------------------------------

    /// Every open app, every background program, and your own command-line
    /// processes (node, python, docker and the like).
    private void Snapshot(string when)
    {
        var procs = ScanProcesses();
        var open = Grouped(procs.Values.Where(p => p.windowed).Select(p => p.name));
        var background = new List<string>();
        var tools = new List<string>();
        foreach (var (pid, info) in procs)
        {
            if (info.windowed) continue;
            var path = Watching.ProcessPath(pid);
            if (path != null && IsConsoleProgram(path)) tools.Add(Watching.ProcessName(pid));
            else background.Add(info.name);
        }
        var bg = Grouped(background);
        var cli = Grouped(tools);
        Write("RUNNING", $"{when}: {open.Count} open apps: {string.Join(", ", open)}");
        Write("RUNNING", $"{when}: {bg.Count} background apps: {string.Join(", ", bg)}");
        Write("RUNNING", $"{when}: {cli.Count} command-line processes: {(cli.Count == 0 ? "none" : string.Join(", ", cli))}");
        if (lastBluetooth != null) Write("BLUETOOTH", $"{lastBluetooth} ({when})");
    }

    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, bool> ConsoleCache = new(StringComparer.OrdinalIgnoreCase);

    /// True when the executable is a console program, read from its PE header.
    private static bool IsConsoleProgram(string path)
    {
        if (ConsoleCache.TryGetValue(path, out var hit)) return hit;
        bool console = false;
        try
        {
            using var f = File.OpenRead(path);
            using var r = new BinaryReader(f);
            f.Position = 0x3C;
            int pe = r.ReadInt32();
            // Signature (4) + file header (20), then the subsystem sits 68
            // bytes into the optional header.
            f.Position = pe + 4 + 20 + 68;
            ushort subsystem = r.ReadUInt16();
            console = subsystem == 3;
        }
        catch { }
        ConsoleCache[path] = console;
        return console;
    }

    /// Sorted, with repeats folded into "name x3".
    private static List<string> Grouped(IEnumerable<string> names)
    {
        var counts = new Dictionary<string, int>();
        foreach (var n in names) counts[n] = counts.TryGetValue(n, out var c) ? c + 1 : 1;
        return counts.Keys.OrderBy(k => k, StringComparer.OrdinalIgnoreCase)
            .Select(k => counts[k] > 1 ? $"{k} x{counts[k]}" : k).ToList();
    }

    // Writing -------------------------------------------------------------------

    private static string Duration(TimeSpan span)
    {
        int s = (int)Math.Round(span.TotalSeconds);
        if (s < 60) return $"{s}s";
        if (s < 3600) return $"{s / 60}m {s % 60}s";
        return $"{s / 3600}h {(s % 3600) / 60}m";
    }

    private readonly object writeLock = new();

    private void Write(string kind, string message)
    {
        lock (writeLock)
        {
            WriteLocked(kind, message);
        }
    }

    private void WriteLocked(string kind, string message)
    {
        try
        {
            var now = DateTime.Now;
            string line = $"{now.ToString("HH:mm:ss", CultureInfo.InvariantCulture)}  {kind.PadRight(10)}{message}\r\n";
            string path = TodayPath;
            if (!File.Exists(path))
            {
                Directory.CreateDirectory(Folder);
                string header = $"Screen Cat activity log for {now.ToString("dddd d MMMM yyyy", CultureInfo.InvariantCulture)}\r\n\r\n";
                File.WriteAllText(path, header);
            }
            File.AppendAllText(path, line);
        }
        catch
        {
            // A log that cannot be written is not worth stopping the cat for.
        }
    }

    /// Deletes day files older than `keepDays`.
    private static void Prune(int keepDays)
    {
        if (keepDays <= 0) return;
        try
        {
            var cutoff = DateTime.Now.AddDays(-keepDays);
            foreach (var file in Directory.GetFiles(Folder, "activity-*.txt"))
            {
                if (File.GetLastWriteTime(file) < cutoff) File.Delete(file);
            }
        }
        catch { }
    }
}
