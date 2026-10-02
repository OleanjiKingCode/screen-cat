using System;
using System.Runtime.InteropServices;

namespace ScreenCat;

/// Watches for real keyboard and mouse input while the idle crawl runs.
///
/// Low-level hooks see every event with a flag that says whether software
/// injected it, so the key tap the cat may use to bring an app forward never
/// counts as you coming back. Only real hardware input ends the crawl, the
/// same rule the Mac version keeps.
public sealed class InputWatch : IDisposable
{
    private IntPtr keyboardHook;
    private IntPtr mouseHook;
    private readonly Native.LowLevelProc keyboardProc;
    private readonly Native.LowLevelProc mouseProc;

    /// When real input last arrived, from Environment.TickCount64.
    public long LastRealInput { get; private set; }
    /// When the app last injected input itself, so the fallback can skip it.
    public long LastInjected { get; set; }
    public bool Hooked => keyboardHook != IntPtr.Zero && mouseHook != IntPtr.Zero;

    public InputWatch()
    {
        keyboardProc = OnKeyboard;
        mouseProc = OnMouse;
    }

    public void Start()
    {
        Stop();
        LastRealInput = 0;
        var module = Native.GetModuleHandle(null);
        keyboardHook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, keyboardProc, module, 0);
        mouseHook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, mouseProc, module, 0);
    }

    public void Stop()
    {
        if (keyboardHook != IntPtr.Zero) Native.UnhookWindowsHookEx(keyboardHook);
        if (mouseHook != IntPtr.Zero) Native.UnhookWindowsHookEx(mouseHook);
        keyboardHook = IntPtr.Zero;
        mouseHook = IntPtr.Zero;
    }

    private IntPtr OnKeyboard(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var info = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            if ((info.flags & Native.LLKHF_INJECTED) == 0) LastRealInput = Environment.TickCount64;
        }
        return Native.CallNextHookEx(keyboardHook, code, wParam, lParam);
    }

    private IntPtr OnMouse(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var info = Marshal.PtrToStructure<Native.MSLLHOOKSTRUCT>(lParam);
            if ((info.flags & Native.LLMHF_INJECTED) == 0) LastRealInput = Environment.TickCount64;
        }
        return Native.CallNextHookEx(mouseHook, code, wParam, lParam);
    }

    public void Dispose() => Stop();
}
