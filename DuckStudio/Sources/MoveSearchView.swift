import SwiftUI
import DuckKit
import StudioKit

/// Search a move's keyframes — the second of the app's two searches, and the
/// one somebody asking for "the search in the tuning" usually means.
///
/// WHAT IT IS, AND WHY IT IS NOT ON THE TUNE SCREEN. `TuneView` searches a
/// network: twenty-eight numbers that fold into a last layer, needing a base
/// policy to fold into, producing a file robotd loads. This searches a MOVE:
/// the poses and times of an authored keyframe track, needing a challenge
/// entrant to open, producing a harness intent the bench replays. One screen
/// for both would be one screen that could do neither without asking which.
///
/// NOTHING ON THIS SCREEN COMPUTES ANYTHING. The objective is
/// `MoveSearch.cellScore`, the clamp is `MoveSearch.apply`, the ranking is
/// `MoveSearch.ranked`, the budget is `MoveSearch.budget`, and every sentence
/// is a `static let` the kit's tests read. This file arranges them and
/// `MoveSearchRun` owns the wire.
///
/// THE DELIVERABLE IS THE SWING TABLE, AND THAT IS MEASURED RATHER THAN
/// PREFERRED. The conditions move this score far more than the gap between two
/// expert moves does — measured on the two published vaults this app ships, one
/// leaderboard place apart, whose cells differ by an average of 0.004 against a
/// 0.91 spread. That is not a reason to refuse the feature; it is the number
/// printed above the button, and it is why "measure what each handle is worth"
/// sits between "measure this move" and "search".
///
/// THE STAGE CARRIES NO OVERLAY AT ALL. Every number is a row below the
/// picture, so the rule about overlays on a live picture is satisfied by
/// construction rather than by a collapsed box somebody has to keep collapsed.
struct MoveSearchView: View {

    @ObservedObject var benches: BenchStore
    @ObservedObject var models: EndpointStore
    @StateObject private var run = MoveSearchRun()
    @StateObject private var specs = SearchSpecStore()

    @State private var file = StairsChallenge.record.file
    @State private var rise = StairsChallenge.defaultRise
    @State private var playhead: TimeInterval = 0
    @State private var orbit = OrbitState()
    @State private var expanded: Set<String> = []
    @State private var sentence = ""
    @State private var reading = false
    @State private var wordNotes: [String] = []
    @State private var wordRefusals: [String] = []
    @State private var outgoing: ExportedFile?
    @Environment(\.dynamicTypeSize) private var typeSize

    // MARK: - what is on screen

    /// The picker's rows: the entrants, then the three reference controls.
    private var rows: [StairsChallenge.Row] {
        StairsChallenge.entries + StairsChallenge.controls
    }

    private var move: StairsChallenge.Move? {
        try? StairsChallenge.move(named: file)
    }

    private var keys: [IntentDraft.Key] {
        guard let move else { return [] }
        return MoveSearch.draft(of: move).keys.sorted { $0.time < $1.time }
    }

    /// A PURE READ, safe from `body`: the store loads and prunes in `.task`,
    /// never from a getter a view update evaluates.
    private var spec: MoveSearch.Spec {
        var held = specs.held(file, rise: rise)
        held.rise = rise
        return held
    }

    var body: some View {
        Form {
            whatThisSearches
            theMove
            if !keys.isEmpty { handleRows }
            shapeSection
            describeIt
            whatItWillCost
            whatAResultWouldHaveToBeat
            buttons
            if !run.swings.isEmpty { swingTable }
            if let result = run.result { resultSection(result) }
            if !run.failedCells.isEmpty { failedCellRows }
            if let failure = run.failure { failureRow(failure) }
            theOtherThings
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Search a move's keyframes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await run.probe(benches: benches)
            Haptic.prepare()
        }
        .task(id: file) {
            if let move { specs.load(file: file, rise: rise, in: move) }
        }
        .onDisappear { specs.flush() }
        .sheet(item: $outgoing) { file in
            ShareSheet(items: [file.url]) { outgoing = nil }
        }
    }

    // MARK: - what this searches

