using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ScreenCat;

/// User settings, read from %APPDATA%\ScreenCat\screencat.json. Every key is
/// optional; missing keys fall back to the defaults below, so a partial or
/// hand-edited file still works. Same keys and defaults as the Mac version.
public sealed class Config
{
    // Size ---------------------------------------------------------------
    /// Cat standing height = screen height / sizeDivisor. Bigger number = smaller cat.
    public double SizeDivisor = 24;

    // Timing -------------------------------------------------------------
    public double FirstAppearanceDelay = 20;
    public double MinGapSeconds = 3;
    public double MaxGapSeconds = 15;

    // Pace, expressed in "body heights per second" so it scales with the cat.
    public double WalkSpeed = 1.35;
    public double RunSpeed = 4.2;

    // Behaviour lengths --------------------------------------------------
    public double NapSecondsMin = 20;
    public double NapSecondsMax = 60;
    public double BegSecondsMin = 9;
    public double BegSecondsMax = 20;
    public double PlaySecondsMin = 4;
    public double PlaySecondsMax = 8;

    /// How much smaller the cat gets at the top of the screen than at the
    /// bottom. This is what makes walking up read as walking away.
    public double DepthShrink = 0.18;

    // Where the cat is allowed to be, and how steeply it may travel ----------
    /// The cat only roams the bottom this fraction of the screen.
    public double RoamHeight = 0.55;
    /// Pulls positions toward the very bottom. 1 = anywhere in the band,
    /// higher = hugs the bottom edge more tightly.
    public double GroundBias = 3.0;
    /// Steepest a walk may be, as a rise over run. Keeps travel to shallow
    /// diagonals so the cat never appears to drop straight down the screen.
    public double MaxSlope = 0.45;
    /// How often a routine treats a side edge as the floor instead of the
    /// bottom, so the cat also walks up and down the left and right edges.
    public double WallChance = 0.4;

    // Where the window sits, and who can see it ---------------------------
    /// "top" and "status" keep the cat above every normal window. "floating"
    /// lets other always-on-top windows cover it.
    public string WindowLevel = "top";
    /// Leave the cat out of screenshots, screen recordings and screen sharing,
    /// while still showing it to you on the glass.
    public bool HideFromCapture = true;

    // Keeping out of the way ---------------------------------------------
    /// Stay hidden while a blocked app is in front or fullscreen.
    public bool HideWhileWatching = true;
    /// Process name fragments. Matched case-insensitively as substrings.
    public List<string> BlockedApps = new(Watching.DefaultBlockedApps);

    // Relative chance of each behaviour being picked.
    public double WeightStroll = 4;
    public double WeightNap = 2;
    public double WeightBall = 2;
    public double WeightHungry = 2;
    /// Deliberately low: the invite ties the cat up for minutes at a time.
    public double WeightPlay = 0.25;

    /// How long the cat waits with its speech bubble up before giving up.
    public double InviteSeconds = 180;
    /// How long it follows the pointer once you accept.
    public double FollowSeconds = 60;
    /// Rest the pointer on the cat or its bubble this long to accept, instead of
    /// clicking OK. The button fills up as it counts.
    public double DwellSeconds = 30;
    /// How much the cat shrinks between the bottom of the screen and the top
    /// while following you. Do not set it to zero.
    public double FollowDepthShrink = 0.35;
    /// Rest the pointer on the cat this long and it stops for a pet. 0 turns
    /// petting off.
    public double PetSeconds = 1.0;

    // Look ---------------------------------------------------------------
    public string FurColor = "#A87BE0";
    public string FurShadeColor = "#7E52B3";
    public string OutlineColor = "#2E1B47";
    public string InnerColor = "#F5A8CE";
    public string EyeColor = "#FFC94A";
    public string BallColor = "#BC4A9B";
    public bool Shadow = true;
    /// Chance per visit, 0 to 1, that the cat turns up in each accessory.
    public double ChainChance = 1.0;
    public double GlassesChance = 0.35;

    // Modes ----------------------------------------------------------------
    /// "normal", or "crawler": the cat goes round zapping windows and they
    /// look like they break. Only paint; no app is ever touched.
    public string Mode = "normal";
    /// In crawler mode, the chance that a visit is a crawl.
    public double CrawlChance = 0.7;
    /// Start the nonstop crawl after this long with no input. Any input stops it.
    public bool IdleCrawl = true;
    public double IdleCrawlSeconds = 120;
    /// How big the cat grows when the idle crawl starts.
    public double GrowScale = 2;
    /// How long each full-screen glitch style plays before the next one.
    public double GlitchStyleSeconds = 60;
    /// How fast the idle crawl's glitches animate and change. Zero Day runs
    /// at `zeroDaySpeed`.
    public double GlitchSpeed = 2;
    public double ZeroDaySpeed = 8;

