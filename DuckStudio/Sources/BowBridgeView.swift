import SwiftUI
import Combine
import RealityKit
import ARKit
import DuckKit
import DuckRender
import StudioKit

/// Bow Bridge, at duck scale.
///
/// A 25 cm duck crossing the real Central Park would be a rounding error, so
/// this is the diorama version: one landmark, built at the size the robot
/// actually is, on a lake you can lose it in.
///
/// THE GEOMETRY IS THE GAME. The deck is 0.5 m across and arches 0.22 m to its
/// crown, and the duck cannot turn on the spot — commanded yaw saturates at
/// about 14 degrees and stops — so every correction is an arc it has to plan.
/// It cannot creep either: below a walking command the policy marches in place.
/// Those two measured facts are the entire difficulty; nothing here is tuned.
///
/// THE ARCH IS A CURVE, NEVER STEPS. `step_up` scores 0/16 on flat ground and
/// the duck tops out at a 10 mm step, so a bridge with a lip would not be hard,
/// it would be impassable.
struct BowBridgeView: View {
    @StateObject private var referee = BridgeReferee()

    var body: some View {
        ZStack(alignment: .bottom) {
            BridgeContainer(referee: referee)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(referee.run.summary).font(.headline)
                        Text(String(format: "%.1f s", referee.run.elapsed))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // How close to the rail, which is the only warning the
                    // player gets — the duck has no railing sense of its own.
                    Circle()
                        .fill(referee.run.edgeProximity > 0.75 ? Color.orange : Color.green)
                        .frame(width: 14, height: 14)
                        .opacity(0.3 + 0.7 * referee.run.edgeProximity)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if referee.run.outcome == .crossing {
                    HStack(alignment: .bottom) {
                        JoystickView { vector in
                            referee.forward = vector.x
                            referee.steer = -vector.y
                        }
                        Spacer()
                    }
                } else {
                    Button("Cross again") { referee.restart() }
                        .buttonStyle(.borderedProminent)
                }
                if referee.run.elapsed == 0 || referee.run.outcome != .crossing {
                    VenuePicker(venue: $referee.venue)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .padding()
        }
        .navigationTitle("Bow Bridge")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Owns the crossing and steps it at a fixed rate.
@MainActor
final class BridgeReferee: ObservableObject {
    @Published private(set) var run = BridgeCrossing()
    @Published var status = "Point at the floor and tap to put the bridge down."
    @Published var isPlaced = false
    @Published var venue: LabVenue = .stage
    var forward = 0.0
    var steer = 0.0
    private var accumulator = 0.0

    func restart() {
        run = BridgeCrossing()
        forward = 0; steer = 0
    }

    /// FIXED 50 Hz, like the pitch. Feeding a render dt straight into a game
    /// makes a 120 Hz phone play a different game from a 60 Hz one, which the
    /// soccer engine learned the hard way.
    func tick(dt: TimeInterval) {
        guard isPlaced, run.outcome == .crossing else { return }
        accumulator += min(dt, 0.25)
        let step = 1.0 / 50.0
        while accumulator >= step {
            accumulator -= step
            run.advance(dt: step, forward: forward, steer: steer)
        }
    }
}

private struct BridgeContainer: UIViewRepresentable {
    @ObservedObject var referee: BridgeReferee

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR,
                          automaticallyConfigureSession: false)
        context.coordinator.attach(to: view, referee: referee)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let venue = referee.venue
        let coordinator = context.coordinator
        guard coordinator.needsRebuild(venue: venue) else { return }
        DispatchQueue.main.async { coordinator.ensure(venue: venue) }
    }

    func makeCoordinator() -> BridgeCoordinator { BridgeCoordinator() }
    static func dismantleUIView(_ view: ARView, coordinator: BridgeCoordinator) {
        coordinator.detach()
    }
}

@MainActor
final class BridgeCoordinator: NSObject {
    private weak var view: ARView?
    private weak var referee: BridgeReferee?
    private var updates: (any Cancellable)?
    private var stage: LabStage?
    private var built: LabVenue?
    private var duck: DuckGhostEntity?
    private var anchor: AnchorEntity?
    private var walk: DuckTrajectory?
    private var stand: DuckTrajectory?
    private var phase = 0.0
    private var lastDrawn: SIMD3<Float>?
    private var lastTick: TimeInterval = 0

    func attach(to view: ARView, referee: BridgeReferee) {
        self.view = view
        self.referee = referee
        walk = try? DuckTrajectory.bundled(.walk)
        stand = try? DuckTrajectory.bundled(.stand)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(place)))
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    func detach() { updates = nil; stage = nil; duck = nil; anchor = nil; view = nil }

    func needsRebuild(venue: LabVenue) -> Bool { built != venue }

