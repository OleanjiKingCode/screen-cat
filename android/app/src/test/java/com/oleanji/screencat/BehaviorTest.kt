package com.oleanji.screencat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Plays routines offscreen, the way the Mac's --simulate does, and checks the
 * movement rules. No Android drawing is touched.
 */
class BehaviorTest {
    private val dt = 1f / 60f

    private fun scene(): Scene {
        val s = Scene()
        // A phone in portrait, in dp, above a 48 dp navigation bar.
        val frame = Box(0f, 48f, 411f, 866f)
        s.cat.size = maxOf(24f, frame.height / s.config.sizeDivisor)
        s.setStage(frame, s.cat.size)
        s.crawlTargets = pretendWindows(s)
        return s
    }

    @Test
    fun glitchRandomMatchesTheMac() {
        // Reference values printed by the Swift GlitchRandom.
        val expected = mapOf(
            1 to listOf(0.913283f, 0.592588f, 0.365874f, 0.550861f),
            7 to listOf(0.163284f, 0.916552f, 0.904503f, 0.323891f),
            99 to listOf(0.627124f, 0.637840f, 0.133339f, 0.106321f),
            4000000000L.toInt() to listOf(0.304126f, 0.592001f, 0.569763f, 0.618259f),
        )
        for ((seed, values) in expected) {
            val g = GlitchRandom(seed)
            for (v in values) assertEquals(v, g.unit(), 0.000002f)
        }
    }

    @Test
    fun fiftyNamedStyles() {
        assertEquals(50, GLITCH_RECIPES.size)
        assertEquals(50, GLITCH_RECIPES.map { it.name }.toSet().size)
    }

    @Test
    fun everyRoutineFinishesAndLeavesBySide() {
        for (routine in listOf(Routine.STROLL, Routine.NAP, Routine.BALL, Routine.HUNGRY, Routine.CRAWL)) {
            repeat(20) {
                val s = scene()
                s.config = s.config.copy(napSecondsMin = 2f, napSecondsMax = 3f, begSecondsMin = 1f, begSecondsMax = 2f)
                val b = makeBehavior(routine, s)
                var t = 0f
                var done = false
                while (t < 240f && !done) {
                    s.cat.advance(dt)
                    done = b.update(dt, s)
                    t += dt
                    // Never far above the floor band: the rules keep it low.
                    assertTrue("$routine climbed to ${s.cat.pos.y}", s.cat.pos.y <= s.roamBand + s.cat.size)
                }
                assertTrue("$routine did not finish", done)
                val x = s.cat.pos.x
                assertTrue("$routine ended on screen at $x", x < s.stage.minX + s.cat.size || x > s.stage.maxX - s.cat.size)
            }
        }
    }

    @Test
    fun strollNeverDescendsSteeperThanMaxSlope() {
        repeat(50) {
            val s = scene()
            val b = makeBehavior(Routine.STROLL, s)
            var last = s.cat.pos.copy()
            var done = false
            var t = 0f
            while (!done && t < 240f) {
                s.cat.advance(dt)
                done = b.update(dt, s)
                t += dt
                val dx = abs(s.cat.pos.x - last.x)
                val dy = s.cat.pos.y - last.y
                // Arcs bend at most 8% of a leg, so allow a little on top.
                if (dx + abs(dy) > 0.5f) assertTrue("dropped too steeply", -dy <= dx * (s.config.maxSlope + 0.35f) + 0.01f)
                last = s.cat.pos.copy()
            }
        }
    }

    @Test
    fun idleCrawlGrowsTakesOverRoamsShallowAndShrinksAway() {
        val s = scene()
        val base = s.cat.size
        val idle = makeBehavior(Routine.IDLE_CRAWL, s) as IdleCrawlBehavior
        idle.requestTargets = { pretendWindows(s) }
        var t = 0f
        var maxSize = 0f
        var last = s.cat.pos.copy()
        var steepest = 0f
        var sawTakeover = false
        val styles = HashSet<Int>()
        while (t < 200f) {
            s.cat.advance(dt)
            assertFalse(idle.update(dt, s))
            t += dt
            maxSize = maxOf(maxSize, s.cat.size)
            if (idle.takeoverOpacity >= 1f) sawTakeover = true
            styles.add(idle.recipeIndex)
            val dx = abs(s.cat.pos.x - last.x)
            val dy = abs(s.cat.pos.y - last.y)
            if (idle.stageName == "moving" && dx + dy > 0.01f) steepest = maxOf(steepest, dy / maxOf(dx, 0.0001f))
            last = s.cat.pos.copy()
        }
        assertEquals(base * s.config.growScale, maxSize, base * 0.2f)
        assertTrue("glitch never took over", sawTakeover)
        assertTrue("style never changed", styles.size >= 3)
        assertTrue("roamed steeper than maxSlope: $steepest", steepest <= s.config.maxSlope + 0.01f)

        idle.beginExit()
        assertEquals(0f, idle.takeoverOpacity, 0f)
        var gone = false
        var e = 0f
        while (!gone && e < 2f) {
            s.cat.advance(dt)
            gone = idle.update(dt, s)
            e += dt
        }
        assertTrue("did not shrink away", gone)
        assertTrue("shrink took $e s", e in 0.75f..0.9f)
    }

    @Test
    fun mrRobotCountsDownThenEndsAfterThreeMinutes() {
        val s = scene()
        val robot = makeBehavior(Routine.MR_ROBOT, s) as IdleCrawlBehavior
        assertFalse(s.cat.visible)
        assertTrue(robot.countdownLeft > 2.9f)
        var t = 0f
        var done = false
        var styleChanges = 0
        var lastStyle = robot.recipeIndex
        while (!done && t < 190f) {
            s.cat.advance(dt)
            done = robot.update(dt, s)
            t += dt
            if (t > 3.1f && t < 3.2f) assertTrue(s.cat.visible)
            if (robot.recipeIndex != lastStyle) { styleChanges++; lastStyle = robot.recipeIndex }
        }
        assertTrue(done)
        assertTrue("ended at $t", t in 180f..182f)
        // A style every 15 s over about two and a half minutes of glitch.
        assertTrue("only $styleChanges style changes", styleChanges >= 8)
    }
}
