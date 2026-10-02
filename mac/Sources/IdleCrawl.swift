import AppKit

/// The crawl that runs while you are away, in any mode. It starts after a
/// stretch with no mouse, trackpad or keyboard input and only ends when the
/// app stops it, which it does on the first touch or key press.
///
/// The order is: the cat walks in on a normal screen, stops and grows to
/// `growScale` while you watch, then the whole screen turns into a glitch. One
/// style plays for `glitchStyleSeconds`, then the next takes over. The cat
/// roams the screen on top of it, up, down and sideways, zapping windows. At
/// the edge it brings the next app forward, which slides in like a
/// three-finger swipe. The glitch drops for that moment, so the new screen is
/// seen normally while the cat walks in, then a new style takes it over.
///
/// The cat roams the whole screen here, not just its floor. Like "follow me",
/// that is only allowed because two things stand in for the floor: it shrinks
/// as it goes up, so up reads as further away, and it never moves steeper than
/// `maxSlope`, zig-zagging up anything steeper instead of rising straight.
final class IdleCrawlBehavior: Behavior, BreachSource {
    private enum Stage { case entering, growing, moving, zapping, resting, switching, arriving }
    private var stage: Stage = .entering
    /// For `--idle-selftest` and the log.
    var stageName: String { "\(stage)" }
    private struct Stop {
        var point: CGPoint
        /// The window to zap there, if it is a window and not just a waypoint.
        var window: CGRect?
    }
    private var stops: [Stop] = []
    private var current = 0
    private var goal = CGPoint.zero
    /// True while heading for the edge rather than a stop.
    private var leaving = false
    private var direction: CGFloat = 1
    private var legDirection: CGFloat = 1
    private var timer: CGFloat = 0
    private var growTime: CGFloat = 0
    private var baseSize: CGFloat = 0
    private let growDuration: CGFloat = 3

    private(set) var breaches: [Breach] = []
    private(set) var zap: Zap?
    private(set) var aura: Aura?

    // The full-screen glitch.
    private var takeoverOn = false
    private(set) var takeoverOpacity: CGFloat = 0
    private(set) var recipeIndex = Int.random(in: 0..<glitchRecipes.count)
    private(set) var styleTime: CGFloat = 0
    private(set) var styleSeed = UInt32.random(in: 1...UInt32.max)
    private(set) var pulse: CGFloat = 0

    /// Fresh windows for the screen as it is now.
    var requestTargets: (() -> [CGRect])?
    /// Bring the next app forward in this direction. True if it did.
    var requestNextApp: ((CGFloat) -> Bool)?

    init(scene: Scene, targets: [CGRect]) {
        let cat = scene.cat
        baseSize = cat.size
        let start = entryPoint(scene, size: cat.size)
        cat.pos = start
        cat.visible = true
        direction = start.x < scene.stage.midX ? 1 : -1
        walkIn(scene)
    }

    /// From off the side to a spot a quarter of the way in, on a normal screen.
    private func walkIn(_ scene: Scene) {
        let s = scene.stage
        goal = CGPoint(x: direction > 0 ? s.minX + s.width * 0.25 : s.maxX - s.width * 0.25,
                       y: min(scene.cat.pos.y, s.maxY - scene.cat.size * 1.3))
        leaving = false
    }

    /// The next style, never the one just shown.
    private func nextStyle() {
        var next = Int.random(in: 0..<glitchRecipes.count)
        if next == recipeIndex { next = (next + 1) % glitchRecipes.count }
        recipeIndex = next
        styleTime = 0
        styleSeed = UInt32.random(in: 1...UInt32.max)
        pulse = 1
    }

    /// Where to go on this screen: each window, plus a couple of open spots so
    /// it wanders the whole screen, in walking order.
    private func planStops(_ windows: [CGRect], _ scene: Scene) {
        let s = scene.stage
        let top = s.maxY - scene.cat.size * 1.3
        var list: [Stop] = windows.map { w in
            let inset = min(scene.cat.size, w.width / 3)
            return Stop(point: CGPoint(x: CGFloat.random(in: (w.minX + inset)...(w.maxX - inset)),
                                       y: min(max(w.minY, s.minY), top)), window: w)
        }
        for _ in 0..<Int.random(in: 2...3) {
            list.append(Stop(point: CGPoint(x: CGFloat.random(in: (s.minX + s.width * 0.1)...(s.maxX - s.width * 0.1)),
                                            y: CGFloat.random(in: s.minY...max(s.minY, top))), window: nil))
        }
        stops = list.sorted { direction > 0 ? $0.point.x < $1.point.x : $0.point.x > $1.point.x }
        current = 0
        nextGoal(scene)
    }

    private func nextGoal(_ scene: Scene) {
        let s = scene.stage
        stage = .moving
        if current < stops.count {
            goal = stops[current].point
            leaving = false
        } else {
            let top = s.maxY - scene.cat.size * 1.3
            goal = CGPoint(x: direction > 0 ? s.maxX - scene.cat.size * 0.6 : s.minX + scene.cat.size * 0.6,
                           y: min(max(scene.cat.pos.y + CGFloat.random(in: -0.2...0.2) * s.height, s.minY), top))
            leaving = true
        }
    }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        zap?.age += dt
        pulse = max(0, pulse - dt * 1.5)
        // Fades in over 1.2s, out over 0.4s so the next screen shows promptly.
        takeoverOpacity = takeoverOn ? min(1, takeoverOpacity + dt / 1.2) : max(0, takeoverOpacity - dt / 0.4)
        if takeoverOpacity > 0 {
            styleTime += dt
            if styleTime >= scene.config.glitchStyleSeconds { nextStyle() }
        }
        let cat = scene.cat

