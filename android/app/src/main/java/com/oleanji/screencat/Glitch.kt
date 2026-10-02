package com.oleanji.screencat

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

// Crawler mode's "hack" effects. Everything here is paint on the cat's own
// overlay: the app underneath is never touched, it only looks broken for a few
// seconds and then "reboots".

/** The look of one breach. Picked at random each time. */
enum class GlitchStyle {
    // Cracks, RGB slices, scrolling hacker code, "SYSTEM BREACHED".
    BREACH,
    // Columns of falling characters.
    MATRIX,
    // A crash screen: ":(", "CAT.EXE HAS STOPPED" and a counting percentage.
    BLUE_SCREEN,
    // TV static, colour bars and "NO SIGNAL".
    NO_SIGNAL,
    // The area melts down in drips of colour.
    MELT,
}

/** The colours a breach can come in. */
val GLITCH_ACCENTS = listOf(
    argb(1f, 56, 255, 122),   // green
    argb(1f, 51, 230, 255),   // cyan
    argb(1f, 255, 77, 217),   // magenta
    argb(1f, 255, 191, 51),   // amber
    argb(1f, 255, 69, 77),    // red
    argb(1f, 179, 128, 255),  // purple
)

private val ALARM_RED = argb(1f, 255, 59, 92)

/** One area the cat has broken, in the same coordinates as the cat. */
class Breach(
    val rect: Box,
    // Where the zap landed. The cracks spread out from here.
    val touch: P,
    val seed: Int,
    val style: GlitchStyle = GlitchStyle.BREACH,
    // Index into GLITCH_ACCENTS.
    var accentIndex: Int = 0,
) {
    var age = 0f
    val duration = 4.2f

    val finished get() = age >= duration
    val accent get() = GLITCH_ACCENTS[accentIndex % GLITCH_ACCENTS.size]

    companion object {
        /** A breach in a random style and colour. */
        fun random(rect: Box, touch: P) = Breach(
            rect, touch, randomSeed(), GlitchStyle.entries.random(), rndInt(0, GLITCH_ACCENTS.size - 1),
        )
    }
}

/** Anything that has breaches and a zap to paint: both crawl routines. */
interface BreachSource {
    val breaches: List<Breach>
    val zap: Zap?
    // The glow while the cat powers up, if it is.
    val aura: Aura? get() = null
}

/** Rings pulsing out from the cat while it grows. */
data class Aura(val center: P, val size: Float, val progress: Float, val age: Float, val accentIndex: Int)

/** Three rings expanding and fading, with a flicker of sparks. */
fun drawAura(a: Aura, g: Gfx) {
    val accent = GLITCH_ACCENTS[a.accentIndex % GLITCH_ACCENTS.size]
    for (k in 0 until 3) {
        val phase = (a.age * 1.6f + k / 3f) % 1f
        val radius = a.size * (0.4f + phase * 1.5f)
        g.strokeOval(Box(a.center.x - radius, a.center.y - radius, radius * 2, radius * 2), accent.withAlpha((1 - phase) * 0.8f), 3f)
    }
    val sparks = GlitchRandom((a.age / 0.06f).toInt() + 99)
    for (i in 0 until 14) {
        val angle = sparks.range(0f, (PI * 2).toFloat())
        val d = a.size * sparks.range(0.5f, 1.6f)
        g.fill(a.center.x + cos(angle) * d - 2, a.center.y + sin(angle) * d - 2, 4f, 4f, accent)
    }
}

/** The bolt from the cat's head to the target, while it is "hacking" it. */
class Zap(val from: P, val to: P, var age: Float = 0f, var accentIndex: Int = 0) {
    val accent get() = GLITCH_ACCENTS[accentIndex % GLITCH_ACCENTS.size]
}

/** Fictional, harmless "hacker" lines for the scrolling code. */
private val FAKE_CODE = listOf(
    "> connecting to cat-net node 7 ...",
    "$ sudo purr --force --no-mercy",
    "inject --payload whiskers.bin",
    "bypass firewall :: port 443 OPEN",
    "decrypt(0x3F2A9C) -> ok",
    "while (true) { claw(memory); }",
    "sector 0x7FF2 corrupted",
    "rm -rf /system/naps/*",
    "kernel.panic(\"too many cats\")",
    "ssh root@app --whiskers",
    "override AUTH_TOKEN=meow",
    "hooking event loop ...",
    "patching memory @ 0x0C47",
    "exfiltrating yarn.db (2.3 MB)",
    "access level: ROOT",
    "for (i = 0; i < 9; i++) lives[i].backup()",
    "segfault in app.render()",
    "def pounce(target): return chaos",
    "chmod 777 /dev/catnip",
    "rewriting pixels ...",
    "ERROR 0xDEAD: app not responding",
    "trace: paw -> cursor -> window",
    "SYN  SYN  SYN  ACK",
    "compiling mischief.c ... done",
    "mount /dev/fishtank /mnt/snacks",
    "GET /api/v1/treats  200 OK",
    "deleting monday.exe ...",
    "fork() x 9 lives",
    "0101 1100 0011 1010 1110",
    "uploading hairball.zip",
)