    // Activity log ---------------------------------------------------------
    /// Keep a plain-text diary in %LOCALAPPDATA%\ScreenCat\Logs. Local only.
    public bool ActivityLog = true;
    /// Day files older than this are deleted. 0 keeps them forever.
    public double ActivityLogDays = 30;
    public double Opacity = 1.0;

    /// Recolour table applied to the sprite sheet when it loads.
    public SpritePalette SpritePalette => new(
        Rgba.FromHex(FurColor) ?? new Rgba(0.5, 0, 0.5),
        Rgba.FromHex(FurShadeColor) ?? new Rgba(0.5, 0, 0.5),
        Rgba.FromHex(OutlineColor) ?? Rgba.Black,
        Rgba.FromHex(InnerColor) ?? new Rgba(1, 0.18, 0.33),
        Rgba.FromHex(EyeColor) ?? Rgba.WhiteColor,
        Rgba.FromHex(BallColor) ?? new Rgba(1, 0, 1));

    /// Colours for the few things drawn rather than blitted: the z's and the
    /// food bowl.
    public Palette Extras => new(
        Rgba.FromHex(OutlineColor) ?? Rgba.Black,
        Rgba.FromHex(InnerColor) ?? new Rgba(1, 0.18, 0.33));

    public static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ScreenCat");
    public static string FilePath => Path.Combine(Folder, "screencat.json");

    public static Config Load()
    {
        try
        {
            return File.Exists(FilePath) ? Parse(File.ReadAllText(FilePath)) : new Config();
        }
        catch
        {
            return new Config();
        }
    }

    /// Settings from JSON text. Unknown keys are ignored and bad values fall
    /// back to the defaults, then everything is clamped to a safe range.
    public static Config Parse(string json)
    {
        var c = new Config();
        JsonObject? raw;
        try
        {
            raw = JsonNode.Parse(json,
                documentOptions: new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip }) as JsonObject;
        }
        catch
        {
            raw = null;
        }
        if (raw == null) return c;

