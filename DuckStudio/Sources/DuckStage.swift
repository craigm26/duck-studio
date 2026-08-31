import SwiftUI
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
    mutating func resetView() {
        let following = follows
        self = .defaults
        follows = following
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
                     props: props, trail: trail, progress: progress, orbit: $orbit)
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
        c.rebuildProps(environment, graspables: props)
        c.rebuildPath(trail)
        c.includeTrail(trail)
        c.reveal(progress: progress, ticks: trail.count)

        // Fixed looks at the middle of the run so the whole motion stays in
        // frame; following looks at the trunk.
        let target = orbit.follows
            ? SIMD3(pose.position.x, max(pose.position.y, 0.08), pose.position.z)
            : c.centre
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

/// The line of text over the stage that says what is being looked at.
///
/// A 3D VIEW WITH NO NUMBERS ON IT CANNOT BE CHECKED. "It looks about right"
/// is not a judgement anyone can act on; "it is 240 mm forward and 12 mm up,
/// against a step whose top is at 10 mm" is.
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
    /// squat reads +39 mm and turns that line orange while the Checks tab says
    /// nothing is wrong.
    var rootIsPinned = false
    @Binding var orbit: OrbitState

    /// Loaded once for the process. Choosing the sample points sorts through
    /// every body, which does not belong on a frame.
    private static let clearance = try? DuckGroundClearance.bundled()

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

    private var place: String {
        guard !rootIsPinned else {
            return StageCaption.pinnedTrunk(heightMetres: pose.root.z)
        }
        return String(format: "x %+.0f · y %+.0f · z %.0f mm",
                      pose.root.x * 1000, pose.root.y * 1000, pose.root.z * 1000)
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
        // but nothing there is wrong, so nothing there is orange.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(place).font(.caption2.monospacedDigit().weight(.medium))
                // NO TOGGLE WHERE THERE IS NOTHING TO FOLLOW. `DuckStage`
                // follows `pose.position`, which is the root; against a pinned
                // one the camera would ride a point that never moves, so the
                // control is not disabled and inert here — it is absent, and
                // the line beside it says why the root cannot move.
                if !rootIsPinned {
                    Button {
                        orbit.follows.toggle()
                    } label: {
                        Label(followWord,
                              systemImage: orbit.follows ? "location.fill" : "mappin.and.ellipse")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.white)
                    // "FOLLOWING" ON ITS OWN NAMES NOTHING. On screen the word
                    // sits beside the trunk reading and under the stage, which
                    // is the whole of its context; read out in a list of
                    // controls it could be following anything. Name the thing,
                    // and let the state be the value — which is also what makes
                    // VoiceOver announce the change when it is toggled.
                    .accessibilityLabel(Text("Camera"))
                    .accessibilityValue(Text(followWord))
                }
            }
            Text(context).font(.caption2).foregroundStyle(.white.opacity(0.65))
            // NOTHING ADDED HERE, AND THAT IS THE DECISION. Orange is the only
            // part of this line a screen reader cannot see, and it is not
            // carrying anything on its own: `DuckGroundClearance.summary` puts
            // the verdict in the words — "nothing should be floating" — and
            // `isWrong` only colours what the sentence already said. A spoken
            // "warning" bolted on top would be a second verdict, composed here,
            // able to disagree with the kit's.
            if let ground {
                Text(ground.text)
                    .font(.caption2)
                    .foregroundStyle(ground.wrong ? Color.orange : .white.opacity(0.65))
            }
            // THREE GESTURES, TO A READER WHO MAY BE ABLE TO MAKE NONE OF THEM.
            // The printed line is right for a finger and a dead end without
            // one, and "double-tap" means something else entirely once
            // VoiceOver is on. The words on screen do not change — a sighted
            // person is being told the truth — but what is read aloud names the
            // other route, because a stage with actions on it is only useful to
            // somebody who knows to look for them.
            Text("Drag to orbit · pinch to zoom · double-tap to reset")
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
                .accessibilityLabel(Text(Self.spokenGestures))
        }
        .padding(10)
        .foregroundStyle(.white)
    }
}
