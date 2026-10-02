import AppKit

/// The crawl that runs while you are away. It starts after a stretch with no
/// mouse, trackpad or keyboard input and only ends when the app stops it,
/// which it does on the first touch or key press.
///
/// The cat roams the whole screen here, not just its floor. Like "follow me",
/// that is only allowed because two things stand in for the floor: it shrinks
/// as it goes up, so up reads as further away, and it never moves steeper than
/// `maxSlope`, zig-zagging up anything steeper instead of rising straight.
///
/// It walks to each window, stands on its bottom edge, zaps it and lets it
/// break. With the windows done it heads for the side of the screen it is
/// travelling toward. There it asks the app for the next app, which slides in
/// like a three-finger swipe, and comes in from the other side. With no other
/// app to go to, it turns round and starts again on the same screen.
final class IdleCrawlBehavior: Behavior, BreachSource {
    private enum Stage { case moving, zapping, watching, switching, growing }
    private var stage: Stage = .moving
    private var targets: [CGRect] = []
    private var current = 0
    private var goal = CGPoint.zero
    /// True while heading for the edge rather than a window.
    private var leaving = false
    private var direction: CGFloat = 1
    private var legDirection: CGFloat = 1
    private var timer: CGFloat = 0
    private(set) var breaches: [Breach] = []
    private(set) var zap: Zap?
    private(set) var aura: Aura?
    private var elapsed: CGFloat = 0
    private var grown = false
    private var growTime: CGFloat = 0
    private var baseSize: CGFloat = 0
    /// What the cat was doing when it stopped to grow, to pick up after.
    private var stageBeforeGrowing: Stage = .moving
    private let growDuration: CGFloat = 3

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
        load(targets, scene)
    }

    /// Takes a new set of windows, in walking order. An empty desktop gets a
    /// few patches of screen to break instead, so there is always something.
    private func load(_ windows: [CGRect], _ scene: Scene) {
        var list = windows
        if list.isEmpty {
            let s = scene.stage
            list = (0..<3).map { _ in
                let w = s.width * CGFloat.random(in: 0.2...0.35)
                let h = s.height * CGFloat.random(in: 0.2...0.35)
                return CGRect(x: CGFloat.random(in: s.minX...(s.maxX - w)),
                              y: CGFloat.random(in: s.minY...(s.maxY - h)), width: w, height: h)
            }
        }
        targets = list.sorted { direction > 0 ? $0.midX < $1.midX : $0.midX > $1.midX }
        current = 0
        nextGoal(scene)
    }

    private func nextGoal(_ scene: Scene) {
        let cat = scene.cat
        let s = scene.stage
        let top = s.maxY - cat.size * 1.3
        stage = .moving
        if current < targets.count {
            // Stand on the window's bottom edge, somewhere along it.
            let t = targets[current]
            let inset = min(cat.size, t.width / 3)
            goal = CGPoint(x: CGFloat.random(in: (t.minX + inset)...(t.maxX - inset)),
                           y: min(max(t.minY, s.minY), top))
            leaving = false
        } else {
            goal = CGPoint(x: direction > 0 ? s.maxX - cat.size * 0.6 : s.minX + cat.size * 0.6,
                           y: min(max(cat.pos.y + CGFloat.random(in: -0.2...0.2) * s.height, s.minY), top))
            leaving = true
        }
    }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        for i in breaches.indices { breaches[i].age += dt }
        breaches.removeAll { $0.finished }
        zap?.age += dt
        let cat = scene.cat
        elapsed += dt

        // After `growAfterSeconds` of crawling it powers up, once: it stops
        // where it is and grows to `growScale` in front of you. Only between
        // moves, so it never grows mid-zap or off screen.
        if !grown, elapsed >= scene.config.growAfterSeconds, cat.visible,
           stage == .moving || stage == .watching {
            grown = true
            growTime = 0
            stageBeforeGrowing = stage
            stage = .growing
            zap = nil
            cat.setClip(.standIdle)
        }

        switch stage {
        case .growing:
            growTime += dt
            let t = min(1, growTime / growDuration)
            // Grows in pulses that settle, so the change is easy to watch.
            let pulse = 1 + 0.08 * sin(t * .pi * 6) * (1 - t)
            let eased = t * t * (3 - 2 * t)
            cat.size = baseSize * (1 + (scene.config.growScale - 1) * eased) * pulse
            // Keep the head on screen as it gets bigger.
            cat.pos.y = min(cat.pos.y, scene.stage.maxY - cat.size * 1.3)
            aura = Aura(center: CGPoint(x: cat.pos.x, y: cat.pos.y + cat.drawnSize * 0.45),
                        size: cat.drawnSize, progress: t, age: growTime, accentIndex: Int(growTime * 2) % glitchAccents.count)
            if t >= 1 {
                cat.size = baseSize * scene.config.growScale
                aura = nil
                stage = stageBeforeGrowing
            }

        case .moving:
            guard roam(toward: goal, scene, dt) else { break }
            if leaving {
                if requestNextApp?(direction) == true {
                    // Off this side; the next app slides in. Wait for the
                    // Space animation before looking at its windows.
                    cat.visible = false
                    timer = 1.4
                    stage = .switching
                } else {
                    direction = -direction
                    load(requestTargets?() ?? [], scene)
                }
            } else {
                let t = targets[current]
                let head = CGPoint(x: cat.pos.x, y: cat.pos.y + cat.drawnSize * 0.75)
                let to = CGPoint(x: min(max(head.x + CGFloat.random(in: -40...40), t.minX + 10), t.maxX - 10),
                                 y: min(max(head.y + cat.drawnSize * 0.8, t.minY + 10), t.maxY - 10))
                zap = Zap(from: head, to: to, accentIndex: Int.random(in: 0..<glitchAccents.count))
                cat.setClip(.crouch)
                timer = 0.7
                stage = .zapping
            }

        case .zapping:
            timer -= dt
            if timer <= 0, let z = zap {
                var breach = Breach.random(rect: targets[current], touch: z.to)
                breach.accentIndex = z.accentIndex
                breaches.append(breach)
                zap = nil
                cat.setClip(.sitIdle)
                timer = CGFloat.random(in: 0.8...1.6)
                stage = .watching
            }

        case .watching:
            timer -= dt
            if timer <= 0 {
                current += 1
                nextGoal(scene)
            }

        case .switching:
            timer -= dt
            if timer <= 0 {
                // Come in from the side the screen slid in from.
                let s = scene.stage
                cat.pos = CGPoint(x: direction > 0 ? s.minX - cat.size : s.maxX + cat.size,
                                  y: min(cat.pos.y, s.maxY - cat.size * 1.3))
                cat.visible = true
                load(requestTargets?() ?? [], scene)
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
