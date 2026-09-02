import SwiftUI
import Combine
import RealityKit
import DuckKit
import DuckRender
import DuckVisual
import StudioKit

/// Where the camera is looking from. Spherical, because that is what an orbit
/// control naturally produces and it makes the limits obvious.
struct OrbitState: Equatable {
    var azimuth: Float = .pi / 4
    /// Clamped short of straight up and straight down: at the poles the
    /// azimuth stops meaning anything and the view snaps as you cross.
    var elevation: Float = 0.30
    /// Metres from the point being looked at. The robot is 0.25 m tall, so the
    /// useful range is close — but a staircase is over a metre long, so the far
    /// end has to reach far enough to see one whole.
    var distance: Float = 0.85
    /// Whether the camera rides with the robot or stays put.
    ///
    /// FIXED IS THE DEFAULT, and that is the whole answer to "where is it?".
    /// A camera locked to the trunk shows a duck that never moves and a world
    /// that slides past, which is exactly the view that cannot tell you whether
    /// the robot reached the step. Standing still and letting it walk away is
    /// what makes travel visible.
    var follows = false

    /// What the camera looks at, when the caller knows better than the middle
    /// of the scene.
    ///
    /// A BOUNDING BOX IS THE RIGHT ANSWER FOR WATCHING AND THE WRONG ONE FOR
    /// AUTHORING. `rebuildProps` centres on everything worth seeing, which for
    /// a four-step flight at 180 mm is a 720 mm staircase — and a 250 mm duck
    /// at the bottom of it is then about forty points tall, which is not a
    /// thing anybody can pose. Nobody is authoring the fourth step: the move is
    /// the first riser. `DuckScene.authoringFraming` works out the point that
    /// holds the duck and that riser together, and this is where it goes.
    ///
    /// nil MEANS "use the box", which is what every stage but the editor's
    /// does.
    var focus: SIMD3<Float>?

    /// THE FRAMING THE STAGE WAS OPENED ON, if any. "Reset the view" returns
    /// here, not to the empty-floor defaults, so a challenge motion's reset
    /// brings the riser back into the picture instead of losing it.
    var homeFocus: SIMD3<Float>?
    var homeDistance: Float?
    var homeElevation: Float?

    /// Aim the camera the way the kit says a scene is best authored, and
    /// remember that as home. `nil` forgets both: the camera goes back to
    /// following the duck's centre, and reset goes back to the defaults.
    mutating func frame(_ framing: DuckScene.Framing?) {
        guard let framing else {
            focus = nil
            homeFocus = nil
            homeDistance = nil
            homeElevation = nil
            return
        }
        let aim = SIMD3(Float(framing.targetX), Float(framing.targetZ), 0)
        homeFocus = aim
        homeDistance = Float(framing.distance)
        homeElevation = Float(framing.elevation)
        focus = aim
        distance = Float(framing.distance)
        elevation = Float(framing.elevation)
    }

    static let defaults = OrbitState()

    mutating func drag(dx: Float, dy: Float) {
        azimuth -= dx * 0.01
        elevation = min(max(elevation + dy * 0.01, -0.2), 1.3)
    }

    mutating func zoom(by scale: Float) {
        distance = min(max(distance / scale, 0.20), 4.0)
    }

    /// Back to the starting angle, keeping whether the camera follows.
    ///
    /// ONE DEFINITION OF "RESET", because there are now two ways to ask for it:
    /// the double-tap and the VoiceOver action. Written twice they would drift,
    /// and the half that drifts is `follows` — a reset that quietly stopped
    /// following would move the camera for a reason the person cannot see.
    /// KEPT ALONGSIDE `follows`, AND FOR THE SAME REASON. A reset that also
    /// forgot what the camera was aimed at would swing the editor off the
    /// riser it was framed on and onto the middle of a staircase, which is the
    /// camera moving for a reason the person cannot see — exactly the failure
    /// the `follows` line above documents. Angle and distance go back; what
    /// the camera is FOR does not.
    mutating func resetView() {
        let following = follows
        let home = (homeFocus, homeDistance, homeElevation)
        self = .defaults
        follows = following
        (homeFocus, homeDistance, homeElevation) = home
        focus = homeFocus
        if let homeDistance { distance = homeDistance }
        if let homeElevation { elevation = homeElevation }
    }

    /// Camera position, relative to whatever it is looking at.
    func position(target: SIMD3<Float>) -> SIMD3<Float> {
        let horizontal = distance * cos(elevation)
        return target + SIMD3(horizontal * sin(azimuth),
                              distance * sin(elevation),
                              horizontal * cos(azimuth))
    }
}

/// One frame to draw: the robot's joints, and where the robot IS.
///
/// THE ROOT IS NOT OPTIONAL, and leaving it out was the bug this closes. The
/// stage used to take joint angles alone, so every clip played with the trunk
/// pinned to the origin: `climb` walked 208 mm forward and 357 mm sideways in
/// the recording and stood perfectly still on screen, while the staircase it
/// was supposed to reach sat off to one side untouched. A viewer could not tell
/// a move that got there from one that fell short, because neither of them went
/// anywhere.
///
/// The pose itself is `DuckStance`, which lives in StudioKit and is tested
/// there. This adds only the change of basis into RealityKit's frame.
typealias StagePose = DuckStance

extension DuckStance {
    /// The trunk, in RealityKit's frame. MuJoCo is z-up, RealityKit is y-up:
    /// (x, y, z) → (x, z, −y), the same swap `DuckGhostEntity` applies to every
    /// vertex, so the robot and the world it stands in cannot disagree.
    ///
    /// FOR LOOKING AT, NOT FOR PLACING. Putting the entity here is the bug that
    /// drew the robot floating; `DuckGhostEntity.place(root:jointAngles:)` owns
    /// placement. This is what the camera aims at and what the legend prints.
    var position: SIMD3<Float> {
        SIMD3(Float(root.x), Float(root.z), Float(-root.y))
    }

    /// The same point projected onto the floor — where the shadow goes.
    var groundPosition: SIMD3<Float> {
        SIMD3(Float(root.x), 0, Float(-root.y))
    }
}

// MARK: - where a joint landed on the glass

/// One joint's three points, on screen.
///
/// THREE POINTS AND NOT ONE, WHICH IS THE WHOLE OF THE ARRANGEMENT. StudioKit
/// knows the kinematics and has never heard of a camera; RealityKit owns the
/// camera and must not learn the kinematics. `JointHandles.Handle` hands over
/// three positions in the model's world frame — the pivot, the point a thumb
/// pulls, and where that point lands after a tenth of a radian — and this
/// carries all three back after the one conversion the app is allowed to make.
/// `JointHandles.grab` turns them into a drag law. Nothing in between
/// re-derives a tangent, and nothing here knows what one is.
struct StageProjection: Equatable {
    /// The index into a fifteen-wide draft pose, as the kit hands it over.
    let joint: Int
    let pivot: JointHandles.ScreenPoint
    /// Where the marker is drawn: `pivot` plus the joint's lever.
    let grip: JointHandles.ScreenPoint
    /// Where `grip` goes under `JointHandles.probeRadians` of this joint.
    let swung: JointHandles.ScreenPoint
    /// How far the grip is from the camera, in metres.
    let depth: Double
}

/// Everything the overlay needs from one rendered frame.
struct StageProjections: Equatable {
    var handles: [StageProjection] = []
    /// The trunk's distance from the camera, which is what makes "behind the
    /// duck" a fact rather than a guess. `JointHandles.place` compares each
    /// grip against it.
    var trunkDepth: Double = 0
}