/**
 * Paints a breach in its style. Every style fades in, darkens the area, does
 * its thing, then shows "REBOOTING..." and fades back to the real app.
 */
fun drawBreach(b: Breach, g: Gfx) {
    val fadeIn = min(1f, b.age / 0.25f)
    val fadeOut = min(1f, max(0f, (b.duration - b.age) / 0.6f))
    val envelope = fadeIn * fadeOut
    if (envelope <= 0.01f) return
    val r = b.rect
    val flicker = GlitchRandom(b.seed + (b.age / 0.07f).toInt())

    g.save()
    val before = g.globalAlpha
    g.globalAlpha = before * envelope
    g.clip(r)

    // Falling code only reads against near black.
    g.fill(r, gray(0f, if (b.style == GlitchStyle.MATRIX) 0.88f else 0.55f))

    when (b.style) {
        GlitchStyle.BREACH -> {
            breachScanlines(r, g)
            breachSlices(r, flicker, g)
            breachCracks(b, g)
            breachCode(b, r, g)
            breachBanner(b, r, flicker, g, listOf("SYSTEM BREACHED", "HACKED!"), ALARM_RED)
        }
        GlitchStyle.MATRIX -> {
            breachMatrix(b, r, g)
            breachBanner(b, r, flicker, g, listOf("ACCESS GRANTED", "ACCESS OK"), b.accent)
        }
        GlitchStyle.BLUE_SCREEN -> {
            breachBlueScreen(b, r, g)
            breachBanner(b, r, flicker, g, emptyList(), b.accent)
        }
        GlitchStyle.NO_SIGNAL -> {
            breachNoSignal(b, r, flicker, g)
            breachBanner(b, r, flicker, g, listOf("NO SIGNAL", "NO SIGNAL"), b.accent)
        }
        GlitchStyle.MELT -> {
            breachMelt(b, r, g)
            breachScanlines(r, g)
            breachBanner(b, r, flicker, g, listOf("MELTDOWN", "MELT"), b.accent)
        }
    }

    // A flickering border, like a target lock.
    g.strokeRect(r.insetBy(1.5f, 1.5f), b.accent.withAlpha(flicker.range(0.5f, 1f)), 3f)
    g.globalAlpha = before
    g.restore()
}

private fun breachScanlines(r: Box, g: Gfx) {
    var y = r.minY
    while (y < r.maxY) {
        g.fill(r.minX, y, r.width, 1f, gray(0f, 0.3f))
        y += 4
    }
}

/** Sliced, shifted bars in the two halves of an RGB split. */
private fun breachSlices(r: Box, flicker: GlitchRandom, g: Gfx) {
    val tints = listOf(argb(0.28f, 255, 0, 153), argb(0.28f, 0, 230, 255), gray(1f, 0.12f))
    for (i in 0 until 10) {
        val h = flicker.range(3f, 24f)
        g.fill(r.minX + flicker.range(-50f, 50f), flicker.range(r.minY, r.maxY - h),
               r.width * flicker.range(0.3f, 1.05f), h, tints[i % tints.size])
    }
}

/** Jagged cracks from the touch point. Their shape comes from the seed alone. */
private fun breachCracks(b: Breach, g: Gfx) {
    val grow = min(1f, max(0f, (b.age - 0.15f) / 0.9f))
    val eased = 1 - (1 - grow).pow(3)
    if (eased <= 0) return
    val reach = max(b.rect.width, b.rect.height) * 0.55f * eased
    val shape = GlitchRandom(b.seed)
    val base = shape.range(0f, (PI * 2).toFloat())
    val count = 7
    for (k in 0 until count) {
        var angle = base + k * PI.toFloat() * 2 / count + shape.range(-0.3f, 0.3f)
        var px = b.touch.x
        var py = b.touch.y
        val p = path { moveTo(px, py) }
        val segments = 7
        repeat(segments) {
            angle += shape.range(-0.5f, 0.5f)
            val step = reach / segments * shape.range(0.6f, 1.3f)
            px += cos(angle) * step
            py += sin(angle) * step
            p.lineTo(px, py)
        }
        g.strokePath(p, gray(0f, 0.7f), 3.5f)
        g.strokePath(p, gray(1f, 0.9f), 1.2f)
    }
}

