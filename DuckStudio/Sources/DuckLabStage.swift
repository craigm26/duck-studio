import UIKit
import SwiftUI
import RealityKit
import ARKit

/// A world of its own for the lab's games — floor, sky, lights and an orbit
/// camera — with no camera feed, no plane detection and no tap-to-place.
///
/// MOST OF THESE GAMES ARE BETTER WITHOUT AR, AND THE REASON IS FLOOR SPACE.
/// The slalom is 3.5 m of gates. Duck golf's long hole is 2.2 m. Bow Bridge is
/// a 4 m deck. Very few rooms have that much clear carpet, and a course that
/// cannot be laid out is a game nobody gets to play — you place it, back into
/// the sofa, and lose the far end behind a table. Nothing in these modes is
/// real anyway: the duck is a ghost, the ball is a sphere, the bridge and the
/// mountain are invented. Borrowing your carpet costs the whole room and buys
/// a backdrop.
///
/// IT ALSO STOPS ASKING FOR THE CAMERA. A stage runs no ARSession at all, so
/// opening the lab no longer prompts for camera access, works on a train, in
/// the dark, or on a device with no world tracking, and costs a fraction of
/// the battery.
///
/// AR IS KEPT WHERE IT PAYS, and it is offered on every mode as "Your floor".
/// Soccer on your own carpet is the pitch of the whole app. And FOLLOW ME
/// CANNOT BE ANYTHING ELSE: the thing it follows is the phone, and ARKit's
/// camera pose is a real measurement of where a person is standing. Swapping
/// that for a joystick would swap perception for pretend, which is the one
/// thing this lab does not do — so that mode has no stage, and says so.
enum LabVenue: String, CaseIterable, Identifiable {
    /// A rendered world. No camera, no room required.
    case stage
    /// Your actual floor, through the camera.
    case ar
    var id: String { rawValue }
    var name: String { self == .stage ? "Stage" : "Your floor" }
}

/// The palette a stage is dressed in.
struct StageTheme: Equatable {
    let name: String
    let sky: UIColor
    let floor: UIColor
    /// The grid ruled on the floor. Without it a flat colour gives the eye
    /// nothing to measure speed against and the duck looks like it is hovering
    /// in place.
    let grid: UIColor
    let accent: UIColor

    static let meadow = StageTheme(
        name: "Meadow",
        sky: UIColor(red: 0.75, green: 0.89, blue: 0.98, alpha: 1),
        floor: UIColor(red: 0.52, green: 0.78, blue: 0.50, alpha: 1),
        grid: UIColor(red: 0.44, green: 0.70, blue: 0.43, alpha: 1),
        accent: UIColor(red: 0.98, green: 0.85, blue: 0.35, alpha: 1))

    static let dusk = StageTheme(
        name: "Dusk",
        sky: UIColor(red: 0.16, green: 0.07, blue: 0.28, alpha: 1),
        floor: UIColor(red: 0.24, green: 0.11, blue: 0.36, alpha: 1),
        grid: UIColor(red: 0.45, green: 0.25, blue: 0.62, alpha: 1),
        accent: UIColor(red: 0.35, green: 0.92, blue: 0.93, alpha: 1))

    static let arcade = StageTheme(
        name: "Arcade",
        sky: UIColor(red: 0.07, green: 0.06, blue: 0.16, alpha: 1),
        floor: UIColor(red: 0.20, green: 0.13, blue: 0.34, alpha: 1),
        grid: UIColor(red: 0.36, green: 0.24, blue: 0.58, alpha: 1),
        accent: UIColor(red: 0.98, green: 0.93, blue: 0.35, alpha: 1))

    /// Snow under a cold sky, for the mountain.
    static let alpine = StageTheme(
        name: "Alpine",
        sky: UIColor(red: 0.68, green: 0.84, blue: 0.95, alpha: 1),
        floor: UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1),
        grid: UIColor(red: 0.82, green: 0.87, blue: 0.94, alpha: 1),
        accent: UIColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1))

    /// Park lawn beside water, for the bridge.
    static let park = StageTheme(
        name: "Park",
        sky: UIColor(red: 0.80, green: 0.90, blue: 0.97, alpha: 1),
        floor: UIColor(red: 0.47, green: 0.72, blue: 0.45, alpha: 1),
        grid: UIColor(red: 0.41, green: 0.65, blue: 0.40, alpha: 1),
        accent: UIColor(red: 0.35, green: 0.60, blue: 0.85, alpha: 1))

    static let choices: [StageTheme] = [.meadow, .dusk, .arcade]
}

/// The rendered world, and the camera that looks at it.
///
/// One of these replaces the whole tap-to-place dance: build it, add your
/// scenery to `root`, and call `follow` each frame with wherever the duck is.
@MainActor
final class LabStage: NSObject {
    /// Everything a mode draws goes under here. It sits at the world origin,
    /// so a mode's own coordinates are the stage's coordinates and no mode has
    /// to know it is not in AR.
    let root = AnchorEntity(world: .zero)

