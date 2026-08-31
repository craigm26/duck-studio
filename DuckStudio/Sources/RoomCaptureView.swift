import SwiftUI
import ARKit
import RealityKit
import Combine
import DuckKit
import StudioKit

/// Scan a room, get a MuJoCo scene the duck can be trained in.
///
/// A policy trained only in an empty box meets its first coffee table as a
/// surprise. This turns the room you are standing in into an MJCF file — floor
/// extent plus the obstacles on it — so the same simulator that produced the
/// walking policy can run against your actual furniture.
///
/// THE REDUCTION CONTAINS NO ARKIT AND THE ARKIT LAYER MAKES NO DECISIONS.
/// `DuckRoomReduction` — in DuckKit, with its own tests that run on a Pi — is a
/// pure function from six doubles per plane to a `DuckSceneMJCF.Capture`. This
/// file's whole job is reading `ARPlaneAnchor`s into that input. When those two
/// get mixed the geometry stops being testable anywhere but on a phone in a
/// room, and geometry is exactly the part that is easy to get subtly, silently
/// wrong: a mirrored scene, or one a metre off, still looks like a room.
///
/// PLANES, NOT THE LiDAR MESH. Scene reconstruction gives a far better surface
/// and only exists on Pro hardware, and `DuckSceneMJCF.Obstacle` is a box
/// either way — so a mesh would have to be reduced to its bounding box, which
/// is roughly what the plane already is. Planes work on every ARKit device.
///
/// AND IT HAS NO STAGE VERSION EITHER, for a different reason from Follow me's.
/// Follow me could be faked and must not be; this one cannot be faked at all —
/// what it writes out is the floor and the furniture ARKit found in the room
/// you are standing in, and with no camera there is nothing to find. So when
/// the door is shut it refuses outright rather than opening an ARView over a
/// session that will never run. The sentence is composed in
/// `CameraAvailability`, where `swift test` reads it.
struct RoomCaptureView: View {

    @StateObject private var capture = RoomCaptureModel()
    /// Checked here as well as in the Lab's row, because the unconditional
    /// `ARView(cameraMode: .ar)` this replaces is the shape of the bug that
    /// killed build 27.
    @State private var door = CameraDoor.availability

    var body: some View {
        Group {
            if let refusal = door.refusal(for: .roomCapture) {
                ContentUnavailableView(CameraAvailability.Dependent.roomCapture.title,
                                       systemImage: "video.slash",
                                       description: Text(refusal))
            } else {
                scanning
            }
        }
        .refreshingCameraDoor($door)
        .navigationTitle("Room capture")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $capture.showingScene) {
            NavigationStack {
                ScrollView {
                    Text(capture.mjcf)
                        .font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("captured-room.xml")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { capture.showingScene = false }
                    }
                }
            }
        }
    }

    /// The scan itself. Reached only when the door is open, so
    /// `RoomCaptureContainer` builds its `ARView` on the strength of this
    /// branch having been taken.
    private var scanning: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureContainer(model: capture).ignoresSafeArea()

            VStack(spacing: 10) {
                Text(capture.status)
                    .font(.footnote)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                HStack(spacing: 20) {
                    Label("\(capture.planeCount)", systemImage: "square.stack.3d.up")
                    if let floor = capture.floorExtent {
                        Text(String(format: "%.1f × %.1f m", floor.0 * 2, floor.1 * 2))
                            .font(.caption.monospacedDigit())
                    }
                }
                .font(.caption)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

                Button("Write the scene") { capture.emit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(capture.floorExtent == nil)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - the session

@MainActor
final class RoomCaptureModel: ObservableObject {
    @Published var status = "Walk the room slowly. Look at the floor, then the walls."
    @Published var planeCount = 0
    @Published var floorExtent: (Double, Double)?
    @Published var showingScene = false
    @Published var mjcf = ""

    /// Latest reading of every plane, keyed by anchor so an update replaces
    /// rather than duplicates. ARKit grows and merges planes constantly; a
    /// list that only ever appended would describe a room full of ghosts.
    var planes: [UUID: DuckRoomReduction.ScannedPlane] = [:]

    func refresh() {
        planeCount = planes.count
        guard let capture = try? DuckRoomReduction.reduce(planes: Array(planes.values)) else {
            floorExtent = nil
            return
        }
        floorExtent = (capture.floorHalfX, capture.floorHalfY)
    }

    func emit() {
        guard let capture = try? DuckRoomReduction.reduce(planes: Array(planes.values)) else { return }
        mjcf = DuckSceneMJCF.scene(from: capture)
        showingScene = true
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    @ObservedObject var model: RoomCaptureModel

    /// REACHED ONLY WHEN THE DOOR IS OPEN — see `RoomCaptureView.body`. The
    /// `isSupported` guard below is kept anyway: it is the ARKit-side check
    /// this file has always had, and a second reading of a fact costs nothing
    /// next to a session started on a device that cannot hold one.
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        guard ARWorldTrackingConfiguration.isSupported else {
            model.status = "This device cannot do world tracking."
            return view
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        view.session.delegate = context.coordinator
        view.session.run(config)
        context.coordinator.model = model
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}

    func makeCoordinator() -> RoomCaptureCoordinator { RoomCaptureCoordinator() }

    static func dismantleUIView(_ view: ARView, coordinator: RoomCaptureCoordinator) {
        view.session.pause()
    }
}

final class RoomCaptureCoordinator: NSObject, ARSessionDelegate {

    @MainActor var model: RoomCaptureModel?

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { absorb(anchors) }
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { absorb(anchors) }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let ids = anchors.compactMap { ($0 as? ARPlaneAnchor)?.identifier }
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            guard let model else { return }
            for id in ids { model.planes.removeValue(forKey: id) }
            model.refresh()
        }
    }

    /// Read the anchors into plain numbers and hand them over. Everything that
    /// decides anything happens in `DuckRoomReduction`, over in DuckKit.
    private nonisolated func absorb(_ anchors: [ARAnchor]) {
        let read: [(UUID, DuckRoomReduction.ScannedPlane)] = anchors.compactMap { anchor in
            guard let plane = anchor as? ARPlaneAnchor else { return nil }
            // `center` is relative to the anchor, so the plane's actual centre
            // is the anchor transform applied to it. Using the anchor's own
            // translation instead puts every plane at its original centroid and
            // they drift apart from the geometry as ARKit extends them.
            let local = SIMD4<Float>(plane.center.x, plane.center.y, plane.center.z, 1)
            let world = plane.transform * local
            // Yaw straight off the transform's first basis vector.
            let yaw = atan2(plane.transform.columns.0.z, plane.transform.columns.0.x)
            return (plane.identifier, DuckRoomReduction.ScannedPlane(
                x: Double(world.x), y: Double(world.y), z: Double(world.z),
                extentX: Double(plane.planeExtent.width),
                extentZ: Double(plane.planeExtent.height),
                yaw: Double(yaw),
                isHorizontal: plane.alignment == .horizontal))
        }
        guard !read.isEmpty else { return }
        Task { @MainActor in
            guard let model else { return }
            for (id, plane) in read { model.planes[id] = plane }
            model.refresh()
        }
    }
}
