import AppKit

final class Scene {
    let cat = CatState()
    var ball = BallState()
    /// Which edge the cat is treating as the floor this time.
    var surface: Surface = .bottom
    /// The screen the routine plays out on, in global coordinates.
    var screenRect: CGRect = .zero
    /// The walking area in surface-local coordinates. All behaviour maths, and
    /// `cat.pos`, are in this space; the surface transform maps it to the screen.
    var stage: CGRect = .zero
    /// How far from the floor the cat may stray, in local units.
    var roamBand: CGFloat = 0
    var config = Config()
    /// Windows for crawler mode to break, in surface-local coordinates.
    var crawlTargets: [CGRect] = []
    /// What the trash rescue goes after, and where the Trash is, as a
    /// surface-local x on the floor.
    var rescueItems: [TrashedItem] = []
    var trashX: CGFloat = 0
    /// Where Finder sits in the Dock, surface-local. Things thrown from a
    /// folder other than the Desktop are tossed back there.
    var finderSpot: CGPoint = .zero
    /// The loaded sprites, for routines that need to know where the body is.
    var sheet: SpriteSheet?

    /// Lay out the local walking space for a surface on a screen.
    func setStage(surface: Surface, screen: CGRect, catSize: CGFloat) {
        self.surface = surface
        screenRect = screen
        stage = surface.localRect(for: screen)
        // The band is measured off the shorter screen edge, so a wall gets the
        // same sensible depth as the floor instead of half the screen width.
        let reference = min(screen.width, screen.height)
        roamBand = max(0, min(stage.height, reference * config.roamHeight) - catSize)
    }

    /// Depth over the whole screen rather than the narrow floor band, used
    /// while following the pointer. The cat is free to roam the full height
    /// there, and this shrink is what makes moving up read as walking away
    /// into the room instead of taking off.
    func applyDepthOverFullStage(strength: CGFloat) {
        guard stage.height > 1 else { cat.depth = 1; return }
        let t = min(max((cat.pos.y - stage.minY) / stage.height, 0), 1)
        cat.depth = 1 - strength * t
    }

    /// A cat further from the floor is further away, so it draws slightly
    /// smaller. Without this, drifting off the floor just looks like lift-off.
    func applyDepth() {
        guard roamBand > 1 else { cat.depth = 1; return }
        let t = min(max((cat.pos.y - stage.minY) / roamBand, 0), 1)
        cat.depth = 1 - config.depthShrink * t
    }
}

protocol Behavior: AnyObject {
    /// Returns true once the routine is finished.
    func update(_ dt: CGFloat, _ scene: Scene) -> Bool
}

// MARK: - Scripted behaviours

enum Action {
    /// Walk along a gentle arc to a point. `bend` curves the path so it is not
    /// a straight line; the arc is a single sweep, never a bob.
    case walkTo(CGPoint, pace: CGFloat, bend: CGFloat)
    case runTo(CGPoint, pace: CGFloat)
    case hold(Clip, CGFloat)
    /// Play a one-shot clip through to its last frame.
    case play(Clip)
    case face(CGFloat)
}

final class ScriptedBehavior: Behavior {
    private let actions: [Action]
    /// Which action is playing now. Equal to the count once the script is done.
    private(set) var index = 0
    private var started = false

    // Path state
    private var samples: [CGPoint] = []
    private var cumulative: [CGFloat] = []
    private var total: CGFloat = 0
    private var travelled: CGFloat = 0
    private var pace: CGFloat = 1
    private var running = false
    private var paceSeed: CGFloat = 0
    private var timer: CGFloat = 0
    private var maxSlope: CGFloat = 0.45

