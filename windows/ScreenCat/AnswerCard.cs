using System;
using System.Drawing;
using System.Windows.Forms;

namespace ScreenCat;

/// The card the cat sits under in LLM mode, with the answer in it. A small
/// borderless window rather than paint on the overlay, so the text can be
/// selected, scrolled and copied. It shows without taking focus from your
/// app, and it follows the same screenshot setting as the cat.
public sealed class AnswerCard : Form
{
    /// The card was closed by you or timed out. Not called by `Dismiss()`.
    public Action? OnClosedByUser;
    /// The answer was put on the clipboard, by the button or automatically.
    public Action? OnCopy;
    public string Answer { get; private set; } = "";

    private const int CardWidth = 380;
    private const int MaxTextHeight = 320;
    private readonly Color ink;
    private readonly Color paper = Color.FromArgb(250, 250, 250);
    private readonly Label heading = new();
    private readonly Label copyButton = new();
    private readonly Label closeButton = new();
    private readonly TextBox body = new();
    private readonly System.Windows.Forms.Timer thinkingTimer = new() { Interval = 400 };
    private readonly System.Windows.Forms.Timer closeTimer = new() { Interval = 1000 };
    private readonly System.Windows.Forms.Timer copiedTimer = new() { Interval = 1200 };
    private int dots;
    private double secondsLeft;
    private Point anchor;
    private Rectangle area;
    /// Pixels per logical pixel on the cat's screen.
    private double ui = 1;
    private Font? bodyFont;
    private Font? labelFont;
    private readonly ToolTip tips = new();
    private bool topmost = true;

    public AnswerCard(Rgba outline)
    {
        ink = Color.FromArgb(ToByte(outline.R), ToByte(outline.G), ToByte(outline.B));
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        BackColor = paper;
        Text = "Screen Cat answer";

        foreach (var label in new[] { heading, copyButton, closeButton })
        {
            label.AutoSize = true;
            label.ForeColor = ink;
            label.BackColor = paper;
        }
        copyButton.Text = "COPY";
        copyButton.Cursor = Cursors.Hand;
        copyButton.Click += (_, _) => CopyAnswer();
        closeButton.Text = "✕";
        closeButton.Cursor = Cursors.Hand;
        closeButton.Click += (_, _) => CloseByUser();
        tips.SetToolTip(closeButton, "Close (Esc)");

        body.ReadOnly = true;
        body.Multiline = true;
        body.WordWrap = true;
        body.BorderStyle = BorderStyle.None;
        body.BackColor = paper;
        body.ForeColor = ink;
        body.TabStop = false;
        Controls.AddRange(new Control[] { heading, copyButton, closeButton, body });

        // Drag the card by its background or heading, like the Mac's.
        MouseDown += DragCard;
        heading.MouseDown += DragCard;

        thinkingTimer.Tick += (_, _) =>
        {
            dots = (dots + 1) % 4;
            heading.Text = "THINKING" + new string('.', dots);
        };
        closeTimer.Tick += (_, _) =>
        {
            if (Bounds.Contains(Cursor.Position)) return;
            secondsLeft -= 1;
            if (secondsLeft <= 0) CloseByUser();
        };
        copiedTimer.Tick += (_, _) =>
        {
            copiedTimer.Stop();
            copyButton.Text = "COPY";
        };
    }

    private static int ToByte(double v) => (int)Math.Round(Math.Clamp(v, 0, 1) * 255);

