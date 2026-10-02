package com.oleanji.screencat

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

class Scene {
    val cat = CatState()
    var ball = BallState()
    // The walking area on screen, in dp, y up from the bottom of the display.
    // Android only uses the bottom edge, so local and screen space differ by
    // this rect's origin alone.
    var screenRect = Box()
    // The walking area in local coordinates. All behaviour maths, and
    // `cat.pos`, are in this space.
    var stage = Box()
    // How far from the floor the cat may stray, in local units.
    var roamBand = 0f
    var config = Config()
    // Areas for crawler mode to break, in local coordinates.
    var crawlTargets: List<Box> = emptyList()

    /** Lay out the local walking space on a screen. */
    fun setStage(screen: Box, catSize: Float) {
        screenRect = screen
        stage = Box(0f, 0f, screen.w, screen.h)
        // The band is measured off the shorter screen edge, so a tall phone
        // gets the same sensible depth as a wide one.
        val reference = min(screen.w, screen.h)
        roamBand = max(0f, min(stage.height, reference * config.roamHeight) - catSize)
    }

    /**
     * Depth over the whole screen rather than the narrow floor band, used
     * while the cat roams the full height. The shrink is what makes moving
     * up read as walking away instead of taking off.
     */
    fun applyDepthOverFullStage(strength: Float) {
        if (stage.height <= 1) { cat.depth = 1f; return }
        val t = clamp((cat.pos.y - stage.minY) / stage.height, 0f, 1f)
        cat.depth = 1 - strength * t
    }

    /**
     * A cat further from the floor is further away, so it draws slightly
     * smaller. Without this, drifting off the floor just looks like lift-off.
     */
    fun applyDepth() {
        if (roamBand <= 1) { cat.depth = 1f; return }
        val t = clamp((cat.pos.y - stage.minY) / roamBand, 0f, 1f)
        cat.depth = 1 - config.depthShrink * t
    }
}

interface Behavior {
    /** Returns true once the routine is finished. */
    fun update(dt: Float, scene: Scene): Boolean
}

// Scripted behaviours -------------------------------------------------------

sealed class Action {
    // Walk along a gentle arc to a point. `bend` curves the path so it is not
    // a straight line; the arc is a single sweep, never a bob.
    data class WalkTo(val p: P, val pace: Float, val bend: Float) : Action()
    data class RunTo(val p: P, val pace: Float) : Action()
    data class Hold(val clip: Clip, val seconds: Float) : Action()
    // Play a one-shot clip through to its last frame.
    data class Play(val clip: Clip) : Action()
    data class Face(val facing: Float) : Action()
}

class ScriptedBehavior(private val actions: List<Action>) : Behavior {
    // Which action is playing now. Equal to the count once the script is done.
    var index = 0
        private set
    private var started = false

    // Path state.
    private val samples = ArrayList<P>()
    private val cumulative = ArrayList<Float>()
    private var total = 0f
    private var travelled = 0f
    private var pace = 1f
    private var running = false
    private var paceSeed = 0f
    private var timer = 0f
    private var maxSlope = 0.45f

    override fun update(dt: Float, scene: Scene): Boolean {
        if (index < actions.size) {
            if (!started) { begin(actions[index], scene); started = true }
            if (step(actions[index], dt, scene)) {
                index += 1
                started = false
                return index >= actions.size
            }
            return false
        }
        return true
    }

    private fun begin(action: Action, scene: Scene) {
        val cat = scene.cat
        maxSlope = scene.config.maxSlope
        when (action) {
            is Action.WalkTo -> {
                buildPath(cat.pos, action.p, action.bend)
                pace = action.pace; running = false
                paceSeed = rnd(0f, (PI * 2).toFloat())
                travelled = 0f
            }
            is Action.RunTo -> {
                buildPath(cat.pos, action.p, 0f)
                pace = action.pace; running = true
                travelled = 0f
                cat.switchClip(Clip.RUN)
            }
            is Action.Hold -> {
                timer = action.seconds
                cat.switchClip(action.clip)
            }
            is Action.Play -> cat.switchClip(action.clip)
            is Action.Face -> cat.facing = action.facing
        }
    }