/** Code scrolling up the left side, newest line at the bottom, typed out. */
private fun breachCode(b: Breach, r: Box, g: Gfx) {
    val lineHeight = 15f
    val rows = ((r.height - 20) / lineHeight).toInt()
    if (rows <= 0 || b.age <= 0.3f) return
    val typed = (b.age - 0.3f) * 11
    val shown = min(rows, typed.toInt() + 1)
    val first = ((b.seed.toLong() and 0xFFFFFFFFL) % FAKE_CODE.size).toInt()
    for (row in 0 until shown) {
        val index = typed.toInt() - row
        var text = FAKE_CODE[(first + max(0, index)) % FAKE_CODE.size]
        if (row == 0) {
            // The newest line types itself out, cursor and all.
            val chars = ((typed - floor(typed)) * text.length).toInt()
            text = text.take(chars) + "_"
        }
        val alpha = if (row == 0) 1f else max(0.35f, 0.95f - row * 0.03f)
        g.text(text, r.minX + 14, r.minY + 10 + row * lineHeight, 11f, b.accent.withAlpha(alpha))
    }
}

private const val RAIN_GLYPHS = "01アイウエオカキクケコサシスセソタチツテト$#@*<>=+ABCDEFXYZ"

/** Columns of falling characters, bright at the head and fading up the trail. */
private fun breachMatrix(b: Breach, r: Box, g: Gfx) {
    val colW = max(16f, r.width / 60)
    val rowH = 18f
    val cols = (r.width / colW).toInt()
    val columnRandom = GlitchRandom(b.seed)
    val charTick = (b.age / 0.09f).toInt()
    for (c in 0 until cols) {
        val speed = columnRandom.range(140f, 420f)
        val start = columnRandom.range(0f, r.height)
        val trail = columnRandom.range(5f, 13f).toInt()
        val span = r.height + trail * rowH
        val headY = r.maxY - (b.age * speed + start) % span
        val chars = GlitchRandom(b.seed + c * 977 + charTick)
        val x = r.minX + c * colW
        for (k in 0 until trail) {
            val y = headY + k * rowH
            if (y <= r.minY - rowH || y >= r.maxY) continue
            val ch = RAIN_GLYPHS[(chars.unit() * (RAIN_GLYPHS.length - 1)).toInt()]
            val isHead = k == 0
            val alpha = if (isHead) 1f else max(0.15f, 1 - k.toFloat() / trail)
            g.text(ch.toString(), x + 2, y + 1, 14f, (if (isHead) WHITE else b.accent).withAlpha(alpha), bold = true)
        }
    }
}

/** A pixel-font crash screen that counts its way up to "100%". */
private fun breachBlueScreen(b: Breach, r: Box, g: Gfx) {
    g.fill(r, argb(1f, 20, 84, 209))
    val percent = min(100, (max(0f, b.age - 0.4f) / 2.6f * 100).toInt())
    val lines = listOf("CAT.EXE HAS STOPPED", "STOP CODE: HAIRBALL", "COLLECTING CATNIP $percent%")
    val widest = (lines.maxOf { PixelFont.width(it) }).toFloat()
    val pixel = max(2f, min(6f, floor(r.width * 0.8f / widest)))
    val left = r.minX + max(12f, r.width * 0.08f)
    var y = r.maxY - max(20f, r.height * 0.18f)
    val face = pixel * 3
    y -= PixelFont.HEIGHT * face
    PixelFont.draw(":(", left, y, face, WHITE, g)
    y -= pixel * 6
    for (line in lines) {
        y -= PixelFont.HEIGHT * pixel + pixel * 3
        if (y <= r.minY + 6 || PixelFont.width(line) * pixel >= r.width - 12) continue
        PixelFont.draw(line, left, y, pixel, WHITE, g)
    }
}

/** TV static with a band of colour bars and a rolling bright bar. */
private fun breachNoSignal(b: Breach, r: Box, flicker: GlitchRandom, g: Gfx) {
    val block = max(10f, r.width / 70)
    var y = r.minY
    while (y < r.maxY) {
        var x = r.minX
        while (x < r.maxX) {
            if (flicker.unit() < 0.45f) g.fill(x, y, block, block, gray(flicker.range(0.15f, 0.9f), 0.85f))
            x += block
        }
        y += block
    }
    val bars = listOf(gray(0.8f), SYSTEM_YELLOW, SYSTEM_TEAL, SYSTEM_GREEN, SYSTEM_PINK, SYSTEM_RED, SYSTEM_BLUE)
    val band = Box(r.minX, r.midY - r.height * 0.15f, r.width, r.height * 0.3f)
    val barW = band.width / bars.size
    val shift = flicker.range(-12f, 12f)
    for ((i, colour) in bars.withIndex()) {
        g.fill(band.minX + i * barW + shift, band.minY, barW + 1, band.height, colour.withAlpha(0.85f))
    }
    val roll = r.minY + (b.age * r.height * 0.6f) % r.height
    g.fill(r.minX, roll, r.width, max(8f, r.height * 0.05f), gray(1f, 0.18f))
}

