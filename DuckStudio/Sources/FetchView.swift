import SwiftUI
import Combine
import RealityKit
import ARKit
import DuckKit
import DuckRender
import StudioKit

/// Fetch: drop balls on your floor and time the duck bringing them in.
///
/// THE CONTROLLER IS THE ONE THE BENCH PROVED. `walk_to` arrives at a ball 8
/// times out of 8 from up to 40 degrees off the nose, steering on nothing but a
/// camera bearing, and this runs that same law.
///
/// BUT IT IS NOT SEEING ANYTHING HERE, and the screen says so. On the bench the
/// bearing comes from a rendered frame through a Hailo; in AR the app already
/// knows where the virtual ball is. Same law, different source — and letting a
/// demo imply the robot has eyes it is not using would be the sort of claim
/// this app spends its time avoiding.
struct FetchView: View {
    @StateObject private var referee = FetchReferee()

    var body: some View {
        ZStack(alignment: .bottom) {
            FetchContainer(referee: referee).ignoresSafeArea()
            VStack(spacing: 8) {
                Text(referee.run.summary).font(.headline)
                Text(referee.hint).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if referee.run.elapsed == 0 || referee.run.isFinished {
                    VenuePicker(venue: $referee.venue)
                }
                if referee.isPlaced && referee.run.isFinished && !referee.run.fetched.isEmpty {
                    Button("Again") { referee.restart() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
        }
        .navigationTitle("Fetch")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class FetchReferee: ObservableObject {
    @Published private(set) var run = FetchRun(balls: [])
    @Published var isPlaced = false
    @Published var venue: LabVenue = .stage
    @Published var hint = "Tap the floor to put the duck down."
    private var accumulator = 0.0

    func restart() { run = FetchRun(balls: []) ; hint = "Tap to drop a ball." }

    /// A venue switch rebuilds the world, so the run starts over with it.
    func reset() {
        run = FetchRun(balls: [])
        accumulator = 0
        isPlaced = true
        hint = "Tap the ground to drop a ball. It will go and get it."
    }

    func drop(_ ball: DuckSoccer.Vec2) {
        var balls = run.pending
        balls.append(ball)
        let carried = run
        run = FetchRun(balls: balls)
        // Keep where the duck already is, so a new ball does not teleport it.
        run.resume(from: carried.duck, fetched: carried.fetched, elapsed: carried.elapsed)
        hint = "The bearing comes from coordinates here, not from a camera — "
             + "on the bench this same controller steers on what it can see."
    }

    func tick(dt: TimeInterval) {
        guard isPlaced else { return }
        accumulator += min(dt, 0.25)
        let step = 1.0 / 50.0
        while accumulator >= step { accumulator -= step; run.advance(dt: step) }
    }
}

private struct FetchContainer: UIViewRepresentable {
    @ObservedObject var referee: FetchReferee

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

    func makeCoordinator() -> FetchCoordinator { FetchCoordinator() }
    static func dismantleUIView(_ view: ARView, coordinator: FetchCoordinator) { coordinator.detach() }
}

@MainActor
final class FetchCoordinator: NSObject {
    private weak var view: ARView?
    private weak var referee: FetchReferee?
    private var updates: (any Cancellable)?
    private var stage: LabStage?
    private var built: LabVenue?
    private var duck: DuckGhostEntity?
    private var anchor: AnchorEntity?
    private var balls: [ModelEntity] = []
    private var walk: DuckTrajectory?
    private var stand: DuckTrajectory?
    private var phase = 0.0
    private var lastPosition: SIMD3<Float>?
    private var lastTick: TimeInterval = 0

    func attach(to view: ARView, referee: FetchReferee) {
        self.view = view; self.referee = referee
        walk = try? DuckTrajectory.bundled(.walk)
        stand = try? DuckTrajectory.bundled(.stand)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    func detach() { updates = nil; stage = nil; duck = nil; anchor = nil; balls = []; view = nil }

    func needsRebuild(venue: LabVenue) -> Bool { built != venue }

    func ensure(venue: LabVenue) {
        guard built != venue, let view, let referee else { return }
        built = venue
        stage?.dismantle(); stage = nil
        if let anchor { view.scene.removeAnchor(anchor) }
        anchor = nil; duck = nil; balls = []
        lastPosition = nil; phase = 0
        referee.isPlaced = false

        switch venue {
        case .stage:
            let stage = LabStage(in: view, theme: .meadow, extent: 8, distance: 2.4)
            self.stage = stage
            let ghost = DuckGhostEntity()
            stage.root.addChild(ghost)
            duck = ghost; anchor = stage.root
            referee.reset()
            lastTick = CACurrentMediaTime()
        case .ar:
            view.cameraMode = .ar
            view.environment.background = .cameraFeed()
            guard ARWorldTrackingConfiguration.isSupported else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            view.session.run(config)
            referee.hint = "Tap the floor to put the duck down."
        }
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let view, let referee else { return }
        let point = gesture.location(in: view)

        if built == .stage {
            // No detected planes on a stage: the camera ray, met with y = 0.
            guard let world = LabStage.groundPoint(at: point, in: view),
                  let anchor else { return }
            drop(at: anchor.convert(position: world, from: nil), on: anchor)
            return
        }

        let hits = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        let fallback = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        guard let hit = (hits.first ?? fallback.first) else { return }
        let world = SIMD3<Float>(hit.worldTransform.columns.3.x,
                                 hit.worldTransform.columns.3.y,
                                 hit.worldTransform.columns.3.z)
        if anchor == nil {
            let root = AnchorEntity(world: hit.worldTransform)
            let ghost = DuckGhostEntity()
            root.addChild(ghost)
            view.scene.addAnchor(root)
            anchor = root; duck = ghost
            referee.reset()
            lastTick = CACurrentMediaTime()
            return
        }
        guard let anchor else { return }
        drop(at: anchor.convert(position: world, from: nil), on: anchor)
    }

    private func drop(at local: SIMD3<Float>, on anchor: AnchorEntity) {
        guard let referee else { return }
        referee.drop(DuckSoccer.Vec2(Double(local.x), Double(-local.z)))
        let ball = ModelEntity(mesh: .generateSphere(radius: 0.05),
                               materials: [UnlitMaterial(color: .systemOrange)])
        ball.position = SIMD3<Float>(local.x, 0.05, local.z)
        anchor.addChild(ball)
        balls.append(ball)
    }

    private func frame() {
        guard let referee, let duck, referee.isPlaced else { return }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? now - lastTick : 0
        lastTick = now
        let before = referee.run.fetched.count
        referee.tick(dt: dt)
        // A fetched ball comes off the floor.
        if referee.run.fetched.count > before, !balls.isEmpty {
            balls.removeFirst().removeFromParent()
        }

        let run = referee.run
        let position = SIMD3<Float>(Float(run.duck.position.x), 0, Float(-run.duck.position.y))
        if let walk, let stand {
            let travelled = lastPosition.map { Double(simd_distance($0, position)) } ?? 0
            lastPosition = position
            if run.isFinished {
                duck.apply(jointAngles: stand.pose(
                    at: now.truncatingRemainder(dividingBy: 1000)).jointAngles)
            } else {
                let clipSpeed = max(walk.deltaX / (Double(walk.frames.count) / walk.hz), 0.01)
                phase += travelled / clipSpeed
                duck.apply(jointAngles: walk.pose(at: phase).jointAngles)
            }
        }
        duck.position = position
        duck.orientation = simd_quatf(angle: Float(-run.duck.heading),
                                      axis: SIMD3<Float>(0, 1, 0))
        stage?.follow(position)
    }
}
