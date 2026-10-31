using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace ScreenCat;

/// Zero Day's background sound, made live rather than played from a file: a
/// low, uneasy drone, quick data beeps, bursts of static crackle, and a rising
/// whoosh each time it hops to another app. Quiet by default (`zeroDayVolume`).
///
/// A small waveOut player on its own thread keeps four short buffers queued.
/// The thread only does arithmetic on `Synth` and copies samples, so nothing
/// on the UI thread can stall the audio. It fades out and closes the device
/// by itself after `Stop`.
public sealed class ZeroDaySound
{
    private const int SampleRate = 44_100;
    private const int Channels = 2;
    private const int BufferFrames = 2048;
    private const int BufferCount = 4;

    public sealed class Synth
    {
        public float SampleRateF = SampleRate;
        public volatile float Volume = 0.25f;
        /// Where the gain is heading: 1 while playing, 0 to fade out.
        public volatile float Target;
        public float Gain;
        /// Bumped by the UI thread on each hop; the audio thread compares.
        public int HopsRequested;
        private int hopsPlayed;

        private float drone0, drone1, drone2;
        private float lfo;
        private float beepPhase;
        private float beepFrequency;
        private int beepLeft;
        private int beepWait;
        private int noiseLeft;
        private int noiseWait;
        private float noiseHold;
        private int noiseCount;
        private int sweepLeft;
        private float sweepPhase;
        private uint random = 0x9E37_79B9;
        private static readonly float[] Pitches = { 660, 880, 1320, 1760, 2640, 3520 };

        /// xorshift32, 0 to 1. Cheap enough for the audio thread.
        private float Unit()
        {
            random ^= random << 13;
            random ^= random >> 17;
            random ^= random << 5;
            return random / (float)uint.MaxValue;
        }

        public float Next()
        {
            float sr = SampleRateF;
            const float twoPi = MathF.PI * 2;
            Gain += (Target - Gain) * 0.0004f;

            // Drone: three low sines a hair apart, so they beat and throb.
            drone0 += twoPi * 55 / sr;
            drone1 += twoPi * 55.6f / sr;
            drone2 += twoPi * 110.4f / sr;
            lfo += twoPi * 0.18f / sr;
            if (drone0 > twoPi) drone0 -= twoPi;
            if (drone1 > twoPi) drone1 -= twoPi;
            if (drone2 > twoPi) drone2 -= twoPi;
            if (lfo > twoPi) lfo -= twoPi;
            float throb = 0.7f + 0.3f * MathF.Sin(lfo);
            float output = (0.35f * MathF.Sin(drone0) + 0.3f * MathF.Sin(drone1) + 0.12f * MathF.Sin(drone2)) * throb * 0.6f;

            // Data beeps: short square blips at computer-ish pitches.
            if (beepLeft > 0)
            {
                beepLeft--;
                beepPhase += twoPi * beepFrequency / sr;
                if (beepPhase > twoPi) beepPhase -= twoPi;
                output += MathF.Sin(beepPhase) > 0 ? 0.09f : -0.09f;
            }
            else
            {
                beepWait--;
                if (beepWait <= 0)
                {
                    beepFrequency = Pitches[(int)(Unit() * (Pitches.Length - 1))];
                    beepLeft = (int)(sr * (0.02f + 0.06f * Unit()));
                    beepWait = (int)(sr * (0.04f + 0.5f * Unit()));
                }
            }

            // Static crackle: held noise samples, which sounds bit-crushed.
            if (noiseLeft > 0)
            {
                noiseLeft--;
                noiseCount++;
                if (noiseCount % 6 == 0) noiseHold = Unit() * 2 - 1;
                output += noiseHold * 0.12f;
            }
            else
            {
                noiseWait--;
                if (noiseWait <= 0)
                {
                    noiseLeft = (int)(sr * (0.02f + 0.08f * Unit()));
                    noiseWait = (int)(sr * (0.3f + 1.5f * Unit()));
                }
            }

            // Hop whoosh: a fast rising sweep with noise, half a second long.
            int requested = Volatile.Read(ref HopsRequested);
            if (hopsPlayed != requested)
            {
                hopsPlayed = requested;
                sweepLeft = (int)(sr * 0.5f);
            }
            if (sweepLeft > 0)
            {
                float total = sr * 0.5f;
                float t = 1 - sweepLeft / total;
                sweepLeft--;
                sweepPhase += twoPi * (150 + 2400 * t * t) / sr;
                if (sweepPhase > twoPi) sweepPhase -= twoPi;
                output += (MathF.Sin(sweepPhase) * 0.18f + (Unit() * 2 - 1) * 0.06f) * (1 - t);
            }

            // Soft clip, then the master level.
            return MathF.Tanh(output) * Gain * Volume;
        }
    }

    private readonly Synth synth = new();
    private readonly object gate = new();
    private Thread? thread;

