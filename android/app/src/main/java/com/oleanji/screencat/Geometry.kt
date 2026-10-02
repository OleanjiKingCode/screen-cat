package com.oleanji.screencat

import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

// All behaviour and drawing maths uses y-up coordinates in dp, the same way
// round as the Mac code: x runs along the floor, y is height above it. The
// overlay flips the canvas once, so the ported code reads like the original.

/** A point. Mutable, like CGPoint, so the cat can be nudged in place. */
data class P(var x: Float = 0f, var y: Float = 0f)

/** A rectangle with its origin at the bottom left. */
data class Box(var x: Float = 0f, var y: Float = 0f, var w: Float = 0f, var h: Float = 0f) {
    val minX get() = x
    val maxX get() = x + w
    val minY get() = y
    val maxY get() = y + h
    val midX get() = x + w / 2
    val midY get() = y + h / 2
    val width get() = w
    val height get() = h

    fun insetBy(dx: Float, dy: Float) = Box(x + dx, y + dy, w - dx * 2, h - dy * 2)
    fun offsetBy(dx: Float, dy: Float) = Box(x + dx, y + dy, w, h)
    fun contains(p: P) = p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
}

fun rnd(a: Float, b: Float): Float = if (b <= a) a else a + Random.nextFloat() * (b - a)
fun rndInt(a: Int, bInclusive: Int): Int = Random.nextInt(a, bInclusive + 1)
fun coin(): Boolean = Random.nextBoolean()
fun clamp(v: Float, lo: Float, hi: Float) = max(lo, min(hi, v))
fun hypot(x: Float, y: Float) = kotlin.math.sqrt(x * x + y * y)

/** Swift's truncatingRemainder: keeps the sign of `a`. */
fun Float.rem2(b: Float): Float = this % b

/**
 * Small deterministic random source, the same SplitMix64 scramble and LCG as
 * the Mac's GlitchRandom, so a style flickers a few times a second but each
 * frame is stable. Seeds are UInt32 on the Mac; here they are Int with the
 * same wrapping arithmetic.
 */
class GlitchRandom(seed: Int) {
    private var state: Long

    init {
        var z = (seed.toLong() and 0xFFFFFFFFL) + -0x61c8864680b583ebL
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        state = z xor (z ushr 31)
    }

    fun unit(): Float {
        state = state * 6364136223846793005L + 1442695040888963407L
        return ((state ushr 33) and 0xFFFFFFL).toFloat() / 0xFFFFFF.toFloat()
    }

    fun range(a: Float, b: Float): Float = a + (b - a) * unit()
}

/** A random 32-bit seed, never zero, like UInt32.random(in: 1...max). */
fun randomSeed(): Int {
    var s = Random.nextInt()
    if (s == 0) s = 1
    return s
}
