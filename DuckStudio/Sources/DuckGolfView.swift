import SwiftUI
import Combine
import RealityKit
import ARKit
import DuckKit
import DuckRender
import StudioKit

/// Duck golf: three holes on your carpet, fewest kicks wins.
///
/// NOTHING HERE IS DECIDED BY LUCK, WHICH IS THE POINT. The kick landed 16
/// times out of 16 on the bench, so the engine never rolls a die for it: a
/// stroke that connects always connects. What makes it hard is the same thing
/// that makes the real robot hard — getting into position. Lining up is an arc,
/// because the duck cannot turn on the spot, and the foot only reaches the ball
/// inside a quarter-turn cone in front of it.
///
/// A SWING FROM OUT OF RANGE COSTS NOTHING. It is not a shot; it is a walk you
/// have not finished yet, and charging a stroke for it would punish the player
/// for the engine's honesty about reach.
struct DuckGolfView: View {
    @StateObject private var model = GolfModel()
    /// So the stick, the power column and the kick stop sharing a width they
    /// cannot share — see the `isAccessibilitySize` branch below.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack(alignment: .bottom) {
            GolfContainer(model: model).ignoresSafeArea()
            VStack(spacing: Theme.spacing(.snug)) {
                Text(model.headline)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isPlaced {
                    // THE SCORE AND THE RANGE, AS ROWS. Both are in the
                    // headline as a sentence; as rows they get a label that
                    // never changes beside a value that does, tabular figures
                    // so the range stops jittering as the duck walks, and a
                    // stacked pair rather than a truncated number at an
                    // accessibility size.
                    TelemetryRow(label: "Strokes",
                                 value: "\(model.game.strokes) of par \(model.game.hole.par)")
                    TelemetryRow(label: "To the cup",
                                 value: String(format: "%.2f", model.game.toCup), unit: "m")
                }
                if model.game.strokes == 0 || model.game.holed {
                    VenuePicker(venue: $model.venue)
                }
                if model.isPlaced {
                    if model.game.holed {
                        // IT MOVES A DUCK TO A NEW TEE, so it is the sixty
                        // point variant like every other control here that
                        // does.
                        Button(model.hasNextHole ? "Next hole" : "Play again") {
                            model.advanceHole()
                        }
                        .buttonStyle(.primaryActionMoves)
                    } else if typeSize.isAccessibilitySize {
                        // STACKED WHERE SIDE BY SIDE WOULD SQUEEZE. A stick, a
                        // power column and a sixty-point button do not share
                        // the width of a phone at AX5 — one of them loses, and
                        // it is always the words. They take the whole width in
                        // turn instead.
                        JoystickView(side: GolfMetric.stick) { model.stick = $0 }
                        power
                        kick
                    } else {
                        HStack(spacing: Theme.spacing(.standard)) {
                            JoystickView(side: GolfMetric.stick) { model.stick = $0 }
                            VStack(spacing: Theme.spacing(.tight)) {
                                power
                                kick
                            }
                            .frame(maxWidth: GolfMetric.powerWidth)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.spacing(.standard))
            .padding(.vertical, Theme.spacing(.snug))
            // AN OPAQUE PANEL OVER A LIVE PICTURE, the same decision
            // `DriveView` makes about its readout: on `.thinMaterial` the
            // contrast of every word here was whatever the grass happened to be
            // that frame. `surfacePrimary` is one of the four grounds
            // `PaletteTests` proves every text token against at 4.5:1.
            .background(Theme.surfacePrimary, in: panel)
            .overlay(panel.strokeBorder(Theme.separator,
                                        lineWidth: GolfMetric.hairlineStroke))
            .padding(Theme.spacing(.standard))
        }
        .navigationTitle("Duck golf")
        .navigationBarTitleDisplayMode(.inline)
        .task { Haptic.prepare() }
        // HOLING OUT IS A WORLD EVENT — the ball went in while the person was
        // watching the ball, not the panel. On the edge only: `holed` stays
        // true until the next hole is laid out.
        .onChange(of: model.game.holed) { _, holed in
            if holed { Haptic.finished() }
        }
    }

    /// How hard the kick will be.
    ///
    /// THE BILL IS THE FILL, which is what `BillIndicator` is for: one end
    /// squared where the bar is attached and one rounded where it stops, saying
    /// "this much, from here". The slider underneath is still the control — it
    /// is a real `Slider`, so Voice Control, Switch Control and VoiceOver's
    /// adjustable action all keep working — and the bill and the row above it
    /// are how the same number is read while a thumb is on the stick.
    private var power: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            TelemetryRow(label: "Power",
                         value: "\(Int(model.power * 100))", unit: "%")
            BillIndicator(fill: model.power)
            Slider(value: $model.power, in: 0.1...1.0)
                .accessibilityLabel(Text("Power"))
                .accessibilityValue(Text("\(Int(model.power * 100)) per cent"))
        }
    }

    /// THE ONE CONTROL ON THIS SCREEN THAT SWINGS A FOOT. Everything orange
    /// moves the duck and nothing else on the screen is orange, which is
    /// `DriveView`'s rule and the whole colour story here; `.tint(.orange)`
    /// said the same thing in a literal the palette cannot check, and at
    /// whatever height a `.borderedProminent` button happened to be. Sixty
    /// points, because the person pressing it is watching the ball.
    private var kick: some View {
        Button("Kick") { model.kick() }
            .buttonStyle(.primaryActionMoves)
            .accessibilityHint(Text("Swings at the ball with the power set above. Out of range it costs no stroke."))
    }

    private var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(GolfMetric.panel), style: .continuous)
    }
}