/// A turntable view of the robot IN A PLACE — not AR. The bench is somewhere to
/// look at a pose from every side, and a camera feed behind it would be scenery.
///
/// WHY THERE IS A SWIFTUI VIEW IN FRONT OF THE REPRESENTABLE. Everything below
/// draws; this layer is what a person who cannot see the drawing gets instead,
/// and it has to live on the SwiftUI side for two reasons. The spoken value
/// changes whenever the pose or the scene changes, and SwiftUI re-evaluates
/// `body` on exactly those changes — set on the `ARView` in `updateUIView` it
/// would be a second copy of the same state, refreshed by hand, silently stale
/// the first time somebody adds an early return to that method. And the actions
/// have to write to `orbit`: `$orbit` is in scope here and fresh on every pass,
/// where the coordinator's copy is captured once in `makeUIView` and never
/// renewed. The representable keeps the same name-shape and defaults it always
/// had, so nothing at a call site changes.
struct DuckStage: View {
    let pose: StagePose
    var variant: DuckKinematics.Variant = .legs
    let environment: DuckIntentClip.Environment
    var props: [DuckScene.Prop] = []
    var trail: [DuckIntentClip.Root] = []
    var progress: Double = 0
    @Binding var orbit: OrbitState
    /// The joints that can be grabbed on this stage.
    ///
    /// EMPTY EVERYWHERE BUT THE EDITOR, AND DEFAULTED SO IT STAYS THAT WAY.
    /// Eight screens draw this stage and exactly one of them is authoring a
    /// pose; a handle on the drive screen would be a control that edits a
    /// keyframe that does not exist. The default is what lets the other seven
    /// compile untouched.
    var handles: [JointHandles.Handle] = []
    /// Called once per rendered frame with where those joints landed, and only
    /// when they have actually moved. Nothing is drawn from here — the caller
    /// draws, above the stage, in SwiftUI.
    var onProject: ((StageProjections) -> Void)?
    /// WHERE THE BALL IS RIGHT NOW, in metres on the floor, when a bench is
    /// reporting it. Moving the ball this way leaves `props` alone, so a
    /// rolling ball does not rebuild every step and wall on every round trip.
    var rolling: SIMD2<Double>?

    /// One notch of camera movement, in the points of drag the pan recogniser
    /// hands `OrbitState.drag` — so an action IS the gesture, one notch of it,
    /// and there is no second scale factor to keep in step. 24 points is about
    /// fourteen degrees: small enough to aim with, big enough to feel, and a
    /// whole turn in twenty-six swipes rather than a hundred.
    private static let notch: Float = 24
    /// And one notch of pinch, as the ratio `zoom(by:)` already takes.
    private static let zoomNotch: Float = 1.25

    /// What is in the place, in the legend's own words.
    ///
    /// THE SAME SENTENCE THE LEGEND PRINTS, from the same StudioKit function on
    /// the same counts — a stage that announced "3D view" and stopped would say
    /// nothing about whether there is a step in front of the robot. It is
    /// deliberately NOT the trunk reading: the legend takes `rootIsPinned` and
    /// this does not, and x/y/z spoken over an authored draft would be three
    /// constants read as if physics had put the body there, which is the exact
    /// falsehood `StageCaption.pinnedTrunk` exists to stop. The camera clause is
    /// furniture, in the words the legend's own button uses.
    private var spokenScene: String {
        let contents = StageCaption.context(
            gridMetres: StageSurface.gridMetres,
            stepCount: environment.steps.count,
            tallestStepMetres: environment.steps.map(\.top).max() ?? 0,
            wallCount: environment.walls.count,
            propCount: props.count)
        return contents + (orbit.follows ? " · camera following the robot"
                                         : " · camera fixed")
    }

    var body: some View {
        StageSurface(pose: pose, variant: variant, environment: environment,
                     props: props, trail: trail, progress: progress, orbit: $orbit,
                     handles: handles, onProject: onProject, rolling: rolling)
            // ONE ELEMENT, NOT ONE PER JOINT. The scene holds a duck of fifteen
            // drawn parts, a grid, a path and whatever props the place has; as
            // elements that is a swipe through dozens of unnamed boxes, and
            // nothing in it is separately operable. What a person needs from a
            // picture is what the picture is of, which is one sentence.
            .accessibilityElement()
            .accessibilityLabel(Text("The robot on the stage, in 3D"))
            .accessibilityValue(Text(spokenScene))
            // THE LEGEND'S THREE GESTURES, AS ACTIONS. "Drag to orbit · pinch to
            // zoom · double-tap to reset" is printed to people who can do none
            // of the three; these are the same three moves for a person using
            // VoiceOver, Switch Control or one hand. They are worth having even
            // though nothing is spoken back afterwards: the person who cannot
            // pinch is usually looking at the screen, and the screen is the
            // answer. Naming: left and right are the drag they stand in for,
            // higher and lower say where the camera ends up, because "tilt up"
            // is ambiguous about whether the camera or the duck is what tilts.
            .accessibilityAction(named: Text("Orbit left")) {
                orbit.drag(dx: -Self.notch, dy: 0)
            }
            .accessibilityAction(named: Text("Orbit right")) {
                orbit.drag(dx: Self.notch, dy: 0)
            }
            .accessibilityAction(named: Text("Look from higher")) {
                orbit.drag(dx: 0, dy: Self.notch)
            }
            .accessibilityAction(named: Text("Look from lower")) {
                orbit.drag(dx: 0, dy: -Self.notch)
            }
            .accessibilityAction(named: Text("Zoom in")) {
                orbit.zoom(by: Self.zoomNotch)
            }
            .accessibilityAction(named: Text("Zoom out")) {
                orbit.zoom(by: 1 / Self.zoomNotch)
            }
            .accessibilityAction(named: Text("Reset the view")) {
                orbit.resetView()
            }
    }
}

/// The RealityKit half: the scene, the camera and the three recognisers.
struct StageSurface: UIViewRepresentable {

    /// How far apart the floor's rules are, in metres.
    ///
    /// ONE CONSTANT, READ BY BOTH THE DRAWING AND THE CAPTION. They used to be
    /// two literals — `line += 0.1` here and "100 mm grid" in StudioKit — which
    /// is the arrangement where a floor and the sentence describing it drift
    /// apart without anything failing. The Lab's own stage rules a half-metre,
    /// so the pair was one reuse away from printing a number that was wrong by
    /// a factor of five.
    static let gridMetres = 0.1

