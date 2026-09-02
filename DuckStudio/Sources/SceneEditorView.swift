import SwiftUI
import DuckKit
import StudioKit

// MARK: - the numbers and words these screens write down for themselves

/// Dimensions that are layout decisions rather than facts.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST — the same line `Theme` draws and this
/// file stays behind. A ratio is a fact about two colours and lives in `Palette`
/// where `swift test` runs the WCAG formula over it; how tall to let a viewport
/// get is a judgement about a phone, and it belongs beside the view that made it.
private enum SceneMetric {
    /// The stage viewport's card. The legend drawn inside it takes
    /// `viewport.inner` — which is how the concentric rule is expressed rather
    /// than asserted: pick a different outer radius and the inner one follows.
    static let viewport = Palette.Radius.group

    /// How much of the screen the robot is allowed while a scene is being built.
    /// Above this the editor's own sliders stop fitting on a small phone; below
    /// it the duck is a thumbnail of a duck, and the whole argument for drawing
    /// it at all is that a number typed into a field means nothing without a
    /// 250 mm machine standing beside it.
    static let viewportHeight: CGFloat = 300

    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke = DesignMetric.hairlineStroke
}

/// The units this editor prints, written once each.
///
/// ONE SPELLING PER UNIT, PRINTED AND SPOKEN FROM THE SAME LETTERS.
/// `TelemetryRow` draws the value and the unit as two pieces; the slider beneath
/// it announces them as one string. Writing "mm" twice is how a row ends up
/// showing millimetres while the control under it says something else.
private enum SceneUnit {
    static let millimetres = "mm"
    static let grams = "g"
}

/// The value and its unit, joined the way `TelemetryRow` joins them for
/// VoiceOver — so a slider can never announce a number the row above it is not
/// showing, or show it in a unit the row does not name.
private func spoken(_ value: String, _ unit: String) -> String { "\(value) \(unit)" }

/// How a scene's problems are drawn.
///
/// THE SEVERITY IS THE KIT'S AND SO IS THE WORD. `DuckScene.Problem.Severity`
/// is a two-case enum whose raw values are the words themselves, so nothing here
/// invents a vocabulary for how wrong a scene is — it chooses a symbol and a
/// token for each, which is a drawing decision and the only kind this file is
/// allowed to make.
///
/// BROKEN IS A REFUSAL AND UNREACHABLE IS A WARNING, and the palette keeps those
/// apart on purpose. A broken scene cannot be drawn or played as written, which
/// is the app saying no; an unreachable one draws perfectly and the robot will
/// not manage it, which is the app saying this will not work. Drawn in one
/// colour they become the same message, and the one a person can safely ignore
/// teaches them to ignore the other.
private extension DuckScene.Problem.Severity {
    var tint: Color {
        switch self {
        case .broken: return Theme.refused
        case .unreachable: return Theme.warning
        }
    }

    var symbol: String {
        switch self {
        case .broken: return "exclamationmark.triangle.fill"
        case .unreachable: return "figure.fall"
        }
    }

    /// The severity as a word. The kit's own raw value, with a capital on it
    /// because it starts a label rather than because it means anything more.
    var word: String { rawValue.capitalized }
}

/// The places you can put the robot.
struct SceneListView: View {
    @ObservedObject var store: SceneStore
    /// HELD AND NOT READ, WHICH IS DELIBERATE AND SHOULD NOT LAST. Both of
    /// these existed to hand to Settings from this screen's own gear, and the
    /// gear is gone — Scenes is a row inside Studio now, and Studio's root
    /// carries the one gear. They stay because `StudioHubView` constructs this
    /// view exactly as the old shell did, and because the editor sheet this
    /// screen opens is the obvious next place a model or a bench is wanted.
    /// Whoever needs neither should delete both and the argument labels with
    /// them, in one change rather than by removing the call site first.
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore
    /// On an id, not a copy — see `DraftID`. Holding the scene meant the sheet
    /// carried a value that went stale on the first slider tick.
    @State private var editing: SceneID?

