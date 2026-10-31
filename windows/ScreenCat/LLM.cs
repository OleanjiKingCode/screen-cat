using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ScreenCat;

/// What the cat is asked about: something you copied, or a screenshot.
public abstract record Question
{
    public sealed record Text(string Value) : Question;
    /// PNG bytes, already shrunk for upload, and where they came from.
    public sealed record Image(byte[] Png, string From) : Question;

    /// For the activity log and the card. Never the full content.
    public string Summary => this switch
    {
        Text t => $"copied text ({t.Value.Length} characters)",
        Image i => i.From,
        _ => "something",
    };
}

public abstract record Answer
{
    public sealed record Text(string Value) : Answer;
    public sealed record Failed(string Why) : Answer;
}

/// Answers a question with Claude. With your own API key it calls the Claude
/// API directly. Without one it runs the `claude` command line tool with the
/// login it already has. One question at a time: a new one cancels the one
/// before it.
///
/// The tool runs with no tools, no MCP servers, no CLAUDE.md and no memory,
/// from an empty folder, so your coding setup does not leak into the answers.
public sealed class Asker
{
    private Process? process;
    private CancellationTokenSource? cancel;
    /// Bumped on every ask and cancel, so a late reply to an old question is
    /// dropped instead of replacing the new one.
    private int generation;
    private readonly SynchronizationContext ui;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(180) };
    private static readonly UTF8Encoding Utf8 = new(false);

    public Asker()
    {
        ui = SynchronizationContext.Current ?? new SynchronizationContext();
    }

    public const string SystemPrompt =
        "You are the brain of Screen Cat, a desktop pet cat. The user just copied some text or took " +
        "a screenshot, and the cat shows your reply in a small card. Work out what they want and give it:\n" +
        "- A question: answer it.\n" +
        "- Maths (an equation, a sum, a word problem): solve it. Give the final answer, then the few " +
        "steps that get there.\n" +
        "- A statement of fact: say whether it is right, and correct it if it is not.\n" +
        "- A word or phrase: explain what it means.\n" +
        "- Code or an error message: say what is wrong and how to fix it, or what the code does.\n" +
        "- A quiz or multiple-choice question: give the correct option and one line on why.\n" +
        "- Anything else: the most useful short explanation or summary.\n" +
        "Put the answer in the first line. Keep the whole reply short, a few lines, unless the " +
        "working is needed. Write plain text only: no Markdown, no headings, no bold. Write maths " +
        "in plain text, for example x^2 + 3x = 10, sqrt(2), pi.";

    /// The usual install spots, then PATH. The native installer puts
    /// claude.exe in ~\.local\bin; npm puts a claude.cmd shim in %APPDATA%\npm.
    public static string? ClaudePath(string configured)
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var candidates = new List<string>
        {
            Environment.ExpandEnvironmentVariables(configured.Trim().Trim('"')),
            Path.Combine(home, ".local", "bin", "claude.exe"),
            Path.Combine(appData, "npm", "claude.cmd"),
            Path.Combine(local, "Microsoft", "WinGet", "Links", "claude.exe"),
            Path.Combine(home, ".claude", "local", "claude.exe"),
        };
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            candidates.Add(Path.Combine(dir.Trim().Trim('"'), "claude.exe"));
            candidates.Add(Path.Combine(dir.Trim().Trim('"'), "claude.cmd"));
        }
        return candidates.FirstOrDefault(p => p.Length > 0 && File.Exists(p));
    }

    public void Cancel()
    {
        generation++;
        try { if (process is { HasExited: false } p) p.Kill(entireProcessTree: true); } catch { }
        process = null;
        cancel?.Cancel();
        cancel = null;
    }

    /// Calls `done` once, on the UI thread, unless cancelled first.
    public void Ask(Question question, Config config, Action<Answer> done)
    {
        Cancel();
        int mine = generation;
        void Finish(Answer answer) => ui.Post(_ =>
        {
            if (generation != mine) return;
            // Once only: a timeout and the reader can both get here.
            generation++;
            process = null;
            cancel = null;
            done(answer);
        }, null);

        if (ApiKey.Load() is string key)
        {
            var token = new CancellationTokenSource();
            cancel = token;
            _ = AskApiAsync(question, key, config, token.Token, Finish);
            return;
        }
        if (ClaudePath(config.LlmClaudePath) is not string exe)
        {
            Finish(new Answer.Failed("Could not find the claude command. Install Claude Code, set an API key, or set llmClaudePath in settings."));
            return;
        }
        try
        {
            AskCli(question, exe, config, Finish);
        }
        catch (Exception e)
        {
            Finish(new Answer.Failed($"Could not start claude: {e.Message}"));
        }
    }

    private void AskCli(Question question, string exe, Config config, Action<Answer> finish)
    {
        string folder = Path.Combine(Path.GetTempPath(), "ScreenCatLLM");
        Directory.CreateDirectory(folder);
        // A file, not an argument: the prompt has quotes and line breaks, and
        // cmd.exe mangles those on the way to an npm shim.
        string promptFile = Path.Combine(folder, "system-prompt.txt");
        File.WriteAllText(promptFile, SystemPrompt, Utf8);

        // The model name is passed through cmd.exe for an npm install, so only
        // plain model ids are allowed through.
        string model = Regex.IsMatch(config.LlmModel, @"^[A-Za-z0-9._:\-\[\]]+$") ? config.LlmModel : new Config().LlmModel;
        var args = new[]
        {
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--tools", "", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
            "--model", model, "--effort", config.LlmEffort, "--system-prompt-file", promptFile,
        };
        var psi = new ProcessStartInfo
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding = Utf8,
            StandardOutputEncoding = Utf8,
            StandardErrorEncoding = Utf8,
            WorkingDirectory = folder,
        };
        if (exe.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || exe.EndsWith(".bat", StringComparison.OrdinalIgnoreCase))
        {
            // A batch shim only runs through cmd.exe. /s keeps the outer quotes simple.
            psi.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            psi.Arguments = "/d /s /c \"" + string.Join(" ", new[] { exe }.Concat(args).Select(CmdQuote)) + "\"";
        }
        else
        {
            psi.FileName = exe;
            foreach (var a in args) psi.ArgumentList.Add(a);
        }
        psi.Environment["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1";
        psi.Environment["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1";

        var p = Process.Start(psi) ?? throw new InvalidOperationException("no process");
        process = p;
        // Both pipes are drained at once, or a chatty stderr could fill its
        // buffer and stall the process before stdout ends.
        var output = p.StandardOutput.ReadToEndAsync();
        var errors = p.StandardError.ReadToEndAsync();
        string line = InputLine(question);
        // A screenshot is a few MB of base64, so the write can block until
        // claude reads it. Never on the UI thread.
        Task.Run(() =>
        {
            try
            {
                p.StandardInput.Write(line);
                p.StandardInput.Close();
            }
            catch { }
        });
        Task.Run(async () =>
        {
            string outText = "", errText = "";
            try
            {
                outText = await output;
                errText = await errors;
                p.WaitForExit();
            }
            catch { }
            int code = 0;
            try { code = p.ExitCode; } catch { }
            finish(ParseCli(outText, code, errText));
        });
        Task.Delay(TimeSpan.FromSeconds(180)).ContinueWith(_ =>
        {
            try
            {
                if (p.HasExited) return;
                finish(new Answer.Failed("No answer after three minutes, so the cat gave up."));
                p.Kill(entireProcessTree: true);
            }
            catch { }
        });
    }

    private static string CmdQuote(string arg)
    {
        if (arg.Length == 0) return "\"\"";
        return arg.Any(ch => char.IsWhiteSpace(ch) || "&|<>^()%!\"".Contains(ch)) ? "\"" + arg.Replace("\"", "\"\"") + "\"" : arg;
    }

    /// Models that take `fallbacks: "default"`: a declined answer is retried
    /// on another model by the API instead of coming back empty.
    private static readonly HashSet<string> FallbackModels = new()
    {
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    };

    /// Straight to the Claude API with your key. A few seconds faster than
    /// the command line tool, and works on a PC without Claude Code.
    private static async Task AskApiAsync(Question question, string key, Config config, CancellationToken token, Action<Answer> finish)
    {
        var body = new JsonObject
        {
            ["model"] = config.LlmModel,
            ["max_tokens"] = 16000,
            ["system"] = SystemPrompt,
            ["output_config"] = new JsonObject { ["effort"] = config.LlmEffort },
            ["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = Content(question) }),
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
        request.Headers.Add("x-api-key", key);
        request.Headers.Add("anthropic-version", "2023-06-01");
        if (FallbackModels.Contains(config.LlmModel))
        {
            body["fallbacks"] = "default";
            request.Headers.Add("anthropic-beta", "server-side-fallback-2026-07-01");
        }
        request.Content = new StringContent(body.ToJsonString(), Utf8, "application/json");
        try
        {
            using var response = await Http.SendAsync(request, token);
            string text = await response.Content.ReadAsStringAsync(token);
            finish(ParseApi(text, (int)response.StatusCode));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
        catch (Exception e)
        {
            finish(new Answer.Failed($"Could not reach the Claude API: {e.Message}"));
        }
    }

    /// The reply's text blocks, joined; thinking blocks are skipped. A refusal
    /// or an API error comes back as a reason to show on the card.
    public static Answer ParseApi(string json, int status)
    {
        JsonObject? obj;
        try { obj = JsonNode.Parse(json) as JsonObject; } catch { obj = null; }
        if (obj == null) return new Answer.Failed($"The Claude API sent back something unreadable (HTTP {status}).");
        if (obj["error"] is JsonObject error)
        {
            string message = Str(error["message"]) ?? "unknown error";
            return new Answer.Failed(status == 401 ? $"Your API key was not accepted: {message}" : $"Claude API error: {message}");
        }
        if (Str(obj["stop_reason"]) == "refusal") return new Answer.Failed("Claude would not answer this one.");
        var text = string.Concat((obj["content"] as JsonArray ?? new JsonArray())
            .OfType<JsonObject>()
            .Where(b => Str(b["type"]) == "text")
            .Select(b => Str(b["text"]) ?? "")).Trim();
        return text.Length == 0 ? new Answer.Failed("Claude sent back an empty answer.") : new Answer.Text(text);
    }

    /// The last line of claude's output is a "result" event with the reply,
    /// or the reason there is none (not logged in, out of usage, and so on).
    public static Answer ParseCli(string output, int status, string errors)
    {
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries).Reverse())
        {
            JsonObject? obj;
            try { obj = JsonNode.Parse(line) as JsonObject; } catch { continue; }
            if (obj == null || Str(obj["type"]) != "result") continue;
            string result = (Str(obj["result"]) ?? "").Trim();
            bool isError = obj["is_error"] is JsonValue v && v.TryGetValue<bool>(out bool b) && b;
            if (isError || Str(obj["subtype"]) != "success" || result.Length == 0)
            {
                return new Answer.Failed(result.Length == 0 ? $"claude stopped: {Str(obj["subtype"]) ?? "no reply"}" : result);
            }
            return new Answer.Text(result);
        }
        string tail = errors.Split('\n', StringSplitOptions.RemoveEmptyEntries).LastOrDefault()?.Trim() ?? "";
        return new Answer.Failed(tail.Length == 0 ? $"claude exited with code {status} and no answer." : tail);
    }

    private static string? Str(JsonNode? node) => node is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    /// The user message: the copied text, or the screenshot.
    public static JsonArray Content(Question question) => question switch
    {
        Question.Image image => new JsonArray(
            new JsonObject
            {
                ["type"] = "image",
                ["source"] = new JsonObject
                {
                    ["type"] = "base64",
                    ["media_type"] = "image/png",
                    ["data"] = Convert.ToBase64String(image.Png),
                },
            },
            new JsonObject { ["type"] = "text", ["text"] = "I took this screenshot." }),
        Question.Text text => new JsonArray(
            new JsonObject { ["type"] = "text", ["text"] = $"I copied this:\n<copied>\n{text.Value}\n</copied>" }),
        _ => new JsonArray(),
    };

    /// One stream-json user message for the command line tool.
    public static string InputLine(Question question)
    {
        var message = new JsonObject
        {
            ["type"] = "user",
            ["message"] = new JsonObject { ["role"] = "user", ["content"] = Content(question) },
        };
        return message.ToJsonString() + "\n";
    }

    /// Shrinks an image so its long edge is at most 1568 px, the most Claude
    /// looks at, and returns it as PNG. A 4K screenshot is far bigger than
    /// that, and sending the full size only makes the upload slower.
    public static byte[]? PngForUpload(System.Drawing.Image image)
    {
        try
        {
            double scale = Math.Min(1, 1568.0 / Math.Max(image.Width, image.Height));
            int w = Math.Max(1, (int)(image.Width * scale)), h = Math.Max(1, (int)(image.Height * scale));
            using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(image, new Rectangle(0, 0, w, h));
            }
            using var ms = new MemoryStream();
            bmp.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }
        catch
        {
            return null;
        }
    }
}

