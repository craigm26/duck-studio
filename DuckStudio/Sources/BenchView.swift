import SwiftUI
import RealityKit
import DuckKit
import DuckRender
import StudioKit

/// The bench: a policy, an observation, and the robot it would command.
///
/// WHAT THIS SHOWS, AND WHAT IT DELIBERATELY DOES NOT. Feed the network an
/// observation and it answers with fourteen numbers; `DuckGait` turns those
/// into joint targets and `DuckKinematics` turns those into a robot. That whole
/// chain is exact, and it is what you see.
///
/// What you are NOT seeing is the robot walking. Closing the loop — feeding the
/// resulting pose back in as the next observation — does not work and cannot be
/// made to: the policy locks its gait phase to CONTACT, read through the gyro,
/// projected gravity and joint velocities, and on a bench all three are
/// whatever you last typed. Measured, that loop gives a 25 Hz flip-flop or a
/// slam into the travel stops. So this is a single honest step of the network,
/// held still and inspectable, rather than an animation that would imply
/// physics nobody ran.
struct BenchView: View {
    let entry: PolicyLibrary.Entry

    @State private var policy: DuckPolicy?
    @State private var observation = DuckObservation.zeroed
    @State private var actions: [Float] = Array(repeating: 0, count: DuckModel.policyJointCount)
    @State private var stages: DuckGait.Stages?
    @State private var preset: ObservationPreset = .standing
    @State private var failure: String?
    @State private var tab: Tab = .inputs
    @State private var strip: ZScoreStrip?
    @State private var sensitivity: Sensitivity?
    @State private var orbit = OrbitState()
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var playing: DuckIntentClip?
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = false

    enum Tab: String, CaseIterable, Identifiable {
        case inputs = "Inputs", actions = "Actions", sensitivity = "Sensitivity", play = "Play"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                DuckStage(jointAngles: jointAngles, orbit: $orbit)
                    .background(Color(white: 0.08))
                // What you are looking at, and how to move it. A 3D view with
                // no label is a view where nobody knows whether the duck is
                // posed by the policy or just sitting at home.
                VStack(alignment: .leading, spacing: 2) {
                    Text(poseSource).font(.caption2.weight(.medium))
                    Text("Drag to orbit · pinch to zoom · double-tap to reset")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10)
                .foregroundStyle(.white)
            }
            .frame(maxHeight: 320)