    init(_ actions: [Action]) { self.actions = actions }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        while index < actions.count {
            if !started { begin(actions[index], scene); started = true }
            if step(actions[index], dt, scene) {
                index += 1
                started = false
                return index >= actions.count
            }
            return false
        }
        return true
    }

    private func begin(_ action: Action, _ scene: Scene) {
        let cat = scene.cat
        maxSlope = scene.config.maxSlope
        switch action {
        case .walkTo(let p, let pc, let bend):
            buildPath(from: cat.pos, to: p, bend: bend)
            pace = pc; running = false
            paceSeed = CGFloat.random(in: 0...(.pi * 2))
            travelled = 0
        case .runTo(let p, let pc):
            buildPath(from: cat.pos, to: p, bend: 0)
            pace = pc; running = true
            travelled = 0
            cat.setClip(.run)
        case .hold(let clip, let seconds):
            timer = seconds
            cat.setClip(clip)
        case .play(let clip):
            cat.setClip(clip)
        case .face(let f):
            cat.facing = f
        }
    }

    /// Samples a quadratic arc so the walk can be advanced by real distance.
    private func buildPath(from a: CGPoint, to bRaw: CGPoint, bend: CGFloat) {
        // Two rules, both about not looking airborne:
        //  - never climb: the sheet has no back view, and a side-on cat drifting
        //    upward reads as levitating;
        //  - never drop faster than maxSlope: a steep or vertical descent looks
        //    like the cat fell rather than walked.
        let drop = abs(bRaw.x - a.x) * maxSlope
        let b = CGPoint(x: bRaw.x, y: min(max(bRaw.y, a.y - drop), a.y))
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let perp = CGPoint(x: -dy / len, y: dx / len)
        // Cap the arc too. A perpendicular bulge on a level path is vertical
        // movement by another name, so keep it to a gentle sweep.
        let lean = min(bend, len * 0.08) * (Bool.random() ? 1 : -1)
        let control = CGPoint(x: (a.x + b.x) / 2 + perp.x * lean,
                              y: (a.y + b.y) / 2 + perp.y * lean)

        samples.removeAll(keepingCapacity: true)
        cumulative.removeAll(keepingCapacity: true)
        let steps = 32
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let u = 1 - t
            samples.append(CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                                   y: u * u * a.y + 2 * u * t * control.y + t * t * b.y))
        }
        var run: CGFloat = 0
        cumulative.append(0)
        for i in 1..<samples.count {
            run += hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y)
            cumulative.append(run)
        }
        total = max(1, run)
    }

    private func pointAt(_ distance: CGFloat) -> (CGPoint, CGPoint) {
        let d = min(max(distance, 0), total)
        var i = 1
        while i < cumulative.count - 1 && cumulative[i] < d { i += 1 }
        let seg = max(0.0001, cumulative[i] - cumulative[i - 1])
        let t = (d - cumulative[i - 1]) / seg
        let a = samples[i - 1], b = samples[i]
        let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        let len = max(0.0001, hypot(b.x - a.x, b.y - a.y))
        return (p, CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len))
    }

    private func step(_ action: Action, _ dt: CGFloat, _ scene: Scene) -> Bool {
        let cat = scene.cat
        switch action {
        case .walkTo, .runTo:
            let base = running ? scene.config.runSpeed : scene.config.walkSpeed
            // Gentle drift in pace, so the walk is never metronomic.
            let wobble = running ? 1 : 1 + 0.2 * sin(travelled / (cat.drawnSize * 2.4) + paceSeed)
            let speed = cat.drawnSize * base * pace * wobble
            travelled += speed * dt

            let (p, tangent) = pointAt(travelled)
            cat.pos = p
            scene.applyDepth()

            // Sideways travel uses the profile walk; travel toward the viewer
            // uses the front-on walk. There is no away-facing sprite, so an
            // upward tangent falls back to the profile.
            if abs(tangent.x) >= abs(tangent.y) || tangent.y > 0 {
                cat.setClip(running ? .run : .sideWalk)
                if abs(tangent.x) > 0.05 { cat.facing = tangent.x > 0 ? 1 : -1 }
            } else {
                cat.setClip(running ? .run : .frontWalk)
            }
            cat.stride += speed * dt
            return travelled >= total

        case .hold:
            timer -= dt
            return timer <= 0

        case .play:
            return cat.finishedOnce

        case .face:
            return true
        }
    }
}

// MARK: - Ball chase

final class BallBehavior: Behavior {
    private enum Stage { case chase, pounce, play, batAway, followOff }
    private var stage: Stage = .chase
    private var ballVel = CGPoint.zero
    private var friction: CGFloat = 0.55
    private var timer: CGFloat = 0
    private var exit = CGPoint.zero
    private var setUp = false
    private var heading: CGFloat = 1
    private var playFor: CGFloat = 0

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        let cat = scene.cat
        let rect = scene.stage
        if !setUp { configure(scene); setUp = true }

