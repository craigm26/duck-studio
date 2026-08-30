import SwiftUI
import ARKit
import RealityKit
import Combine
import QuartzCore
import DuckKit
import DuckVisual
import DuckRender

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
    @ObservedObject private var celebrations = CelebrationStore.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            GhostDuckContainer(model: ghost)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(ghost.status)
                    .font(.footnote)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                VenuePicker(venue: $ghost.venue)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())

                if ghost.isPlaced {
                    Picker("Gait", selection: $ghost.clip) {
                        ForEach(DuckTrajectory.Clip.allCases, id: \.self) { clip in
                            Text(label(for: clip)).tag(clip)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Button(ghost.isMirrored ? "Mirrored" : "As recorded") {
                        ghost.isMirrored.toggle()
                    }
                    .buttonStyle(.bordered)
                    // Only a turn has a meaningful mirror: mirroring a straight
                    // walk gives back a straight walk, so offering the control
                    // there would be a button that visibly does nothing.
                    .disabled(ghost.clip != .turnLeft || ghost.studioMove != nil)

                    // ANYTHING FROM DUCK STUDIO. Every .duckmove on this phone
                    // — authored in the editor, opened here — plays on the
                    // ghost, standing in place: an authored move carries no
                    // root motion because no physics produced any, and the
                    // ghost does not invent one.
                    if !celebrations.imported.isEmpty {
                        Menu {
                            Button("Recorded gaits") { ghost.studioMove = nil }
                            ForEach(celebrations.imported) { move in
                                Button(move.name) { ghost.studioMove = move }
                            }
                        } label: {
                            Label(ghost.studioMove?.name ?? "Your Duck Studio motions",
                                  systemImage: "figure.dance")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            if ghost.isPlaced {
                // Six modes no longer fit across a phone in one row, so they
                // wrap. The grid is three wide because that is what keeps
                // "Bow Bridge" on one line at caption2.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                         count: 3), spacing: 10) {
                    NavigationLink {
                        TrickRunView(model: ghost)
                    } label: {
                        Label("Trick run", systemImage: "figure.gymnastics")
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(.thinMaterial, in: Capsule())
                    }
                    NavigationLink {
                        BowBridgeView()
                    } label: {
                        Label("Bow Bridge", systemImage: "figure.walk")
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(.thinMaterial, in: Capsule())
                    }
                    NavigationLink {
                        FlamingoHoldView(model: ghost)
                    } label: {
                        Label("Flamingo", systemImage: "figure.stand")
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(.thinMaterial, in: Capsule())
                    }
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
                        Label("Slalom", systemImage: "flag.2.crossed")
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(.thinMaterial, in: Capsule())
                    }
                    NavigationLink {
                        DuckGolfView()
                    } label: {
                        Label("Golf", systemImage: "flag.filled.and.flag.crossed")
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(.thinMaterial, in: Capsule())
                    }
                    NavigationLink {
                        FollowMeView()
                    } label: {
                        Label("Follow me", systemImage: "figure.walk.motion")
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(.thinMaterial, in: Capsule())
                    }
                    NavigationLink {
                        FetchView()
                    } label: {
                        Label("Fetch", systemImage: "circle.circle")
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .font(.caption2)
                .padding(.horizontal).padding(.bottom, 8)
            }
        }
        .navigationTitle("Ghost duck")
        .navigationBarTitleDisplayMode(.inline)
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
    /// A motion from Duck Studio, chosen instead of a gait. The ghost stands
    /// in place and performs it on a loop — an authored move carries no root
    /// motion because no physics produced any.
    @Published var studioMove: CelebrationStore.Celebration?

    /// A trick being performed right now, and when it started. It outranks the
    /// gait picker and the Duck Studio motion for as long as it runs, then
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
                model.status = "This device cannot do world tracking."
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
        // A Duck Studio motion outranks the gait picker while chosen: the
        // ghost performs it in place on a loop, through DuckMove.pose(at:) —
        // the same smoothstep the editor previews and the pitch celebration
        // plays.
        if let move = model?.studioMove?.move {
            let elapsed = (CACurrentMediaTime() - clipStart)
                .truncatingRemainder(dividingBy: max(move.duration + 0.6, 0.7))
            ghost.apply(jointAngles: move.pose(at: elapsed))
            return
        }
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