/// Your own Anthropic API key, kept in Windows Credential Manager (under
/// "ScreenCat/anthropic-api-key") and never in the settings file.
/// `ANTHROPIC_API_KEY` in the environment works too.
public static class ApiKey
{
    private const string Target = "ScreenCat/anthropic-api-key";

    public static bool IsSet => Load() != null;

    public static string? Load()
    {
        try
        {
            if (Native.CredReadW(Target, Native.CRED_TYPE_GENERIC, 0, out IntPtr ptr))
            {
                try
                {
                    var cred = Marshal.PtrToStructure<Native.CREDENTIAL>(ptr);
                    if (cred.CredentialBlobSize > 0 && cred.CredentialBlob != IntPtr.Zero)
                    {
                        var bytes = new byte[cred.CredentialBlobSize];
                        Marshal.Copy(cred.CredentialBlob, bytes, 0, bytes.Length);
                        string key = Encoding.UTF8.GetString(bytes).Trim();
                        if (key.Length > 0) return key;
                    }
                }
                finally
                {
                    Native.CredFree(ptr);
                }
            }
        }
        catch { }
        string env = (Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY") ?? "").Trim();
        return env.Length == 0 ? null : env;
    }

    public static bool Save(string key)
    {
        var bytes = Encoding.UTF8.GetBytes(key);
        IntPtr blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var cred = new Native.CREDENTIAL
            {
                Type = Native.CRED_TYPE_GENERIC,
                TargetName = Target,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = Native.CRED_PERSIST_LOCAL_MACHINE,
                UserName = "anthropic-api-key",
            };
            return Native.CredWriteW(ref cred, 0);
        }
        catch
        {
            return false;
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
        }
    }