    /** Samples a quadratic arc so the walk can be advanced by real distance. */
    private fun buildPath(a: P, bRaw: P, bend: Float) {
        // Two rules, both about not looking airborne:
        //  - never climb: the sheet has no back view, and a side-on cat
        //    drifting upward reads as levitating;
        //  - never drop faster than maxSlope: a steep or vertical descent
        //    looks like the cat fell rather than walked.
        val drop = abs(bRaw.x - a.x) * maxSlope
        val b = P(bRaw.x, min(max(bRaw.y, a.y - drop), a.y))
        val dx = b.x - a.x
        val dy = b.y - a.y
        val len = max(1f, hypot(dx, dy))
        val perp = P(-dy / len, dx / len)
        // Cap the arc too. A perpendicular bulge on a level path is vertical
        // movement by another name, so keep it to a gentle sweep.
        val lean = min(bend, len * 0.08f) * (if (coin()) 1 else -1)
        val control = P((a.x + b.x) / 2 + perp.x * lean, (a.y + b.y) / 2 + perp.y * lean)

        samples.clear()
        cumulative.clear()
        val steps = 32
        for (i in 0..steps) {
            val t = i.toFloat() / steps
            val u = 1 - t
            samples.add(P(u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                          u * u * a.y + 2 * u * t * control.y + t * t * b.y))
        }
        var run = 0f
        cumulative.add(0f)
        for (i in 1 until samples.size) {
            run += hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y)
            cumulative.add(run)
        }
        total = max(1f, run)
    }

    private fun pointAt(distance: Float): Pair<P, P> {
        val d = clamp(distance, 0f, total)
        var i = 1
        while (i < cumulative.size - 1 && cumulative[i] < d) i++
        val seg = max(0.0001f, cumulative[i] - cumulative[i - 1])
        val t = (d - cumulative[i - 1]) / seg
        val a = samples[i - 1]
        val b = samples[i]
        val p = P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        val len = max(0.0001f, hypot(b.x - a.x, b.y - a.y))
        return Pair(p, P((b.x - a.x) / len, (b.y - a.y) / len))
    }

    private fun step(action: Action, dt: Float, scene: Scene): Boolean {
        val cat = scene.cat
        return when (action) {
            is Action.WalkTo, is Action.RunTo -> {
                val base = if (running) scene.config.runSpeed else scene.config.walkSpeed
                // Gentle drift in pace, so the walk is never metronomic.
                val wobble = if (running) 1f else 1 + 0.2f * sin(travelled / (cat.drawnSize * 2.4f) + paceSeed)
                val speed = cat.drawnSize * base * pace * wobble
                travelled += speed * dt

                val (p, tangent) = pointAt(travelled)
                cat.pos = p
                scene.applyDepth()

                // Sideways travel uses the profile walk; travel toward the
                // viewer uses the front-on walk. There is no away-facing
                // sprite, so an upward tangent falls back to the profile.
                if (abs(tangent.x) >= abs(tangent.y) || tangent.y > 0) {
                    cat.switchClip(if (running) Clip.RUN else Clip.SIDE_WALK)
                    if (abs(tangent.x) > 0.05f) cat.facing = if (tangent.x > 0) 1f else -1f
                } else {
                    cat.switchClip(if (running) Clip.RUN else Clip.FRONT_WALK)
                }
                cat.stride += speed * dt
                travelled >= total
            }
            is Action.Hold -> {
                timer -= dt
                timer <= 0
            }
            is Action.Play -> cat.finishedOnce
            is Action.Face -> true
        }
    }
}

// Ball chase ----------------------------------------------------------------

class BallBehavior : Behavior {
    private enum class Stage { CHASE, POUNCE, PLAY, BAT_AWAY, FOLLOW_OFF }
    private var stage = Stage.CHASE
    private var ballVel = P()
    private var friction = 0.55f
    private var timer = 0f
    private var exit = P()
    private var setUp = false
    private var heading = 1f
    private var playFor = 0f

