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
    var store: SceneStore?

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
    /// A place to stand the pose in. A network has no world of its own — but
    /// looking at a crouch beside a step is how you find out whether the crouch
    /// clears it, and a bench floating in a void cannot answer that.
    @State private var scene: DuckScene?

    enum Tab: String, CaseIterable, Identifiable {
        case inputs = "Inputs", actions = "Actions", sensitivity = "Sensitivity"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                DuckStage(pose: benchPose,
                          environment: scene?.environment ?? .bareFloor,
                          orbit: $orbit)
                // What you are looking at, and how to move it. A 3D view with
                // no label is a view where nobody knows whether the duck is
                // posed by the policy or just sitting at home.
                VStack(alignment: .leading, spacing: 2) {
                    Text(poseSource).font(.caption2.weight(.medium))
                    StageLegend(pose: benchPose,
                                environment: scene?.environment ?? .bareFloor,
                                orbit: $orbit)
                }
                .padding(.bottom, 2)
                .foregroundStyle(.white)
            }
            .frame(maxHeight: 320)

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            List {
                if let failure {
                    Section { Text(failure).font(.footnote).foregroundStyle(.orange) }
                }
                if let strip, tab != .actions {
                    Section { Text(strip.summary).font(.footnote) }
                }

                switch tab {
                case .inputs:
                    if let store, !store.scenes.isEmpty {
                        Section {
                            Picker("Stand it in", selection: $scene) {
                                Text("Bare floor").tag(DuckScene?.none)
                                ForEach(store.scenes) { s in
                                    Text(s.name).tag(DuckScene?.some(s))
                                }
                            }
                            .pickerStyle(.menu)
                        } footer: {
                            Text("A network has no world of its own. Standing the pose beside a step is how you see whether it clears one.")
                        }
                    }
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
        .onAppear(perform: load)
        .onChange(of: preset) { _, _ in run() }
    }

    /// The pose to draw: the policy's clamped targets, or the home stance
    /// while nothing has run. Nothing PLAYS here — a network has no time axis,
    /// and recordings live in the Intents tab.
    private var jointAngles: [Double] {
        stages?.clamped ?? ObservationPreset.restingPose
    }

    /// The bench has no root of its own — a network has no position — so the
    /// robot stands where every clip starts, wearing the pose the policy just
    /// asked for.
    private var benchPose: StagePose {
        StagePose(jointAngles: jointAngles, root: StagePose.home.root)
    }

    private var poseSource: String {
        stages == nil ? "Home stance" : "Posed by the policy at this observation"
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
        // AT THE SCALE ROBOTD WOULD RUN THIS NETWORK. The scales are per
        // network, not global: roulade, ground-pick and the sit/rise cycle run
        // at 1.0 and only walking and the kicks are de-rated to 0.9 — so a
        // bench that applied the walking scale to a roulade policy showed
        // targets 10% short of what the robot would actually be sent.
        let kind = DuckPolicyKind.allCases.first { $0.fileName == entry.displayName
                                                || "BEST_" + $0.fileName == entry.displayName }
        stages = DuckGait.stages(action: actions, previousTargets: nil, kind: kind ?? .walk)
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

/// One observation input: what it is, what it is set to, and how far out of
/// distribution that is.
private struct SlotRow: View {
    let slot: ObservationSlot
    let reading: ZScoreStrip.Reading
    let onChange: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(slot.label).font(.caption).lineLimit(1)
                Spacer()
                if slot.isNeverEmitted {
                    Text("unused").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(String(format: "%+.3f", reading.value))
                    .font(.caption.monospacedDigit())
                Text(slot.unit.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Slider(value: Binding(get: { Double(reading.value) },
                                      set: { onChange(Float($0)) }),
                       in: slot.lower...max(slot.upper, slot.lower + 1e-6))
                // The z-score sits beside the slider rather than in a separate
                // strip: the number only means anything next to the value that
                // produced it.
                Text(String(format: "%+.1fσ", reading.z))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(reading.isOutlier ? .orange : .secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

/// One input's influence, as a bar against the strongest input at this
/// observation — not against whatever the largest value happens to be, so the
/// chart does not rescale every time a slider moves.
private struct SensitivityRow: View {
    let column: Sensitivity.Column
    let peak: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(column.slot.label).font(.caption).lineLimit(1)
                Spacer()
                Text(column.strongestJoint).font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(peak > 0 ? column.norm / peak : 0))
                }
            }
            .frame(height: 5)
        }
    }
}