        switch stage {
        case .entering, .arriving:
            if roam(toward: goal, scene, dt) {
                if stage == .entering {
                    stage = .growing
                    growTime = 0
                    cat.setClip(.standIdle)
                } else {
                    takeoverOn = true
                    nextStyle()
                    planStops(requestTargets?() ?? [], scene)
                }
            }

        case .growing:
            growTime += dt
            let t = min(1, growTime / growDuration)
            // Grows in pulses that settle, so the change is easy to watch.
            let wobble = 1 + 0.08 * sin(t * .pi * 6) * (1 - t)
            let eased = t * t * (3 - 2 * t)
            cat.size = baseSize * (1 + (scene.config.growScale - 1) * eased) * wobble
            cat.pos.y = min(cat.pos.y, scene.stage.maxY - cat.size * 1.3)
            aura = Aura(center: CGPoint(x: cat.pos.x, y: cat.pos.y + cat.drawnSize * 0.45),
                        size: cat.drawnSize, progress: t, age: growTime,
                        accentIndex: Int(growTime * 2) % glitchAccents.count)
            if t >= 1 {
                cat.size = baseSize * scene.config.growScale
                aura = nil
                takeoverOn = true
                planStops(requestTargets?() ?? [], scene)
            }

        case .moving:
            guard roam(toward: goal, scene, dt) else { break }
            if leaving {
                if requestNextApp?(direction) == true {
                    // Off this side. The glitch drops so the next app is seen
                    // as it slides in; wait out the Space animation first.
                    cat.visible = false
                    takeoverOn = false
                    timer = 1.4
                    stage = .switching
                } else {
                    // Nowhere to go: turn round, with a new style.
                    direction = -direction
                    nextStyle()
                    planStops(requestTargets?() ?? [], scene)
                }
            } else if let window = stops[current].window {
                let head = CGPoint(x: cat.pos.x, y: cat.pos.y + cat.drawnSize * 0.75)
                let to = CGPoint(x: min(max(head.x + CGFloat.random(in: -60...60), window.minX + 10), window.maxX - 10),
                                 y: min(max(head.y + cat.drawnSize, window.minY + 10), window.maxY - 10))
                zap = Zap(from: head, to: to, accentIndex: Int.random(in: 0..<glitchAccents.count))
                cat.setClip(.crouch)
                timer = 0.7
                stage = .zapping
            } else {
                cat.setClip(Bool.random() ? .sitIdle : .standIdle)
                timer = CGFloat.random(in: 0.6...1.4)
                stage = .resting
            }

        case .zapping:
            timer -= dt
            if timer <= 0 {
                zap = nil
                pulse = 1
                cat.setClip(.sitIdle)
                timer = 0.8
                stage = .resting
            }

        case .resting:
            timer -= dt
            if timer <= 0 {
                current += 1
                nextGoal(scene)
            }

        case .switching:
            timer -= dt
            if timer <= 0 {
                // Come in from the side the screen slid in from, on a normal
                // screen; the glitch comes back once it is in.
                let s = scene.stage
                cat.pos = CGPoint(x: direction > 0 ? s.minX - cat.size : s.maxX + cat.size,
                                  y: min(cat.pos.y, s.maxY - cat.size * 1.3))
                cat.visible = true
                walkIn(scene)
                stage = .arriving
            }
        }
        // Never finishes by itself; any input ends it.
        return false
    }

    /// One frame of walking toward `target` anywhere on the screen. True on
    /// arrival. Shallow routes are taken straight; steeper ones zig-zag at the
    /// steepest allowed slope, turning at the ends of each leg.
    private func roam(toward target: CGPoint, _ scene: Scene, _ dt: CGFloat) -> Bool {
        let cat = scene.cat
        let dx = target.x - cat.pos.x
        let dy = target.y - cat.pos.y
        let distance = hypot(dx, dy)
        guard distance > max(2, cat.drawnSize * 0.15) else { return true }

        let slope = max(0.05, scene.config.maxSlope)
        let hurrying = distance > cat.drawnSize * 6
        let pace = cat.drawnSize * (hurrying ? scene.config.runSpeed * 0.7 : scene.config.walkSpeed * 1.3)
        var step = pace * dt
        let vx: CGFloat, vy: CGFloat
        let margin = cat.drawnSize * 0.6
        if abs(dy) <= slope * abs(dx) {
            vx = dx / distance
            vy = dy / distance
            legDirection = dx >= 0 ? 1 : -1
            step = min(step, distance)
        } else {
            let reach = cat.drawnSize * 2.5
            let offStage = legDirection > 0
                ? cat.pos.x + step > scene.stage.maxX - margin
                : cat.pos.x - step < scene.stage.minX + margin
            let pastTarget = (cat.pos.x - target.x) * legDirection > reach
            if offStage || pastTarget { legDirection = -legDirection }
            let length = sqrt(1 + slope * slope)
            vx = legDirection / length
            vy = (dy > 0 ? slope : -slope) / length
        }
        cat.pos.x += vx * step
        cat.pos.y = min(max(cat.pos.y + vy * step, scene.stage.minY), scene.stage.maxY - cat.drawnSize * 1.3)
        if abs(vx) > 0.05 { cat.facing = vx > 0 ? 1 : -1 }
        cat.setClip(hurrying ? .run : .sideWalk)
        cat.stride += step
        scene.applyDepthOverFullStage(strength: scene.config.followDepthShrink)
        return false
    }
}
