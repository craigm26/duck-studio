import SwiftUI
import DuckKit
import StudioKit

/// Write a motion from scratch: pose the robot, mark the moment, repeat.
///
/// WHAT THIS IS NOT. It is not a recording, and the screen says so on every
/// visit. A recorded intent is a trained policy driving the robot through
/// physics with the trunk going wherever physics put it. This is a list of
/// poses and the times they happen at, interpolated. It is the same shape as
/// the authored moves already in the corpus — `step_up` and `wall_flip` are
/// exactly this — and those are also the ones measured at 0 of 16, which is the
/// most useful thing anybody can know before writing another one.
struct IntentAuthorView: View {
    @State var draft: IntentDraft
    @ObservedObject var scenes: SceneStore
    /// Which model answers "make the bow deeper". Optional so a screen that
    /// has no store still opens the editor — the Ask panel then says what is
    /// missing rather than being absent, because a tab that vanishes is a
    /// feature nobody finds twice.
    var models: EndpointStore?
    /// True when this editor created the motion. A draft must be in the store
    /// before the sheet can look it up, so a new one exists before its editor
    /// appears — and Cancel has to be able to un-create it.
    let isNew: Bool
    let onSave: (IntentDraft) -> Void
    /// Take it out of the store. Must clear the presentation binding BEFORE
    /// touching the store, or the sheet's lookup stops resolving while it is
    /// still on screen and presents an empty, toolbar-less NavigationStack.
    let onDiscard: (IntentDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = false
    @State private var orbit = OrbitState()
    /// THE SELECTED KEYFRAME BY IDENTITY, NOT BY INDEX. `ordered` is sorted by
    /// time and the times are editable, so an index means a different keyframe
    /// the moment somebody drags one past its neighbour — and means NO keyframe
    /// at all once one is deleted, which left the Pose tab silently blank.
    @State private var selectedKey: UUID?
    /// What the draft looked like on the way in, so Cancel has something to go
    /// back to.
    @State private var original: IntentDraft?
    @State private var panel: Panel = .joints
    @State private var outgoing: Outgoing?
    @State private var failure: String?
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false
    @State private var publishing = false

    enum Panel: String, CaseIterable, Identifiable {
        case joints = "Pose", timeline = "Keyframes", ask = "Ask", checks = "Checks"
        var id: String { rawValue }
    }

    private var ordered: [IntentDraft.Key] { draft.keys.sorted { $0.time < $1.time } }

    @State private var asked = ""
    @State private var thinking = false
    @State private var tweakNotes: [String] = []
    @State private var tweakFailure: String?
    /// The motion as it was before the last tweak, so a sentence that made it
    /// worse can be taken back. ONE STEP IS ENOUGH: the alternative is an undo
    /// stack nobody asked for, and Cancel already puts back the whole session.
    @State private var beforeTweak: IntentDraft?

    /// The keyframe being edited, falling back to the first. A selection can go
    /// stale — the keyframe it named was deleted — and the right answer then is
    /// to edit something rather than to show an empty panel.
    private var editingKey: IntentDraft.Key? {
        ordered.first { $0.id == selectedKey } ?? ordered.first
    }

    private var hasUnsavedChanges: Bool {
        guard let original else { return false }
        return original != draft
    }
    private var scene: DuckScene? { scenes.scenes.first { $0.id == draft.sceneID } }

    /// What to draw. Scrubbing shows the interpolated motion; standing on a
    /// keyframe shows that keyframe exactly, which is what makes editing one
    /// feel like editing rather than like nudging an average.
    private var shown: [Double] {
        draft.pose(at: playhead)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                DuckStage(pose: StagePose(jointAngles: shown, root: StagePose.home.root),
                          environment: scene?.environment ?? .bareFloor,
                          orbit: $orbit)
                StageLegend(pose: StagePose(jointAngles: shown, root: StagePose.home.root),
                            environment: scene?.environment ?? .bareFloor,
                            orbit: $orbit)
            }
            .frame(maxHeight: 300)

            TransportBar(duration: max(draft.duration, 0.01),
                         playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal).padding(.vertical, 6)

            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 6)

