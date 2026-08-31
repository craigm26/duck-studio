import SwiftUI
import ARKit
import RealityKit
import Combine
import QuartzCore
import StudioKit
import DuckKit
import DuckVisual
import DuckRender
import DuckEvidence

/// Five-a-side duck soccer on your carpet: you drive one duck, nine CPUs play
/// the rest, and every goal lands in a hash chain nobody can quietly edit.
///
/// THE MATCH IS CASTORKIT'S, THE PIXELS ARE HERE. `DuckSoccer.Match` advances
/// the whole game — roles, kicks, saves, halves — as a deterministic tick
/// function proved by `swift test` on Linux, at the robot's MEASURED envelope:
/// ducks in this match walk at the 0.106 m/s and turn at the 0.34 rad/s the
/// canon plant records for `alpha_walking`, so what you are playing is a claim
/// about what ten real Microducks could do on this floor. The one number that
/// is not measured is the kick speed, and the engine labels it gameplay tuning.
///
/// EVERY MATCH HERE IS A PRACTICE MATCH AND EXPORT IS REFUSED. All ten players
/// are ghosts; a match of simulations exported as evidence would be a
/// fabricated receipt. It is still signed and chained locally — the same code
/// path a real match will take — and the Export button demonstrates the
/// refusal on purpose.
struct DuckSoccerView: View {

    @StateObject private var referee = SoccerReferee()
    /// The setup dialog fronts every match — venue, theme, gear, half length,
    /// celebration — and the game only starts when it says so.
    @State private var showingSetup = true
    @State private var startRequested = false