    override fun update(dt: Float, scene: Scene): Boolean {
        val cat = scene.cat
        val rect = scene.stage
        if (!setUp) { configure(scene); setUp = true }

        if (scene.ball.visible) {
            scene.ball.pos.x += ballVel.x * dt
            scene.ball.pos.y += ballVel.y * dt
            val keep = friction.pow(dt)
            ballVel.x *= keep; ballVel.y *= keep
            val speed = hypot(ballVel.x, ballVel.y)
            if (speed < 6) ballVel = P()
            scene.ball.rotation -= (if (ballVel.x >= 0) 1 else -1) * (speed * dt) / max(1f, scene.ball.size * 0.5f)
        }

        when (stage) {
            Stage.CHASE -> {
                val dx = scene.ball.pos.x - cat.pos.x
                val dy = (scene.ball.pos.y - scene.ball.size * 0.5f) - cat.pos.y
                val dist = hypot(dx, dy)
                runCat(cat, dx, dy, dist, cat.drawnSize * scene.config.runSpeed, dt)
                scene.applyDepth()
                if ((dist < cat.drawnSize * 0.8f && hypot(ballVel.x, ballVel.y) < cat.drawnSize * 1.2f) ||
                    cat.clipTime > 25) {
                    stage = Stage.POUNCE
                    timer = 0.25f
                    cat.switchClip(Clip.RUN)
                }
            }
            Stage.POUNCE -> {
                timer -= dt
                if (timer <= 0) {
                    // The play animation draws its own yarn ball, so park the
                    // cat on the ball's spot and hide the loose one.
                    cat.pos = P(scene.ball.pos.x, scene.ball.pos.y - scene.ball.size * 0.5f)
                    scene.applyDepth()
                    scene.ball.visible = false
                    ballVel = P()
                    cat.switchClip(Clip.BALL_PLAY)
                    playFor = rnd(scene.config.playSecondsMin, scene.config.playSecondsMax)
                    stage = Stage.PLAY
                }
            }
            Stage.PLAY -> {
                playFor -= dt
                if (playFor <= 0) {
                    // Bat it away, off the far side.
                    exit = P(
                        if (heading > 0) rect.maxX + cat.drawnSize * 2.2f else rect.minX - cat.drawnSize * 2.2f,
                        min(max(cat.pos.y + rnd(-rect.height * 0.08f, 0f), rect.minY + cat.drawnSize * 0.1f),
                            rect.minY + rect.height * 0.75f),
                    )
                    scene.ball.pos = P(cat.pos.x + heading * cat.drawnSize * 0.4f, cat.pos.y + scene.ball.size * 0.5f)
                    scene.ball.visible = true
                    val d = P(exit.x - scene.ball.pos.x, exit.y - scene.ball.pos.y)
                    val len = max(1f, hypot(d.x, d.y))
                    val kick = cat.drawnSize * 8
                    ballVel = P(d.x / len * kick, d.y / len * kick)
                    friction = 0.92f
                    cat.facing = if (d.x >= 0) 1f else -1f
                    cat.switchClip(Clip.STAND_IDLE)
                    stage = Stage.BAT_AWAY
                    // A beat watching it go.
                    timer = 0.7f
                }
            }
            Stage.BAT_AWAY -> {
                timer -= dt
                if (timer <= 0) { stage = Stage.FOLLOW_OFF; cat.switchClip(Clip.RUN) }
            }
            Stage.FOLLOW_OFF -> {
                val dx = exit.x - cat.pos.x
                val dy = exit.y - cat.pos.y
                val dist = hypot(dx, dy)
                runCat(cat, dx, dy, dist, cat.drawnSize * scene.config.runSpeed, dt)
                scene.applyDepth()
                if (scene.ball.pos.x < rect.minX - cat.drawnSize * 2 || scene.ball.pos.x > rect.maxX + cat.drawnSize * 2) {
                    scene.ball.visible = false
                }
                if (dist < cat.drawnSize * 0.4f) return true
            }
        }
        return false
    }