    var body: some View {
        List {
            Section {
                Text("A scene is the world a motion is played against: the floor, the steps, the walls. Build one here, then open any intent and play it somewhere other than where it was recorded.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
            Section {
                ForEach(store.scenes) { scene in
                    Button { editing = SceneID(id: scene.id) } label: { row(scene) }
                        .buttonStyle(.plain)
                }
                .onDelete { store.delete(at: $0) }
            }
            .listRowBackground(Theme.surfacePrimary)
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
                SectionHeading(text: "Start from")
            } footer: {
                // THE KIT'S SENTENCE, because the one that was here — "that is what the
                // robot has been measured to clear" — was false: nothing has been
                // measured to clear 10 mm, and the check cannot see a step that small.
                // AND THE WHOLE CLAIM WITH ITS CAVEATS IN THE SAME BREATH, plus why
                // the count this footer used to carry is gone: an earlier audit's
                // staircase pushed its own blocks apart and measured itself.
                VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                    Text(StepCeiling.current.editorSentence)
                        .foregroundStyle(Theme.textSecondary)
                    Text(StepCeiling.current.says)
                        .foregroundStyle(Theme.textSecondary)
                    Text(StepCeiling.current.whyTheOldCountIsGone)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY.
        // `backgroundSecondary` is the token `Theme` documents as a ground for
        // surfaces rather than for words, which is exactly what a grouped list
        // is: every row keeps a real `surfacePrimary` card under it, so nothing
        // is ever set on the ground the palette says is short of 4.5:1.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Scenes")
        // NO GEAR HERE ANY MORE. ONE PER TAB ROOT, AND THIS IS NO LONGER ONE.
        // Scenes is a row inside Studio, whose own root carries the gear — so a
        // gear here put two of them one tap apart, in the same corner, leading
        // to the same screen, which reads as two different Settings until
        // somebody opens both to find out.
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

    /// The first problem worth showing on the row: a broken scene outranks an
    /// unreachable one, because a scene that cannot be drawn is not a scene the
    /// robot is going to fail to climb.
    ///
    /// `first` RATHER THAN `contains`, only so there is something to quote. The
    /// two predicates pick the same rows.
    private func headline(_ scene: DuckScene) -> DuckScene.Problem? {
        scene.problems.first { $0.severity == .broken }
            ?? scene.problems.first { $0.severity == .unreachable }
    }

    private func row(_ scene: DuckScene) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack {
                Text(scene.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.spacing(.tight))
                // THE WORD IS BACK BESIDE THE MARK. This was a bare orange
                // triangle, which is a state carried entirely in a colour: two
                // different severities were drawn in the same orange, and to
                // anybody who cannot separate that orange from the ink beside
                // it the row said nothing at all — the summary underneath counts
                // steps and props and never mentions that the scene is broken.
                // Now the severity is a word, its own token, and its own symbol,
                // which is three signals where there was one.
                //
                // THE SENTENCE IS STILL THE VALUE. The word says how wrong;
                // the kit's own text says what is wrong, and it is the same
                // sentence the editor prints once the row is opened.
                if let problem = headline(scene) {
                    Label(problem.severity.word, systemImage: problem.severity.symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(problem.severity.tint)
                        .lineLimit(1)
                        // THE SENTENCE, NOT THE WORD, BECAUSE THIS SITS INSIDE A
                        // BUTTON. A row is one tappable element and VoiceOver
                        // joins what its children say into a single utterance,
                        // so a value set here would be dropped in the joining and
                        // the word alone would tell somebody the scene is broken
                        // without telling them how. The kit's sentence is what
                        // the old bare triangle announced and it stays.
                        .accessibilityLabel(Text(problem.text))
                }
            }
            Text(scene.summary).font(.caption).foregroundStyle(Theme.textSecondary)
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
    /// So the viewport can stop clipping at accessibility sizes — see `stage`.
    @Environment(\.dynamicTypeSize) private var typeSize
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
            stage
            List {
                if !scene.problems.isEmpty {
                    Section {
                        ForEach(Array(scene.problems.enumerated()), id: \.offset) { _, problem in
                            // THE SEVERITY IS A WORD BEFORE IT IS A COLOUR, on
                            // the same argument the list row makes: broken and
                            // unreachable used to be one orange, so the two
                            // could not be told apart at all without reading
                            // both sentences to the end. The word leads, the
                            // kit's sentence follows, and the token separates
                            // a refusal from a warning for anybody who can see
                            // the difference.
                            Label {
                                VStack(alignment: .leading,
                                       spacing: Theme.spacing(.hairline)) {
                                    Text(problem.severity.word)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(problem.severity.tint)
                                    Text(problem.text)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } icon: {
                                Image(systemName: problem.severity.symbol)
                                    .foregroundStyle(problem.severity.tint)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        SectionHeading(text: "Before you use this")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                Section {
                    TextField("Name", text: $typed)
                    if let refusal = SceneName.refusal(typed, keeping: scene.name) {
                        // A REFUSAL, IN THE REFUSAL COLOUR. `Theme.refused` is
                        // the palette's own word for this — the app has been
                        // handed a name and will not take it — and it is a
                        // different token from the warning the problems above
                        // carry, because a name this editor rejects is not the
                        // same kind of trouble as a step the robot cannot climb.
                        Text(refusal).font(.caption).foregroundStyle(Theme.refused)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Floor", isOn: $scene.ground)
                    Text(scene.provenance).font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionHeading(text: "Scene")
                }
                .listRowBackground(Theme.surfacePrimary)

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
                    SectionHeading(text: "Steps")
                } footer: {
                    Text("Height is the top face, above the floor. A new step is added one \(Int(DuckScene.measuredStepCeiling * 1000)) mm rise above the tallest one already there.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    ForEach($scene.walls) { $wall in
                        WallEditor(wall: $wall)
                    }
                    .onDelete { scene.walls.remove(atOffsets: $0) }
                    Button {
                        scene.walls.append(.init(x: 0, y: 0.6))
                    } label: { Label("Add a wall", systemImage: "plus") }
                } header: {
                    SectionHeading(text: "Walls")
                }
                .listRowBackground(Theme.surfacePrimary)

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
                    SectionHeading(text: "Things in it")
                } footer: {
                    Text("Steps and walls are what a motion is judged AGAINST — you fall off them. A prop is what a motion is FOR. Every number here describes YOUR object, not the robot: what it weighs and how thick it is decide whether the job is possible, and the robot's own limits are measured and live elsewhere.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    Picker("Show the robot", selection: $stance) {
                        Text("Standing").tag(Stance.standing)
                        Text("On the top step").tag(Stance.onTopStep)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Putting the robot where the motion is supposed to end is the quickest way to see whether the scene is the size you meant.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
            // GREY — every row keeps a real `surfacePrimary` card under it, so
            // nothing is ever set on the ground the palette says is short of
            // 4.5:1 for words.
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
        }
        .background(Theme.backgroundPrimary)
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

    /// The viewport: the robot in the place being built, with the legend
    /// floating on it.
    ///
    /// A CARD, WITH THE LEGEND AS A CARD INSIDE IT. The radii are concentric —
    /// `Palette.Radius.group` outside and `.inner`, which is `.card`, within, the
    /// value `StageLegend` takes for its own panel — so the corner of the caption
    /// is drawn at the next step down rather than at whatever looked right. Two
    /// radii chosen independently read as two stacked rectangles; two radii a
    /// step apart read as one machined part.
    ///
    /// NOT CAPPED AT ACCESSIBILITY SIZES. The legend stacks its label-over-value
    /// rows when the text is large, and a fixed 300-point viewport would then
    /// clip exactly that reflow — hiding the millimetres from the people who
    /// enlarged them in order to read them. The duck shrinks to make room; the
    /// words do not disappear.
    private var stage: some View {
        ZStack(alignment: .bottomLeading) {
            DuckStage(pose: preview, environment: scene.environment,
                      props: scene.props, orbit: $orbit)
            // The stage draws the props; the caption has to count them, or
            // a floor with a broom, a dowel and a pencil on it is captioned
            // "bare floor" with all three visible above the words.
            StageLegend(pose: preview, environment: scene.environment,
                        props: scene.props, orbit: $orbit)
        }
        .frame(maxHeight: typeSize.isAccessibilitySize ? nil : SceneMetric.viewportHeight)
        .clipShape(viewport)
        .overlay(viewport.strokeBorder(Theme.separator,
                                       lineWidth: SceneMetric.hairlineStroke))
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.top, Theme.spacing(.tight))
        .padding(.bottom, Theme.spacing(.tight))
    }

    private var viewport: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(SceneMetric.viewport),
                         style: .continuous)
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

/// One step, and the three distances that describe it.
///
/// THE ROWS ARE `TelemetryRow`S NOW, AND THAT IS NOT A COSMETIC SWAP. Each of
/// these numbers changes under a thumb, which is the app's whole definition of
/// telemetry: label in SF beside a value in tabular figures, so 9 mm replaced by
/// 11 mm does not shift the row, and stacked rather than truncated when the text
/// is large. Hand-drawn as `HStack { Text; Spacer; Text }` they were the pair
/// that loses the fight for the width at AX5 — and the half that loses is always
/// the number, on the right, which is to say the app hid the millimetres from
/// the person who most enlarged them.
///
/// THE ORANGE ON "TOP" IS GONE ON PURPOSE, and it is a correctness fix rather
/// than a restyle. It coloured the number when `step.top` exceeded
/// `measuredStepCeiling` — an ABSOLUTE height check — while `DuckScene.problems`
/// judges a flight by each step's RISE ABOVE THE ONE BEFORE IT and says in its
/// own comment why the absolute check is wrong: ten 10 mm steps are climbable
/// and 100 mm tall, one 100 mm block is not, and an absolute test calls them the
/// same thing. So a legal staircase's top steps were drawn in a warning colour
/// with nothing in the Problems section agreeing. The kit's verdict is the only
/// one on screen now, and it is a sentence rather than a hue.
private struct StepEditor: View {
    @Binding var step: DuckScene.Step

    // ONE EXPRESSION PER NUMBER, PRINTED AND SPOKEN FROM THE SAME PLACE. A
    // spoken value that rounds differently from the printed one is a second
    // source of truth for a distance the robot is measured against, and the
    // person who cannot see the printed one has no way to catch the drift.
    // The unit is separate because `TelemetryRow` sets it half-size beside the
    // digits; `spoken` puts the two back together for the slider.
    private var topMillimetres: String { "\(Int((step.top * 1000).rounded()))" }
    private var distanceMillimetres: String { "\(Int((step.x * 1000).rounded()))" }
    private var depthMillimetres: String { "\(Int((step.halfDepth * 2000).rounded()))" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            // THE NAME AND THE NUMBER ARE HIDDEN HERE AND CARRIED BY THE SLIDER
            // INSTEAD, on all three rows. A Slider is its own accessibility
            // element with the adjustable trait, so a name sitting in a sibling
            // row never reaches it: without this VoiceOver reads three
            // identical "52 percent, adjustable" controls, and reading the row
            // above as well would say every number twice while still leaving
            // the control itself anonymous.
            TelemetryRow(label: "Top", value: topMillimetres,
                         unit: SceneUnit.millimetres)
                .accessibilityHidden(true)
            Slider(value: $step.top, in: 0.002...0.30)
                .accessibilityLabel(Text("Top"))
                .accessibilityValue(Text(spoken(topMillimetres, SceneUnit.millimetres)))
            TelemetryRow(label: "Distance", value: distanceMillimetres,
                         unit: SceneUnit.millimetres)
                .accessibilityHidden(true)
            Slider(value: $step.x, in: 0.05...1.6)
                .accessibilityLabel(Text("Distance"))
                .accessibilityValue(Text(spoken(distanceMillimetres, SceneUnit.millimetres)))
            TelemetryRow(label: "Depth", value: depthMillimetres,
                         unit: SceneUnit.millimetres)
                .accessibilityHidden(true)
            Slider(value: $step.halfDepth, in: 0.04...0.4)
                .accessibilityLabel(Text("Depth"))
                .accessibilityValue(Text(spoken(depthMillimetres, SceneUnit.millimetres)))
        }
        .padding(.vertical, Theme.spacing(.hairline))
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
    private var sidewaysMillimetres: String { "\(Int((wall.y * 1000).rounded()))" }
    private var heightMillimetres: String { "\(Int((wall.height * 1000).rounded()))" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            TelemetryRow(label: "To the side", value: sidewaysMillimetres,
                         unit: SceneUnit.millimetres)
                .accessibilityHidden(true)
            Slider(value: $wall.y, in: -1.5...1.5)
                .accessibilityLabel(Text("To the side"))
                .accessibilityValue(Text(spoken(sidewaysMillimetres, SceneUnit.millimetres)))
            TelemetryRow(label: "Height", value: heightMillimetres,
                         unit: SceneUnit.millimetres)
                .accessibilityHidden(true)
            Slider(value: $wall.height, in: 0.05...1.0)
                .accessibilityLabel(Text("Height"))
                .accessibilityValue(Text(spoken(heightMillimetres, SceneUnit.millimetres)))
        }
        .padding(.vertical, Theme.spacing(.hairline))
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
    // would be disagreeing with the refusal it caused. The unit is carried
    // separately now because `TelemetryRow` sets it half-size beside the
    // digits, and `spoken` joins the two back for the slider.
    private var weight: String { String(format: "%.0f", prop.grams) }
    private var thickness: String { String(format: "%.0f", prop.thicknessMillimetres) }
    private var friction: String { String(format: "%.2f", prop.floorFriction) }
    private func gripped(_ height: Double) -> String {
        String(format: "%.0f", height)
    }

    var body: some View {
        DisclosureGroup {
            TelemetryRow(label: "Weight", value: weight, unit: SceneUnit.grams)
                .accessibilityHidden(true)
            Slider(value: $prop.grams, in: 1...2000, step: 1)
                .accessibilityLabel(Text("Weight"))
                .accessibilityValue(Text(spoken(weight, SceneUnit.grams)))
            TelemetryRow(label: "Thickness where it bites", value: thickness,
                         unit: SceneUnit.millimetres)
                .accessibilityHidden(true)
            Slider(value: $prop.thicknessMillimetres, in: 2...120, step: 1)
                .accessibilityLabel(Text("Thickness where it bites"))
                .accessibilityValue(Text(spoken(thickness, SceneUnit.millimetres)))
            Toggle("Standing up", isOn: Binding(
                get: { prop.graspHeightMillimetres != nil },
                set: { prop.graspHeightMillimetres = $0 ? 150 : nil }))
            if let height = prop.graspHeightMillimetres {
                // "UP" HAS LEFT THE NUMBER, AND THE SENTENCE BELOW STILL SAYS
                // IT. The printed value used to read "150 mm up", which puts a
                // direction inside a unit — and `TelemetryRow` sets the unit at
                // half the digits' size, where a word carrying meaning would be
                // the smallest thing in the group. The label is "Gripped", the
                // unit is millimetres, and what that height MEANS is the kit's
                // sentence two rows down.
                TelemetryRow(label: "Gripped", value: gripped(height),
                             unit: SceneUnit.millimetres)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { height },
                                      set: { prop.graspHeightMillimetres = $0 }),
                       in: Retrieval.Reach.lowestDuringPick * 1000
                           ... Retrieval.Reach.highestDuringPick * 1000, step: 5)
                    .accessibilityLabel(Text("Gripped"))
                    .accessibilityValue(Text(spoken(gripped(height),
                                                    SceneUnit.millimetres)))
                // The sentence under the slider is left audible: it is the
                // kit's answer to what this height MEANS — when the jaw shuts
                // — and it is not a repeat of anything the slider now says.
                Text(Retrieval.Reach.graspTime(forHeight: height / 1000)
                        .map { String(format: "The mouth passes that height %.2f s into a ground pick — that is when the jaw shuts.", $0) }
                     ?? "Outside the arc the mouth sweeps.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // NO UNIT, BECAUSE FRICTION HAS NONE. `TelemetryRow`'s unit defaults
            // to empty and it draws nothing rather than inventing a symbol for a
            // ratio.
            TelemetryRow(label: "How well it slides", value: friction)
                .accessibilityHidden(true)
            Slider(value: $prop.floorFriction, in: 0.1...1.2, step: 0.05)
                .accessibilityLabel(Text("How well it slides"))
                .accessibilityValue(Text(friction))
            verdict
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(prop.name).foregroundStyle(Theme.textPrimary)
                Text(String(format: "%.0f g · %.0f mm · %.2f m away",
                            prop.grams, prop.thicknessMillimetres, prop.metresAway))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the duck would make of this object.
    ///
    /// A CARD INSIDE THE ROW'S CARD, AT THE NEXT RADIUS DOWN. The row is drawn
    /// on `surfacePrimary` at `Palette.Radius.card`; this sits on
    /// `surfaceElevated` at `card.inner`, which is `.control`. It earns the
    /// separation: everything above it in this group is something the person
    /// typed, and this is the only thing in it the app is claiming. Two radii a
    /// step apart read as one machined part; two chosen independently read as
    /// two stacked rectangles.
    ///
    /// `surfaceElevated` RATHER THAN THE RECESSED GROUND. `backgroundSecondary`
    /// is the obvious choice for a nested block and is the wrong one here — the
    /// palette documents it as a ground for SURFACES, with the four coloured
    /// inks landing between 4.17:1 and 4.27:1 on it, short of the 4.5:1 body
    /// text owes. This block is nothing but coloured ink: a green seal, a red
    /// refusal. `surfaceElevated` is a ground the tests prove those against.
    ///
    /// THE COLOURS SAY WHICH KIND OF NO IT IS. A fatal refusal is
    /// `Theme.refused` — the job cannot be done — and a non-fatal one is
    /// ordinary secondary text, because it is a note about the job rather than a
    /// reason it is off. That distinction was drawn in one orange before, so the
    /// note that does not stop anything looked exactly like the one that does.
    private var verdict: some View {
        let plan = prop.plan
        return VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Label(plan.isPossible ? "It could do this" : "It could not do this",
                  systemImage: plan.isPossible ? "checkmark.seal" : "xmark.octagon")
                .font(.footnote.weight(.medium))
                .foregroundStyle(plan.isPossible ? Theme.success : Theme.refused)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(plan.refusals, id: \.message) { refusal in
                // A GLYPH BESIDE THE HUE. Fatal and caution were told apart by colour
                // alone — a person who cannot separate the red from the grey had no way
                // to know which refusals stop the scene and which merely warn.
                Label(refusal.message,
                      systemImage: refusal.isFatal ? "xmark.octagon" : "exclamationmark.triangle")
                    .foregroundStyle(refusal.isFatal ? Theme.refused : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing(.snug))
        .background(Theme.surfaceElevated, in: verdictCard)
        .overlay(verdictCard.strokeBorder(Theme.separator,
                                          lineWidth: SceneMetric.hairlineStroke))
    }

    private var verdictCard: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(Palette.Radius.card.inner),
                         style: .continuous)
    }
}
