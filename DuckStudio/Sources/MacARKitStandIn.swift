#if os(macOS)
import Foundation
import RealityKit
import simd

/// The slice of ARKit this app names, on a Mac that has no ARKit.
///
/// INERT BY CONSTRUCTION, AND THAT IS THE WHOLE CONTRACT. Every AR path in the
/// app already begins at `ARWorldTrackingConfiguration.isSupported` or at
/// `CameraDoor` — the same checks that turned "Your floor" off for an iPad
/// with no world tracking. Here `isSupported` is `false`, so those checks
/// refuse with the sentence they already have, and nothing below is ever asked
/// to do real work: a session that runs nothing, a raycast that hits nothing.
/// The types exist so the iOS source compiles unchanged, not so a Mac can
/// pretend to track a floor.
///
/// IF ONE OF THESE IS EVER REACHED, THE BUG IS THE GATE, NOT THIS FILE. A
/// raycast that returns no hits on a Mac is correct; a screen that raycasts on
/// a Mac without having asked `isSupported` first is the defect.

final class ARWorldTrackingConfiguration {
    static var isSupported: Bool { false }

    struct PlaneDetection: OptionSet {
        let rawValue: Int
        static let horizontal = PlaneDetection(rawValue: 1)
        static let vertical = PlaneDetection(rawValue: 2)
    }
    enum EnvironmentTexturing { case none, manual, automatic }

    var planeDetection: PlaneDetection = []
    var environmentTexturing = EnvironmentTexturing.none
}

protocol ARSessionDelegate: AnyObject {}

final class ARSession {
    struct RunOptions: OptionSet {
        let rawValue: Int
        static let resetTracking = RunOptions(rawValue: 1)
        static let removeExistingAnchors = RunOptions(rawValue: 2)
    }
    weak var delegate: ARSessionDelegate?
    func run(_ configuration: ARWorldTrackingConfiguration, options: RunOptions = []) {}
    func pause() {}
}

class ARAnchor {
    let identifier = UUID()
    var transform = matrix_identity_float4x4
}

final class ARPlaneAnchor: ARAnchor {
    enum Alignment { case horizontal, vertical }
    struct Extent { var width: Float = 0; var height: Float = 0 }
    var center = SIMD3<Float>.zero
    var planeExtent = Extent()
    var alignment = Alignment.horizontal
}

struct ARError {
    enum Code: Int { case cameraUnauthorized = 103 }
}

struct ARRaycastResult {
    var worldTransform = matrix_identity_float4x4
}

enum ARRaycastQuery {
    enum Target { case existingPlaneGeometry, existingPlaneInfinite, estimatedPlane }
    enum TargetAlignment { case horizontal, vertical, any }
}

@MainActor
private let inertSession = ARSession()

extension ARView {
    enum CameraMode { case ar, nonAR }

    /// A Mac's ARView is always the non-AR kind: a RealityKit scene with a
    /// virtual camera, which is what every venue but "Your floor" already is.
    convenience init(frame: CGRect, cameraMode: CameraMode, automaticallyConfigureSession: Bool) {
        self.init(frame: frame)
    }

    var cameraMode: CameraMode {
        get { .nonAR }
        set {}
    }

    var session: ARSession { inertSession }

    func raycast(from point: CGPoint, allowing target: ARRaycastQuery.Target,
                 alignment: ARRaycastQuery.TargetAlignment) -> [ARRaycastResult] { [] }
}

extension ARView.Environment.Background {
    /// There is no camera feed behind a Mac's scene; black is what an AR view
    /// shows before its first frame, so it is the least surprising stand-in.
    static func cameraFeed() -> ARView.Environment.Background { .color(.black) }
}
#endif