    public static void Delete()
    {
        try { Native.CredDeleteW(Target, Native.CRED_TYPE_GENERIC, 0); } catch { }
    }
}

/// LLM mode's ears: new clipboard contents and new screenshots.
public sealed class QuestionWatch : IDisposable
{
    public Action<Question>? OnQuestion;
    /// Text the cat itself put there, such as a line copied out of an answer.
    /// It is not a new question.
    public Func<string, bool>? IsOwnText;
    /// Set after the cat writes the clipboard, so that change is skipped.
    public uint OwnChange;

    private readonly System.Windows.Forms.Timer clipboardTimer = new() { Interval = 400 };
    private uint lastChange;
    private int busyTries;
    private string lastText = "";
    private FileSystemWatcher? folderWatch;
    private string screenshotFolder = "";
    private readonly HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
    private DateTime since;
    /// Windows screenshot tools copy the picture and save it too, so one
    /// screenshot would be asked about twice. One picture per few seconds.
    private DateTime lastImageAt = DateTime.MinValue;
    private SynchronizationContext? ui;

    public QuestionWatch()
    {
        clipboardTimer.Tick += (_, _) => CheckClipboard();
    }

    public bool IsRunning => clipboardTimer.Enabled || folderWatch != null;

    /// Only what changes after this call counts. Whatever is already on the
    /// clipboard, or already in the screenshots folder, is left alone.
    public void Start(bool clipboard, bool screenshots)
    {
        Stop();
        ui = SynchronizationContext.Current;
        lastChange = Native.GetClipboardSequenceNumber();
        if (clipboard) clipboardTimer.Start();
        if (screenshots) WatchScreenshots();
    }

