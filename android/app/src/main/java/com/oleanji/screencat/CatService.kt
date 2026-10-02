package com.oleanji.screencat

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.Choreographer
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import kotlin.math.ceil
import kotlin.math.max
import kotlin.random.Random

/**
 * The cat's home: a foreground service that owns the overlay window, picks a
 * routine every few seconds, runs the 60 fps frame loop while the cat is out,
 * and watches for the phone being left alone.
 */
class CatService : Service() {
    companion object {
        private const val TAG = "ScreenCat"
        private const val CHANNEL = "screencat"
        private const val NOTIFICATION_ID = 1

        const val ACTION_RUN = "com.oleanji.screencat.RUN"
        const val ACTION_PAUSE = "com.oleanji.screencat.PAUSE"
        const val ACTION_STOP = "com.oleanji.screencat.STOP"
        const val ACTION_RELOAD = "com.oleanji.screencat.RELOAD"
        const val EXTRA_ROUTINE = "routine"

        @Volatile var running = false
            private set

        fun intent(context: Context, action: String, routine: Routine? = null): Intent =
            Intent(context, CatService::class.java).setAction(action).apply {
                if (routine != null) putExtra(EXTRA_ROUTINE, routine.key)
            }

        fun start(context: Context, action: String? = null, routine: Routine? = null) {
            val i = if (action != null) intent(context, action, routine) else Intent(context, CatService::class.java)
            context.startForegroundService(i)
        }
    }

    private lateinit var wm: WindowManager
    private val handler = Handler(Looper.getMainLooper())
    private val scene = Scene()
    private lateinit var view: OverlayView
    private var overlayAttached = false
    private var watcher: TouchWatcher? = null
    private lateinit var renderer: TakeoverRenderer

    private var behavior: Behavior? = null
    private var loadedPaletteKey = ""
    private var paused = false
    // Screen off or locked. Nobody can see the cat then, so it stays in and the
    // frame loop does not run for nothing.
    private var away = false
    private var nextVisitAt = 0L
    private var screen: ScreenInfo? = null

    // The idle crawl: starts after idleCrawlSeconds without a touch, ends on
    // the first touch.
    private var lastTouch = SystemClock.elapsedRealtime()
    private var idleCrawlStarted = 0L
    // Ignore touches this soon after a manual start, or the tap that chose it
    // would end it at once.
    private var idleCrawlGraceMs = 0L
    private var exitHandled = false
    private var lastTakeoverRequest = 0L

    private var frameScheduled = false
    private var lastFrameNanos = 0L
    private val frameCallback = Choreographer.FrameCallback { now -> onFrame(now) }

    private val scheduleRunnable = Runnable {
        nextVisitAt = 0L
        startRandom()
    }

