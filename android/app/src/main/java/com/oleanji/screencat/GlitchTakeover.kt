package com.oleanji.screencat

import com.oleanji.screencat.TakeoverLayer.*
import java.util.Locale
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

// The full-screen glitch for the idle crawl. Fifty named styles, each a stack
// of effect layers in its own colours. One style plays for about a minute,
// then the next takes over. It is all paint on the overlay; no app is touched.
//
// It renders at half resolution into a bitmap shown with nearest-neighbour
// scaling: chunky pixels suit a glitch, and it keeps a full-screen effect
// cheap enough to run for as long as you are away.

/** One effect. A style stacks a few of these. */
sealed class TakeoverLayer {
    object Scanlines : TakeoverLayer()
    object Slices : TakeoverLayer()
    object StaticNoise : TakeoverLayer()
    object ColorBars : TakeoverLayer()
    object RollingBar : TakeoverLayer()
    object Tint : TakeoverLayer()
    object Tears : TakeoverLayer()
    class Matrix(val chars: String) : TakeoverLayer()
    object HexWall : TakeoverLayer()
    object CodeWall : TakeoverLayer()
    object BlueScreen : TakeoverLayer()
    object Melt : TakeoverLayer()
    object PixelSort : TakeoverLayer()
    object Vhs : TakeoverLayer()
    object Blocks : TakeoverLayer()
    object Cracks : TakeoverLayer()
    object Popups : TakeoverLayer()
    object Radar : TakeoverLayer()
    object Tunnel : TakeoverLayer()
    object Warp : TakeoverLayer()
    object Scope : TakeoverLayer()
    object Heartbeat : TakeoverLayer()
    object GridFloor : TakeoverLayer()
    object Waves : TakeoverLayer()
    object Checker : TakeoverLayer()
    object Loading : TakeoverLayer()
    object Virus : TakeoverLayer()
    object DataStream : TakeoverLayer()
    // Big pixel-font words. "#" counts down from 10.
    class BigText(val options: List<String>) : TakeoverLayer()
    // A word tiled over the whole screen in scrolling rows.
    class Tiled(val word: String) : TakeoverLayer()
}

class GlitchRecipe(
    val name: String,
    // How dark the screen goes under the effect, 0 to 1.
    val dim: Float,
    val layers: List<TakeoverLayer>,
    val palette: List<Int>,
)

// Danger colours only: blood red, terminal green, warning amber, white on
// black. Each palette is [main, highlight, deep].
private val TOXIC = listOf(rgb(0x00FF41), rgb(0xB6FF3B), rgb(0x003B10))
private val ICE = listOf(rgb(0x00FF41), rgb(0xFFFFFF), rgb(0x0A2A0A))
private val HOT_PINK = listOf(rgb(0xFF0033), rgb(0x00FF41), rgb(0x2A0008))
private val AMBER = listOf(rgb(0xFFB000), rgb(0xFF3B00), rgb(0x2B1600))
private val BLOOD = listOf(rgb(0xFF0033), rgb(0xFF5C5C), rgb(0x4D0000))
private val SYNTH = listOf(rgb(0xFF0033), rgb(0xFFFFFF), rgb(0x00FF41))
private val GHOST = listOf(rgb(0xFFFFFF), rgb(0xFF0033), rgb(0x333333))
private val ROYAL = listOf(rgb(0xFF0033), rgb(0xFFB000), rgb(0x1A0000))
private val SUNSET = listOf(rgb(0xFF3B00), rgb(0xFFB000), rgb(0x2B0A00))
private val VOID = listOf(rgb(0xFF0033), rgb(0x8B0000), rgb(0x0D0000))

private const val KANA = "アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789"