            List {
                switch panel {
                case .joints:   joints
                case .timeline: timeline
                case .ask:      ask
                case .checks:   checks
                }
            }
        }
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        // TWO WAYS OUT, BOTH ALWAYS PRESENT. The first version had one — a
        // "Save" button that both wrote to the store and dismissed in the same
        // tick — and a person who did not want to keep what they had made had
        // nowhere to go. Done only dismisses, because the work is already
        // saved; Cancel puts back what was there on the way in.
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { discard() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { share() } label: {
                        Label("Export the motion", systemImage: "square.and.arrow.up")
                    }
                    Button { publishing = true } label: {
                        Label("Publish to Hugging Face", systemImage: "arrow.up.circle")
                    }
                    Menu("Author against") {
                        Button("Bare floor") { draft.sceneID = nil }
                        ForEach(scenes.scenes) { s in
                            Button(s.name) { draft.sceneID = s.id }
                        }
                    }
                    Divider()
                    // The only other way to remove a motion is swiping its row
                    // in the list, which nothing signposts.
                    Button("Delete this motion", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Throw away this motion?", isPresented: $confirmingDiscard,
                            titleVisibility: .visible) {
            Button("Throw it away", role: .destructive) { reallyDiscard() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            // THE OLD COPY WAS FALSE AT EXACTLY THE MOMENT IT MATTERED. It
            // chose on `keys.count < 3`, and a blank motion has two, so every
            // brand-new one was told "It has not been saved anywhere else" —
            // while sitting in the list, saved.
            Text(isNew
                 ? "This motion will be deleted. It is not saved anywhere else."
                 : "Everything since you opened it will go back to how it was.")
        }
        .confirmationDialog("Delete this motion?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { dismiss(); onDiscard(draft) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It goes from the list and from this iPhone. This cannot be undone.")
        }
        .onAppear { if original == nil { original = draft } }
        .sheet(item: $outgoing) { out in
            NavigationStack {
                ShareDestinationsView(title: draft.name, file: out.url, message: out.message)
            }
        }
        .sheet(isPresented: $publishing) {
            PublishMotionView(draft: draft)
        }
        .alert("Could not export", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
        .onReceive(Timer.publish(every: 1.0 / DuckModel.tickHz, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning, draft.duration > 0 else { return }
            playhead += 1.0 / DuckModel.tickHz
            if playhead >= draft.duration { playhead = 0 }
        }
        .onChange(of: draft) { _, new in onSave(new) }
    }

    // MARK: - posing

    @ViewBuilder private var joints: some View {
        Section {
            TextField("Name", text: $draft.name)
            Text(IntentDraft.disclaimer).font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Picker("Editing", selection: Binding(
                get: { editingKey?.id },
                set: { picked in
                    selectedKey = picked
                    // Jump the playhead to whatever was picked, so the robot on
                    // screen is always the pose the sliders move. Editing one
                    // keyframe while looking at another is how somebody drags a
                    // joint for a minute and wonders why nothing happens.
                    if let picked, let key = ordered.first(where: { $0.id == picked }) {
                        playhead = key.time
                    }
                    isRunning = false
                })) {
                ForEach(ordered) { key in
                    Text(String(format: "%.2f s", key.time)).tag(UUID?.some(key.id))
                }
            }
            .pickerStyle(.segmented)
            // The picker shows what exists; this makes one. Without it the only
            // way to add a keyframe was the Keyframes tab, which somebody
            // working on a pose has no reason to open.
            Button {
                let time = nudged(playhead)
                let key = IntentDraft.Key(time: time, pose: draft.pose(at: playhead))
                draft.keys.append(key)
                selectedKey = key.id
                playhead = time
            } label: {
                Label(String(format: "Add a keyframe here (%.2f s)", playhead),
                      systemImage: "plus")
                    .font(.footnote)
            }
        } header: {
            Text("Keyframe")
        } footer: {
            Text("Pick a moment, then move the joints. The robot above shows the keyframe you are editing. A new one holds whatever the motion was already doing at that instant — every pose stays pinned, though the curve between them re-eases, because each span is smoothed on its own.")
        }

        if let key = editingKey {
            ForEach(JointGroup.all) { group in
                Section {
                    ForEach(group.joints, id: \.self) { joint in
                        JointSlider(control: JointControl(index: joint),
                                    value: binding(joint: joint, of: key.id))
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    group.note.map { Text($0) }
                }
            }
        }
    }

    /// A slider drives ONE joint of ONE keyframe, found by id — sorting by time
    /// means an index names a different keyframe the moment somebody drags one
    /// past its neighbour, and names nothing once one is deleted.
    private func binding(joint: Int, of id: UUID) -> Binding<Double> {
        Binding(
            get: {
                draft.keys.first { $0.id == id }?.pose[joint]
                    ?? JointControl(index: joint).home
            },
            set: { value in
                guard let index = draft.keys.firstIndex(where: { $0.id == id }),
                      draft.keys[index].pose.indices.contains(joint) else { return }
                draft.keys[index].pose[joint] = value
            })
    }

    // MARK: - asking for a change

    /// Describe a change and watch it happen.
    ///
    /// IT EDITS; IT DOES NOT REDRAFT. The model is shown the motion that exists
    /// — every keyframe, every joint that has moved — and asked for a list of
    /// changes. Everything it does not mention is left alone, which is the only
    /// behaviour that makes a second sentence safe to send. Asking for a whole
    /// new motion would throw away every slider already nudged.
    @ViewBuilder private var ask: some View {
        Section {
            TextField("Make the bow deeper. Hold it longer. Look left at the end.",
                      text: $asked, axis: .vertical)
                .lineLimit(1...4)
            Button {
                Task { await applyTweak() }
            } label: {
                HStack {
                    Label("Change it", systemImage: "wand.and.stars")
                    if thinking { Spacer(); ProgressView() }
                }
            }
            .disabled(thinking || asked.trimmingCharacters(in: .whitespaces).isEmpty
                      || models?.selected.kind != .openAICompatible)
        } header: {
            Text("Describe a change")
        } footer: {
            if let models, models.selected.kind == .openAICompatible {
                Text("\(models.selected.name) is asked for a list of changes to THIS motion, not for a new one. Anything it does not mention is left exactly as it is. \(models.selected.privacyNote)")
            } else {
                Text("Needs a model that can return a list of edits. Choose one under Draft → Models: a small local one is plenty, because every angle it asks for is checked and clamped here afterwards.")
            }
        }

        if let failure = tweakFailure {
            Section {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }

        if !tweakNotes.isEmpty {
            Section {
                ForEach(tweakNotes, id: \.self) {
                    Label($0, systemImage: "checkmark").font(.footnote)
                }
                if beforeTweak != nil {
                    Button(role: .destructive) {
                        if let before = beforeTweak {
                            draft = before
                            beforeTweak = nil
                            tweakNotes = []
                        }
                    } label: {
                        Label("Put it back", systemImage: "arrow.uturn.backward")
                    }
                }
            } header: {
                Text("What changed")
            } footer: {
                Text("The robot above is already showing it. Scrub the timeline to watch it through.")
            }
        }
    }

    private func applyTweak() async {
        guard let models else { return }
        let sentence = asked.trimmingCharacters(in: .whitespaces)
        thinking = true; tweakFailure = nil
        defer { thinking = false }
        let endpoint = models.armed(models.selected)
        do {
            let answer = try await DraftEngine.ask(
                endpoint, kind: .tweak, prompt: sentence, knownIntents: [],
                instructions: ChatDraft.tweakInstructions(for: draft))
            let tweak = try ChatDraft.tweak(fromJSON: answer.json)
            let (edited, notes) = try tweak.applied(to: draft)
            beforeTweak = draft
            draft = edited
            tweakNotes = notes.isEmpty ? [tweak.summary] : notes
            asked = ""
            // Show the first thing that changed, so the preview is looking at
            // the edit rather than wherever the playhead happened to be.
            // The editor autosaves on every change of `draft`, so there is
            // nothing to call here — the onChange above has already run.
            if let first = edited.keys.map(\.time).sorted().first { playhead = first }
            isRunning = false
        } catch let failure as MotionTweak.Failure {
            tweakFailure = failure.message
        } catch let wire as ChatWire.WireError {
            tweakFailure = wire.message
        } catch let draftError as ChatDraft.DraftError {
            tweakFailure = draftError.message
        } catch {
            tweakFailure = error.localizedDescription
        }
    }

    // MARK: - the timeline

    @ViewBuilder private var timeline: some View {
        Section {
            ForEach(ordered) { key in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(format: "%.2f s", key.time))
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Button("Show") {
                            playhead = key.time; isRunning = false
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    // RETIMING WAS THE MISSING ONE. A keyframe could be added,
                    // shown and deleted, and the only way to change WHEN it
                    // happened was to delete it and build it again — so every
                    // "hold it a bit longer" meant redoing the pose.
                    Stepper(value: Binding(
                        get: { key.time },
                        set: { retime(key, to: $0) }),
                            in: 0...30, step: 0.05) {
                        Text("Move it").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { ordered[$0].id }
                draft.keys.removeAll { doomed.contains($0.id) }
            }
        } header: {
            Text("Keyframes")
        } footer: {
            Text("Between keyframes the robot is interpolated with smoothstep — it arrives and leaves at rest. A linear blend would change speed instantly at every keyframe, and a servo asked to do that answers with a jolt the balance controller then has to absorb.")
        }

        Section {
            Button {
                // The pose currently on screen, at the moment currently on
                // screen. Capturing the interpolated pose rather than a copy of
                // a neighbour keeps every pose that was pinned pinned — but it
                // is NOT a no-op, and this comment used to claim it was. Each
                // span is smoothstepped separately, so splitting one in two
                // makes the duck ease through the middle where it used to sail
                // past: about two degrees at the half-second on a simple bow.
                // The least surprising choice available, not a free one.
                let time = nudged(playhead)
                let key = IntentDraft.Key(time: time, pose: draft.pose(at: playhead))
                draft.keys.append(key)
                selectedKey = key.id
                playhead = time
                panel = .joints
            } label: {
                Label(String(format: "Add a keyframe at %.2f s", playhead), systemImage: "plus")
            }
            Button {
                let last = ordered.last
                draft.keys.append(.init(time: (last?.time ?? 0) + 0.5,
                                        pose: last?.pose ?? DuckStance.home.jointAngles))
            } label: {
                Label("Add half a second on the end", systemImage: "arrow.right.to.line")
            }
        }
    }

    /// Move a keyframe to another moment, refusing a collision rather than
    /// creating one.
    private func retime(_ key: IntentDraft.Key, to time: TimeInterval) {
        guard let index = draft.keys.firstIndex(where: { $0.id == key.id }) else { return }
        let wanted = max(time, 0)
        guard !draft.keys.contains(where: { $0.id != key.id && abs($0.time - wanted) < 0.005 })
        else { return }
        draft.keys[index].time = wanted
        playhead = wanted
        isRunning = false
    }

    /// A time not already taken. Two keyframes at the same instant is a broken
    /// motion, and the button that creates it should not be able to.
    private func nudged(_ time: TimeInterval) -> TimeInterval {
        var candidate = max(time, 0)
        while draft.keys.contains(where: { abs($0.time - candidate) < 0.005 }) {
            candidate += 0.02
        }
        return candidate
    }

    // MARK: - checks

    @ViewBuilder private var checks: some View {
        let problems = draft.problems
        Section {
            Text(draft.provenance).font(.footnote).foregroundStyle(.secondary)
        }
        if problems.isEmpty {
            Section {
                Label("Nothing to flag. Every pose is inside its travel and nothing moves faster than the recorded corpus does.",
                      systemImage: "checkmark.circle")
                    .font(.footnote)
            }
        } else {
            Section {
                ForEach(problems) { problem in
                    Label {
                        Text(problem.text).font(.footnote)
                    } icon: {
                        Image(systemName: icon(problem.severity))
                            .foregroundStyle(problem.severity == .caution ? Color.secondary : .orange)
                    }
                }
            } header: {
                Text("Checks")
            } footer: {
                Text("These are the things a phone can check: travel, ordering, and how fast a joint is asked to move against what the recorded corpus actually does. What it cannot check is whether the robot stays up, because that needs physics.")
            }
        }
        Section {
            Text("Every authored move in this app — step_up, lever_up, riser_up, climb — was written this way and searched against a real step, and all four get up their flight 0 times in 16. Authoring is the easy half.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Before you run it")
        }
    }

    private func icon(_ severity: IntentDraft.Problem.Severity) -> String {
        switch severity {
        case .broken:     return "exclamationmark.triangle.fill"
        case .impossible: return "gauge.with.dots.needle.100percent"
        case .caution:    return "info.circle"
        }
    }

    /// Leave without keeping the changes. Asks first only when there is
    /// something to lose — a confirmation on an untouched draft is a dialog
    /// that teaches people to tap through dialogs.
    private func discard() {
        // An untouched NEW motion still has something to lose — itself. It was
        // committed to the store before this sheet opened, so dismissing
        // silently leaves a row called "New motion" that the person never
        // wanted and cannot explain.
        guard hasUnsavedChanges else {
            dismiss()
            if isNew { onDiscard(draft) }
            return
        }
        confirmingDiscard = true
    }

    private func reallyDiscard() {
        if isNew {
            // NOTHING TO GO BACK TO: this motion did not exist before the sheet
            // opened. And do NOT restore `original` first — assigning `draft`
            // fires the .onChange that saves, which would re-create the row
            // being deleted. That is what the first version did, so the red
            // "Throw it away" button put the motion straight back.
            dismiss()
            onDiscard(draft)
            return
        }
        if let original {
            draft = original
            onSave(original)
        }
        dismiss()
    }

    private func share() {
        do {
            let data = try draft.exported()
            guard let url = ExportFile.write(data, named: draft.suggestedFilename) else {
                failure = "The file could not be written."
                return
            }
            outgoing = Outgoing(url: url, message: CommunityShare.message(forDraft: draft))
        } catch let error as DuckMove.Invalid {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
    }
}

/// One joint, with its real travel as the slider's ends.
private struct JointSlider: View {
    let control: JointControl
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(control.name).font(.caption)
                Spacer()
                Text(control.degrees(value))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            // The ends ARE the travel stops, so the slider cannot ask for an
            // angle the joint does not have. A slider with generous ends and a
            // warning underneath is a slider that teaches people to ignore
            // warnings.
            Slider(value: $value, in: control.lower...control.upper)
            HStack {
                Text(control.travelLabel.lower)
                Spacer()
                Text(control.travelLabel.upper)
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}


