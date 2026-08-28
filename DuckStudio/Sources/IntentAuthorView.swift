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
    @State private var selected: Int = 0
    @State private var panel: Panel = .joints
    @State private var outgoing: Outgoing?
    @State private var failure: String?

    enum Panel: String, CaseIterable, Identifiable {
        case joints = "Pose", timeline = "Keyframes", checks = "Checks"
        var id: String { rawValue }
    }

    private var ordered: [IntentDraft.Key] { draft.keys.sorted { $0.time < $1.time } }
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(draft); dismiss() }
            }
            ToolbarItem(placement: .topBarLeading) {
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
            Picker("Editing", selection: $selected) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { index, key in
                    Text(String(format: "%.2f s", key.time)).tag(index)
                }
            }
            .pickerStyle(.segmented)
            Button {
                // Jump the playhead to the keyframe being edited, so the robot
                // on screen is the pose the sliders move. Editing keyframe 3
                // while looking at keyframe 1 is how somebody drags a joint for
                // a minute and wonders why nothing happens.
                if ordered.indices.contains(selected) { playhead = ordered[selected].time }
                isRunning = false
            } label: { Label("Show this keyframe", systemImage: "eye") }
        } header: {
            Text("Keyframe")
        }

        if ordered.indices.contains(selected) {
            ForEach(JointGroup.all) { group in
                Section {
                    ForEach(group.joints, id: \.self) { joint in
                        JointSlider(control: JointControl(index: joint),
                                    value: binding(joint: joint))
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    group.note.map { Text($0) }
                }
            }
        }
    }

    /// A slider drives ONE joint of ONE keyframe. The keyframe is found by id
    /// rather than by index, because sorting by time means the index moves the
    /// instant somebody drags a keyframe past its neighbour.
    private func binding(joint: Int) -> Binding<Double> {
        let id = ordered[selected].id
        return Binding(
            get: {
                draft.keys.first { $0.id == id }?.pose[joint]
                    ?? JointControl(index: joint).home
            },
            set: { value in
                guard let index = draft.keys.firstIndex(where: { $0.id == id }) else { return }
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
                draft.keys.append(.init(time: time, pose: draft.pose(at: playhead)))
                selected = draft.keys.sorted { $0.time < $1.time }
                    .firstIndex { $0.time == time } ?? selected
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


