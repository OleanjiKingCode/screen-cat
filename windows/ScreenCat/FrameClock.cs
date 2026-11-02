using System;
using System.Diagnostics;
using System.Threading;

namespace ScreenCat;

/// A 60 fps tick on the UI thread. The WinForms timer only manages about 64
/// ticks a second at best and often far fewer, so a background thread keeps
/// time and posts each frame to the UI thread, never queueing more than one.
public sealed class FrameClock : IDisposable
{
    private readonly SynchronizationContext ui;
    private readonly Action tick;
    private readonly double interval;
    private Thread? thread;
    private volatile bool running;
    private volatile bool disposed;
    private int pending;
    private bool fineTimer;

    public FrameClock(SynchronizationContext ui, Action tick, double fps = 60)
    {
        this.ui = ui;
        this.tick = tick;
        interval = 1.0 / fps;
    }

    public bool Running => running;

    public void Start()
    {
        if (!fineTimer)
        {
            // Sleep(1) really sleeps about 1 ms only with the fine system timer.
            Native.timeBeginPeriod(1);
            fineTimer = true;
        }
        running = true;
        if (thread != null) return;
        thread = new Thread(Loop) { IsBackground = true, Name = "Screen Cat frame clock" };
        thread.Start();
    }

    public void Stop()
    {
        running = false;
        if (fineTimer)
        {
            Native.timeEndPeriod(1);
            fineTimer = false;
        }
    }

    private void Loop()
    {
        var clock = Stopwatch.StartNew();
        double next = 0;
        while (!disposed)
        {
            if (!running)
            {
                Thread.Sleep(30);
                next = clock.Elapsed.TotalSeconds;
                continue;
            }
            next += interval;
            double now = clock.Elapsed.TotalSeconds;
            // Fell well behind (the PC was busy): start counting again from now.
            if (next < now - interval * 3) next = now + interval;
            while ((now = clock.Elapsed.TotalSeconds) < next)
            {
                double left = next - now;
                Thread.Sleep(left > 0.002 ? 1 : 0);
            }
            if (Interlocked.Exchange(ref pending, 1) == 0)
            {
                ui.Post(_ =>
                {
                    Interlocked.Exchange(ref pending, 0);
                    if (running && !disposed) tick();
                }, null);
            }
        }
    }

    public void Dispose()
    {
        Stop();
        disposed = true;
    }
}