    private weak var view: ARView?
    private let camera = PerspectiveCamera()
    private var orbit = StadiumCamera()
    private var target = SIMD3<Float>.zero
    private var smoothed = SIMD3<Float>.zero
    /// Kept so a venue switch can take them off again. Gesture recognizers
    /// added and never removed stack up, and three pans on one view is three
    /// times the orbit speed — a bug that only shows after switching twice.
    private var recognizers: [UIGestureRecognizer] = []

    /// Build the world into `view`. The view is switched out of AR, so no
    /// session runs and no camera permission is asked for.
    /// `azimuth` defaults to looking down the +x axis from behind, because
    /// every course in the lab is laid out running +x. Getting this wrong is
    /// the stadium camera's old bug in a new place: a camera at the far end
    /// inverts the stick, and the player blames the controls.
    /// `ground: false` for a mode that brings its own — the bridge has a lake
    /// under it and the bobsled a mountainside, and a grid floor laid over
    /// either one z-fights with it.
    init(in view: ARView, theme: StageTheme, extent: Float = 8,
         distance: Float = 2.2, elevation: Float = 0.5,
         azimuth: Float = -.pi / 2, ground: Bool = true) {
        super.init()
        self.view = view
        view.cameraMode = .nonAR
        view.environment.background = .color(theme.sky)

        let key = DirectionalLight()
        key.light.intensity = 3200
        key.look(at: .zero, from: SIMD3<Float>(1.2, 2.2, 1.4), relativeTo: nil)
        root.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 1400
        fill.light.color = theme.sky
        fill.look(at: .zero, from: SIMD3<Float>(-1.4, 1.2, -1.0), relativeTo: nil)
        root.addChild(fill)

        if ground {
            let floor = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(extent, 0.004, extent)),
                materials: [UnlitMaterial(color: theme.floor)])
            floor.position.y = -0.002
            root.addChild(floor)

            // A half-metre rule in both directions. It is what makes the duck read
            // as travelling rather than sliding on the spot.
            let count = Int(extent / 0.5)
            for i in 0...count {
                let offset = -extent / 2 + Float(i) * 0.5
                for axis in 0..<2 {
                    let size = axis == 0
                        ? SIMD3<Float>(extent, 0.002, 0.006)
                        : SIMD3<Float>(0.006, 0.002, extent)
                    let line = ModelEntity(mesh: .generateBox(size: size),
                                           materials: [UnlitMaterial(color: theme.grid)])
                    line.position = axis == 0
                        ? SIMD3<Float>(0, 0.001, offset)
                        : SIMD3<Float>(offset, 0.001, 0)
                    root.addChild(line)
                }
            }
        }

        camera.camera.fieldOfViewInDegrees = 45
        root.addChild(camera)
        orbit.distance = distance
        orbit.elevation = elevation
        orbit.azimuth = azimuth

        view.scene.addAnchor(root)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.pan))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch))
        view.addGestureRecognizer(pan); view.addGestureRecognizer(pinch)
        recognizers = [pan, pinch]
        place()
    }

    /// Take the world down again, for a switch to the camera.
    func dismantle() {
        guard let view else { return }
        recognizers.forEach(view.removeGestureRecognizer)
        recognizers = []
        view.scene.removeAnchor(root)
    }

    /// Point the camera at something — the duck, usually. Smoothed, because a
    /// camera welded to a walking duck bobs with its gait and is unwatchable.
    func follow(_ position: SIMD3<Float>, smoothing: Float = 0.06) {
        target = position
        smoothed += (target - smoothed) * min(max(smoothing, 0), 1)
        place()
    }

    private func place() {
        camera.position = smoothed + orbit.position
        camera.look(at: smoothed, from: camera.position, relativeTo: nil)
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let t = gesture.translation(in: gesture.view)
        orbit.drag(dx: Float(t.x), dy: Float(t.y))
        gesture.setTranslation(.zero, in: gesture.view)
        place()
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        orbit.zoom(by: Float(gesture.scale))
        gesture.scale = 1
        place()
    }

    /// Where a tap lands on the stage floor, in world coordinates.
    ///
    /// A non-AR scene has no raycast against detected planes, so this is the
    /// plain thing: the camera ray, intersected with y = 0.
    static func groundPoint(at point: CGPoint, in view: ARView) -> SIMD3<Float>? {
        guard let ray = view.ray(through: point) else { return nil }
        guard abs(ray.direction.y) > 1e-5 else { return nil }
        let t = -ray.origin.y / ray.direction.y
        guard t > 0 else { return nil }
        return ray.origin + ray.direction * t
    }
}

/// The same two-way switch on every mode that has both.
struct VenuePicker: View {
    @Binding var venue: LabVenue
    var body: some View {
        Picker("Venue", selection: $venue) {
            ForEach(LabVenue.allCases) { v in Text(v.name).tag(v) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }
}