        if scene.ball.visible {
            scene.ball.pos.x += ballVel.x * dt
            scene.ball.pos.y += ballVel.y * dt
            let keep = pow(friction, dt)
            ballVel.x *= keep; ballVel.y *= keep
            let speed = hypot(ballVel.x, ballVel.y)
            if speed < 6 { ballVel = .zero }
            scene.ball.rotation -= (ballVel.x >= 0 ? 1 : -1) * (speed * dt) / max(1, scene.ball.size * 0.5)
        }

        switch stage {
        case .chase:
            let dx = scene.ball.pos.x - cat.pos.x
            let dy = (scene.ball.pos.y - scene.ball.size * 0.5) - cat.pos.y
            let dist = hypot(dx, dy)
            runCat(cat, dx: dx, dy: dy, dist: dist,
                   speed: cat.drawnSize * scene.config.runSpeed, dt: dt)
            scene.applyDepth()
            if (dist < cat.drawnSize * 0.8 && hypot(ballVel.x, ballVel.y) < cat.drawnSize * 1.2)
                || cat.clipTime > 25 {
                stage = .pounce
                timer = 0.25
                cat.setClip(.run)
            }

        case .pounce:
            timer -= dt
            if timer <= 0 {
                // The play animation draws its own yarn ball, so park the cat on
                // the ball's spot and hide the loose one.
                cat.pos = CGPoint(x: scene.ball.pos.x, y: scene.ball.pos.y - scene.ball.size * 0.5)
                scene.applyDepth()
                scene.ball.visible = false
                ballVel = .zero
                cat.setClip(.ballPlay)
                playFor = CGFloat.random(in: scene.config.playSecondsMin...scene.config.playSecondsMax)
                stage = .play
            }

        case .play:
            playFor -= dt
            if playFor <= 0 {
                // Bat it away, off the far side.
                exit = CGPoint(x: heading > 0 ? rect.maxX + cat.drawnSize * 2.2
                                              : rect.minX - cat.drawnSize * 2.2,
                               y: min(max(cat.pos.y + CGFloat.random(in: -rect.height * 0.08...0),
                                          rect.minY + cat.drawnSize * 0.1),
                                      rect.minY + rect.height * 0.75))
                scene.ball.pos = CGPoint(x: cat.pos.x + heading * cat.drawnSize * 0.4,
                                         y: cat.pos.y + scene.ball.size * 0.5)
                scene.ball.visible = true
                let d = CGPoint(x: exit.x - scene.ball.pos.x, y: exit.y - scene.ball.pos.y)
                let len = max(1, hypot(d.x, d.y))
                let kick = cat.drawnSize * 8
                ballVel = CGPoint(x: d.x / len * kick, y: d.y / len * kick)
                friction = 0.92
                cat.facing = d.x >= 0 ? 1 : -1
                cat.setClip(.standIdle)
                stage = .batAway
                timer = 0.7   // a beat watching it go
            }

        case .batAway:
            timer -= dt
            if timer <= 0 { stage = .followOff; cat.setClip(.run) }

        case .followOff:
            let dx = exit.x - cat.pos.x, dy = exit.y - cat.pos.y
            let dist = hypot(dx, dy)
            runCat(cat, dx: dx, dy: dy, dist: dist,
                   speed: cat.drawnSize * scene.config.runSpeed, dt: dt)
            scene.applyDepth()
            if scene.ball.pos.x < rect.minX - cat.drawnSize * 2 ||
               scene.ball.pos.x > rect.maxX + cat.drawnSize * 2 {
                scene.ball.visible = false
            }
            if dist < cat.drawnSize * 0.4 { return true }
        }
        return false
    }

    private func runCat(_ cat: CatState, dx: CGFloat, dy: CGFloat, dist: CGFloat,
                        speed: CGFloat, dt: CGFloat) {
        cat.setClip(.run)
        guard dist > 1 else { return }
        let stepLen = min(speed * dt, dist)
        cat.pos.x += dx / dist * stepLen
        cat.pos.y += dy / dist * stepLen
        if abs(dx) > dist * 0.15 { cat.facing = dx > 0 ? 1 : -1 }
        cat.stride += stepLen
    }

    private func configure(_ scene: Scene) {
        let cat = scene.cat
        let rect = scene.stage
        let size = cat.size

        // The ball rolls across the screen, so it enters from a side edge and
        // stops well inside the far half.
        heading = Bool.random() ? 1 : -1
        let lane = groundY(scene, size: size)
        let start = CGPoint(x: heading > 0 ? rect.minX - size * 0.8 : rect.maxX + size * 0.8, y: lane)
        let travel = rect.width * CGFloat.random(in: 0.5...0.75)
        let aim = CGPoint(x: start.x + heading * travel, y: lane)

        let d = CGPoint(x: aim.x - start.x, y: aim.y - start.y)
        let len = max(1, hypot(d.x, d.y))

        scene.ball.size = size * 0.42
        scene.ball.pos = CGPoint(x: start.x, y: start.y + scene.ball.size * 0.5)
        scene.ball.rotation = 0
        scene.ball.visible = true
        // Keeping 55% of speed per second means the ball coasts about 1.67x its
        // first second, so this launch speed lands it near `aim`.
        friction = 0.55
        let roll = len * 0.62
        ballVel = CGPoint(x: d.x / len * roll, y: d.y / len * roll)

        cat.pos = CGPoint(x: start.x - d.x / len * size * 1.8, y: start.y)
        cat.facing = heading
        cat.setClip(.run)
        cat.visible = true
        scene.applyDepth()
    }
}