    let pose: StagePose
    /// Which feet: a roller clip is drawn on Pollen's roller blades.
    var variant: DuckKinematics.Variant = .legs
    /// The props to draw. Bare floor is still a place; `nil` is not.
    let environment: DuckIntentClip.Environment
    /// Things in the scene the duck could take hold of. Separate from
    /// `environment` because that type belongs to DuckKit and describes what a
    /// CLIP was recorded against — a prop is a Studio idea, and a recording
    /// made before props existed must keep decoding.
    var props: [DuckScene.Prop] = []
    /// The whole run, so the path can be drawn and the robot seen against where
    /// it has already been. Empty for a bench, which has no time axis.
    var trail: [DuckIntentClip.Root] = []
    /// How far through `trail` the playhead is, 0…1.
    var progress: Double = 0
    @Binding var orbit: OrbitState
    /// The joints that can be grabbed, in the model's world frame. Empty on
    /// every stage but the editor's — see `DuckStage.handles`.
    var handles: [JointHandles.Handle] = []
    /// Where they landed, once per rendered frame.
    var onProject: ((StageProjections) -> Void)?
    /// WHERE THE BALL IS RIGHT NOW, in metres on the floor, when a bench is
    /// reporting it. Moving the ball this way leaves `props` alone, so a
    /// rolling ball does not rebuild every step and wall on every round trip.
    var rolling: SIMD2<Double>?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.init(white: 0.11, alpha: 1))

        let world = AnchorEntity(world: .zero)
        view.scene.addAnchor(world)
        context.coordinator.world = world

        // LIGHTS, because the props are physically-based and a non-AR scene
        // ships with almost nothing. The first cut drew a 0.16-grey floor on an
        // 0.08-grey background under no light at all, which is why the answer to
        // "where is the robot?" was a black rectangle.
        let key = DirectionalLight()
        key.light.intensity = 3500
        key.light.color = .white
        // A cast shadow is what fixes the robot to the floor rather than
        // floating over it. `DirectionalLight.Shadow` is the nested type; the
        // top-level name reads better and does not exist.
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 2)
        key.look(at: .zero, from: SIMD3(0.6, 1.2, 0.8), relativeTo: nil)
        world.addChild(key)

        let fill = DirectionalLight()
        fill.light.intensity = 1200
        fill.light.color = .init(red: 0.8, green: 0.86, blue: 1, alpha: 1)
        fill.look(at: .zero, from: SIMD3(-0.9, 0.6, -0.7), relativeTo: nil)
        world.addChild(fill)

        let duck = DuckGhostEntity()
        world.addChild(duck)
        context.coordinator.duck = duck

        let shadow = ModelEntity(
            mesh: .generatePlane(width: 0.16, depth: 0.16, cornerRadius: 0.08),
            materials: [UnlitMaterial(color: UIColor(white: 0.02, alpha: 0.55))])
        world.addChild(shadow)
        context.coordinator.shadow = shadow

        let props = Entity()
        world.addChild(props)
        context.coordinator.props = props

        let path = Entity()
        world.addChild(path)
        context.coordinator.path = path

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 40
        // RealityKit measures that angle along the VERTICAL axis by default,
        // which is what `DuckScene.authoringFieldOfView` assumes when it
        // frames a scene: the stage is at least as wide as it is tall, so the
        // vertical field is the tighter one.
        world.addChild(camera)
        context.coordinator.camera = camera

        context.coordinator.buildGround(in: world)
        context.coordinator.orbit = $orbit
        view.addGestureRecognizer(UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.pan)))
        view.addGestureRecognizer(UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.pinch)))
        let reset = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.reset))
        reset.numberOfTapsRequired = 2
        view.addGestureRecognizer(reset)

        // PROJECTED FROM THE RENDER CALLBACK, NOT FROM `updateUIView`. Two
        // reasons, and both of them bite. The camera is moved at the END of
        // `updateUIView`, so a projection taken there is against where the
        // camera was one pass ago — every handle would lag the duck by a frame
        // while orbiting, which is the whole of when it matters. And
        // `onProject` writes SwiftUI state: called from inside a view update
        // that is the "Modifying state during view update" warning and an
        // undefined pass. A frame callback is neither.
        let coordinator = context.coordinator
        coordinator.updates = view.scene.subscribe(to: SceneEvents.Update.self) {
            [weak view, weak coordinator] _ in
            MainActor.assumeIsolated {
                guard let view, let coordinator else { return }
                coordinator.project(in: view)
            }
        }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let c = context.coordinator
        // PLACED BY DUCKKIT, not by arithmetic here. `bodyPoses` works in the
        // model's world frame with the trunk already 120 mm up, and a recorded
        // root IS the trunk — setting position straight from it added the
        // offset twice and drew the robot floating by its own trunk height.
        if let duck = c.duck, duck.variant != variant, let world = c.world {
            duck.removeFromParent()
            let fresh = DuckGhostEntity(variant: variant)
            world.addChild(fresh)
            c.duck = fresh
        }
        c.duck?.place(root: pose.root, jointAngles: pose.jointAngles)
        // A contact patch under the FEET, on the floor — not under the trunk.
        // The trunk is the thing that leans, so a shadow tracking it slides out
        // from under a robot that is bending down, which reads as the robot
        // drifting rather than as the trunk moving.
        c.shadow?.position = SIMD3(pose.groundPosition.x, 0.0015, pose.groundPosition.z)
        // Handed over rather than read: the representable is a fresh struct on
        // every pass and the coordinator is the one thing that lives long
        // enough for a frame callback to hold.
        c.handles = handles
        c.onProject = onProject
        c.rebuildProps(environment, graspables: props)
        if let rolling, let ball = c.ballEntity {
            ball.position.x = Float(rolling.x)
            ball.position.z = Float(-rolling.y)
        }
        c.rebuildPath(trail)
        c.includeTrail(trail)
        c.reveal(progress: progress, ticks: trail.count)

        // Fixed looks at the middle of the run so the whole motion stays in
        // frame; following looks at the trunk. AN EXPLICIT FOCUS BEATS BOTH,
        // because it is the one that was worked out for a purpose rather than
        // derived from whatever happens to be in the scene.
        let target = orbit.focus ?? (orbit.follows
            ? SIMD3(pose.position.x, max(pose.position.y, 0.08), pose.position.z)
            : c.centre)
        c.camera?.look(at: target, from: orbit.position(target: target), relativeTo: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var duck: DuckGhostEntity?
        var camera: PerspectiveCamera?
        var world: AnchorEntity?
        var shownGraspables: [DuckScene.Prop] = []
        var props: Entity?
        var path: Entity?
        var shadow: Entity?
        var orbit: Binding<OrbitState>?
        /// The joints to project, refreshed from the representable each pass.
        var handles: [JointHandles.Handle] = []
        var onProject: ((StageProjections) -> Void)?
        /// The drawn ball, kept so `rolling` can move it without a rebuild.
        var ballEntity: ModelEntity?
        /// The frame subscription. Held here because a `Cancellable` that
        /// nobody holds is a subscription that ends immediately.
        var updates: (any Cancellable)?
        /// The last set published, so a still stage publishes nothing.
        private var sent: StageProjections?
        /// What a fixed camera looks at: the middle of everything worth seeing.
        private(set) var centre = SIMD3<Float>(0, 0.09, 0)
        private var lastScale: CGFloat = 1
        private var shownEnvironment: DuckIntentClip.Environment?
        private var shownTrail: Int = -1
        /// Each segment with the tick it ends on, so the line can be revealed
        /// against time rather than against its own index.
        private var markers: [(entity: ModelEntity, endTick: Int)] = []

        // MARK: - the floor

        /// A metre of floor, ruled.
        ///
        /// A GRID IS THE ANSWER TO "WHERE IS IT?" — a flat grey plane gives the
        /// eye nothing to measure against, so a duck 300 mm from the camera and
        /// one 300 mm further away look identical. Lines every 100 mm with a
        /// heavier one every 500 mm turn the floor into a ruler, and the robot
        /// is 250 mm tall, so a square is a recognisable fraction of it.
        func buildGround(in world: Entity) {
            let extent: Float = 1.6
            let deck = ModelEntity(
                mesh: .generateBox(width: extent * 2, height: 0.002, depth: extent * 2),
                materials: [SimpleMaterial(color: UIColor(white: 0.30, alpha: 1),
                                           roughness: 1.0, isMetallic: false)])
            deck.position = SIMD3(0, -0.001, 0)
            world.addChild(deck)

            let minor = UnlitMaterial(color: UIColor(white: 0.42, alpha: 1))
            let major = UnlitMaterial(color: UIColor(white: 0.62, alpha: 1))
            var line = -extent
            while line <= extent + 1e-4 {
                let isMajor = abs(line.truncatingRemainder(dividingBy: 0.5)) < 1e-3
                    || abs(abs(line.truncatingRemainder(dividingBy: 0.5)) - 0.5) < 1e-3
                let thickness: Float = isMajor ? 0.004 : 0.0015
                let material = isMajor ? major : minor
                for alongX in [true, false] {
                    let mesh = MeshResource.generateBox(
                        width: alongX ? extent * 2 : thickness,
                        height: 0.001,
                        depth: alongX ? thickness : extent * 2)
                    let entity = ModelEntity(mesh: mesh, materials: [material])
                    entity.position = alongX ? SIMD3(0, 0.0006, line) : SIMD3(line, 0.0006, 0)
                    world.addChild(entity)
                }
                // Float at the drawing site, Double in the constant: RealityKit
                // works in Float and StudioKit's caption takes Double, so the
                // conversion has to happen somewhere. It happens here, once,
                // rather than by keeping two constants that can drift.
                line += Float(StageSurface.gridMetres)
            }

            // Where the robot starts and which way it faces. Every clip is
            // de-origined to begin here, so this is not decoration — it is the
            // fixed point every distance on screen is measured from.
            let axis = ModelEntity(
                mesh: .generateBox(width: 0.16, height: 0.0016, depth: 0.006),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1))])
            axis.position = SIMD3(0.08, 0.0012, 0)
            world.addChild(axis)
            let origin = ModelEntity(
                mesh: .generatePlane(width: 0.04, depth: 0.04, cornerRadius: 0.02),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1))])
            origin.position = SIMD3(0, 0.0014, 0)
            world.addChild(origin)
        }

        // MARK: - props

        /// Draw what the motion was performed against.
        ///
        /// The duck's own frame is MuJoCo's — z up — and this is RealityKit's,
        /// so every prop goes through the same (x, z, −y) swap the robot does.
        /// One conversion, used everywhere, because a staircase built in the
        /// other handedness sits behind the duck and looks like a placement bug.
        ///
        /// `Environment.yaw` is deliberately NOT applied: the recorder already
        /// rotated the props into the clip's frame when it de-origined the run,
        /// and that field is the record of how far it turned them. Applying it
        /// again would turn the room a second time.
        /// Graspable things, drawn where they stand. A rod lies along +x
        /// unless it is standing, in which case it leans out of the floor —
        /// which is the shape that makes "the handle crosses the mouth's arc"
        /// visible rather than a number in a footer.
        func addGraspables(_ graspables: [DuckScene.Prop], to world: Entity) {
            for prop in graspables {
                let colour: UIColor = prop.shape == .ball ? .systemOrange
                    : (prop.graspHeightMillimetres == nil ? UIColor(white: 0.55, alpha: 1)
                                                          : .systemBrown)
                let thickness = Float(prop.thicknessMillimetres / 1000)
                let mesh: MeshResource
                switch prop.shape {
                case .ball:
                    mesh = .generateSphere(radius: Float(prop.length / 2))
                case .block:
                    mesh = .generateBox(size: SIMD3<Float>(repeating: Float(prop.length)))
                case .rod:
                    mesh = .generateBox(size: SIMD3<Float>(Float(prop.length),
                                                           thickness, thickness))
                }
                let entity = ModelEntity(mesh: mesh,
                                         materials: [UnlitMaterial(color: colour)])
                let x = Float(prop.x), z = Float(-prop.y)
                if prop.shape == .rod, let height = prop.graspHeightMillimetres {
                    // Leaning: one end on the floor, the grip at the height
                    // the person set. The angle follows from the two.
                    let grip = Float(height / 1000)
                    let lean = asin(min(max(grip / Float(prop.length) * 2, -1), 1))
                    entity.orientation = simd_quatf(angle: -lean, axis: SIMD3<Float>(0, 0, 1))
                    entity.position = SIMD3<Float>(x, Float(prop.length) / 2 * sin(lean), z)
                } else {
                    entity.position = SIMD3<Float>(x, max(thickness / 2, 0.005), z)
                }
                if prop.shape == .ball { ballEntity = entity }
                world.addChild(entity)
            }
        }

        func rebuildProps(_ environment: DuckIntentClip.Environment,
                          graspables: [DuckScene.Prop] = []) {
            // The graspables are part of the comparison: a broom that moved,
            // or grew heavier, has to redraw, and an environment that did not
            // change would otherwise hold the old one on screen.
            guard let props, shownEnvironment != environment || shownGraspables != graspables
            else { return }
            shownEnvironment = environment
            shownGraspables = graspables
            ballEntity = nil
            props.children.removeAll()
            addGraspables(graspables, to: props)

            var block = PhysicallyBasedMaterial()
            block.baseColor = .init(tint: UIColor(red: 0.62, green: 0.56, blue: 0.48, alpha: 1))
            block.roughness = 0.85
            block.metallic = 0.0
            var wallMaterial = PhysicallyBasedMaterial()
            wallMaterial.baseColor = .init(tint: UIColor(red: 0.44, green: 0.48, blue: 0.56, alpha: 1))
            wallMaterial.roughness = 0.9
            wallMaterial.metallic = 0.0

            // A BOUNDING BOX, NOT A MEAN. Averaging the props pulled the
            // fixed camera two-thirds of the way up a four-step flight, and
            // `climb` then spent 96 of its 206 ticks outside the frustum while
            // `riser_up` spent 94 of 154 outside it. A box that contains
            // everything worth seeing contains the robot too.
            var low = SIMD3<Float>(0, 0, 0)
            var high = SIMD3<Float>(0, 0.18, 0)
            func include(_ point: SIMD3<Float>) {
                low = SIMD3(Swift.min(low.x, point.x), Swift.min(low.y, point.y),
                            Swift.min(low.z, point.z))
                high = SIMD3(Swift.max(high.x, point.x), Swift.max(high.y, point.y),
                             Swift.max(high.z, point.z))
            }

            for step in environment.steps {
                let entity = ModelEntity(
                    mesh: .generateBox(width: Float(step.halfDepth * 2),
                                       height: Float(step.halfHeight * 2),
                                       depth: Float(step.halfWidth * 2),
                                       cornerRadius: 0.002),
                    materials: [block])
                // `top` is the upper face; the box centre sits half a height
                // below it, which is what stops a 10 mm step floating.
                entity.position = SIMD3(Float(step.x),
                                        Float(step.top - step.halfHeight),
                                        Float(-step.y))
                props.addChild(entity)

                // A bright lip along the leading edge. A 10 mm step drawn as a
                // grey box on a grey floor is invisible at any camera angle
                // that matters, and it is the single most important thing in
                // the scene: it is what the move either clears or does not.
                let lip = ModelEntity(
                    mesh: .generateBox(width: 0.004, height: 0.0025,
                                       depth: Float(step.halfWidth * 2)),
                    materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.78,
                                                             blue: 0.25, alpha: 1))])
                lip.position = SIMD3(Float(step.x - step.halfDepth),
                                     Float(step.top) + 0.0014,
                                     Float(-step.y))
                props.addChild(lip)
                include(SIMD3(Float(step.x - step.halfDepth), Float(step.top),
                              Float(-step.y - step.halfWidth)))
                include(SIMD3(Float(step.x + step.halfDepth), Float(step.top),
                              Float(-step.y + step.halfWidth)))
            }
            for wall in environment.walls {
                let entity = ModelEntity(
                    mesh: .generateBox(width: Float(wall.halfLength * 2),
                                       height: Float(wall.height),
                                       depth: Float(wall.halfThickness * 2)),
                    materials: [wallMaterial])
                entity.position = SIMD3(Float(wall.x),
                                        Float(wall.height / 2),
                                        Float(-wall.y))
                props.addChild(entity)
                include(SIMD3(Float(wall.x - wall.halfLength), Float(wall.height),
                              Float(-wall.y)))
                include(SIMD3(Float(wall.x + wall.halfLength), 0, Float(-wall.y)))
            }
            centre = (low + high) / 2
        }

        /// Take the path into account too, so a motion that walks away from its
        /// props is still framed. Called after the trail is built, because the
        /// trail is the half of the scene the props cannot describe.
        func includeTrail(_ trail: [DuckIntentClip.Root]) {
            guard !trail.isEmpty else { return }
            var low = centre, high = centre
            for root in trail {
                let point = SIMD3(Float(root.x), Float(root.z), Float(-root.y))
                low = SIMD3(Swift.min(low.x, point.x), Swift.min(low.y, point.y),
                            Swift.min(low.z, point.z))
                high = SIMD3(Swift.max(high.x, point.x), Swift.max(high.y, point.y),
                             Swift.max(high.z, point.z))
            }
            centre = (low + high) / 2
        }

        // MARK: - the path

        /// Where the robot has been, as a line on the floor.
        ///
        /// ONE SEGMENT PER TICK, AND EACH REMEMBERS WHICH TICK IT ENDS ON.
        /// The first version walked a four-tick stride and then revealed
        /// `round(count * progress)` segments — indexing surviving SEGMENTS
        /// rather than TIME. Two errors compounded: a stride of four means the
        /// line can only end on every fourth tick, and dropping the
        /// sub-0.1 mm segments made the index drift further still. Measured
        /// against where the duck actually is, the head of the trail was out by
        /// 255 mm on `roulade`, 91 mm on `climb`, 67 mm on `lever_up`. A line
        /// that leads the robot by a quarter of a metre is worse than no line:
        /// it looks like the robot is behind where it has got to.
        ///
        /// Per-tick segments with an explicit end tick fix both, and the tail
        /// is no longer dropped — the old loop stopped four ticks short and
        /// silently lost the end of every clip.
        func rebuildPath(_ trail: [DuckIntentClip.Root]) {
            guard let path, shownTrail != trail.count else { return }
            shownTrail = trail.count
            path.children.removeAll()
            markers.removeAll()
            guard trail.count > 1 else { return }

            let material = UnlitMaterial(color: UIColor(red: 0.35, green: 0.75,
                                                        blue: 1, alpha: 1))
            for index in 1..<trail.count {
                let a = trail[index - 1], b = trail[index]
                let dx = Float(b.x - a.x), dz = Float(-(b.y - a.y))
                let length = (dx * dx + dz * dz).squareRoot()
                // A stationary tick contributes no segment — a zero-length box
                // is a degenerate mesh — but it still advances the clock,
                // which is why the tick is stored rather than inferred from a
                // position in the array.
                guard length > 1e-4 else { continue }
                let segment = ModelEntity(
                    mesh: .generateBox(width: length, height: 0.0012, depth: 0.005),
                    materials: [material])
                segment.position = SIMD3(Float(a.x) + dx / 2, 0.0022, Float(-a.y) + dz / 2)
                segment.orientation = simd_quatf(angle: -atan2(dz, dx), axis: SIMD3(0, 1, 0))
                segment.isEnabled = false
                path.addChild(segment)
                markers.append((entity: segment, endTick: index))
            }
        }

        /// Show the part of the path already walked.
        ///
        /// Compared against the TICK the playhead is on, the same way
        /// `DuckIntentClip.pose(at:)` samples — which floors rather than
        /// rounds, so rounding here would put the line half a tick ahead of the
        /// robot drawing it.
        func reveal(progress: Double, ticks: Int) {
            guard !markers.isEmpty, ticks > 1 else { return }
            let now = min(max(progress, 0), 1) * Double(ticks - 1)
            for marker in markers {
                marker.entity.isEnabled = Double(marker.endTick) <= now
            }
        }

        // MARK: - the handles, on the glass

        /// How far a projected point has to move before the overlay is told.
        ///
        /// HALF A POINT, WHICH IS UNDER ONE PIXEL ON EVERY DEVICE THIS SHIPS
        /// TO. A stage nobody is touching still re-renders sixty times a
        /// second, and the camera's own floating-point noise moves a projection
        /// by a fraction of a point each time. Publishing that is a SwiftUI
        /// pass over fourteen targets for a picture that has not changed.
        /// Below half a point the eye cannot see the difference and the display
        /// cannot draw it.
        static let stillEnough = 0.5

        /// Where every handle is on the glass this frame, published if it moved.
        ///
        /// THE ONE LEGAL CONVERSION, AND IT IS THE WHOLE METHOD.
        /// `handle.pivot`, `.grip` and `.swung` are in the MODEL's world frame
        /// — floor origin, z up, `trunk_base` already 120 mm up — which is not
        /// RealityKit's and is not the duck entity's either, because the editor
        /// drops the body by the pose's own ground clearance. Going through
        /// `DuckGhostEntity.rk` and then the duck's own `convert` absorbs both:
        /// the change of basis and wherever the entity was placed. A handle
        /// worked out any other way floats by 116 mm, which is the exact bug
        /// `place(root:jointAngles:)` exists to have fixed once.
        func project(in view: ARView) {
            guard let onProject else { return }
            guard let duck, !handles.isEmpty else {
                // A stage that has just lost its handles has to say so, or the
                // overlay keeps drawing the last set over a duck that no longer
                // has them.
                if sent != nil { sent = nil; onProject(StageProjections()) }
                return
            }
            let eye = camera?.position(relativeTo: nil) ?? .zero
            func world(_ point: DuckVector) -> SIMD3<Float> {
                duck.convert(position: DuckGhostEntity.rk(point), to: nil)
            }
            func screen(_ point: SIMD3<Float>) -> JointHandles.ScreenPoint? {
                guard let flat = view.project(point) else { return nil }
                return JointHandles.ScreenPoint(x: Double(flat.x), y: Double(flat.y))
            }

            var made: [StageProjection] = []
            made.reserveCapacity(handles.count)
            for handle in handles {
                // A POINT BEHIND THE CAMERA PROJECTS TO NOTHING, and `project`
                // says so by answering nil rather than by answering a point
                // mirrored to the wrong side of the screen. All three have to
                // be on the glass for the drag law to mean anything, so any
                // nil leaves this handle out of the set entirely.
                let grip = world(handle.grip)
                guard let onPivot = screen(world(handle.pivot)),
                      let onGrip = screen(grip),
                      let onSwung = screen(world(handle.swung)) else { continue }
                made.append(StageProjection(joint: handle.joint, pivot: onPivot,
                                            grip: onGrip, swung: onSwung,
                                            depth: Double(simd_distance(grip, eye))))
            }
            let trunk = world(DuckKinematics.trunkOriginInModelFrame)
            let next = StageProjections(handles: made,
                                        trunkDepth: Double(simd_distance(trunk, eye)))
            guard changed(from: sent, to: next) else { return }
            sent = next
            onProject(next)
        }

        /// Whether anything the overlay draws has actually changed.
        ///
        /// AXES SEPARATELY, NOT A DISTANCE. There is no geometry in this — it
        /// is a comparison against a threshold, and taking a square root to
        /// make it a circle rather than a square would be arithmetic in the app
        /// target for a difference of a fifth of a point.
        private func changed(from old: StageProjections?, to new: StageProjections) -> Bool {
            guard let old, old.handles.count == new.handles.count else { return true }
            for (was, now) in zip(old.handles, new.handles) {
                if was.joint != now.joint { return true }
                // The DEPTH matters only through the one thing it decides —
                // whether this joint is drawn dim — so a duck rotating away
                // from the camera publishes when a leg crosses behind it and
                // not on every millimetre before that.
                if (was.depth > old.trunkDepth) != (now.depth > new.trunkDepth) { return true }
                if apart(was.pivot, now.pivot) || apart(was.grip, now.grip)
                    || apart(was.swung, now.swung) { return true }
            }
            return false
        }

        private func apart(_ a: JointHandles.ScreenPoint,
                           _ b: JointHandles.ScreenPoint) -> Bool {
            abs(a.x - b.x) >= Self.stillEnough || abs(a.y - b.y) >= Self.stillEnough
        }

        // MARK: - gestures

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let orbit else { return }
            let t = g.translation(in: g.view)
            orbit.wrappedValue.drag(dx: Float(t.x), dy: Float(t.y))
            // Reset the translation each tick so it reads as a rate rather than
            // an absolute — otherwise one long drag accelerates away.
            g.setTranslation(.zero, in: g.view)
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let orbit else { return }
            if g.state == .began { lastScale = 1 }
            let delta = g.scale / max(lastScale, 0.0001)
            lastScale = g.scale
            orbit.wrappedValue.zoom(by: Float(delta))
        }

        @objc func reset(_ g: UITapGestureRecognizer) {
            orbit?.wrappedValue.resetView()
        }
    }
}