    public void Stop()
    {
        clipboardTimer.Stop();
        folderWatch?.Dispose();
        folderWatch = null;
    }

    public void Dispose()
    {
        Stop();
        clipboardTimer.Dispose();
    }

    /// Password managers mark what they copy with these formats, so a
    /// password is never sent anywhere.
    private static readonly string[] PrivateFormats =
    {
        "ExcludeClipboardContentFromMonitorProcessing",
        "Clipboard Viewer Ignore",
    };

    /// What is on the clipboard now, for the menu's one-off ask. Null when it
    /// is empty, private, or a file. Must run on the UI thread.
    public static Question? ClipboardQuestion()
    {
        var data = Clipboard.GetDataObject();
        if (data == null) return null;
        var formats = data.GetFormats(false);
        if (formats.Any(f => PrivateFormats.Contains(f, StringComparer.OrdinalIgnoreCase))) return null;
        if (formats.Contains("CanIncludeInClipboardHistory") && IsZero(data.GetData("CanIncludeInClipboardHistory"))) return null;
        if (data.GetDataPresent(DataFormats.FileDrop)) return null;

        string text = (data.GetData(DataFormats.UnicodeText) as string ?? "").Trim();
        bool hasImage = data.GetDataPresent("PNG") || data.GetDataPresent(DataFormats.Bitmap);
        // "Copy image" in a browser can also put the image's address there.
        // The picture is the question, not the link.
        bool justALink = (text.StartsWith("http://") || text.StartsWith("https://")) && !text.Any(char.IsWhiteSpace);
        if (text.Length >= 2 && !(hasImage && justALink)) return new Question.Text(text);
        if (!hasImage) return null;
        using var image = ReadImage(data);
        return image != null && Asker.PngForUpload(image) is byte[] png ? new Question.Image(png, "copied image") : null;
    }