// MARK: - Hungry (needs a food bowl drawn beside the cat)

final class HungryBehavior: Behavior {
    private let inner: ScriptedBehavior
    private(set) var bowlAt: CGPoint?
    private let spot: CGPoint
    /// Seconds since the cat started walking away, to lift the bowl a beat later.
    private var leftFor: CGFloat = 0

    init(scene: Scene) {
        let cat = scene.cat
        let rect = scene.stage
        let size = cat.size
        let start = entryPoint(scene, size: size)
        cat.pos = start
        cat.visible = true

        // Beg down on the bottom band, level with or below where it came in.
        let target = CGPoint(x: CGFloat.random(in: rect.minX + rect.width * 0.2...rect.maxX - rect.width * 0.2),
                             y: min(start.y, groundY(scene, size: size)))
        spot = target
        let beg = CGFloat.random(in: scene.config.begSecondsMin...scene.config.begSecondsMax)

        inner = ScriptedBehavior([
            .walkTo(target, pace: 1.0, bend: size * 0.5),
            .hold(.standIdle, 0.6),
            .hold(.sitIdle, beg),
            .hold(.crouch, 1.2),
            .walkTo(exitPoint(rect, from: target, size: size), pace: 1.1, bend: size * 0.35),
        ])
    }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        let done = inner.update(dt, scene)
        // Keyed to the script, not to a guessed walk time: pace wobble, depth
        // and the arc all change how long the walk in takes, so a timer put
        // the bowl down before the cat arrived or after it had sat.
        if inner.index >= 4 { leftFor += dt }
        bowlAt = (inner.index >= 1 && leftFor < 1.0)
            ? CGPoint(x: spot.x + scene.cat.drawnSize * 0.75, y: spot.y)
            : nil
        return done
    }
}

// MARK: - Asking to play

/// Walks on, sits, and asks for a game with a speech bubble. If the OK button is
/// clicked inside the invite window, the cat follows your pointer for a while.
/// Otherwise it gives up and wanders off.
final class PlayBehavior: Behavior {
    private enum Stage { case arriving, asking, following, leaving }
    private var stage: Stage = .arriving
    private var script: ScriptedBehavior
    private var leaving: ScriptedBehavior?
    private var waited: CGFloat = 0
    private var followed: CGFloat = 0
    private var fidget: CGFloat = 0
    /// Which way the cat is zig-zagging while it climbs toward the pointer.
    private var legDirection: CGFloat = 1
    /// Test hook: a stand-in for the real pointer, in global screen coordinates.
    static var pointerSource: (() -> CGPoint)?
    private let spot: CGPoint