    func ensure(venue: LabVenue) {
        guard built != venue, let view, let referee else { return }
        // THE SECOND LOCK, AND THE ONE THAT MATTERS: it is the line above
        // `session.run`. `VenuePicker` already disables "Your floor" and prints
        // the reason when the camera cannot be opened, so this is unreachable
        // through the UI — which is exactly why it is here. Build 27 shipped
        // with `session.run` called against a plist that did not permit it and
        // iOS killed the app; a guard that only lives in a picker is a guard
        // the next screen forgets to copy.
        //
        // It refuses BEFORE `built` is updated and before the stage comes down,
        // so a refusal leaves the world that was already standing rather than
        // tearing it down for one that never arrives. The sentence is on screen
        // under the venue picker, which is the only route to `.ar`.
        if venue == .ar, let refusal = CameraDoor.availability.refusal(for: .venue) {
            referee.status = refusal
            return
        }
        built = venue
        stage?.dismantle(); stage = nil
        if let anchor { view.scene.removeAnchor(anchor) }
        anchor = nil; duck = nil; lastDrawn = nil; phase = 0
        referee.isPlaced = false
        referee.restart()

        switch venue {
        case .stage:
            // No grid floor: the bridge brings its own lake.
            let stage = LabStage(in: view, theme: .park, extent: 10,
                                 distance: 2.8, elevation: 0.42, ground: false)
            self.stage = stage
            BowBridgeScene.build(on: stage.root, deck: referee.run.deck)
            let ghost = DuckGhostEntity()
            stage.root.addChild(ghost)
            anchor = stage.root; duck = ghost
            referee.isPlaced = true
            referee.status = "Walk across. You cannot turn on the spot — only while walking."
            lastTick = CACurrentMediaTime()
        case .ar:
            view.cameraMode = .ar
            view.environment.background = .cameraFeed()
            guard ARWorldTrackingConfiguration.isSupported else {
                // THE KIT OWNS THIS SENTENCE. This stub predates
                // `CameraAvailability` and says strictly less than it: no
                // consequence, no remedy, and a second place the same fact
                // is worded. The door has already refused on
                // `deviceCannotWorldTrack`, so reaching here means the door
                // said yes and ARKit then said no — rare, and worth saying
                // in the same words as everywhere else.
                referee.status = CameraAvailability(usageDescriptionIsDeclared: true,
                                          permission: .authorized,
                                          deviceSupportsWorldTracking: false)
                    .refusal(for: .venue) ?? ""
                return
            }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            view.session.run(config)
            referee.status = "Point at the floor and tap to lay the bridge down."
        }
    }

    @objc private func place(_ gesture: UITapGestureRecognizer) {
        guard let view, let referee, built == .ar, anchor == nil else { return }
        let point = gesture.location(in: view)
        let hits = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        let fallback = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        guard let hit = (hits.first ?? fallback.first) else {
            referee.status = "No floor there yet — move the phone and tap again."
            return
        }
        // The bridge faces the way you are looking, so "forward" on the stick
        // is away from you — the same placement rule the pitch uses.
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
        BowBridgeScene.build(on: world, deck: referee.run.deck)
        let ghost = DuckGhostEntity()
        world.addChild(ghost)
        view.scene.addAnchor(world)
        anchor = world
        duck = ghost
        referee.isPlaced = true
        referee.status = "Walk across. You cannot turn on the spot — only while walking."
        lastTick = CACurrentMediaTime()
    }

    private func frame() {
        guard let referee, let duck, anchor != nil else { return }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? now - lastTick : 0
        lastTick = now
        referee.tick(dt: dt)

        let run = referee.run
        // The bridge runs along +x from the anchor; the deck rises under it.
        let position = SIMD3<Float>(Float(run.x), Float(run.height), Float(-run.y))
        // Feet paced by ground covered, the same rule the pitch uses — a clip
        // played on wall-clock time moonwalks.
        if let walk, let stand {
            let travelled = lastDrawn.map { Double(simd_distance($0, position)) } ?? 0
            lastDrawn = position
            if case .inTheLake = run.outcome {
                duck.apply(jointAngles: stand.pose(at: 0).jointAngles)
            } else if travelled > 1e-4 {
                let clipSpeed = max(walk.deltaX / (Double(walk.frames.count) / walk.hz), 0.01)
                phase += travelled / clipSpeed
                duck.apply(jointAngles: walk.pose(at: phase).jointAngles)
            } else {
                duck.apply(jointAngles: stand.pose(
                    at: now.truncatingRemainder(dividingBy: 1000)).jointAngles)
            }
        }
        duck.position = position
        duck.orientation = simd_quatf(angle: Float(-run.heading), axis: SIMD3<Float>(0, 1, 0))
        // Going in means going down: the lake is below the deck.
        if case .inTheLake = run.outcome {
            duck.position.y = -0.06
        }
        stage?.follow(duck.position)
    }
}
