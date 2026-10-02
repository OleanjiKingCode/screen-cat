import AVFoundation

/// Zero Day's background sound, made live rather than played from a file: a
/// low, uneasy drone, quick data beeps, bursts of static crackle, and a rising
/// whoosh each time it hops to another app. Quiet by default (`zeroDayVolume`).
///
/// Everything the audio thread reads lives in `Synth`, and the render block
/// only does arithmetic on it: no allocation, no locks, nothing that can stall
/// the audio.
final class ZeroDaySound {
    private final class Synth {
        var sampleRate: Float = 44_100
        var volume: Float = 0.25
        /// Where the gain is heading: 1 while playing, 0 to fade out.
        var target: Float = 0
        var gain: Float = 0
        /// Bumped by the main thread on each hop; the audio thread compares.
        var hopsRequested: Int = 0
        var hopsPlayed: Int = 0

        var drone = (Float(0), Float(0), Float(0))
        var lfo: Float = 0
        var beepPhase: Float = 0
        var beepFrequency: Float = 0
        var beepLeft = 0
        var beepWait = 0
        var noiseLeft = 0
        var noiseWait = 0
        var noiseHold: Float = 0
        var noiseCount = 0
        var sweepLeft = 0
        var sweepPhase: Float = 0
        var random: UInt32 = 0x9E37_79B9
        /// Made once here: an array literal inside `next()` would allocate on
        /// the audio thread.
        let pitches: [Float] = [660, 880, 1320, 1760, 2640, 3520]

        /// xorshift32, 0 to 1. Cheap enough for the audio thread.
        func unit() -> Float {
            random ^= random << 13
            random ^= random >> 17
            random ^= random << 5
            return Float(random) / Float(UInt32.max)
        }

        func next() -> Float {
            let sr = sampleRate
            let twoPi = Float.pi * 2
            gain += (target - gain) * 0.0004

            // Drone: three low sines a hair apart, so they beat and throb.
            drone.0 += twoPi * 55 / sr
            drone.1 += twoPi * 55.6 / sr
            drone.2 += twoPi * 110.4 / sr
            lfo += twoPi * 0.18 / sr
            if drone.0 > twoPi { drone.0 -= twoPi }
            if drone.1 > twoPi { drone.1 -= twoPi }
            if drone.2 > twoPi { drone.2 -= twoPi }
            if lfo > twoPi { lfo -= twoPi }
            let throb = 0.7 + 0.3 * sin(lfo)
            var out = (0.35 * sin(drone.0) + 0.3 * sin(drone.1) + 0.12 * sin(drone.2)) * throb * 0.6

            // Data beeps: short square blips at computer-ish pitches.
            if beepLeft > 0 {
                beepLeft -= 1
                beepPhase += twoPi * beepFrequency / sr
                if beepPhase > twoPi { beepPhase -= twoPi }
                out += (sin(beepPhase) > 0 ? 0.09 : -0.09)
            } else {
                beepWait -= 1
                if beepWait <= 0 {
                    beepFrequency = pitches[Int(unit() * Float(pitches.count - 1))]
                    beepLeft = Int(sr * (0.02 + 0.06 * unit()))
                    beepWait = Int(sr * (0.04 + 0.5 * unit()))
                }
            }

            // Static crackle: held noise samples, which sounds bit-crushed.
            if noiseLeft > 0 {
                noiseLeft -= 1
                noiseCount += 1
                if noiseCount % 6 == 0 { noiseHold = unit() * 2 - 1 }
                out += noiseHold * 0.12
            } else {
                noiseWait -= 1
                if noiseWait <= 0 {
                    noiseLeft = Int(sr * (0.02 + 0.08 * unit()))
                    noiseWait = Int(sr * (0.3 + 1.5 * unit()))
                }
            }

            // Hop whoosh: a fast rising sweep with noise, half a second long.
            if hopsPlayed != hopsRequested {
                hopsPlayed = hopsRequested
                sweepLeft = Int(sr * 0.5)
            }
            if sweepLeft > 0 {
                let total = sr * 0.5
                let t = 1 - Float(sweepLeft) / total
                sweepLeft -= 1
                sweepPhase += twoPi * (150 + 2400 * t * t) / sr
                if sweepPhase > twoPi { sweepPhase -= twoPi }
                out += (sin(sweepPhase) * 0.18 + (unit() * 2 - 1) * 0.06) * (1 - t)
            }

            // Soft clip, then the master level.
            return tanh(out) * gain * volume
        }
    }

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let synth = Synth()
    private var stopWork: DispatchWorkItem?

    func start(volume: Float) {
        stopWork?.cancel()
        synth.volume = max(0, min(1, volume))
        synth.target = 1
        guard node == nil else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        synth.sampleRate = Float(format.sampleRate)
        let synth = self.synth
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let sample = synth.next()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            node = source
        } catch {
            NSLog("Screen Cat: could not start Zero Day sound: %@", error.localizedDescription)
            engine.detach(source)
        }
    }

    /// `--zeroday-sound <path.wav> [seconds]`: the same sound written to a
    /// file instead of the speakers, with a hop every two seconds.
    static func writeSample(to path: String, seconds: Double) {
        let synth = Synth()
        synth.target = 1
        synth.gain = 1
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let file = try? AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings) else { return }
        buffer.frameLength = frames
        var peak: Float = 0, sum: Float = 0
        for i in 0..<Int(frames) {
            if i % Int(format.sampleRate * 2) == Int(format.sampleRate) { synth.hopsRequested += 1 }
            let s = synth.next()
            peak = max(peak, abs(s))
            sum += s * s
            buffer.floatChannelData![0][i] = s
            buffer.floatChannelData![1][i] = s
        }
        try? file.write(from: buffer)
        print(String(format: "wrote %@: %.0fs, peak %.3f, rms %.3f (volume %.2f)", path, seconds, peak,
                     (sum / Float(frames)).squareRoot(), synth.volume))
    }

    /// The whoosh for a hop to another app.
    func hop() { synth.hopsRequested &+= 1 }

    /// Fades out quickly, then shuts the engine down so nothing idles.
    func stop() {
        synth.target = 0
        guard node != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let node = self.node else { return }
            self.engine.stop()
            self.engine.detach(node)
            self.node = nil
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}