/// The numbers this screen writes down for itself.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST — a ratio is a fact and lives in
/// `Palette`, where a test runs the formula over it. How wide to let a power
/// slider get is a judgement about a thumb.
private enum GolfMetric {
    /// The HUD panel. A card, on the scale.
    static let panel = Palette.Radius.card
    /// The thumb stick's side, unchanged from the shape this screen shipped
    /// with.
    static let stick: CGFloat = 110
    /// How wide the power column may grow beside the stick.
    static let powerWidth: CGFloat = 150
    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke = DesignMetric.hairlineStroke
}

@MainActor
final class GolfModel: ObservableObject {
    @Published private(set) var game = DuckGolf(hole: DuckGolf.course[0])
    @Published private(set) var holeIndex = 0
    @Published var isPlaced = false
    @Published var venue: LabVenue = .stage
    @Published var stick = DuckSoccer.Vec2.zero
    @Published var power = 0.6
    @Published private(set) var lastStroke = ""
    /// The duck's own position and heading, driven by the stick. The engine
    /// owns the ball and the cup; where the player stands is the player's.
    @Published private(set) var duck = DuckSoccer.Vec2.zero
    @Published private(set) var heading = 0.0
    private(set) var strokeTotal = 0

    var hasNextHole: Bool { holeIndex + 1 < DuckGolf.course.count }

    var headline: String {
        guard isPlaced else { return "Tap the floor to lay out the hole." }
        return "Hole \(holeIndex + 1) of \(DuckGolf.course.count) · par \(game.hole.par) — \(game.summary)"
    }

    var detail: String {
        guard isPlaced else {
            return "Three holes. Walk up to the ball and kick it in."
        }
        if game.strokes == 0 && lastStroke.isEmpty {
            return String(format: "%.1f m to the cup. The foot reaches %.2f m and only "
                        + "in front — it steers in arcs, so line up early.",
                          game.hole.length, game.capabilities.kickRange)
        }
        if !lastStroke.isEmpty { return lastStroke }
        return "The foot reaches \(String(format: "%.2f", game.capabilities.kickRange)) m "
             + "and only in front — it steers in arcs, so line up early."
    }

    /// Start this hole over where it stands. Used when the venue changes: the
    /// world is rebuilt, so the duck has to be back on the tee with it.
    func reset() {
        game = DuckGolf(hole: DuckGolf.course[holeIndex])
        duck = .zero; heading = 0; lastStroke = ""
        isPlaced = true
    }

    func advanceHole() {
        if hasNextHole { holeIndex += 1 } else { holeIndex = 0; strokeTotal = 0 }
        game = DuckGolf(hole: DuckGolf.course[holeIndex])
        duck = .zero; heading = 0; lastStroke = ""
    }

    func kick() {
        switch game.kick(from: duck, heading: heading, power: power) {
        case .struck(let distance):
            lastStroke = String(format: "Struck — the ball ran %.2f m.", distance)
        case .missed(let why):
            lastStroke = "No contact: \(why). That does not cost a stroke."
        case .holed(let strokes):
            strokeTotal += strokes
            lastStroke = "In. \(strokeTotal) strokes so far."
        }
    }

    func advance(dt: Double) {
        guard isPlaced, !game.holed else { return }
        let capabilities = game.capabilities
        let forward = max(-1, min(1, stick.x))
        let turn = max(-1, min(1, stick.y))
        heading += turn * capabilities.turnRate * dt
        let speed = forward * capabilities.walkSpeed
        duck = duck + DuckSoccer.Vec2(cos(heading), sin(heading)) * (speed * dt)
    }
}

private struct GolfContainer: UIViewRepresentable {
    @ObservedObject var model: GolfModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR,
                          automaticallyConfigureSession: false)
        context.coordinator.attach(to: view, model: model)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let venue = model.venue
        let coordinator = context.coordinator
        guard coordinator.needsRebuild(venue: venue) else { return }
        DispatchQueue.main.async { coordinator.ensure(venue: venue) }
    }

    func makeCoordinator() -> GolfCoordinator { GolfCoordinator() }
    static func dismantleUIView(_ view: ARView, coordinator: GolfCoordinator) { coordinator.detach() }
}