        double? Num(string key)
        {
            try
            {
                var n = raw[key];
                if (n is JsonValue v && v.TryGetValue<double>(out var d)) return d;
            }
            catch { }
            return null;
        }
        string? Str(string key)
        {
            try { return raw[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null; }
            catch { return null; }
        }
        bool? Bool(string key)
        {
            try { return raw[key] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null; }
            catch { return null; }
        }
        List<string>? Strs(string key)
        {
            if (raw[key] is not JsonArray a) return null;
            var list = new List<string>();
            foreach (var item in a)
            {
                if (item is JsonValue v && v.TryGetValue<string>(out var s)) list.Add(s);
            }
            return list;
        }

        c.SizeDivisor = Num("sizeDivisor") ?? c.SizeDivisor;
        c.FirstAppearanceDelay = Num("firstAppearanceDelay") ?? c.FirstAppearanceDelay;
        c.MinGapSeconds = Num("minGapSeconds") ?? c.MinGapSeconds;
        c.MaxGapSeconds = Num("maxGapSeconds") ?? c.MaxGapSeconds;
        c.WalkSpeed = Num("walkSpeed") ?? c.WalkSpeed;
        c.RunSpeed = Num("runSpeed") ?? c.RunSpeed;
        c.NapSecondsMin = Num("napSecondsMin") ?? c.NapSecondsMin;
        c.NapSecondsMax = Num("napSecondsMax") ?? c.NapSecondsMax;
        c.BegSecondsMin = Num("begSecondsMin") ?? c.BegSecondsMin;
        c.BegSecondsMax = Num("begSecondsMax") ?? c.BegSecondsMax;
        c.PlaySecondsMin = Num("playSecondsMin") ?? c.PlaySecondsMin;
        c.PlaySecondsMax = Num("playSecondsMax") ?? c.PlaySecondsMax;
        c.DepthShrink = Num("depthShrink") ?? c.DepthShrink;
        c.RoamHeight = Num("roamHeight") ?? c.RoamHeight;
        c.GroundBias = Num("groundBias") ?? c.GroundBias;
        c.MaxSlope = Num("maxSlope") ?? c.MaxSlope;
        c.WallChance = Num("wallChance") ?? c.WallChance;
        c.WindowLevel = Str("windowLevel") ?? c.WindowLevel;
        c.HideFromCapture = Bool("hideFromCapture") ?? c.HideFromCapture;
        c.WeightStroll = Num("weightStroll") ?? c.WeightStroll;
        c.WeightNap = Num("weightNap") ?? c.WeightNap;
        c.WeightBall = Num("weightBall") ?? c.WeightBall;
        c.WeightHungry = Num("weightHungry") ?? c.WeightHungry;
        c.WeightPlay = Num("weightPlay") ?? c.WeightPlay;
        c.InviteSeconds = Num("inviteSeconds") ?? c.InviteSeconds;
        c.FollowSeconds = Num("followSeconds") ?? c.FollowSeconds;
        c.DwellSeconds = Num("dwellSeconds") ?? c.DwellSeconds;
        c.FollowDepthShrink = Num("followDepthShrink") ?? c.FollowDepthShrink;
        c.PetSeconds = Num("petSeconds") ?? c.PetSeconds;
        c.FurColor = Str("furColor") ?? c.FurColor;
        c.FurShadeColor = Str("furShadeColor") ?? c.FurShadeColor;
        c.OutlineColor = Str("outlineColor") ?? c.OutlineColor;
        c.InnerColor = Str("innerColor") ?? c.InnerColor;
        c.EyeColor = Str("eyeColor") ?? c.EyeColor;
        c.BallColor = Str("ballColor") ?? c.BallColor;
        c.HideWhileWatching = Bool("hideWhileWatching") ?? c.HideWhileWatching;
        c.BlockedApps = Strs("blockedApps") ?? c.BlockedApps;
        c.Shadow = Bool("shadow") ?? c.Shadow;
        c.ChainChance = Num("chainChance") ?? c.ChainChance;
        c.GlassesChance = Num("glassesChance") ?? c.GlassesChance;
        c.Mode = Str("mode") ?? c.Mode;
        c.CrawlChance = Num("crawlChance") ?? c.CrawlChance;
        c.IdleCrawl = Bool("idleCrawl") ?? c.IdleCrawl;
        c.IdleCrawlSeconds = Num("idleCrawlSeconds") ?? c.IdleCrawlSeconds;
        c.GlitchStyleSeconds = Num("glitchStyleSeconds") ?? c.GlitchStyleSeconds;
        c.GrowScale = Num("growScale") ?? c.GrowScale;
        c.GlitchSpeed = Num("glitchSpeed") ?? c.GlitchSpeed;
        c.ZeroDaySpeed = Num("zeroDaySpeed") ?? c.ZeroDaySpeed;
        c.ActivityLog = Bool("activityLog") ?? c.ActivityLog;
        c.ActivityLogDays = Num("activityLogDays") ?? c.ActivityLogDays;
        c.Opacity = Num("opacity") ?? c.Opacity;

        c.SizeDivisor = Math.Clamp(c.SizeDivisor, 2, 60);
        c.RoamHeight = Math.Clamp(c.RoamHeight, 0.05, 1);
        c.GroundBias = Math.Clamp(c.GroundBias, 1, 8);
        c.MaxSlope = Math.Clamp(c.MaxSlope, 0, 2);
        c.WallChance = Math.Clamp(c.WallChance, 0, 1);
        c.MinGapSeconds = Math.Max(3, c.MinGapSeconds);
        c.MaxGapSeconds = Math.Max(c.MinGapSeconds, c.MaxGapSeconds);
        c.Opacity = Math.Clamp(c.Opacity, 0.1, 1);
        // Each pair feeds a random range, so a hand edit that swaps them must
        // not turn into a negative range on the next visit.
        c.NapSecondsMin = Math.Max(0, c.NapSecondsMin);
        c.NapSecondsMax = Math.Max(c.NapSecondsMin, c.NapSecondsMax);
        c.BegSecondsMin = Math.Max(0, c.BegSecondsMin);
        c.BegSecondsMax = Math.Max(c.BegSecondsMin, c.BegSecondsMax);
        c.PlaySecondsMin = Math.Max(0, c.PlaySecondsMin);
        c.PlaySecondsMax = Math.Max(c.PlaySecondsMin, c.PlaySecondsMax);
        c.PetSeconds = Math.Max(0, c.PetSeconds);
        c.CrawlChance = Math.Clamp(c.CrawlChance, 0, 1);
        c.IdleCrawlSeconds = Math.Max(15, c.IdleCrawlSeconds);
        c.GlitchStyleSeconds = Math.Max(5, c.GlitchStyleSeconds);
        c.GrowScale = Math.Clamp(c.GrowScale, 1, 4);
        c.GlitchSpeed = Math.Clamp(c.GlitchSpeed, 0.25, 16);
        c.ZeroDaySpeed = Math.Clamp(c.ZeroDaySpeed, 1, 16);
        c.ChainChance = Math.Clamp(c.ChainChance, 0, 1);
        c.GlassesChance = Math.Clamp(c.GlassesChance, 0, 1);
        return c;
    }

