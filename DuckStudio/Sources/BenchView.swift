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
    /// OBSERVED, AND NOT OPTIONAL. Resolving the scene by id is only half the
    /// fix: without a property wrapper this view never subscribes to the
    /// store's `objectWillChange`, so whether the resolution is redrawn is left
    /// to parent invalidation that nothing here specifies. And the optionality
    /// bought nothing — the single construction site (PolicyListView) has
    /// always passed a real store. A default that silently removes a feature is
    /// a default that will be taken.
    @ObservedObject var store: SceneStore

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
    /// BY IDENTITY, NEVER BY VALUE. Holding the `DuckScene` itself made this
    /// screen go stale the instant anybody edited that scene — including a
    /// rename, which is just a modification. `DuckScene` is `Hashable`, the
    /// Picker below tagged rows by the whole value, so one edited character
    /// made the held copy unequal to every tag: the Picker then matched
    /// nothing and the stage kept drawing the pre-edit geometry, with no way
    /// to tell from the screen that it had come adrift. `IntentAuthorView`
    /// already does it this way and does not have the bug.
    @State private var sceneID: UUID?

    /// Looked up fresh every time it is drawn, which is the whole point.
    private var scene: DuckScene? {
        guard let sceneID else { return nil }
        return store.scenes.first { $0.id == sceneID }
    }

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
                // THE SCENE WAS PICKED AND IS NOW GONE. Without this the stage
                // silently drops to a bare floor and the pose is judged against
                // a world nobody chose — the same class of silence the stale
                // copy caused, one step later in its life.
                if sceneID != nil, scene == nil {
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Label(StageCaption.sceneDeleted(.stoodIn),
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                            Spacer(minLength: 8)
                            Button("Bare floor") { sceneID = nil }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                if let strip, tab != .actions {
                    Section { Text(strip.summary).font(.footnote) }
                }

                switch tab {
                case .inputs:
                    if !store.scenes.isEmpty {
                        Section {
                            Picker("Stand it in", selection: $sceneID) {
                                Text("Bare floor").tag(UUID?.none)
                                ForEach(store.scenes) { s in
                                    Text(s.name).tag(UUID?.some(s.id))
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

    /// The words this screen already uses for a clamped joint — the header over
    /// the list of them, three sections up. THE ICON AND THE ORANGE ARE THE
    /// ONLY PLACE THIS ROW SAYS "clamped", and neither is a word, so the same
    /// heading is what it says out loud rather than a second wording of the
    /// same fact.
    private static let atTheStops = "At the travel stops"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption)
                if limited {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2).foregroundStyle(.orange)
                        .accessibilityLabel(Text(Self.atTheStops))
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
        // ONE ELEMENT PER JOINT. Nothing in this row can be acted on, so the
        // three pieces of it — the joint, whether it is clamped, the target it
        // was given — are one thing to hear rather than three to swipe past.
        // The bar says nothing out loud: it draws the same number the text
        // already carries.
        .accessibilityElement(children: .combine)
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

    /// The printed number, the printed unit, the printed z-score and the
    /// printed "unused" — each written ONCE and read twice, by the row you look
    /// at and the row you hear.
    ///
    /// A SECOND FORMAT FOR THE SAME QUANTITY IS A SECOND SOURCE OF TRUTH. A
    /// slider that showed "+0.132" and said "0.13 radians" would be two
    /// different answers about the same input, and the spoken one is the answer
    /// nobody can check by looking at the screen.
    private var printedValue: String { String(format: "%+.3f", reading.value) }
    private var printedUnit: String { slot.unit.rawValue }
    private var printedSigma: String { String(format: "%+.1fσ", reading.z) }
    private var printedUnused: String? { slot.isNeverEmitted ? "unused" : nil }

    /// Everything the row shows, in the order it shows it, for the slider to
    /// speak as its value.
    private var spokenValue: String {
        let parts: [String?] = [printedUnused, printedValue,
                                printedUnit.isEmpty ? nil : printedUnit, printedSigma]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(slot.label).font(.caption).lineLimit(1)
                Spacer()
                if printedUnused != nil {
                    // Text("literal"), NOT Text(someString). A String-typed
                    // argument picks the verbatim initialiser and ships English
                    // whatever the catalogue says; the literal keeps its
                    // LocalizedStringKey path. `printedUnused` stays a String
                    // because the SPOKEN value concatenates it.
                    Text("unused").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(printedValue)
                    .font(.caption.monospacedDigit())
                Text(printedUnit).font(.caption2).foregroundStyle(.secondary)
            }
            // HIDDEN, NOT DELETED — see the slider below, which says all of it.
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                Slider(value: Binding(get: { Double(reading.value) },
                                      set: { onChange(Float($0)) }),
                       in: slot.lower...max(slot.upper, slot.lower + 1e-6))
                    // THE SLIDER IS THE ROW, AS FAR AS VOICEOVER IS CONCERNED.
                    // A Slider is its own accessibility element and carries the
                    // .adjustable trait, so the name in the HStack above is a
                    // SIBLING and never reaches it: unlabelled, all sixty-one
                    // of these announce "52 percent, adjustable" and nothing
                    // else — gyro X and left knee velocity indistinguishable,
                    // on the screen where typing the wrong number into the
                    // wrong input is the whole hazard.
                    //
                    // LABELLED, NOT COMBINED, AND THAT IS THE DECISION.
                    // Folding the row into one element with
                    // `accessibilityElement(children: .combine)` would read the
                    // same three things — and fold the adjustable trait away
                    // with them, leaving sixty-one inputs that can be heard and
                    // not moved. Editing an input IS this screen. So the slider
                    // keeps the element, the texts around it are hidden into
                    // its value, and swipe-up still moves the number.
                    .accessibilityLabel(Text(slot.label))
                    .accessibilityValue(Text(spokenValue))
                // The z-score sits beside the slider rather than in a separate
                // strip: the number only means anything next to the value that
                // produced it.
                Text(printedSigma)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(reading.isOutlier ? .orange : .secondary)
                    .frame(width: 52, alignment: .trailing)
                    .accessibilityHidden(true)
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
        // The input and the joint it moves most are one fact, and the bar is
        // that fact drawn again — so this is one element, and the bar is silent.
        .accessibilityElement(children: .combine)
    }
}