@MainActor
final class GolfCoordinator: NSObject {
    private weak var view: ARView?
    private weak var model: GolfModel?
    private var updates: (any Cancellable)?
    private var stage: LabStage?
    private var built: LabVenue?
    private var anchor: AnchorEntity?
    private var duck: DuckGhostEntity?
    private var ball: ModelEntity?
    private var cup: ModelEntity?
    private var walk: DuckTrajectory?
    private var stand: DuckTrajectory?
    private var phase = 0.0
    private var lastPosition: SIMD3<Float>?
    private var lastTick: TimeInterval = 0
    private var laidOutHole = -1

    func attach(to view: ARView, model: GolfModel) {
        self.view = view; self.model = model
        walk = try? DuckTrajectory.bundled(.walk)
        stand = try? DuckTrajectory.bundled(.stand)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    func detach() { updates = nil; stage = nil; anchor = nil; duck = nil; ball = nil; cup = nil; view = nil }

    func needsRebuild(venue: LabVenue) -> Bool { built != venue }

    func ensure(venue: LabVenue) {
        guard built != venue, let view, let model else { return }
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
        // Golf has no writable status line — its headline and detail are
        // computed from the game — so the refusal beside the venue picker is
        // the whole of what a person sees, and this only keeps the session
        // shut.
        if venue == .ar, !CameraDoor.availability.canOfferAR { return }
        built = venue
        stage?.dismantle(); stage = nil
        if let anchor { view.scene.removeAnchor(anchor) }
        anchor = nil; duck = nil; ball = nil; cup = nil
        laidOutHole = -1; lastPosition = nil; phase = 0
        model.isPlaced = false

        switch venue {
        case .stage:
            let stage = LabStage(in: view, theme: .meadow, extent: 8, distance: 2.2)
            self.stage = stage
            layout(on: stage.root)
            anchor = stage.root
            model.reset()
            lastTick = CACurrentMediaTime()
        case .ar:
            view.cameraMode = .ar
            view.environment.background = .cameraFeed()
            guard ARWorldTrackingConfiguration.isSupported else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            view.session.run(config)
        }
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let view, let model, built == .ar, anchor == nil else { return }
        let point = gesture.location(in: view)
        let hits = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        let fallback = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        guard let hit = (hits.first ?? fallback.first) else { return }
        let root = AnchorEntity(world: hit.worldTransform)
        layout(on: root)
        view.scene.addAnchor(root)
        anchor = root
        model.reset()
        lastTick = CACurrentMediaTime()
    }

    /// Duck, ball and cup, on whichever anchor was chosen.
    private func layout(on root: AnchorEntity) {
        let ghost = DuckGhostEntity()
        root.addChild(ghost)
        let ballEntity = ModelEntity(mesh: .generateSphere(radius: 0.04),
                                     materials: [UnlitMaterial(color: .white)])
        let cupEntity = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.16, 0.004, 0.16)),
                                    materials: [UnlitMaterial(color: .systemGreen)])
        root.addChild(ballEntity); root.addChild(cupEntity)
        duck = ghost; ball = ballEntity; cup = cupEntity
    }

    private func frame() {
        guard let model, let duck, let ball, let cup, model.isPlaced else { return }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? min(now - lastTick, 0.25) : 0
        lastTick = now
        model.advance(dt: dt)

        let game = model.game
        if laidOutHole != model.holeIndex {
            laidOutHole = model.holeIndex
            cup.position = SIMD3<Float>(Float(game.hole.cup.x), 0.002, Float(-game.hole.cup.y))
        }
        ball.position = SIMD3<Float>(Float(game.ball.x), 0.04, Float(-game.ball.y))

        let position = SIMD3<Float>(Float(model.duck.x), 0, Float(-model.duck.y))
        if let walk, let stand {
            let travelled = lastPosition.map { Double(simd_distance($0, position)) } ?? 0
            lastPosition = position
            if travelled > 0.0005 {
                let clipSpeed = max(walk.deltaX / (Double(walk.frames.count) / walk.hz), 0.01)
                phase += travelled / clipSpeed
                duck.apply(jointAngles: walk.pose(at: phase).jointAngles)
            } else {
                duck.apply(jointAngles: stand.pose(
                    at: now.truncatingRemainder(dividingBy: 1000)).jointAngles)
            }
        }
        duck.position = position
        duck.orientation = simd_quatf(angle: Float(-model.heading),
                                      axis: SIMD3<Float>(0, 1, 0))
        // The camera watches the ball, not the duck: golf is about where the
        // ball ends up, and a camera welded to the player loses the cup.
        stage?.follow(SIMD3<Float>(Float((game.ball.x + model.duck.x) / 2), 0,
                                   Float(-(game.ball.y + model.duck.y) / 2)))
    }
}
