package com.oleanji.screencat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * User settings, read from screencat.json in the app's files folder. The keys
 * are the same as the Mac's ~/.screencat.json, so a file can be copied across.
 * Every key is optional; missing keys fall back to the defaults below. Keys
 * that mean nothing on Android (windowLevel, hideFromCapture, blockedApps,
 * the activity log, the play invite and petting) are kept in the file but
 * not used.
 */
data class Config(
    // Size: cat standing height = screen height / sizeDivisor.
    var sizeDivisor: Float = 24f,

    // Timing.
    var firstAppearanceDelay: Float = 20f,
    var minGapSeconds: Float = 3f,
    var maxGapSeconds: Float = 15f,

    // Pace, in body heights per second, so it scales with the cat.
    var walkSpeed: Float = 1.35f,
    var runSpeed: Float = 4.2f,

    // Behaviour lengths.
    var napSecondsMin: Float = 20f,
    var napSecondsMax: Float = 60f,
    var begSecondsMin: Float = 9f,
    var begSecondsMax: Float = 20f,
    var playSecondsMin: Float = 4f,
    var playSecondsMax: Float = 8f,

    // How much smaller the cat gets at the top of its band.
    var depthShrink: Float = 0.18f,

    // Where the cat may be, and how steeply it may travel.
    var roamHeight: Float = 0.55f,
    var groundBias: Float = 3.0f,
    var maxSlope: Float = 0.45f,
    var wallChance: Double = 0.4,

    // Mac only, kept so the file round-trips.
    var windowLevel: String = "top",
    var hideFromCapture: Boolean = true,
    var hideWhileWatching: Boolean = true,
    var blockedApps: List<String> = DEFAULT_BLOCKED_APPS,

    // Relative chance of each routine.
    var weightStroll: Double = 4.0,
    var weightNap: Double = 2.0,
    var weightBall: Double = 2.0,
    var weightHungry: Double = 2.0,
    var weightPlay: Double = 0.25,

    // The play invite and petting: Mac only.
    var inviteSeconds: Float = 180f,
    var followSeconds: Float = 60f,
    var dwellSeconds: Float = 30f,
    var followDepthShrink: Float = 0.35f,
    var petSeconds: Float = 1.0f,

    // Look.
    var furColor: String = "#A87BE0",
    var furShadeColor: String = "#7E52B3",
    var outlineColor: String = "#2E1B47",
    var innerColor: String = "#F5A8CE",
    var eyeColor: String = "#FFC94A",
    var ballColor: String = "#BC4A9B",
    var shadow: Boolean = true,
    var chainChance: Double = 1.0,
    var glassesChance: Double = 0.35,

    // Modes.
    var mode: String = "normal",
    var crawlChance: Double = 0.7,
    var idleCrawl: Boolean = true,
    var idleCrawlSeconds: Float = 120f,
    var growScale: Float = 2f,
    var glitchStyleSeconds: Float = 60f,

    // Activity log: Mac only.
    var activityLog: Boolean = true,
    var activityLogDays: Float = 30f,
    var opacity: Float = 1.0f,
) {
    /** Recolour table applied to the sprite sheet when it loads. */
    val spritePalette: SpritePalette
        get() = SpritePalette(
            fur = parseHex(furColor) ?: rgb(0x800080),
            furShade = parseHex(furShadeColor) ?: rgb(0x800080),
            outline = parseHex(outlineColor) ?: BLACK,
            inner = parseHex(innerColor) ?: SYSTEM_PINK,
            eye = parseHex(eyeColor) ?: WHITE,
            ball = parseHex(ballColor) ?: rgb(0xFF00FF),
        )

    /** Colours for the few things drawn rather than blitted. */
    val extras: Palette
        get() = Palette(outline = parseHex(outlineColor) ?: BLACK, inner = parseHex(innerColor) ?: SYSTEM_PINK)

    /** A key that changes only when the sprite colours do. */
    val paletteKey: String
        get() = listOf(furColor, furShadeColor, outlineColor, innerColor, eyeColor, ballColor).joinToString("|")

    fun toJson(): JSONObject = JSONObject().apply {
        put("sizeDivisor", sizeDivisor.toDouble())
        put("firstAppearanceDelay", firstAppearanceDelay.toDouble())
        put("minGapSeconds", minGapSeconds.toDouble())
        put("maxGapSeconds", maxGapSeconds.toDouble())
        put("walkSpeed", walkSpeed.toDouble())
        put("runSpeed", runSpeed.toDouble())
        put("napSecondsMin", napSecondsMin.toDouble())
        put("napSecondsMax", napSecondsMax.toDouble())
        put("begSecondsMin", begSecondsMin.toDouble())
        put("begSecondsMax", begSecondsMax.toDouble())
        put("playSecondsMin", playSecondsMin.toDouble())
        put("playSecondsMax", playSecondsMax.toDouble())
        put("depthShrink", depthShrink.toDouble())
        put("roamHeight", roamHeight.toDouble())
        put("groundBias", groundBias.toDouble())
        put("maxSlope", maxSlope.toDouble())
        put("wallChance", wallChance)
        put("windowLevel", windowLevel)
        put("hideFromCapture", hideFromCapture)
        put("hideWhileWatching", hideWhileWatching)
        put("blockedApps", JSONArray(blockedApps))
        put("weightStroll", weightStroll)
        put("weightNap", weightNap)
        put("weightBall", weightBall)
        put("weightHungry", weightHungry)
        put("weightPlay", weightPlay)
        put("inviteSeconds", inviteSeconds.toDouble())
        put("followSeconds", followSeconds.toDouble())
        put("dwellSeconds", dwellSeconds.toDouble())
        put("followDepthShrink", followDepthShrink.toDouble())
        put("petSeconds", petSeconds.toDouble())
        put("furColor", furColor)
        put("furShadeColor", furShadeColor)
        put("outlineColor", outlineColor)
        put("innerColor", innerColor)
        put("eyeColor", eyeColor)
        put("ballColor", ballColor)
        put("shadow", shadow)
        put("chainChance", chainChance)
        put("glassesChance", glassesChance)
        put("mode", mode)
        put("crawlChance", crawlChance)
        put("idleCrawl", idleCrawl)
        put("idleCrawlSeconds", idleCrawlSeconds.toDouble())
        put("glitchStyleSeconds", glitchStyleSeconds.toDouble())
        put("growScale", growScale.toDouble())
        put("activityLog", activityLog)
        put("activityLogDays", activityLogDays.toDouble())
        put("opacity", opacity.toDouble())
    }

    companion object {
        val DEFAULT_BLOCKED_APPS = listOf(
            "org.videolan.vlc", "com.colliderli.iina", "io.mpv", "com.apple.QuickTimePlayerX",
            "com.apple.TV", "com.netflix.Netflix", "com.plexapp.plexamp", "tv.plex.desktop",
            "com.firecore.infuse",
        )

        fun file(context: Context) = File(context.filesDir, "screencat.json")

        fun readRaw(context: Context): JSONObject? = try {
            val f = file(context)
            if (f.exists()) JSONObject(f.readText()) else null
        } catch (_: Exception) {
            null
        }

        fun load(context: Context): Config = fromJson(readRaw(context))

        fun fromJson(raw: JSONObject?): Config {
            val c = Config()
            if (raw == null) return c
            fun num(k: String, d: Float) = if (raw.has(k)) raw.optDouble(k, d.toDouble()).toFloat() else d
            fun dbl(k: String, d: Double) = if (raw.has(k)) raw.optDouble(k, d) else d
            fun str(k: String, d: String) = if (raw.has(k)) raw.optString(k, d) else d
            fun bool(k: String, d: Boolean) = if (raw.has(k)) raw.optBoolean(k, d) else d

            c.sizeDivisor = num("sizeDivisor", c.sizeDivisor)
            c.firstAppearanceDelay = num("firstAppearanceDelay", c.firstAppearanceDelay)
            c.minGapSeconds = num("minGapSeconds", c.minGapSeconds)
            c.maxGapSeconds = num("maxGapSeconds", c.maxGapSeconds)
            c.walkSpeed = num("walkSpeed", c.walkSpeed)
            c.runSpeed = num("runSpeed", c.runSpeed)
            c.napSecondsMin = num("napSecondsMin", c.napSecondsMin)
            c.napSecondsMax = num("napSecondsMax", c.napSecondsMax)
            c.begSecondsMin = num("begSecondsMin", c.begSecondsMin)
            c.begSecondsMax = num("begSecondsMax", c.begSecondsMax)
            c.playSecondsMin = num("playSecondsMin", c.playSecondsMin)
            c.playSecondsMax = num("playSecondsMax", c.playSecondsMax)
            c.depthShrink = num("depthShrink", c.depthShrink)
            c.roamHeight = num("roamHeight", c.roamHeight)
            c.groundBias = num("groundBias", c.groundBias)
            c.maxSlope = num("maxSlope", c.maxSlope)
            c.wallChance = dbl("wallChance", c.wallChance)
            c.windowLevel = str("windowLevel", c.windowLevel)
            c.hideFromCapture = bool("hideFromCapture", c.hideFromCapture)
            c.hideWhileWatching = bool("hideWhileWatching", c.hideWhileWatching)
            raw.optJSONArray("blockedApps")?.let { a -> c.blockedApps = (0 until a.length()).map { a.optString(it) } }
            c.weightStroll = dbl("weightStroll", c.weightStroll)
            c.weightNap = dbl("weightNap", c.weightNap)
            c.weightBall = dbl("weightBall", c.weightBall)
            c.weightHungry = dbl("weightHungry", c.weightHungry)
            c.weightPlay = dbl("weightPlay", c.weightPlay)
            c.inviteSeconds = num("inviteSeconds", c.inviteSeconds)
            c.followSeconds = num("followSeconds", c.followSeconds)
            c.dwellSeconds = num("dwellSeconds", c.dwellSeconds)
            c.followDepthShrink = num("followDepthShrink", c.followDepthShrink)
            c.petSeconds = num("petSeconds", c.petSeconds)
            c.furColor = str("furColor", c.furColor)
            c.furShadeColor = str("furShadeColor", c.furShadeColor)
            c.outlineColor = str("outlineColor", c.outlineColor)
            c.innerColor = str("innerColor", c.innerColor)
            c.eyeColor = str("eyeColor", c.eyeColor)
            c.ballColor = str("ballColor", c.ballColor)
            c.shadow = bool("shadow", c.shadow)
            c.chainChance = dbl("chainChance", c.chainChance)
            c.glassesChance = dbl("glassesChance", c.glassesChance)
            c.mode = str("mode", c.mode)
            c.crawlChance = dbl("crawlChance", c.crawlChance)
            c.idleCrawl = bool("idleCrawl", c.idleCrawl)
            c.idleCrawlSeconds = num("idleCrawlSeconds", c.idleCrawlSeconds)
            c.glitchStyleSeconds = num("glitchStyleSeconds", c.glitchStyleSeconds)
            c.growScale = num("growScale", c.growScale)
            c.activityLog = bool("activityLog", c.activityLog)
            c.activityLogDays = num("activityLogDays", c.activityLogDays)
            c.opacity = num("opacity", c.opacity)

            // The same clamps as the Mac, so a hand edit cannot crash a visit.
            c.sizeDivisor = clamp(c.sizeDivisor, 2f, 60f)
            c.roamHeight = clamp(c.roamHeight, 0.05f, 1f)
            c.groundBias = clamp(c.groundBias, 1f, 8f)
            c.maxSlope = clamp(c.maxSlope, 0f, 2f)
            c.wallChance = c.wallChance.coerceIn(0.0, 1.0)
            c.minGapSeconds = maxOf(3f, c.minGapSeconds)
            c.maxGapSeconds = maxOf(c.minGapSeconds, c.maxGapSeconds)
            c.opacity = clamp(c.opacity, 0.1f, 1f)
            c.napSecondsMin = maxOf(0f, c.napSecondsMin)
            c.napSecondsMax = maxOf(c.napSecondsMin, c.napSecondsMax)
            c.begSecondsMin = maxOf(0f, c.begSecondsMin)
            c.begSecondsMax = maxOf(c.begSecondsMin, c.begSecondsMax)
            c.playSecondsMin = maxOf(0f, c.playSecondsMin)
            c.playSecondsMax = maxOf(c.playSecondsMin, c.playSecondsMax)
            c.petSeconds = maxOf(0f, c.petSeconds)
            c.crawlChance = c.crawlChance.coerceIn(0.0, 1.0)
            c.idleCrawlSeconds = maxOf(15f, c.idleCrawlSeconds)
            c.glitchStyleSeconds = maxOf(5f, c.glitchStyleSeconds)
            c.growScale = clamp(c.growScale, 1f, 4f)
            c.chainChance = c.chainChance.coerceIn(0.0, 1.0)
            c.glassesChance = c.glassesChance.coerceIn(0.0, 1.0)
            return c
        }

        /** Writes the defaults if there is no file yet. */
        fun writeDefaultFileIfMissing(context: Context) {
            val f = file(context)
            if (!f.exists()) f.writeText(Config().toJson().toString(2))
        }

        /** Writes some keys back, leaving every other key exactly as it was. */
        fun update(context: Context, values: Map<String, Any>) {
            val raw = readRaw(context) ?: Config().toJson()
            for ((k, v) in values) raw.put(k, v)
            file(context).writeText(raw.toString(2))
        }
    }
}