    /// Set while the invite is up, in surface-local coordinates. The app turns
    /// this into a screen rect so the click can be matched and the window can
    /// stop being click-through just over the button.
    private(set) var bubbleTip: CGPoint?
    /// Flipped by the app when the OK button is clicked.
    var accepted = false
    /// Set by the app each frame: is the pointer resting on the bubble or cat?
    var pointerResting = false
    /// How much of the required dwell has been served, 0...1, for the button fill.
    private(set) var dwellProgress: CGFloat = 0
    private var dwell: CGFloat = 0

    init(scene: Scene) {
        let cat = scene.cat
        let rect = scene.stage
        let size = cat.size
        let start = entryPoint(scene, size: size)
        cat.pos = start
        cat.visible = true
        // Well inside the screen, so the bubble has room and does not hang off.
        spot = CGPoint(x: CGFloat.random(in: rect.minX + rect.width * 0.25...rect.maxX - rect.width * 0.25),
                       y: min(start.y, groundY(scene, size: size)))
        script = ScriptedBehavior([
            .walkTo(spot, pace: 1.1, bend: size * 0.3),
            .hold(.standIdle, 0.4),
        ])
    }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        let cat = scene.cat
        switch stage {
        case .arriving:
            if script.update(dt, scene) {
                stage = .asking
                cat.setClip(.sitIdle)
                bubbleTip = CGPoint(x: cat.pos.x, y: cat.pos.y + cat.drawnSize * 1.05)
            }

        case .asking:
            waited += dt
            bubbleTip = CGPoint(x: cat.pos.x, y: cat.pos.y + cat.drawnSize * 1.05)

            // Resting the pointer on the cat or its bubble counts as saying yes,
            // so you never have to hit a small target. Moving away resets it,
            // otherwise a pointer parked at the bottom of the screen would
            // accept by accident.
            let needed = max(0.5, scene.config.dwellSeconds)
            dwell = pointerResting ? dwell + dt : 0
            dwellProgress = min(dwell / needed, 1)
            if dwell >= needed { accepted = true }
            // Shift about a little so it does not look frozen for three minutes.
            fidget -= dt
            if fidget <= 0 {
                fidget = CGFloat.random(in: 4...11)
                cat.setClip([Clip.sitIdle, .sitIdle, .standIdle, .crouch].randomElement()!)
            }
            if accepted {
                bubbleTip = nil
                followed = 0
                stage = .following
                cat.setClip(.standIdle)
            } else if waited >= scene.config.inviteSeconds {
                bubbleTip = nil
                stage = .leaving
                leaving = ScriptedBehavior([
                    .hold(.crouch, 0.8),
                    .walkTo(exitPoint(scene.stage, from: cat.pos, size: cat.size), pace: 1.0, bend: cat.size * 0.3),
                ])
            }

        case .following:
            followed += dt
            follow(scene, dt: dt)
            if followed >= scene.config.followSeconds {
                stage = .leaving
                leaving = ScriptedBehavior([
                    .hold(.sitIdle, 1.4),
                    .walkTo(exitPoint(scene.stage, from: cat.pos, size: cat.size), pace: 1.0, bend: cat.size * 0.3),
                ])
            }

        case .leaving:
            return leaving?.update(dt, scene) ?? true
        }
        return false
    }

    /// Trots after the pointer across the whole screen.
    ///
    /// Following in y as well as x means giving up the "never leave the floor"
    /// rule, so the thing that stopped it looking like levitation has to come
    /// from somewhere else. Two mechanisms replace it:
    ///
    ///  - the screen is treated as a floor receding away from you, and the cat
    ///    shrinks as it moves up it, so height reads as distance;
    ///  - it still never travels steeply. Vertical speed stays within
    ///    `maxSlope` of horizontal, so it can neither rise nor drop vertically.
    ///
    /// When the pointer is somewhere it cannot reach on one shallow diagonal,
    /// the cat switchbacks: it zig-zags up, the way you would walk up a slope
    /// too steep to take head on, rather than floating straight there.
    private func follow(_ scene: Scene, dt: CGFloat) {
        let cat = scene.cat
        let inverse = scene.surface.transform(for: scene.screenRect).inverted()
        let pointer = (PlayBehavior.pointerSource?() ?? NSEvent.mouseLocation).applying(inverse)
        let margin = cat.drawnSize * 0.6
        let target = CGPoint(
            x: min(max(pointer.x, scene.stage.minX + margin), scene.stage.maxX - margin),
            y: min(max(pointer.y, scene.stage.minY), scene.stage.maxY - cat.drawnSize * 1.3))

        let dx = target.x - cat.pos.x
        let dy = target.y - cat.pos.y
        let distance = hypot(dx, dy)
        // Settle beside the pointer rather than jittering underneath it.
        let comfort = cat.drawnSize * 0.8
        guard distance > comfort else {
            cat.setClip(.sitIdle)
            return
        }

        let slope = max(0.05, scene.config.maxSlope)
        let hurrying = distance > cat.drawnSize * 5
        let pace = cat.drawnSize * (hurrying ? scene.config.runSpeed : scene.config.walkSpeed)
        var step = pace * dt
        var vx: CGFloat
        var vy: CGFloat

        if abs(dy) <= slope * abs(dx) {
            // Shallow enough to head straight for it.
            vx = dx / distance
            vy = dy / distance
            legDirection = dx >= 0 ? 1 : -1
            step = min(step, distance - comfort)
        } else {
            // Too steep. Hold the steepest allowed diagonal and turn at the
            // ends of each leg, so it climbs by zig-zagging.
            let reach = cat.drawnSize * 2.5
            let leavingStage = legDirection > 0
                ? cat.pos.x + step > scene.stage.maxX - margin
                : cat.pos.x - step < scene.stage.minX + margin
            let pastTarget = (cat.pos.x - target.x) * legDirection > reach
            if leavingStage || pastTarget { legDirection = -legDirection }
            let length = sqrt(1 + slope * slope)
            vx = legDirection / length
            vy = (dy > 0 ? slope : -slope) / length
        }

        cat.pos.x += vx * step
        cat.pos.y += vy * step
        cat.pos.y = min(max(cat.pos.y, scene.stage.minY),
                        scene.stage.maxY - cat.drawnSize * 1.3)
        if abs(vx) > 0.05 { cat.facing = vx > 0 ? 1 : -1 }
        cat.setClip(hurrying ? .run : .sideWalk)
        cat.stride += step
        scene.applyDepthOverFullStage(strength: scene.config.followDepthShrink)
    }
}