    public void Start(double volume)
    {
        lock (gate)
        {
            synth.Volume = (float)Math.Clamp(volume, 0, 1);
            synth.Target = 1;
            if (thread != null) return;
            thread = new Thread(Run) { IsBackground = true, Name = "Zero Day sound", Priority = ThreadPriority.AboveNormal };
            thread.Start();
        }
    }

    /// The whoosh for a hop to another app.
    public void Hop() => Interlocked.Increment(ref synth.HopsRequested);

    /// Fades out quickly; the audio thread then closes the device by itself.
    public void Stop() => synth.Target = 0;

    private void Run()
    {
        var format = new Native.WAVEFORMATEX
        {
            wFormatTag = Native.WAVE_FORMAT_PCM,
            nChannels = Channels,
            nSamplesPerSec = SampleRate,
            wBitsPerSample = 16,
            nBlockAlign = Channels * 2,
            nAvgBytesPerSec = SampleRate * Channels * 2,
        };
        if (Native.waveOutOpen(out IntPtr wave, Native.WAVE_MAPPER, ref format, IntPtr.Zero, IntPtr.Zero, Native.CALLBACK_NULL) != 0)
        {
            // No sound device (a remote desktop, a server): Zero Day is silent.
            ActivityLog.Shared.Cat("zero day sound: no audio device");
            lock (gate) thread = null;
            return;
        }

        int headerSize = Marshal.SizeOf<Native.WAVEHDR>();
        int flagsOffset = (int)Marshal.OffsetOf<Native.WAVEHDR>(nameof(Native.WAVEHDR.dwFlags));
        int bytes = BufferFrames * Channels * 2;
        var headers = new IntPtr[BufferCount];
        var data = new IntPtr[BufferCount];
        var queued = new bool[BufferCount];
        var samples = new short[BufferFrames * Channels];
        try
        {
            for (int i = 0; i < BufferCount; i++)
            {
                data[i] = Marshal.AllocHGlobal(bytes);
                headers[i] = Marshal.AllocHGlobal(headerSize);
                Marshal.StructureToPtr(new Native.WAVEHDR { lpData = data[i], dwBufferLength = (uint)bytes }, headers[i], false);
                Native.waveOutPrepareHeader(wave, headers[i], (uint)headerSize);
            }
            while (true)
            {
                for (int i = 0; i < BufferCount; i++)
                {
                    uint flags = (uint)Marshal.ReadInt32(headers[i], flagsOffset);
                    if (queued[i] && (flags & Native.WHDR_DONE) == 0) continue;
                    for (int f = 0; f < BufferFrames; f++)
                    {
                        short s = (short)(Math.Clamp(synth.Next(), -1f, 1f) * short.MaxValue);
                        samples[f * 2] = s;
                        samples[f * 2 + 1] = s;
                    }
                    Marshal.Copy(samples, 0, data[i], samples.Length);
                    Native.waveOutWrite(wave, headers[i], (uint)headerSize);
                    queued[i] = true;
                }
                // Faded out: hand the device back, unless a new Start came in.
                if (synth.Target == 0 && synth.Gain < 0.0005f)
                {
                    lock (gate)
                    {
                        if (synth.Target == 0)
                        {
                            thread = null;
                            break;
                        }
                    }
                }
                Thread.Sleep(10);
            }
        }
        finally
        {
            Native.waveOutReset(wave);
            for (int i = 0; i < BufferCount; i++)
            {
                if (headers[i] != IntPtr.Zero)
                {
                    Native.waveOutUnprepareHeader(wave, headers[i], (uint)headerSize);
                    Marshal.FreeHGlobal(headers[i]);
                }
                if (data[i] != IntPtr.Zero) Marshal.FreeHGlobal(data[i]);
            }
            Native.waveOutClose(wave);
        }
    }

    /// `--zeroday-sound <file.wav> [seconds]` and the self-test: the same
    /// sound written to a 16-bit WAV file, with a hop every two seconds.
    /// Returns the peak and RMS level.
    public static (float peak, float rms) WriteSample(string path, double seconds)
    {
        var synth = new Synth { Target = 1, Gain = 1 };
        int frames = (int)(seconds * SampleRate);
        float peak = 0, sum = 0;
        using var file = new BinaryWriter(File.Create(path));
        int dataBytes = frames * Channels * 2;
        file.Write("RIFF"u8);
        file.Write(36 + dataBytes);
        file.Write("WAVEfmt "u8);
        file.Write(16);
        file.Write((short)1);
        file.Write((short)Channels);
        file.Write(SampleRate);
        file.Write(SampleRate * Channels * 2);
        file.Write((short)(Channels * 2));
        file.Write((short)16);
        file.Write("data"u8);
        file.Write(dataBytes);
        for (int i = 0; i < frames; i++)
        {
            if (i % (SampleRate * 2) == SampleRate) synth.HopsRequested++;
            float s = synth.Next();
            peak = Math.Max(peak, Math.Abs(s));
            sum += s * s;
            short v = (short)(Math.Clamp(s, -1f, 1f) * short.MaxValue);
            file.Write(v);
            file.Write(v);
        }
        return (peak, MathF.Sqrt(sum / Math.Max(1, frames)));
    }
}
