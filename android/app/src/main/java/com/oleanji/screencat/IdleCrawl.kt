package com.oleanji.screencat

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * The crawl that runs while you are away, in any mode. It starts after a
 * stretch with no touch and only ends when the service stops it, which it does
 * on the first touch.
 *
 * The order is: the cat walks in on a normal screen, stops and grows to
 * `growScale` while you watch, then the whole screen turns into a glitch. One
 * style plays for `glitchStyleSeconds`, then the next takes over. The cat
 * roams the screen on top of it, up, down and sideways, zapping areas. Android
 * cannot bring the next app forward for us, so at the edge the cat turns round
 * and a new style takes over instead.
 *
 * The cat roams the whole screen here, not just its floor. That is only
 * allowed because two things stand in for the floor: it shrinks as it goes up,
 * so up reads as further away, and it never moves steeper than `maxSlope`,
 * zig-zagging up anything steeper instead of rising straight.
 */
class IdleCrawlBehavior(
    scene: Scene,
    // 1 for the idle crawl. Mr. Robot runs at 4: glitches animate and change
    // four times as fast.
    val speed: Float = 1f,
    // Ends by itself after this many seconds (Mr. Robot's three minutes).
    private val maxDuration: Float? = null,
    countdown: Float = 0f,
    // Mr. Robot: no cat at all. The screen glitches with bursts of flashes,
    // and every few seconds it "hops": the glitch dims for a moment, then a
    // new style takes over. The Mac brings a random app forward on each hop;
    // Android cannot switch apps for us, so here the hop is the dim alone.
    val catless: Boolean = false,
) : Behavior, BreachSource {
    private enum class Stage {
        COUNTDOWN, ENTERING, GROWING, MOVING, ZAPPING, RESTING, EXITING,
        // Mr. Robot only: glitch on, then hop.
        HACKING, HOPPING,
    }
    private var stage = Stage.ENTERING
    val stageName get() = stage.name.lowercase()

    private class Stop(val point: P, val window: Box?)
    private var stops: List<Stop> = emptyList()
    private var current = 0
    private var goal = P()
    // True while heading for the edge rather than a stop.
    private var leaving = false
    private var direction = 1f
    private var legDirection = 1f
    private var timer = 0f
    private var growTime = 0f
    private val baseSize: Float
    private val growDuration get() = if (speed > 1) 1f else 3f

    private var elapsed = 0f
    // Seconds left on the "starting in" countdown, so the tap that started it
    // is over before any touch can end it.
    var countdownLeft = 0f
        private set
    private var burstTimer = 0f
    private var exitTime = 0f
    private var exitStartSize = 0f
    val isExiting get() = stage == Stage.EXITING

    override val breaches: List<Breach> = emptyList()
    override var zap: Zap? = null
        private set
    override var aura: Aura? = null
        private set

    // The full-screen glitch.
    private var takeoverOn = false
    var takeoverOpacity = 0f
        private set
    var recipeIndex = Random.nextInt(GLITCH_RECIPES.size)
        private set
    var styleTime = 0f
        private set
    var styleSeed = randomSeed()
        private set
    var pulse = 0f
        private set

    /** Fresh areas to zap for the screen as it is now. */
    var requestTargets: (() -> List<Box>)? = null

    // Kept so beginExit can be called from outside an update.
    private var sceneCatSize = 0f

    init {
        val cat = scene.cat
        baseSize = cat.size
        sceneCatSize = cat.size
        val start = entryPoint(scene, cat.size)
        cat.pos = start.copy()
        cat.visible = true
        direction = if (start.x < scene.stage.midX) 1f else -1f
        walkIn(scene)
        if (countdown > 0) {
            countdownLeft = countdown
            cat.visible = false
            stage = Stage.COUNTDOWN
        }
    }

    /**
     * Any touch, or the end of Mr. Robot: the glitch goes at once, and the cat
     * shrinks away to nothing where it stands.
     */
    fun beginExit() {
        if (stage == Stage.EXITING) return
        stage = Stage.EXITING
        takeoverOn = false
        takeoverOpacity = 0f
        countdownLeft = 0f
        zap = null
        aura = null
        exitTime = 0f
        exitStartSize = sceneCatSize
    }

    /** From off the side to a spot a quarter of the way in, on a normal screen. */
    private fun walkIn(scene: Scene) {
        val s = scene.stage
        goal = P(if (direction > 0) s.minX + s.width * 0.25f else s.maxX - s.width * 0.25f,
                 min(scene.cat.pos.y, s.maxY - scene.cat.size * 1.3f))
        leaving = false
    }

    /** The next style, never the one just shown. */
    private fun nextStyle() {
        var next = Random.nextInt(GLITCH_RECIPES.size)
        if (next == recipeIndex) next = (next + 1) % GLITCH_RECIPES.size
        recipeIndex = next
        styleTime = 0f
        styleSeed = randomSeed()
        pulse = 1f
    }

    /**
     * Where to go on this screen: each area, plus a couple of open spots so it
     * wanders the whole screen, in walking order.
     */
    private fun planStops(windowsIn: List<Box>, scene: Scene) {
        val s = scene.stage
        val top = s.maxY - scene.cat.size * 1.3f
        // Mr. Robot turns fast: one area, no wandering.
        val windows = if (speed > 1) windowsIn.take(1) else windowsIn
        val list = windows.map { w ->
            val inset = min(scene.cat.size, w.width / 3)
            Stop(P(rnd(w.minX + inset, w.maxX - inset), min(max(w.minY, s.minY), top)), w)
        }.toMutableList()
        val extra = if (speed > 1) (if (windows.isEmpty()) 1 else 0) else rndInt(2, 3)
        repeat(extra) {
            list.add(Stop(P(rnd(s.minX + s.width * 0.1f, s.maxX - s.width * 0.1f), rnd(s.minY, max(s.minY, top))), null))
        }
        stops = if (direction > 0) list.sortedBy { it.point.x } else list.sortedByDescending { it.point.x }
        current = 0
        nextGoal(scene)
    }

    private fun nextGoal(scene: Scene) {
        val s = scene.stage
        stage = Stage.MOVING
        if (current < stops.size) {
            goal = stops[current].point
            leaving = false
        } else {
            val top = s.maxY - scene.cat.size * 1.3f
            goal = P(if (direction > 0) s.maxX - scene.cat.size * 0.6f else s.minX + scene.cat.size * 0.6f,
                     min(max(scene.cat.pos.y + rnd(-0.2f, 0.2f) * s.height, s.minY), top))
            leaving = true
        }
    }

    override fun update(dt: Float, scene: Scene): Boolean {
        zap?.let { it.age += dt }
        pulse = max(0f, pulse - dt * 1.5f)
        // Fades in over 1.2s (0.3s for Mr. Robot), out over 0.4s. While Mr.
        // Robot hops it only dims to a quarter, then the new style comes in.
        val level = if (takeoverOn) (if (stage == Stage.HOPPING) 0.25f else 1f) else 0f
        val rise = if (catless) 0.3f else 1.2f
        takeoverOpacity = if (takeoverOpacity < level) min(level, takeoverOpacity + dt / rise)
                          else max(level, takeoverOpacity - dt / 0.4f)
        if (takeoverOpacity > 0) {
            styleTime += dt * speed
            if (styleTime >= scene.config.glitchStyleSeconds) nextStyle()
        }
        val cat = scene.cat
        sceneCatSize = cat.size
        elapsed += dt
        val limit = maxDuration
        if (limit != null && elapsed >= limit && stage != Stage.EXITING) beginExit()
        if (catless) cat.visible = false

        when (stage) {
            Stage.COUNTDOWN -> {
                countdownLeft -= dt
                if (countdownLeft <= 0) {
                    countdownLeft = 0f
                    if (catless) {
                        takeoverOn = true
                        nextStyle()
                        timer = rnd(4f, 7f)
                        stage = Stage.HACKING
                    } else {
                        cat.visible = true
                        stage = Stage.ENTERING
                    }
                }
            }
            Stage.HACKING -> {
                timer -= dt
                burstTimer -= dt
                if (burstTimer <= 0) {
                    pulse = rnd(0.5f, 1f)
                    burstTimer = rnd(0.5f, 1.5f)
                }
                if (timer <= 0) {
                    timer = 1.3f
                    stage = Stage.HOPPING
                }
            }
            Stage.HOPPING -> {
                timer -= dt
                if (timer <= 0) {
                    nextStyle()
                    timer = rnd(4f, 7f)
                    stage = Stage.HACKING
                }
            }
            Stage.EXITING -> {
                // No cat to shrink in Mr. Robot: it is over at once.
                if (!cat.visible || catless) return true
                exitTime += dt
                val t = min(1f, exitTime / 0.8f)
                // Shrinks slowly, then fast, and is gone.
                cat.size = max(1f, exitStartSize * (1 - t * t))
                if (t >= 1) {
                    cat.visible = false
                    return true
                }
            }
            Stage.ENTERING -> {
                if (roam(goal, scene, dt)) {
                    stage = Stage.GROWING
                    growTime = 0f
                    cat.switchClip(Clip.STAND_IDLE)
                }
            }
            Stage.GROWING -> {
                growTime += dt
                val t = min(1f, growTime / growDuration)
                // Grows in pulses that settle, so the change is easy to watch.
                val wobble = 1 + 0.08f * sin(t * PI.toFloat() * 6) * (1 - t)
                val eased = t * t * (3 - 2 * t)
                cat.size = baseSize * (1 + (scene.config.growScale - 1) * eased) * wobble
                cat.pos.y = min(cat.pos.y, scene.stage.maxY - cat.size * 1.3f)
                aura = Aura(P(cat.pos.x, cat.pos.y + cat.drawnSize * 0.45f), cat.drawnSize, t, growTime,
                            (growTime * 2).toInt() % GLITCH_ACCENTS.size)
                if (t >= 1) {
                    cat.size = baseSize * scene.config.growScale
                    aura = null
                    takeoverOn = true
                    planStops(requestTargets?.invoke() ?: emptyList(), scene)
                }
            }
            Stage.MOVING -> {
                if (roam(goal, scene, dt)) {
                    val window = if (current < stops.size) stops[current].window else null
                    if (leaving) {
                        // Nowhere to go on Android: turn round, with a new style.
                        direction = -direction
                        nextStyle()
                        planStops(requestTargets?.invoke() ?: emptyList(), scene)
                    } else if (window != null) {
                        val head = P(cat.pos.x, cat.pos.y + cat.drawnSize * 0.75f)
                        val to = P(min(max(head.x + rnd(-60f, 60f), window.minX + 10), window.maxX - 10),
                                   min(max(head.y + cat.drawnSize, window.minY + 10), window.maxY - 10))
                        zap = Zap(head, to, accentIndex = rndInt(0, GLITCH_ACCENTS.size - 1))
                        cat.switchClip(Clip.CROUCH)
                        timer = 0.7f
                        stage = Stage.ZAPPING
                    } else {
                        cat.switchClip(if (coin()) Clip.SIT_IDLE else Clip.STAND_IDLE)
                        timer = rnd(0.6f, 1.4f)
                        stage = Stage.RESTING
                    }
                }
            }
            Stage.ZAPPING -> {
                timer -= dt
                if (timer <= 0) {
                    zap = null
                    pulse = 1f
                    cat.switchClip(Clip.SIT_IDLE)
                    timer = 0.8f
                    stage = Stage.RESTING
                }
            }
            Stage.RESTING -> {
                timer -= dt
                if (timer <= 0) {
                    current += 1
                    nextGoal(scene)
                }
            }
        }
        // Never finishes by itself; a touch ends it.
        return false
    }

    /**
     * One frame of walking toward `target` anywhere on the screen. True on
     * arrival. Shallow routes are taken straight; steeper ones zig-zag at the
     * steepest allowed slope, turning at the ends of each leg.
     */
    private fun roam(target: P, scene: Scene, dt: Float): Boolean {
        val cat = scene.cat
        val dx = target.x - cat.pos.x
        val dy = target.y - cat.pos.y
        val distance = hypot(dx, dy)
        if (distance <= max(2f, cat.drawnSize * 0.15f)) return true

        val slope = max(0.05f, scene.config.maxSlope)
        val hurrying = distance > cat.drawnSize * 6
        val boost = if (speed > 1) 2f else 1f
        val pace = boost * cat.drawnSize * (if (hurrying) scene.config.runSpeed * 0.7f else scene.config.walkSpeed * 1.3f)
        var step = pace * dt
        val vx: Float
        val vy: Float
        val margin = cat.drawnSize * 0.6f
        if (abs(dy) <= slope * abs(dx)) {
            vx = dx / distance
            vy = dy / distance
            legDirection = if (dx >= 0) 1f else -1f
            step = min(step, distance)
        } else {
            val reach = cat.drawnSize * 2.5f
            val offStage = if (legDirection > 0) cat.pos.x + step > scene.stage.maxX - margin
                           else cat.pos.x - step < scene.stage.minX + margin
            val pastTarget = (cat.pos.x - target.x) * legDirection > reach
            if (offStage || pastTarget) legDirection = -legDirection
            val length = sqrt(1 + slope * slope)
            vx = legDirection / length
            vy = (if (dy > 0) slope else -slope) / length
        }
        cat.pos.x += vx * step
        cat.pos.y = min(max(cat.pos.y + vy * step, scene.stage.minY), scene.stage.maxY - cat.drawnSize * 1.3f)
        if (abs(vx) > 0.05f) cat.facing = if (vx > 0) 1f else -1f
        cat.switchClip(if (hurrying) Clip.RUN else Clip.SIDE_WALK)
        cat.stride += step
        scene.applyDepthOverFullStage(scene.config.followDepthShrink)
        return false
    }
}