    private fun runCat(cat: CatState, dx: Float, dy: Float, dist: Float, speed: Float, dt: Float) {
        cat.switchClip(Clip.RUN)
        if (dist <= 1) return
        val stepLen = min(speed * dt, dist)
        cat.pos.x += dx / dist * stepLen
        cat.pos.y += dy / dist * stepLen
        if (abs(dx) > dist * 0.15f) cat.facing = if (dx > 0) 1f else -1f
        cat.stride += stepLen
    }

    private fun configure(scene: Scene) {
        val cat = scene.cat
        val rect = scene.stage
        val size = cat.size

        // The ball rolls across the screen, so it enters from a side edge and
        // stops well inside the far half.
        heading = if (coin()) 1f else -1f
        val lane = groundY(scene)
        val start = P(if (heading > 0) rect.minX - size * 0.8f else rect.maxX + size * 0.8f, lane)
        val travel = rect.width * rnd(0.5f, 0.75f)
        val aim = P(start.x + heading * travel, lane)

        val d = P(aim.x - start.x, aim.y - start.y)
        val len = max(1f, hypot(d.x, d.y))

        scene.ball.size = size * 0.42f
        scene.ball.pos = P(start.x, start.y + scene.ball.size * 0.5f)
        scene.ball.rotation = 0f
        scene.ball.visible = true
        // Keeping 55% of speed per second means the ball coasts about 1.67x
        // its first second, so this launch speed lands it near `aim`.
        friction = 0.55f
        val roll = len * 0.62f
        ballVel = P(d.x / len * roll, d.y / len * roll)

        cat.pos = P(start.x - d.x / len * size * 1.8f, start.y)
        cat.facing = heading
        cat.switchClip(Clip.RUN)
        cat.visible = true
        scene.applyDepth()
    }
}

// Hungry (needs a food bowl drawn beside the cat) ---------------------------

class HungryBehavior(scene: Scene) : Behavior {
    private val inner: ScriptedBehavior
    var bowlAt: P? = null
        private set
    private val spot: P
    // Seconds since the cat started walking away, to lift the bowl a beat later.
    private var leftFor = 0f

    init {
        val cat = scene.cat
        val rect = scene.stage
        val size = cat.size
        val start = entryPoint(scene, size)
        cat.pos = start.copy()
        cat.visible = true

        // Beg down on the bottom band, level with or below where it came in.
        val target = P(rnd(rect.minX + rect.width * 0.2f, rect.maxX - rect.width * 0.2f), min(start.y, groundY(scene)))
        spot = target
        val beg = rnd(scene.config.begSecondsMin, scene.config.begSecondsMax)

        inner = ScriptedBehavior(listOf(
            Action.WalkTo(target, 1.0f, size * 0.5f),
            Action.Hold(Clip.STAND_IDLE, 0.6f),
            Action.Hold(Clip.SIT_IDLE, beg),
            Action.Hold(Clip.CROUCH, 1.2f),
            Action.WalkTo(exitPoint(rect, target, size), 1.1f, size * 0.35f),
        ))
    }

    override fun update(dt: Float, scene: Scene): Boolean {
        val done = inner.update(dt, scene)
        // Keyed to the script, not to a guessed walk time: pace wobble, depth
        // and the arc all change how long the walk in takes.
        if (inner.index >= 4) leftFor += dt
        bowlAt = if (inner.index >= 1 && leftFor < 1.0f) P(spot.x + scene.cat.drawnSize * 0.75f, spot.y) else null
        return done
    }
}

// Crawler ---------------------------------------------------------------------

/**
 * Crawler mode: walks under each target area in turn, zaps it from its head
 * and watches it "break". The breaking is drawn on the overlay; no app is
 * touched. Movement keeps every rule the other routines keep: in from the
 * side, level or downhill, out the side. It never climbs to a target; the zap
 * goes up instead.
 */
class CrawlBehavior(scene: Scene, targets: List<Box>) : Behavior, BreachSource {
    private enum class Stage { WALKING, ZAPPING, WATCHING, LEAVING }
    private var stage = Stage.WALKING
    private val targets: List<Box>
    private var current = 0
    private var walk: ScriptedBehavior? = null
    private var timer = 0f
    override val breaches = ArrayList<Breach>()
    override var zap: Zap? = null
        private set