/** Drips of colour sliding down from the top edge, each at its own pace. */
private fun breachMelt(b: Breach, r: Box, g: Gfx) {
    val colW = max(8f, r.width / 60)
    val cols = kotlin.math.ceil(r.width / colW).toInt()
    val progress = min(1f, b.age / (b.duration - 1.2f))
    val eased = 1 - (1 - progress).pow(2)
    val columns = GlitchRandom(b.seed)
    val dark = mix(b.accent, BLACK, 0.45f)
    for (c in 0 until cols) {
        val length = r.height * eased * columns.range(0.25f, 1.05f)
        val x = r.minX + c * colW
        g.fill(x, r.maxY - length, colW + 0.5f, length, dark.withAlpha(0.9f))
        g.fill(x, r.maxY - length, colW + 0.5f, min(length, colW * 0.6f), b.accent)
        // A drop falling ahead of the drip now and then.
        if (columns.unit() < 0.3f) {
            val fall = (b.age * 260 * columns.range(0.6f, 1.4f)) % r.height
            g.fill(x + colW * 0.25f, r.maxY - length - fall, colW * 0.5f, colW * 0.8f, b.accent.withAlpha(0.8f))
        }
    }
}

/**
 * The style's banner in the pixel font, then "REBOOTING..." before it clears.
 * Empty `options` shows only the rebooting part.
 */
private fun breachBanner(b: Breach, r: Box, flicker: GlitchRandom, g: Gfx, options: List<String>, colour: Int) {
    val rebooting = b.age > b.duration - 1.1f
    if (b.age <= 0.6f) return
    if (!rebooting && options.isEmpty()) return
    // Blink on and off now and then, the way a warning does.
    if (!rebooting && flicker.unit() < 0.12f) return
    // The long wording when it fits at the smallest pixel size, else a short one.
    val choices = if (rebooting) listOf("REBOOTING...", "REBOOT") else options
    val text = choices.firstOrNull { (PixelFont.width(it) + 6) * 2f <= r.width * 0.9f } ?: choices.last()
    val tint = if (rebooting) b.accent else colour
    val widthPx = PixelFont.width(text).toFloat()
    val pixel = max(2f, min(5f, floor(r.width * 0.6f / widthPx)))
    val w = widthPx * pixel
    val h = PixelFont.HEIGHT * pixel
    val box = Box(r.midX - w / 2 - pixel * 3, r.midY - h / 2 - pixel * 3, w + pixel * 6, h + pixel * 6)
    g.fill(box, gray(0f, 0.85f))
    g.strokeRect(box.insetBy(pixel / 2, pixel / 2), tint, pixel)
    PixelFont.draw(text, Math.round(r.midX - w / 2).toFloat(), Math.round(r.midY - h / 2).toFloat(), pixel, tint, g)
}

/** A jittery bolt from the cat to the area it is hacking. */
fun drawZap(z: Zap, g: Gfx) {
    val jitter = GlitchRandom((z.age / 0.05f).toInt() + 7)
    val segments = 9
    val dx = z.to.x - z.from.x
    val dy = z.to.y - z.from.y
    val len = max(1f, hypot(dx, dy))
    val nx = -dy / len
    val ny = dx / len
    val p = path {
        moveTo(z.from.x, z.from.y)
        for (i in 1 until segments) {
            val t = i.toFloat() / segments
            val off = jitter.range(-8f, 8f)
            lineTo(z.from.x + dx * t + nx * off, z.from.y + dy * t + ny * off)
        }
        lineTo(z.to.x, z.to.y)
    }
    g.strokePath(p, z.accent.withAlpha(0.3f), 7f)
    g.strokePath(p, z.accent, 2f)
    // Sparks where it lands.
    for (i in 0 until 6) {
        val a = jitter.range(0f, (PI * 2).toFloat())
        val d = jitter.range(3f, 14f)
        g.fill(z.to.x + cos(a) * d - 1.5f, z.to.y + sin(a) * d - 1.5f, 3f, 3f, z.accent)
    }
}
