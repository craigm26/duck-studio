import UIKit
import SwiftUI
import RealityKit
import ARKit
import Combine
import simd
import StudioKit
import DuckKit
import DuckRender

/// The drive, drawn on the floor you are standing on.
///
/// THE PHYSICS DOES NOT MOVE HOUSE, WHICH IS THE WHOLE THING TO UNDERSTAND
/// ABOUT THIS SCREEN. Nothing here simulates anything. The bench is still
/// running MuJoCo in a 2.9 m box on whatever machine it was running on, the
/// stick still posts `robot.move` to it, and what arrives back is fifteen joint
/// angles and a root — the same numbers `DuckStage` draws against a rendered
/// floor. This file draws them against a camera feed instead. The duck is
/// therefore a ghost of a simulation standing on your carpet: it will walk
/// through your sofa, because your sofa is not in the world it is walking in,
/// and it will stop dead at an invisible wall 1.45 m out, because that wall IS.
/// `DriveVenue.arIsReal` and `.arIsNot` are the two halves of that said on the
/// glass, and they are on screen the whole time rather than once at the start.
///
/// `DuckStage.swift` IS NOT TOUCHED AND MUST NOT BE. That file is a turntable:
/// it owns a stage, an orbit camera, a grid and a legend, and none of those
/// mean anything when the camera is a real camera in a real room. Bending it
/// into an AR view would put two incompatible worlds behind one `ARView`
/// whose `cameraMode` is decided by a caller — the shape that produces a
/// black rectangle nobody can explain. This is a second, smaller stage that
/// shares the one thing worth sharing: `DuckGhostEntity`, which is the app's
/// only drawing of the robot.
///
/// EVERY GEOMETRIC DECISION HERE IS THE SAME ONE `GhostDuckView` AND
/// `BowBridgeView` ALREADY MADE, and it is made the same way on purpose: the
/// camera door is asked immediately above `session.run`, the raycast asks for
/// measured plane geometry first and an estimate second, and the anchor is
/// yawed to the camera so that forward on the stick is away from you. A fourth
/// spelling of any of those is a fourth place for the coordinate swap to be
/// got wrong, and that error looks like a duck lying on its side rather than
/// like a bug.
struct ARDriveStage: View {

    /// The duck as the bench last reported it — the same value `DuckStage`
    /// draws.
    let pose: StagePose
    /// What the bench said its world is. Nil before the first read, and on a
    /// bench with no `/world` route at all.
    let world: DuckWorld?
    /// Where the ball is right now, off `/state`, which moves between world
    /// reads because a duck kicks it.
    let ball: DuckWorld.Point?
    /// Whether the physics and the camera are the same phone — the one
    /// arrangement nobody in this project has measured. See
    /// `DriveVenue.twoEnginesOnOnePhone`.
    let benchIsThisPhone: Bool
    /// Round trips since Drive was pressed, and what one control tick cost on
    /// the bench. BOTH ON THE GLASS BECAUSE THE COST IS UNKNOWN: the honest
    /// answer to "can this phone run MuJoCo and ARKit at once" is that nobody
    /// has timed it, and the next best thing to a measurement is the two
    /// numbers a person can watch while they find out.
    let trips: Int
    let tickMillis: Double?
    /// How far the host's floating top strip reaches down, measured there; the
    /// panel is pushed under it rather than drawn beneath it.
    var topInset: CGFloat = 0
    /// The panel's own height, reported back so the host's readout stacks
    /// under it instead of over it.
    var onHudHeight: ((CGFloat) -> Void)? = nil