    init {
        val cat = scene.cat
        val start = entryPoint(scene, cat.size)
        cat.pos = start.copy()
        cat.visible = true
        // Visit them in walking order from whichever side it came in.
        val fromLeft = start.x < scene.stage.midX
        this.targets = if (fromLeft) targets.sortedBy { it.midX } else targets.sortedByDescending { it.midX }
        beginWalk(scene)
    }

    private fun beginWalk(scene: Scene) {
        val cat = scene.cat
        if (current >= targets.size) {
            stage = Stage.LEAVING
            walk = ScriptedBehavior(listOf(Action.WalkTo(exitPoint(scene.stage, cat.pos, cat.size), 1.15f, cat.size * 0.3f)))
            return
        }
        val t = targets[current]
        val margin = cat.size
        val x = min(max(t.midX + rnd(-0.2f, 0.2f) * t.width, scene.stage.minX + margin), scene.stage.maxX - margin)
        val y = min(cat.pos.y, groundY(scene))
        walk = ScriptedBehavior(listOf(
            Action.WalkTo(P(x, y), 1.25f, cat.size * 0.3f),
            Action.Hold(Clip.STAND_IDLE, 0.3f),
        ))
        stage = Stage.WALKING
    }

    override fun update(dt: Float, scene: Scene): Boolean {
        for (b in breaches) b.age += dt
        breaches.removeAll { it.finished }
        zap?.let { it.age += dt }
        val cat = scene.cat

        when (stage) {
            Stage.WALKING -> {
                if (walk?.update(dt, scene) != false) {
                    val t = targets[current]
                    val head = P(cat.pos.x, cat.pos.y + cat.drawnSize * 0.75f)
                    val to = P(min(max(head.x, t.minX + 10), t.maxX - 10),
                               min(max(t.minY + 10, head.y + cat.drawnSize * 0.6f), t.maxY - 10))
                    zap = Zap(head, to, accentIndex = rndInt(0, GLITCH_ACCENTS.size - 1))
                    cat.switchClip(Clip.CROUCH)
                    timer = 0.8f
                    stage = Stage.ZAPPING
                }
            }
            Stage.ZAPPING -> {
                timer -= dt
                val z = zap
                if (timer <= 0 && z != null) {
                    val breach = Breach.random(targets[current], z.to)
                    breach.accentIndex = z.accentIndex
                    breaches.add(breach)
                    zap = null
                    cat.switchClip(Clip.SIT_IDLE)
                    timer = 1.8f
                    stage = Stage.WATCHING
                }
            }
            Stage.WATCHING -> {
                timer -= dt
                if (timer <= 0) {
                    current += 1
                    beginWalk(scene)
                }
            }
            Stage.LEAVING -> {
                val gone = walk?.update(dt, scene) ?: true
                return gone && breaches.isEmpty()
            }
        }
        return false
    }
}

// Behaviour factory -----------------------------------------------------------

enum class Routine(val key: String) {
    STROLL("stroll"), NAP("nap"), BALL("ball"), HUNGRY("hungry"), CRAWL("crawl"),
    // The nonstop crawl that runs while you are away from the phone.
    IDLE_CRAWL("idlecrawl"),
    // Three minutes of the idle crawl at four times the pace.
    MR_ROBOT("mrrobot");

    companion object {
        fun from(key: String?) = entries.firstOrNull { it.key == key }
    }
}