    /// A text box ignores alpha, so faded ink is mixed with the paper instead.
    private static Color Blend(Color a, Color b, double t) => Color.FromArgb(
        (int)Math.Round(a.R + (b.R - a.R) * t), (int)Math.Round(a.G + (b.G - a.G) * t), (int)Math.Round(a.B + (b.B - a.B) * t));

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            // No taskbar button and no Alt+Tab entry.
            cp.ExStyle |= Native.WS_EX_TOOLWINDOW;
            return cp;
        }
    }

    /// COPY and the cross work without taking focus from your app. A click on
    /// the text does take it, so you can select and copy part of the answer.
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_MOUSEACTIVATE && Visible)
        {
            var at = PointToClient(Cursor.Position);
            if ((copyButton.Visible && copyButton.Bounds.Contains(at)) || closeButton.Bounds.Contains(at))
            {
                m.Result = (IntPtr)Native.MA_NOACTIVATE;
                return;
            }
        }
        base.WndProc(ref m);
    }

    /// The card lays itself out in pixels for the cat's screen, so WinForms
    /// must not scale it again when it lands on a screen with another scale.
    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        e.Cancel = true;
        base.OnDpiChanged(e);
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == Keys.Escape)
        {
            CloseByUser();
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    /// The cat's speech bubble, grown up: off-white with a chunky outline.
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        int line = Math.Max(2, (int)Math.Round(3 * ui));
        using var pen = new Pen(ink, line) { Alignment = System.Drawing.Drawing2D.PenAlignment.Inset };
        e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
    }

    private void DragCard(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        Native.ReleaseCapture();
        Native.SendMessage(Handle, Native.WM_NCLBUTTONDOWN, (IntPtr)Native.HTCAPTION, IntPtr.Zero);
    }

    /// Topmost or not, and in screenshots or not, the same as the cat.
    public void Follow(bool topmost, bool hideFromCapture)
    {
        this.topmost = topmost;
        Native.SetWindowDisplayAffinity(Handle, hideFromCapture ? Native.WDA_EXCLUDEFROMCAPTURE : Native.WDA_NONE);
        Raise();
    }

    private void Raise() => Native.SetWindowPos(Handle, topmost ? Native.HWND_TOPMOST : Native.HWND_NOTOPMOST, 0, 0, 0, 0,
        Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);

    /// Shows the card above `anchor` (screen pixels, the top of the cat's
    /// head) while the answer is on its way, with what was asked in grey.
    public void ShowThinking(Question question, Point anchor, Rectangle screen, double scale)
    {
        this.anchor = anchor;
        area = screen;
        SetScale(scale);
        StopTimers();
        Answer = "";
        copyButton.Visible = false;
        string asked = question switch
        {
            Question.Text t => Shorten(t.Value.Replace("\r", "").Replace("\n", " ")),
            Question.Image i => i.From == "screenshot" ? "Your screenshot" : "Your copied image",
            _ => "",
        };
        SetBody(asked, Blend(ink, paper, 0.45));
        dots = 0;
        heading.Text = "THINKING";
        thinkingTimer.Start();
        if (Visible) return;
        Show();
        // Above the cat's window, which went to the top when the cat came out.
        Raise();
    }

    private static string Shorten(string line) => line.Length > 160 ? line.Substring(0, 160) + "…" : line;

    /// The answer, and a countdown to close it. Resting the pointer on the
    /// card holds the countdown, so it never vanishes while you read.
    public void ShowAnswer(string text, double closeAfter)
    {
        StopTimers();
        Answer = text;
        heading.Text = "ANSWER";
        copyButton.Visible = true;
        SetBody(text, ink);
        StartCloseTimer(closeAfter);
    }

    public void ShowError(string text, double closeAfter)
    {
        StopTimers();
        Answer = "";
        heading.Text = "NO ANSWER";
        copyButton.Visible = false;
        SetBody(text, Color.FromArgb(179, 31, 51));
        StartCloseTimer(closeAfter);
    }

    /// Takes the card away without telling anyone: the cat is already going.
    public void Dismiss()
    {
        StopTimers();
        Hide();
    }

    private void CloseByUser()
    {
        Dismiss();
        OnClosedByUser?.Invoke();
    }

    public void CopyAnswer()
    {
        if (Answer.Length == 0) return;
        try
        {
            // Retries for a moment if another app has the clipboard open.
            Clipboard.SetDataObject(Answer, true, 5, 100);
        }
        catch
        {
            return;
        }
        OnCopy?.Invoke();
        copyButton.Text = "COPIED";
        copiedTimer.Stop();
        copiedTimer.Start();
    }

    /// Fonts in pixels, sized for the cat's screen, so the card is the same
    /// size there whatever the scale of the screen it was made on.
    private void SetScale(double scale)
    {
        if (Math.Abs(scale - ui) < 0.01 && bodyFont != null) return;
        ui = scale;
        bodyFont?.Dispose();
        labelFont?.Dispose();
        bodyFont = new Font("Segoe UI", (float)(14 * ui), FontStyle.Regular, GraphicsUnit.Pixel);
        labelFont = new Font("Consolas", (float)(12 * ui), FontStyle.Bold, GraphicsUnit.Pixel);
        body.Font = bodyFont;
        heading.Font = labelFont;
        copyButton.Font = labelFont;
        closeButton.Font = labelFont;
    }

    private int Px(double logical) => (int)Math.Round(logical * ui);

    private void SetBody(string text, Color color)
    {
        body.Text = text.Replace("\r\n", "\n").Replace("\n", "\r\n");
        body.ForeColor = color;
        body.SelectionStart = 0;
        body.SelectionLength = 0;
        Relayout();
    }

    /// Grows to fit the text up to a cap, then scrolls. The bottom edge stays
    /// just above the cat's head, kept inside the screen.
    private void Relayout()
    {
        int width = Px(CardWidth);
        int pad = Px(14);
        int textWidth = width - pad * 2;
        var measured = TextRenderer.MeasureText(body.Text.Length == 0 ? " " : body.Text, body.Font,
            new Size(textWidth, int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl);
        int textHeight = Math.Min(Px(MaxTextHeight), Math.Max(Px(18), measured.Height + Px(4)));
        body.ScrollBars = measured.Height + Px(4) > Px(MaxTextHeight) ? ScrollBars.Vertical : ScrollBars.None;
        int headTop = Px(12);
        int headHeight = Math.Max(heading.PreferredHeight, Px(16));
        heading.Location = new Point(pad, headTop);
        closeButton.Location = new Point(width - Px(10) - closeButton.PreferredWidth, headTop);
        copyButton.Location = new Point(closeButton.Left - Px(8) - copyButton.PreferredWidth, headTop);
        body.SetBounds(pad, headTop + headHeight + Px(10), textWidth, textHeight);
        int height = body.Bottom + pad;

        // No screen given yet: use the primary one, never an empty rect.
        var given = area.Width > 24 && area.Height > 24 ? area : (Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 720));
        var room = Rectangle.Inflate(given, -Px(12), -Px(12));
        int x = Math.Clamp(anchor.X - width / 2, room.Left, Math.Max(room.Left, room.Right - width));
        int y = Math.Max(room.Top, anchor.Y - Px(8) - height);
        SetBounds(x, y, width, height);
        Invalidate();
    }

    private void StartCloseTimer(double seconds)
    {
        if (seconds <= 0) return;
        secondsLeft = seconds;
        closeTimer.Start();
    }

    private void StopTimers()
    {
        thinkingTimer.Stop();
        closeTimer.Stop();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            thinkingTimer.Dispose();
            closeTimer.Dispose();
            copiedTimer.Dispose();
            bodyFont?.Dispose();
            labelFont?.Dispose();
            tips.Dispose();
        }
        base.Dispose(disposing);
    }
}

