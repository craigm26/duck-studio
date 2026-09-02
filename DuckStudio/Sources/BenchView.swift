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
///
/// THE PROVENANCE COLOURS DO THE WHOLE OF THE EXPLAINING HERE. Every number on
/// this screen is one of two things and they are easy to confuse: what somebody
/// TYPED into an input, and what the network then DID with it. So the sliders'
/// readings and the action bars are `Theme.asked` — yellow, what somebody asked
/// for — and the sensitivity bars, which come out of the exact Jacobian, are
/// `Theme.measured`. A joint the robot's travel stops refuse is `Theme.refused`,
/// and it says "At the travel stops" in words beside the colour, because the
/// clamp is the one thing on this screen a person acts on.
///
/// AND THE FIGURES ARE TELEMETRY ROWS BECAUSE THEY ALL CHANGE. Fourteen joint
/// targets and sixty-one inputs move every time a slider moves; tabular figures
/// are what stop the whole list from shuffling sideways while a thumb is on one
/// of them, and the stacked reflow is what stops the number — always on the
/// right, always the one that loses — from being the half that is truncated at
/// an accessibility text size.
struct BenchView: View {
    let entry: PolicyLibrary.Entry
    /// For the policy's stored manifest — the only place the action scale is
    /// KNOWN rather than inferred from a file name. See `probe()`.
    @ObservedObject var model: LibraryModel
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

