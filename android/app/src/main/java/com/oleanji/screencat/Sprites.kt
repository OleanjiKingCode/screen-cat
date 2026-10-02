package com.oleanji.screencat

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect

// Sprite art: "Cat Pack" (free tier) by Glem / octopusINKUS.
// https://octopusinkus.itch.io/cat-pack , see assets/CREDIT.txt.
//
// The sheet is 384x288: a 12 x 9 grid of 32x32 frames. Frames are bottom
// aligned, with the ground line at row 30 and a standing cat about 27px tall.
// Side-view rows face right and are mirrored to walk left.

data class ClipInfo(
    val row: Int,
    val start: Int,
    val count: Int,
    val fps: Float,
    val loops: Boolean,
    // Side-view clips mirror when the cat faces left; front-view ones never do.
    val mirrors: Boolean,
    // Frame index is driven by distance travelled, not by the clock, so the
    // paws do not skate along the ground.
    val strideDriven: Boolean,
)

enum class Clip(val info: ClipInfo) {
    // Sitting, front on, tail swishing, blinks.
    SIT_IDLE(ClipInfo(0, 0, 9, 7f, true, false, false)),
    // Standing, front on.
    STAND_IDLE(ClipInfo(1, 0, 11, 7f, true, false, false)),
    // Sit, then settle down.
    SIT_DOWN(ClipInfo(2, 0, 11, 10f, false, false, false)),
    // Low crouch, front on.
    CROUCH(ClipInfo(3, 0, 6, 7f, true, false, false)),
    // Drop from standing to lying.
    LIE_DOWN(ClipInfo(4, 0, 4, 7f, false, false, false)),
    // Lying, slow breathing.
    SLEEP(ClipInfo(4, 4, 6, 3f, true, false, false)),
    // Walking toward the viewer.
    FRONT_WALK(ClipInfo(5, 0, 10, 10f, true, false, true)),
    // Walking in profile.
    SIDE_WALK(ClipInfo(6, 0, 10, 10f, true, true, true)),
    // Lying on its side batting the yarn ball.
    BALL_PLAY(ClipInfo(7, 0, 11, 12f, true, true, false)),
    // Profile pounce / run.
    RUN(ClipInfo(8, 0, 6, 14f, true, true, true)),
}

/** Loads the sheet, recolours it once, and hands out frames. */
class SpriteSheet(assets: AssetManager, palette: SpritePalette) {
    companion object {
        const val FRAME_SIZE = 32
        // Row 30 of each frame is where the paws meet the ground.
        const val GROUND_ROW = 30f
        // A standing cat measures about this many pixels.
        const val STAND_HEIGHT = 27f
    }

    val sheet: Bitmap?
    val ball: Bitmap?
    val shadow: Bitmap?

    // The unrecoloured sheet's pixels, kept to find the face in each frame.
    private val raw: IntArray
    private val rawWidth: Int
    private val accessoryFrames = HashMap<Int, Bitmap?>()
    private val frameRect = Rect()

    init {
        // The sheet gets the coat mapping only. The yarn colours are left alone
        // there because the cat's nose and mouth are drawn in them too, and
        // tinting those turns its face the colour of the ball.
        val original = decode(assets, "Cat_Sprite_Sheet.png")
        sheet = original?.let { recolour(it, palette.coat) }
        ball = decode(assets, "Cat_Ball.png")?.let { recolour(it, palette.yarn) }
        shadow = decode(assets, "Cat_Shadow.png")
        if (original != null) {
            rawWidth = original.width
            raw = IntArray(original.width * original.height)
            original.getPixels(raw, 0, original.width, 0, 0, original.width, original.height)
        } else {
            rawWidth = 0
            raw = IntArray(0)
        }
    }

    val isLoaded get() = sheet != null

