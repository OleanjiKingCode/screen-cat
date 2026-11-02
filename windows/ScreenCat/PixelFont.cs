using System;
using System.Collections.Generic;

namespace ScreenCat;

/// A 5x7 pixel font, so speech matches the sprites instead of sitting on top of
/// them in Segoe UI. Uppercase only, which is all the cat has to say.
public static class PixelFont
{
    public const int Height = 7;
    public const int GlyphWidth = 5;
    /// One blank column between letters.
    public const int Tracking = 1;

    public static readonly Dictionary<char, string[]> Glyphs = new()
    {
        ['A'] = new[] { "01110", "10001", "10001", "11111", "10001", "10001", "10001" },
        ['B'] = new[] { "11110", "10001", "10001", "11110", "10001", "10001", "11110" },
        ['C'] = new[] { "01111", "10000", "10000", "10000", "10000", "10000", "01111" },
        ['D'] = new[] { "11110", "10001", "10001", "10001", "10001", "10001", "11110" },
        ['E'] = new[] { "11111", "10000", "10000", "11110", "10000", "10000", "11111" },
        ['F'] = new[] { "11111", "10000", "10000", "11110", "10000", "10000", "10000" },
        ['G'] = new[] { "01110", "10001", "10000", "10111", "10001", "10001", "01110" },
        ['H'] = new[] { "10001", "10001", "10001", "11111", "10001", "10001", "10001" },
        ['I'] = new[] { "11111", "00100", "00100", "00100", "00100", "00100", "11111" },
        ['J'] = new[] { "00111", "00010", "00010", "00010", "00010", "10010", "01100" },
        ['K'] = new[] { "10001", "10010", "10100", "11000", "10100", "10010", "10001" },
        ['L'] = new[] { "10000", "10000", "10000", "10000", "10000", "10000", "11111" },
        ['M'] = new[] { "10001", "11011", "10101", "10101", "10001", "10001", "10001" },
        ['N'] = new[] { "10001", "11001", "10101", "10011", "10001", "10001", "10001" },
        ['O'] = new[] { "01110", "10001", "10001", "10001", "10001", "10001", "01110" },
        ['P'] = new[] { "11110", "10001", "10001", "11110", "10000", "10000", "10000" },
        ['Q'] = new[] { "01110", "10001", "10001", "10001", "10101", "10010", "01101" },
        ['R'] = new[] { "11110", "10001", "10001", "11110", "10100", "10010", "10001" },
        ['S'] = new[] { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
        ['T'] = new[] { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
        ['U'] = new[] { "10001", "10001", "10001", "10001", "10001", "10001", "01110" },
        ['V'] = new[] { "10001", "10001", "10001", "10001", "10001", "01010", "00100" },
        ['W'] = new[] { "10001", "10001", "10001", "10101", "10101", "11011", "10001" },
        ['X'] = new[] { "10001", "10001", "01010", "00100", "01010", "10001", "10001" },
        ['Y'] = new[] { "10001", "10001", "01010", "00100", "00100", "00100", "00100" },
        ['Z'] = new[] { "11111", "00001", "00010", "00100", "01000", "10000", "11111" },
        ['\''] = new[] { "00100", "00100", "01000", "00000", "00000", "00000", "00000" },
        ['!'] = new[] { "00100", "00100", "00100", "00100", "00100", "00000", "00100" },
        ['?'] = new[] { "01110", "10001", "00001", "00010", "00100", "00000", "00100" },
        ['.'] = new[] { "00000", "00000", "00000", "00000", "00000", "00000", "00100" },
        [' '] = new[] { "00000", "00000", "00000", "00000", "00000", "00000", "00000" },
        ['0'] = new[] { "01110", "10001", "10011", "10101", "11001", "10001", "01110" },
        ['1'] = new[] { "00100", "01100", "00100", "00100", "00100", "00100", "01110" },
        ['2'] = new[] { "01110", "10001", "00001", "00010", "00100", "01000", "11111" },
        ['3'] = new[] { "11111", "00010", "00100", "00010", "00001", "10001", "01110" },
        ['4'] = new[] { "00010", "00110", "01010", "10010", "11111", "00010", "00010" },
        ['5'] = new[] { "11111", "10000", "11110", "00001", "00001", "10001", "01110" },
        ['6'] = new[] { "00110", "01000", "10000", "11110", "10001", "10001", "01110" },
        ['7'] = new[] { "11111", "00001", "00010", "00100", "01000", "01000", "01000" },
        ['8'] = new[] { "01110", "10001", "10001", "01110", "10001", "10001", "01110" },
        ['9'] = new[] { "01110", "10001", "10001", "01111", "00001", "00010", "01100" },
        [':'] = new[] { "00000", "00100", "00100", "00000", "00100", "00100", "00000" },
        ['('] = new[] { "00010", "00100", "01000", "01000", "01000", "00100", "00010" },
        [')'] = new[] { "01000", "00100", "00010", "00010", "00010", "00100", "01000" },
        ['-'] = new[] { "00000", "00000", "00000", "11111", "00000", "00000", "00000" },
        ['%'] = new[] { "11000", "11001", "00010", "00100", "01000", "10011", "00011" },
        ['/'] = new[] { "00000", "00001", "00010", "00100", "01000", "10000", "00000" },
    };

    /// Width of a rendered string, in font pixels.
    public static int Width(string text)
    {
        int n = text.Length;
        if (n == 0) return 0;
        return n * GlyphWidth + (n - 1) * Tracking;
    }

    /// Draws `text` with its bottom-left corner at `origin`, in y-up space.
    /// `pixel` should already be a whole number so the glyphs stay square.
    public static void Draw(string text, Vec origin, double pixel, Rgba color, Canvas ctx)
    {
        double penX = origin.X;
        foreach (char raw in text.ToUpperInvariant())
        {
            if (Glyphs.TryGetValue(raw, out var rows))
            {
                // Rows are written top first; y-up space wants the bottom first.
                for (int r = 0; r < rows.Length; r++)
                {
                    var row = rows[rows.Length - 1 - r];
                    for (int c = 0; c < row.Length; c++)
                    {
                        if (row[c] != '1') continue;
                        ctx.FillRect(new RectD(penX + c * pixel, origin.Y + r * pixel, pixel, pixel), color);
                    }
                }
            }
            penX += (GlyphWidth + Tracking) * pixel;
        }
    }
}

/// The speech bubble the cat uses to ask for a game, plus the button in it.
public readonly struct SpeechBubble
{
    /// Everything is laid out in font pixels first, then scaled once.
    private const int Padding = 4;
    private const int Gap = 4;
    private const int ButtonPadX = 4;
    private const int ButtonPadY = 2;
    private const int Tail = 4;

    public readonly string Text;
    public readonly string Button;

    public SpeechBubble(string text, string button) { Text = text; Button = button; }

    private int ButtonPixelWidth => PixelFont.Width(Button) + ButtonPadX * 2;
    private int ButtonPixelHeight => PixelFont.Height + ButtonPadY * 2;

    /// Size in font pixels, tail included.
    public (int w, int h) PixelSize
    {
        get
        {
            int contentW = Math.Max(PixelFont.Width(Text), ButtonPixelWidth);
            return (contentW + Padding * 2, Padding * 2 + PixelFont.Height + Gap + ButtonPixelHeight + Tail);
        }
    }

    /// Draws the bubble with the tip of its tail at `tip`, pointing down at the
    /// cat. Returns the button rect for click matching and the whole body rect,
    /// which together with the cat forms the area you can rest the pointer on.
    /// `progress` fills the button as the dwell accumulates, so a thirty second
    /// wait is something you can watch rather than guess at.
    public (RectD button, RectD body) Draw(Vec tip, double pixel, Palette palette, bool hovering, double progress, Canvas ctx)
    {
        double p = Math.Max(2, Math.Round(pixel));
        var size = PixelSize;
        double w = size.w * p;
        double bodyH = (size.h - Tail) * p;
        double originX = Math.Round(tip.X - w / 2);
        double originY = Math.Round(tip.Y + Tail * p);
        var paper = Rgba.White(0.98);

        var body = new RectD(originX, originY, w, bodyH);
        // Border first, then the fill inset by one pixel: a chunky 1px outline.
        ctx.FillRect(body.Inset(-p, -p), palette.Outline);
        ctx.FillRect(body, paper);

        // Tail: a stepped triangle down to the tip, in the same two passes.
        for (int step = 0; step < Tail; step++)
        {
            double half = Tail - step;
            var row = new RectD(Math.Round(tip.X - half * p), originY - (step + 1) * p, Math.Round(half * 2 * p), p);
            ctx.FillRect(row.Inset(-p, 0), palette.Outline);
            ctx.FillRect(row, paper);
        }

        // Text, centred.
        double textW = PixelFont.Width(Text) * p;
        PixelFont.Draw(Text, new Vec(body.MidX - textW / 2, body.MaxY - (Padding + PixelFont.Height) * p), p, palette.Outline, ctx);

        // Button, centred under the text.
        double buttonW = ButtonPixelWidth * p;
        double buttonH = ButtonPixelHeight * p;
        var buttonRect = new RectD(Math.Round(body.MidX - buttonW / 2), Math.Round(body.MinY + Padding * p), buttonW, buttonH);
        ctx.FillRect(buttonRect.Inset(-p, -p), palette.Outline);
        ctx.FillRect(buttonRect, hovering ? Rgba.White(0.94) : Rgba.White(0.88));
        if (progress > 0)
        {
            ctx.FillRect(new RectD(buttonRect.MinX, buttonRect.MinY, Math.Round(buttonRect.Width * Math.Min(progress, 1)), buttonRect.Height), palette.Inner);
        }
        double labelW = PixelFont.Width(Button) * p;
        PixelFont.Draw(Button, new Vec(buttonRect.MidX - labelW / 2, buttonRect.MidY - PixelFont.Height * p / 2), p, palette.Outline, ctx);

        // The button is grown a little, because it is a small target.
        return (buttonRect.Inset(-p * 2, -p * 2), body.Inset(-p, -p));
    }
}