/** The fifty styles, the same names, layers and palettes as the Mac. */
val GLITCH_RECIPES: List<GlitchRecipe> = listOf(
    GlitchRecipe("Green Breach", 0.7f, listOf(Scanlines, Slices, CodeWall, Cracks, BigText(listOf("SYSTEM BREACHED", "BREACHED"))), TOXIC),
    GlitchRecipe("Digital Rain", 0.92f, listOf(Matrix(KANA), RollingBar), TOXIC),
    GlitchRecipe("Binary Rain", 0.92f, listOf(Matrix("01"), Scanlines), ICE),
    GlitchRecipe("Blood Rain", 0.92f, listOf(Matrix(KANA), Tint), HOT_PINK),
    GlitchRecipe("Kernel Panic", 1f, listOf(BlueScreen), ICE),
    GlitchRecipe("No Signal", 0.7f, listOf(StaticNoise, ColorBars, RollingBar, BigText(listOf("NO SIGNAL"))), GHOST),
    GlitchRecipe("Amber Static", 0.75f, listOf(StaticNoise, Scanlines, Tint), AMBER),
    GlitchRecipe("Meltdown", 0.7f, listOf(Melt, Scanlines, BigText(listOf("MELTDOWN"))), BLOOD),
    GlitchRecipe("Pixel Sort", 0.78f, listOf(PixelSort, Tears), SYNTH),
    GlitchRecipe("VHS Rewind", 0.85f, listOf(ColorBars, Waves, Vhs, Tears, Scanlines), SUNSET),
    GlitchRecipe("Corrupt Blocks", 0.72f, listOf(Blocks, Slices, Scanlines), SYNTH),
    GlitchRecipe("Shatter", 0.78f, listOf(Cracks, Tears, Tint), GHOST),
    GlitchRecipe("Error Storm", 0.62f, listOf(Popups, Scanlines), ROYAL),
    GlitchRecipe("Radar Lock", 0.92f, listOf(Radar, Scanlines), TOXIC),
    GlitchRecipe("Tunnel", 0.88f, listOf(Tunnel, Scanlines), HOT_PINK),
    GlitchRecipe("Warp Speed", 0.96f, listOf(Warp), ICE),
    GlitchRecipe("Oscilloscope", 0.92f, listOf(Scope, Scanlines), TOXIC),
    GlitchRecipe("Flatline", 0.94f, listOf(Heartbeat, Scanlines), BLOOD),
    GlitchRecipe("Grid Runner", 0.96f, listOf(GridFloor, Scanlines), SYNTH),
    GlitchRecipe("RGB Waves", 0.78f, listOf(Waves, Slices), SYNTH),
    GlitchRecipe("Checker Panic", 0.72f, listOf(Checker, BigText(listOf("ALERT"))), BLOOD),
    GlitchRecipe("Root Wall", 0.88f, listOf(Tiled("ROOT ACCESS"), Scanlines), ROYAL),
    GlitchRecipe("Hacked Wall", 0.88f, listOf(Tiled("HACKED"), Slices), TOXIC),
    GlitchRecipe("Download Everything", 0.92f, listOf(HexWall, Loading), AMBER),
    GlitchRecipe("Worm Outbreak", 0.85f, listOf(Virus, BigText(listOf("WORM SPREADING", "INFECTED"))), TOXIC),
    GlitchRecipe("Hex Dump", 0.94f, listOf(HexWall, RollingBar), AMBER),
    GlitchRecipe("Root Shell", 0.94f, listOf(CodeWall, Scanlines), TOXIC),
    GlitchRecipe("Data Stream", 0.92f, listOf(DataStream, Scanlines), ICE),
    GlitchRecipe("Red Haze", 0.8f, listOf(Waves, Tint, StaticNoise), VOID),
    GlitchRecipe("Ghost Signal", 0.78f, listOf(StaticNoise, Tears, BigText(listOf("WE ARE INSIDE", "INSIDE"))), GHOST),
    GlitchRecipe("Red Alert", 0.82f, listOf(RollingBar, Checker, BigText(listOf("SELF DESTRUCT IN #", "BOOM IN #"))), BLOOD),
    GlitchRecipe("Firewall Melt", 0.72f, listOf(Melt, Waves), SUNSET),
    GlitchRecipe("Breach Tunnel", 0.92f, listOf(Tunnel, Warp), SYNTH),
    GlitchRecipe("Matrix Breach", 0.88f, listOf(Matrix(KANA), Cracks, BigText(listOf("ACCESS GRANTED", "GRANTED"))), TOXIC),
    GlitchRecipe("Static Rain", 0.85f, listOf(StaticNoise, Matrix("01")), GHOST),
    GlitchRecipe("Glitch Mosaic", 0.72f, listOf(Blocks, Checker), ROYAL),
    GlitchRecipe("Broken Display", 0.72f, listOf(Tears, ColorBars, Slices, Cracks), GHOST),
    GlitchRecipe("Radar Rain", 0.92f, listOf(Radar, Matrix("01")), ICE),
    GlitchRecipe("Signal Intercept", 0.96f, listOf(GridFloor, Scope), SYNTH),
    GlitchRecipe("Access Denied", 0.75f, listOf(Tiled("ACCESS DENIED"), Popups), BLOOD),
    GlitchRecipe("Infection", 0.85f, listOf(Virus, CodeWall), HOT_PINK),
    GlitchRecipe("Deep Sort", 0.75f, listOf(PixelSort, RollingBar, Scanlines), VOID),
    GlitchRecipe("Ransomware", 0.9f, listOf(Tiled("PAY 5 BTC"), DataStream, BigText(listOf("YOUR FILES ARE ENCRYPTED", "ENCRYPTED"))), AMBER),
    GlitchRecipe("Heartbeat Grid", 0.94f, listOf(GridFloor, Heartbeat), TOXIC),
    GlitchRecipe("Lockdown", 0.78f, listOf(Checker, Tint, Cracks), ICE),
    GlitchRecipe("Fatal Exception", 1f, listOf(BlueScreen, Tears), BLOOD),
    GlitchRecipe("Signal Lost", 0.75f, listOf(Vhs, StaticNoise, BigText(listOf("SIGNAL LOST", "LOST"))), AMBER),
    GlitchRecipe("Laser Grid", 0.94f, listOf(GridFloor, Radar), BLOOD),
    GlitchRecipe("Hyperdrive", 0.96f, listOf(Warp, Tunnel), VOID),
    GlitchRecipe("Total Chaos", 0.72f, listOf(Blocks, Slices, Tears, Popups, Cracks), SYNTH),
)