    /** The source rect of frame `index` of `clip` on the sheet. */
    fun frame(clip: Clip, index: Int): Rect? {
        if (sheet == null) return null
        val info = clip.info
        val i = if (info.count > 0) ((index % info.count) + info.count) % info.count else 0
        val col = info.start + i
        val s = FRAME_SIZE
        frameRect.set(col * s, info.row * s, col * s + s, info.row * s + s)
        return frameRect
    }

    /**
     * `accessory` for frame `index` of `clip`, built on first use and cached.
     * A frame with the eyes shut borrows the face from the nearest earlier
     * frame of the same clip that has them open.
     */
    fun accessory(accessory: Accessory, clip: Clip, index: Int): Bitmap? {
        if (raw.isEmpty()) return null
        val info = clip.info
        val i = if (info.count > 0) ((index % info.count) + info.count) % info.count else 0
        val key = accessory.ordinal * 10_000 + info.row * 100 + info.start + i
        if (accessoryFrames.containsKey(key)) return accessoryFrames[key]

        val col = info.start + i
        val s = FRAME_SIZE
        var anchor: FaceAnchor? = null
        var back = 0
        while (back < info.count && anchor == null) {
            val c = info.start + ((i - back) % info.count + info.count) % info.count
            anchor = FaceAnchor.find(raw, rawWidth, c, info.row)
            back++
        }
        val image = anchor?.let { a ->
            makeAccessoryImage(accessory, a) { x, y -> (raw[(info.row * s + y) * rawWidth + col * s + x] ushr 24) and 0xFF }
        }
        accessoryFrames[key] = image
        return image
    }

    private fun decode(assets: AssetManager, name: String): Bitmap? = try {
        assets.open(name).use { stream ->
            BitmapFactory.decodeStream(stream, null, BitmapFactory.Options().apply {
                inScaled = false
                inPreferredConfig = Bitmap.Config.ARGB_8888
            })
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Exact-colour swap. getPixels hands back unpremultiplied colours, so the
     * source colours compare exactly against the palette table.
     */
    private fun recolour(src: Bitmap, table: Map<Int, Int>): Bitmap {
        val w = src.width
        val h = src.height
        val px = IntArray(w * h)
        src.getPixels(px, 0, w, 0, 0, w, h)
        for (i in px.indices) {
            val c = px[i]
            val a = c ushr 24
            if (a == 0) continue
            val to = table[c and 0xFFFFFF] ?: continue
            px[i] = (a shl 24) or (to and 0xFFFFFF)
        }
        return Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888)
    }
}

/** Maps the pack's ten source colours onto the user's configured colours. */
class SpritePalette(fur: Int, furShade: Int, outline: Int, inner: Int, eye: Int, ball: Int) {
    companion object {
        // The exact palette of the original sheet.
        const val SRC_OUTLINE = 0x222034
        const val SRC_BODY = 0x322B28
        const val SRC_DARK = 0x221C1A
        const val SRC_SHADE1 = 0x45283C
        const val SRC_SHADE2 = 0x422433
        const val SRC_ACCENT = 0x793A80
        const val SRC_EAR = 0xE86A73
        const val SRC_EYE = 0xFFFFFF
        const val SRC_YARN_A = 0xBC4A9B
        const val SRC_YARN_B = 0xD25A87
    }

    // Coat, ears and eyes. Applied to the sheet.
    val coat: Map<Int, Int> = mapOf(
        SRC_OUTLINE to outline,
        SRC_BODY to fur,
        SRC_DARK to mix(furShade, outline, 0.55f),
        SRC_SHADE1 to furShade,
        SRC_SHADE2 to mix(furShade, outline, 0.25f),
        SRC_ACCENT to mix(fur, furShade, 0.45f),
        SRC_EAR to inner,
        SRC_EYE to eye,
    )

    // Yarn only. Applied to the loose ball sprite, never to the sheet.
    val yarn: Map<Int, Int> = mapOf(
        SRC_OUTLINE to outline,
        SRC_YARN_A to ball,
        SRC_YARN_B to mix(ball, WHITE, 0.32f),
        SRC_ACCENT to mix(ball, BLACK, 0.28f),
    )
}
