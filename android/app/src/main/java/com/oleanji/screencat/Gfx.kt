package com.oleanji.screencat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import kotlin.math.roundToInt

// Colours are plain ARGB ints. These helpers stand in for NSColor.

fun rgb(hex: Int): Int = (0xFF shl 24) or (hex and 0xFFFFFF)

fun gray(white: Float, alpha: Float = 1f): Int {
    val v = (clamp(white, 0f, 1f) * 255).roundToInt()
    return argb(alpha, v, v, v)
}

fun argb(alpha: Float, r: Int, g: Int, b: Int): Int =
    ((clamp(alpha, 0f, 1f) * 255).roundToInt() shl 24) or (r shl 16) or (g shl 8) or b

/** The colour with its alpha replaced, like withAlphaComponent. */
fun Int.withAlpha(a: Float): Int = ((clamp(a, 0f, 1f) * 255).roundToInt() shl 24) or (this and 0xFFFFFF)

/** `a` moved `t` of the way toward `b`, like NSColor.blended(withFraction:of:). */
fun mix(a: Int, b: Int, t: Float): Int {
    fun ch(c: Int, s: Int) = (c shr s) and 0xFF
    fun m(s: Int) = (ch(a, s) + (ch(b, s) - ch(a, s)) * t).roundToInt().coerceIn(0, 255)
    return (m(24) shl 24) or (m(16) shl 16) or (m(8) shl 8) or m(0)
}

/** "#RRGGBB" or "#RRGGBBAA" to ARGB, or null. */
fun parseHex(text: String): Int? {
    var s = text.trim()
    if (s.startsWith("#")) s = s.substring(1)
    if (s.length != 6 && s.length != 8) return null
    val v = s.toLongOrNull(16) ?: return null
    return if (s.length == 6) rgb(v.toInt())
    else (((v and 0xFF).toInt()) shl 24) or ((v shr 8).toInt() and 0xFFFFFF)
}

const val WHITE = -0x1
const val BLACK = -0x1000000

// Apple's system colours, used by the colour bars.
val SYSTEM_YELLOW = rgb(0xFFCC00)
val SYSTEM_TEAL = rgb(0x5AC8FA)
val SYSTEM_GREEN = rgb(0x34C759)
val SYSTEM_PINK = rgb(0xFF2D55)
val SYSTEM_RED = rgb(0xFF3B30)
val SYSTEM_BLUE = rgb(0x007AFF)

/**
 * A canvas that has already been flipped to y-up, plus the few drawing calls
 * the Mac code makes through AppKit. `globalAlpha` works like
 * CGContext.setAlpha: it scales every colour drawn after it is set.
 */