/** The "starting in" screen before Zero Day. `n` is the seconds left. */
fun countdownRecipe(n: Int) = GlitchRecipe(
    "Countdown", 0.6f, listOf(Scanlines, Tears, BigText(listOf("ZERO DAY IN $n", "$n"))), TOXIC,
)

// Rendering -------------------------------------------------------------------

/**
 * Paints one frame of `recipe`, `t` seconds in, filling `r`. `pulse` (0 to 1)
 * flashes the screen when the cat zaps something.
 */
fun renderTakeover(recipe: GlitchRecipe, r: Box, t: Float, seed: Int, pulse: Float, g: Gfx) {
    g.save()
    g.antialias = false
    g.clip(r)
    g.fill(r, gray(0f, recipe.dim))
    val pal = recipe.palette
    for (layer in recipe.layers) {
        val f = GlitchRandom(seed + (max(0f, t) * 20).toInt())
        when (layer) {
            Scanlines -> scanlines(r, g)
            Slices -> slices(r, pal, f, g)
            StaticNoise -> staticNoise(r, pal, f, g)
            ColorBars -> colorBars(r, f, g)
            RollingBar -> rollingBar(r, t, g)
            Tint -> g.fill(r, pal[0].withAlpha(0.14f))
            Tears -> tears(r, pal, f, g)
            is Matrix -> matrix(r, t, pal, seed, layer.chars, g)
            HexWall -> hexWall(r, t, pal, seed, g)
            CodeWall -> codeWall(r, t, pal, seed, g)
            BlueScreen -> blueScreen(r, t, pal, g)
            Melt -> melt(r, t, pal, seed, g)
            PixelSort -> pixelSort(r, t, pal, seed, g)
            Vhs -> vhs(r, t, pal, f, g)
            Blocks -> blocks(r, pal, f, g)
            Cracks -> cracks(r, t, seed, g)
            Popups -> popups(r, t, pal, seed, g)
            Radar -> radar(r, t, pal, seed, g)
            Tunnel -> tunnel(r, t, pal, g)
            Warp -> warp(r, t, pal, seed, g)
            Scope -> scope(r, t, pal, g)
            Heartbeat -> heartbeat(r, t, pal, f, g)
            GridFloor -> gridFloor(r, t, pal, g)
            Waves -> waves(r, t, pal, g)
            Checker -> checker(r, t, pal, f, g)
            Loading -> loading(r, t, pal, g)
            Virus -> virus(r, t, pal, seed, f, g)
            DataStream -> dataStream(r, t, pal, seed, g)
            is BigText -> bigText(r, t, pal, layer.options, f, g)
            is Tiled -> tiled(r, t, pal, layer.word, g)
        }
    }
    // Flashes are alarm red, with now and then a white one.
    if (pulse > 0.01f) {
        val white = (seed.toLong() and 0xFFFFFFFFL) % 4 == 0L
        g.fill(r, (if (white) WHITE else argb(1f, 255, 0, 51)).withAlpha(0.4f * pulse))
    }
    g.antialias = true
    g.restore()
}

private fun stroke(p: android.graphics.Path, colour: Int, width: Float, g: Gfx, glow: Boolean = false) {
    if (glow) g.strokePath(p, colour.withAlpha(0.25f), width * 4)
    g.strokePath(p, colour, width)
}

private fun scanlines(r: Box, g: Gfx) {
    var y = r.minY
    while (y < r.maxY) { g.fill(r.minX, y, r.width, 2f, gray(0f, 0.35f)); y += 6 }
}

private fun slices(r: Box, pal: List<Int>, f: GlitchRandom, g: Gfx) {
    for (i in 0 until 16) {
        val h = f.range(4f, 40f)
        g.fill(r.minX + f.range(-80f, 80f), f.range(r.minY, r.maxY - h), r.width * f.range(0.3f, 1.1f), h,
               pal[i % pal.size].withAlpha(0.3f))
    }
}

private fun staticNoise(r: Box, pal: List<Int>, f: GlitchRandom, g: Gfx) {
    val block = max(10f, r.width / 90)
    var y = r.minY
    while (y < r.maxY) {
        var x = r.minX
        while (x < r.maxX) {
            val roll = f.unit()
            if (roll < 0.4f) {
                g.fill(x, y, block, block, gray(f.range(0.1f, 0.95f), 0.85f))
            } else if (roll < 0.46f) {
                g.fill(x, y, block, block, pal[(f.unit() * 2.99f).toInt()].withAlpha(0.8f))
            }
            x += block
        }
        y += block
    }
}

