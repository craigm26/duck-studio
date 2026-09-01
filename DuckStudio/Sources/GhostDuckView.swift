import SwiftUI
import ARKit
import RealityKit
import Combine
import QuartzCore
import DuckKit
import DuckVisual
import DuckRender
import StudioKit

/// A life-size Microduck standing on your floor, before one exists to stand there.
///
/// WHY A RECORDING AND NOT THE POLICY. The obvious build is to run the trained
/// network here — `DuckSimulation` exists, it loads the real `alpha_walking.onnx`,
/// and it steps at 50 Hz. It does not walk, and it cannot be made to. The policy
/// locks its gait phase to CONTACT, which it reads through the gyro, projected
/// gravity and joint velocities; on a phone with no physics under it all three
/// are constants, so the network gets told the duck is standing perfectly still
/// forever and answers accordingly. Closing that loop produces a 25 Hz flip-flop
/// or a duck slamming into its travel stops, depending on how you fake the
/// velocities — both were measured, neither is a gait.
///
/// So the ghost replays `DuckTrajectory`: joint angles recorded FROM a physics
/// run, sampled continuously. That is not a downgrade. The frames are the
/// policy's own output against real contact, so this is the trained duck
/// walking; the honest description is that the physics happened earlier and
/// somewhere else. `DuckSimulation`'s real job is running the network on
/// observations somebody else measured — a robot over `DuckRPC`, or a trace.
///
/// IT IS THE REAL SHAPE NOW. Earlier this drew the kinematic chain as spheres
/// and bones, because the MJCF DuckKinematics is generated from carries no
/// geometry and Pollen's meshes reached this project by a permission that does
/// not cover redistributing them in an App Store binary. `DuckVisual` fixes
/// both: the same parts, taken instead from the Apache-2.0
/// `pollen-robotics/microduck_rl`, one mesh per body in that body's frame.
///
/// TWO COORDINATE TRAPS, both handled in `DuckGhostEntity`. The robot's model is
/// Z-up (MuJoCo's convention, X forward, Y left) and ARKit is Y-up with -Z
/// forward. And the duck is 25 cm tall in metres, which is also ARKit's unit —
/// so the ghost is placed at 1:1 scale deliberately, not scaled to taste. A
/// ghost you have to squint at to compare against a real robot is not doing the
/// one job it has.
struct GhostDuckView: View {

    @StateObject private var ghost = GhostDuckModel()

    /// The two modes that drive the duck on THIS screen rather than building
    /// one of their own, and so have to be shown over it instead of instead
    /// of it. See the comment on the Trick run button.
    private enum Driving: String, Identifiable {
        case trickRun, flamingo
        var id: String { rawValue }
        var title: String { self == .trickRun ? "Trick run" : "Flamingo hold" }
    }
    @State private var driving: Driving?
    /// FOLLOW ME IS REACHED FROM HERE AND FROM NOWHERE ELSE, so this hub is
    /// where its door is shut. Every other row in the grid below runs on a
    /// stage and does not care whether there is a camera.
    @State private var door = CameraDoor.availability
    /// So the mode grid stops being three columns wide at the sizes where three
    /// columns cannot hold a word — see `columns`.
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The background behind anything on this screen that holds a SENTENCE.
    ///
    /// NOT A CAPSULE, AND THAT IS THE POINT. A Capsule's corners are half its
    /// height, so the moment the text inside it wraps to three lines the ends
    /// become half-circles that eat the first and last words. The status line
    /// here is not always short: `ensure(venue:)` below writes a whole camera
    /// refusal into it, which is four lines on a phone. A fixed radius looks
    /// the same as a capsule on one line and survives five — and it now comes
    /// off the scale, at the step the design system calls a card.
    private static let panel = RoundedRectangle(
        cornerRadius: Theme.radius(GhostMetric.panel), style: .continuous)

