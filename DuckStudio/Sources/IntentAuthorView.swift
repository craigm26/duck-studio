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
    let onSave: (IntentDraft) -> Void

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

    enum Panel: String, CaseIterable, Identifiable {
        case joints = "Pose", timeline = "Keyframes", checks = "Checks"
        var id: String { rawValue }
    }

    private var ordered: [IntentDraft.Key] { draft.keys.sorted { $0.time < $1.time } }

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
                    Menu("Author against") {
                        Button("Bare floor") { draft.sceneID = nil }
                        ForEach(scenes.scenes) { s in
                            Button(s.name) { draft.sceneID = s.id }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Throw away this motion?", isPresented: $confirmingDiscard,
                            titleVisibility: .visible) {
            Button("Throw it away", role: .destructive) { reallyDiscard() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(original == nil || (original?.keys.count ?? 0) < 3
                 ? "It has not been saved anywhere else."
                 : "Everything since you opened it will go back to how it was.")
        }
        .onAppear { if original == nil { original = draft } }
        .sheet(item: $outgoing) { out in
            NavigationStack {
                ShareDestinationsView(title: draft.name, file: out.url, message: out.message)
            }
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
        } header: {
            Text("Keyframe")
        } footer: {
            Text("Pick a moment, then move the joints. The robot above shows the keyframe you are editing.")
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

    // MARK: - the timeline

    @ViewBuilder private var timeline: some View {
        Section {
            ForEach(ordered) { key in
                HStack {
                    Text(String(format: "%.2f s", key.time)).font(.subheadline.monospacedDigit())
                    Spacer()
                    Button("Show") {
                        playhead = key.time; isRunning = false
                    }
                    .buttonStyle(.bordered).controlSize(.small)
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
                // a neighbour means adding a keyframe mid-motion changes
                // nothing until you move something — which is the only
                // behaviour that lets you refine a curve.
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
        guard hasUnsavedChanges else { return dismiss() }
        confirmingDiscard = true
    }

    private func reallyDiscard() {
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