// MARK: - the numbers the legend writes down for itself

/// Dimensions that are layout decisions rather than facts.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST, which is the line `Theme` draws and
/// this file stays behind — the same split `DriveMetric` makes one screen over.
/// A contrast ratio is a fact about two colours and lives in `Palette`, where
/// `swift test` runs the WCAG formula over it. How thick to draw a rule is not
/// a fact about anything; it is a judgement about a phone.
private enum StageMetric {
    /// The radius of the panel the legend sits on.
    ///
    /// THE CONCENTRIC RULE, TAKEN RATHER THAN CHOSEN. A stage viewport is
    /// clipped to `Palette.Radius.group` — `DriveView` does exactly that — and
    /// this panel is drawn inside it, so it takes the next radius down. Written
    /// as `.group.inner` rather than as `.card`, the pair cannot drift: change
    /// the viewport's radius and the panel's follows.
    static let panel = Palette.Radius.group.inner

    /// A hairline STROKE, the app's one.
    static let hairlineStroke = DesignMetric.hairlineStroke

    /// The smallest thing a finger is asked to hit — the app's one 44, by name.
    /// It is a floor and not a size: the chip below is wider than this because
    /// its label makes it so, and taller than this at every text size past the
    /// default. This used to be a second copy, with a paragraph explaining that
    /// the first was private to its file; the first is not private any more.
    static let minimumTarget = DesignMetric.minimumTarget

