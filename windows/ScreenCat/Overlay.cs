using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ScreenCat;

/// The transparent, click-through window that the cat lives in. It spans every
/// monitor, never takes focus, and shows a 32-bit premultiplied bitmap through
/// UpdateLayeredWindow, so the cat has soft edges and no box around it.
///
/// Only the parts that changed are pushed to the screen each frame: the cat's
/// old and new spots, or the whole screen when the glitch has a new frame.
public sealed unsafe class OverlayWindow : NativeWindow, IDisposable
{
    /// The virtual screen this window covers, in screen pixels.
    public RectI Bounds { get; private set; }
    public Canvas? Canvas { get; private set; }

    private IntPtr memDc;
    private IntPtr dib;
    private IntPtr oldBitmap;
    private bool shown;
    private bool clickThrough = true;
    private byte constantAlpha = 255;
    private IntPtr displayNotify;

    /// A click on the window. Only possible while it is not click-through,
    /// which is only while the pointer is on the OK button.
    public event Action? Clicked;
    /// Monitors were added, removed, moved or rescaled.
    public event Action? DisplaysChanged;
    /// The display turned off (false) or back on (true).
    public event Action<bool>? DisplayPower;

    public OverlayWindow(RectI bounds)
    {
        var cp = new CreateParams
        {
            Caption = "Screen Cat",
            ClassName = null,
            X = bounds.X0,
            Y = bounds.Y0,
            Width = bounds.Width,
            Height = bounds.Height,
            Style = Native.WS_POPUP,
            ExStyle = Native.WS_EX_LAYERED | Native.WS_EX_TRANSPARENT | Native.WS_EX_TOOLWINDOW
                      | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOPMOST,
        };
        CreateHandle(cp);
        Resize(bounds);
        try
        {
            displayNotify = Native.RegisterPowerSettingNotification(Handle, ref Native.GUID_CONSOLE_DISPLAY_STATE, 0);
        }
        catch
        {
            displayNotify = IntPtr.Zero;
        }
    }

    /// The rectangle that covers every monitor, in screen pixels.
    public static RectI VirtualScreen()
    {
        var v = SystemInformation.VirtualScreen;
        return new RectI(v.Left, v.Top, v.Right, v.Bottom);
    }

    /// Rebuilds the bitmap for a new virtual screen.
    public void Resize(RectI bounds)
    {
        FreeBitmap();
        Bounds = bounds;
        int w = Math.Max(1, bounds.Width), h = Math.Max(1, bounds.Height);
        var screenDc = Native.GetDC(IntPtr.Zero);
        memDc = Native.CreateCompatibleDC(screenDc);
        Native.ReleaseDC(IntPtr.Zero, screenDc);
        var bmi = new Native.BITMAPINFOHEADER
        {
            biSize = (uint)Marshal.SizeOf<Native.BITMAPINFOHEADER>(),
            biWidth = w,
            // Negative height: rows run top down, like the canvas expects.
            biHeight = -h,
            biPlanes = 1,
            biBitCount = 32,
        };
        dib = Native.CreateDIBSection(memDc, ref bmi, 0, out IntPtr bits, IntPtr.Zero, 0);
        oldBitmap = Native.SelectObject(memDc, dib);
        Canvas = new Canvas(w, h, bits, w * 4);
        Native.SetWindowPos(Handle, Native.HWND_TOPMOST, bounds.X0, bounds.Y0, w, h, Native.SWP_NOACTIVATE);
        Present(new RectI(0, 0, w, h));
    }

    private void FreeBitmap()
    {
        Canvas?.Dispose();
        Canvas = null;
        if (memDc != IntPtr.Zero)
        {
            Native.SelectObject(memDc, oldBitmap);
            Native.DeleteDC(memDc);
            memDc = IntPtr.Zero;
        }
        if (dib != IntPtr.Zero)
        {
            Native.DeleteObject(dib);
            dib = IntPtr.Zero;
        }
    }

