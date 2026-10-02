using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace ScreenCat;

/// One top-level window, as the crawl and the blocked-app check see it.
public readonly struct WindowInfo
{
    public readonly IntPtr Handle;
    public readonly uint Pid;
    /// Screen pixels, y down.
    public readonly RectD Rect;

    public WindowInfo(IntPtr handle, uint pid, RectD rect) { Handle = handle; Pid = pid; Rect = rect; }
}

/// Decides whether the cat should stay away, and finds the windows it plays
/// with.
///
/// Deliberately dumb: only apps you name in `blockedApps` can banish the cat,
/// and only while they are in front or fullscreen. Everything else gets the
/// cat, which is what you want from a desktop pet.
public static class Watching
{
    /// Video players, by process name. Matched as case-insensitive substrings.
    public static readonly string[] DefaultBlockedApps =
    {
        "vlc",
        "mpc-hc",
        "mpc-be",
        "PotPlayer",
        "mpv",
        "wmplayer",
        "Video.UI",
        "Microsoft.Media.Player",
        "Netflix",
        "Plex",
        "KMPlayer",
        "GOM",
    };

    private static readonly uint MyPid = (uint)Environment.ProcessId;

    private sealed class ProcessEntry
    {
        public string Name = "";
        public string? Path;
        public string Display = "";
        public DateTime Seen;
    }

    private static readonly Dictionary<uint, ProcessEntry> Processes = new();

    private static readonly object ProcessLock = new();

    private static ProcessEntry Entry(uint pid)
    {
        lock (ProcessLock) return EntryLocked(pid);
    }

    private static ProcessEntry EntryLocked(uint pid)
    {
        if (Processes.TryGetValue(pid, out var e) && (DateTime.UtcNow - e.Seen).TotalSeconds < 60) return e;
        e = new ProcessEntry { Seen = DateTime.UtcNow };
        e.Path = Native.ProcessPath(pid);
        e.Name = e.Path != null ? System.IO.Path.GetFileNameWithoutExtension(e.Path) : $"pid {pid}";
        e.Display = e.Name;
        if (e.Path != null)
        {
            try
            {
                var desc = FileVersionInfo.GetVersionInfo(e.Path).FileDescription;
                if (!string.IsNullOrWhiteSpace(desc)) e.Display = desc.Trim();
            }
            catch { }
        }
        Processes[pid] = e;
        if (Processes.Count > 600)
        {
            foreach (var old in Processes.Where(kv => (DateTime.UtcNow - kv.Value.Seen).TotalMinutes > 5).Select(kv => kv.Key).ToList())
            {
                Processes.Remove(old);
            }
        }
        return e;
    }

    /// The executable name without ".exe", such as "vlc".
    public static string ProcessName(uint pid) => Entry(pid).Name;

    /// What the user would call the app, such as "VLC media player".
    public static string DisplayName(uint pid) => Entry(pid).Display;

    public static string? ProcessPath(uint pid) => Entry(pid).Path;

