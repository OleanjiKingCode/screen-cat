package com.oleanji.screencat

import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Everything the renderer needs to know about the cat right now. */
class CatState {
    // The point under the cat's paws, in surface-local coordinates.
    var pos = P()
    // 1 = facing right, -1 = facing left. Only side-view clips use it.
    var facing = 1f
    var clip = Clip.STAND_IDLE
        private set
    var clipTime = 0f
    // Distance walked in the current clip, used to drive walk and run frames.
    var stride = 0f
    // Standing height in dp, before perspective.
    var size = 120f
    // Shrinks the cat slightly as it moves up the screen, so travelling "up"
    // reads as walking away rather than levitating.
    var depth = 1f
    var visible = false
    // What it has on for this visit. Picked when a routine starts.
    var wearing: MutableSet<Accessory> = mutableSetOf()

    fun switchClip(c: Clip) {
        if (c == clip) return
        clip = c
        clipTime = 0f
        stride = 0f
    }

    val drawnSize get() = size * depth
    val pixelScale get() = drawnSize / SpriteSheet.STAND_HEIGHT

    /** How far the cat travels per full cycle of the current walk or run. */
    val cycleDistance: Float
        get() = when (clip) {
            Clip.RUN -> drawnSize * 2.0f
            Clip.FRONT_WALK -> drawnSize * 0.9f
            else -> drawnSize * 1.15f
        }

    val frameIndex: Int
        get() {
            val info = clip.info
            if (info.strideDriven) {
                val cycles = stride / max(1f, cycleDistance)
                return (cycles * info.count).toInt() % max(1, info.count)
            }
            val i = (clipTime * info.fps).toInt()
            return if (info.loops) i % max(1, info.count) else min(i, info.count - 1)
        }

    val finishedOnce: Boolean
        get() {
            val info = clip.info
            return !info.loops && clipTime * info.fps >= info.count
        }

    fun advance(dt: Float) { clipTime += dt }
}

/** Colours used by the bits that are drawn rather than blitted. */
data class Palette(val outline: Int, val inner: Int)

fun drawCat(c: CatState, sheet: SpriteSheet, drawShadow: Boolean, palette: Palette, g: Gfx, pxPerDp: Float) {
    val bitmap = sheet.sheet ?: return
    val frame = sheet.frame(c.clip, c.frameIndex) ?: return
    val ps = c.pixelScale
    val side = SpriteSheet.FRAME_SIZE * ps
    // The frame's ground line is row 30 of 32, so the sprite sits two source
    // pixels below the paws.
    val rect = Box(c.pos.x - side / 2, c.pos.y - (SpriteSheet.FRAME_SIZE - SpriteSheet.GROUND_ROW) * ps, side, side)

    val shadow = sheet.shadow
    if (drawShadow && shadow != null) {
        val w = side * 0.72f
        val h = w * shadow.height / shadow.width
        g.image(shadow, null, Box(c.pos.x - w / 2, c.pos.y - h * 0.45f, w, h), false, 0.35f, pxPerDp)
    }

    val mirrored = c.clip.info.mirrors && c.facing < 0
    g.image(bitmap, frame, rect, mirrored, 1f, pxPerDp)
    // Chain first, so the glasses win anywhere the two overlap.
    for (item in listOf(Accessory.CHAIN, Accessory.GLASSES)) {
        if (!c.wearing.contains(item)) continue
        val overlay = sheet.accessory(item, c.clip, c.frameIndex) ?: continue
        g.image(overlay, null, rect, mirrored, 1f, pxPerDp)
    }

    if (c.clip == Clip.SLEEP) drawZzz(c, palette, g)
}

// A 5x7 pixel "z". Big enough that a one-pixel halo reads as an outline.
private val Z_GLYPH = listOf(
    "#####",
    "....#",
    "...#.",
    "..#..",
    ".#...",
    "#....",
    "#####",
)