private fun colorBars(r: Box, f: GlitchRandom, g: Gfx) {
    val bars = listOf(gray(0.85f), rgb(0xFF0033), BLACK, rgb(0x00FF41), rgb(0xFFB000), rgb(0x8B0000), BLACK)
    val band = Box(r.minX, r.midY - r.height * 0.18f, r.width, r.height * 0.36f)
    val w = band.width / bars.size
    val shift = f.range(-20f, 20f)
    for ((i, c) in bars.withIndex()) g.fill(band.minX + i * w + shift, band.minY, w + 1, band.height, c.withAlpha(0.85f))
}

private fun rollingBar(r: Box, t: Float, g: Gfx) {
    val y = r.minY + (t * r.height * 0.35f) % r.height
    g.fill(r.minX, y, r.width, max(12f, r.height * 0.06f), gray(1f, 0.16f))
}

private fun tears(r: Box, pal: List<Int>, f: GlitchRandom, g: Gfx) {
    for (i in 0 until 28) {
        val y = f.range(r.minY, r.maxY)
        val x = r.minX + f.range(-40f, r.width * 0.5f)
        val colour = if (i % 3 == 0) WHITE else pal[i % pal.size]
        val a = f.range(0.35f, 0.8f)
        g.fill(x, y, r.width * f.range(0.2f, 0.9f), f.range(1f, 4f), colour.withAlpha(a))
    }
}

private fun matrix(r: Box, t: Float, pal: List<Int>, seed: Int, chars: String, g: Gfx) {
    val colW = max(18f, r.width / 80)
    val rowH = 20f
    val columns = GlitchRandom(seed)
    val tick = (t / 0.1f).toInt()
    for (c in 0 until (r.width / colW).toInt()) {
        val speed = columns.range(120f, 420f)
        val start = columns.range(0f, r.height)
        val trail = columns.range(8f, 22f).toInt()
        val span = r.height + trail * rowH
        val head = r.maxY - (t * speed + start) % span
        val glyphs = GlitchRandom(seed + c * 977 + tick)
        val x = r.minX + c * colW
        for (k in 0 until trail) {
            val y = head + k * rowH
            if (y <= r.minY - rowH || y >= r.maxY) { glyphs.unit(); continue }
            val ch = chars[(glyphs.unit() * (chars.length - 1)).toInt()]
            val colour = if (k == 0) WHITE else pal[if (k % 7 == 3) 1 else 0]
            val alpha = if (k == 0) 1f else max(0.12f, 1 - k.toFloat() / trail)
            g.text(ch.toString(), x + 2, y + 1, 15f, colour.withAlpha(alpha), bold = true)
        }
    }
}

private fun hexWall(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val lineH = 16f
    val scroll = (t * 7).toInt()
    val rows = (r.height / lineH).toInt() + 1
    val highlight = (scroll / 5) % max(1, rows)
    for (row in 0 until rows) {
        val rand = GlitchRandom(seed + (row + scroll) * 131)
        val line = StringBuilder(String.format(Locale.US, "%08X  ", (row + scroll) * 16))
        repeat(16) { line.append(String.format(Locale.US, "%02X ", (rand.unit() * 255).toInt())) }
        line.append(' ')
        repeat(12) { line.append((33 + (rand.unit() * 90).toInt()).toChar()) }
        val colour = if (row == highlight) pal[1] else pal[0].withAlpha(0.55f + 0.4f * rand.unit())
        var x = r.minX + 12
        val text = line.toString()
        while (x < r.maxX) {
            g.text(text, x, r.maxY - (row + 1) * lineH, 12f, colour)
            x += 560
        }
    }
}

private val WALL_CODE = listOf(
    "> connecting to 185.220.101.47:22 ...", "\$ nmap -sS -p- 10.0.0.0/24 --open",
    "PORT     STATE SERVICE", "22/tcp   open  ssh",
    "443/tcp  open  https", "\$ ssh -i id_rsa root@10.0.0.14",
    "Permission denied (publickey).", "\$ hydra -l admin -P rockyou.txt ssh://10.0.0.14",
    "[22][ssh] login: admin  password: ********", "bypassing firewall ... rule 0x1F dropped",
    "decrypt(0x3F2A9C) -> ok", "dumping /etc/shadow ...",
    "root:\$6\$Zx9Q...:19622:0:99999:7:::", "privilege escalation: CVE-20XX-0000 ... ok",
    "uid=0(root) gid=0(root)", "\$ curl -s http://10.0.0.14/admin.php?id=1' OR '1'='1",
    "injecting payload stage2.bin (48 KB)", "spawning reverse shell -> 185.220.101.47:4444",
    "keylogger attached to pid 4127", "exfiltrating /Users/*/Documents (2.3 GB)",
    "wiping logs: /var/log/*.log", "kernel: segfault at 0x00007ffd in libsystem",
    "ERROR 0xDEAD: process not responding", "rerouting traffic through 7 proxies",
    "hash cracked: 5f4dcc3b5aa765d61d8327deb882cf99", "AES-256 key found: 9b2e...c41f",
    "mounting /dev/disk2s1 /mnt/target", "GET /api/v1/users  200 OK",
    "0101 1100 0011 1010 1110", "establishing persistence: launchd.plist",
)