    /// How far the camera chip's word may shrink before it is allowed to clip.
    ///
    /// A LAST RESORT WITH A NUMBER ON IT, NOT A LAYOUT STRATEGY. Every other
    /// piece of text on this panel wraps and takes the height it needs; the chip
    /// cannot, because "Following" is one word with nowhere to break and a
    /// capsule is not a paragraph. Seven tenths is chosen against the case that
    /// bites: a footnote at AX5 is about forty-four points, and seven tenths of
    /// that is around thirty — over twice the size the same word is drawn at by
    /// default, so nobody who enlarged the type is pushed back below where they
    /// started. Lower would buy width nobody needs at the cost of undoing the
    /// setting; higher leaves the ellipsis it exists to prevent.
    ///
    /// NOT IN `DesignMetric`, AND NOT YET. One caller is a judgement about one
    /// chip. The moment a second control needs a floor it stops being that and
    /// becomes a token, which is the same rule this file's radius and stroke
    /// followed on their way into the design system.
    static let chipScaleFloor: CGFloat = 0.7
}

/// The unit the legend prints, written once.
///
/// ONE SPELLING, THREE ROWS. `TelemetryRow` draws the value and the unit as two
/// pieces and joins them again for VoiceOver, so a unit typed out beside each
/// axis is three chances for one of them to end up saying something else.
private enum StageUnit {
    static let millimetres = "mm"
}

