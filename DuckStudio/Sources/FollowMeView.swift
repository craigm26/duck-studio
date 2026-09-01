import SwiftUI
import Combine
import RealityKit
import ARKit
import DuckKit
import DuckRender
import StudioKit

/// Follow me: put the duck down and walk. It comes after you.
///
/// THIS IS THE ONE MODE WHERE THE PERCEPTION IS REAL. Everywhere else in the
/// lab the steering law is fed coordinates the app invented; here the thing
/// being followed is the phone, and ARKit's camera pose is a measurement of
/// where a person actually is in the room. The law on top is `walk_to`'s,
/// which arrived 8 times out of 8 on the bench.
///
/// AND YOU WILL HAVE TO WALK THIRTEEN TIMES SLOWER THAN NORMAL. That is the
/// point of it. Stroll off at a human 1.4 m/s and the duck is lost in a few
/// seconds; the screen says how far behind it is and asks you to slow down,
/// which is more use than a duck that magically keeps up.
///
/// AND IT IS THE ONE MODE THAT CANNOT FALL BACK. Every other Lab mode swaps a
/// camera feed for a rendered stage and loses a backdrop. This one would have
/// to swap the person for a joystick, which is the app inventing the very
/// number the mode exists to measure. So when the camera cannot be opened this
/// screen refuses outright and says what it is that it cannot do without —
/// `CameraAvailability` composes that sentence and `swift test` reads it.
struct FollowMeView: View {
    @StateObject private var model = FollowMeModel()
    /// THE DOOR IS CHECKED HERE AND NOT ONLY IN THE HUB THAT LINKS HERE.
    /// `GhostDuckView` disables its Follow me row when this is shut, so the
    /// branch below is unreachable through the UI — and it stays, because the
    /// unconditional `ARView(cameraMode: .ar)` that used to sit in
    /// `FollowContainer.makeUIView` is exactly the shape of the bug that killed
    /// build 27: a session started with no gate anywhere between the tap and
    /// the plist.
    @State private var door = CameraDoor.availability

    var body: some View {
        Group {
            if let refusal = door.refusal(for: .followMe) {
                ContentUnavailableView(CameraAvailability.Dependent.followMe.title,
                                       systemImage: "video.slash",
                                       description: Text(refusal))
            } else {
                walking
            }
        }
        .refreshingCameraDoor($door)
        .navigationTitle("Follow me")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The mode itself. Reached only when the door is open, so nothing under
    /// here has to ask again — `FollowContainer` builds its `ARView` on the
    /// strength of this branch having been taken.
    private var walking: some View {
        ZStack(alignment: .bottom) {
            FollowContainer(model: model).ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                // THE HEADLINE CARRIES A RANGE THAT CHANGES AS YOU WALK, which
                // is why the digits stay tabular: proportional figures make the
                // whole line breathe around the number. The words beside them
                // are not set in mono, because they do not change.
                Text(model.headline)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isPlaced {
                    // THE DISTANCE IS THE WHOLE MODE, so it gets a row of its
                    // own. It is the one number in the Lab that is a real
                    // measurement of the world — ARKit's camera pose is where a
                    // person actually is — and it is inside a sentence in the
                    // headline where a screen reader cannot step to it.
                    TelemetryRow(label: "You are",
                                 value: String(format: "%.2f", model.follow.range),
                                 unit: "m away")
                    // NOT A DOT. Whether it has lost you is the state this
                    // screen is about, and the badge is a word beside the mark
                    // rather than a colour on its own.
                    StateBadge(text: word, state: state)
                }
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacing(.standard))
            .padding(.vertical, Theme.spacing(.snug))
            // AN OPAQUE PANEL OVER THE CAMERA FEED. This is the one mode that
            // is AR-only, so there is no rendered stage behind these words —
            // whatever the room is, is behind them. `.thinMaterial` made every
            // sentence here a different contrast ratio in every room;
            // `surfacePrimary` is one of the four grounds `PaletteTests` proves
            // every text token against at 4.5:1.
            .background(Theme.surfacePrimary, in: panel)
            .overlay(panel.strokeBorder(Theme.separator,
                                        lineWidth: FollowMetric.hairlineStroke))
            .padding(Theme.spacing(.standard))
        }
        .task { Haptic.prepare() }
        // LOSING YOU IS THE LINK GOING AWAY ON ITS OWN, which is exactly what
        // `Haptic.linkLost` means — and the person it has to reach is walking
        // away with the phone in their hand and their back to the duck. On the
        // edge only, so it fires when you go out of range rather than for as
        // long as you stay there.
        .onChange(of: model.follow.hasLostYou) { _, lost in
            if lost { Haptic.linkLost() }
        }
    }

    /// The state as one word.
    ///
    /// ALL THREE WORDS ARE ALREADY ON THIS SCREEN. `FollowMe` names these
    /// states itself — `hasLostYou`, `isWalking`, `inStation` — and
    /// `model.detail` opens with the same three words in the sentence that
    /// explains each of them. The badge is that fact short enough to sit beside
    /// a mark, and the sentence underneath is still where the reason lives.
    private var word: String {
        if model.follow.hasLostYou { return "Lost you" }
        return model.follow.isWalking ? "Walking" : "In station"
    }

    /// A duck standing in station is `idle`; one walking after you is `active`;
    /// one that has lost you is still powered and still standing, so it is idle
    /// too — the word beside the dot is what separates those two, which is the
    /// rule the badge exists to enforce.
    private var state: RobotState {
        model.follow.isWalking ? .active : .idle
    }