// MARK: - Crawler

/// Crawler mode: walks under each target window in turn, zaps it from its head
/// and watches it "break". The breaking is drawn on the overlay; the windows
/// themselves are never touched. Movement keeps every rule the other routines
/// keep: in from the side, level or downhill, out the side. It never climbs to
/// a window; the zap goes up instead.
// MARK: - LLM mode

/// LLM mode: walks on, sits under the answer card, and stays while the card is
/// up. `release()` sends it off again.
final class AskBehavior: Behavior {
    private var script: ScriptedBehavior
    private var leaving: ScriptedBehavior?
    private var seated = false
    private var released = false
    private var fidget: CGFloat = 0
    /// Where the cat sits, so the card can go up before it arrives.
    let spot: CGPoint

    init(scene: Scene) {
        let cat = scene.cat
        let rect = scene.stage
        let size = cat.size
        let start = entryPoint(scene, size: size)
        cat.pos = start
        cat.visible = true
        // Toward the right, and far enough in that the card above fits.
        let margin = max(220, size * 2)
        let low = max(rect.minX + margin, rect.minX + rect.width * 0.55)
        let high = max(low, min(rect.maxX - margin, rect.minX + rect.width * 0.8))
        spot = CGPoint(x: CGFloat.random(in: low...high), y: min(start.y, groundY(scene, size: size)))
        script = ScriptedBehavior([
            .walkTo(spot, pace: 1.2, bend: size * 0.3),
            .hold(.standIdle, 0.3),
        ])
    }