    private static string ClassName(IntPtr hwnd)
    {
        var sb = new StringBuilder(128);
        Native.GetClassName(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    private static readonly HashSet<string> ShellClasses = new(StringComparer.Ordinal)
    {
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow",
        "NotifyIconOverflowWindow", "Xaml_WindowedPopupClass",
    };

    /// Window bounds as drawn, without the invisible resize border Windows 10
    /// and 11 add around most windows.
    public static RectD FrameOf(IntPtr hwnd)
    {
        if (Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_EXTENDED_FRAME_BOUNDS, out Native.RECT r,
                System.Runtime.InteropServices.Marshal.SizeOf<Native.RECT>()) == 0)
        {
            return r.ToRectD();
        }
        Native.GetWindowRect(hwnd, out r);
        return r.ToRectD();
    }

    public static bool IsCloaked(IntPtr hwnd)
    {
        return Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0;
    }

    /// App windows you can see, front to back: visible, not minimised, not
    /// cloaked (hidden on another virtual desktop or suspended), not tool
    /// windows, not the desktop or taskbar, and not ours. Titles are never read.
    public static List<WindowInfo> AppWindows(bool includeMinimised = false)
    {
        var list = new List<WindowInfo>();
        Native.EnumWindows((hwnd, _) =>
        {
            if (!Native.IsWindowVisible(hwnd)) return true;
            if (!includeMinimised && Native.IsIconic(hwnd)) return true;
            int ex = Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE);
            if ((ex & Native.WS_EX_TOOLWINDOW) != 0 && (ex & Native.WS_EX_APPWINDOW) == 0) return true;
            if (Native.GetWindow(hwnd, Native.GW_OWNER) != IntPtr.Zero && (ex & Native.WS_EX_APPWINDOW) == 0) return true;
            if (IsCloaked(hwnd)) return true;
            if (ShellClasses.Contains(ClassName(hwnd))) return true;
            Native.GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == MyPid || pid == 0) return true;
            var rect = FrameOf(hwnd);
            if (rect.Width < 2 || rect.Height < 2) return true;
            list.Add(new WindowInfo(hwnd, pid, rect));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    /// The process of the window in front. A Store app is hosted by
    /// ApplicationFrameHost, so the real app is found among its children.
    public static uint ForegroundPid()
    {
        var hwnd = Native.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return 0;
        Native.GetWindowThreadProcessId(hwnd, out uint pid);
        if (!ProcessName(pid).Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase)) return pid;
        uint real = pid;
        Native.EnumChildWindows(hwnd, (child, _) =>
        {
            Native.GetWindowThreadProcessId(child, out uint cpid);
            if (cpid != pid && cpid != 0) { real = cpid; return false; }
            return true;
        }, IntPtr.Zero);
        return real;
    }

    private static bool Matches(string name, IEnumerable<string> blocked)
        => blocked.Any(b => !string.IsNullOrWhiteSpace(b) && name.Contains(b.Trim(), StringComparison.OrdinalIgnoreCase));

    public static bool IsBlocked(uint pid, IEnumerable<string> blocked) => pid != 0 && Matches(ProcessName(pid), blocked);

    /// True when the app in front is one the cat should not walk over.
    public static bool FrontmostIsBlocked(IEnumerable<string> blocked) => IsBlocked(ForegroundPid(), blocked);

    /// One of the blocked apps filling the whole of `screen` (its full bounds,
    /// taskbar included), which is what separates true fullscreen from a
    /// merely maximised window.
    public static uint? FullscreenHolder(IEnumerable<string> blocked, RectD screen)
    {
        foreach (var w in AppWindows())
        {
            if (w.Rect.Width >= screen.Width - 2 && w.Rect.Height >= screen.Height - 2 && w.Rect.Intersects(screen)
                && IsBlocked(w.Pid, blocked))
            {
                return w.Pid;
            }
        }
        return null;
    }

    public static bool ShouldStayAway(Config config, RectD screen) => Reason(config, screen) != null;

    /// A human-readable reason, or null if the cat is free to come out.
    /// Only apps on `blockedApps` can keep the cat away, and only when they are
    /// in front or fullscreen.
    public static string? Reason(Config config, RectD screen)
    {
        if (!config.HideWhileWatching) return null;
        uint front = ForegroundPid();
        if (IsBlocked(front, config.BlockedApps))
        {
            return $"hiding: {DisplayName(front)} is in front";
        }
        if (FullscreenHolder(config.BlockedApps, screen) is uint pid)
        {
            return $"hiding: {DisplayName(pid)} is fullscreen";
        }
        return null;
    }

    /// True when some window of `pid` covers a whole monitor.
    public static bool IsFullscreen(uint pid)
    {
        var screens = System.Windows.Forms.Screen.AllScreens;
        foreach (var w in AppWindows())
        {
            if (w.Pid != pid) continue;
            foreach (var s in screens)
            {
                var b = s.Bounds;
                if (w.Rect.Width >= b.Width - 2 && w.Rect.Height >= b.Height - 2) return true;
            }
        }
        return false;
    }
}