            if let playing {
                TransportBar(clip: playing, playhead: $playhead, isRunning: $isRunning,
                             onStop: { self.playing = nil; self.isRunning = false })
                    .padding(.horizontal).padding(.top, 6)
            }

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            List {
                if let failure {
                    Section { Text(failure).font(.footnote).foregroundStyle(.orange) }
                }
                if let strip {
                    Section { Text(strip.summary).font(.footnote) }
                }

                switch tab {
                case .inputs:
                    Section("Start from") {
                        Picker("Preset", selection: $preset) {
                            ForEach(ObservationPreset.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if let strip {
                        ForEach(ObservationSlot.Block.allCases, id: \.self) { block in
                            Section(block.title) {
                                ForEach(ObservationSlot.slots(in: block)) { slot in
                                    SlotRow(slot: slot,
                                            reading: strip.readings[slot.index],
                                            onChange: { edit(slot: slot.index, to: $0) })
                                }
                            }
                        }
                    }
                case .sensitivity:
                    if let sensitivity {
                        Section {
                            Text("How much each input moves the output, from the exact Jacobian at this observation. A unit here is one training standard deviation, which is what makes the inputs comparable.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("What this policy listens to") {
                            ForEach(sensitivity.ranked(limit: 15)) { column in
                                SensitivityRow(column: column, peak: sensitivity.peak)
                            }
                        }
                        let ignored = sensitivity.ignored()
                        if !ignored.isEmpty {
                            Section("Ignored entirely") {
                                Text(ignored.map(\.slot.label).joined(separator: ", "))
                                    .font(.caption)
                                Text("These inputs move no output at all here. A policy trained without them shows up as a list rather than as a mystery in behaviour.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                case .actions:
                    EmptyView()
                case .play:
                    Section("Recorded intents") {
                        Text("Motions recorded from the trained policies in MuJoCo, because the policy cannot run live on a phone. Playing one shows the robot doing it; it does not re-run the network.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(clips.keys.sorted(), id: \.self) { name in
                            ClipRow(clip: clips[name]!,
                                    isPlaying: playing?.name == name,
                                    onPlay: { start(clips[name]!) })
                        }
                    }
                }

                if let stages, tab == .actions {
                    Section("What the policy commands") {
                        // Walk the POLICY's fourteen slots and ask which joint
                        // each one drives, rather than walking the fifteen
                        // joints and hoping the mouth lines up. DuckModel owns
                        // that mapping in one direction used both ways.
                        ForEach(0..<DuckModel.policyJointCount, id: \.self) { slot in
                            let joint = DuckModel.jointOfPolicySlot(slot)
                            ActionRow(name: DuckModel.jointNames[joint],
                                      action: actions[slot],
                                      target: stages.clamped[joint],
                                      limited: stages.limitedBy.contains(DuckModel.jointNames[joint]))
                        }
                    }
                    if !stages.limitedBy.isEmpty {
                        Section("At the travel stops") {
                            Text(stages.limitedBy.joined(separator: ", "))
                                .font(.footnote.monospaced())
                            Text("These joints were asked for more than they have. The policy is not wrong to ask — the clamp is where the robot's limits enter.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bench")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
            clips = (try? DuckIntentClip.bundled()) ?? [:]
        }
        // 50 Hz is the robot's own control rate, so a clip plays at the speed
        // it was recorded rather than at whatever the display happens to do.
        .onReceive(Timer.publish(every: 1.0 / DuckModel.tickHz, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning, let playing else { return }
            playhead += 1.0 / DuckModel.tickHz
            if playing.pose(at: playhead).hasFinished && !playing.loops { isRunning = false }
        }
        .onChange(of: preset) { _, _ in run() }
    }

    /// The pose to draw. A clip being played wins over the policy's own
    /// answer, because while a recording is running THAT is what you are
    /// looking at and the label says so.
    private var jointAngles: [Double] {
        if let playing { return playing.pose(at: playhead).jointAngles }
        return stages?.clamped ?? ObservationPreset.restingPose
    }

    private var poseSource: String {
        if let playing {
            return "Playing \(playing.name) — \(playing.startsFrom.rawValue) to \(playing.endsIn.rawValue)"
        }
        return stages == nil ? "Home stance" : "Posed by the policy at this observation"
    }

    private func load() {
        guard case .parameters = entry.identity else {
            failure = "This file does not load, so there is nothing to run."
            return
        }
        // The library holds the report, not the bytes — reload from wherever it
        // was persisted rather than keeping megabytes of policy in a view.
        guard let data = PolicyStore.data(for: entry) else {
            failure = "The policy file could not be re-read."
            return
        }
        do {
            policy = try DuckPolicy.load(from: data)
            run()
        } catch {
            failure = "\(error)"
        }
    }

    private func start(_ clip: DuckIntentClip) {
        playing = clip
        playhead = 0
        isRunning = true
        tab = .play
    }

    private func run() {
        guard let policy else { return }
        observation = preset.observation
        recompute()
    }

    /// Move one input and see everything downstream change.
    private func edit(slot: Int, to value: Float) {
        observation = observation.replacing(slot: slot, with: value)
        recompute()
    }

    /// The whole chain, in the order it actually runs: the network, then the
    /// gait that turns its output into joint targets, then the two analyses of
    /// what just happened. The Jacobian is fourteen reverse passes — about
    /// 560 microseconds — so it is comfortably live while a slider moves.
    private func recompute() {
        guard let policy else { return }
        actions = policy.infer(observation)
        stages = DuckGait.stages(action: actions, previousTargets: nil)
        strip = ZScoreStrip(observation: observation, policy: policy)
        sensitivity = Sensitivity(policy: policy, observation: observation)
    }
}

/// One joint's row: what the network asked for, and what the robot will do.
private struct ActionRow: View {
    let name: String
    let action: Float
    let target: Double
    let limited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption)
                if limited {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                Text(String(format: "%+.3f rad", target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(limited ? .orange : .secondary)
            }
            // Raw against clamped, drawn together: the gap between them IS the
            // travel limit, and a bar that showed only the final number would
            // hide every time the robot could not do what it was told.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(limited ? Color.orange : Color.accentColor)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
    }

    /// The raw action, not the target. 1.5 rad is a generous full scale — the
    /// policies rarely exceed it, and a bar normalised to whatever the largest
    /// value happens to be would rescale every time the observation changed.
    private var fraction: CGFloat {
        CGFloat(min(abs(Double(action)) / 1.5, 1))
    }
}

/// One recorded intent in the list: what it is, and where it leaves the robot.
private struct ClipRow: View {
    let clip: DuckIntentClip
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "waveform" : "play.circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.name).font(.subheadline)
                    // The measured start and end posture. step_up says
                    // "standing to toppled" because that is what was recorded —
                    // it falls over against a real stair.
                    Text("\(clip.startsFrom.rawValue) → \(clip.endsIn.rawValue) · "
                         + String(format: "%.1fs", clip.duration))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if clip.credit != nil {
                    Text("shared").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Play, pause, scrub. A recording is a thing you watch, and watching needs a
/// way to stop and go back to the bit that looked wrong.
private struct TransportBar: View {
    let clip: DuckIntentClip
    @Binding var playhead: TimeInterval
    @Binding var isRunning: Bool
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { isRunning.toggle() } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
            }
            Button { playhead = 0; isRunning = true } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            Slider(value: $playhead, in: 0...max(clip.duration, 0.01)) { editing in
                // Scrubbing pauses. Otherwise the playhead fights the thumb and
                // the duck twitches between where you dragged and where the
                // timer has got to.
                if editing { isRunning = false }
            }
            Text(String(format: "%.2fs", playhead))
                .font(.caption2.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
            Button(action: onStop) { Image(systemName: "xmark.circle.fill") }
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }
}