private fun codeWall(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val lineH = 16f
    val colW = 420f
    val columns = max(1, (r.width / colW).toInt())
    val rows = (r.height / lineH).toInt()
    val typed = t * 9
    val n = WALL_CODE.size
    for (c in 0 until columns) {
        val offset = ((seed.toLong() and 0xFFFFFFFFL) % 97).toInt() + c * 7
        for (row in 0 until rows) {
            val index = typed.toInt() - row + offset + c * 3
            var text = WALL_CODE[((index % n) + n) % n]
            if (row == 0) text = text.take(((typed - floor(typed)) * text.length).toInt()) + "_"
            val colour = if (row == 0) pal[1] else pal[0].withAlpha(max(0.3f, 1 - row.toFloat() / rows))
            g.text(text, r.minX + 16 + c * colW, r.minY + 12 + row * lineH, 12f, colour)
        }
    }
}

/** Pixel-font text, fitted to `maxWidth`. Returns the pixel size used. */
private fun pixelText(text: String, cx: Float, cy: Float, maxWidth: Float, maxPixel: Float, colour: Int,
                      g: Gfx, box: Boolean = false): Float {
    val w = PixelFont.width(text).toFloat()
    val p = max(2f, min(maxPixel, floor(maxWidth / max(1f, w))))
    val width = w * p
    val height = PixelFont.HEIGHT * p
    val ox = (cx - width / 2).roundToInt().toFloat()
    val oy = (cy - height / 2).roundToInt().toFloat()
    if (box) {
        val frame = Box(ox - p * 3, oy - p * 3, width + p * 6, height + p * 6)
        g.fill(frame, gray(0f, 0.85f))
        g.strokeRect(frame.insetBy(p / 2, p / 2), colour, p)
    }
    PixelFont.draw(text, ox, oy, p, colour, g)
    return p
}

private fun blueScreen(r: Box, t: Float, pal: List<Int>, g: Gfx) {
    g.fill(r, mix(pal[2], BLACK, 0.15f))
    val percent = min(100, (t * 1.7f).toInt())
    val lines = listOf("YOUR SYSTEM HAS BEEN COMPROMISED", "KERNEL PANIC: NOT SYNCING", "STOP CODE: 0XC000021A", "UPLOADING MEMORY DUMP $percent%")
    val widest = lines.maxOf { PixelFont.width(it) }.toFloat()
    val p = max(2f, min(7f, floor(r.width * 0.75f / widest)))
    val left = r.minX + r.width * 0.1f
    var y = r.maxY - r.height * 0.2f
    y -= PixelFont.HEIGHT * p * 3
    PixelFont.draw(":(", left, y, p * 3, WHITE, g)
    y -= p * 8
    for (line in lines) {
        y -= PixelFont.HEIGHT * p + p * 4
        PixelFont.draw(line, left, y, p, WHITE, g)
    }
}

private fun melt(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val colW = max(10f, r.width / 80)
    val phase = (t / 14) % 1f
    val eased = 1 - (1 - phase).pow(2)
    val cols = GlitchRandom(seed)
    val dark = pal[2]
    for (c in 0 until ceil(r.width / colW).toInt()) {
        val length = r.height * eased * cols.range(0.3f, 1.1f)
        val x = r.minX + c * colW
        g.fill(x, r.maxY - length, colW + 0.5f, length, dark.withAlpha(0.9f))
        g.fill(x, r.maxY - length, colW + 0.5f, min(length, colW), pal[0])
        if (cols.unit() < 0.35f) {
            val fall = (t * 300 * cols.range(0.6f, 1.4f)) % r.height
            g.fill(x + colW * 0.25f, r.maxY - length - fall, colW * 0.5f, colW, pal[1])
        }
    }
}

private fun pixelSort(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val colW = max(6f, r.width / 140)
    val cols = GlitchRandom(seed)
    for (c in 0 until (r.width / colW).toInt()) {
        val x = r.minX + c * colW
        val base = cols.range(r.minY, r.maxY)
        val speed = cols.range(0.5f, 2.5f)
        val phase = cols.range(0f, 6.28f)
        val h = r.height * (0.15f + 0.35f * (0.5f + 0.5f * sin(t * speed + phase)))
        val colour = pal[(cols.unit() * 2.99f).toInt()]
        for (s in 0 until 5) g.fill(x, base - s * h / 5, colW, h / 5, colour.withAlpha(0.85f - s * 0.16f))
    }
}

private fun vhs(r: Box, t: Float, pal: List<Int>, f: GlitchRandom, g: Gfx) {
    val bandH = r.height * 0.12f
    val bandY = r.maxY - (t * r.height * 0.25f) % (r.height + bandH)
    var y = bandY
    while (y < bandY + bandH) {
        val c = gray(f.range(0.3f, 1f), 0.6f)
        g.fill(r.minX + f.range(-30f, 30f), y, r.width, 3f, c)
        y += 5
    }
    val secs = t.toInt() % 60
    val mins = (t.toInt() / 60) % 60
    PixelFont.draw("PLAY", r.minX + 40, r.maxY - 70, 5f, WHITE, g)
    PixelFont.draw(String.format(Locale.US, "00:%02d:%02d", mins, secs), r.minX + 40, r.minY + 40, 5f, pal[0], g)
}