    var body: some View {
        ZStack(alignment: .bottom) {
            GhostDuckContainer(model: ghost)
                .ignoresSafeArea()

            VStack(spacing: Theme.spacing(.snug)) {
                Text(ghost.status)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // NO WIDTH CAP AT ACCESSIBILITY SIZES. This line carries a
                    // whole camera refusal, and 340 points at AX5 is a column
                    // of single words hiding the sentence from the person who
                    // enlarged it in order to read it — the same trade
                    // `DriveView` makes on its viewport.
                    .frame(maxWidth: typeSize.isAccessibilitySize ? nil
                                                                  : GhostMetric.panelWidth)
                    .padding(.horizontal, Theme.spacing(.snug))
                    .padding(.vertical, Theme.spacing(.tight))
                    // AN OPAQUE PANEL OVER A LIVE CAMERA, WHICH IS THE WHOLE
                    // ARGUMENT. `.ultraThinMaterial` made the contrast of this
                    // sentence whatever the floor happened to be that frame —
                    // a bright carpet and a dark one are two different numbers
                    // and nothing checks either. `surfacePrimary` is one of the
                    // four grounds `PaletteTests` proves every text token
                    // against at 4.5:1, so the refusal is legible on any floor.
                    .background(Theme.surfacePrimary, in: Self.panel)
                    .overlay(Self.panel.strokeBorder(Theme.separator,
                                                     lineWidth: GhostMetric.hairlineStroke))

                // ONE REFUSAL ON THIS SCREEN, NOT TWO. `VenuePicker` prints its
                // own reason when the camera door is shut, and the Follow me
                // reason is printed under the grid below. Both come from the
                // same `CameraAvailability` blocker, so with the door shut this
                // hub — the only screen in the Lab that draws both — showed the
                // same cause and the same remedy twice, ninety-odd words of
                // caption2 stacked over a seven-cell grid.
                //
                // THE ONE THAT SURVIVES IS FOLLOW ME'S, because it is the one
                // that costs something: the venue sentence's own words are that
                // the mode "plays in its own rendered world instead — which is
                // where it starts anyway", while Follow me is off entirely. So
                // the switch is drawn only while it can be used. With the door
                // shut it has one legal value — `standDownFromAR()` below is
                // what holds it there — and what is left on screen is a dead
                // control repeating a reason that is already below it.
                if door.canOfferAR {
                    VenuePicker(venue: $ghost.venue)
                        .padding(.horizontal, Theme.spacing(.snug))
                        .padding(.vertical, Theme.spacing(.tight))
                        // The switch is two short words and never wraps, so
                        // this one IS allowed to be a capsule — the panel above
                        // is not, and the comment there says why.
                        .background(Theme.surfacePrimary, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.separator,
                                                        lineWidth: GhostMetric.hairlineStroke))
                }

                if ghost.isPlaced {
                    Picker("Gait", selection: $ghost.clip) {
                        ForEach(DuckTrajectory.Clip.allCases, id: \.self) { clip in
                            Text(label(for: clip)).tag(clip)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.spacing(.standard))

                    mirrorChip
                    // NO "YOUR DUCK STUDIO MOTIONS" MENU. It was already
                    // invisible — guarded by `!celebrations.imported.isEmpty`,
                    // and that list can never fill in this build — so it was
                    // dead code that read like a live feature.
                }
            }
            .padding(.bottom, Theme.spacing(.loose))
        }
        // OVER THE STAGE, NOT INSTEAD OF IT. `.medium` leaves the duck
        // visible above the sheet and `presentationBackgroundInteraction`
        // leaves it draggable, so a run can be watched and orbited while its
        // own controls are on screen.
        .sheet(item: $driving) { which in
            NavigationStack {
                Group {
                    switch which {
                    case .trickRun: TrickRunView(model: ghost)
                    case .flamingo: FlamingoHoldView(model: ghost)
                    }
                }
                .navigationTitle(which.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { driving = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .safeAreaInset(edge: .bottom) {
            if ghost.isPlaced {
                // Seven modes no longer fit across a phone in one row, so
                // they wrap. The grid is three wide because that is what keeps
                // "Bow Bridge" on one line at caption2 — and one wide at an
                // accessibility size, where three columns cannot hold a word at
                // all. See `columns`.
                VStack(spacing: Theme.spacing(.tight)) {
                    LazyVGrid(columns: columns, spacing: Theme.spacing(.tight)) {
                        // A SHEET, NOT A PUSH, AND THE REASON IS THE DUCK.
                        // Trick run and Flamingo are the only two modes here
                        // with no stage of their own: their bodies are lists,
                        // and the thing they animate is `ghost` — the duck on
                        // THIS screen. Pushing them therefore started a run and
                        // then navigated away from the only place it could be
                        // watched, which is exactly how it was reported: "it
                        // seems to start the run and we only see the
                        // instruction set and not the actual sim screen."
                        //
                        // A medium detent keeps the stage above the sheet, and
                        // background interaction stays on so the duck can still
                        // be orbited while the run plays. The other five modes
                        // build their own stages and are still pushed.
                        Button { driving = .trickRun } label: {
                            modeCell("Trick run", symbol: "figure.gymnastics")
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            BowBridgeView()
                        } label: {
                            modeCell("Bow Bridge", symbol: "figure.walk")
                        }
                        .buttonStyle(.plain)
                        Button { driving = .flamingo } label: {
                            modeCell("Flamingo", symbol: "figure.stand")
                        }
                        .buttonStyle(.plain)
                        // BOBSLED IS NOT HERE, AND IT IS NOT AN OVERSIGHT. OpenCastor's
                        // bobsled is a rover game wearing a duck: it steers a sled, and
                        // the thing that makes every other game on this screen a DUCK
                        // game — the 14-degree yaw saturation, the 0.31 m arc a walk
                        // cannot beat — has nothing to do with it. Porting it would put
                        // a mode in the Lab whose difficulty comes from a vehicle this
                        // robot is not. It is listed in `LabCatalogue` as planned, to be
                        // built against the duck's own turn radius instead.
                        NavigationLink {
                            SlalomView()
                        } label: {
                            modeCell("Slalom", symbol: "flag.2.crossed")
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            DuckGolfView()
                        } label: {
                            modeCell("Golf", symbol: "flag.filled.and.flag.crossed")
                        }
                        .buttonStyle(.plain)
                        // FOLLOW ME IS THE ONE ROW THAT CAN GO DEAD, and it is
                        // the only mode in the Lab with nothing to fall back to:
                        // what it follows is the phone, and ARKit's camera pose is
                        // a real reading of where a person is standing. A stage
                        // version would feed the steering law a joystick position,
                        // which is the app inventing the very number the mode
                        // exists to measure. So it is disabled rather than
                        // substituted, and the sentence goes under the grid where
                        // there is room for it — a capsule this size cannot hold a
                        // reason, and a reason that only appears after a tap is a
                        // control that looked alive.
                        if let refusal = door.refusal(for: .followMe) {
                            // SHUT, AND STILL A REAL SURFACE. Half-opacity over
                            // a camera feed takes the word to roughly 2:1 and
                            // makes "why can't I press this" unanswerable; this
                            // reads as unavailable because it lost the ink the
                            // live cells have, which is the same argument
                            // `PrimaryActionStyle` makes about a disabled button.
                            modeCell("Follow me", symbol: "figure.walk.motion",
                                     isOpen: false)
                                .accessibilityElement(children: .combine)
                                // BOTH HALVES COME FROM StudioKit. A label
                                // assembled here out of a word like
                                // "unavailable" would be a claim about a
                                // refusal that no test reads, which is the one
                                // thing the sentences were moved into the kit
                                // to stop.
                                .accessibilityLabel(CameraAvailability.Dependent.followMe.title
                                                    + ". " + refusal)
                        } else {
                            NavigationLink {
                                FollowMeView()
                            } label: {
                                modeCell("Follow me", symbol: "figure.walk.motion")
                            }
                            .buttonStyle(.plain)
                        }
                        NavigationLink {
                            FetchView()
                        } label: {
                            modeCell("Fetch", symbol: "circle.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.spacing(.standard))
                    if let refusal = door.refusal(for: .followMe) {
                        Text(refusal)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            // Hidden from VoiceOver because the disabled row
                            // above already reads this same sentence as part
                            // of its own label; announcing it twice makes the
                            // grid harder to get through, not clearer.
                            .accessibilityHidden(true)
                            .padding(.horizontal, Theme.spacing(.snug))
                            .padding(.vertical, Theme.spacing(.tight))
                            // Four lines of caption2 over a camera feed, so it
                            // gets the same height-independent panel the status
                            // line has rather than sitting on whatever the
                            // camera happens to be pointing at — and the same
                            // opaque surface, for the same contrast reason.
                            .background(Theme.surfacePrimary, in: Self.panel)
                            .overlay(Self.panel.strokeBorder(
                                Theme.separator, lineWidth: GhostMetric.hairlineStroke))
                            .padding(.horizontal, Theme.spacing(.standard))
                    }
                }
                .padding(.bottom, Theme.spacing(.tight))
            }
        }
        .refreshingCameraDoor($door)
        // STANDING DOWN FROM AR IS THIS SCREEN'S JOB WHILE THE SWITCH IS GONE.
        // `VenuePicker` coerces the venue back to `.stage` when the door shuts,
        // and it can only do that while it is on screen — so the one case it
        // exists for, a person who picks "Your floor" and then turns the camera
        // off in Settings, would otherwise come back to a hub stuck on a venue
        // that cannot be built and no control to leave it with. The coordinator
        // below refuses to run an AR session either way; this is what puts the
        // duck back on the stage.
        .onAppear { standDownFromAR() }
        // WARMED BEFORE THE FIRST TAP, NOT AT IT. The taptic engine spins up on
        // demand and the first tap of a session arrives after the thing it is
        // about — which teaches the person that the buzz and the duck landing on
        // their floor are unrelated, and that is not a lesson a later
        // `prepare()` undoes.
        .task { Haptic.prepare() }
        .onChange(of: door) { _, _ in standDownFromAR() }
        .navigationTitle("Ghost duck")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func standDownFromAR() {
        if !door.canOfferAR && ghost.venue != .stage { ghost.venue = .stage }
    }

    // MARK: - the grid

    /// Three across, one at an accessibility size.
    ///
    /// A THREE-COLUMN GRID IS A FIXED FRAME BY ANOTHER NAME. At AX5 a third of
    /// a phone holds about four characters of "Bow Bridge", and a cell that
    /// truncates is a mode whose name the person who most enlarged it cannot
    /// read. One column costs a scroll and loses nothing.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.spacing(.tight)),
              count: typeSize.isAccessibilitySize ? 1 : 3)
    }

    /// One cell in the mode grid.
    ///
    /// NOT A CAPSULE, FOR THE REASON THE PANEL IS NOT ONE. These wrap: "Bow
    /// Bridge" is two lines in a third of a phone at anything above the default
    /// text size, and a capsule's half-height ends eat the first and last word
    /// of a wrapped line. `Palette.Radius.control` is the scale's step for
    /// "pressable and not a pill".
    ///
    /// THE TARGET COMES OFF THE SPACING SCALE. `.snug` above and below a
    /// caption leaves a cell comfortably past the forty-four points the HIG
    /// asks of a control, so this file never writes that floor down as a
    /// number — there is exactly one of those in the app and it is in
    /// `DesignComponents`. These cells open a mode; they do not move the duck,
    /// which is what the sixty-point variant is for.
    private func modeCell(_ title: String, symbol: String,
                          isOpen: Bool = true) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(isOpen ? Theme.textPrimary : Theme.textSecondary)
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.spacing(.tight))
            .padding(.vertical, Theme.spacing(.snug))
            // 44pt FLOOR, EXPLICITLY. caption2's line box plus two 12pt pads
            // came to ~37pt — under the HIG minimum, on the tap target for all
            // seven Lab modes, floating over a live 3D stage where a mis-hit
            // also orbits the camera.
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surfacePrimary, in: cell)
            .overlay(cell.strokeBorder(Theme.separator,
                                       lineWidth: GhostMetric.hairlineStroke))
            .contentShape(cell)
    }

    private var cell: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(GhostMetric.cell), style: .continuous)
    }

    /// As recorded, or mirrored.
    ///
    /// THE BILL IS THE SELECTION, NOT THE TINT, which is the rule `DriveView`'s
    /// layer chips follow: on this palette a filled chip differs from its ground
    /// by about 1.02:1 in light, which `Theme` says in as many words is a hint
    /// and not information. The orange bar under the chip is the mark that
    /// carries it, the weight of the word is a second signal, and the word
    /// itself changes — three ways to read one state, none of them a colour.
    ///
    /// IT STAYS `.disabled` ON A STRAIGHT WALK. Mirroring a straight walk gives
    /// back a straight walk, so the control genuinely does nothing there; unlike
    /// the dead pad buttons in `DriveView` there is no sentence to be had by
    /// pressing it, which is the test for whether disabling costs anything.
    private var mirrorChip: some View {
        let on = ghost.isMirrored
        // The same condition `.disabled` is given, read here as well so the
        // chip LOOKS inert rather than only being inert: a `.plain` button
        // draws whatever its label draws, disabled or not.
        let live = ghost.clip == .turnLeft
        return Button {
            ghost.isMirrored.toggle()
        } label: {
            Text(on ? "Mirrored" : "As recorded")
                .font(.footnote.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(live ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, Theme.spacing(.standard))
                .padding(.vertical, Theme.spacing(.snug))
                .background { if on { Capsule().fill(Theme.surfaceInteractive) } }
                .background(Capsule().fill(Theme.surfacePrimary))
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: GhostMetric.hairlineStroke))
                .overlay(alignment: .bottom) {
                    if on { BillIndicator().offset(y: Theme.spacing(.tight)) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Only a turn has a meaningful mirror: mirroring a straight
        // walk gives back a straight walk, so offering the control
        // there would be a button that visibly does nothing.
        .disabled(ghost.clip != .turnLeft)
        .accessibilityLabel(Text("Mirror the recording"))
        .accessibilityValue(Text(on ? "on" : "off"))
    }

    private func label(for clip: DuckTrajectory.Clip) -> String {
        switch clip {
        case .stand:    return "Stand"
        case .walk:     return "Walk"
        case .walkFast: return "Fast"
        case .turnLeft: return "Turn"
        case .skateStand: return "Skate idle"
        case .skate:      return "Skate"
        case .skateFast:  return "Skate fast"
        case .skateBack:  return "Skate back"
        case .skateTurn:  return "Skate turn"
        }
    }
}

// MARK: - the numbers this screen writes down for itself

/// Dimensions and radii that are layout decisions rather than facts.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST, which is the line `Theme` draws and
/// this file stays behind: a ratio is a fact and lives in `Palette`, where a
/// test runs the WCAG formula over it. How wide to let a status line grow on an
/// iPad is a judgement about a screen.
private enum GhostMetric {
    /// The panel behind a sentence. A card, on the scale.
    static let panel = Palette.Radius.card
    /// A cell in the mode grid — pressable, and not a pill.
    static let cell = Palette.Radius.control

    /// How wide the status line may grow before it stops being a caption under
    /// a duck and starts being a paragraph across an iPad. Lifted entirely at
    /// accessibility sizes — see `body`.
    static let panelWidth: CGFloat = 340

    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke = DesignMetric.hairlineStroke
}

// MARK: - the session

/// What the AR view and the SwiftUI controls both talk to.
///
/// This owns no ARKit state of its own on purpose. The container below holds
/// the `ARView`, and the only things that cross between them are a placement
/// request, the selected clip, and a sentence for the label — because an
/// `ObservableObject` that also held entities would republish the whole view
/// hierarchy on every one of the sixty transform writes a frame does.
@MainActor
final class GhostDuckModel: ObservableObject {
    @Published var status = "Point the camera at the floor."
    @Published var isPlaced = false
    /// A stage by default. The ghost is a 25 cm robot standing on a floor —
    /// it does not need YOUR floor to be that, and asking for the camera to
    /// look at a duck is a poor trade. AR stays one tap away.
    @Published var venue: LabVenue = .stage
    @Published var clip: DuckTrajectory.Clip = .walk
    @Published var isMirrored = false
    /// A motion from Microduck Studio, chosen instead of a gait. The ghost stands
    /// in place and performs it on a loop — an authored move carries no root
    /// motion because no physics produced any.

    /// A trick being performed right now, and when it started. It outranks the
    /// gait picker and the Microduck Studio motion for as long as it runs, then
    /// clears itself — a trick is an event, not a mode.
    @Published var trick: DuckIntentClip?
    var trickStarted: TimeInterval = 0

    /// The measured corpus, for the trick game's odds. A failure to load is a
    /// game with no odds, which is no game — the view says so rather than
    /// inventing numbers.
    let success: DuckIntentSuccess?
    let intents: [String: DuckIntentClip]

    /// Loaded once. `DuckTrajectory.all()` decodes the whole file per call, and
    /// the ghost samples it sixty times a second.
    let clips: [String: DuckTrajectory]
    let loadFailure: String?

    init() {
        do {
            clips = try DuckTrajectory.all()
            loadFailure = nil
        } catch {
            clips = [:]
            loadFailure = "The recorded gaits did not load: \(error)"
        }
        intents = (try? DuckIntentClip.bundled()) ?? [:]
        success = try? DuckIntentSuccess.bundled()
    }

    /// The trajectory to play, already mirrored if asked. Mirroring is a swap
    /// and a negate over the whole clip, so it is done here rather than per
    /// frame.
    func currentTrajectory() -> DuckTrajectory? {
        guard let t = clips[clip.rawValue] else { return nil }
        return (isMirrored && clip == .turnLeft) ? t.mirrored() : t
    }
}

// MARK: - the AR view

private struct GhostDuckContainer: UIViewRepresentable {
    @ObservedObject var model: GhostDuckModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR,
                          automaticallyConfigureSession: false)
        if let failure = model.loadFailure {
            model.status = failure
            return view
        }
        context.coordinator.attach(to: view, model: model)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.model = model
        let venue = model.venue
        let coordinator = context.coordinator
        if coordinator.needsRebuild(venue: venue) {
            DispatchQueue.main.async { coordinator.ensure(venue: venue) }
        }
        coordinator.clipChanged()
    }

    func makeCoordinator() -> GhostDuckCoordinator { GhostDuckCoordinator() }

    static func dismantleUIView(_ view: ARView, coordinator: GhostDuckCoordinator) {
        // An ARView left running keeps the camera and the tracking thread alive
        // behind whatever the user navigated to next.
        view.session.pause()
        coordinator.detach()
    }
}

@MainActor
final class GhostDuckCoordinator: NSObject {

