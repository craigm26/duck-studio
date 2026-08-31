import SwiftUI
import DuckKit
import StudioKit

/// The places you can put the robot.
struct SceneListView: View {
    @ObservedObject var store: SceneStore
    /// Held only to hand to Settings from this tab's gear. Passing stores by
    /// hand is the house style here.
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore
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
        // ONE GEAR, SAME PLACE, SAME WORD, ON ALL FIVE TAB ROOTS.
        // Configuration was scattered across three tabs and nothing was called
        // "Settings", which is the first word anybody looks for.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(models: models, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
        .sheet(item: $editing) { wrapper in
            NavigationStack {
                if let current = store.scenes.first(where: { $0.id == wrapper.id }) {
                    SceneEditorView(scene: current) { store.update($0) }
                        .onDisappear { store.flush() }
                } else {
                    // Same missing `else` as the chat's preview sheet: a scene
                    // deleted while its editor was opening left a blank sheet
                    // with nothing to tap.
                    ContentUnavailableView {
                        Label("That scene is not here", systemImage: "questionmark.square.dashed")
                    } description: {
                        Text("It was being opened and is no longer in your scenes. Nothing that "
                           + "was saved has been lost.")
                    } actions: {
                        Button("Close") { editing = nil }
                    }
                }
            }
        }
    }

    private func row(_ scene: DuckScene) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(scene.name).font(.subheadline.weight(.medium))
                Spacer()
                // THE BADGE IS THE ONLY WARNING ON THIS ROW, and an unlabelled
                // orange triangle is nothing at all to somebody who cannot see
                // it — the summary underneath counts steps and props and never
                // says a scene is broken. The label is the kit's own sentence
                // for the first problem of that severity, which is the same
                // sentence the editor prints once the row is opened. `first`
                // rather than `contains` only so there is something to quote;
                // the two predicates pick the same rows.
                if let broken = scene.problems.first(where: { $0.severity == .broken }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        .accessibilityLabel(Text(broken.text))
                } else if let unreachable = scene.problems.first(where: { $0.severity == .unreachable }) {
                    Image(systemName: "figure.fall").font(.caption2).foregroundStyle(.orange)
                        .accessibilityLabel(Text(unreachable.text))
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

    /// AN EXPLICIT INIT, BECAUSE THE NAME FIELD HAS TO BE SEEDED BEFORE THE
    /// FIRST BODY PASS. `.onAppear` runs after it, so seeding there put the
    /// "a scene with no name" refusal under a blank field for one frame every
    /// time this sheet opened — a warning about a state the person had not
    /// caused. Seeding both `@State`s here means the first thing drawn is the
    /// scene as it is.
    init(scene: DuckScene, onChange: @escaping (DuckScene) -> Void) {
        _scene = State(initialValue: scene)
        _typed = State(initialValue: scene.name)
        self.onChange = onChange
    }

    @Environment(\.dismiss) private var dismiss
    @State private var orbit = OrbitState()
    @State private var original: DuckScene?
    @State private var confirmingDiscard = false
    @State private var stance: Stance = .standing
    /// WHAT IS IN THE FIELD, WHICH IS NOT ALWAYS WHAT THE SCENE IS CALLED. The
    /// field used to bind straight to `scene.name`, so deleting the last
    /// character left the store holding a scene called "" — a blank, unpickable
    /// row in four separate menus. Buffering it here means an empty field is a
    /// state of the keyboard rather than a state of the library: nothing
    /// reaches the store until `SceneName` allows it.
    /// SEEDED FROM THE SCENE, NOT FROM EMPTY. `.onAppear` runs AFTER the first
    /// body pass, so an empty seed put the "a scene with no name" refusal on
    /// screen under a blank field for one frame every time the editor opened —
    /// a warning about a state the person had not caused and could not see the
    /// cause of. The initial value is the name the sheet was opened on.
    @State private var typed: String

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
                    TextField("Name", text: $typed)
                    if let refusal = SceneName.refusal(typed, keeping: scene.name) {
                        Text(refusal).font(.caption).foregroundStyle(.orange)
                    }
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
        // THE LIVE NAME, NOT "EDIT SCENE". This is the screen a rename happens
        // on, and a constant title is a screen that cannot answer "did that
        // take?" — the question the whole store-write path exists to answer.
        // A `String` variable, so it is drawn verbatim rather than looked up as
        // a localization key. No empty branch: `SceneName` keeps the name from
        // ever being blank, so a fallback here would be dead code claiming
        // otherwise.
        .navigationTitle(scene.name)
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
                // The field is put back too, not only the scene: it is a
                // separate piece of state now, and leaving it holding a
                // discarded name would be the screen showing an edit that no
                // longer exists.
                if let original { scene = original; typed = original.name; onChange(original) }
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear { if original == nil { original = scene } }
        // Committed per keystroke, exactly as the field did when it bound
        // straight to the scene — the 0.4 s settle in the store is what keeps
        // that cheap. The only difference is the gate: a name the kit refuses
        // stays in the field and never becomes the scene's.
        .onChange(of: typed) { _, new in
            if SceneName.refusal(new, keeping: scene.name) == nil { scene.name = new }
        }
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

    // ONE EXPRESSION PER NUMBER, PRINTED AND SPOKEN FROM THE SAME PLACE. A
    // spoken value that rounds differently from the printed one is a second
    // source of truth for a distance the robot is measured against, and the
    // person who cannot see the printed one has no way to catch the drift.
    private var topMillimetres: String { "\(Int((step.top * 1000).rounded())) mm" }
    private var distanceMillimetres: String { "\(Int((step.x * 1000).rounded())) mm" }
    private var depthMillimetres: String { "\(Int((step.halfDepth * 2000).rounded())) mm" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // THE NAME AND THE NUMBER ARE HIDDEN HERE AND CARRIED BY THE SLIDER
            // INSTEAD, on all three rows. A Slider is its own accessibility
            // element with the adjustable trait, so a name sitting in a sibling
            // HStack never reaches it: without this VoiceOver reads three
            // identical "52 percent, adjustable" controls, and reading the row
            // above as well would say every number twice while still leaving
            // the control itself anonymous.
            HStack {
                Text("Top").font(.caption)
                Spacer()
                Text(topMillimetres)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(step.top > DuckScene.measuredStepCeiling ? .orange : .secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $step.top, in: 0.002...0.30)
                .accessibilityLabel(Text("Top"))
                .accessibilityValue(Text(topMillimetres))
            HStack {
                Text("Distance").font(.caption)
                Spacer()
                Text(distanceMillimetres).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $step.x, in: 0.05...1.6)
                .accessibilityLabel(Text("Distance"))
                .accessibilityValue(Text(distanceMillimetres))
            HStack {
                Text("Depth").font(.caption)
                Spacer()
                Text(depthMillimetres)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $step.halfDepth, in: 0.04...0.4)
                .accessibilityLabel(Text("Depth"))
                .accessibilityValue(Text(depthMillimetres))
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

    /// Printed and spoken from one expression, for the reason `StepEditor`
    /// gives: a wall that passes through where the robot starts is a broken
    /// scene, and the distance is the only thing that says so before it does.
    private var sidewaysMillimetres: String { "\(Int((wall.y * 1000).rounded())) mm" }
    private var heightMillimetres: String { "\(Int((wall.height * 1000).rounded())) mm" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("To the side").font(.caption)
                Spacer()
                Text(sidewaysMillimetres)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $wall.y, in: -1.5...1.5)
                .accessibilityLabel(Text("To the side"))
                .accessibilityValue(Text(sidewaysMillimetres))
            HStack {
                Text("Height").font(.caption)
                Spacer()
                Text(heightMillimetres)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $wall.height, in: 0.05...1.0)
                .accessibilityLabel(Text("Height"))
                .accessibilityValue(Text(heightMillimetres))
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

    // Printed and spoken from one expression each. These four numbers decide
    // the verdict at the bottom of the group — 600 g is past the lift and
    // inside the pull — so a spoken value that disagreed with the printed one
    // would be disagreeing with the refusal it caused.
    private var weight: String { String(format: "%.0f g", prop.grams) }
    private var thickness: String { String(format: "%.0f mm", prop.thicknessMillimetres) }
    private var friction: String { String(format: "%.2f", prop.floorFriction) }
    private func gripped(_ height: Double) -> String {
        String(format: "%.0f mm up", height)
    }

    var body: some View {
        DisclosureGroup {
            HStack {
                Text("Weight")
                Spacer()
                Text(weight).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $prop.grams, in: 1...2000, step: 1)
                .accessibilityLabel(Text("Weight"))
                .accessibilityValue(Text(weight))
            HStack {
                Text("Thickness where it bites")
                Spacer()
                Text(thickness)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $prop.thicknessMillimetres, in: 2...120, step: 1)
                .accessibilityLabel(Text("Thickness where it bites"))
                .accessibilityValue(Text(thickness))
            Toggle("Standing up", isOn: Binding(
                get: { prop.graspHeightMillimetres != nil },
                set: { prop.graspHeightMillimetres = $0 ? 150 : nil }))
            if let height = prop.graspHeightMillimetres {
                HStack {
                    Text("Gripped")
                    Spacer()
                    Text(gripped(height)).foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
                Slider(value: Binding(get: { height },
                                      set: { prop.graspHeightMillimetres = $0 }),
                       in: Retrieval.Reach.lowestDuringPick * 1000
                           ... Retrieval.Reach.highestDuringPick * 1000, step: 5)
                    .accessibilityLabel(Text("Gripped"))
                    .accessibilityValue(Text(gripped(height)))
                // The sentence under the slider is left audible: it is the
                // kit's answer to what this height MEANS — when the jaw shuts
                // — and it is not a repeat of anything the slider now says.
                Text(Retrieval.Reach.graspTime(forHeight: height / 1000)
                        .map { String(format: "The mouth passes that height %.2f s into a ground pick — that is when the jaw shuts.", $0) }
                     ?? "Outside the arc the mouth sweeps.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("How well it slides")
                Spacer()
                Text(friction).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $prop.floorFriction, in: 0.1...1.2, step: 0.05)
                .accessibilityLabel(Text("How well it slides"))
                .accessibilityValue(Text(friction))
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