    var body: some View {
        ZStack {
            SoccerContainer(referee: referee, startRequested: $startRequested)
                .ignoresSafeArea()

            VStack {
                if referee.isPlaced {
                    scoreboard
                }
                Spacer()
                if referee.isPlaced {
                    controls
                } else if !showingSetup {
                    Text(referee.status)
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            SoccerSetupSheet(referee: referee) {
                showingSetup = false
                referee.status = referee.venue == .ar
                    ? "Point at the floor and tap to lay out the pitch."
                    : "Welcome to \(referee.theme.name)."
                startRequested = true
            }
            .interactiveDismissDisabled()
        }
        .navigationTitle("Duck soccer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // NO GOAL-CELEBRATION PICKER. It offered one option and told
            // people to "author a motion in Duck Studio and open the .duckmove
            // here to celebrate with it" — which this build cannot do:
            // `CelebrationStore.importFile(at:)` has no caller anywhere, no
            // .duckmove is bundled, and `LibraryModel` routes that extension to
            // drafts. So `imported` is permanently empty and the sentence was
            // instructions for a door that does not exist. A setting that
            // cannot be set is not a placement problem; it comes out until the
            // import is real. `CelebrationStore` stays: its readers are correct
            // code with a nil input, and the roulade still plays.
        }
        .alert("Not exportable", isPresented: $referee.showingRefusal) {
            Button("I see", role: .cancel) {}
        } message: { Text(referee.refusalExplanation) }
    }

    private var scoreboard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                Text("YOU \(referee.homeGoals)")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.yellow)
                Text(referee.clockText).font(.callout.monospacedDigit())
                Text("\(referee.awayGoals) CPU")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.cyan)
            }
            Text(referee.status).font(.caption)
            // The chain head changes on every goal — which is the whole point
            // of showing it.
            Text("chain \(referee.chainHeadPrefix)")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 4)
    }

    /// A game controller, because that is what a football game is played on:
    /// stick on the left; on the right KICK and PASS with SPRINT under the
    /// thumb and SWITCH above them. Every hold button uses a zero-distance
    /// drag gesture, NOT a Button — a SwiftUI Button fires on TOUCH-UP, so the
    /// first version's kick registered only when the finger left the screen
    /// and then for a single engine tick, which played exactly like a kick
    /// button that does nothing.
    private var controls: some View {
        HStack(alignment: .bottom) {
            JoystickView { vector in referee.stick = vector }
                .frame(width: 130, height: 130)

            Spacer()

            if referee.isOver {
                VStack(spacing: 10) {
                    Button("Export as evidence") { referee.attemptExport() }
                        .buttonStyle(.bordered)
                    Button("Rematch") { referee.kickoff() }
                        .buttonStyle(.borderedProminent)
                }
            } else if referee.gamepadConnected {
                // The controller has the buttons; the screen keeps only the
                // legend, so nothing competes with the pad in hand.
                Label("A pass · B shoot · Y roulade/crouch · L1 switch · R2 sprint",
                      systemImage: "gamecontroller.fill")
                    .font(.caption)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
            } else {
                // The FIFA cluster, thumb-shaped: SHOOT outside where the
                // thumb rests, PASS beside it, the skill above, SPRINT below,
                // SWITCH on top — the L1 of a screen.
                // ROULADE holds the prime bottom spot — it is the signature
                // move, the measured forward roll, and it earned the thumb's
                // resting place; SPRINT moves up where ROLL used to sit.
                // (Roulade: French for "roll", and Pollen's own name for the
                // clip.)
                VStack(alignment: .trailing, spacing: 10) {
                    HoldButton(label: "SWITCH", size: 50, tint: .white.opacity(0.8)) {
                        if $0 { referee.requestSwitch = true }
                    }
                    HoldButton(label: "SPRINT", size: 56, tint: .orange) {
                        referee.sprintHeld = $0
                    }
                    HStack(spacing: 12) {
                        HoldButton(label: "PASS", size: 60, tint: .cyan) {
                            referee.passHeld = $0
                        }
                        HoldButton(label: "SHOOT", size: 76, tint: .yellow) {
                            referee.kickHeld = $0
                        }
                    }
                    // On legs the roulade; on wheels Pollen's crouch-glide
                    // trick — each the special move its policy set has.
                    HoldButton(label: referee.wearing == .legs ? "ROULADE" : "CROUCH",
                               size: 64, tint: .purple) {
                        referee.specialHeld = $0
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
    }
}

/// The team talk before kickoff: everything about the match, decided in one
/// place, before a single entity exists.
private struct SoccerSetupSheet: View {
    @ObservedObject var referee: SoccerReferee
    let onStart: () -> Void
    /// Soccer's venue switch is its own control rather than `VenuePicker` — it
    /// says "Stadium" where the games say "Stage" — so it carries its own copy
    /// of the door.
    @State private var door = CameraDoor.availability

    var body: some View {
        NavigationStack {
            Form {
                Section("Where") {
                    Picker("Venue", selection: $referee.venue) {
                        Text("Stadium").tag(SoccerReferee.Venue.stadium)
                        Text("Your floor (AR)").tag(SoccerReferee.Venue.ar)
                    }
                    .pickerStyle(.segmented)
                    // A segmented control cannot disable one segment, so the
                    // whole switch goes inert — which is honest, because with
                    // the carpet gone there is one venue and no choice — and
                    // the reason sits under it instead of arriving in a dialog
                    // after a tap that did nothing.
                    .disabled(!door.canOfferAR)
                    if let refusal = door.refusal(for: .venue) {
                        Text(refusal).font(.caption).foregroundStyle(.secondary)
                    }
                    if referee.venue == .stadium {
                        Picker("Stadium", selection: $referee.theme) {
                            ForEach(SoccerTheme.stadiums) { theme in
                                Text(theme.name).tag(theme)
                            }
                        }
                        Text("A whole palette, not an accent — pastel sherbet, the grid-sunset nineties, bowling-alley carpet, Saturday cartoon.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("The camera pitch on your carpet: point at the floor and tap to place it, facing the way you look.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Your duck wears") {
                    Picker("Gear", selection: $referee.wearing) {
                        Text("Legs").tag(SoccerReferee.Gear.legs)
                        Text("Skates").tag(SoccerReferee.Gear.skates)
                    }
                    .pickerStyle(.segmented)
                    Text(referee.wearing == .legs
                         ? "Walks 0.11 m/s, sprints 0.15, and can ROULADE — the measured forward roll, faster than running."
                         : "Pollen's roller blades: glides 0.45 m/s, tops out at 0.6, propelled by the real swizzle recorded from the roller policy — and the CROUCH trick instead of a roulade. Speeds are the older rollers scene's; its training-parameter rebuild is pending.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Match") {
                    Picker("Half length", selection: $referee.halfLength) {
                        Text("1 min").tag(60.0)
                        Text("2 min").tag(120.0)
                        Text("5 min").tag(300.0)
                    }
                    .pickerStyle(.segmented)
                }

                if GamepadInput.shared.isConnected {
                    Section {
                        Label("Controller connected — A pass · B shoot · Y roulade/crouch · L1 switch · R2 sprint",
                              systemImage: "gamecontroller.fill")
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        onStart()
                    } label: {
                        Text(referee.venue == .ar ? "Place the pitch" : "Kick off")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Match setup")
            .navigationBarTitleDisplayMode(.inline)
        }
        // The selection is put back rather than left pointing at a pitch that
        // cannot be laid: `start(venue:theme:)` refuses `.ar` when the door is
        // shut, and a refusal there would leave a match with no world in it.
        .onAppear { coerce() }
        .refreshingCameraDoor($door)
        .onChange(of: door) { _, _ in coerce() }
        .presentationDetents([.large])
    }

    private func coerce() {
        if !door.canOfferAR && referee.venue != .stadium { referee.venue = .stadium }
    }
}

/// A press-and-hold pad. Reports true on touch-down and false on release —
/// the contract the engine's held-control model wants.
private struct HoldButton: View {
    let label: String
    let size: CGFloat
    let tint: Color
    let onChange: (Bool) -> Void
    @State private var down = false

    var body: some View {
        Text(label)
            .font(size > 64 ? .headline : .caption.bold())
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(down ? 1.0 : 0.75)))
            .foregroundStyle(.black)
            .scaleEffect(down ? 0.92 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down { down = true; onChange(true) }
                    }
                    .onEnded { _ in
                        down = false; onChange(false)
                    })
    }
}

// MARK: - the referee

/// Owns the engine, the clock that drives it, and the match record.
@MainActor
final class SoccerReferee: ObservableObject {

    @Published var status = "Point at the floor and tap to lay out a pitch."
    @Published var isPlaced = false
    @Published var isOver = false
    @Published var homeGoals = 0
    @Published var awayGoals = 0
    @Published var clockText = "0:00"
    @Published var chainHeadPrefix = "GENESIS"
    @Published var showingRefusal = false
    @Published var refusalExplanation = ""
    /// Chosen at setup: the walking robot, or the skating one. Skates carry
    /// their own measured envelope — and their own caveat, which the setup
    /// sheet shows.
    @Published var wearing: Gear = .legs
    @Published var gamepadConnected = false
    /// Where the match is played: on your carpet, or in a themed stadium.
    @Published var venue: Venue = .stadium
    @Published var theme: SoccerTheme = .pastel
    /// Seconds per half, from the setup dialog.
    @Published var halfLength: Double = 120

    enum Gear: String { case legs, skates
        var capabilities: DuckSoccer.Capabilities { self == .legs ? .measured : .skates }
    }

    enum Venue: String { case ar, stadium }

    /// The human's inputs, written by the HUD and read by the tick. Held
    /// flags stay true for as long as the finger is down.
    var stick: DuckSoccer.Vec2 = .zero
    /// The stadium camera's azimuth, written by the coordinator each frame,
    /// so the stick can be CAMERA-relative there: "up" is away from the
    /// viewer whichever way the broadcast camera has been orbited. In AR
    /// the pitch faces the player at placement and the stick is field-
    /// relative as before.
    var cameraAzimuth: Double = 0
    var kickHeld = false
    var passHeld = false
    var sprintHeld = false
    var requestSwitch = false

    /// Render time not yet simulated. THE ENGINE ALWAYS STEPS AT THE ROBOT'S
    /// OWN 50 Hz: feeding it raw render dt made a 120 Hz phone integrate a
    /// different match from a 60 Hz one — the header's "two devices play the
    /// identical game" was false across frame rates until this accumulator.
    private var accumulator: Double = 0

    /// The whole game.
    private(set) var match = DuckSoccer.Match()

    /// Ten ghosts, identifiable as ghosts in the record itself — a simulated
    /// player must be marked in the data, not only by the flag beside it.
    static let rrns: [String] = DuckSoccer.Team.allCases.flatMap { team in
        (0..<5).map { "RRN-GHOST-\(team.rawValue.uppercased())-\($0)" }
    }

    private(set) var record = DuckSoccerMatch(participantRRNs: rrns, isPractice: true)
    // FULLY QUALIFIED, AND NO LONGER FOR THE REASON IT WAS. In OpenCastor this
    // file imported CastorKit, which declared a SigningKeyStore of its own —
    // the protocol predates the duck's split into its own package — so the
    // qualification resolved a genuine ambiguity. StudioKit declares no such
    // protocol, so nothing is ambiguous here any more. It stays qualified
    // because the match record is DuckEvidence's and the store that signs it
    // should be visibly the same package's, not because the compiler needs it.
    private let keyStore: any DuckEvidence.SigningKeyStore =
        DuckEvidence.KeychainSigningKeyStore()

    var specialHeld = false

    func kickoff() {
        stick = .zero
        kickHeld = false; passHeld = false; sprintHeld = false
        specialHeld = false
        requestSwitch = false
        accumulator = 0
        match = DuckSoccer.Match(capabilities: wearing.capabilities,
                                 halfLength: halfLength)
        record = DuckSoccerMatch(participantRRNs: Self.rrns, isPractice: true)
        record.append(.kickoff(atMs: Self.nowMs()))
        isOver = false
        homeGoals = 0; awayGoals = 0
        refreshChain()
        status = "Kick off. Your duck wears the bright ring."
    }

    /// Advance the match by however much render time has passed, in exact
    /// 50 Hz engine ticks.
    func tick(dt: Double) {
        guard isPlaced, !isOver else { return }
        // A paired controller wins over touch whenever one is connected —
        // holding a phone AND thumbing its screen is the fallback, not the
        // preference.
        var control = DuckSoccer.Control(stick: stick, kick: kickHeld,
                                         pass: passHeld, sprint: sprintHeld,
                                         special: specialHeld)
        if let pad = GamepadInput.shared.poll() {
            control = pad.control
            // The pad's held state is mirrored into the referee's flags:
            // the animator reads `specialHeld` for the CROUCH trick, and a
            // pad's Y never reached it.
            kickHeld = pad.control.kick; passHeld = pad.control.pass
            sprintHeld = pad.control.sprint; specialHeld = pad.control.special
            if pad.switchPressed { requestSwitch = true }
            gamepadConnected = true
        } else {
            gamepadConnected = false
        }
        if venue == .stadium {
            // Camera-relative: with the camera at azimuth a, "up" on the stick
            // is the pitch direction (−sin a, cos a) and "right" is
            // (cos a, sin a). At a = −π/2 this is the AR mapping exactly.
            let a = cameraAzimuth
            let up = control.stick.x, right = -control.stick.y
            control.stick = DuckSoccer.Vec2(-up * sin(a) + right * cos(a),
                                            up * cos(a) + right * sin(a))
        }
        if requestSwitch {
            match.switchControl()
            requestSwitch = false
        }
        let step = 1.0 / 50.0
        accumulator += min(dt, 0.25)
        var events: [DuckSoccer.Event] = []
        while accumulator >= step {
            accumulator -= step
            events.append(contentsOf: match.advance(
                dt: step, controls: [match.controlled ?? "": control]))
        }

        for event in events {
            switch event {
            case .goal(let team, let scorer):
                // The scorer's ghost RRN, so the record says WHICH simulation
                // scored — same shape a real match will use.
                let rrn = "RRN-GHOST-\(scorer.uppercased())"
                record.append(.goal(scorerRRN: rrn, atMs: Self.nowMs(),
                                    judgedBy: "engine-geometry"))
                refreshChain()
                status = team == .home ? "GOAL — you score!" : "CPU scores."
            case .halfTime:
                status = "Half time."
            case .fullTime:
                record.append(.finalWhistle(atMs: Self.nowMs()))
                refreshChain()
                isOver = true
                status = finalWords()
            case .whistle:
                status = "Play."
            case .kick, .roll:
                break
            }
        }

        homeGoals = match.score[.home] ?? 0
        awayGoals = match.score[.away] ?? 0
        let seconds = Int(match.clock)
        clockText = "H\(match.half) \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func finalWords() -> String {
        if homeGoals > awayGoals { return "Full time — you win \(homeGoals)–\(awayGoals)." }
        if awayGoals > homeGoals { return "Full time — the CPUs take it \(awayGoals)–\(homeGoals)." }
        return "Full time — a \(homeGoals)–\(awayGoals) draw."
    }

    func attemptExport() {
        do {
            let key = try keyStore.loadOrCreateIdentity()
            _ = try record.signedRecord(with: key, kid: DuckSigning.kid(for: key.publicKey))
            refusalExplanation = "Signed and ready to export."
        } catch DuckSoccerMatch.ExportRefusal.practiceMatchesStayOnDevice {
            refusalExplanation = """
                All ten players in this match are simulations, so it is a \
                practice match and stays on this device. It is still signed \
                and hash-chained locally — the refusal is about calling a \
                simulation evidence, not about whether the record is sound.
                """
        } catch {
            refusalExplanation = "The signing identity could not be loaded: \(error)"
        }
        showingRefusal = true
    }

    private func refreshChain() {
        chainHeadPrefix = String(record.chainHead.prefix(8))
    }

    private static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

// MARK: - the joystick

/// A plain drag-anywhere stick, FIELD-relative: up is always toward the CPU
/// goal, wherever you stand — the pitch is laid out facing you at placement,
/// and after that the mapping is the pitch's, like a foosball table's.
// Shared with the Bow Bridge crossing: one stick, one behaviour, one place to
// fix it. It was private only because nothing else needed it yet.
struct JoystickView: View {
    let onChange: (DuckSoccer.Vec2) -> Void
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(.yellow.opacity(0.8)).frame(width: 52, height: 52)
                .offset(offset)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let limit: CGFloat = 42
                    var dx = value.translation.width, dy = value.translation.height
                    let length = max((dx * dx + dy * dy).squareRoot(), 1)
                    if length > limit { dx *= limit / length; dy *= limit / length }
                    offset = CGSize(width: dx, height: dy)
                    // Screen up = pitch +x; screen right = pitch −y.
                    onChange(DuckSoccer.Vec2(Double(-dy / limit), Double(-dx / limit)))
                }
                .onEnded { _ in
                    offset = .zero
                    onChange(.zero)
                })
    }
}

// MARK: - the AR container

private struct SoccerContainer: UIViewRepresentable {
    @ObservedObject var referee: SoccerReferee
    @Binding var startRequested: Bool

    func makeUIView(context: Context) -> ARView {
        // The view starts BLANK — no session, no world — because the venue is
        // not known until the setup dialog closes. `updateUIView` reads the
        // start signal and builds whichever world was chosen.
        let view = ARView(frame: .zero, cameraMode: .nonAR,
                          automaticallyConfigureSession: false)
        view.environment.background = .color(.black)
        context.coordinator.attach(to: view, referee: referee)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        if startRequested {
            // Deferred: start() publishes referee state (kickoff), and
            // publishing from inside a view update is undefined behaviour.
            let coordinator = context.coordinator
            let venue = referee.venue, theme = referee.theme
            DispatchQueue.main.async {
                startRequested = false
                coordinator.start(venue: venue, theme: theme)
            }
        }
    }
    func makeCoordinator() -> SoccerCoordinator { SoccerCoordinator() }

    static func dismantleUIView(_ view: ARView, coordinator: SoccerCoordinator) {
        view.session.pause()
        coordinator.detach()
    }
}

/// Draws the match. Ten ducks — DuckRender's own entity, one coordinate
/// conversion for every screen that shows a duck — a ball, a boarded pitch
/// with two goals, and per-duck animation mapped from the engine's motion
/// states onto the canon clips.
@MainActor
final class SoccerCoordinator: NSObject, ARSessionDelegate {

    private weak var view: ARView?
    private var referee: SoccerReferee?
    private var updates: (any Cancellable)?
    private var pitch: AnchorEntity?
    private var ball: ModelEntity?
    private var ducks: [String: DuckGhostEntity] = [:]
    /// Per-duck animation clocks, advanced by each duck's own motion state.
    private var walkPhase: [String: Double] = [:]
    private var kickStart: [String: Double] = [:]
    /// Where each duck was drawn last frame, for distance-paced feet.
    private var lastDrawn: [String: SIMD3<Float>] = [:]
    /// Where each duck's roll STARTED, so the clip's own root motion — the
    /// tuck, the drop, the tumble — plays out from there instead of being
    /// thrown away.
    private var rollAnchor: [String: (x: Double, y: Double, heading: Double)] = [:]
    private var lastTick: TimeInterval = 0

    private var walk: DuckTrajectory?
    private var stand: DuckTrajectory?
    private var kickLeft: DuckIntentClip?
    private var roulade: DuckIntentClip?
    // ON ROLLERS: Pollen's roller policy, recorded — the swizzle that
    // propels a glide, at four speeds — and the crouch trick. See
    // DuckTrajectory.Clip for what each is.
    private var skateStand: DuckTrajectory?
    private var skate: DuckTrajectory?
    private var skateFast: DuckTrajectory?
    private var skateBack: DuckTrajectory?
    private var crouch: DuckIntentClip?
    /// Each duck's wheels' rolled angle so far, radians. The wheels are
    /// passive on the robot and not in any pose; they turn with the ground
    /// covered. The tyre is 30 mm across.
    private var wheelSpin: [String: Double] = [:]
    private var skatePhase: [String: Double] = [:]
    private var crouchStart: [String: TimeInterval] = [:]
    private static let tyreRadius = 0.015
    private var theme: SoccerTheme = .classic
    private var venue: SoccerReferee.Venue = .ar
    private var stadiumCamera = StadiumCamera()
    private var cameraEntity: PerspectiveCamera?
    private var lastPinch: CGFloat = 1

    func attach(to view: ARView, referee: SoccerReferee) {
        self.view = view
        self.referee = referee
        view.addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(handleTap)))
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    /// The setup dialog closed: build the chosen world.
    func start(venue: SoccerReferee.Venue, theme: SoccerTheme) {
        guard let view, let referee, pitch == nil else { return }

        // REFUSE BEFORE ANYTHING IS COMMITTED. The two assignments below used
        // to run first, so a refused AR start left the coordinator holding
        // `venue == .ar` with `pitch` still nil — a state no later code
        // expects. `handleTap` guards on exactly that pair, so the screen came
        // up looking alive and every tap on it did nothing, silently, which is
        // a worse outcome than the crash this gate was added to prevent.
        if venue == .ar, let refusal = CameraDoor.availability.refusal(for: .venue) {
            referee.status = refusal
            return
        }

        self.venue = venue
        self.theme = venue == .stadium ? theme : .classic

        if venue == .ar {
            // THE SECOND LOCK, AND THE ONE ABOVE `session.run`. The setup sheet
            // already disables the venue switch and puts the selection back
            // when the camera cannot be opened, so this is unreachable through
            // the UI — which is why it is here. Build 27 ran a session against
            // a plist that did not permit it and iOS killed the app; a gate
            // that lives only in a picker is a gate the next screen forgets.
            //
            // It returns rather than quietly kicking off in the stadium: the
            // person chose a carpet, and substituting a different venue without
            // saying so is the silent failure this app is built against. The
            // status line above is what they get instead.
            view.cameraMode = .ar
            view.environment.background = .cameraFeed()
            // Kept even though `refusal(for:)` has already read the same fact:
            // this is the ARKit-side check the file has always had, and it is
            // the one that sits immediately above the session.
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
            view.session.delegate = self
            view.session.run(config)
            // Placement continues via the tap handler.
            return
        }

        // THE STADIUM: no camera feed, no plane detection, no tap-to-place —
        // a world of its own under a themed sky, seen from the broadcast
        // camera. Everything else (the engine, the ducks, the controls) is
        // exactly the AR match.
        view.environment.background = .color(theme.sky)
        let anchor = AnchorEntity(world: .zero)
        view.scene.addAnchor(anchor)

        let key = DirectionalLight()
        key.light.intensity = 3200
        key.look(at: .zero, from: SIMD3<Float>(1.2, 2.2, 1.4), relativeTo: nil)
        anchor.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 1400
        fill.light.color = theme.sky
        fill.look(at: .zero, from: SIMD3<Float>(-1.4, 1.2, -1.0), relativeTo: nil)
        anchor.addChild(fill)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 42
        anchor.addChild(camera)
        cameraEntity = camera

        view.addGestureRecognizer(UIPanGestureRecognizer(
            target: self, action: #selector(orbit)))
        view.addGestureRecognizer(UIPinchGestureRecognizer(
            target: self, action: #selector(zoom)))

        buildPitch(on: anchor)
        buildStadiumDressing(on: anchor)
        view.scene.addAnchor(anchor)
        pitch = anchor
        referee.isPlaced = true
        lastTick = CACurrentMediaTime()
        referee.kickoff()
    }

    /// A failed session — camera access denied is the common one — says so
    /// instead of leaving a black view under "tap to place".
    func session(_ session: ARSession, didFailWithError error: Error) {
        let code = (error as NSError).code
        referee?.status = code == ARError.Code.cameraUnauthorized.rawValue
            ? "Camera access is off for OpenCastor — allow it in Settings, or play in the Stadium."
            : "The camera session failed: \(error.localizedDescription)"
    }

    @objc private func orbit(_ g: UIPanGestureRecognizer) {
        guard venue == .stadium else { return }
        let t = g.translation(in: g.view)
        stadiumCamera.drag(dx: Float(t.x), dy: Float(t.y))
        g.setTranslation(.zero, in: g.view)
    }

    @objc private func zoom(_ g: UIPinchGestureRecognizer) {
        guard venue == .stadium else { return }
        if g.state == .began { lastPinch = 1 }
        stadiumCamera.zoom(by: Float(g.scale / max(lastPinch, 0.0001)))
        lastPinch = g.scale
    }

    /// The stands and the mow stripes — pure dressing, zero gameplay.
    private func buildStadiumDressing(on anchor: AnchorEntity) {
        let spec = DuckSoccer.Pitch.livingRoom
        let halfL = Float(spec.halfLength), halfW = Float(spec.halfWidth)

        // Mow stripes: alternating tinted panels over the floor slab.
        let stripeCount = 8
        let stripeWidth = halfL * 2 / Float(stripeCount)
        for index in 0..<stripeCount {
            let colour = index % 2 == 0 ? theme.floor : theme.stripe
            let stripe = ModelEntity(
                mesh: .generateBox(width: stripeWidth, height: 0.004,
                                   depth: halfW * 2 + 0.5),
                materials: [SimpleMaterial(color: colour, roughness: 0.9,
                                           isMetallic: false)])
            stripe.position = SIMD3<Float>(
                -halfL + stripeWidth * (Float(index) + 0.5), -0.004, 0)
            anchor.addChild(stripe)
        }

        // Stands: two long tiers each side, stepped like terraces.
        let standMaterial = SimpleMaterial(color: theme.stands, roughness: 0.95,
                                           isMetallic: false)
        for side in [Float(1), -1] {
            for tier in 0..<2 {
                let stand = ModelEntity(
                    mesh: .generateBox(width: halfL * 2 + 0.9,
                                       height: 0.10 + Float(tier) * 0.06,
                                       depth: 0.18),
                    materials: [standMaterial])
                stand.position = SIMD3<Float>(
                    0, (0.10 + Float(tier) * 0.06) / 2,
                    side * (halfW + 0.32 + Float(tier) * 0.20))
                anchor.addChild(stand)
            }
        }
    }

    func detach() {
        updates = nil
        ball = nil
        pitch = nil
        ducks = [:]
        view = nil
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard venue == .ar, let view, let referee, pitch == nil else { return }
        let point = gesture.location(in: view)
        let hits = view.raycast(from: point, allowing: .existingPlaneGeometry,
                                alignment: .horizontal)
        let fallback = view.raycast(from: point, allowing: .estimatedPlane,
                                    alignment: .horizontal)
        guard let hit = hits.first ?? fallback.first else {
            referee.status = "No floor there yet — move the phone and tap again."
            return
        }
        // THE PITCH FACES THE PLAYER. A raw plane anchor's yaw is whatever
        // ARKit happened to wake up with, so the first build could lay the CPU
        // goal off to your left or behind you and the stick's "up" pointed at
        // a wall. At placement, pitch +x — the direction you attack — points
        // where the phone is looking, projected onto the floor. The mapping is
        // field-relative after that: walk around the pitch and your frame
        // rotates with you, exactly like walking around a foosball table.
        var transform = hit.worldTransform
        let camera = view.cameraTransform
        let forward = SIMD3<Float>(-camera.matrix.columns.2.x, 0,
                                   -camera.matrix.columns.2.z)
        if simd_length(forward) > 1e-4 {
            let f = simd_normalize(forward)
            let yaw = atan2f(-f.z, f.x)
            let rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let position = SIMD3<Float>(transform.columns.3.x,
                                        transform.columns.3.y,
                                        transform.columns.3.z)
            transform = float4x4(rotation)
            transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        }
        let anchor = AnchorEntity(world: transform)
        buildPitch(on: anchor)
        view.scene.addAnchor(anchor)
        pitch = anchor
        referee.isPlaced = true
        lastTick = CACurrentMediaTime()
        referee.kickoff()
    }

    // MARK: - building the world

    private func buildPitch(on anchor: AnchorEntity) {
        let spec = DuckSoccer.Pitch.livingRoom
        let halfL = Float(spec.halfLength), halfW = Float(spec.halfWidth)
        let mouthHalf = Float(spec.goalHalfWidth)

        var line = UnlitMaterial(color: theme.line)
        line.blending = .transparent(opacity: 0.9)
        let board = SimpleMaterial(color: theme.board, roughness: 0.6,
                                   isMetallic: false)

        // Boards, because the engine plays board soccer: the ball rebounds
        // rather than going out. Low enough to see over from standing height.
        let boardHeight: Float = 0.05
        let longBoard = MeshResource.generateBox(width: halfL * 2, height: boardHeight,
                                                 depth: 0.008)
        for z in [-halfW, halfW] {
            let e = ModelEntity(mesh: longBoard, materials: [board])
            e.position = SIMD3<Float>(0, boardHeight / 2, z)
            anchor.addChild(e)
        }
        // End boards leave the goal mouth open.
        let endSegment = (halfW - mouthHalf)
        let endBoard = MeshResource.generateBox(width: 0.008, height: boardHeight,
                                                depth: endSegment)
        for x in [-halfL, halfL] {
            for sign in [Float(1), -1] {
                let e = ModelEntity(mesh: endBoard, materials: [board])
                e.position = SIMD3<Float>(x, boardHeight / 2,
                                          sign * (mouthHalf + endSegment / 2))
                anchor.addChild(e)
            }
        }

        // Centre line and spot.
        let centre = ModelEntity(
            mesh: .generateBox(width: 0.004, height: 0.002, depth: halfW * 2),
            materials: [line])
        centre.position = SIMD3<Float>(0, 0.001, 0)
        anchor.addChild(centre)

        // Two goals: posts, crossbar, net panel. Home defends −x (yours),
        // the CPUs defend +x.
        for (x, tint) in [(-halfL, theme.homeGoal), (halfL, theme.awayGoal)] {
            var net = UnlitMaterial(color: tint.withAlphaComponent(0.30))
            net.blending = .transparent(opacity: 0.30)
            let frame = UnlitMaterial(color: .white)
            let height: Float = 0.22
            let postMesh = MeshResource.generateBox(width: 0.012, height: height, depth: 0.012)
            for z in [-mouthHalf, mouthHalf] {
                let post = ModelEntity(mesh: postMesh, materials: [frame])
                post.position = SIMD3<Float>(Float(x), height / 2, z)
                anchor.addChild(post)
            }
            let bar = ModelEntity(
                mesh: .generateBox(width: 0.012, height: 0.012, depth: mouthHalf * 2 + 0.012),
                materials: [frame])
            bar.position = SIMD3<Float>(Float(x), height, 0)
            anchor.addChild(bar)
            let depth = Float(spec.goalDepth)
            let panel = ModelEntity(
                mesh: .generateBox(width: depth, height: height, depth: mouthHalf * 2),
                materials: [net])
            panel.position = SIMD3<Float>(Float(x) + (x > 0 ? depth : -depth) / 2,
                                          height / 2, 0)
            anchor.addChild(panel)
        }

        let ballEntity = ModelEntity(mesh: .generateSphere(radius: 0.02),
                                     materials: [UnlitMaterial(color: theme.ball)])
        ballEntity.position = SIMD3<Float>(0, 0.02, 0)
        anchor.addChild(ballEntity)
        ball = ballEntity

        // Ten ducks. DuckRender's entity — the same duck, the same coordinate
        // conversion, as every other screen. Team rings underneath, because
        // the entity paints the robot's real colours and a jersey would paint
        // over the machine.
        guard let match = referee?.match else { return }
        // Everyone wears what the match was set up in: the legs mesh, or
        // Pollen's roller blades with their four wheels.
        let variant: DuckKinematics.Variant = referee?.wearing == .skates ? .rollers : .legs
        for player in match.players {
            let duck = DuckGhostEntity(variant: variant)
            anchor.addChild(duck)
            ducks[player.id] = duck

            let isYou = player.id == match.controlled
            let tint: UIColor = player.team == .home ? .systemYellow : .systemTeal
            let ring = ModelEntity(
                mesh: .generatePlane(width: 0.16, depth: 0.16, cornerRadius: 0.08),
                materials: [UnlitMaterial(color: tint.withAlphaComponent(isYou ? 0.9 : 0.35))])
            ring.position = SIMD3<Float>(0, 0.003, 0)
            duck.addChild(ring)
        }

        walk = try? DuckTrajectory.bundled(.walk)
        stand = try? DuckTrajectory.bundled(.stand)
        let clips = try? DuckIntentClip.bundled()
        kickLeft = clips?["kick_left"]
        roulade = clips?["roulade"]
        skateStand = try? DuckTrajectory.bundled(.skateStand)
        skate = try? DuckTrajectory.bundled(.skate)
        skateFast = try? DuckTrajectory.bundled(.skateFast)
        skateBack = try? DuckTrajectory.bundled(.skateBack)
        crouch = clips?["roller_crouch"]
    }

    // MARK: - every frame

    /// The clip's recorded root, carried to where the duck actually is.
    ///
    /// THE ROLL IS A ROOT-MOTION CLIP AND THE FIRST ANIMATOR THREW THE ROOT
    /// AWAY. It applied the roll's joint angles while the ENGINE kept the duck
    /// upright at standing height — so on screen the duck hovered, half-tucked,
    /// and never tumbled: the drop to the floor, the 360° of trunk pitch, the
    /// forward travel all live in the recording's root, not its joints. This
    /// rotates the clip root by the duck's heading, translates it to the
    /// anchor, and hands the result to DuckGhostEntity.place — the same
    /// placement path every recorded clip uses, trunk offset and all.
    private func worldRoot(clip root: DuckIntentClip.Root,
                           anchorX: Double, anchorY: Double,
                           heading: Double) -> DuckIntentClip.Root {
        let cosH = cos(heading), sinH = sin(heading)
        let x = anchorX + root.x * cosH - root.y * sinH
        let y = anchorY + root.x * sinH + root.y * cosH
        // The heading as a quaternion about +z, composed ahead of the clip's
        // own orientation: world = yaw ∘ recorded.
        let hw = cos(heading / 2), hz = sin(heading / 2)
        let (w, qx, qy, qz) = root.quaternion
        let quaternion = (hw * w - hz * qz,
                          hw * qx - hz * qy,
                          hw * qy + hz * qx,
                          hw * qz + hz * w)
        return DuckIntentClip.Root(x: x, y: y, z: root.z, quaternion: quaternion)
    }

    /// A duck on wheels, drawn from what the roller policy actually does.
    ///
    /// THE FIRST VERSION HELD THE STAND POSE AND SLID. That was honest about
    /// what had been recorded — nothing — and looked like a toy on a string.
    /// The roller policy propels itself with a ~0.62 s swizzle of hip yaw,
    /// knee and ankle; DuckTrajectory carries it at four speeds, and it is
    /// paced by ground covered like the walk, so the legs never slide. The
    /// wheels turn with the same distance. The CROUCH button plays Pollen's
    /// crouch-glide trick — visual only: the engine has no special on wheels.
    ///
    /// KEYED ON THE ENGINE'S MOTION STATE, not on per-frame displacement:
    /// the referee steps the engine at 50 Hz from an accumulator, so a 60 Hz
    /// display gets one render frame in six with no tick and zero
    /// displacement — and the second version read that as "stopped", reset
    /// the swizzle to phase 0 and flashed the idle pose ten times a second.
    private func drawSkater(_ duck: DuckGhostEntity, player: DuckSoccer.Player,
                            match: DuckSoccer.Match, signed: Double, travelled: Double,
                            dt: Double, celebration: (id: String, at: Double)?) {
        // A teleport on wheels is a lineup reset, not a fast frame: the
        // threshold is the envelope's — fast glide plus the separation shove
        // over the referee's 0.25 s dt clamp — so one hitched frame at skate
        // speed is not thrown away.
        let teleport = travelled > (match.capabilities.fastSpeed + 0.11) * 0.25 + 0.02
        let spin = (wheelSpin[player.id] ?? 0) + (teleport ? 0 : signed / Self.tyreRadius)
        wheelSpin[player.id] = spin
        let now = CACurrentMediaTime()

        /// The crouch trick WITH ITS ROOT: the trunk drops from 0.12 m to
        /// ~0.07 m and leans; drawn from a fixed trunk the wheels lifted
        /// 5 cm off the floor. The engine keeps the duck's x/y and heading;
        /// the clip supplies height and attitude.
        func crouched(_ crouch: DuckIntentClip, at t: TimeInterval) {
            let clipPose = crouch.pose(at: min(max(t, 0), crouch.duration - 0.02))
            let attitude = DuckIntentClip.Root(x: 0, y: 0, z: clipPose.root.z,
                                               quaternion: clipPose.root.quaternion)
            duck.place(root: worldRoot(clip: attitude,
                                       anchorX: player.position.x, anchorY: player.position.y,
                                       heading: player.heading),
                       jointAngles: clipPose.jointAngles)
        }

        if let celebration, celebration.id == player.id {
            if player.team == .home, let move = CelebrationStore.shared.chosen?.move {
                duck.apply(jointAngles: move.pose(at: celebration.at), wheelSpin: spin)
                return
            }
            if let crouch { crouched(crouch, at: celebration.at); return }
        }

        if player.id == match.controlled, referee?.specialHeld == true, let crouch {
            let start = crouchStart[player.id] ?? now
            crouchStart[player.id] = start
            crouched(crouch, at: (now - start).truncatingRemainder(dividingBy: crouch.duration))
            return
        }
        crouchStart[player.id] = nil

        switch player.motion {
        case .kicking:
            // A kick is a kick on wheels too: everything above the ankles is
            // the same robot, and the engine roots the kicker for 0.9 s.
            if kickStart[player.id] == nil { kickStart[player.id] = now }
            if let kick = kickLeft, let start = kickStart[player.id] {
                duck.apply(jointAngles: kick.pose(at: now - start).jointAngles, wheelSpin: spin)
            }
        case .walking, .rolling:
            kickStart[player.id] = nil
            // Which glide: reversing, sprinting, or cruising. The phase only
            // ever advances — a frame with no engine tick adds nothing and
            // resets nothing.
            let clip: DuckTrajectory?
            if signed < 0 { clip = skateBack }
            else { clip = (dt > 0 && travelled / dt > 0.5) || (referee?.sprintHeld == true
                            && player.id == match.controlled) ? skateFast : skate }
            if let clip {
                let clipSpeed = max(abs(clip.deltaX) / clip.duration, 0.05)
                let phase = (skatePhase[player.id] ?? 0) + (teleport ? 0 : travelled / clipSpeed)
                skatePhase[player.id] = phase
                duck.apply(jointAngles: clip.pose(at: phase).jointAngles, wheelSpin: spin)
            }
        case .standing:
            kickStart[player.id] = nil
            skatePhase[player.id] = 0
            if let idle = skateStand {
                duck.apply(jointAngles: idle.pose(
                    at: now.truncatingRemainder(dividingBy: 1000)).jointAngles, wheelSpin: spin)
            }
        }
    }

    private func frame() {
        guard let referee, pitch != nil else { return }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? now - lastTick : 0
        lastTick = now
        referee.tick(dt: dt)
        draw(match: referee.match, dt: dt)
        // The broadcast camera follows the orbit state; AR has a real camera
        // and needs none of this.
        if let cameraEntity {
            cameraEntity.look(at: SIMD3<Float>(0, 0.05, 0),
                              from: stadiumCamera.position, relativeTo: nil)
            referee.cameraAzimuth = Double(stadiumCamera.azimuth)
        }
    }

    /// Put every duck and the ball where the engine says, wearing the pose the
    /// canon clips say.
    ///
    /// WALKING IS PACED BY THE GROUND ACTUALLY COVERED. Each duck's clip phase
    /// advances by its own displacement this frame over the walk clip's
    /// recorded speed — signed along the heading, so REVERSING plays the gait
    /// backwards, which is what a robot stepping backwards looks like. The
    /// first version fed a constant walk speed to every mover, and the review
    /// measured the result: 29% foot-slide on sprinting ducks and striding on
    /// the spot while pivoting — the exact artifact this docstring claimed the
    /// design prevented.
    private func draw(match: DuckSoccer.Match, dt: Double) {
        if let ball {
            ball.position = SIMD3<Float>(Float(match.ball.position.x), 0.02,
                                         Float(-match.ball.position.y))
        }
        guard let walk, let stand else { return }
        let clipSpeed = max(walk.deltaX / (Double(walk.frames.count) / walk.hz), 0.01)

        // Who is celebrating, and how far into the roll they are.
        var celebration: (id: String, at: Double)?
        if case .goal(_, let scorer, let remaining) = match.phase {
            celebration = (scorer, 3.2 - remaining)
        }

        for player in match.players {
            guard let duck = ducks[player.id] else { continue }
            let position = SIMD3<Float>(Float(player.position.x), 0,
                                        Float(-player.position.y))

            // Distance actually covered, SIGNED along the heading so reverse
            // plays the gait backwards. A teleport (kickoff or reset moves a
            // duck across the pitch in one frame) resets the pacing instead of
            // spinning the clip through several strides.
            let previous = lastDrawn[player.id] ?? position
            let dx = Double(position.x - previous.x)
            let dz = Double(position.z - previous.z)
            let travelled = (dx * dx + dz * dz).squareRoot()
            lastDrawn[player.id] = position
            let forward = dx * cos(player.heading) + (-dz) * sin(player.heading)
            let signed = forward < 0 ? -travelled : travelled

            duck.position = position
            duck.orientation = simd_quatf(angle: Float(player.heading),
                                          axis: SIMD3<Float>(0, 1, 0))

            // No roll in progress means no anchor: the roll-end tick and the
            // next walking tick can land in one render frame, and a stale
            // anchor drew the NEXT roll from the previous roll's start.
            if player.rollElapsed == nil { rollAnchor[player.id] = nil }

            if duck.variant == .rollers {
                drawSkater(duck, player: player, match: match, signed: signed,
                           travelled: travelled, dt: dt, celebration: celebration)
                continue
            }

            // A goal celebration outranks the engine's motion state. YOUR
            // team's scorer performs the motion you authored in Duck Studio,
            // if you chose one; everyone else — and your team, when you have
            // not — rolls Pollen's own roulade. An authored move is a list of
            // poses smoothstepped between keyframes, so it plays through
            // DuckMove.pose(at:), the same arithmetic the editor previews.
            if let celebration, celebration.id == player.id {
                if player.team == .home,
                   let move = CelebrationStore.shared.chosen?.move {
                    duck.apply(jointAngles: move.pose(at: celebration.at))
                    walkPhase[player.id] = 0
                    continue
                }
                if let roll = roulade {
                    // With its ROOT: the scorer actually goes over and comes
                    // back up, at its own spot, facing its own way.
                    let clipPose = roll.pose(at: celebration.at)
                    duck.place(root: worldRoot(clip: clipPose.root,
                                               anchorX: player.position.x,
                                               anchorY: player.position.y,
                                               heading: player.heading),
                               jointAngles: clipPose.jointAngles)
                    walkPhase[player.id] = 0
                    continue
                }
            }

            switch player.motion {
            case .rolling:
                // The canon roulade at exactly the engine's elapsed time — and
                // WITH ITS ROOT, anchored where the roll began. The engine
                // advances the duck linearly at the measured average; the clip
                // root carries the true profile (it reaches 0.56 m by 1.5 s
                // and holds), and the two do NOT quite meet at the end: the
                // recording drifts 8 cm sideways and 8.5° in yaw that the
                // engine's straight line does not, so the handover to the
                // standing pose carries that small snap. A blend over the
                // last tenths of a second is the obvious next step.
                if let roll = roulade, let elapsed = player.rollElapsed {
                    let anchor = rollAnchor[player.id] ?? {
                        let fresh = (x: player.position.x, y: player.position.y,
                                     heading: player.heading)
                        rollAnchor[player.id] = fresh
                        return fresh
                    }()
                    let clipPose = roll.pose(at: elapsed)
                    duck.place(root: worldRoot(clip: clipPose.root,
                                               anchorX: anchor.x, anchorY: anchor.y,
                                               heading: anchor.heading),
                               jointAngles: clipPose.jointAngles)
                    walkPhase[player.id] = 0
                    kickStart[player.id] = nil
                    lastDrawn[player.id] = duck.position
                    continue
                }
                walkPhase[player.id] = 0
                kickStart[player.id] = nil
            case .kicking:
                if kickStart[player.id] == nil {
                    kickStart[player.id] = CACurrentMediaTime()
                }
                if let kick = kickLeft, let start = kickStart[player.id] {
                    duck.apply(jointAngles: kick.pose(at: CACurrentMediaTime() - start)
                        .jointAngles)
                }
            case .walking:
                if !match.capabilities.canRoll {
                    // SKATES GLIDE. No skating gait is recorded in the
                    // trajectory set yet, and a stepping walk under a duck
                    // moving at four times walking speed reads as a cartoon —
                    // the settled stand pose gliding is closer to what
                    // BEST_roller actually does.
                    duck.apply(jointAngles: stand.pose(
                        at: CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))
                        .jointAngles)
                    kickStart[player.id] = nil
                } else if travelled > 0.05 {
                    // A teleport, not a stride: reset rather than replay.
                    walkPhase[player.id] = 0
                } else {
                    let phase = (walkPhase[player.id] ?? 0) + signed / clipSpeed
                    walkPhase[player.id] = phase
                    duck.apply(jointAngles: walk.pose(at: phase).jointAngles)
                }
                kickStart[player.id] = nil
            case .standing:
                rollAnchor[player.id] = nil
                kickStart[player.id] = nil
                duck.apply(jointAngles: stand.pose(
                    at: CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))
                    .jointAngles)
            }
        }
    }
}
