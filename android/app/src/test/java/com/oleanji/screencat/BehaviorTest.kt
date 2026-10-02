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
    fun zeroDayNeverShowsTheCatHopsAndEndsAfterThreeMinutes() {
        val s = scene()
        val zeroDay = makeBehavior(Routine.ZERO_DAY, s) as IdleCrawlBehavior
        assertTrue(zeroDay.catless)
        assertTrue(zeroDay.countdownLeft > 2.9f)
        var t = 0f
        var done = false
        var styleChanges = 0
        var lastStyle = zeroDay.recipeIndex
        var hops = 0
        var wasHopping = false
        var sawFull = false
        var minAfterFull = 1f
        while (!done && t < 190f) {
            s.cat.advance(dt)
            done = zeroDay.update(dt, s)
            t += dt
            assertFalse("cat showed at $t", s.cat.visible)
            // Fades in over 0.3 s once the countdown is over.
            if (t > 3.4f && t < 4f) assertTrue(zeroDay.takeoverOpacity >= 0.99f)
            if (zeroDay.takeoverOpacity >= 0.99f) sawFull = true
            if (sawFull && !done) minAfterFull = minOf(minAfterFull, zeroDay.takeoverOpacity)
            val hopping = zeroDay.stageName == "hopping"
            if (hopping && !wasHopping) hops++
            wasHopping = hopping
            if (zeroDay.recipeIndex != lastStyle) { styleChanges++; lastStyle = zeroDay.recipeIndex }
        }
        assertTrue(done)
        assertEquals(Routine.ZERO_DAY, Routine.from("zeroday"))
        assertTrue("ended at $t", t in 180f..181f)
        // A hop every 1.5 to 3 s plus 0.8 s of dim, over 177 s of glitch.
        assertTrue("$hops hops", hops in 45..78)
        assertTrue("dimmed to $minAfterFull during hops", minAfterFull in 0.24f..0.26f)
        assertTrue("only $styleChanges style changes", styleChanges >= hops)
    }

    @Test
    fun zeroDayTouchEndsAtOnceWithNoShrink() {
        val s = scene()
        val zeroDay = makeBehavior(Routine.ZERO_DAY, s) as IdleCrawlBehavior
        var t = 0f
        while (t < 10f) { s.cat.advance(dt); zeroDay.update(dt, s); t += dt }
        zeroDay.beginExit()
        assertEquals(0f, zeroDay.takeoverOpacity, 0f)
        assertTrue("did not end on the next frame", zeroDay.update(dt, s))
        assertFalse(s.cat.visible)
    }

    @Test
    fun noCatThemeLeftInTheGlitches() {
        val names = GLITCH_RECIPES.map { it.name }
        for (gone in listOf("Blue Screen of Meow", "Meow Wall", "Cat Virus", "Cat OS Crash", "Gold Rush", "Error 404")) {
            assertFalse(gone, names.contains(gone))
        }
        for (gone in listOf("Pink Rain", "Ice Rain", "Purple Haze", "Sunset Melt", "Frozen", "Neon Tunnel", "Synthwave Scope", "Outrun")) {
            assertFalse(gone, names.contains(gone))
        }
        for (now in listOf("Kernel Panic", "Root Wall", "Worm Outbreak", "Fatal Exception", "Ransomware", "Access Denied",
                           "Blood Rain", "Binary Rain", "Red Haze", "Firewall Melt", "Lockdown", "Breach Tunnel",
                           "Signal Intercept", "Grid Runner")) {
            assertTrue(now, names.contains(now))
        }
    }
}
