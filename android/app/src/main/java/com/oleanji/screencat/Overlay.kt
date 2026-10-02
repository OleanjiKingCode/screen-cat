package com.oleanji.screencat

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import kotlin.math.ceil

/** The real screen, in device pixels, and the part of it the cat may walk on. */
data class ScreenInfo(
    val widthPx: Int,
    val heightPx: Int,
    val density: Float,
    // System bar insets. The cat walks above the navigation bar, the same way
    // the Mac cat keeps clear of the Dock.
    val insetLeftPx: Int,
    val insetTopPx: Int,
    val insetRightPx: Int,
    val insetBottomPx: Int,
) {
    val widthDp get() = widthPx / density
    val heightDp get() = heightPx / density

    /** The visible frame in y-up dp, like NSScreen.visibleFrame. */
    val visibleFrame: Box
        get() = Box(
            insetLeftPx / density, insetBottomPx / density,
            (widthPx - insetLeftPx - insetRightPx) / density, (heightPx - insetTopPx - insetBottomPx) / density,
        )
}

/**
 * The view that paints the cat, and under it the full-screen glitch. It lives
 * in a TYPE_APPLICATION_OVERLAY window that is not touchable, so every tap
 * goes straight through to the app underneath.
 */
class OverlayView(context: Context) : View(context) {
    var scene: Scene? = null
    var sheet: SpriteSheet? = null
    var screen: ScreenInfo? = null
    var extras = Config().extras
    var drawShadows = true
    // Set by the hungry routine while the bowl should be on the ground.
    var bowlAt: P? = null
    // Crawler effects, in local coordinates like the cat.
    var breaches: List<Breach> = emptyList()
    var zap: Zap? = null
    var aura: Aura? = null
    // The latest rendered glitch frame and how strongly to show it.
    var takeover: Bitmap? = null
    var takeoverOpacity = 0f

    private val gfx = Gfx(Canvas())
    private val takeoverPaint = Paint().apply { isFilterBitmap = false; isAntiAlias = false; isDither = false }
    private val dst = Rect()
    private val location = IntArray(2)

    override fun onDraw(canvas: Canvas) {
        val scene = scene ?: return
        val sheet = sheet ?: return
        val screen = screen ?: return
        // The window may not start at the very top of the display, so draw in
        // screen space and shift by where the view really is, like the Mac
        // view subtracting its window's origin.
        getLocationOnScreen(location)
        val ox = location[0].toFloat()
        val oy = location[1].toFloat()

        val image = takeover
        if (image != null && takeoverOpacity > 0.01f) {
            takeoverPaint.alpha = (clamp(takeoverOpacity, 0f, 1f) * 255).toInt()
            dst.set(-location[0], -location[1], screen.widthPx - location[0], screen.heightPx - location[1])
            canvas.drawBitmap(image, null, dst, takeoverPaint)
        }

        val d = screen.density
        canvas.save()
        canvas.translate(-ox, -oy)
        // y-up dp from here on, with the origin at the bottom of the screen.
        canvas.scale(d, -d)
        canvas.translate(0f, -screen.heightDp)
        canvas.translate(scene.screenRect.x, scene.screenRect.y)
        gfx.canvas = canvas
        gfx.globalAlpha = 1f

        for (breach in breaches) drawBreach(breach, gfx)
        bowlAt?.let { drawFoodBowl(it, scene.cat.pixelScale, extras, 1f, gfx) }
        if (scene.ball.visible) drawBall(scene.ball, sheet, gfx, d)
        if (scene.cat.visible) {
            drawCat(scene.cat, sheet, drawShadows, extras, gfx, d)
            zap?.let { drawZap(it, gfx) }
            aura?.let { drawAura(it, gfx) }
        }
        canvas.restore()
    }
}

/**
 * A 1x1 window that watches for touches anywhere else. With
 * FLAG_WATCH_OUTSIDE_TOUCH every tap on another app arrives here as
 * ACTION_OUTSIDE, which is the "last input" clock for the idle crawl.
 */
@SuppressLint("ViewConstructor")
class TouchWatcher(context: Context, private val onTouch: () -> Unit) : View(context) {
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_OUTSIDE || event.actionMasked == MotionEvent.ACTION_DOWN) onTouch()
        return false
    }
}

/**
 * Renders the takeover off the main thread at half resolution, so the cat's
 * own 60 fps frames never wait for it. Three bitmaps take turns, so the one
 * being painted is never the one on screen or the one just before it.
 */
class TakeoverRenderer(private val onFrame: () -> Unit) {
    private val thread = HandlerThread("takeover").apply { start() }
    private val worker = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private val pool = arrayOfNulls<Bitmap>(3)
    private var writeIndex = 0
    private var busy = false
    private var generation = 0
    private val gfx = Gfx(Canvas())

    var front: Bitmap? = null
        private set

    /** Starts one frame unless the last is still rendering. Main thread only. */
    fun request(recipe: GlitchRecipe, time: Float, seed: Int, pulse: Float, widthDp: Float, heightDp: Float) {
        if (busy) return
        busy = true
        val gen = generation
        val index = writeIndex
        worker.post {
            val bw = ceil(widthDp * 0.5f).toInt().coerceAtLeast(1)
            val bh = ceil(heightDp * 0.5f).toInt().coerceAtLeast(1)
            var bitmap = pool[index]
            if (bitmap == null || bitmap.width != bw || bitmap.height != bh) {
                bitmap = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
                pool[index] = bitmap
            }
            bitmap.eraseColor(0)
            val canvas = Canvas(bitmap)
            // Half size, y up, the way the Mac renders into its bitmap.
            canvas.scale(0.5f, -0.5f)
            canvas.translate(0f, -heightDp)
            gfx.canvas = canvas
            gfx.globalAlpha = 1f
            renderTakeover(recipe, Box(0f, 0f, widthDp, heightDp), time, seed, pulse, gfx)
            main.post {
                if (gen == generation) {
                    front = bitmap
                    writeIndex = (index + 1) % pool.size
                }
                busy = false
                onFrame()
            }
        }
    }

    fun clear() {
        generation += 1
        front = null
    }

    fun release() {
        clear()
        thread.quitSafely()
    }
}
