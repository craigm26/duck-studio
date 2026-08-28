import SwiftUI
import RealityKit
import DuckKit
import DuckRender

/// Where the camera is looking from. Spherical, because that is what an orbit
/// control naturally produces and it makes the limits obvious.
struct OrbitState: Equatable {
    var azimuth: Float = .pi / 4
    /// Clamped short of straight up and straight down: at the poles the
    /// azimuth stops meaning anything and the view snaps as you cross.
    var elevation: Float = 0.35
    /// Metres from the point being looked at. The robot is 0.25 m tall, so the
    /// useful range is close.
    var distance: Float = 0.55

    static let defaults = OrbitState()

    mutating func drag(dx: Float, dy: Float) {
        azimuth -= dx * 0.01
        elevation = min(max(elevation + dy * 0.01, -1.2), 1.2)
    }

    mutating func zoom(by scale: Float) {
        distance = min(max(distance / scale, 0.18), 2.0)
    }

    /// Camera position, looking at the trunk.
    var position: SIMD3<Float> {
        let horizontal = distance * cos(elevation)
        return SIMD3(horizontal * sin(azimuth),
                     0.10 + distance * sin(elevation),
                     horizontal * cos(azimuth))
    }
}

/// A turntable view of the robot — not AR. The bench is a place to look at a
/// pose from every side, and a camera feed behind it would be scenery.
struct DuckStage: UIViewRepresentable {
    let jointAngles: [Double]
    /// The props this motion was performed against. Nil draws bare ground.
    let environment: DuckIntentClip.Environment?
    @Binding var orbit: OrbitState

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.init(white: 0.08, alpha: 1))

        let duck = DuckGhostEntity()
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(duck)
        view.scene.addAnchor(anchor)
        context.coordinator.duck = duck

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 35
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        view.scene.addAnchor(cameraAnchor)
        context.coordinator.camera = camera

        context.coordinator.world = AnchorEntity(world: .zero)
        view.scene.addAnchor(context.coordinator.world!)
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
        context.coordinator.duck?.apply(jointAngles: jointAngles)
        context.coordinator.rebuildWorld(environment)
        context.coordinator.camera?.look(at: SIMD3<Float>(0, 0.10, 0),
                                         from: orbit.position, relativeTo: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var duck: DuckGhostEntity?
        var camera: PerspectiveCamera?
        var world: AnchorEntity?
        var orbit: Binding<OrbitState>?
        private var lastScale: CGFloat = 1
        /// What the world currently shows, so props are rebuilt only when the
        /// clip changes rather than on every frame of playback.
        private var shown: DuckIntentClip.Environment??

        /// Draw the floor and whatever the motion was recorded against.
        ///
        /// The duck's own frame is MuJoCo's — z up — and this is RealityKit's,
        /// so every prop goes through the same (x, z, −y) swap the robot does.
        /// One conversion, used everywhere, because a staircase built in the
        /// other handedness sits behind the duck and looks like a placement bug.
        func rebuildWorld(_ environment: DuckIntentClip.Environment?) {
            guard let world, shown == nil || shown! != environment else { return }
            shown = .some(environment)
            world.children.removeAll()

            let floor = UnlitMaterial(color: UIColor(white: 0.16, alpha: 1))

            let ground = ModelEntity(mesh: .generateBox(width: 2, height: 0.002, depth: 2),
                                     materials: [floor])
            ground.position = SIMD3<Float>(0, -0.001, 0)
            world.addChild(ground)

            guard let environment else { return }
            var solid = PhysicallyBasedMaterial()
            solid.baseColor = .init(tint: UIColor(white: 0.42, alpha: 1))
            solid.roughness = 0.9
            solid.metallic = 0.0

            for step in environment.steps {
                let entity = ModelEntity(
                    mesh: .generateBox(width: Float(step.halfDepth * 2),
                                       height: Float(step.halfHeight * 2),
                                       depth: Float(step.halfWidth * 2)),
                    materials: [solid])
                // `top` is the upper face; the box centre sits half a height
                // below it, which is what stops a 10 mm step floating.
                entity.position = SIMD3<Float>(Float(step.x),
                                               Float(step.top - step.halfHeight),
                                               Float(-step.y))
                world.addChild(entity)
            }
            for wall in environment.walls {
                let entity = ModelEntity(
                    mesh: .generateBox(width: Float(wall.halfLength * 2),
                                       height: Float(wall.height),
                                       depth: Float(wall.halfThickness * 2)),
                    materials: [solid])
                entity.position = SIMD3<Float>(Float(wall.x),
                                               Float(wall.height / 2),
                                               Float(-wall.y))
                world.addChild(entity)
            }
        }

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
            orbit?.wrappedValue = .defaults
        }
    }
}