class Gfx(var canvas: Canvas) {
    private val fillPaint = Paint().apply { style = Paint.Style.FILL }
    private val strokePaint = Paint().apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.MITER
    }
    private val imagePaint = Paint().apply { isFilterBitmap = false; isAntiAlias = false; isDither = false }
    private val textPaint = Paint().apply { typeface = Typeface.MONOSPACE }
    private val rectF = RectF()
    private val src = Rect()

    var globalAlpha = 1f
    var antialias = true
        set(value) {
            field = value
            fillPaint.isAntiAlias = value
            strokePaint.isAntiAlias = value
            textPaint.isAntiAlias = value
        }

    init { antialias = true }

    private fun scaled(colour: Int): Int {
        if (globalAlpha >= 0.999f) return colour
        val a = ((colour ushr 24) * globalAlpha).roundToInt().coerceIn(0, 255)
        return (a shl 24) or (colour and 0xFFFFFF)
    }

    fun save() = canvas.save()
    fun restore() = canvas.restore()
    fun clip(r: Box) { canvas.clipRect(r.minX, r.minY, r.maxX, r.maxY) }

    fun fill(r: Box, colour: Int) = fill(r.x, r.y, r.w, r.h, colour)

    fun fill(x: Float, y: Float, w: Float, h: Float, colour: Int) {
        if (w <= 0f || h <= 0f) return
        fillPaint.color = scaled(colour)
        canvas.drawRect(x, y, x + w, y + h, fillPaint)
    }

    fun fillOval(r: Box, colour: Int) {
        fillPaint.color = scaled(colour)
        rectF.set(r.minX, r.minY, r.maxX, r.maxY)
        canvas.drawOval(rectF, fillPaint)
    }

    fun fillPath(path: Path, colour: Int) {
        fillPaint.color = scaled(colour)
        canvas.drawPath(path, fillPaint)
    }

    fun strokePath(path: Path, colour: Int, width: Float) {
        strokePaint.color = scaled(colour)
        strokePaint.strokeWidth = width
        canvas.drawPath(path, strokePaint)
    }

    fun strokeRect(r: Box, colour: Int, width: Float) {
        strokePaint.color = scaled(colour)
        strokePaint.strokeWidth = width
        canvas.drawRect(r.minX, r.minY, r.maxX, r.maxY, strokePaint)
    }

    fun strokeOval(r: Box, colour: Int, width: Float) {
        strokePaint.color = scaled(colour)
        strokePaint.strokeWidth = width
        rectF.set(r.minX, r.minY, r.maxX, r.maxY)
        canvas.drawOval(rectF, strokePaint)
    }

    /** A pie wedge, angles in radians counter-clockwise from +x, as on the Mac. */
    fun fillWedge(cx: Float, cy: Float, radius: Float, start: Float, end: Float, colour: Int) {
        fillPaint.color = scaled(colour)
        rectF.set(cx - radius, cy - radius, cx + radius, cy + radius)
        val startDeg = Math.toDegrees(start.toDouble()).toFloat()
        val sweep = Math.toDegrees((end - start).toDouble()).toFloat()
        canvas.drawArc(rectF, startDeg, sweep, true, fillPaint)
    }

    /** An oval filled with a vertical gradient, `bottom` colour at the bottom. */
    fun fillOvalGradient(r: Box, bottom: Int, top: Int) {
        fillPaint.shader = LinearGradient(0f, r.minY, 0f, r.maxY, scaled(bottom), scaled(top), Shader.TileMode.CLAMP)
        rectF.set(r.minX, r.minY, r.maxX, r.maxY)
        canvas.drawOval(rectF, fillPaint)
        fillPaint.shader = null
    }

    /**
     * Monospaced text with its bottom-left corner near (x, y), the way
     * NSString.draw(at:) places it in an unflipped view.
     */
    fun text(s: String, x: Float, y: Float, size: Float, colour: Int, bold: Boolean = false) {
        textPaint.textSize = size
        textPaint.color = scaled(colour)
        textPaint.typeface = if (bold) Typeface.create(Typeface.MONOSPACE, Typeface.BOLD) else Typeface.MONOSPACE
        val descent = textPaint.descent()
        canvas.save()
        canvas.translate(x, y)
        canvas.scale(1f, -1f)
        canvas.drawText(s, 0f, -descent, textPaint)
        canvas.restore()
    }

    /**
     * Pixel art, nearest neighbour, upright, into `dst`. `pxPerUnit` is the
     * device pixels per dp, used to snap the rect to whole device pixels so
     * the sprite never shimmers as it moves.
     */
    fun image(bitmap: Bitmap, srcRect: Rect?, dst: Box, mirrored: Boolean, alpha: Float, pxPerUnit: Float = 1f) {
        val x = (dst.x * pxPerUnit).roundToInt() / pxPerUnit
        val y = (dst.y * pxPerUnit).roundToInt() / pxPerUnit
        val w = (dst.w * pxPerUnit).roundToInt() / pxPerUnit
        val h = (dst.h * pxPerUnit).roundToInt() / pxPerUnit
        imagePaint.alpha = (clamp(alpha * globalAlpha, 0f, 1f) * 255).roundToInt()
        canvas.save()
        // Undo the y flip locally, so the bitmap is the right way up.
        canvas.translate(x, y + h)
        canvas.scale(1f, -1f)
        if (mirrored) {
            canvas.translate(w, 0f)
            canvas.scale(-1f, 1f)
        }
        rectF.set(0f, 0f, w, h)
        if (srcRect != null) {
            canvas.drawBitmap(bitmap, srcRect, rectF, imagePaint)
        } else {
            src.set(0, 0, bitmap.width, bitmap.height)
            canvas.drawBitmap(bitmap, src, rectF, imagePaint)
        }
        canvas.restore()
    }
}

/** A path in y-up coordinates, built the way NSBezierPath is. */
fun path(block: Path.() -> Unit): Path = Path().apply(block)