    @StateObject private var model = ARDriveModel()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ARDriveContainer(model: model, pose: pose, world: world, ball: ball)
            hud
        }
        // A SESSION THAT OUTLIVES THE SCREEN IS A CAMERA AND A TRACKING THREAD
        // RUNNING BEHIND WHATEVER CAME NEXT. `dismantleUIView` covers the case
        // where the representable is torn down — switching back to Sim, or
        // leaving the tab in a way that rebuilds the hierarchy. This covers the
        // case it does not: a tab bar that keeps the screen alive off-screen,
        // where `onDisappear` fires and nothing is dismantled.
        .onAppear { model.resume() }
        .onDisappear { model.pause() }
    }

    /// What is real, what is not, and what it is costing — over the picture,
    /// on a real surface.
    ///
    /// AN OPAQUE PANEL FOR THE REASON `DriveView`'s READOUT IS ONE: text set
    /// over a live camera feed has whatever contrast the room happens to give
    /// it, which is a number nothing in this app has checked.
    /// `Theme.surfacePrimary` is one of the four grounds `PaletteTests` proves
    /// every text token against.
    /// COLLAPSED BY DEFAULT AND OUT OF THE WAY OF THE TAP. A panel taller
    /// than the viewport covered the camera feed and swallowed the one
    /// gesture that places the duck; the paragraphs now sit behind a
    /// disclosure under a one-line status, so the panel is a few lines tall
    /// and the floor stays tappable around it.
    @State private var showingWhatIsReal = false
    private var hud: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(model.status)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text(cost)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            DisclosureGroup(isExpanded: $showingWhatIsReal) {
                Text(DriveVenue.arIsReal)
                    .font(.caption2)
                    .foregroundStyle(Theme.measured)
                Text(DriveVenue.arIsNot)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                if let unmeasured = DriveVenue.twoEnginesOnOnePhone(
                    benchIsThisPhone: benchIsThisPhone) {
                    Text(unmeasured)
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                }
                // WHY THERE IS NO ZOOM COLUMN ON THIS VENUE, said inside the
                // disclosure that is already collapsed — so it costs the camera
                // feed zero added height, which is the failure this disclosure
                // exists to prevent. The camera in your hand IS the camera:
                // there is one recogniser on this stage and it places the duck,
                // and a scale factor here would falsify `DriveVenue.arIsNot`,
                // which has a test on it.
                Text(DriveVenue.arHasNoZoom)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } label: {
                Text(DriveVenue.arWhatIsRealTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Theme.spacing(.snug))
        .background(Theme.surfacePrimary, in: panel)
        .overlay(panel.strokeBorder(Theme.separator,
                                    lineWidth: DesignMetric.hairlineStroke))
        .frame(maxWidth: typeSize.isAccessibilitySize ? nil : ARDriveMetric.hudWidth,
               alignment: .leading)
        .padding(Theme.spacing(.snug))
        .measuringChromeHeight { onHudHeight?($0) }
        .padding(.top, topInset)
    }

    private var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(Palette.Radius.group.inner),
                         style: .continuous)
    }

    /// The two numbers, and no claim about them.
    ///
    /// THE TICK IS THE BENCH'S OWN MEASUREMENT AND THE TRIPS ARE THIS SCREEN'S
    /// COUNT. Neither is a frame rate and neither is presented as one: a
    /// sentence saying "AR is fine on this phone" would be exactly the
    /// invention `twoEnginesOnOnePhone` refuses to make.
    private var cost: String {
        guard let tickMillis else { return "\(trips) round trips · tick not measured" }
        return String(format: "%d round trips · %.2f ms a tick on the bench",
                      trips, tickMillis)
    }
}

/// The numbers this file writes down for itself.
private enum ARDriveMetric {
    /// How wide the honesty panel may grow before it is the whole picture. At
    /// accessibility sizes the cap lifts, for the reason `DriveView`'s readout
    /// lifts its own: a fixed frame around words somebody enlarged in order to
    /// read is a frame that hides them.
    static let hudWidth: CGFloat = 300

    /// How translucent a ghost of a simulation is. Solid enough to read as an
    /// object, thin enough that nobody mistakes it for something in the room.
    static let ghostAlpha: CGFloat = 0.38

    /// The floor line marking the world's edge: 10 mm wide, 2 mm proud, so it
    /// reads as chalk rather than as a kerb somebody could trip the duck on.
    static let edgeWidth: Float = 0.010
    static let edgeHeight: Float = 0.002
}

// MARK: - what the screen has to say back

/// The one thing the AR view tells SwiftUI: what it is doing.
@MainActor
final class ARDriveModel: ObservableObject {
    /// The line at the top of the panel — "tap the floor", "no floor there
    /// yet", or the camera door's own refusal.
    @Published var status = ARDriveModel.pointAtTheFloor

    /// Held so the screen can pause the session without owning the `ARView`.
    weak var coordinator: ARDriveCoordinator?