private fun blocks(r: Box, pal: List<Int>, f: GlitchRandom, g: Gfx) {
    repeat(46) {
        val w = f.range(20f, 180f)
        val h = f.range(14f, 120f)
        val rect = Box(f.range(r.minX, r.maxX - w), f.range(r.minY, r.maxY - h), w, h)
        val colour = pal[(f.unit() * 2.99f).toInt()]
        g.fill(rect, colour.withAlpha(f.range(0.4f, 0.9f)))
        if (f.unit() < 0.4f) g.fill(rect.minX, rect.midY, rect.width, 2f, gray(1f, 0.5f))
    }
}

private fun cracks(r: Box, t: Float, seed: Int, g: Gfx) {
    val cycle = 8f
    val round = (t / cycle).toInt()
    val grow = min(1f, (t % cycle) / 2.5f)
    val shape = GlitchRandom(seed + round * 31)
    val reach = max(r.width, r.height) * 0.35f * (1 - (1 - grow).pow(3))
    repeat(4) {
        val ox = shape.range(r.minX, r.maxX)
        val oy = shape.range(r.minY, r.maxY)
        for (k in 0 until 8) {
            var angle = k * PI.toFloat() / 4 + shape.range(-0.3f, 0.3f)
            var px = ox
            var py = oy
            val p = path { moveTo(ox, oy) }
            repeat(7) {
                angle += shape.range(-0.5f, 0.5f)
                val step = reach / 7 * shape.range(0.6f, 1.3f)
                px += cos(angle) * step
                py += sin(angle) * step
                p.lineTo(px, py)
            }
            stroke(p, gray(0f, 0.7f), 4f, g)
            stroke(p, gray(1f, 0.9f), 1.5f, g)
        }
    }
}

private val POPUP_MESSAGES = listOf("ACCESS DENIED", "SEGMENTATION FAULT", "FIREWALL DISABLED", "DISK ENCRYPTED", "CONNECTION HIJACKED")

private fun popups(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val shown = (t * 1.6f).toInt() + 2
    val first = max(0, shown - 36)
    for (i in first until shown) {
        val rand = GlitchRandom(seed + i * 7919)
        val w = rand.range(220f, 320f)
        val h = rand.range(100f, 130f)
        val box = Box(rand.range(r.minX, r.maxX - w), rand.range(r.minY, r.maxY - h), w, h)
        g.fill(box.offsetBy(6f, -6f), gray(0f, 0.4f))
        g.fill(box, gray(0.93f))
        g.fill(box.minX, box.maxY - 22, w, 22f, pal[i % pal.size])
        PixelFont.draw("ERROR", box.minX + 10, box.maxY - 18, 2f, WHITE, g)
        PixelFont.draw(POPUP_MESSAGES[i % POPUP_MESSAGES.size], box.minX + 12, box.midY - 6, 2f, gray(0.15f), g)
        val ok = Box(box.maxX - 60, box.minY + 10, 48f, 22f)
        g.fill(ok, gray(0.8f))
        PixelFont.draw("OK", ok.minX + 15, ok.minY + 4, 2f, gray(0.15f), g)
    }
}

private fun radar(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val cx = r.midX
    val cy = r.midY
    val radius = min(r.width, r.height) * 0.46f
    for (i in 1..5) {
        val rr = radius * i / 5
        val ring = path { addOval(cx - rr, cy - rr, cx + rr, cy + rr, android.graphics.Path.Direction.CCW) }
        stroke(ring, pal[0].withAlpha(0.45f), 2f, g)
    }
    val cross = path {
        moveTo(cx - radius, cy); lineTo(cx + radius, cy)
        moveTo(cx, cy - radius); lineTo(cx, cy + radius)
    }
    stroke(cross, pal[0].withAlpha(0.35f), 1.5f, g)
    val angle = t * 1.8f
    for (k in 0 until 24) {
        val a0 = angle - k * 0.03f
        g.fillWedge(cx, cy, radius, a0 - 0.03f, a0, pal[0].withAlpha(0.4f * (1 - k / 24f)))
    }
    val blips = GlitchRandom(seed)
    repeat(10) {
        val a = blips.range(0f, (PI * 2).toFloat())
        val d = blips.range(0.15f, 0.95f) * radius
        val since = (angle - a) % (PI * 2).toFloat()
        val fade = if (since < 0) 0f else max(0f, 1 - since / 3)
        g.fillOval(Box(cx + cos(a) * d - 6, cy + sin(a) * d - 6, 12f, 12f), pal[1].withAlpha(fade))
    }
}

