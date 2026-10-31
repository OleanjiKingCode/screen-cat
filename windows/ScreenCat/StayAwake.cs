namespace ScreenCat;

/// Stepped out: the PC never goes to sleep and the screen never goes off, for
/// as long as the mode is on.
///
/// One execution-state request, held by the UI thread. `powercfg /requests`
/// lists it under SYSTEM and DISPLAY for ScreenCat.exe. Windows drops it when
/// the app quits or crashes, so a dead cat can never keep the PC awake.
///
/// Closing a laptop lid still does what the lid setting says. That is Windows,
/// not us.
public static class StayAwake
{
    public static bool IsOn { get; private set; }

    /// Call from the UI thread only: the request belongs to the thread that
    /// made it, and the UI thread lives as long as the app.
    public static void Set(bool on)
    {
        if (on == IsOn) return;
        uint flags = on
            ? Native.ES_CONTINUOUS | Native.ES_SYSTEM_REQUIRED | Native.ES_DISPLAY_REQUIRED
            : Native.ES_CONTINUOUS;
        // Zero means Windows refused; the tick then stays as it was.
        if (Native.SetThreadExecutionState(flags) == 0) return;
        IsOn = on;
    }
}