    func release() { released = true }
    var isLeaving: Bool { released }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        let cat = scene.cat
        if let leaving { return leaving.update(dt, scene) }
        if released {
            leaving = ScriptedBehavior([
                .hold(.standIdle, 0.4),
                .walkTo(exitPoint(scene.stage, from: cat.pos, size: cat.size), pace: 1.0, bend: cat.size * 0.3),
            ])
            return false
        }
        if !seated {
            if script.update(dt, scene) {
                seated = true
                cat.setClip(.sitIdle)
                fidget = CGFloat.random(in: 5...10)
            }
            return false
        }
        // Shift about a little while you read, so it does not look frozen.
        fidget -= dt
        if fidget <= 0 {
            fidget = CGFloat.random(in: 5...12)
            cat.setClip([Clip.sitIdle, .sitIdle, .sitIdle, .standIdle].randomElement()!)
        }
        return false
    }
}

final class CrawlBehavior: Behavior, BreachSource {
    private enum Stage { case walking, zapping, watching, leaving }
    private var stage: Stage = .walking
    private let targets: [CGRect]
    private var current = 0
    private var walk: ScriptedBehavior?
    private var timer: CGFloat = 0
    private(set) var breaches: [Breach] = []
    private(set) var zap: Zap?

    init(scene: Scene, targets: [CGRect]) {
        let cat = scene.cat
        let start = entryPoint(scene, size: cat.size)
        cat.pos = start
        cat.visible = true
        // Visit them in walking order from whichever side it came in.
        let fromLeft = start.x < scene.stage.midX
        self.targets = targets.sorted { fromLeft ? $0.midX < $1.midX : $0.midX > $1.midX }
        beginWalk(scene)
    }

    private func beginWalk(_ scene: Scene) {
        let cat = scene.cat
        guard current < targets.count else {
            stage = .leaving
            walk = ScriptedBehavior([
                .walkTo(exitPoint(scene.stage, from: cat.pos, size: cat.size), pace: 1.15, bend: cat.size * 0.3),
            ])
            return
        }
        let t = targets[current]
        let margin = cat.size
        let x = min(max(t.midX + CGFloat.random(in: -0.2...0.2) * t.width, scene.stage.minX + margin),
                    scene.stage.maxX - margin)
        let y = min(cat.pos.y, groundY(scene, size: cat.size))
        walk = ScriptedBehavior([
            .walkTo(CGPoint(x: x, y: y), pace: 1.25, bend: cat.size * 0.3),
            .hold(.standIdle, 0.3),
        ])
        stage = .walking
    }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        for i in breaches.indices { breaches[i].age += dt }
        breaches.removeAll { $0.finished }
        zap?.age += dt
        let cat = scene.cat

        switch stage {
        case .walking:
            if walk?.update(dt, scene) ?? true {
                let t = targets[current]
                let head = CGPoint(x: cat.pos.x, y: cat.pos.y + cat.drawnSize * 0.75)
                let to = CGPoint(x: min(max(head.x, t.minX + 10), t.maxX - 10),
                                 y: min(max(t.minY + 10, head.y + cat.drawnSize * 0.6), t.maxY - 10))
                zap = Zap(from: head, to: to, accentIndex: Int.random(in: 0..<glitchAccents.count))
                cat.setClip(.crouch)
                timer = 0.8
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
                timer = 1.8
                stage = .watching
            }
        case .watching:
            timer -= dt
            if timer <= 0 {
                current += 1
                beginWalk(scene)
            }
        case .leaving:
            let gone = walk?.update(dt, scene) ?? true
            return gone && breaches.isEmpty
        }
        return false
    }
}

// MARK: - Behaviour factory

enum Routine: String, CaseIterable {
    case stroll, nap, ball, hungry, play, crawl
    /// The nonstop crawl that runs while you are away from the Mac.
    case idleCrawl = "idlecrawl"
    /// Zero Day: three minutes of catless glitching at high speed.
    case zeroDay = "zeroday"
    /// LLM mode: sits under the answer to what you copied.
    case ask
    /// Digs what you just threw away out of the Trash and puts it back.
    case rescue
}