    private static readonly JsonSerializerOptions Pretty = new() { WriteIndented = true };

    /// Writes one key back to the settings file, leaving every other key, and
    /// any hand edits, exactly as they were.
    public static void Update(string key, JsonNode? value)
    {
        try
        {
            JsonObject raw = new();
            if (File.Exists(FilePath))
            {
                raw = JsonNode.Parse(File.ReadAllText(FilePath),
                    documentOptions: new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip }) as JsonObject ?? new JsonObject();
            }
            raw[key] = value;
            Directory.CreateDirectory(Folder);
            File.WriteAllText(FilePath, Sorted(raw).ToJsonString(Pretty));
        }
        catch
        {
            // A settings file we cannot write is not worth crashing the cat over.
        }
    }

    private static JsonObject Sorted(JsonObject o)
    {
        var sorted = new JsonObject();
        foreach (var kv in o.OrderBy(k => k.Key, StringComparer.Ordinal))
        {
            sorted[kv.Key] = kv.Value?.DeepClone();
        }
        return sorted;
    }

    /// Writes a full default file if the user has none yet.
    public static void WriteDefaultFileIfMissing()
    {
        try
        {
            if (File.Exists(FilePath)) return;
            Directory.CreateDirectory(Folder);
            File.WriteAllText(FilePath, DefaultJson());
        }
        catch
        {
            // No settings file just means defaults.
        }
    }

    /// Every key with its default value, sorted, as the default file holds it.
    public static string DefaultJson()
    {
        var d = new Config();
        var blocked = new JsonArray();
        foreach (var b in d.BlockedApps) blocked.Add(b);
        var dict = new JsonObject
        {
            ["sizeDivisor"] = d.SizeDivisor,
            ["firstAppearanceDelay"] = d.FirstAppearanceDelay,
            ["minGapSeconds"] = d.MinGapSeconds,
            ["maxGapSeconds"] = d.MaxGapSeconds,
            ["walkSpeed"] = d.WalkSpeed,
            ["runSpeed"] = d.RunSpeed,
            ["napSecondsMin"] = d.NapSecondsMin,
            ["napSecondsMax"] = d.NapSecondsMax,
            ["begSecondsMin"] = d.BegSecondsMin,
            ["begSecondsMax"] = d.BegSecondsMax,
            ["playSecondsMin"] = d.PlaySecondsMin,
            ["playSecondsMax"] = d.PlaySecondsMax,
            ["depthShrink"] = d.DepthShrink,
            ["roamHeight"] = d.RoamHeight,
            ["groundBias"] = d.GroundBias,
            ["maxSlope"] = d.MaxSlope,
            ["wallChance"] = d.WallChance,
            ["windowLevel"] = d.WindowLevel,
            ["hideFromCapture"] = d.HideFromCapture,
            ["weightStroll"] = d.WeightStroll,
            ["weightNap"] = d.WeightNap,
            ["weightBall"] = d.WeightBall,
            ["weightHungry"] = d.WeightHungry,
            ["weightPlay"] = d.WeightPlay,
            ["inviteSeconds"] = d.InviteSeconds,
            ["followSeconds"] = d.FollowSeconds,
            ["dwellSeconds"] = d.DwellSeconds,
            ["followDepthShrink"] = d.FollowDepthShrink,
            ["petSeconds"] = d.PetSeconds,
            ["furColor"] = d.FurColor,
            ["furShadeColor"] = d.FurShadeColor,
            ["outlineColor"] = d.OutlineColor,
            ["innerColor"] = d.InnerColor,
            ["eyeColor"] = d.EyeColor,
            ["ballColor"] = d.BallColor,
            ["hideWhileWatching"] = d.HideWhileWatching,
            ["blockedApps"] = blocked,
            ["shadow"] = d.Shadow,
            ["chainChance"] = d.ChainChance,
            ["glassesChance"] = d.GlassesChance,
            ["mode"] = d.Mode,
            ["crawlChance"] = d.CrawlChance,
            ["idleCrawl"] = d.IdleCrawl,
            ["idleCrawlSeconds"] = d.IdleCrawlSeconds,
            ["glitchStyleSeconds"] = d.GlitchStyleSeconds,
            ["growScale"] = d.GrowScale,
            ["glitchSpeed"] = d.GlitchSpeed,
            ["zeroDaySpeed"] = d.ZeroDaySpeed,
            ["activityLog"] = d.ActivityLog,
            ["activityLogDays"] = d.ActivityLogDays,
            ["opacity"] = d.Opacity,
        };
        return Sorted(dict).ToJsonString(Pretty);
    }
}
