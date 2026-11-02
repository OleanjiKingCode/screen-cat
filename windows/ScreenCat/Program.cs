using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
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

        // `--zeroday-sound <file.wav> [seconds]` writes Zero Day's sound to a file.
        i = Array.IndexOf(args, "--zeroday-sound");
        if (i >= 0)
        {
            string path = i + 1 < args.Length ? args[i + 1] : "zeroday.wav";
            double seconds = i + 2 < args.Length && double.TryParse(args[i + 2], NumberStyles.Float, CultureInfo.InvariantCulture, out var s) ? s : 10;
            var (peak, rms) = ZeroDaySound.WriteSample(path, Math.Clamp(seconds, 1, 600));
            Print($"wrote {path}: {seconds:0}s, peak {peak:0.000}, rms {rms:0.000}");
            return 0;
        }

        // `--ask <text>` or `--ask-image <file>` sends one question through LLM
        // mode's asker, with the real settings, and prints the answer. No cat,
        // no card.
        int text = Array.IndexOf(args, "--ask"), image = Array.IndexOf(args, "--ask-image");
        if (text >= 0 && text + 1 < args.Length) return AskOnce(new Question.Text(args[text + 1]));
        if (image >= 0 && image + 1 < args.Length)
        {
            byte[]? png = null;
            try
            {
                using var ms = new MemoryStream(File.ReadAllBytes(args[image + 1]));
                using var picture = Image.FromStream(ms);
                png = Asker.PngForUpload(picture);
            }
            catch { }
            if (png == null)
            {
                Print($"could not read {args[image + 1]}");
                return 1;
            }
            return AskOnce(new Question.Image(png, "screenshot"));
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

    private static int AskOnce(Question question)
    {
        // No message loop here, so the answer arrives on a pool thread.
        var asker = new Asker();
        var started = Stopwatch.StartNew();
        using var finished = new ManualResetEventSlim();
        asker.Ask(question, Config.Load(), answer =>
        {
            Print(answer switch
            {
                Answer.Text t => t.Value,
                Answer.Failed f => $"FAILED: {f.Why}",
                _ => "",
            });
            Print($"({started.Elapsed.TotalSeconds:0.0}s)");
            finished.Set();
        });
        finished.Wait();
        return 0;
    }

    private static StreamWriter? console;

    /// A windowed exe has no console of its own, so it borrows the terminal it
    /// was started from.
    private static void Print(string line)
    {
        if (console == null)
        {
            Native.AttachConsole(-1);
            try { console = new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true }; } catch { return; }
        }
        console.WriteLine(line);
    }
}
