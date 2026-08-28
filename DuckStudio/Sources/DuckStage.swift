import SwiftUI
import RealityKit
import DuckKit
import DuckRender
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
    var position: SIMD3<Float> {
        SIMD3(Float(root.x), Float(root.z), Float(-root.y))
    }

    /// The same change of basis for the trunk's orientation.
    var orientation: simd_quatf {
        simd_quatf(ix: Float(root.quaternion.1), iy: Float(root.quaternion.3),
                   iz: Float(-root.quaternion.2), r: Float(root.quaternion.0))
    }
}

/// A turntable view of the robot IN A PLACE — not AR. The bench is somewhere to
/// look at a pose from every side, and a camera feed behind it would be scenery.
struct DuckStage: UIViewRepresentable {
    let pose: StagePose
    /// The props to draw. Bare floor is still a place; `nil` is not.
    let environment: DuckIntentClip.Environment
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
        c.duck?.apply(jointAngles: pose.jointAngles)
        c.duck?.position = pose.position
        c.duck?.orientation = pose.orientation
        // A contact patch under the trunk, on the floor. It is the cheapest
        // possible depth cue and it does the single job nothing else does:
        // it says which part of the ground the robot is over.
        c.shadow?.position = SIMD3(pose.position.x, 0.0015, pose.position.z)
        c.rebuildProps(environment)
        c.rebuildPath(trail)
        c.reveal(progress: progress)

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
        var props: Entity?
        var path: Entity?
        var shadow: Entity?
        var orbit: Binding<OrbitState>?
        /// What a fixed camera looks at: the middle of everything worth seeing.
        private(set) var centre = SIMD3<Float>(0, 0.09, 0)
        private var lastScale: CGFloat = 1
        private var shownEnvironment: DuckIntentClip.Environment?
        private var shownTrail: Int = -1
        private var markers: [Entity] = []

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
                line += 0.1
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
        func rebuildProps(_ environment: DuckIntentClip.Environment) {
            guard let props, shownEnvironment != environment else { return }
            shownEnvironment = environment
            props.children.removeAll()

            var block = PhysicallyBasedMaterial()
            block.baseColor = .init(tint: UIColor(red: 0.62, green: 0.56, blue: 0.48, alpha: 1))
            block.roughness = 0.85
            block.metallic = 0.0
            var wallMaterial = PhysicallyBasedMaterial()
            wallMaterial.baseColor = .init(tint: UIColor(red: 0.44, green: 0.48, blue: 0.56, alpha: 1))
            wallMaterial.roughness = 0.9
            wallMaterial.metallic = 0.0

            var extremes = SIMD3<Float>(0, 0.09, 0)
            var count: Float = 1

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
                extremes += SIMD3(Float(step.x), Float(step.top), Float(-step.y))
                count += 1
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
                extremes += SIMD3(Float(wall.x), Float(wall.height / 2), Float(-wall.y))
                count += 1
            }
            centre = extremes / count
        }

        // MARK: - the path

        /// Where the robot has been, as a line on the floor.
        ///
        /// Built once for the whole run and revealed as the playhead moves,
        /// rather than rebuilt per frame: a hundred entities created sixty
        /// times a second is a stutter, and the line is the same line either
        /// way. Every fourth tick is enough to read a curve at this scale.
        func rebuildPath(_ trail: [DuckIntentClip.Root]) {
            guard let path, shownTrail != trail.count else { return }
            shownTrail = trail.count
            path.children.removeAll()
            markers.removeAll()
            guard trail.count > 1 else { return }

            let material = UnlitMaterial(color: UIColor(red: 0.35, green: 0.75,
                                                        blue: 1, alpha: 1))
            var index = 0
            while index + 4 < trail.count {
                let a = trail[index], b = trail[index + 4]
                let dx = Float(b.x - a.x), dz = Float(-(b.y - a.y))
                let length = (dx * dx + dz * dz).squareRoot()
                index += 4
                // A stationary tick contributes no segment. Drawing a
                // zero-length box gives a degenerate mesh and a warning.
                guard length > 1e-4 else { continue }
                let segment = ModelEntity(
                    mesh: .generateBox(width: length, height: 0.0012, depth: 0.005),
                    materials: [material])
                segment.position = SIMD3(Float(a.x) + dx / 2, 0.0022, Float(-a.y) + dz / 2)
                segment.orientation = simd_quatf(angle: -atan2(dz, dx), axis: SIMD3(0, 1, 0))
                segment.isEnabled = false
                path.addChild(segment)
                markers.append(segment)
            }
        }

        /// Show the part of the path already walked.
        func reveal(progress: Double) {
            guard !markers.isEmpty else { return }
            let shown = Int((Double(markers.count) * min(max(progress, 0), 1)).rounded())
            for (i, marker) in markers.enumerated() { marker.isEnabled = i < shown }
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
            let follows = orbit?.wrappedValue.follows ?? false
            var fresh = OrbitState.defaults
            fresh.follows = follows
            orbit?.wrappedValue = fresh
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
    @Binding var orbit: OrbitState

    private var place: String {
        String(format: "x %+.0f · y %+.0f · z %.0f mm",
               pose.root.x * 1000, pose.root.y * 1000, pose.root.z * 1000)
    }

    private var context: String {
        var parts = ["100 mm grid"]
        if !environment.steps.isEmpty {
            let tallest = environment.steps.map(\.top).max() ?? 0
            parts.append("\(environment.steps.count) step\(environment.steps.count == 1 ? "" : "s") to \(Int((tallest * 1000).rounded())) mm")
        }
        if !environment.walls.isEmpty {
            parts.append("\(environment.walls.count) wall\(environment.walls.count == 1 ? "" : "s")")
        }
        if environment.steps.isEmpty && environment.walls.isEmpty {
            parts.append("bare floor")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(place).font(.caption2.monospacedDigit().weight(.medium))
                Button {
                    orbit.follows.toggle()
                } label: {
                    Label(orbit.follows ? "Following" : "Fixed",
                          systemImage: orbit.follows ? "location.fill" : "mappin.and.ellipse")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.white)
            }
            Text(context).font(.caption2).foregroundStyle(.white.opacity(0.65))
            Text("Drag to orbit · pinch to zoom · double-tap to reset")
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
        .padding(10)
        .foregroundStyle(.white)
    }
}