private fun drawZzz(c: CatState, pal: Palette, g: Gfx) {
    val ps = c.pixelScale
    // The sleeping cat's head is at the front, so trail the z's off that side.
    val dir = if (c.facing < 0) -1f else 1f
    val headX = c.pos.x + dir * ps * 8
    for (i in 0 until 3) {
        val cycle = 2.7f
        val local = ((c.clipTime + i * cycle / 3) % cycle) / cycle
        val alpha = sin(local * PI.toFloat())
        if (alpha <= 0.05f) continue
        val px = ps * (0.8f + local * 0.5f)
        val x = headX + dir * local * ps * 7
        val y = c.pos.y + ps * 13 + local * ps * 14
        // White letter, dark outline: readable over light and dark wallpaper.
        drawGlyph(Z_GLYPH, P(x, y), px, gray(1f, 0.95f), pal.outline, alpha, g)
    }
}

// A little pixel food bowl, so the begging routine reads as "hungry".
private val BOWL_GLYPH = listOf(
    "..rrrrrrr..",
    ".rrrrrrrrr.",
    ".rbbbbbbbr.",
    "..bbbbbbb..",
    "...bbbbb...",
    "....bbb....",
)

fun drawFoodBowl(at: P, pixel: Float, pal: Palette, alpha: Float, g: Gfx) {
    val w = BOWL_GLYPH[0].length * pixel
    val ox = at.x - w / 2
    val oy = at.y
    val before = g.globalAlpha
    g.globalAlpha = before * alpha
    for ((rowIndex, row) in BOWL_GLYPH.reversed().withIndex()) {
        for ((colIndex, ch) in row.withIndex()) {
            if (ch == '.') continue
            g.fill(
                (ox + colIndex * pixel).roundToInt().toFloat(), (oy + rowIndex * pixel).roundToInt().toFloat(),
                pixel.roundToInt().toFloat(), pixel.roundToInt().toFloat(),
                if (ch == 'r') pal.inner else pal.outline,
            )
        }
    }
    g.globalAlpha = before
}

private fun drawGlyph(glyph: List<String>, at: P, pixel: Float, fill: Int, halo: Int, alpha: Float, g: Gfx) {
    // Snap the pixel size and the origin first, so every cell lands on the
    // same grid instead of rounding independently into mush.
    val p = max(2f, pixel.roundToInt().toFloat())
    val ox = at.x.roundToInt().toFloat()
    val oy = at.y.roundToInt().toFloat()
    val before = g.globalAlpha
    g.globalAlpha = before * alpha
    for (dx in -1..1) {
        for (dy in -1..1) {
            if (dx == 0 && dy == 0) continue
            paintGlyph(glyph, ox + dx * p, oy + dy * p, p, halo, g)
        }
    }
    paintGlyph(glyph, ox, oy, p, fill, g)
    g.globalAlpha = before
}

private fun paintGlyph(glyph: List<String>, ox: Float, oy: Float, pixel: Float, colour: Int, g: Gfx) {
    for ((rowIndex, row) in glyph.reversed().withIndex()) {
        for ((colIndex, ch) in row.withIndex()) {
            if (ch == '.') continue
            g.fill(ox + colIndex * pixel, oy + rowIndex * pixel, pixel, pixel, colour)
        }
    }
}

// Ball ----------------------------------------------------------------------

class BallState {
    var pos = P()
    // Drawn width in dp.
    var size = 26f
    var rotation = 0f
    var visible = false
}

fun drawBall(b: BallState, sheet: SpriteSheet, g: Gfx, pxPerDp: Float) {
    val img = sheet.ball ?: return
    g.save()
    g.canvas.translate(b.pos.x, b.pos.y)
    g.canvas.rotate(Math.toDegrees(b.rotation.toDouble()).toFloat())
    val h = b.size * img.height / img.width
    g.image(img, null, Box(-b.size / 2, -h / 2, b.size, h), false, 1f, 1f)
    g.restore()
}