/// The line of text over the stage that says what is being looked at.
///
/// A 3D VIEW WITH NO NUMBERS ON IT CANNOT BE CHECKED. "It looks about right"
/// is not a judgement anyone can act on; "it is 240 mm forward and 12 mm up,
/// against a step whose top is at 10 mm" is.
///
/// IT SITS ON A REAL SURFACE NOW, AND THAT IS THE ACCESSIBILITY DECISION HERE.
/// Every word in this legend used to be white — some of it at 65% and 45% — laid
/// straight over a live RealityKit render. The contrast of each line was
/// therefore whatever happened to be behind it that frame: a bright floor tile,
/// a dark duck, a yellow step lip, three different ratios and not one of them
/// checked by anything. `Theme.surfacePrimary` is one of the four grounds
/// `PaletteTests` proves every text token against at 4.5:1, so putting the panel
/// on it is what turns these readings into legible claims. It costs a strip of
/// the picture, which is the trade `DriveView`'s readout already made.
struct StageLegend: View {
    let pose: StagePose
    let environment: DuckIntentClip.Environment
    /// The things standing in the scene. Separate from `environment` for the
    /// same reason `DuckStage` keeps them separate, and defaulted for the same
    /// reason: a recorded clip has no Studio props. Leaving them out of the
    /// caption is what made a floor holding a broom, a dowel and a pencil read
    /// "bare floor".
    var props: [DuckScene.Prop] = []
    /// TRUE WHEN THE ROOT WAS PUT THERE RATHER THAN RECORDED. An authored draft
    /// carries joints and no root, so its preview stands the robot at the
    /// standing height and moves only the joints — deliberately, and the draft
    /// says so. Two of this legend's readings presume a recorded root and are
    /// false without one: x/y/z are then constants beside a camera-follow
    /// button with nothing to follow, and the clearance line's "nothing should
    /// be floating" is an accusation against the RENDERER, fired at a number
    /// the pinning guarantees. Measured on the real meshes: a slider-legal
    /// squat reads +39 mm, which would put that line in `Theme.warning` and the
    /// badge above it on "Floating" while the Checks tab, two taps away, says
    /// nothing is wrong.
    var rootIsPinned = false
    /// TRUE WHEN THE BODY WAS DROPPED ONTO THE FLOOR rather than left at
    /// standing height. The pose is still authored and the root is still not
    /// recorded, so `rootIsPinned` stays true beside this — what changes is
    /// that the drawn duck is standing on the ground and the reading says how
    /// far below standing the pose puts it, instead of how far its feet float.
    ///
    /// The clearance is measured against the pose at STANDING height, which is
    /// exactly the drop; measuring it at the rested root would read zero by
    /// construction and blind the guard that caught the build where every clip
    /// floated at 116 mm.
    var restedOnFloor = false
    @Binding var orbit: OrbitState

    /// Loaded once for the process. Choosing the sample points sorts through
    /// every body, which does not belong on a frame.
    /// Loaded once for the process, and shared with the screens that need to
    /// PLACE the body as well as report on it.
    static let clearance = try? DuckGroundClearance.bundled()

