import Foundation
import AVFoundation
import DuckKit

/// Playing the duck's voice, which this phone synthesises rather than plays back.
///
/// THERE ARE NO AUDIO FILES IN THIS APP. `DuckVoice.render` builds the samples
/// from a harmonic stack and an envelope, seeded, so the same seed gives the
/// same noise on every device and a test can assert what a duck sounds like.
/// That means this class's whole job is to get a `[Float]` to the speaker —
/// there is nothing to decode, load or cache from disk.
///
/// SCHEDULED, NOT RESTARTED. A held call is start → loop → loop → … → end, and
/// the loop is written so its last instant matches its first. Restarting a
/// player for each repeat puts a gap at every seam and the ride clicks once per
/// half second. So loops are scheduled ahead on the same node and the engine
/// runs them back to back; `AVAudioPlayerNode` is built for exactly this.
///
/// IT LEAVES THE SESSION ALONE ON THE WAY OUT. This app records nothing and has
/// no reason to keep an audio session active — a duck that honks once should
/// not stop somebody's music for the rest of the afternoon, so the category is
/// `.ambient`, which mixes rather than interrupts.
@MainActor
final class DuckVoicePlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var running = false
    /// Seeds differ per utterance so two presses are not identical, the way
    /// `greet`'s coin flip needs them not to be.
    private var seed: UInt64 = 0x5EED

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: DuckVoice.sampleRate, channels: 1)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Start a one-shot, or the attack of a held call.
    func play(_ sound: DuckSound, part: DuckSound.Part) {
        guard start() else { return }
        seed &+= 0x9E37_79B9_7F4A_7C15
        schedule(DuckVoice.render(sound, part: part, seed: seed))
        node.play()
    }

    /// Queue another turn of a held call's loop behind whatever is playing.
    func queueLoop(_ sound: DuckSound) {
        guard running, sound.isHeld else { return }
        seed &+= 0x9E37_79B9_7F4A_7C15
        schedule(DuckVoice.render(sound, part: .loop, seed: seed))
    }

    /// Let go: play the release and stop taking loops.
    func release(_ sound: DuckSound) {
        guard running, sound.isHeld else { return }
        seed &+= 0x9E37_79B9_7F4A_7C15
        schedule(DuckVoice.render(sound, part: .end, seed: seed))
    }

    /// Cut everything now — used when the screen goes away, not between calls.
    func stop() {
        node.stop()
        engine.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start() -> Bool {
        if running { return true }
        do {
            // .ambient mixes with whatever else is playing and respects the
            // silent switch. A duck call is not a phone call.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            running = true
        } catch {
            running = false
        }
        return running
    }

    private func schedule(_ rendering: DuckVoice.Rendering) {
        guard !rendering.samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(rendering.samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        rendering.samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: source.count)
        }
        buffer.frameLength = AVAudioFrameCount(rendering.samples.count)
        node.scheduleBuffer(buffer, completionHandler: nil)
    }
}