/// Paste your own Anthropic API key. It goes to Windows Credential Manager.
/// With it, answers come from the Claude API; without it, from Claude Code.
public sealed class ApiKeyDialog : Form
{
    public enum Choice { Cancel, Save, Remove }
    public Choice Picked { get; private set; } = Choice.Cancel;
    public string Key => keyBox.Text.Trim();
    private readonly TextBox keyBox = new();

    public ApiKeyDialog(bool keySaved)
    {
        Text = "Anthropic API key";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96, 96);
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;

        var layout = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            Padding = new Padding(14),
            WrapContents = false,
        };
        var info = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(380, 0),
            Text = "With a key, LLM mode calls the Claude API directly, and you pay Anthropic for what you use. " +
                   "Without one, it uses the claude command (Claude Code) and its login. " +
                   "The key is kept in Windows Credential Manager, not in the settings file. " +
                   "Get one at console.anthropic.com.",
            Margin = new Padding(0, 0, 0, 10),
        };
        keyBox.Width = 380;
        keyBox.UseSystemPasswordChar = true;
        keyBox.PlaceholderText = keySaved ? "A key is saved. Paste a new one to replace it." : "sk-ant-...";
        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft, Width = 380, Margin = new Padding(0, 12, 0, 0) };
        var save = new Button { Text = "Save", AutoSize = true, DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "Cancel", AutoSize = true, DialogResult = DialogResult.Cancel };
        save.Click += (_, _) => Picked = Choice.Save;
        buttons.Controls.Add(save);
        buttons.Controls.Add(cancel);
        if (keySaved)
        {
            var remove = new Button { Text = "Remove key", AutoSize = true, DialogResult = DialogResult.Abort };
            remove.Click += (_, _) => Picked = Choice.Remove;
            buttons.Controls.Add(remove);
        }
        layout.Controls.Add(info);
        layout.Controls.Add(keyBox);
        layout.Controls.Add(buttons);
        Controls.Add(layout);
        AcceptButton = save;
        CancelButton = cancel;
        Shown += (_, _) =>
        {
            Activate();
            keyBox.Focus();
        };
    }
}
