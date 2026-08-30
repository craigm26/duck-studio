import SwiftUI
import DuckKit
import StudioKit

/// The places you can put the robot.
struct SceneListView: View {
    @ObservedObject var store: SceneStore
    /// On an id, not a copy — see `DraftID`. Holding the scene meant the sheet
    /// carried a value that went stale on the first slider tick.
    @State private var editing: SceneID?

    var body: some View {
        List {
            Section {
                Text("A scene is the world a motion is played against: the floor, the steps, the walls. Build one here, then open any intent and play it somewhere other than where it was recorded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                ForEach(store.scenes) { scene in
                    Button { editing = SceneID(id: scene.id) } label: { row(scene) }
                        .buttonStyle(.plain)
                }
                .onDelete { store.delete(at: $0) }
            }
            Section {
                Button {
                    let fresh = DuckScene(name: "New scene")
                    store.add(fresh)
                    editing = SceneID(id: fresh.id)
                } label: { Label("Empty floor", systemImage: "plus") }
                Button {
                    let stairs = DuckScene.staircase()
                    store.add(stairs)
                    editing = SceneID(id: stairs.id)
                } label: { Label("A flight of steps", systemImage: "stairs") }
                Button {
                    let corridor = DuckScene.corridor()
                    store.add(corridor)
                    editing = SceneID(id: corridor.id)
                } label: { Label("A corridor", systemImage: "rectangle.split.3x1") }
            } header: {
                Text("Start from")
            } footer: {
                Text("The staircase starts at \(Int(DuckScene.measuredStepCeiling * 1000)) mm a step, because that is what the robot has been measured to clear. Raise it and the editor will say so.")
            }
        }
        .navigationTitle("Scenes")
        .sheet(item: $editing) { wrapper in
            NavigationStack {
                if let current = store.scenes.first(where: { $0.id == wrapper.id }) {
                    SceneEditorView(scene: current) { store.update($0) }
                        .onDisappear { store.flush() }
                }
            }
        }
    }

    private func row(_ scene: DuckScene) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(scene.name).font(.subheadline.weight(.medium))
                Spacer()
                if scene.problems.contains(where: { $0.severity == .broken }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                } else if scene.problems.contains(where: { $0.severity == .unreachable }) {
                    Image(systemName: "figure.fall").font(.caption2).foregroundStyle(.orange)
                }
            }
            Text(scene.summary).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Build a place, with the robot standing in it.
///
/// THE ROBOT IS ON SCREEN WHILE YOU EDIT, at the size it really is. Every
/// number in this editor is a distance relative to a 250 mm tall machine, and
/// typing "0.3" into a field with nothing beside it is how somebody ends up
/// with a staircase four times the height of the thing meant to climb it.
struct SceneEditorView: View {
    @State var scene: DuckScene
    let onChange: (DuckScene) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var orbit = OrbitState()
    @State private var original: DuckScene?
    @State private var confirmingDiscard = false
    @State private var stance: Stance = .standing