    private static bool IsZero(object? value)
    {
        if (value is not MemoryStream ms) return false;
        var bytes = ms.ToArray();
        return bytes.Length > 0 && bytes.All(b => b == 0);
    }

    private static System.Drawing.Image? ReadImage(IDataObject data)
    {
        try
        {
            // Browsers and the Snipping Tool put a PNG there; keep its alpha.
            if (data.GetData("PNG") is MemoryStream png) return System.Drawing.Image.FromStream(png);
            if (data.GetData(DataFormats.Bitmap) is System.Drawing.Image bmp) return new Bitmap(bmp);
        }
        catch { }
        return null;
    }

    private void CheckClipboard()
    {
        uint change = Native.GetClipboardSequenceNumber();
        if (change == lastChange) return;
        Question? question;
        try
        {
            question = change == OwnChange ? null : ClipboardQuestion();
        }
        catch
        {
            // Another app has the clipboard open. Try again on the next tick,
            // but not forever.
            if (++busyTries < 5) return;
            question = null;
        }
        busyTries = 0;
        lastChange = change;
        if (question == null) return;
        if (question is Question.Text t)
        {
            // Copying the same thing twice in a row is not a new question.
            if (t.Value == lastText || (IsOwnText?.Invoke(t.Value) ?? false)) return;
            lastText = t.Value;
        }
        else if (!TakeImageSlot())
        {
            return;
        }
        OnQuestion?.Invoke(question);
    }

    private bool TakeImageSlot()
    {
        if ((DateTime.UtcNow - lastImageAt).TotalSeconds < 5) return false;
        lastImageAt = DateTime.UtcNow;
        return true;
    }

    // Screenshots -------------------------------------------------------------

    /// Where Win+Print Screen and the Snipping Tool save: the Screenshots
    /// known folder, which the user can move.
    public static string ScreenshotFolder()
    {
        try
        {
            if (Native.SHGetKnownFolderPath(ref Native.FOLDERID_Screenshots, 0, IntPtr.Zero, out IntPtr ptr) == 0)
            {
                try
                {
                    string? path = Marshal.PtrToStringUni(ptr);
                    if (!string.IsNullOrEmpty(path)) return path;
                }
                finally
                {
                    Marshal.FreeCoTaskMem(ptr);
                }
            }
        }
        catch { }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
    }

    private void WatchScreenshots()
    {
        since = DateTime.UtcNow;
        seen.Clear();
        screenshotFolder = ScreenshotFolder();
        try
        {
            Directory.CreateDirectory(screenshotFolder);
            var watch = new FileSystemWatcher(screenshotFolder)
            {
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite,
                IncludeSubdirectories = false,
            };
            // The file can still be being written when the event comes, so
            // look twice, back on the UI thread.
            void Changed(object? sender, FileSystemEventArgs e) => ui?.Post(_ =>
            {
                Later(500, Scan);
                Later(2000, Scan);
            }, null);
            watch.Created += Changed;
            watch.Renamed += (s, e) => Changed(s, e);
            watch.EnableRaisingEvents = true;
            folderWatch = watch;
        }
        catch (Exception e)
        {
            ActivityLog.Shared.Cat($"llm: cannot watch {screenshotFolder} for screenshots: {e.Message}");
        }
    }

    private static void Later(int ms, Action action)
    {
        var timer = new System.Windows.Forms.Timer { Interval = ms };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            timer.Dispose();
            action();
        };
        timer.Start();
    }

    private void Scan()
    {
        if (folderWatch == null) return;
        string[] files;
        try { files = Directory.GetFiles(screenshotFolder); } catch { return; }
        var images = new[] { ".png", ".jpg", ".jpeg" };
        foreach (var file in files)
        {
            if (seen.Contains(file) || !images.Contains(Path.GetExtension(file).ToLowerInvariant())) continue;
            try
            {
                if (File.GetCreationTimeUtc(file) <= since) continue;
                byte[]? png;
                // Read it all first: Image.FromFile keeps the file locked.
                using (var ms = new MemoryStream(File.ReadAllBytes(file)))
                using (var image = System.Drawing.Image.FromStream(ms))
                {
                    png = Asker.PngForUpload(image);
                }
                seen.Add(file);
                if (png == null || !TakeImageSlot()) continue;
                OnQuestion?.Invoke(new Question.Image(png, "screenshot"));
            }
            catch
            {
                // Still being written; the second look gets it.
            }
        }
    }
}