private fun tunnel(r: Box, t: Float, pal: List<Int>, g: Gfx) {
    val cx = r.midX
    val cy = r.midY
    for (i in 0 until 16) {
        val z = (t * 0.35f + i / 16f) % 1f
        val s = z * z
        val rect = Box(cx - r.width * s * 0.6f, cy - r.height * s * 0.6f, r.width * s * 1.2f, r.height * s * 1.2f)
        val p = path { addRect(rect.minX, rect.minY, rect.maxX, rect.maxY, android.graphics.Path.Direction.CW) }
        stroke(p, pal[i % pal.size].withAlpha(z), 2 + 6 * z, g, glow = true)
    }
}

private fun warp(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val cx = r.midX
    val cy = r.midY
    val maxR = hypot(r.width, r.height) * 0.55f
    val stars = GlitchRandom(seed)
    for (i in 0 until 240) {
        val a = stars.range(0f, (PI * 2).toFloat())
        val speed = stars.range(0.15f, 0.6f)
        val z = (t * speed + stars.unit()) % 1f
        val d = z * z * maxR
        val tail = d * 0.82f
        val p = path {
            moveTo(cx + cos(a) * tail, cy + sin(a) * tail)
            lineTo(cx + cos(a) * d, cy + sin(a) * d)
        }
        val colour = if (i % 4 == 0) pal[i % pal.size] else WHITE
        stroke(p, colour.withAlpha(min(1f, z * 1.6f)), 1 + 3 * z, g)
    }
}

private fun scope(r: Box, t: Float, pal: List<Int>, g: Gfx) {
    var gx = r.minX
    while (gx < r.maxX) { g.fill(gx, r.minY, 1f, r.height, gray(1f, 0.06f)); gx += 60 }
    var gy = r.minY
    while (gy < r.maxY) { g.fill(r.minX, gy, r.width, 1f, gray(1f, 0.06f)); gy += 60 }
    for (w in 0 until 3) {
        val amp = r.height * (0.12f + 0.08f * w) * (1 + 0.3f * sin(t * 0.7f + w))
        val freq = 0.006f + 0.004f * w
        val mid = r.midY + (w - 1) * r.height * 0.18f
        val p = path {
            var x = r.minX
            moveTo(x, mid)
            while (x <= r.maxX) {
                lineTo(x, mid + amp * sin(x * freq + t * (2 + w)))
                x += 6
            }
        }
        stroke(p, pal[w], 3f, g, glow = true)
    }
}

private fun ecg(p: Float): Float = when {
    p >= 0.40f && p < 0.44f -> (p - 0.40f) / 0.04f * 0.2f
    p >= 0.44f && p < 0.47f -> 0.2f - (p - 0.44f) / 0.03f * 0.5f
    p >= 0.47f && p < 0.50f -> -0.3f + (p - 0.47f) / 0.03f * 1.3f
    p >= 0.50f && p < 0.54f -> 1.0f - (p - 0.50f) / 0.04f * 1.0f
    p >= 0.62f && p < 0.70f -> 0.15f * sin((p - 0.62f) / 0.08f * PI.toFloat())
    else -> 0f
}

private fun heartbeat(r: Box, t: Float, pal: List<Int>, f: GlitchRandom, g: Gfx) {
    val amp = r.height * 0.28f
    val p = path {
        var x = r.minX
        moveTo(x, r.midY)
        while (x <= r.maxX) {
            val q = ((x - r.minX) / r.width * 3 - t * 0.9f) % 1f
            lineTo(x, r.midY + ecg(if (q < 0) q + 1 else q) * amp)
            x += 4
        }
    }
    stroke(p, pal[0], 4f, g, glow = true)
    val bpm = 180 + (f.unit() * 819).toInt()
    PixelFont.draw("BPM $bpm", r.maxX - 360, r.maxY - 90, 8f, pal[1], g)
}

private fun gridFloor(r: Box, t: Float, pal: List<Int>, g: Gfx) {
    val horizon = r.minY + r.height * 0.42f
    val sunR = r.height * 0.22f
    val sun = Box(r.midX - sunR, horizon - sunR * 0.3f, sunR * 2, sunR * 2)
    g.fillOvalGradient(sun, pal[2], pal[0])
    for (i in 0 until 6) {
        val y = horizon + i * sunR * 0.18f
        g.fill(sun.minX, y, sun.width, (i + 1) * 2f, gray(0f, 0.9f))
    }
    g.fill(r.minX, r.minY, r.width, horizon - r.minY, gray(0f, 1f))
    val lines = path {
        for (i in -20..20) {
            moveTo(r.midX + i * 30, horizon)
            lineTo(r.midX + i * r.width * 0.12f, r.minY)
        }
        for (k in 0 until 14) {
            val z = (k / 14f + t * 0.35f) % 1f
            val y = horizon - (horizon - r.minY) * z * z * z
            moveTo(r.minX, y)
            lineTo(r.maxX, y)
        }
    }
    stroke(lines, pal[1], 2f, g, glow = true)
}

private fun waves(r: Box, t: Float, pal: List<Int>, g: Gfx) {
    val bands = 34
    val h = r.height / bands
    for (i in 0 until bands) {
        val y = r.minY + i * h
        val shift = sin(i * 0.45f + t * 3) * 70
        g.fill(r.minX + shift, y, r.width, h * 0.7f, pal[i % pal.size].withAlpha(0.26f))
    }
}

