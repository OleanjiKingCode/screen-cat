using System;
using System.Linq;
using System.Threading;
using System.Windows.Forms;

namespace ScreenCat;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        // `--selftest <folder>` checks the sprites, routines and glitches with
        // nobody at the screen and writes pictures of them. It never takes the
        // single-instance lock, so it works while the cat is out.
        int i = Array.IndexOf(args, "--selftest");
        if (i >= 0)
        {
            string folder = i + 1 < args.Length ? args[i + 1] : "selftest";
            return SelfTest.Run(folder);
        }

        // Only one Screen Cat may run at a time, or you get two cats. Windows
        // drops the mutex when the process exits, even on a crash.
        using var mutex = new Mutex(true, @"Local\ScreenCat.SingleInstance", out bool first);
        if (!first)
        {
            MessageBox.Show("Screen Cat is already running. Look for the cat in the system tray.", "Screen Cat",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());

        // `--demo` plays every routine back to back with a two second gap.
        using var app = new App(demo: args.Contains("--demo"));
        Application.Run(app.Context);
        GC.KeepAlive(mutex);
        return 0;
    }
}
