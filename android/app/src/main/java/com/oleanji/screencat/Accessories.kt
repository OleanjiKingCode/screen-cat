package com.oleanji.screencat

import android.graphics.Bitmap

/**
 * Things the cat can wear. Each one is baked into a 32x32 overlay per sprite
 * frame and drawn on top of that frame with the same rect and mirroring, so it
 * stays glued to the face through every walk cycle, blink and head bob.
 */
enum class Accessory { CHAIN, GLASSES }

/**
 * Where the face is in one frame, found from the eye pixels of the source sheet.
 *
 * Designs are written in (u, v): u runs along the line joining the eyes, with
 * the eyes at u = -2 and +2, and v runs toward the chin, with v = 0 the bottom
 * row of the eyes. That one frame of reference covers the upright frames and
 * the ball-play frames, where the cat lies on its side and the face is turned
 * a quarter with the chin pointing left.
 */
data class FaceAnchor(val x: Int, val y: Int, val upright: Boolean) {
    /** (u, v) to frame pixels, y counted down from the top. */
    fun point(u: Int, v: Int): Pair<Int, Int> = if (upright) Pair(x + u, y + v) else Pair(x - v, y + u)

    companion object {
        /**
         * Finds the face in the frame at (col, row). Null when the eyes are
         * fully shut. Eyes are the only pure white pixels on the sheet. They
         * close from the top down, so the bottom row of an eye stays put
         * through a blink and makes a steady anchor.
         */
        fun find(px: IntArray, sheetWidth: Int, col: Int, row: Int): FaceAnchor? {
            val s = SpriteSheet.FRAME_SIZE
            var minX = s
            var maxX = -1
            var minY = s
            var maxY = -1
            for (y in 0 until s) {
                for (x in 0 until s) {
                    val c = px[(row * s + y) * sheetWidth + col * s + x]
                    if (c != -0x1) continue
                    minX = minOf(minX, x); maxX = maxOf(maxX, x)
                    minY = minOf(minY, y); maxY = maxOf(maxY, y)
                }
            }
            if (maxX < 0) return null
            // Upright eyes sit side by side, four pixels apart. Stacked ones are
            // the ball-play frames, where the lids close toward -x.
            if (maxX - minX >= 4) return FaceAnchor((minX + maxX) / 2, maxY, true)
            return FaceAnchor(minX, (minY + maxY) / 2, false)
        }
    }
}

private val GOLD_LIGHT = rgb(0xFFD34E)
private val GOLD_DARK = rgb(0xC98A1B)
private val GOLD_SHINE = rgb(0xFFF4B0)
private val SHADES_FRAME = rgb(0x111018)
private val SHADES_LENS = rgb(0x2A2440)
private val SHADES_GLINT = rgb(0xB8E4FF)

/**
 * Paints one accessory for one frame into a 32x32 image. `alpha(x, y)` is the
 * frame's own opacity, used to keep the chain on the body.
 */
fun makeAccessoryImage(accessory: Accessory, anchor: FaceAnchor, alpha: (Int, Int) -> Int): Bitmap {
    val s = SpriteSheet.FRAME_SIZE
    val px = IntArray(s * s)

    fun put(u: Int, v: Int, c: Int, onBodyOnly: Boolean = false) {
        val (x, y) = anchor.point(u, v)
        if (x < 0 || x >= s || y < 0 || y >= s) return
        if (onBodyOnly && alpha(x, y) == 0) return
        px[y * s + x] = c
    }

    when (accessory) {
        Accessory.CHAIN -> {
            // A U of links hanging under the chin, light and dark alternating so
            // it reads as a chain and not a line, with a small pendant at the
            // bottom. Clipped to the body so it never floats in the air.
            val links = listOf(-4 to 2, -3 to 3, -2 to 4, -1 to 4, 0 to 4, 1 to 4, 2 to 4, 3 to 3, 4 to 2)
            for ((u, v) in links) put(u, v, if ((u and 1) == 0) GOLD_LIGHT else GOLD_DARK, onBodyOnly = true)
            put(-1, 5, GOLD_DARK, onBodyOnly = true)
            put(1, 5, GOLD_DARK, onBodyOnly = true)
            put(0, 5, GOLD_SHINE, onBodyOnly = true)
            put(0, 6, GOLD_LIGHT, onBodyOnly = true)
        }
        Accessory.GLASSES -> {
            // Small shades, just over the eyes: a 3x3 lens per eye with a dark
            // top rim, a one-pixel bridge between them, and a glint top left.
            for (e in listOf(-2, 2)) {
                for (u in (e - 1)..(e + 1)) {
                    put(u, -2, SHADES_FRAME)
                    put(u, -1, SHADES_LENS)
                    put(u, 0, SHADES_LENS)
                }
                put(e - 1, -1, SHADES_GLINT)
            }
            put(0, -2, SHADES_FRAME)
        }
    }
    return Bitmap.createBitmap(px, s, s, Bitmap.Config.ARGB_8888)
}

/** Rolls what the cat wears for one visit, so the glasses stay a surprise. */
fun pickOutfit(c: Config): MutableSet<Accessory> {
    val outfit = mutableSetOf<Accessory>()
    if (Math.random() < c.chainChance) outfit.add(Accessory.CHAIN)
    if (Math.random() < c.glassesChance) outfit.add(Accessory.GLASSES)
    return outfit
}