    private var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(FollowMetric.panel), style: .continuous)
    }
}

/// The two numbers this screen writes down for itself.
///
/// NEITHER IS A COLOUR OR A CONTRAST — a ratio is a fact and lives in `Palette`
/// where a test runs the formula over it.
private enum FollowMetric {
    /// The HUD panel. A card, on the scale.
    static let panel = Palette.Radius.card
    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke: CGFloat = 1
}

@MainActor
final class FollowMeModel: ObservableObject {
    @Published private(set) var follow = FollowMe()
    @Published var isPlaced = false

    var headline: String {
        isPlaced ? follow.summary : "Follow me"
    }

    var detail: String {
        guard isPlaced else {
            return String(format: "THIS ONE IS AR ONLY, and it is the only one that is: "
                        + "the duck follows the PHONE, and the camera pose is a real "
                        + "measurement of where you are standing. A stage version would "
                        + "have to replace you with a joystick — perception with pretend. "
                        + "Tap the floor to put the duck down, then walk. "
                        + "It goes %.3f m/s and you go about 1.4, so you will be "
                        + "waiting for it — that is the mode.",
                          follow.capabilities.walkSpeed)
        }
        if follow.hasLostYou {
            return "It has no idea where you went. Come back and slow down."
        }
        return follow.isWalking
            ? "Walking. It cannot creep — below its dead band it marches in place — so slow following looks like stop, start, stop."
            : "In station. Move off and it will set out again."
    }

    func advance(dt: Double, person: DuckSoccer.Vec2) {
        guard isPlaced else { return }
        follow.advance(dt: dt, person: person)
    }

    func place(startingAt person: DuckSoccer.Vec2) {
        // It starts facing you, because that is where you were standing when
        // you put it down.
        let heading = atan2(person.y, person.x)
        follow = FollowMe(duck: .init(position: .zero, heading: heading), person: person)
        isPlaced = true
    }
}

private struct FollowContainer: UIViewRepresentable {
    @ObservedObject var model: FollowMeModel

    /// REACHED ONLY WHEN THE DOOR IS OPEN. `FollowMeView.body` puts this
    /// container behind an `if` on `CameraAvailability`, so SwiftUI never
    /// builds it — and this `ARView(cameraMode: .ar)` never exists — on a build
    /// with no camera usage description, a device that cannot world-track, or a
    /// phone where the person said no. It used to be unconditional, which is
    /// how a screen with no venue picker still managed to run an ARSession.
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        if ARWorldTrackingConfiguration.isSupported {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            view.session.run(config)
        }
        context.coordinator.attach(to: view, model: model)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}
    func makeCoordinator() -> FollowCoordinator { FollowCoordinator() }
    static func dismantleUIView(_ view: ARView, coordinator: FollowCoordinator) { coordinator.detach() }
}

@MainActor
final class FollowCoordinator: NSObject {
    private weak var view: ARView?
    private weak var model: FollowMeModel?
    private var updates: (any Cancellable)?
    private var anchor: AnchorEntity?
    private var duck: DuckGhostEntity?
    private var walk: DuckTrajectory?
    private var stand: DuckTrajectory?
    private var phase = 0.0
    private var lastTick: TimeInterval = 0

    func attach(to view: ARView, model: FollowMeModel) {
        self.view = view; self.model = model
        walk = try? DuckTrajectory.bundled(.walk)
        stand = try? DuckTrajectory.bundled(.stand)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    func detach() { updates = nil; anchor = nil; duck = nil; view = nil }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let view, let model, anchor == nil else { return }
        let point = gesture.location(in: view)
        let hits = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        let fallback = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        guard let hit = (hits.first ?? fallback.first) else { return }
        let root = AnchorEntity(world: hit.worldTransform)
        let ghost = DuckGhostEntity()
        root.addChild(ghost)
        view.scene.addAnchor(root)
        anchor = root; duck = ghost
        model.place(startingAt: personPosition() ?? .init(1, 0))
        lastTick = CACurrentMediaTime()
    }

    /// Where you are, on the floor, in the course's own frame. THE CAMERA POSE
    /// IS THE MEASUREMENT — height is dropped because the duck is following a
    /// person around a room, not a phone up a ladder.
    private func personPosition() -> DuckSoccer.Vec2? {
        guard let view, let anchor else { return nil }
        let camera = view.cameraTransform.translation
        let local = anchor.convert(position: camera, from: nil)
        return DuckSoccer.Vec2(Double(local.x), Double(-local.z))
    }

    private func frame() {
        guard let model, let duck, let person = personPosition() else { return }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? min(now - lastTick, 0.25) : 0
        lastTick = now
        model.advance(dt: dt, person: person)

        let follow = model.follow
        if let walk, let stand {
            if follow.isWalking {
                let clipSpeed = max(walk.deltaX / (Double(walk.frames.count) / walk.hz), 0.01)
                phase += follow.capabilities.walkSpeed * dt / clipSpeed
                duck.apply(jointAngles: walk.pose(at: phase).jointAngles)
            } else {
                duck.apply(jointAngles: stand.pose(
                    at: now.truncatingRemainder(dividingBy: 1000)).jointAngles)
            }
        }
        duck.position = SIMD3<Float>(Float(follow.duck.position.x), 0,
                                     Float(-follow.duck.position.y))
        duck.orientation = simd_quatf(angle: Float(-follow.duck.heading),
                                      axis: SIMD3<Float>(0, 1, 0))
    }
}