    /// The gesture line as it is read aloud.
    ///
    /// IT DOES NOT REPEAT THE PRINTED LINE, AND THAT IS THE WHOLE REASON IT
    /// EXISTS. The printed line ends "double-tap to reset" — which is true of
    /// the stage and FALSE of the person hearing this, because with VoiceOver
    /// running a double-tap is activation and will not reset anything. Reading
    /// the screen aloud verbatim would hand somebody an instruction that
    /// cannot work, which is a worse failure than saying nothing. So the spoken
    /// form names the route that does work: the actions rotor on the stage.
    ///
    /// A `String`, so it is spoken exactly as written rather than looked up as
    /// a key that is not there.
    private static let spokenGestures =
        "The stage above is a picture of the robot. Its actions rotor carries "
      + "orbit, zoom and reset, which are what the drag, pinch and double-tap "
      + "printed here do for a pointer."

    /// A distance in millimetres, formatted once.
    ///
    /// FORMATTING, NOT ARITHMETIC. The trunk's position is `DuckStance`'s and is
    /// tested there; all this decides is how many digits of it to draw and
    /// whether to keep the sign. The signs are kept on x and y because they are
    /// directions — "−240" and "240" are opposite sides of the origin every clip
    /// is de-origined to — and dropped on z because a trunk below the floor is
    /// not a thing the stage can draw.
    private func millimetres(_ metres: Double, signed: Bool) -> String {
        String(format: signed ? "%+.0f" : "%.0f", metres * 1000)
    }

    /// Where the trunk is: three rows, or the one sentence that replaces them.
    ///
    /// ROWS RATHER THAN ONE FORMATTED LINE, for the reason `DriveView` gives
    /// about its own readout. This was `x %+.0f · y %+.0f · z %.0f mm` — three
    /// facts in one monospaced string, which at an accessibility text size is
    /// wider than any phone and has nowhere to wrap that does not split a number
    /// from its axis, and which VoiceOver reads as a single utterance nobody can
    /// skip through. `TelemetryRow` gives each one a label that never changes
    /// beside a value that does, and stacks the pair rather than truncating the
    /// number — which is the whole point, because the person who most enlarged
    /// the text is the one the old line hid the digits from.
    ///
    /// THE PINNED CASE IS STILL ONE SENTENCE, AND IT IS THE KIT'S. Three rows of
    /// constants beside a camera-follow button invite the reader to look for
    /// travel that is not there; `StageCaption.pinnedTrunk` says what the pin IS
    /// instead, and says it where `swift test` reads it letter by letter.
    @ViewBuilder private var trunk: some View {
        if rootIsPinned {
            Text(StageCaption.pinnedTrunk(heightMetres: pose.root.z))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            TelemetryRow(label: "Trunk x",
                         value: millimetres(pose.root.x, signed: true),
                         unit: StageUnit.millimetres)
            TelemetryRow(label: "Trunk y",
                         value: millimetres(pose.root.y, signed: true),
                         unit: StageUnit.millimetres)
            TelemetryRow(label: "Trunk z",
                         value: millimetres(pose.root.z, signed: false),
                         unit: StageUnit.millimetres)
        }
    }

    /// WHERE THE FEET ARE, which is the number a viewer actually wants and the
    /// one that was wrong for a whole build. The trunk height alone cannot say
    /// it: a duck standing and a duck floating are both at 116 mm.
    private var ground: (text: String, wrong: Bool)? {
        guard let probe = Self.clearance else { return nil }
        let metres = probe.clearance(jointAngles: pose.jointAngles, root: pose.root)
        // THE NUMBER IS TRUE EITHER WAY; ONLY THE VERDICT DEPENDS ON THE ROOT.
        // Keeping the reading on a pinned stage is deliberate — it is the guard
        // that would have caught the build where every clip floated at 116 mm —
        // but nothing there is wrong, so nothing there takes the warning token
        // and the badge above it still reads "Standing".
        if restedOnFloor {
            // `metres` here is the clearance of the pose at standing height,
            // because that is the pose this legend was handed — so it IS the
            // drop, and nothing is floating on screen.
            return (StageCaption.restedGround(dropMetres: metres), false)
        }
        guard !rootIsPinned else {
            return (StageCaption.pinnedGround(clearanceMetres: metres), false)
        }
        return (DuckGroundClearance.summary(clearanceMetres: metres),
                DuckGroundClearance.isWrong(clearanceMetres: metres))
    }

    /// The word on the camera button, and the word VoiceOver reads as its
    /// value. ONE SOURCE FOR BOTH: written twice, the spoken half is the half
    /// that drifts, and a button that says "Fixed" while announcing "Following"
    /// is worse than one that announces nothing. `LocalizedStringKey` rather
    /// than `String` because a `String` handed to `Label` is rendered verbatim
    /// and would drop out of any future translation.
    private var followWord: LocalizedStringKey { orbit.follows ? "Following" : "Fixed" }

    private var context: String {
        StageCaption.context(gridMetres: StageSurface.gridMetres,
                             stepCount: environment.steps.count,
                             tallestStepMetres: environment.steps.map(\.top).max() ?? 0,
                             wallCount: environment.walls.count,
                             propCount: props.count)
    }

    /// What the drawn body is doing, as a WORD.
    ///
    /// THE ORANGE USED TO BE DOING THIS JOB ON ITS OWN. A person who cannot
    /// separate an orange line of text from a white one — roughly one man in
    /// twelve — got the same legend whether the feet were on the floor or
    /// 116 mm above it, because the only thing that changed was the hue of a
    /// sentence they had to read to the end to find out. A badge puts the state
    /// first and in one word, which is the rule the dots elsewhere in this app
    /// follow.
    ///
    /// `.idle` IN BOTH CASES, AND A FLOATING DUCK IS STILL IDLE. The state is
    /// what the drawn body is DOING and a stage holds a still pose: nothing here
    /// is moving, nothing is being reached for, and something is very obviously
    /// there. So VoiceOver hears "Floating, Idle", which is the same shape
    /// `DriveView` chose deliberately when it announces "On its side, Active" —
    /// the word is the pose and the state is the activity, and they are allowed
    /// to be different things. What the badge must never do is claim the pose is
    /// fine, and the word is what stops it.
    ///
    /// THE VERDICT IS THE KIT'S, NOT THIS VIEW'S. `ground.wrong` is
    /// `DuckGroundClearance.isWrong` — floating is wrong, sinking is the meshes
    /// — so the only thing decided here is which of two words to draw.
    @ViewBuilder private var feet: some View {
        if let ground {
            // `.render`: the legend is a strip along the bottom edge of the
            // stage and reads as part of the picture, so the badge keeps its
            // pill and stays one value rather than a line in a column.
            StateBadge(text: ground.wrong ? "Floating" : "Standing", state: .idle,
                       ground: .render)
        }
    }