fun makeBehavior(routine: Routine, scene: Scene): Behavior {
    val cat = scene.cat
    val rect = scene.stage
    val size = cat.size

    return when (routine) {
        Routine.BALL -> BallBehavior()
        Routine.HUNGRY -> HungryBehavior(scene)
        Routine.CRAWL -> CrawlBehavior(scene, scene.crawlTargets)
        Routine.IDLE_CRAWL -> IdleCrawlBehavior(scene)
        Routine.MR_ROBOT -> IdleCrawlBehavior(scene, speed = 4f, maxDuration = 180f, countdown = 3f, catless = true)
        Routine.STROLL -> {
            val start = entryPoint(scene, size)
            cat.pos = start.copy()
            cat.visible = true
            val actions = ArrayList<Action>()
            var previous = start
            // Two to four legs. Each target is drawn from the bottom band and
            // is level with or below the last, and buildPath caps how steeply
            // the cat may descend, so the route is a series of shallow diagonals.
            repeat(rndInt(2, 4)) {
                val y = min(previous.y, groundY(scene))
                val p = P(rnd(rect.minX + size * 0.4f, rect.maxX - size * 0.4f), y)
                actions.add(Action.WalkTo(p, rnd(0.75f, 1.3f), size * rnd(0f, 0.7f)))
                if (coin() && coin()) {
                    actions.add(Action.Hold(if (coin()) Clip.SIT_IDLE else Clip.STAND_IDLE, rnd(1.5f, 4.0f)))
                }
                previous = p
            }
            actions.add(Action.WalkTo(exitPoint(rect, previous, size), rnd(0.9f, 1.2f), size * 0.3f))
            ScriptedBehavior(actions)
        }
        Routine.NAP -> {
            // Naps happen at the sides, and the walk in and out is level, so
            // the cat never has to climb to its bed.
            val onLeft = coin()
            val y = groundY(scene)
            val outside = P(if (onLeft) rect.minX - size * 1.4f else rect.maxX + size * 1.4f, y)
            val inside = P(
                if (onLeft) rect.minX + rect.width * rnd(0.12f, 0.3f) else rect.maxX - rect.width * rnd(0.12f, 0.3f),
                y,
            )
            cat.pos = outside.copy()
            cat.visible = true
            val nap = rnd(scene.config.napSecondsMin, scene.config.napSecondsMax)
            ScriptedBehavior(listOf(
                Action.WalkTo(inside, 0.9f, size * 0.15f),
                Action.Hold(Clip.STAND_IDLE, 0.7f),
                Action.Play(Clip.LIE_DOWN),
                Action.Hold(Clip.SLEEP, nap),
                Action.Hold(Clip.SIT_IDLE, 2.2f),
                Action.Hold(Clip.STAND_IDLE, 0.8f),
                Action.WalkTo(outside, 0.85f, size * 0.12f),
            ))
        }
    }
}

// Point helpers -----------------------------------------------------------------

/**
 * A standing spot, weighted toward the floor so the cat mostly pads along the
 * edge rather than drifting out into open screen.
 */
fun groundY(scene: Scene): Float {
    val u = rnd(0f, 1f)
    return scene.stage.minY + scene.roamBand * u.pow(scene.config.groundBias)
}

/**
 * Cats come on from either end of the floor. Entering from "above" would mean
 * a long descent, and a steep descent is exactly what looks like falling.
 */
fun entryPoint(scene: Scene, size: Float): P {
    val rect = scene.stage
    val y = groundY(scene)
    return P(if (coin()) rect.minX - size * 1.4f else rect.maxX + size * 1.4f, y)
}

/** The nearest way out, always sideways and always level. */
fun exitPoint(rect: Box, from: P, size: Float): P {
    val goLeft = (from.x - rect.minX) <= (rect.maxX - from.x)
    return P(if (goLeft) rect.minX - size * 2.0f else rect.maxX + size * 2.0f, from.y)
}

/**
 * Android cannot see other apps' windows, so crawler mode breaks made-up
 * areas instead: two to four app-sized patches above the floor band.
 */
fun pretendWindows(scene: Scene): List<Box> {
    val s = scene.stage
    val count = rndInt(2, 4)
    return (0 until count).map {
        val w = s.width * rnd(0.35f, 0.6f)
        val h = s.height * rnd(0.14f, 0.24f)
        val x = rnd(s.minX, s.maxX - w)
        val y = rnd(s.minY + s.height * 0.22f, s.maxY - h - s.height * 0.06f)
        Box(x, y, w, h)
    }
}