    func pause() { coordinator?.pause() }
    func resume() { coordinator?.resume() }

    /// The two lines this file writes, and they are the only two.
    ///
    /// THEY ARE NOT CLAIMS ABOUT ANYTHING, which is why they are not in the
    /// kit. Every sentence on this screen that says what is real, what is not,
    /// what a link carries or what a world is, is a `DriveVenue` or `DuckWorld`
    /// string with a test that reads it letter by letter. These two are
    /// instructions for a gesture — where to point a phone — and they are the
    /// same words `GhostDuckView` and `BowBridgeView` already use for the same
    /// gesture.
    static let pointAtTheFloor = DriveVenue.pointAtTheFloor
    static let noFloorThere = DriveVenue.noFloorThere
}

// MARK: - the view

private struct ARDriveContainer: UIViewRepresentable {
    @ObservedObject var model: ARDriveModel
    let pose: StagePose
    let world: DuckWorld?
    let ball: DuckWorld.Point?

    func makeUIView(context: Context) -> ARView {
        // BUILT `.nonAR` AND SWITCHED, WHICH IS `GhostDuckView`'S ORDER AND
        // MATTERS. An `ARView` that configures its own session runs one before
        // anything has checked whether it may — and a session started against
        // a plist with no camera usage description is a process iOS kills.
        let view = ARView(frame: .zero, cameraMode: .nonAR,
                          automaticallyConfigureSession: false)
        let coordinator = context.coordinator
        coordinator.attach(to: view, model: model)
        // AFTER THE VIEW IS HANDED BACK, NOT DURING. `session.run` on a view
        // SwiftUI has not finished installing is a session with no drawable to
        // render into; `GhostDuckView` hops the same way for the same reason.
        DispatchQueue.main.async { coordinator.open() }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.model = model
        context.coordinator.show(pose: pose, world: world, ball: ball)
    }

    func makeCoordinator() -> ARDriveCoordinator { ARDriveCoordinator() }

    static func dismantleUIView(_ view: ARView, coordinator: ARDriveCoordinator) {
        // An ARView left running keeps the camera and the tracking thread alive
        // behind whatever the person navigated to next.
        view.session.pause()
        coordinator.detach()
    }
}

// MARK: - the world under the anchor

@MainActor
final class ARDriveCoordinator: NSObject {

    var model: ARDriveModel?
    private weak var view: ARView?
    private var anchor: AnchorEntity?
    private var ghost: DuckGhostEntity?
    /// Everything that is not the duck — the blocks, the ball and the four
    /// chalk lines — held so a change of world can take them down without
    /// touching the anchor the person placed.
    private var furniture: Entity?
    private var updates: (any Cancellable)?
    private var opened = false

    /// The last pose handed down, read by the frame subscription rather than
    /// applied in `updateUIView`. `place` is cheap and SwiftUI's update rate is
    /// not the render rate; driving it off `SceneEvents.Update` is what keeps
    /// the duck moving smoothly between round trips instead of stepping.
    private var pending: StagePose = .home
    /// What the furniture was built from, so it is rebuilt when — and only
    /// when — the world actually changed.
    private var built: WorldSignature?

    func attach(to view: ARView, model: ARDriveModel) {
        self.view = view
        self.model = model
        model.coordinator = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(place))
        view.addGestureRecognizer(tap)
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    func detach() {
        updates = nil
        anchor = nil
        ghost = nil
        furniture = nil
        view = nil
        opened = false
    }

    /// Turn the camera on, once, and only if this build, this device and this
    /// person's answer all allow it.
    ///
    /// THE SECOND LOCK, AND THE ONE THAT MATTERS: it is the line above
    /// `session.run`. `venueSwitch` already refuses "Your floor" and prints the
    /// reason when the camera cannot be opened, and `DriveVenue.coerce` stands
    /// the venue back down if the door shuts while this is on screen — so this
    /// is unreachable through the UI, which is exactly why it is here. Build 27
    /// shipped with `session.run` called against a plist that did not permit it
    /// and iOS killed the app; a guard that only lives in a picker is a guard
    /// the next screen forgets to copy.
    func open() {
        guard !opened, let view, let model else { return }
        if let refusal = CameraDoor.availability.refusal(for: .venue) {
            model.status = refusal
            return
        }
        guard ARWorldTrackingConfiguration.isSupported else {
            // THE KIT OWNS THIS SENTENCE. Reaching here means the door said yes
            // and ARKit then said no, which is rare and still worth saying in
            // the same words as everywhere else.
            model.status = CameraAvailability(usageDescriptionIsDeclared: true,
                                              permission: .authorized,
                                              deviceSupportsWorldTracking: false)
                .refusal(for: .venue) ?? ""
            return
        }
        opened = true
        view.cameraMode = .ar
        view.environment.background = .cameraFeed()
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        view.session.run(config)
        model.status = ARDriveModel.pointAtTheFloor
    }