    /// Where to stand the robot while the scene is being built.
    private enum Stance: Hashable { case standing, onTopStep }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                DuckStage(pose: preview, environment: scene.environment, props: scene.props, orbit: $orbit)
                // The stage draws the props; the caption has to count them, or
                // a floor with a broom, a dowel and a pencil on it is captioned
                // "bare floor" with all three visible above the words.
                StageLegend(pose: preview, environment: scene.environment,
                            props: scene.props, orbit: $orbit)
            }
            .frame(maxHeight: 300)

            List {
                if !scene.problems.isEmpty {
                    Section("Before you use this") {
                        ForEach(Array(scene.problems.enumerated()), id: \.offset) { _, problem in
                            Label {
                                Text(problem.text).font(.footnote)
                            } icon: {
                                Image(systemName: problem.severity == .broken
                                      ? "exclamationmark.triangle.fill" : "figure.fall")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section("Scene") {
                    TextField("Name", text: $scene.name)
                    Toggle("Floor", isOn: $scene.ground)
                    Text(scene.provenance).font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ForEach($scene.steps) { $step in
                        StepEditor(step: $step)
                    }
                    .onDelete { scene.steps.remove(atOffsets: $0) }
                    Button {
                        let next = (scene.steps.map(\.top).max() ?? 0) + DuckScene.measuredStepCeiling
                        let x = (scene.steps.map(\.x).max() ?? 0.13) + 0.28
                        scene.steps.append(.init(x: x, y: 0, top: next,
                                                 halfHeight: max(0.10, next)))
                    } label: { Label("Add a step", systemImage: "plus") }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Height is the top face, above the floor. A new step is added one \(Int(DuckScene.measuredStepCeiling * 1000)) mm rise above the tallest one already there.")
                }

                Section {
                    ForEach($scene.walls) { $wall in
                        WallEditor(wall: $wall)
                    }
                    .onDelete { scene.walls.remove(atOffsets: $0) }
                    Button {
                        scene.walls.append(.init(x: 0, y: 0.6))
                    } label: { Label("Add a wall", systemImage: "plus") }
                } header: {
                    Text("Walls")
                }

                Section {
                    ForEach($scene.props) { $prop in
                        PropEditor(prop: $prop)
                    }
                    .onDelete { scene.props.remove(atOffsets: $0) }
                    Menu {
                        ForEach(DuckScene.graspables, id: \.name) { entry in
                            Button(entry.name) { scene.props.append(entry.make()) }
                        }
                    } label: {
                        Label("Add something to pick up", systemImage: "plus")
                    }
                } header: {
                    Text("Things in it")
                } footer: {
                    Text("Steps and walls are what a motion is judged AGAINST — you fall off them. A prop is what a motion is FOR. Every number here describes YOUR object, not the robot: what it weighs and how thick it is decide whether the job is possible, and the robot's own limits are measured and live elsewhere.")
                }

                Section {
                    Picker("Show the robot", selection: $stance) {
                        Text("Standing").tag(Stance.standing)
                        Text("On the top step").tag(Stance.onTopStep)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Putting the robot where the motion is supposed to end is the quickest way to see whether the scene is the size you meant.")
                }
            }
        }
        .navigationTitle("Edit scene")
        .navigationBarTitleDisplayMode(.inline)
        // TWO WAYS OUT, BOTH ALWAYS PRESENT — and Done only dismisses, because
        // every change is already written. Publishing to the store and
        // dismissing in the same tick makes the presenting list re-render while
        // the sheet is going away.
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    guard original != scene, original != nil else { return dismiss() }
                    confirmingDiscard = true
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
        .confirmationDialog("Throw away these changes?", isPresented: $confirmingDiscard,
                            titleVisibility: .visible) {
            Button("Throw them away", role: .destructive) {
                if let original { scene = original; onChange(original) }
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear { if original == nil { original = scene } }
        .onChange(of: scene) { _, new in onChange(new) }
    }

    /// The robot standing on the highest step, which is what a stair scene is
    /// being built to make possible.
    private var preview: StagePose {
        guard stance == .onTopStep,
              let top = scene.steps.max(by: { $0.top < $1.top }) else { return .home }
        return .onTop(of: top)
    }
}

/// A scene's identity, so a sheet can be presented on something stable.
struct SceneID: Identifiable, Hashable {
    let id: UUID
}

private struct StepEditor: View {
    @Binding var step: DuckScene.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Top").font(.caption)
                Spacer()
                Text("\(Int((step.top * 1000).rounded())) mm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(step.top > DuckScene.measuredStepCeiling ? .orange : .secondary)
            }
            Slider(value: $step.top, in: 0.002...0.30)
            HStack {
                Text("Distance").font(.caption)
                Spacer()
                Text("\(Int((step.x * 1000).rounded())) mm").font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $step.x, in: 0.05...1.6)
            HStack {
                Text("Depth").font(.caption)
                Spacer()
                Text("\(Int((step.halfDepth * 2000).rounded())) mm")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $step.halfDepth, in: 0.04...0.4)
        }
        // A step is only solid down to the floor if its body reaches it, and a
        // slider that moved the top without the body would make every step
        // above 200 mm float.
        .onChange(of: step.top) { _, new in
            step.halfHeight = max(step.halfHeight, new / 2)
        }
    }
}

private struct WallEditor: View {
    @Binding var wall: DuckScene.Wall

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("To the side").font(.caption)
                Spacer()
                Text("\(Int((wall.y * 1000).rounded())) mm")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $wall.y, in: -1.5...1.5)
            HStack {
                Text("Height").font(.caption)
                Spacer()
                Text("\(Int((wall.height * 1000).rounded())) mm")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $wall.height, in: 0.05...1.0)
        }
    }
}

/// One prop, and what the duck would make of it.
///
/// THE VERDICT IS THE POINT. Anyone can type 600 grams; what they cannot do is
/// know that 600 g is past the lift but inside the pull, or that a 7 mm pencil
/// passes under a jaw that shuts 20 mm above the floor. The row says so as the
/// numbers change, which is how somebody learns the robot without reading a
/// datasheet.
private struct PropEditor: View {
    @Binding var prop: DuckScene.Prop

    var body: some View {
        DisclosureGroup {
            HStack {
                Text("Weight")
                Spacer()
                Text(String(format: "%.0f g", prop.grams)).foregroundStyle(.secondary)
            }
            Slider(value: $prop.grams, in: 1...2000, step: 1)
            HStack {
                Text("Thickness where it bites")
                Spacer()
                Text(String(format: "%.0f mm", prop.thicknessMillimetres))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $prop.thicknessMillimetres, in: 2...120, step: 1)
            Toggle("Standing up", isOn: Binding(
                get: { prop.graspHeightMillimetres != nil },
                set: { prop.graspHeightMillimetres = $0 ? 150 : nil }))
            if let height = prop.graspHeightMillimetres {
                HStack {
                    Text("Gripped")
                    Spacer()
                    Text(String(format: "%.0f mm up", height)).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { height },
                                      set: { prop.graspHeightMillimetres = $0 }),
                       in: Retrieval.Reach.lowestDuringPick * 1000
                           ... Retrieval.Reach.highestDuringPick * 1000, step: 5)
                Text(Retrieval.Reach.graspTime(forHeight: height / 1000)
                        .map { String(format: "The mouth passes that height %.2f s into a ground pick — that is when the jaw shuts.", $0) }
                     ?? "Outside the arc the mouth sweeps.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("How well it slides")
                Spacer()
                Text(String(format: "%.2f", prop.floorFriction)).foregroundStyle(.secondary)
            }
            Slider(value: $prop.floorFriction, in: 0.1...1.2, step: 0.05)
            verdict
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(prop.name)
                Text(String(format: "%.0f g · %.0f mm · %.2f m away",
                            prop.grams, prop.thicknessMillimetres, prop.metresAway))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var verdict: some View {
        let plan = prop.plan
        return VStack(alignment: .leading, spacing: 4) {
            Label(plan.isPossible ? "It could do this" : "It could not do this",
                  systemImage: plan.isPossible ? "checkmark.seal" : "xmark.octagon")
                .font(.footnote)
                .foregroundStyle(plan.isPossible ? Color.green : Color.orange)
            ForEach(plan.refusals, id: \.message) { refusal in
                Text(refusal.message).font(.caption2)
                    .foregroundStyle(refusal.isFatal ? Color.orange : Color.secondary)
            }
        }
    }
}
