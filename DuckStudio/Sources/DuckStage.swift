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
        context.coordinator.camera?.look(at: SIMD3<Float>(0, 0.10, 0),
                                         from: orbit.position, relativeTo: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var duck: DuckGhostEntity?
        var camera: PerspectiveCamera?
        var orbit: Binding<OrbitState>?
        private var lastScale: CGFloat = 1

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
