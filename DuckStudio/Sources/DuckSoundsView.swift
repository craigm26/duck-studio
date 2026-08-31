import SwiftUI
import DuckKit
import StudioKit

/// The seven duck calls, folded in from the app they used to be.
///
/// WHY IT IS A SCREEN AND NOT AN APP. Duck Sounds had its own README, its own
/// gates and its own bundle identifier, and needed a shell, an icon, a privacy
/// label and a review before it could show anybody a duck. Everything it
/// actually does — the voice, the choreography, the model — was already in
/// DuckKit and tested on a Pi with no phone in the room. It is a screen here for
/// the same reason Duck Soccer is.
///
/// A CALL IS A VOICE AND A MOVEMENT, PLAYED TOGETHER. Neither half is decoration
/// for the other: `inquire` is a rising pitch AND a head tilt, and the README's
/// own line for it is that the rising pitch alone reads as a squeak. So the
/// stage and the speaker run off one clock — the same elapsed time samples
/// `DuckPerformance` and drives the audio that was scheduled when the call
/// started.
///
/// HELD IS NOT LONG, AND ONLY ONE CALL IS HELD. `coo` is the longest thing here
/// and still fire-and-forget; `wheee` is the ride, and it is the one that keeps
/// going while a finger is down, decaying through its release when the holds
/// stop arriving. That is DuckKit's distinction — `DuckSound.isHeld` — and it is
/// the robot's own hold semantics rather than a UI convention, so the button
/// behaviour follows it rather than deciding it.
struct DuckSoundsView: View {
    @State private var playing: DuckSound?
    @State private var part: DuckSound.Part = .whole
    @State private var began = Date()
    @State private var holding = false
    @State private var orbit = OrbitState()
    @State private var player = DuckVoicePlayer()
    /// Both recordings, because the choice is per-moment and not per-call.
    /// `SoundStaging.gait` reads the twist through the runtime's own
    /// threshold, and `wheee` crosses it partway through its own start — so a
    /// screen holding one clip would have to ignore that and ride a standing
    /// recording through a ride.
    @State private var gaits: [DuckTrajectory.Clip: DuckTrajectory] = [:]
    @State private var unavailable: String?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation) { timeline in
                DuckStage(pose: stance(at: timeline.date),
                          environment: .bareFloor,
                          orbit: $orbit)
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .navigationTitle("Duck sounds")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .onDisappear { player.stop() }
    }

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let unavailable {
                Text(unavailable).font(.footnote).foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(DuckSound.allCases, id: \.self) { sound in
                    button(for: sound)
                }
            }
            .padding(.horizontal)

            Text(SoundStaging.caveat)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal).padding(.bottom, 8)
        }
    }

    private func button(for sound: DuckSound) -> some View {
        let isActive = playing == sound
        return VStack(spacing: 2) {
            Text(sound.tag).font(.subheadline.weight(.semibold))
            // THE HELD ONE SAYS SO ON ITS FACE. A button that behaves
            // differently from the six beside it has to look different before
            // it is pressed, not after.
            if sound.isHeld {
                Text("hold").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(isActive ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .gesture(gesture(for: sound))
        .disabled(gaits.isEmpty)
        .accessibilityLabel(Text(sound.isHeld ? "\(sound.tag), press and hold" : sound.tag))
    }

    private func gesture(for sound: DuckSound) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard playing != sound else { return }
                start(sound)
            }
            .onEnded { _ in
                guard sound.isHeld, holding else { return }
                letGo(sound)
            }
    }

    // MARK: - one clock for both halves

    private func stance(at now: Date) -> StagePose {
        guard let playing, !gaits.isEmpty else { return StagePose.home }
        let elapsed = now.timeIntervalSince(began)
        let timeline = DuckPerformance.timeline(for: playing, part: part)

        // A held call sits in its loop until the finger lifts, so the loop's
        // own clock wraps rather than running off the end and holding a pose.
        let at = part == .loop && holding
            ? elapsed.truncatingRemainder(dividingBy: max(timeline.duration, 0.001))
            : elapsed
        let pose = timeline.pose(at: at)

        // The legs ride the recording chosen by the runtime's own threshold,
        // sampled on the same clock so a walk does not stutter. The choice is
        // made per frame: `wheee` crosses the threshold partway through its
        // own attack, which is the moment the walking policy takes over on the
        // robot too.
        let wanted = SoundStaging.gait(for: pose)
        guard let clip = gaits[wanted] ?? gaits[.stand] else { return StagePose.home }
        return SoundStaging.stance(pose, legs: clip.pose(at: elapsed))
    }

    private func start(_ sound: DuckSound) {
        playing = sound
        began = Date()
        holding = sound.isHeld
        part = sound.isHeld ? .start : .whole
        player.play(sound, part: part)

        if sound.isHeld {
            // The attack cannot be cut short — the duck has already drawn
            // breath — so the loop begins when the start is done, not when the
            // finger happens to still be down.
            let attack = DuckPerformance.timeline(for: sound, part: .start).duration
            DispatchQueue.main.asyncAfter(deadline: .now() + attack) {
                guard playing == sound, holding else { return }
                part = .loop
                began = Date()
                player.queueLoop(sound)
            }
        } else {
            let whole = DuckPerformance.timeline(for: sound, part: .whole).duration
            DispatchQueue.main.asyncAfter(deadline: .now() + whole) {
                if playing == sound { playing = nil }
            }
        }
    }

    private func letGo(_ sound: DuckSound) {
        holding = false
        part = .end
        began = Date()
        player.release(sound)
        let release = DuckPerformance.timeline(for: sound, part: .end).duration
        DispatchQueue.main.asyncAfter(deadline: .now() + release) {
            if playing == sound { playing = nil }
        }
    }

    /// Both gaits up front. A missing standing clip disables the buttons and
    /// says so rather than drawing a duck that never moves and letting it look
    /// broken; a missing WALKING clip is survivable — six of the seven never
    /// ask for it — so the ride falls back to standing and the screen says
    /// what was lost instead of pretending the ride happened.
    private func load() {
        gaits = [:]
        if let stand = try? DuckTrajectory.bundled(.stand) { gaits[.stand] = stand }
        if let walk = try? DuckTrajectory.bundled(.walk) { gaits[.walk] = walk }

        if gaits[.stand] == nil {
            unavailable = "The recorded standing gait did not load, so there is nothing to draw "
                        + "a duck with. The calls are disabled rather than silent."
        } else if gaits[.walk] == nil {
            unavailable = "The recorded walking gait did not load. The six standing calls are "
                        + "unaffected; wheee will make its noise and move its head, but it will "
                        + "not travel, and that is a missing recording rather than the ride."
        }
    }
}