private fun checker(r: Box, t: Float, pal: List<Int>, f: GlitchRandom, g: Gfx) {
    val cell = r.width / 18
    val tick = (t * 4).toInt()
    var y = r.minY
    var j = 0
    while (y < r.maxY) {
        var x = r.minX
        var i = 0
        while (x < r.maxX) {
            if ((i + j + tick) % 2 == 0 && f.unit() < 0.7f) {
                g.fill(x, y, cell, cell, pal[(i + j + tick / 2) % pal.size].withAlpha(0.38f))
            }
            x += cell; i += 1
        }
        y += cell; j += 1
    }
}

private val LOADING_LABELS = listOf("COPYING KEYCHAIN", "UPLOADING FILES", "ENCRYPTING DISK", "CRACKING PASSWORDS", "WIPING BACKUPS", "DISABLING FIREWALL")

private fun loading(r: Box, t: Float, pal: List<Int>, g: Gfx) {
    val barW = min(r.width * 0.6f, 900f)
    val barH = 26f
    val x = r.midX - barW / 2
    var y = r.midY + LOADING_LABELS.size * 34
    for ((i, label) in LOADING_LABELS.withIndex()) {
        val progress = (t * (0.05f + 0.03f * i) + i * 0.17f) % 1f
        y -= 68
        PixelFont.draw("$label ${(progress * 100).toInt()}%", x, y + barH + 8, 3f, pal[i % pal.size], g)
        g.fill(x, y, barW, barH, gray(0f, 0.85f))
        g.fill(x + 3, y + 3, (barW - 6) * progress, barH - 6, pal[i % pal.size])
    }
}

private fun virus(r: Box, t: Float, pal: List<Int>, seed: Int, f: GlitchRandom, g: Gfx) {
    val cell = r.width / 48
    val phase = (t / 20) % 1f
    val rand = GlitchRandom(seed + (t / 20).toInt())
    val seeds = (0 until 5).map { P(rand.range(r.minX, r.maxX), rand.range(r.minY, r.maxY)) }
    val radius = phase * hypot(r.width, r.height) * 0.6f
    var y = r.minY
    while (y < r.maxY) {
        var x = r.minX
        while (x < r.maxX) {
            var d = Float.MAX_VALUE
            for (s in seeds) d = min(d, hypot(s.x - x, s.y - y))
            if (d < radius) {
                val front = radius - d < cell * 2
                val colour = if (front) pal[1].withAlpha(0.9f) else pal[0].withAlpha(f.range(0.25f, 0.6f))
                g.fill(x + 1, y + 1, cell - 2, cell - 2, colour)
            }
            x += cell
        }
        y += cell
    }
}

private fun dataStream(r: Box, t: Float, pal: List<Int>, seed: Int, g: Gfx) {
    val rows = 40
    val h = r.height / rows
    val rand = GlitchRandom(seed)
    for (row in 0 until rows) {
        val speed = rand.range(80f, 600f) * (if (row % 2 == 0) 1 else -1)
        val dash = rand.range(20f, 140f)
        val gap = rand.range(10f, 80f)
        val period = dash + gap
        val offset = (t * speed) % period
        var x = r.minX - period + offset
        val colour = pal[row % pal.size].withAlpha(0.7f)
        while (x < r.maxX) {
            g.fill(x, r.minY + row * h + h * 0.3f, dash, h * 0.35f, colour)
            x += period
        }
    }
}

private fun bigText(r: Box, t: Float, pal: List<Int>, options: List<String>, f: GlitchRandom, g: Gfx) {
    if (f.unit() <= 0.12f) return
    val count = (10 - t.toInt() % 11).toString()
    val texts = options.map { it.replace("#", count) }
    val maxWidth = r.width * 0.7f
    val text = texts.firstOrNull { PixelFont.width(it) * 4f <= maxWidth } ?: texts.last()
    val cx = r.midX + f.range(-4f, 4f)
    val cy = r.midY
    pixelText(text, cx, cy, maxWidth, 16f, pal[0], g, box = true)
    // A shifted ghost copy, the RGB split look.
    pixelText(text, cx + 5, cy - 3, maxWidth, 16f, pal[1].withAlpha(0.45f), g)
}

private fun tiled(r: Box, t: Float, pal: List<Int>, word: String, g: Gfx) {
    val p = max(3f, (r.width / 260).roundToInt().toFloat())
    val unit = PixelFont.width("$word  ") * p
    val rowH = (PixelFont.HEIGHT + 5) * p
    var row = 0
    var y = r.minY
    while (y < r.maxY) {
        val dir = if (row % 2 == 0) 1f else -1f
        val offset = (t * 40 * dir) % unit
        var x = r.minX - unit + offset
        while (x < r.maxX) {
            PixelFont.draw(word, x, y, p, pal[row % pal.size].withAlpha(0.6f), g)
            x += unit
        }
        y += rowH; row += 1
    }
}