    var model: GhostDuckModel?
    private weak var view: ARView?
    private var ghost: DuckGhostEntity?
    private var updates: (any Cancellable)?
    private var trajectory: DuckTrajectory?
    /// When the current clip started, so switching gait does not teleport the
    /// duck to wherever the new clip's accumulated root motion had reached.
    private var clipStart: TimeInterval = 0
    private var wheelSpin: Double = 0
    private var lastGhostX: Double = 0, lastGhostY: Double = 0
    private var stage: LabStage?
    private var built: LabVenue?

    func attach(to view: ARView, model: GhostDuckModel) {
        self.view = view
        self.model = model
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    func detach() {
        updates = nil
        stage = nil
        ghost = nil
        view = nil
    }

    func needsRebuild(venue: LabVenue) -> Bool { built != venue }

    /// Build the chosen world. On a stage the duck is simply there; in AR it
    /// waits for a tap on a real floor, as it always has.
    func ensure(venue: LabVenue) {
        guard built != venue, let view, let model else { return }
        // THE SECOND LOCK, AND THE ONE THAT MATTERS: it is the line above
        // `session.run`. The hub above does not offer "Your floor" at all when
        // the camera cannot be opened, and stands the venue back down if the
        // door shuts while it is on screen, so this is unreachable
        // through the UI — which is exactly why it is here. Build 27 shipped
        // with `session.run` called against a plist that did not permit it and
        // iOS killed the app; a guard that only lives in a picker is a guard
        // the next screen forgets to copy.
        //
        // It refuses BEFORE `built` is updated and before the stage comes down,
        // so a refusal leaves the world that was already standing rather than
        // tearing it down for one that never arrives. The sentence goes into
        // the status line, which this screen draws whatever else is on it —
        // the venue picker is not there to sit under while the door is shut.
        if venue == .ar, let refusal = CameraDoor.availability.refusal(for: .venue) {
            model.status = refusal
            return
        }
        built = venue
        stage?.dismantle(); stage = nil
        if let anchor = ghost?.parent as? AnchorEntity { view.scene.removeAnchor(anchor) }
        ghost = nil
        model.isPlaced = false

        switch venue {
        case .stage:
            // Close in and low: a 25 cm robot filmed from two metres is a dot.
            let stage = LabStage(in: view, theme: .meadow, extent: 6,
                                 distance: 1.1, elevation: 0.32)
            self.stage = stage
            let duck = DuckGhostEntity(variant: model.clip.variant)
            duck.position.y = 0
            stage.root.addChild(duck)
            ghost = duck
            clipStart = CACurrentMediaTime()
            trajectory = model.currentTrajectory()
            model.isPlaced = true
            model.status = "Life size, 25 cm at the shoulder. Drag to walk round it, pinch to zoom."
        case .ar:
            view.cameraMode = .ar
            view.environment.background = .cameraFeed()
            guard ARWorldTrackingConfiguration.isSupported else {
                // THE KIT OWNS THIS SENTENCE. This stub predates
                // `CameraAvailability` and says strictly less than it: no
                // consequence, no remedy, and a second place the same fact
                // is worded. The door has already refused on
                // `deviceCannotWorldTrack`, so reaching here means the door
                // said yes and ARKit then said no — rare, and worth saying
                // in the same words as everywhere else.
                model.status = CameraAvailability(usageDescriptionIsDeclared: true,
                                          permission: .authorized,
                                          deviceSupportsWorldTracking: false)
                    .refusal(for: .venue) ?? ""
                return
            }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.environmentTexturing = .automatic
            view.session.run(config)
            model.status = "Point the camera at the floor and tap."
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view, ghost == nil, let model, built == .ar else { return }
        let point = gesture.location(in: view)

        // `.existingPlaneGeometry` first, `.estimatedPlane` as the fallback: on
        // a phone with LiDAR the first lands on measured floor, and on one
        // without it never succeeds and the estimate is all there is. Asking
        // for the estimate only would throw away the better answer on the
        // devices that have it.
        let hits = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        let fallback = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        guard let hit = hits.first ?? fallback.first else {
            model.status = "No floor there yet — move the phone a little and tap again."
            return
        }

        let anchor = AnchorEntity(world: hit.worldTransform)
        let duck = DuckGhostEntity(variant: model.clip.variant)
        // Stand it ON the plane. The trunk origin is roughly 120 mm up inside
        // the robot, so anchoring the entity itself would bury the feet.
        // The entity's origin is its feet — bodyPoses works in the model's
        // world frame, whose origin is the floor.
        duck.position.y = 0
        anchor.addChild(duck)
        view.scene.addAnchor(anchor)
        ghost = duck

        clipStart = CACurrentMediaTime()
        trajectory = model.currentTrajectory()
        model.isPlaced = true
        model.status = "Life size, 25 cm at the shoulder. Walk around it."
        // A DUCK ARRIVED ON THE FLOOR AND STARTED WALKING, which is an event in
        // the world rather than a tap: the same tap two seconds earlier found no
        // plane and produced the sentence above instead. `behaviourStarted` is
        // the design system's feeling for "something is now moving", and the
        // person is looking at their carpet rather than at the glass — which is
        // the whole argument for spending the taptic engine at all. Nothing
        // fires on the stage: there the duck is simply there when the screen
        // opens, and a buzz on arriving at a screen is a buzz for a scroll.
        Haptic.behaviourStarted()
    }

    func clipChanged() {
        guard let model, let current = ghost else { return }
        // A skating clip is drawn on the rollers robot, a walking one on
        // legs: swap the entity under the same anchor when the feet change.
        if current.variant != model.clip.variant, let anchor = current.parent {
            current.removeFromParent()
            let fresh = DuckGhostEntity(variant: model.clip.variant)
            fresh.position.y = 0
            anchor.addChild(fresh)
            ghost = fresh
        }
        let wanted = model.currentTrajectory()
        guard wanted != trajectory else { return }
        trajectory = wanted
        wheelSpin = 0; lastGhostX = 0; lastGhostY = 0
        clipStart = CACurrentMediaTime()
    }

    private func step() {
        guard let ghost else { return }
        // A TRICK OUTRANKS EVERYTHING, AND CARRIES ITS ROOT. These clips were
        // recorded in physics: a roulade travels 0.559 m and a back roll ends
        // somewhere else entirely, so drawing one from a fixed trunk would
        // hover it exactly as the soccer pitch's roulade once hovered. When it
        // finishes it clears itself and the gait picker takes over again.
        if let model, let trick = model.trick {
            let elapsed = CACurrentMediaTime() - model.trickStarted
            if elapsed >= trick.duration {
                model.trick = nil
            } else {
                let pose = trick.pose(at: elapsed)
                ghost.place(root: pose.root, jointAngles: pose.jointAngles)
                return
            }
        }
        // The branch that played a chosen Microduck Studio motion in place is gone
        // with the menu that chose it — `studioMove` could only ever be nil,
        // because nothing in this build can put a .duckmove in that list.
        guard let trajectory, let model else { return }
        let pose = trajectory.pose(at: CACurrentMediaTime() - clipStart)
        if ghost.variant == .rollers {
            // The wheels roll with the ground covered, signed along the
            // heading; on 'Skate idle' the ghost holds its place — the
            // recording drifts ~0.09 m/s at a zero command on the un-rebuilt
            // rollers plant (its deltaX says so), and a ghost creeping across
            // the floor while "idle" tells the wrong story.
            let idle = model.clip == .skateStand
            let x = idle ? 0 : pose.x, y = idle ? 0 : pose.y
            let dx = x - lastGhostX, dy = y - lastGhostY
            lastGhostX = x; lastGhostY = y
            let along = dx * cos(pose.yaw) + dy * sin(pose.yaw)
            let step = hypot(dx, dy)
            if step < 0.1 { wheelSpin += (along < 0 ? -step : step) / 0.015 }
            ghost.apply(jointAngles: pose.jointAngles, wheelSpin: wheelSpin)
            ghost.position = SIMD3<Float>(Float(x), 0, Float(-y))
            ghost.orientation = simd_quatf(angle: Float(-(idle ? 0 : pose.yaw)), axis: SIMD3<Float>(0, 1, 0))
            stage?.follow(ghost.position)
            return
        }
        ghost.apply(jointAngles: pose.jointAngles)
        ghost.position = SIMD3<Float>(Float(pose.x), 0, Float(-pose.y))
        ghost.orientation = simd_quatf(angle: Float(-pose.yaw), axis: SIMD3<Float>(0, 1, 0))
        stage?.follow(ghost.position)
    }
}