    func pause() { view?.session.pause() }

    func resume() {
        guard opened, let view else { open(); return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        // `.resetTracking` IS DELIBERATELY NOT PASSED. Coming back to this
        // screen should find the duck where it was left, not ask the person to
        // place it again; ARKit relocalises against the map it already has.
        view.session.run(config)
    }

    /// The newest answer from the bench. Cheap on purpose — this is called
    /// from `updateUIView`, which SwiftUI runs whenever anything on the screen
    /// changes.
    func show(pose: StagePose, world: DuckWorld?, ball: DuckWorld.Point?) {
        pending = pose
        let signature = WorldSignature(world: world, ball: ball)
        guard signature != built else { return }
        built = signature
        rebuildFurniture(world: world, ball: ball)
    }

    // MARK: - putting it down

    @objc private func place(_ gesture: UITapGestureRecognizer) {
        guard let view, let model, opened else { return }
        let point = gesture.location(in: view)
        // `.existingPlaneGeometry` FIRST, `.estimatedPlane` AS THE FALLBACK. On
        // a phone with LiDAR the first lands on measured floor; on one without
        // it never succeeds and the estimate is all there is. Asking only for
        // the estimate would throw away the better answer on the devices that
        // have it.
        let measured = view.raycast(from: point, allowing: .existingPlaneGeometry,
                                    alignment: .horizontal)
        let estimated = view.raycast(from: point, allowing: .estimatedPlane,
                                     alignment: .horizontal)
        guard let hit = measured.first ?? estimated.first else {
            model.status = ARDriveModel.noFloorThere
            return
        }

        // THE WORLD FACES THE WAY YOU ARE LOOKING, so forward on the stick is
        // away from you rather than off to one side. Same placement rule as the
        // bridge and the pitch, and the same arithmetic, because a second
        // spelling of it is a second chance to get the sign wrong.
        var transform = hit.worldTransform
        let camera = view.cameraTransform
        let forward = SIMD3<Float>(-camera.matrix.columns.2.x, 0, -camera.matrix.columns.2.z)
        if simd_length(forward) > 1e-4 {
            let f = simd_normalize(forward)
            let yaw = atan2f(-f.z, f.x)
            let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y,
                                        transform.columns.3.z)
            transform = float4x4(simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)))
            transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        }

        let world = AnchorEntity(world: transform)
        let duck = DuckGhostEntity()
        // The entity's origin is its feet: `bodyPoses` works in the model's
        // world frame, whose origin is the floor.
        duck.position.y = 0
        world.addChild(duck)
        // A SECOND TAP MOVES IT: the old anchor comes down and the same ghost
        // and furniture go under the new one, so the duck is never in two
        // places and the room follows the duck.
        if let old = anchor { view.scene.removeAnchor(old) }
        view.scene.addAnchor(world)
        anchor = world
        ghost = duck
        if let furniture { world.addChild(furniture) }
        model.status = DriveVenue.placedSaid
        Haptic.behaviourStarted()
    }

    /// One frame: put the duck where the bench last said it was.
    private func frame() {
        guard let ghost else { return }
        ghost.place(root: pending.root, jointAngles: pending.jointAngles)
    }

    // MARK: - the world, as ghosts

    /// What the furniture was built from. THE READBACK ONLY: the blocks come
    /// back out of the bench's own qpos, so this rebuilds when the bench's
    /// world changes and not when a picker's selection does.
    private struct WorldSignature: Equatable {
        let steps: [Double]
        let ball: [Double]
        let radius: Double
        let inner: Double

        init(world: DuckWorld?, ball: DuckWorld.Point?) {
            steps = (world?.steps ?? []).flatMap {
                [$0.x, $0.y, $0.top, $0.halfDepth, $0.halfWidth, $0.halfHeight]
            }
            let where_ = ball ?? world?.ball
            self.ball = where_.map { [$0.x, $0.y] } ?? []
            radius = world?.ballRadius ?? DuckWorld.ballRadius
            inner = world?.bank.arenaInner ?? DuckWorld.Bank.pinned.arenaInner
        }
    }

    /// Take the last world down and put this one up.
    ///
    /// TRANSLUCENT, AND THAT IS THE HONEST MATERIAL FOR IT. A solid block on
    /// your carpet reads as a block on your carpet; these are the bench's
    /// 200 kg step blocks drawn where the bench says they are, and a person
    /// walking through one has to be able to see that they walked through it.
    private func rebuildFurniture(world: DuckWorld?, ball: DuckWorld.Point?) {
        furniture?.removeFromParent()
        let room = Entity()
        furniture = room
        anchor?.addChild(room)
        // THE ARENA IS DRAWN WHETHER OR NOT A WORLD WAS READ BACK: it is the
        // room the duck is in, and the HUD's sentence promises it. The bank's
        // pinned constant stands in for a bench that answered no /world.
        addTheEdge(inner: Float(world?.bank.arenaInner ?? DuckWorld.Bank.pinned.arenaInner), to: room)
        guard let world else { return }

        let stepMaterial = ghostMaterial(UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1))
        for step in world.steps {
            let mesh = MeshResource.generateBox(
                size: SIMD3<Float>(Float(step.halfDepth * 2),
                                   Float(step.halfHeight * 2),
                                   Float(step.halfWidth * 2)))
            let block = ModelEntity(mesh: mesh, materials: [stepMaterial])
            // THE ONE COORDINATE SWAP IN THIS FILE, WRITTEN ONCE. The bench's
            // world is (x forward, y left, z up); RealityKit's is (x right,
            // y up, z toward you). So x stays, z is the height, and y becomes
            // −z. `top` is the block's UPPER face, which is why the centre is
            // half a block below it.
            block.position = SIMD3<Float>(Float(step.x),
                                          Float(step.top - step.halfHeight),
                                          Float(-step.y))
            room.addChild(block)
        }

        if let at = ball ?? world.ball {
            let radius = Float(world.ballRadius ?? DuckWorld.ballRadius)
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: radius),
                materials: [ghostMaterial(UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1))])
            sphere.position = SIMD3<Float>(Float(at.x), radius, Float(-at.y))
            room.addChild(sphere)
        }

    }

    /// The square the duck cannot leave, drawn as four chalk lines.
    ///
    /// IT IS THE ARENA AND IT IS NOT YOUR ROOM. Four static walls stand 1.45 m
    /// out on every side of the bench's world, 250 mm tall, and the duck will
    /// hit them; they are invisible in a camera feed, so what would otherwise
    /// happen is a duck walking into nothing on somebody's carpet. Drawn as
    /// lines on the floor rather than as walls because a 250 mm slab across
    /// your living room is a picture of furniture that is not there —
    /// `DriveVenue.arIsNot` says the square is the edge of the world it is in,
    /// not of yours.
    private func addTheEdge(inner: Float, to room: Entity) {
        let material = ghostMaterial(UIColor(white: 1, alpha: 1))
        for (along, sign) in [(true, 1), (true, -1), (false, 1), (false, -1)] {
            let long = inner * 2 + ARDriveMetric.edgeWidth
            let size = along
                ? SIMD3<Float>(long, ARDriveMetric.edgeHeight, ARDriveMetric.edgeWidth)
                : SIMD3<Float>(ARDriveMetric.edgeWidth, ARDriveMetric.edgeHeight, long)
            let bar = ModelEntity(mesh: .generateBox(size: size), materials: [material])
            let offset = inner * Float(sign)
            bar.position = along
                ? SIMD3<Float>(0, ARDriveMetric.edgeHeight / 2, offset)
                : SIMD3<Float>(offset, ARDriveMetric.edgeHeight / 2, 0)
            room.addChild(bar)
        }
    }

    private func ghostMaterial(_ colour: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: colour.withAlphaComponent(ARDriveMetric.ghostAlpha))
    }
}