    /// The ground reading, in the kit's own sentence.
    ///
    /// NOTHING IS ADDED FOR A SCREEN READER HERE, AND THAT IS THE DECISION.
    /// `DuckGroundClearance.summary` already puts the verdict in the words —
    /// "nothing should be floating" — and `isWrong` only colours what the
    /// sentence said. A spoken "warning" bolted on top would be a second
    /// verdict, composed in a view, able to disagree with the kit's. The badge
    /// above carries the state; this carries the number and the reason.
    ///
    /// `Theme.warning`, NOT `Theme.refused`. Nothing refused anything — the
    /// bench did not say no, a renderer drew a body off the floor — and the
    /// palette keeps a separate colour for a refusal precisely so that
    /// distinction survives.
    @ViewBuilder private var groundSentence: some View {
        if let ground {
            Text(ground.text)
                .font(.caption2)
                .foregroundStyle(ground.wrong ? Theme.warning : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The camera toggle, as a chip.
    ///
    /// FORTY-FOUR POINTS, AND THIS TIME MEASURED RATHER THAN ASSERTED. It began
    /// as `.bordered` at `.controlSize(.mini)` — a control around twenty points
    /// tall, well under the HIG's floor, sitting on top of a live 3D render
    /// where the penalty for missing it is that the pan recogniser underneath
    /// swings the camera instead. The repair claimed the spacing scale had
    /// settled it: "`.standard` either side of a footnote and `.snug` above and
    /// below it is comfortably past the floor in both directions, off the
    /// spacing scale alone". Add it up and it is not. A footnote's line box is
    /// about eighteen points at the default text size, and `.snug` above plus
    /// `.snug` below is twenty-four, which makes forty-two — two points short of
    /// the floor, at the one text size most people are actually on, in a comment
    /// that said the opposite. Nothing in the app could have contradicted it:
    /// a padding is a number typed here and a rendered height is not, so the
    /// claim was never checked against anything.
    ///
    /// So the floor is now ASKED FOR, in the units it is specified in. It stays
    /// a floor rather than a size — the paddings still decide the chip at every
    /// text size past the default, where the label alone already clears 44 — and
    /// the fill, the rim and the hit-testing shape are all applied after it, so
    /// what a finger can land on is the same 44 points the eye is offered.
    ///
    /// THE WORD IS THE STATE, NOT THE WASH. `surfaceInteractive` differs from
    /// its ground by about 1.02:1 in light, which `Theme` says in as many words
    /// is a hint and not information, so the fill is not what tells anybody the
    /// camera is following. "Fixed" and "Following" are, and the weight of the
    /// word is a third signal for somebody who reads shape before colour.
    ///
    /// "FOLLOWING" ON ITS OWN NAMES NOTHING, which is why the label and the
    /// value are split. On screen the word sits beside the trunk reading under a
    /// stage, and that is the whole of its context; read out in a list of
    /// controls it could be following anything. Naming the thing and letting the
    /// state be the value is also what makes VoiceOver announce the change when
    /// it is toggled.
    ///
    /// AND THE WORD IS THE STATE, SO THE WORD MAY NOT BE THE THING THAT GETS
    /// CUT. This was `.lineLimit(1)` with no floor under it. A footnote at AX5
    /// is around forty-four points; "Following" is nine characters of it beside
    /// a symbol, and the panel it sits in has `.snug` outside and `.snug` in
    /// again before the chip's own `.standard` either side — which on a 320-point
    /// phone leaves the label a little over two hundred points to live in. One
    /// line and no floor is an ellipsis, and "Follow…" against "Fixed" is a
    /// control whose two states are told apart by the part that was cut off.
    ///
    /// SO IT WRAPS FIRST AND SHRINKS ONLY IF IT MUST. Dropping the line limit is
    /// what lets a label with a break opportunity in it take a second line —
    /// which is the case the day this word is translated, since most languages
    /// spell this as two. "Following" has no such opportunity, so
    /// `StageMetric.chipScaleFloor` stands behind the wrap, and that constant
    /// carries the arithmetic for why the number is what it is. The 44-point
    /// target is a `minWidth`/`minHeight` and untouched by either: a chip that
    /// grows to two lines grows past the floor, never under it.
    private var cameraChip: some View {
        Button {
            orbit.follows.toggle()
        } label: {
            Label(followWord,
                  systemImage: orbit.follows ? "location.fill" : "mappin.and.ellipse")
                .font(.footnote.weight(orbit.follows ? .semibold : .regular))
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(StageMetric.chipScaleFloor)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(orbit.follows ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.spacing(.standard))
                .padding(.vertical, Theme.spacing(.snug))
                // BOTH DIRECTIONS, BECAUSE THE HIG SPECIFIES BOTH. The width is
                // never the binding one here — "Following" beside a symbol is
                // far wider than 44 — but a minimum that is only asserted for
                // the dimension that currently needs it is a minimum that stops
                // being true the day somebody shortens the word.
                .frame(minWidth: StageMetric.minimumTarget,
                       minHeight: StageMetric.minimumTarget)
                .background { if orbit.follows { Capsule().fill(Theme.surfaceInteractive) } }
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: StageMetric.hairlineStroke))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Camera"))
        .accessibilityValue(Text(followWord))
    }

    /// Whether the readings are open. Remembered across screens, because a
    /// person who wants the numbers wants them on every stage, and one who
    /// wants the duck wants the duck on every stage.
    @AppStorage("stage.legend.expanded") private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            // COLLAPSED BY DEFAULT, BECAUSE THE FULL LEGEND HID THE DUCK. On a
            // phone, in the clip player's 340-point viewport, the badge, three
            // trunk rows, the ground sentence, the camera chip, the context
            // line and the gesture hint stacked to two thirds of the picture —
            // and a standing duck at the default camera distance sits exactly
            // where that card was. Craig's screenshot of build 41 showed a
            // grid, a legend and no robot. A stage's first job is the robot;
            // the numbers are one tap away and stay open once opened.
            HStack(spacing: Theme.spacing(.tight)) {
                feet
                if !expanded {
                    Text(trunkZLine)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .accessibilityLabel(Text("Trunk height"))
                        .accessibilityValue(Text(trunkZLine))
                }
                Spacer(minLength: Theme.spacing(.tight))
                if !rootIsPinned { cameraChip }
                disclosure
            }
            if expanded {
                trunk
                groundSentence
                Text(context)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // THREE GESTURES, TO A READER WHO MAY BE ABLE TO MAKE NONE OF
                // THEM. The printed line is right for a finger and a dead end
                // without one, and "double-tap" means something else entirely
                // once VoiceOver is on. The words on screen do not change — a
                // sighted person is being told the truth — but what is read
                // aloud names the other route, because a stage with actions on
                // it is only useful to somebody who knows to look for them.
                Text("Drag to orbit · pinch to zoom · double-tap to reset")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(Self.spokenGestures))
            }
        }
        // TIGHT PADDING, BECAUSE THE ROW IS ALREADY 44 POINTS: the two chips set its
        // height, and snug padding inside and out put a 92-point strip over a
        // 300-point stage — over the quarter the rule allows. Tight brings it
        // to 76, and nothing in the row is smaller than its floor.
        .padding(Theme.spacing(.tight))
        // FULL WIDTH, NEVER TALL. Width is free — the duck is centred and a strip
        // along the bottom edge does not reach it; height is what covers a
        // robot, and the collapsed row is one badge, one number and two chips.
        // Expanded, the longest sentence — the pinned-trunk clearance reading,
        // over a hundred characters — still wraps across the full width rather
        // than becoming a column of single words at large text sizes.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: panel)
        .overlay(panel.strokeBorder(Theme.separator,
                                    lineWidth: StageMetric.hairlineStroke))
        .padding(Theme.spacing(.tight))
    }

    /// The one number the collapsed row keeps: how high the trunk is. Height is
    /// the reading that says "standing" or "fallen" at a glance; x and y are
    /// where on the floor, which the picture already shows.
    private var trunkZLine: String {
        "z \(millimetres(pose.root.z, signed: false)) \(StageUnit.millimetres)"
    }

    /// The chevron that opens and closes the readings. A button with a word for
    /// VoiceOver, at the same floor every other control on the stage clears.
    private var disclosure: some View {
        Button {
            withAnimation(Theme.settle) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: StageMetric.minimumTarget,
                       minHeight: StageMetric.minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(expanded ? "Hide the readings" : "Show the readings"))
        .accessibilityHint(Text("The trunk position, the ground clearance and how to move the camera."))
    }

    private var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(StageMetric.panel),
                         style: .continuous)
    }
}
