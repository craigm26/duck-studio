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
        // THE REFUSAL BRANCH NEEDS A GROUND OF ITS OWN. `scanning` covers the
        // screen with a camera feed; `ContentUnavailableView` does not, and
        // without this it would sit on whatever the system decided the window
        // was — which is the one surface in the app no test has an opinion on.
        .background(Theme.backgroundPrimary)
        .refreshingCameraDoor($door)
        .navigationTitle("Room capture")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $capture.showingScene) {
            NavigationStack {
                ScrollView {
                    // MONOSPACE IS EARNED HERE. The design system's rule is that
                    // tabular figures are a claim the thing will change, and
                    // this is an XML file whose every line is different from the
                    // last — it is also the one place in the app where column
                    // alignment is the reader's only way of scanning a
                    // generated document.
                    Text(capture.mjcf)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(Theme.spacing(.standard))
                }
                .scrollContentBackground(.hidden)
                .background(Theme.backgroundPrimary)
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
    ///
    /// THE GLASS IS GONE, AND OVER A CAMERA FEED THAT IS NOT A TASTE. Both
    /// panels here were `.ultraThinMaterial`, which means the contrast of every
    /// word on them was whatever the camera happened to be pointed at — a white
    /// wall, a dark sofa, a window — changing several times a second while the
    /// person walks the room. There is no ratio to check because there is no
    /// second colour: the ground is the room. `Theme.surfacePrimary` is one of
    /// the four grounds `PaletteTests` proves every text token against at 4.5:1,
    /// and it is opaque, so the status line and the readings stay legible over
    /// whatever the lens finds.
    private var scanning: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureContainer(model: capture).ignoresSafeArea()

            VStack(spacing: Theme.spacing(.snug)) {
                Text(capture.status)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.spacing(.standard))
                    .padding(.vertical, Theme.spacing(.tight))
                    .background(Theme.surfacePrimary, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.separator,
                                                    lineWidth: RoomMetric.hairlineStroke))

                // THE NUMBERS ARE `TelemetryRow`S BECAUSE THEY CHANGE, which is
                // the app's whole definition of telemetry — and both of these
                // change several times a second while ARKit grows and merges
                // planes. The plane count in particular used to be a bare
                // number inside a `Label`, so VoiceOver read "seven" with
                // nothing to say what seven was; a row gives it a name that
                // never changes beside a value that does, and stacks the pair
                // rather than truncating the digits when the text is large.
                VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                    TelemetryRow(label: "Planes found", value: "\(capture.planeCount)")
                    if let floor = capture.floorExtent {
                        TelemetryRow(label: "Floor",
                                     value: String(format: "%.1f × %.1f",
                                                   floor.0 * 2, floor.1 * 2),
                                     unit: RoomUnit.metres)
                    }
                }
                .padding(Theme.spacing(.snug))
                .background(Theme.surfacePrimary, in: readout)
                .overlay(readout.strokeBorder(Theme.separator,
                                              lineWidth: RoomMetric.hairlineStroke))

                // THE CAPTURE ACTION, AT THE APP'S OWN PRIMARY. It was
                // `.borderedProminent`, which is the system's accent and the
                // system's height — and this is the button the whole screen
                // exists for, pressed by somebody holding a phone up at arm's
                // length in the middle of a room. `.primaryAction` is Duck
                // Orange at the HIG's 44-point floor with a findable edge in
                // light, a real surface and real secondary text when it is
                // disabled, and a press that darkens rather than shrinking.
                //
                // NOT `.primaryActionMoves`. Sixty points is for a control that
                // moves the ROBOT; this one writes a file.
                Button("Write the scene") { capture.emit() }
                    .buttonStyle(.primaryAction)
                    .disabled(capture.floorExtent == nil)
                    .accessibilityLabel(Text("Write the scene"))
                    .accessibilityHint(Text(
                        "Turns the floor and the obstacles found so far into a MuJoCo scene file."))
            }
            .padding(.horizontal, Theme.spacing(.snug))
            .padding(.bottom, Theme.spacing(.loose))
        }
    }

    private var readout: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(RoomMetric.readout),
                         style: .continuous)
    }
}

// MARK: - the numbers and words this screen writes down for itself

/// Dimensions that are layout decisions rather than facts.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST — a ratio is a fact and lives in
/// `Palette`, where `swift test` runs the WCAG formula over it.
private enum RoomMetric {
    /// The readout's card. It floats over a camera feed rather than inside
    /// another card, so it takes `.card` rather than a step down from anything.
    static let readout = Palette.Radius.card

    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke = DesignMetric.hairlineStroke
}

/// The unit this screen prints, written once.
private enum RoomUnit {
    /// A room is metres. Everything else the app measures is millimetres,
    /// which is exactly why this is written down rather than typed twice.
    static let metres = "m"
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