    /// So the viewport can stop clipping at accessibility sizes — see `stage`.
    @Environment(\.dynamicTypeSize) private var typeSize

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
            stage

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.spacing(.standard))
            .padding(.top, Theme.spacing(.tight))
            .padding(.bottom, Theme.spacing(.tight))

            list
        }
        .background(Theme.backgroundPrimary)
        // "Bench" was one tap from a screen called "Benches" and meant
        // something else entirely — this probes a policy's own arithmetic on
        // this phone. The row that pushes it already says these words.
        .navigationTitle("Probe this network")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: preset) { _, _ in run() }
    }

    // MARK: - the duck

    /// The viewport: the 3D stage, with the legend standing on it.
    ///
    /// A CARD, AT THE GROUP RADIUS, WITH A HAIRLINE EDGE — the same viewport
    /// the Drive screen draws, so the two 3D views in this app are the same
    /// object seen twice rather than two rectangles of different sizes.
    ///
    /// NOT CAPPED AT ACCESSIBILITY SIZES. A fixed 320-point viewport clipped
    /// the legend's own reflow at large text, which hides the readings from the
    /// people who enlarged them in order to read them. The duck shrinks to make
    /// room; the words do not disappear.
    ///
    /// THE LEGEND STAYS WHITE, AND THAT IS THE ONE DELIBERATE LITERAL ON THIS
    /// SCREEN. `StageLegend` lives in `DuckStage.swift` and sets its own
    /// `.foregroundStyle(.white)`, because it is an annotation ON the render
    /// rather than chrome beside it — the same class of thing as the floor
    /// material and the duck's bill. Putting it on a `surfacePrimary` panel the
    /// way the Drive screen's readout sits would make white text on cream in
    /// light mode; colouring only the line above it would put two treatments in
    /// one caption. Both halves are left as they were, together.
    private var stage: some View {
        ZStack(alignment: .bottomLeading) {
            DuckStage(pose: benchPose,
                      environment: scene?.environment ?? .bareFloor,
                      orbit: $orbit)
            // What you are looking at, and how to move it. A 3D view with
            // no label is a view where nobody knows whether the duck is
            // posed by the policy or just sitting at home.
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(poseSource).font(.caption2.weight(.medium))
                StageLegend(pose: benchPose,
                            environment: scene?.environment ?? .bareFloor,
                            orbit: $orbit)
            }
            // ON A PLATE, THE WAY DriveView's HUD IS. It floated in white over
            // whatever the scene drew that frame — 1.55:1 against the cream
            // shell, 8.6:1 against the floor, depending on the orbit — with a
            // comment blaming StageLegend's own white, which StageLegend no
            // longer has. Tokened text on a translucent charcoal plate reads
            // over every material the stage can put behind it.
            .padding(Theme.spacing(.tight))
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.backgroundPrimary.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: Theme.radius(.control)))
            .padding(Theme.spacing(.tight))
        }
        .frame(maxHeight: typeSize.isAccessibilitySize ? nil : BenchMetric.viewportHeight)
        .clipShape(viewport)
        .overlay(viewport.strokeBorder(Theme.separator,
                                       lineWidth: BenchMetric.hairlineStroke))
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.top, Theme.spacing(.tight))
    }

    private var viewport: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(BenchMetric.viewport),
                         style: .continuous)
    }

    // MARK: - the readings

    private var list: some View {
        List {
            if let failure {
                Section {
                    Text(failure).font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            // THE SCENE WAS PICKED AND IS NOW GONE. Without this the stage
            // silently drops to a bare floor and the pose is judged against
            // a world nobody chose — the same class of silence the stale
            // copy caused, one step later in its life.
            if sceneID != nil, scene == nil {
                Section {
                    sceneIsGone
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            if let strip, tab != .actions {
                Section {
                    Text(strip.summary).font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            switch tab {
            case .inputs:
                inputs
            case .sensitivity:
                sensitivityTab
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
                .listRowBackground(Theme.surfacePrimary)

                if !stages.limitedBy.isEmpty {
                    Section("At the travel stops") {
                        // THE NAMES, IN THE REFUSAL COLOUR AND IN SF. A joint
                        // name is a name — it does not change while you look at
                        // it — and the design system reads tabular figures as a
                        // claim that something is about to move. Which names
                        // are in the list changes; the names do not.
                        Text(stages.limitedBy.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(Theme.refused)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("These joints were asked for more than they have. The policy is not wrong to ask — the clamp is where the robot's limits enter.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
        // GREY, and every row keeps a real `surfacePrimary` card under it —
        // which is what lets the provenance colours above be set at all.
        // `Palette` documents `backgroundSecondary` as a ground for surfaces
        // rather than for words: the inks land between 4.17:1 and 4.27:1 on it,
        // short of the 4.5:1 body text owes.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
    }

    /// The scene this pose was being judged against has been deleted.
    ///
    /// THE SENTENCE IS `StageCaption`'s AND THE WAY OUT IS A REAL CONTROL. It
    /// was a `.bordered` button at `.small`, which is a target under the HIG's
    /// forty-four points on a row that only appears when something has already
    /// gone wrong. The padding comes off the spacing scale, so this file never
    /// writes that floor down as a number.
    private var sceneIsGone: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Label(StageCaption.sceneDeleted(.stoodIn),
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Button("Bare floor") { sceneID = nil }
                .buttonStyle(.primaryAction)
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    @ViewBuilder private var inputs: some View {
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
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        Section("Start from") {
            Picker("Preset", selection: $preset) {
                ForEach(ObservationPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Text(preset.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
        if let strip {
            ForEach(ObservationSlot.Block.allCases, id: \.self) { block in
                Section(block.title) {
                    ForEach(ObservationSlot.slots(in: block)) { slot in
                        SlotRow(slot: slot,
                                reading: strip.readings[slot.index],
                                onChange: { edit(slot: slot.index, to: $0) })
                    }
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
    }

    @ViewBuilder private var sensitivityTab: some View {
        if let sensitivity {
            Section {
                Text("How much each input moves the output, from the exact Jacobian at this observation. A unit here is one training standard deviation, which is what makes the inputs comparable.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
            Section("What this policy listens to") {
                ForEach(sensitivity.ranked(limit: 15)) { column in
                    SensitivityRow(column: column, peak: sensitivity.peak)
                }
            }
            .listRowBackground(Theme.surfacePrimary)
            let ignored = sensitivity.ignored()
            if !ignored.isEmpty {
                Section("Ignored entirely") {
                    Text(ignored.map(\.slot.label).joined(separator: ", "))
                        .font(.caption).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("These inputs move no output at all here. A policy trained without them shows up as a list rather than as a mystery in behaviour.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
    }

    /// The pose to draw: the policy's clamped targets, or the home stance
    /// while nothing has run. Nothing PLAYS here — a network has no time axis,
    /// and recordings live in Studio → Motions.
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
        // THE `BEST_` FALLBACK IS FOR FILES, NOT FOR US ANY MORE. This app used
        // to vendor four of the nine under upstream's training-run names, so
        // matching had to try both spellings. The bundle now uses Pollen's role
        // names throughout — but somebody who imported `BEST_alpha_stand.onnx`
        // from the older prototype still has that file on their phone, and it
        // is the same network. Dropping the alternative would silently de-rate
        // their policy to the walking action scale.
        let kind = DuckPolicyKind.allCases.first { $0.fileName == entry.displayName
                                                || "BEST_" + $0.fileName == entry.displayName }
        // THE MANIFEST BEATS THE FILE NAME, when the policy came with one. The
        // match above can only ever recognise the nine Pollen ship; a policy
        // somebody trained themselves matches nothing and falls to `.walk`'s
        // 0.9 however wrong that is for it. A published policy states its own
        // `action_scale` — happy-hop's is 1.0 — and stating it is exactly what
        // this app should stop guessing at.
        stages = DuckGait.stages(action: actions, previousTargets: nil,
                                 kind: kind ?? .walk,
                                 scale: model.declaredScale(for: entry))
        strip = ZScoreStrip(observation: observation, policy: policy)
        sensitivity = Sensitivity(policy: policy, observation: observation)
    }
}

// MARK: - the numbers this screen writes down for itself

/// Dimensions that are layout decisions rather than facts. Nothing here is a
/// colour or a contrast — those are facts, and they live in `Palette` where a
/// test can run the formula over them.
private enum BenchMetric {
    /// The viewport card, and therefore the radius its contents would take one
    /// step down if any of them needed one.
    static let viewport = Palette.Radius.group

    /// How much of the screen the duck is allowed before the readings start to
    /// lose their room. Below it the duck is a thumbnail of a duck.
    static let viewportHeight: CGFloat = 320

    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke = DesignMetric.hairlineStroke

    /// The action bar and the sensitivity bar. Four and five points — the bars
    /// are marks under a number, not a chart, and anything thicker starts to
    /// read as the row's main content.
    static let actionBarHeight: CGFloat = 6
    static let sensitivityBarHeight: CGFloat = 5

    /// The column the z-score is ALIGNED TO beside a slider. A floor, not a
    /// width: fifty-two points holds a reading like "-12.3σ" at the default text
    /// size and lines every slider up on the same edge, and anything that needs
    /// more takes more.
    ///
    /// IT WAS `.frame(width:)`, AND THAT CLIPPED BEFORE THE ACCESSIBILITY SIZES
    /// EVEN BEGAN. The comment beside it said the reservation "becomes a clip"
    /// only past those sizes, and the branch in `SlotRow` was written to that
    /// belief — but `caption2` is eleven points at the default and about fifteen
    /// at xxxLarge, which is still an ordinary size that no
    /// `isAccessibilitySize` check is true at. A six-glyph reading that fits in
    /// fifty-two points at eleven wants nearer seventy at fifteen, so the tail
    /// was being cut off a whole size class before anything was watching for it.
    /// The half that goes first is the σ and then the digits before it, which is
    /// to say the row stops being able to tell you the input is out of
    /// distribution while still looking like it is telling you something.
    ///
    /// As a minimum it keeps the alignment for every reading that fits and
    /// borrows from the slider for the ones that do not — the slider is elastic
    /// and the number is not, so the elastic thing is the one that gives way.
    static let sigmaWidth: CGFloat = 52

    /// The raw action's full scale. 1.5 rad is generous — the policies rarely
    /// exceed it — and a bar normalised to whatever the largest value happens
    /// to be would rescale every time the observation changed.
    static let actionFullScale = 1.5
}

/// One joint's row: what the network asked for, and what the robot will do.
///
/// THE CLAMP IS SAID IN A WORD, NOT ONLY IN A COLOUR. It used to be an orange
/// glyph with an accessibility label on it and an orange number beside it —
/// which is the whole fact carried in a hue, on the one row of this screen a
/// person acts on. The words are the same words the section three below uses,
/// so the row and the summary cannot drift into two different names for one
/// thing.
private struct ActionRow: View {
    let name: String
    let action: Float
    let target: Double
    let limited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            // A TARGET IN RADIANS IS TELEMETRY BY EVERY TEST THE DESIGN SYSTEM
            // APPLIES: it changes on every slider move, it is read against the
            // thirteen rows around it, and at an accessibility size it is the
            // half of the pair that used to be truncated.
            TelemetryRow(label: name,
                         value: String(format: "%+.3f", target), unit: "rad")
            if limited {
                // THE LITERAL, NOT A `static let` HOLDING IT. This is the same
                // wording as the section header three below, and it is written
                // out twice on purpose: `Label(String, systemImage:)` picks the
                // verbatim initialiser and would ship English whatever a
                // catalogue said, while the literal keeps its
                // `LocalizedStringKey` path and keys the same entry the header
                // does. `SlotRow`'s "unused" makes the same argument.
                Label("At the travel stops",
                      systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption2).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Raw against clamped, drawn together: the gap between them IS the
            // travel limit, and a bar that showed only the final number would
            // hide every time the robot could not do what it was told.
            //
            // IN `asked`, WHICH IS WHAT THIS BAR DRAWS. It is the RAW action —
            // the number the network requested before the gait scaled it and
            // before the stops clamped it — and yellow is this app's colour for
            // a request. Where the stops refused it, the bar takes the refusal
            // colour, which is the same claim the word above it makes.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.separator)
                    Capsule().fill(limited ? Theme.refused : Theme.asked)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: BenchMetric.actionBarHeight)
        }
        // ONE ELEMENT PER JOINT. Nothing in this row can be acted on, so the
        // three pieces of it — the joint, whether it is clamped, the target it
        // was given — are one thing to hear rather than three to swipe past.
        // The bar says nothing out loud: it draws a number the row already
        // carries.
        .accessibilityElement(children: .combine)
    }

    /// The raw action, not the target.
    private var fraction: CGFloat {
        CGFloat(min(abs(Double(action)) / BenchMetric.actionFullScale, 1))
    }
}

/// One observation input: what it is, what it is set to, and how far out of
/// distribution that is.
///
/// THE SLIDER IS THE ROW AND THE ROW REFLOWS. Sixty-one of these sit under one
/// another, each with a name, a reading, a unit and a z-score, and at an
/// accessibility text size that is four things fighting for one line. The pair
/// splits the way `TelemetryRow` splits: stacked, each gets the whole width and
/// nothing is dropped — which matters most here, because the number that would
/// be dropped is the one that says the input is out of distribution.
private struct SlotRow: View {
    let slot: ObservationSlot
    let reading: ZScoreStrip.Reading
    let onChange: (Float) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

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
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            heading
                // HIDDEN, NOT DELETED — see the slider below, which says all of
                // it.
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                slider
                sigma.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Theme.spacing(.tight)) {
                    slider
                    // A COLUMN THAT CANNOT CUT THE NUMBER DOWN TO FIT IT.
                    // `fixedSize` is what makes the minimum mean anything: on
                    // its own, a minimum width still lets the HStack squeeze a
                    // `Text` below its ideal width and truncate, because a
                    // `Text` will accept a narrower proposal and a `Slider`
                    // will not. Fixed, the reading always asks for exactly the
                    // room it needs and the slider absorbs the difference; the
                    // minimum then does the only job left, which is keeping the
                    // ordinary readings on one column.
                    sigma
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: BenchMetric.sigmaWidth, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
            Text(slot.label).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.spacing(.tight))
            if printedUnused != nil {
                // Text("literal"), NOT Text(someString). A String-typed
                // argument picks the verbatim initialiser and ships English
                // whatever the catalogue says; the literal keeps its
                // LocalizedStringKey path. `printedUnused` stays a String
                // because the SPOKEN value concatenates it.
                Text("unused").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            // WHAT SOMEBODY TYPED, IN THE COLOUR FOR WHAT SOMEBODY ASKED FOR.
            // Every number on the Inputs tab is authored — that is what the tab
            // is — and drawing it in the same ink as the network's own output
            // would erase the one distinction this screen exists to draw.
            Text(printedValue)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.asked)
            Text(printedUnit).font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }

    private var slider: some View {
        Slider(value: Binding(get: { Double(reading.value) },
                              set: { onChange(Float($0)) }),
               in: slot.lower...max(slot.upper, slot.lower + 1e-6))
            // THE SLIDER IS THE ROW, AS FAR AS VOICEOVER IS CONCERNED.
            // A Slider is its own accessibility element and carries the
            // .adjustable trait, so the name in the heading above is a
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
    }

    /// The z-score sits beside the slider rather than in a separate strip: the
    /// number only means anything next to the value that produced it.
    ///
    /// AN OUTLIER IS A WARNING AND NOT A REFUSAL. Nothing has said no — the
    /// network will answer for an input twelve standard deviations out, and
    /// what it answers is exactly the thing worth looking at. `Theme.warning`
    /// is the token for a limit being approached rather than one being hit.
    private var sigma: some View {
        Text(printedSigma)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(reading.isOutlier ? Theme.warning : Theme.textTertiary)
            .accessibilityHidden(true)
    }
}

/// One input's influence, as a bar against the strongest input at this
/// observation — not against whatever the largest value happens to be, so the
/// chart does not rescale every time a slider moves.
///
/// IN `measured`, WHICH IS THE POINT OF THE TAB. A sensitivity is not something
/// anybody typed: it is the exact Jacobian of this network at this observation,
/// computed on the phone, and teal is this app's claim that a machine produced
/// what you are reading. The Inputs tab beside it is yellow for the same reason
/// in reverse.
private struct SensitivityRow: View {
    let column: Sensitivity.Column
    let peak: Float

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            // THE INPUT AND THE JOINT IT MOVES MOST, REFLOWING RATHER THAN
            // TRUNCATING. "Left hip yaw velocity" and "left_knee" do not share
            // a line at an accessibility size on any phone, and the half that
            // used to be dropped is the joint — which is the half that says
            // what the input does.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                    label
                    Spacer(minLength: Theme.spacing(.tight))
                    joint
                }
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    label
                    joint
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.separator)
                    Capsule().fill(Theme.measured)
                        .frame(width: geo.size.width * CGFloat(peak > 0 ? column.norm / peak : 0))
                }
            }
            .frame(height: BenchMetric.sensitivityBarHeight)
        }
        .padding(.vertical, Theme.spacing(.hairline))
        // The input and the joint it moves most are one fact, and the bar is
        // that fact drawn again — so this is one element, and the bar is silent.
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        Text(column.slot.label).font(.caption)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var joint: some View {
        Text(column.strongestJoint).font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