    private val idleRunnable = object : Runnable {
        override fun run() {
            checkIdleCrawl()
            handler.postDelayed(this, 1000)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> goAway()
                Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> {
                    lastTouch = SystemClock.elapsedRealtime()
                    comeBack()
                }
            }
        }
    }

    private val configCallbacks = object : ComponentCallbacks {
        override fun onConfigurationChanged(newConfig: Configuration) = screensChanged()
        @Deprecated("Deprecated in Java")
        override fun onLowMemory() {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        Config.writeDefaultFileIfMissing(this)
        scene.config = Config.load(this)
        createChannel()
        goForeground()

        view = OverlayView(this)
        view.scene = scene
        renderer = TakeoverRenderer { view.invalidate() }
        loadSprites()

        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "no overlay permission, stopping")
            stopSelf()
            return
        }
        addTouchWatcher()
        registerReceiver(screenReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        })
        registerComponentCallbacks(configCallbacks)
        handler.postDelayed(idleRunnable, 1000)
        schedule(scene.config.firstAppearanceDelay)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Settings.canDrawOverlays(this)) return START_NOT_STICKY
        when (intent?.action) {
            ACTION_RUN -> when (val routine = Routine.from(intent.getStringExtra(EXTRA_ROUTINE))) {
                // Zero Day gets a 3.2 s grace over its 3 s countdown, the
                // crawl a second, so the tap that started it does not stop it.
                Routine.ZERO_DAY -> beginIdleCrawl(3200, Routine.ZERO_DAY)
                Routine.IDLE_CRAWL -> beginIdleCrawl(1000, Routine.IDLE_CRAWL)
                null -> {}
                else -> start(routine, force = true)
            }
            ACTION_PAUSE -> togglePause()
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_RELOAD -> reloadConfig()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        stopBehavior()
        handler.removeCallbacksAndMessages(null)
        if (::renderer.isInitialized) renderer.release()
        watcher?.let { runCatching { wm.removeView(it) } }
        watcher = null
        runCatching { unregisterReceiver(screenReceiver) }
        runCatching { unregisterComponentCallbacks(configCallbacks) }
        super.onDestroy()
    }

    // Notification ----------------------------------------------------------

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Screen Cat", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Keeps the cat running and holds its buttons"
            setShowBadge(false)
        })
    }

    private fun goForeground() {
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun statusLine(): String = when {
        paused -> "Paused"
        away -> "Away while the screen is off"
        behavior is IdleCrawlBehavior -> "Hacking until you touch something"
        behavior != null -> "Out and about"
        nextVisitAt > 0 -> {
            val s = max(1L, (nextVisitAt - SystemClock.elapsedRealtime() + 500) / 1000)
            "Next visit in ${s}s"
        }
        else -> "Waiting for the next visit"
    }

    private fun buildNotification(): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), flags)
        // Zero Day goes through a see-through activity: starting an activity
        // closes the notification shade, so you do not have to swipe it shut
        // (a touch that would end the show).
        val zeroDay = PendingIntent.getActivity(this, 1, ActionActivity.intent(this, Routine.ZERO_DAY), flags)
        val pause = PendingIntent.getService(this, 2, intent(this, ACTION_PAUSE), flags)
        val stop = PendingIntent.getService(this, 3, intent(this, ACTION_STOP), flags)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Screen Cat")
            .setContentText(statusLine())
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .addAction(Notification.Action.Builder(null, "Zero Day", zeroDay).build())
            .addAction(Notification.Action.Builder(null, if (paused) "Resume" else "Pause", pause).build())
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    private fun refreshNotification() {
        if (!running) return
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
    }

    // Config ------------------------------------------------------------------

    private fun applyConfig() {
        val c = scene.config
        view.extras = c.extras
        view.drawShadows = c.shadow
    }

    /** The sheet is recoloured at load time, so it is only rebuilt when the colours change. */
    private fun loadSprites() {
        val c = scene.config
        if (c.paletteKey == loadedPaletteKey) return
        val sheet = SpriteSheet(assets, c.spritePalette)
        if (!sheet.isLoaded) {
            Log.w(TAG, "could not load sprites")
            return
        }
        view.sheet = sheet
        loadedPaletteKey = c.paletteKey
    }

    private fun reloadConfig() {
        scene.config = Config.load(this)
        applyConfig()
        loadSprites()
        view.invalidate()
    }

    // Screen --------------------------------------------------------------------

    @Suppress("DEPRECATION")
    private fun readScreen(): ScreenInfo {
        val density = resources.displayMetrics.density
        if (Build.VERSION.SDK_INT >= 30) {
            val metrics = wm.currentWindowMetrics
            val b = metrics.bounds
            val i = metrics.windowInsets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            return ScreenInfo(b.width(), b.height(), density, i.left, i.top, i.right, i.bottom)
        }
        val dm = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(dm)
        fun dimen(name: String): Int {
            val id = resources.getIdentifier(name, "dimen", "android")
            return if (id > 0) resources.getDimensionPixelSize(id) else 0
        }
        val portrait = dm.heightPixels >= dm.widthPixels
        val nav = dimen(if (portrait) "navigation_bar_height" else "navigation_bar_height_landscape")
        return ScreenInfo(dm.widthPixels, dm.heightPixels, density, 0, dimen("status_bar_height"), 0, nav)
    }

    private fun screensChanged() {
        // The stage was laid out for the old shape. Send the cat home and let
        // the next visit lay it out again.
        if (behavior != null) {
            stopBehavior()
            if (!paused && !away) schedule(3f)
        }
    }

    private fun overlayParams(s: ScreenInfo): WindowManager.LayoutParams {
        val p = WindowManager.LayoutParams(
            s.widthPx, s.heightPx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.title = "Screen Cat"
        if (Build.VERSION.SDK_INT >= 28) {
            p.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        // Android 12 and later block taps that pass through another app's
        // overlay unless it is at most this opaque (0.8 by default).
        var alpha = scene.config.opacity
        if (Build.VERSION.SDK_INT >= 31) {
            val im = getSystemService(InputManager::class.java)
            alpha = minOf(alpha, im.maximumObscuringOpacityForTouch)
        }
        p.alpha = alpha
        return p
    }

    private fun attachOverlay(s: ScreenInfo) {
        val params = overlayParams(s)
        if (overlayAttached) {
            runCatching { wm.updateViewLayout(view, params) }
            return
        }
        runCatching {
            wm.addView(view, params)
            overlayAttached = true
        }.onFailure { Log.w(TAG, "could not add overlay", it) }
    }

    private fun detachOverlay() {
        if (!overlayAttached) return
        runCatching { wm.removeView(view) }
        overlayAttached = false
    }

    private fun addTouchWatcher() {
        val w = TouchWatcher(this) { lastTouch = SystemClock.elapsedRealtime() }
        val p = WindowManager.LayoutParams(
            1, 1,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.title = "Screen Cat touch watcher"
        runCatching {
            wm.addView(w, p)
            watcher = w
        }.onFailure { Log.w(TAG, "could not add touch watcher", it) }
    }

    // Away and back ---------------------------------------------------------------

    private fun goAway() {
        if (away) return
        away = true
        stopBehavior()
        handler.removeCallbacks(scheduleRunnable)
        nextVisitAt = 0L
        refreshNotification()
    }

    private fun comeBack() {
        if (!away) return
        away = false
        if (!paused) schedule(scene.config.firstAppearanceDelay)
        refreshNotification()
    }

    private fun togglePause() {
        paused = !paused
        if (paused) {
            stopBehavior()
            handler.removeCallbacks(scheduleRunnable)
            nextVisitAt = 0L
        } else if (!away) {
            schedule(3f)
        }
        refreshNotification()
    }

    // Idle crawl --------------------------------------------------------------------

    private fun screenInUse(): Boolean {
        val pm = getSystemService(PowerManager::class.java)
        val km = getSystemService(KeyguardManager::class.java)
        return pm.isInteractive && !km.isKeyguardLocked
    }

    private fun checkIdleCrawl() {
        val c = scene.config
        if (!c.idleCrawl || paused || away || behavior is IdleCrawlBehavior) return
        if (!screenInUse()) return
        val idleMs = SystemClock.elapsedRealtime() - lastTouch
        if (idleMs < (c.idleCrawlSeconds * 1000).toLong()) return
        beginIdleCrawl(0, Routine.IDLE_CRAWL)
    }

    private fun beginIdleCrawl(graceMs: Long, routine: Routine) {
        exitHandled = false
        idleCrawlStarted = SystemClock.elapsedRealtime()
        idleCrawlGraceMs = graceMs
        start(routine, force = graceMs > 0)
    }

    /** True once there has been a touch since the crawl began, after the grace. */
    private fun touchedSinceIdleCrawl(): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (now - idleCrawlStarted <= idleCrawlGraceMs) return false
        return lastTouch > idleCrawlStarted + 50
    }

    // Scheduling ----------------------------------------------------------------------

    private fun schedule(seconds: Float) {
        handler.removeCallbacks(scheduleRunnable)
        val delay = (max(1f, seconds) * 1000).toLong()
        nextVisitAt = SystemClock.elapsedRealtime() + delay
        handler.postDelayed(scheduleRunnable, delay)
        refreshNotification()
    }

    private fun scheduleNext() {
        val c = scene.config
        schedule(rnd(c.minGapSeconds, c.maxGapSeconds))
    }

    private fun startRandom() {
        if (away || paused) return
        scene.config = Config.load(this)
        // Locked phone: nobody sees the cat. Check again in a minute.
        if (!screenInUse()) { schedule(60f); return }
        if (scene.config.mode == "crawler" && Random.nextDouble() < scene.config.crawlChance) {
            start(Routine.CRAWL)
            return
        }
        val c = scene.config
        val table = listOf(
            Routine.STROLL to max(0.0, c.weightStroll),
            Routine.NAP to max(0.0, c.weightNap),
            Routine.BALL to max(0.0, c.weightBall),
            Routine.HUNGRY to max(0.0, c.weightHungry),
        )
        val total = table.sumOf { it.second }
        if (total <= 0) { scheduleNext(); return }
        var roll = Random.nextDouble() * total
        for ((routine, weight) in table) {
            roll -= weight
            if (roll < 0) { start(routine); return }
        }
        start(Routine.STROLL)
    }

    private fun start(routine: Routine, force: Boolean = false) {
        // One cat at a time: whatever is out now leaves before the next arrives.
        stopBehavior()
        handler.removeCallbacks(scheduleRunnable)
        nextVisitAt = 0L
        if (!force && !screenInUse()) { schedule(60f); return }

        scene.config = Config.load(this)
        applyConfig()
        loadSprites()

        val s = readScreen()
        screen = s
        view.screen = s
        val frame = s.visibleFrame
        scene.cat.size = max(24f, frame.height / scene.config.sizeDivisor)
        // Android keeps to the bottom edge, so there is one surface.
        scene.setStage(frame, scene.cat.size)
        scene.crawlTargets = if (routine == Routine.CRAWL || routine == Routine.IDLE_CRAWL || routine == Routine.ZERO_DAY) {
            pretendWindows(scene)
        } else {
            emptyList()
        }
        scene.cat.clipTime = 0f
        scene.cat.stride = 0f
        scene.cat.depth = 1f
        scene.ball.visible = false
        view.bowlAt = null

        val b = makeBehavior(routine, scene)
        behavior = b
        scene.cat.wearing = pickOutfit(scene.config)
        // A hacker wears shades.
        if (routine == Routine.CRAWL || routine == Routine.IDLE_CRAWL || routine == Routine.ZERO_DAY) {
            scene.cat.wearing.add(Accessory.GLASSES)
        }
        if (b is IdleCrawlBehavior) b.requestTargets = { pretendWindows(scene) }
        if (b !is IdleCrawlBehavior) scene.cat.visible = true
        Log.i(TAG, "${routine.key} at ${scene.cat.pos} size ${scene.cat.size}")

        attachOverlay(s)
        lastFrameNanos = 0L
        lastTakeoverRequest = 0L
        scheduleFrame()
        refreshNotification()
    }

    private fun stopBehavior() {
        handler.removeCallbacks(scheduleRunnable)
        if (frameScheduled) {
            Choreographer.getInstance().removeFrameCallback(frameCallback)
            frameScheduled = false
        }
        behavior = null
        scene.cat.visible = false
        scene.ball.visible = false
        if (::view.isInitialized) {
            view.bowlAt = null
            view.breaches = emptyList()
            view.zap = null
            view.aura = null
            view.takeover = null
            view.takeoverOpacity = 0f
        }
        if (::renderer.isInitialized) renderer.clear()
        detachOverlay()
    }

    // Frame loop ----------------------------------------------------------------------

    private fun scheduleFrame() {
        if (frameScheduled) return
        frameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun onFrame(now: Long) {
        frameScheduled = false
        val b = behavior ?: return
        val dt = if (lastFrameNanos == 0L) 1f / 60f else ((now - lastFrameNanos) / 1e9f).coerceIn(0.001f, 0.05f)
        lastFrameNanos = now

        // A touch: the glitch goes at once and the cat shrinks away. Zero
        // Day ending on time takes the same exit.
        if (b is IdleCrawlBehavior) {
            if (!b.isExiting && touchedSinceIdleCrawl()) b.beginExit()
            if (b.isExiting && !exitHandled) {
                exitHandled = true
                renderer.clear()
            }
        }

        scene.cat.advance(dt)
        val finished = b.update(dt, scene)
        view.bowlAt = (b as? HungryBehavior)?.bowlAt
        val crawl = b as? BreachSource
        view.breaches = crawl?.breaches?.toList() ?: emptyList()
        view.zap = crawl?.zap
        view.aura = crawl?.aura
        if (b is IdleCrawlBehavior) showTakeover(b)

        view.invalidate()

        if (finished) {
            stopBehavior()
            if (!paused) scheduleNext()
            refreshNotification()
            return
        }
        scheduleFrame()
    }

    /**
     * Puts the glitch over the whole screen and renders it about 20 times a
     * second, 30 for Zero Day, which moves fast.
     */
    private fun showTakeover(idle: IdleCrawlBehavior) {
        val s = screen ?: return
        val countdown = idle.countdownLeft > 0
        val opacity = if (countdown) 1f else idle.takeoverOpacity
        if (opacity <= 0.01f) {
            renderer.clear()
            view.takeover = null
            view.takeoverOpacity = 0f
            return
        }
        view.takeover = renderer.front
        view.takeoverOpacity = opacity
        val nowMs = SystemClock.uptimeMillis()
        if (nowMs - lastTakeoverRequest < (if (idle.catless) 33 else 50)) return
        lastTakeoverRequest = nowMs
        if (countdown) {
            renderer.request(countdownRecipe(ceil(idle.countdownLeft).toInt()), idle.countdownLeft, 7, 0f, s.widthDp, s.heightDp)
        } else {
            renderer.request(GLITCH_RECIPES[idle.recipeIndex], idle.styleTime, idle.styleSeed, idle.pulse, s.widthDp, s.heightDp)
        }
    }
}