func makeBehavior(_ routine: Routine, scene: Scene) -> Behavior {
    let cat = scene.cat
    let rect = scene.stage
    let size = cat.size

    switch routine {
    case .ball:
        return BallBehavior()

    case .hungry:
        return HungryBehavior(scene: scene)

    case .play:
        return PlayBehavior(scene: scene)

    case .ask:
        return AskBehavior(scene: scene)

    case .rescue:
        return RescueBehavior(scene: scene, items: scene.rescueItems, trashX: scene.trashX)

    case .crawl:
        return CrawlBehavior(scene: scene, targets: scene.crawlTargets)

    case .idleCrawl:
        return IdleCrawlBehavior(scene: scene, targets: scene.crawlTargets)

    case .zeroDay:
        return IdleCrawlBehavior(scene: scene, targets: scene.crawlTargets, speed: scene.config.zeroDaySpeed,
                                 maxDuration: 180, catless: true)

    case .stroll:
        let start = entryPoint(scene, size: size)
        cat.pos = start
        cat.visible = true
        var actions: [Action] = []
        var previous = start
        // Two to four legs. Each target is drawn from the bottom band and is
        // level with or below the last, and buildPath caps how steeply the cat
        // may descend, so the route is a series of shallow diagonals.
        for _ in 0..<Int.random(in: 2...4) {
            let y = min(previous.y, groundY(scene, size: size))
            let p = CGPoint(x: CGFloat.random(in: rect.minX + size * 0.4...rect.maxX - size * 0.4), y: y)
            actions.append(.walkTo(p, pace: CGFloat.random(in: 0.75...1.3),
                                   bend: size * CGFloat.random(in: 0...0.7)))
            if Bool.random() && Bool.random() {
                actions.append(.hold(Bool.random() ? .sitIdle : .standIdle,
                                     CGFloat.random(in: 1.5...4.0)))
            }
            previous = p
        }
        actions.append(.walkTo(exitPoint(rect, from: previous, size: size),
                               pace: CGFloat.random(in: 0.9...1.2), bend: size * 0.3))
        return ScriptedBehavior(actions)

    case .nap:
        // Naps happen at the sides, and the walk in and out is level, so the cat
        // never has to climb to its bed.
        let onLeft = Bool.random()
        let y = groundY(scene, size: size)
        let outside = CGPoint(x: onLeft ? rect.minX - size * 1.4 : rect.maxX + size * 1.4, y: y)
        let inside = CGPoint(x: onLeft ? rect.minX + rect.width * CGFloat.random(in: 0.12...0.3)
                                       : rect.maxX - rect.width * CGFloat.random(in: 0.12...0.3), y: y)
        cat.pos = outside
        cat.visible = true
        let nap = CGFloat.random(in: scene.config.napSecondsMin...scene.config.napSecondsMax)
        return ScriptedBehavior([
            .walkTo(inside, pace: 0.9, bend: size * 0.15),
            .hold(.standIdle, 0.7),
            .play(.lieDown),
            .hold(.sleep, nap),
            .hold(.sitIdle, 2.2),
            .hold(.standIdle, 0.8),
            .walkTo(outside, pace: 0.85, bend: size * 0.12),
        ])
    }
}

// MARK: - Point helpers

/// A standing spot, weighted toward the floor so the cat mostly pads along the
/// edge it is walking on rather than drifting out into open screen.
func groundY(_ scene: Scene, size: CGFloat) -> CGFloat {
    let u = CGFloat.random(in: 0...1)
    return scene.stage.minY + scene.roamBand * pow(u, scene.config.groundBias)
}

/// Cats come on from either end of the floor. Entering from "above" would mean
/// a long descent, and a steep descent is exactly what looks like falling.
func entryPoint(_ scene: Scene, size: CGFloat) -> CGPoint {
    let rect = scene.stage
    let y = groundY(scene, size: size)
    return CGPoint(x: Bool.random() ? rect.minX - size * 1.4 : rect.maxX + size * 1.4, y: y)
}

/// The nearest way out, always sideways and always level.
func exitPoint(_ rect: CGRect, from: CGPoint, size: CGFloat) -> CGPoint {
    let goLeft = (from.x - rect.minX) <= (rect.maxX - from.x)
    return CGPoint(x: goLeft ? rect.minX - size * 2.0 : rect.maxX + size * 2.0, y: from.y)
}