    /// Pushes the `dirty` part of the bitmap (window pixels) to the screen.
    public void Present(RectI dirty)
    {
        if (Canvas == null || Handle == IntPtr.Zero) return;
        Canvas.Flush();
        dirty = dirty.Intersect(new RectI(0, 0, Canvas.Width, Canvas.Height));
        var dst = new Native.POINT(Bounds.X0, Bounds.Y0);
        var size = new Native.SIZE(Canvas.Width, Canvas.Height);
        var src = new Native.POINT(0, 0);
        var blend = new Native.BLENDFUNCTION
        {
            BlendOp = Native.AC_SRC_OVER,
            SourceConstantAlpha = constantAlpha,
            AlphaFormat = Native.AC_SRC_ALPHA,
        };
        var rc = new Native.RECT(dirty.X0, dirty.Y0, dirty.X1, dirty.Y1);
        var info = new Native.UPDATELAYEREDWINDOWINFO
        {
            cbSize = (uint)Marshal.SizeOf<Native.UPDATELAYEREDWINDOWINFO>(),
            hdcSrc = memDc,
            crKey = 0,
            dwFlags = Native.ULW_ALPHA,
        };
        var dstPtr = Marshal.AllocHGlobal(Marshal.SizeOf<Native.POINT>());
        var sizePtr = Marshal.AllocHGlobal(Marshal.SizeOf<Native.SIZE>());
        var srcPtr = Marshal.AllocHGlobal(Marshal.SizeOf<Native.POINT>());
        var blendPtr = Marshal.AllocHGlobal(Marshal.SizeOf<Native.BLENDFUNCTION>());
        var rcPtr = Marshal.AllocHGlobal(Marshal.SizeOf<Native.RECT>());
        try
        {
            Marshal.StructureToPtr(dst, dstPtr, false);
            Marshal.StructureToPtr(size, sizePtr, false);
            Marshal.StructureToPtr(src, srcPtr, false);
            Marshal.StructureToPtr(blend, blendPtr, false);
            Marshal.StructureToPtr(rc, rcPtr, false);
            info.pptDst = dstPtr;
            info.psize = sizePtr;
            info.pptSrc = srcPtr;
            info.pblend = blendPtr;
            info.prcDirty = dirty.IsEmpty ? IntPtr.Zero : rcPtr;
            if (!Native.UpdateLayeredWindowIndirect(Handle, ref info))
            {
                // Some setups refuse a dirty rect; push the whole bitmap instead.
                Native.UpdateLayeredWindow(Handle, IntPtr.Zero, ref dst, ref size, memDc, ref src, 0, ref blend, Native.ULW_ALPHA);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(dstPtr);
            Marshal.FreeHGlobal(sizePtr);
            Marshal.FreeHGlobal(srcPtr);
            Marshal.FreeHGlobal(blendPtr);
            Marshal.FreeHGlobal(rcPtr);
        }
    }

    /// Clears the whole bitmap and pushes it, so nothing is left from last time.
    public void ClearAll()
    {
        if (Canvas == null) return;
        var all = new RectI(0, 0, Canvas.Width, Canvas.Height);
        Canvas.ClearDevice(all);
        Present(all);
    }

    public void Show(bool topmost)
    {
        Native.SetWindowPos(Handle, topmost ? Native.HWND_TOPMOST : Native.HWND_TOP, Bounds.X0, Bounds.Y0,
            Bounds.Width, Bounds.Height, Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
        shown = true;
    }

    public void Hide()
    {
        if (!shown) return;
        Native.ShowWindow(Handle, Native.SW_HIDE);
        shown = false;
    }

    public bool IsShown => shown;

    /// Overall transparency, 0.1 to 1.
    public void SetOpacity(double opacity) => constantAlpha = (byte)Math.Round(Math.Clamp(opacity, 0.1, 1) * 255);

    /// Keeps the cat out of screenshots, recordings and screen sharing while
    /// still showing it on the glass. Needs Windows 10 version 2004 or later.
    public bool SetHiddenFromCapture(bool hidden)
    {
        return Native.SetWindowDisplayAffinity(Handle, hidden ? Native.WDA_EXCLUDEFROMCAPTURE : Native.WDA_NONE);
    }

    /// Click-through everywhere is the normal state. Turned off only while the
    /// pointer is on the OK button, so that one click can land.
    public void SetClickThrough(bool on)
    {
        if (on == clickThrough) return;
        clickThrough = on;
        int ex = Native.GetWindowLong(Handle, Native.GWL_EXSTYLE);
        ex = on ? ex | Native.WS_EX_TRANSPARENT : ex & ~Native.WS_EX_TRANSPARENT;
        Native.SetWindowLong(Handle, Native.GWL_EXSTYLE, ex);
    }

    public bool ClickThrough => clickThrough;

    protected override void WndProc(ref Message m)
    {
        switch (m.Msg)
        {
            case Native.WM_MOUSEACTIVATE:
                // Never take focus, even when the OK button is clicked.
                m.Result = (IntPtr)Native.MA_NOACTIVATE;
                return;
            case Native.WM_LBUTTONDOWN:
                Clicked?.Invoke();
                m.Result = IntPtr.Zero;
                return;
            case Native.WM_DPICHANGED:
                // The window spans every monitor and must not be resized by
                // Windows when the scale changes; the app lays it out again.
                m.Result = IntPtr.Zero;
                DisplaysChanged?.Invoke();
                return;
            case Native.WM_DISPLAYCHANGE:
                DisplaysChanged?.Invoke();
                break;
            case Native.WM_POWERBROADCAST:
                if ((int)m.WParam == Native.PBT_POWERSETTINGCHANGE && m.LParam != IntPtr.Zero)
                {
                    var setting = Marshal.PtrToStructure<Native.POWERBROADCAST_SETTING>(m.LParam);
                    if (setting.PowerSetting == Native.GUID_CONSOLE_DISPLAY_STATE)
                    {
                        DisplayPower?.Invoke(setting.Data != 0);
                    }
                }
                break;
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        FreeBitmap();
        if (Handle != IntPtr.Zero) DestroyHandle();
    }

    // Compositing --------------------------------------------------------

    /// Resets `area` (window pixels) to what sits under the cat: the glitch,
    /// scaled up from half resolution with nearest-neighbour sampling and faded
    /// by `opacity`, where it covers `glitchArea`, and transparent elsewhere.
    public void PaintBase(RectI area, Canvas? glitch, RectI glitchArea, double opacity)
    {
        var canvas = Canvas;
        if (canvas == null) return;
        area = area.Intersect(new RectI(0, 0, canvas.Width, canvas.Height));
        if (area.IsEmpty) return;
        canvas.ClearDevice(area);
        if (glitch == null || opacity <= 0.01 || glitchArea.IsEmpty) return;
        var inside = area.Intersect(glitchArea);
        if (inside.IsEmpty) return;
        uint k = (uint)Math.Round(Math.Clamp(opacity, 0, 1) * 255);
        int gw = glitch.Width, gh = glitch.Height;
        int sw = glitchArea.Width, sh = glitchArea.Height;
        var srcX = new int[inside.Width];
        for (int i = 0; i < srcX.Length; i++)
        {
            srcX[i] = Math.Min(gw - 1, (int)((long)(inside.X0 + i - glitchArea.X0) * gw / sw));
        }
        for (int y = inside.Y0; y < inside.Y1; y++)
        {
            int sy = Math.Min(gh - 1, (int)((long)(y - glitchArea.Y0) * gh / sh));
            uint* src = (uint*)(glitch.Bits + sy * glitch.Stride);
            uint* dst = (uint*)(canvas.Bits + y * canvas.Stride) + inside.X0;
            if (k == 255)
            {
                for (int i = 0; i < srcX.Length; i++) dst[i] = src[srcX[i]];
                continue;
            }
            for (int i = 0; i < srcX.Length; i++)
            {
                uint p = src[srcX[i]];
                uint a = ((p >> 24) * k + 127) / 255;
                uint r = (((p >> 16) & 0xFF) * k + 127) / 255;
                uint g = (((p >> 8) & 0xFF) * k + 127) / 255;
                uint b = ((p & 0xFF) * k + 127) / 255;
                dst[i] = (a << 24) | (r << 16) | (g << 8) | b;
            }
        }
    }
}
