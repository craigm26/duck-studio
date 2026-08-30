import SwiftUI
import Combine
import RealityKit
import ARKit
import DuckKit
import DuckRender
import StudioKit

/// Slalom: five gates, and the limit that decides the whole thing.
///
/// A DUCK CANNOT TURN ON THE SPOT, so every change of direction is an arc with
/// a radius of `walkSpeed / turnRate` — 0.31 m on legs, 0.90 m on skates. The
/// course is cut to 0.31 m exactly, which means the legs clean it flat out and
/// the skates have to throttle from 0.45 m/s down to about 0.155 before their
/// arc will fit. They are still faster. They are just 1.5× faster instead of
/// 4.2× faster, and that gap is the game.
///
/// Pick the gear before you start and the difference is immediate: the skater
/// spends the run braking for corners the walker takes at full pace.
struct SlalomView: View {
    @StateObject private var model = SlalomModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            SlalomContainer(model: model).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(model.headline).font(.headline).monospacedDigit()
                Text(model.detail).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if model.run.elapsed == 0 || model.run.isFinished {
                    Picker("Gear", selection: $model.gear) {
                        Text("Legs").tag(SlalomModel.Gear.legs)
                        Text("Skates").tag(SlalomModel.Gear.skates)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 240)
                    VenuePicker(venue: $model.venue)
                }
                if model.isPlaced {
                    if model.run.isFinished {
                        Button("Run it again") { model.restart() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        JoystickView { model.stick = $0 }.frame(width: 120, height: 120)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .navigationTitle("Slalom")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class SlalomModel: ObservableObject {
    enum Gear: String { case legs, skates
        var capabilities: DuckSoccer.Capabilities { self == .legs ? .measured : .skates }
        var variant: DuckKinematics.Variant { self == .legs ? .legs : .rollers }
    }

    @Published var gear: Gear = .legs
    @Published var venue: LabVenue = .stage
    @Published private(set) var run = Slalom()
    @Published var isPlaced = false
    @Published var stick = DuckSoccer.Vec2.zero
    /// Set once at placement: changing gear mid-course would change the arc
    /// under the player's hands.
    private(set) var locked: Gear = .legs

    func begin() {
        locked = gear
        run = Slalom(capabilities: gear.capabilities)
        isPlaced = true
    }

    func restart() { run = Slalom(capabilities: locked.capabilities); stick = .zero }

    var headline: String {
        isPlaced ? run.summary : "Slalom · \(Slalom.course.count) gates"
    }

    var detail: String {
        guard isPlaced else {
            let radius = Slalom.minimumTurnRadius(gear.capabilities)
            return String(format: "Tap the floor to lay out the course. On %@ the "
                        + "tightest arc it can hold is %.2f m, and the gates need 0.31 m.",
                          gear == .legs ? "legs" : "skates", radius)
        }
        if run.elapsed == 0 {
            let radius = Slalom.minimumTurnRadius(locked.capabilities)
            return String(format: "%.1f m of gates. On %@ the tightest arc it can hold "
                        + "is %.2f m, and these need 0.31 m.",
                          Slalom.course.last?.center.x ?? 3.5,
                          locked == .legs ? "legs" : "skates", radius)
        }
        if run.isFinished {
            return run.missed == 0
                ? "Clean. Every gate on the right side of the post."
                : "\(run.missed) gate\(run.missed == 1 ? "" : "s") missed, "
                  + "\(Int(Double(run.missed) * Slalom.missPenalty)) seconds added."
        }
        return locked == .legs
            ? "Full pace fits — the course was cut to the legs' 0.31 m arc."
            : "Ease off. At 0.45 m/s the arc is 0.90 m and no steering angle will make this gate."
    }

    func advance(dt: Double) {
        guard isPlaced else { return }
        run.advance(dt: dt, forward: stick.x, turn: stick.y)
    }
}

private struct SlalomContainer: UIViewRepresentable {
    @ObservedObject var model: SlalomModel

    func makeUIView(context: Context) -> ARView {
        // Starts non-AR and stays that way unless somebody asks for the
        // camera. No session, no permission prompt, no battery.
        let view = ARView(frame: .zero, cameraMode: .nonAR,
                          automaticallyConfigureSession: false)
        context.coordinator.attach(to: view, model: model)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let venue = model.venue, gear = model.gear
        let coordinator = context.coordinator
        // The engine publishes every tick, so this runs 60 times a second.
        // Check before dispatching rather than posting a no-op each frame.
        guard coordinator.needsRebuild(venue: venue, gear: gear) else { return }
        // Deferred: building a world publishes model state, and publishing
        // from inside a view update is undefined behaviour.
        DispatchQueue.main.async { coordinator.ensure(venue: venue, gear: gear) }
    }

    func makeCoordinator() -> SlalomCoordinator { SlalomCoordinator() }
    static func dismantleUIView(_ view: ARView, coordinator: SlalomCoordinator) { coordinator.detach() }
}

@MainActor
final class SlalomCoordinator: NSObject {
    private weak var view: ARView?
    private weak var model: SlalomModel?
    private var updates: (any Cancellable)?
    private var stage: LabStage?
    private var built: (venue: LabVenue, gear: SlalomModel.Gear)?
    private var anchor: AnchorEntity?
    private var duck: DuckGhostEntity?
    private var posts: [Int: [ModelEntity]] = [:]
    private var clips: [DuckTrajectory.Clip: DuckTrajectory] = [:]
    private var phase = 0.0
    private var wheel = 0.0
    private var lastPosition: SIMD3<Float>?
    private var lastTick: TimeInterval = 0

    func attach(to view: ARView, model: SlalomModel) {
        self.view = view; self.model = model
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    func detach() { updates = nil; stage = nil; anchor = nil; duck = nil; posts = [:]; view = nil }

    func needsRebuild(venue: LabVenue, gear: SlalomModel.Gear) -> Bool {
        built?.venue != venue || built?.gear != gear
    }

    /// Build the chosen world, taking down whatever was there. GEAR COUNTS AS
    /// A REBUILD: the skater is a different entity, not a different setting.
    func ensure(venue: LabVenue, gear: SlalomModel.Gear) {
        guard needsRebuild(venue: venue, gear: gear), let view, let model else { return }
        built = (venue, gear)
        stage?.dismantle(); stage = nil
        if let anchor { view.scene.removeAnchor(anchor) }
        anchor = nil; duck = nil; posts = [:]
        lastPosition = nil; phase = 0; wheel = 0
        model.isPlaced = false
        loadClips()

        switch venue {
        case .stage:
            let stage = LabStage(in: view, theme: .meadow, extent: 10, distance: 2.6)
            self.stage = stage
            model.begin()
            layout(on: stage.root, variant: model.locked.variant)
            anchor = stage.root
            lastTick = CACurrentMediaTime()
        case .ar:
            view.cameraMode = .ar
            view.environment.background = .cameraFeed()
            guard ARWorldTrackingConfiguration.isSupported else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            view.session.run(config)
            // Placement continues in the tap handler.
        }
    }

    private func loadClips() {
        guard clips.isEmpty else { return }
        for clip in [DuckTrajectory.Clip.walk, .stand, .skate, .skateStand] {
            clips[clip] = try? DuckTrajectory.bundled(clip)
        }
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let view, let model, built?.venue == .ar, anchor == nil else { return }
        let point = gesture.location(in: view)
        let hits = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        let fallback = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        guard let hit = (hits.first ?? fallback.first) else { return }
        model.begin()
        let root = AnchorEntity(world: hit.worldTransform)
        layout(on: root, variant: model.locked.variant)
        view.scene.addAnchor(root)
        anchor = root
        lastTick = CACurrentMediaTime()
    }

    /// The course and the duck, on whichever anchor was chosen. Shared, so the
    /// two venues cannot drift into being two different games.
    private func layout(on root: AnchorEntity, variant: DuckKinematics.Variant) {
        let ghost = DuckGhostEntity(variant: variant)
        root.addChild(ghost)
        duck = ghost
        for (index, gate) in Slalom.course.enumerated() {
            var pair: [ModelEntity] = []
            for side in [-1.0, 1.0] {
                let offset = gate.center + DuckSoccer.Vec2(-sin(gate.heading), cos(gate.heading))
                    * (gate.halfWidth * side)
                let post = ModelEntity(
                    mesh: .generateBox(size: SIMD3<Float>(0.02, 0.14, 0.02)),
                    materials: [UnlitMaterial(color: .systemYellow)])
                post.position = SIMD3<Float>(Float(offset.x), 0.07, Float(-offset.y))
                root.addChild(post)
                pair.append(post)
            }
            posts[index] = pair
        }
    }

    private func frame() {
        guard let model, let duck, model.isPlaced else { return }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? min(now - lastTick, 0.25) : 0
        lastTick = now
        model.advance(dt: dt)
        let run = model.run

        // The gate you are on is yellow; the ones behind you go green, or red
        // if you went round the outside of a post.
        for (index, pair) in posts {
            let colour: UIColor = index < run.next
                ? (index < run.next - run.missed ? .systemGreen : .systemRed)
                : (index == run.next ? .systemYellow : .white)
            for post in pair {
                post.model?.materials = [UnlitMaterial(color: colour)]
            }
        }

        let position = SIMD3<Float>(Float(run.duck.position.x), 0, Float(-run.duck.position.y))
        let travelled = lastPosition.map { Double(simd_distance($0, position)) } ?? 0
        lastPosition = position
        let moving = travelled > 0.0005
        if model.locked == .skates {
            if let glide = clips[.skate], let still = clips[.skateStand] {
                wheel += travelled / 0.021          // wheel radius, metres
                duck.apply(jointAngles: (moving ? glide : still).pose(
                    at: now.truncatingRemainder(dividingBy: 1000)).jointAngles,
                           wheelSpin: wheel)
            }
        } else if let walk = clips[.walk], let stand = clips[.stand] {
            if moving {
                let clipSpeed = max(walk.deltaX / (Double(walk.frames.count) / walk.hz), 0.01)
                phase += travelled / clipSpeed
                duck.apply(jointAngles: walk.pose(at: phase).jointAngles)
            } else {
                duck.apply(jointAngles: stand.pose(
                    at: now.truncatingRemainder(dividingBy: 1000)).jointAngles)
            }
        }
        duck.position = position
        duck.orientation = simd_quatf(angle: Float(-run.duck.heading), axis: SIMD3<Float>(0, 1, 0))
        stage?.follow(position)
    }
}