    private var whatThisSearches: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing(.snug)) {
                Text(MoveSearch.notTraining)
                Text(MoveSearch.whatItSearches)
                Text(MoveSearch.everythingIsHeldToStart)
                Text(StairsChallenge.realDuckCaveat)
                    .foregroundStyle(Theme.warning)
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Picker("Move", selection: $file) {
                ForEach(rows, id: \.file) { row in
                    Text(row.moveName).tag(row.file)
                }
            }
            .disabled(run.isRunning)

            Picker("Rise", selection: $rise) {
                ForEach(StairsChallenge.rises, id: \.self) { value in
                    Text(StairsChallenge.riseSaid(value)).tag(value)
                }
            }
            .disabled(run.isRunning)

            if let note = specs.droppedNote(for: file) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "What this searches")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the move

    private var theMove: some View {
        Section {
            if let move {
                DuckStage(pose: StagePose(jointAngles: MoveSearch.draft(of: move)
                                                            .pose(at: playhead),
                                          root: StagePose.home.root),
                          environment: .bareFloor, orbit: $orbit)
                    // NOT CAPPED AT ACCESSIBILITY SIZES, the same rule the other
                    // four hosts document: the duck shrinks to make room and the
                    // rows under it do not disappear.
                    .frame(maxHeight: typeSize.isAccessibilitySize
                                        ? nil : MoveSearchMetric.viewportHeight)
                    .listRowInsets(EdgeInsets())
                Slider(value: $playhead, in: 0...max(move.duration, 0.01))
                    .accessibilityLabel(Text("Where in the move"))
                    .accessibilityValue(Text(String(format: "%.2f seconds", playhead)))
                TelemetryRow(label: "At", value: String(format: "%.2f s", playhead))
                TelemetryRow(label: "Keyframes", value: "\(keys.count)")
                if let row = StairsChallenge.row(file: file) {
                    Text(row.note)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A CAVEAT, NOT AN EXCLUSION, and said before anything runs
                // rather than only on the result — the only two files that
                // declare shape bounds are two of the three that carry one, so
                // excluding them would make the shape controls unreachable on
                // every file in the corpus.
                if MoveSearch.carriesALandingLaw(move) {
                    Text(MoveSearch.landingLawNotSearched)
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(StairsChallenge.ResourceError.missing(file).message)
                    .font(.footnote)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "The move")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the handles

    private var handleRows: some View {
        Section {
            ForEach(Array(keys.enumerated()), id: \.element.id) { index, key in
                keyframeRow(index: index, key: key)
            }
            Text(MoveSearch.mouthIsNotSearched)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "Handles · \(spec.handles.count) unlocked")
        } footer: {
            Text(MoveSearch.noBlendPerTransition)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    @ViewBuilder
    private func keyframeRow(index: Int, key: IntentDraft.Key) -> some View {
        let unlocked = spec.handles.contains { $0.keyframe == key.id }
        Button {
            if expanded.contains(key.id.uuidString) { expanded.remove(key.id.uuidString) }
            else { expanded.insert(key.id.uuidString) }
        } label: {
            HStack {
                Image(systemName: unlocked ? "lock.open" : "lock")
                    .foregroundStyle(unlocked ? Theme.actionSecondary : Theme.textTertiary)
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(String(format: "Keyframe %d · %.2f s", index + 1, key.time))
                        .foregroundStyle(Theme.textPrimary)
                    if let move {
                        Text(MoveSearch.describe(keyframe: key, in: move))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)

        if expanded.contains(key.id.uuidString), let move {
            ForEach(JointGroup.all.filter { $0.title != "Mouth" }) { group in
                groupToggle(group, keyframe: key.id, in: move)
            }
            // ONE JOINT, for the case a group is too blunt. Behind a disclosure
            // because fifteen toggles under every keyframe is the eighty-four
            // directions `everythingIsHeldToStart` exists to talk somebody out
            // of, laid out as a list.
            Button {
                let id = "joints:\(key.id.uuidString)"
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            } label: {
                Label("One joint…", systemImage: expanded
                        .contains("joints:\(key.id.uuidString)")
                            ? "chevron.down" : "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.actionSecondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, Theme.spacing(.standard))
            if expanded.contains("joints:\(key.id.uuidString)") {
                ForEach(JointGroup.all.filter { $0.title != "Mouth" }
                            .flatMap(\.joints), id: \.self) { joint in
                    jointToggle(joint, keyframe: key.id, in: move)
                }
            }
            timingToggle(keyframe: key.id, at: key.time, in: move)
        }
    }

    @ViewBuilder
    private func groupToggle(_ group: JointGroup, keyframe: UUID,
                             in move: StairsChallenge.Move) -> some View {
        let handle = MoveSearch.Handle(kind: .pose(keyframe: keyframe, .group(group.title)),
                                       room: degrees(for: keyframe, group: group.title))
        let on = spec.handles.contains { $0.id == handle.id }
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Toggle(group.title, isOn: Binding(
                get: { on },
                set: { wanted in toggle(handle, on: wanted) }))
                .disabled(run.isRunning)
            if on {
                Stepper(value: Binding(
                    get: { degrees(for: keyframe, group: group.title) },
                    set: { widen(handle, to: $0) }),
                        in: MoveSearch.degreeRange.low...MoveSearch.degreeRange.high,
                        step: 1) {
                    Text(String(format: "How far · ±%.0f°",
                                degrees(for: keyframe, group: group.title)))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .disabled(run.isRunning)
                if let room = MoveSearch.headroom(handle, in: move) {
                    Text(room.sentence)
                        .font(.caption)
                        .foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, Theme.spacing(.standard))
    }

    @ViewBuilder
    private func jointToggle(_ joint: Int, keyframe: UUID,
                             in move: StairsChallenge.Move) -> some View {
        let control = JointControl(index: joint)
        let handle = MoveSearch.Handle(kind: .pose(keyframe: keyframe, .joint(joint)),
                                       room: degrees(for: keyframe, joint: joint))
        let on = spec.handles.contains { $0.id == handle.id }
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Toggle(control.plainName, isOn: Binding(
                get: { on }, set: { toggle(handle, on: $0) }))
                .disabled(run.isRunning)
            if on {
                Stepper(value: Binding(get: { degrees(for: keyframe, joint: joint) },
                                       set: { widen(handle, to: $0) }),
                        in: MoveSearch.degreeRange.low...MoveSearch.degreeRange.high,
                        step: 1) {
                    Text(String(format: "How far · ±%.0f°",
                                degrees(for: keyframe, joint: joint)))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .disabled(run.isRunning)
                if let room = MoveSearch.headroom(handle, in: move) {
                    Text(room.sentence)
                        .font(.caption)
                        .foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, Theme.spacing(.loose))
    }

    @ViewBuilder
    private func timingToggle(keyframe: UUID, at time: TimeInterval,
                              in move: StairsChallenge.Move) -> some View {
        let handle = MoveSearch.Handle(kind: .time(keyframe: keyframe),
                                       room: seconds(for: keyframe))
        let on = spec.handles.contains { $0.id == handle.id }
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Toggle("When it happens", isOn: Binding(
                get: { on },
                set: { wanted in toggle(handle, on: wanted) }))
                .disabled(run.isRunning)
            if on {
                Stepper(value: Binding(get: { seconds(for: keyframe) },
                                       set: { widen(handle, to: $0) }),
                        in: 0.01...0.50, step: 0.01) {
                    Text(String(format: "How far · ±%.2f s", seconds(for: keyframe)))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .disabled(run.isRunning)
                if let refusal = timingRefusal(handle, in: move) {
                    Text(refusal)
                        .font(.caption)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, Theme.spacing(.standard))
    }

    /// Whether a timing window would collide, asked of the kit by trying it.
    ///
    /// THE ONLY HONEST TEST IS THE ONE THE RUN WILL MAKE. A second rule here
    /// about how close two keyframes may be would be a second rule to drift.
    private func timingRefusal(_ handle: MoveSearch.Handle,
                               in move: StairsChallenge.Move) -> String? {
        for direction in [1.0, -1.0] {
            let point = MoveSearch.probe(spec, handle: handle, direction: direction)
            do { _ = try MoveSearch.apply(point, to: move, spec: spec.with(handles: [handle])) }
            catch let refusal as MoveSearch.Refusal { return refusal.message }
            catch { return nil }
        }
        return nil
    }

    // MARK: - the shape parameters

    private var shapeSection: some View {
        Section {
            if let move {
                ForEach(MoveSearch.shapeKeys, id: \.self) { key in
                    shapeRow(key, in: move)
                }
            }
            Text(MoveSearch.theOtherBlend)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "Shape")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    @ViewBuilder
    private func shapeRow(_ key: String, in move: StairsChallenge.Move) -> some View {
        if let bounds = MoveSearch.declaredBounds(for: key, in: move) {
            let handle = MoveSearch.Handle(kind: .shape(key), room: span(for: key, bounds: bounds))
            let on = spec.handles.contains { $0.id == handle.id }
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Toggle(key, isOn: Binding(get: { on }, set: { toggle(handle, on: $0) }))
                    .disabled(run.isRunning)
                if on {
                    Slider(value: Binding(get: { span(for: key, bounds: bounds) },
                                          set: { widen(handle, to: $0) }),
                           in: 0.001...(bounds.high - bounds.low) / 2)
                        .disabled(run.isRunning)
                    Text(String(format: "±%.4f, inside the file's own declared %.4f to %.4f.",
                                span(for: key, bounds: bounds), bounds.low, bounds.high))
                        .font(.caption)
                        .foregroundStyle(Theme.measured)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(key).foregroundStyle(Theme.textPrimary)
                Text(MoveSearch.shapeNeedsDeclaredBounds)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - words

    private var describeIt: some View {
        Section {
            TextField("hold the hips in the second pose", text: $sentence, axis: .vertical)
                .lineLimit(1...4)
                .disabled(run.isRunning || reading)
            Button {
                readIt()
            } label: {
                Text(reading ? "Reading…" : "Read it").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || run.isRunning || reading || models.selected.kind == .appleOnDevice)

            if models.selected.kind == .appleOnDevice {
                Text(SearchWords.appleHandsBackOneValue(models.selected.name))
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(wordNotes, id: \.self) { note in
                Label {
                    Text(note).font(.footnote).foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "checkmark.seal").foregroundStyle(Theme.success)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(wordRefusals, id: \.self) { refusal in
                Label {
                    Text(refusal).font(.footnote).foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "xmark.octagon").foregroundStyle(Theme.refused)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "Describe what to hold")
        } footer: {
            Text("Every number a sentence writes is a control above that you could have set "
               + "yourself, and can change afterwards.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - cost, and what a result would have to beat

    private var whatItWillCost: some View {
        Section {
            Text(MoveSearch.budget(for: spec).described)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // THE TWO NUMBERS A SENTENCE MAY WRITE THAT HAD NO CONTROL. The
            // footer above says every number a sentence writes is a control a
            // person could have set and can change back; these two make that
            // true, and share the words path's ranges.
            Stepper(value: Binding(get: { spec.generations },
                                   set: { value in
                                       var held = spec; held.generations = value; specs.save(held)
                                   }),
                    in: MoveSearch.generationsRange) {
                TelemetryRow(label: MoveSearch.generationsSaid, value: "\(spec.generations)")
            }
            Stepper(value: Binding(get: { spec.lambda },
                                   set: { value in
                                       var held = spec; held.lambda = value; specs.save(held)
                                   }),
                    in: MoveSearch.childrenRange) {
                TelemetryRow(label: MoveSearch.childrenSaid, value: "\(spec.lambda)")
            }
            if run.isRunning {
                // THE DENOMINATOR IS THE PHASE IN FLIGHT. The whole-workflow
                // figure belongs to the cost sentence above; a tally that
                // resets every run measured against it read as wrong in both
                // directions.
                TelemetryRow(label: "Asked so far",
                             value: MoveSearch.progressLine(
                                done: run.requestsDone,
                                of: run.expectedRequests))
            }
            Text(run.duration)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "What this will cost")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// HEADED AS WHAT IT IS: a measurement about two OTHER, published moves.
    /// The number a verdict actually compares against is this move's own
    /// spread, measured in the run, and it appears in the result and nowhere
    /// else.
    private var whatAResultWouldHaveToBeat: some View {
        Section {
            Text(MoveSearch.howMuchTheConditionsMove)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(MoveSearch.objectiveIsOurs)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(MoveSearch.reachIsNotZeroAtRest)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "How much these conditions move a score")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the buttons, each ABSENT rather than disabled when it cannot be honest

    @ViewBuilder private var buttons: some View {
        Section {
            if let bench = benches.selected {
                TelemetryRow(label: "Bench", value: bench.name)
            }
            if let host = run.host {
                Text(PhoneBenchReport.ranOn(host))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if run.probing {
                Text("Asking this bench whether it can score a climb…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else if let unreachable = run.unreachable {
                Text(unreachable)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notYet = run.notYet {
                Text(notYet)
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !run.gridIsThePublishedOne {
                Text(StairsChallenge.Grid.differentGridNote)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reading = run.baseline {
                Text(reading.line)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
                Text(StairsChallenge.oneCellIsNotAScore)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if run.canScore, let move, !run.isRunning {
                Button {
                    Haptic.behaviourStarted()
                    Task { await run.measure(move, rise: rise, benches: benches) }
                } label: {
                    Text("Measure this move").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)

                if run.baseline != nil, !spec.handles.isEmpty {
                    Button {
                        Haptic.behaviourStarted()
                        Task { await run.measureSwings(move, spec: spec, benches: benches) }
                    } label: {
                        Text("Measure what each handle is worth").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                }

                searchButton(move)
            }
            // STOP IS NEVER DISABLED, and it is drawn whenever anything runs.
            if run.isRunning {
                if !run.phase.isEmpty {
                    Text(run.phase)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(run.generations.reversed()) { generation in
                    Text(MoveSearch.generationLine(generation))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(generation.rejectedAsInvalid > 0
                                            ? Theme.warning : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(role: .destructive) {
                    run.stop()
                } label: {
                    Text("Stop").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .accessibilityHint(Text("Ends the search after the current cell."))
            }
        } header: {
            SectionHeading(text: "This bench")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// THE SEARCH BUTTON IS ABSENT WHENEVER IT COULD NOT BE HONEST, and the
    /// sentence beside it says which of the three reasons applies. A greyed
    /// button over a move that scores zero everywhere says the feature exists
    /// and this move is not good enough; the sentence says the true thing.
    @ViewBuilder private func searchButton(_ move: StairsChallenge.Move) -> some View {
        let budget = MoveSearch.budget(for: spec)
        if run.baseline == nil {
            Text(MoveSearch.Refusal.noBaselineYet.message)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else if run.baseline?.reachedFlightCells == 0 {
            Text(MoveSearch.nothingToImproveYet)
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if !budget.isResolvable {
            Text(MoveSearch.budgetTooThin(dimensions: budget.dimensions,
                                          resolvable: budget.resolvable))
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                Haptic.behaviourStarted()
                Task { await run.search(move, spec: spec, benches: benches) }
            } label: {
                Text("Search").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
        }
    }

    // MARK: - what each handle is worth

    private var swingTable: some View {
        Section {
            if let move {
                let ranked = MoveSearch.ranked(run.swings, spread: run.spread)
                ForEach(ranked.above) { swing in
                    Text(MoveSearch.swingLine(swing, in: move))
                        .font(.footnote)
                        .foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !ranked.below.isEmpty {
                    if let spread = run.spread {
                        Text(MoveSearch.swingsUnderTheSpread(ranked.below.count, spread: spread))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // 84 NUMBERS CANNOT SHARE ONE WITHHELD VERDICT, so the
                        // rows are still drawn and the ranking is what is
                        // withheld — per row, in its own colour.
                        Text(run.spreadWasMeasured ? MoveSearch.noConditionSpread
                                                   : MoveSearch.spreadNotMeasuredYet)
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(ranked.below) { swing in
                            Text(MoveSearch.swingLine(swing, in: move))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } header: {
            SectionHeading(text: "What each handle is worth")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the result

    private func resultSection(_ result: MoveSearchRun.Result) -> some View {
        Section {
            Text(result.verdict)
                .font(.footnote)
                .foregroundStyle(Theme.measured)
                .fixedSize(horizontal: false, vertical: true)
            Text(result.score.verdict)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(result.score.extendedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // THE KIT'S OWN PARTIAL-GRID SENTENCES, drawn where the fourteen-
            // cell sentence is: a run with nine cells says "9 of 14 answered"
            // under it, exactly as the challenge screen does.
            ForEach(Array(result.score.problems.enumerated()), id: \.offset) { _, problem in
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(result.residual)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(MoveSearch.aScoreHereIsNotALeaderboardRow)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if result.staleParams {
                Text(MoveSearch.paramsAreNowStale)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result.carriesALandingLaw {
                Text(MoveSearch.landingLawNotSearched)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(DuckTuner.neverOnHardware)
                .font(.caption)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                save(result.move, asHarnessIntent: true)
            } label: {
                action("Save the harness intent", symbol: "square.and.arrow.up")
            }
            Button {
                save(result.move, asHarnessIntent: false)
            } label: {
                action("Save it as a .duckmove", symbol: "square.and.arrow.up")
            }
        } header: {
            SectionHeading(text: "Result")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var failedCellRows: some View {
        Section {
            ForEach(run.failedCells, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "Cells that did not answer · \(run.failedCells.count)")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func failureRow(_ text: String) -> some View {
        Section {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.refused)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - what this cannot do

    private var theOtherThings: some View {
        Section {
            Text(MoveSearch.onlyTheStairs)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DuckTuner.whatWordsMayNotChange)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "What this does not search")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func action(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.actionSecondary)
        }
    }

    // MARK: - the handle bindings

    private func degrees(for keyframe: UUID, group: String) -> Double {
        spec.handles.first { handle in
            handle.kind == .pose(keyframe: keyframe, .group(group))
        }?.room ?? MoveSearch.defaultDegrees
    }

    private func degrees(for keyframe: UUID, joint: Int) -> Double {
        spec.handles.first { handle in
            handle.kind == .pose(keyframe: keyframe, .joint(joint))
        }?.room ?? MoveSearch.defaultDegrees
    }

    private func seconds(for keyframe: UUID) -> Double {
        spec.handles.first { $0.kind == .time(keyframe: keyframe) }?.room
            ?? MoveSearch.defaultSeconds
    }

    private func span(for key: String, bounds: (low: Double, high: Double)) -> Double {
        spec.handles.first { $0.kind == .shape(key) }?.room ?? (bounds.high - bounds.low) / 10
    }

    private func toggle(_ handle: MoveSearch.Handle, on: Bool) {
        var held = spec
        held.handles.removeAll { $0.id == handle.id }
        if on { held.handles.append(handle) }
        specs.save(held)
    }

    private func widen(_ handle: MoveSearch.Handle, to room: Double) {
        var held = spec
        held.handles.removeAll { $0.id == handle.id }
        held.handles.append(MoveSearch.Handle(kind: handle.kind, room: room))
        specs.save(held)
    }

    // MARK: - the words

    private func readIt() {
        guard let move else { return }
        let asked = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return }
        reading = true
        wordNotes = []; wordRefusals = []
        Task {
            defer { reading = false }
            do {
                let answer = try await DraftEngine.ask(
                    models.selected, kind: .search, prompt: asked, knownIntents: [],
                    instructions: SearchWords.instructions(for: move, spec: spec))
                let read = try SearchWords.read(fromJSON: answer.json)
                let outcome = try SearchWords.outcome(read, applyingTo: spec, move: move)
                specs.save(outcome.spec)
                // THE PICKER MOVES WITH THE NOTE, or the note is a lie: the
                // words path snaps the rise to one of the challenge's, so it
                // is always a tag the picker has.
                rise = outcome.spec.rise
                wordNotes = outcome.notes
                wordRefusals = outcome.refusals
                // NO SEAL FOR A SENTENCE NOBODY READ. Nothing landed means the
                // refusal colour and an untouched spec, never a green tick over
                // a search that did not change.
                if outcome.notes.isEmpty && outcome.refusals.isEmpty {
                    wordRefusals = [SearchWords.nothingWasRead]
                }
            } catch let failure as SearchWords.Failure {
                wordRefusals = [failure.message]
            } catch {
                wordRefusals = [error.localizedDescription]
            }
        }
    }

    // MARK: - saving

    private func save(_ move: StairsChallenge.Move, asHarnessIntent: Bool) {
        do {
            if asHarnessIntent {
                outgoing = ExportedFile(
                    url: try ExportFile.write(move.encoded(), named: "\(stem)-searched.json"))
            } else {
                var draft = MoveSearch.draft(of: move)
                draft.name = "\(stem) searched"
                outgoing = ExportedFile(
                    url: try ExportFile.write(try draft.exported(),
                                              named: draft.suggestedFilename))
            }
        } catch let refusal as ExportFile.Failure {
            run.failure = refusal.message
        } catch let refusal as IntentDraft.ExportRefusal {
            run.failure = refusal.message
        } catch {
            run.failure = error.localizedDescription
        }
    }

    private var stem: String {
        file.hasSuffix(".json") ? String(file.dropLast(5)) : file
    }
}

/// How tall this screen's stage is, READ FROM THE KIT RATHER THAN RESTATED.
///
/// THIS WAS A SIXTH COPY OF THE 300 AND THE GUARD CAUGHT IT. An earlier draft
/// of this file wrote the number here and called restating it "the rule the
/// other four stage hosts already follow". That had it backwards:
/// `camera_math_allowlist.txt` names those four copies as DEBT, says in as many
/// words that the list only shrinks, and that "a new screen writing its own
/// field of view or its own 300 is the failure this guard exists to catch".
/// This screen is new, so it takes the kit's number and adds no entry.
///
/// The name stays so the one call site above reads the same; only the source of
/// the number moved. `StageViewport.standardHeight` is a `Double`, hence the
/// explicit conversion.
enum MoveSearchMetric {
    static let viewportHeight = CGFloat(StageViewport.standardHeight)
}
