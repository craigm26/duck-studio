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
    @StateObject private var moves = SoccerMovesStore()
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var benches: BenchStore

    /// Where the person is: choosing a match, or playing one.
    @State private var inLobby = true
    @State private var startRequested = false
    @State private var resetRequested = false

    var body: some View {
        ZStack {
            SoccerContainer(referee: referee, startRequested: $startRequested,
                            resetRequested: $resetRequested)
                .ignoresSafeArea()

            if referee.isPlaced && !inLobby {
                VStack {
                    hud
                    Spacer()
                    if !referee.isOver && !referee.isPaused && !referee.practiceDone { controls }
                }
                if let toast = referee.toast {
                    ToastView(toast: toast).allowsHitTesting(false)
                }
                if referee.isPaused { pauseMenu }
                if referee.isOver { results }
                if referee.practiceDone { practiceResults }
            } else if !inLobby {
                placementNote
            }

            if inLobby { lobby }
        }
        .navigationTitle("Duck soccer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(inLobby ? .visible : .hidden, for: .navigationBar)
        .statusBarHidden(!inLobby)
    }

    // MARK: - the lobby

    private var lobby: some View {
        SoccerLobby(referee: referee, moves: moves, library: library, drafts: drafts,
                    benches: benches) { begin() }
        .transition(.opacity)
    }

    /// Get the moves ready, take down any pitch, and lay out a fresh one for
    /// whatever the lobby chose: a match, or a drill.
    private func begin() {
        Task {
            await moves.prepare(library: library, drafts: drafts, benches: benches)
            referee.moves = moves.moves
            referee.customClips = moves.clips
            referee.saveSettings()
            inLobby = false
            if referee.isPlaced { resetRequested = true }
            referee.status = referee.venue == .ar
                ? "Point at the floor and tap to lay out the pitch." : ""
            startRequested = true
        }
    }

    // MARK: - during play

    /// One pill: the score and the clock, and a pause button beside it.
    private var hud: some View {
        HStack(spacing: Theme.spacing(.snug)) {
            if let drill = referee.drill {
                HStack(spacing: 10) {
                    Image(systemName: drill.symbol)
                    Text(drill.title).font(.subheadline.weight(.bold))
                    Divider().frame(height: 18)
                    Text(referee.practiceLine).font(.subheadline.monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
            } else {
            HStack(spacing: 10) {
                Text("YOU").font(.caption.weight(.heavy)).foregroundStyle(.yellow)
                Text("\(referee.homeGoals)  –  \(referee.awayGoals)")
                    .font(.title3.weight(.bold).monospacedDigit())
                Text("CPU").font(.caption.weight(.heavy)).foregroundStyle(.teal)
                Divider().frame(height: 18)
                Text(referee.clockText).font(.subheadline.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Score: you \(referee.homeGoals), CPU \(referee.awayGoals). "
                                     + referee.clockText))
            }
            Button {
                referee.isPaused = true
            } label: {
                Image(systemName: "pause.fill")
                    .font(.headline).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel(Text("Pause"))
        }
        .padding(.top, Theme.spacing(.tight))
    }

    private var placementNote: some View {
        VStack(spacing: Theme.spacing(.snug)) {
            Spacer()
            Text(referee.status)
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(Theme.spacing(.snug))
                .background(.black.opacity(0.6), in: Capsule())
            Button("Back to the lobby") { backToLobby() }
                .buttonStyle(.bordered).tint(.white)
                .padding(.bottom, Theme.spacing(.loose))
        }
        .accessibilityLabel(Text("Pitch placement"))
    }

    private var controls: some View {
        HStack(alignment: .bottom) {
            JoystickView { vector in referee.stick = vector }
            Spacer()
            if !referee.gamepadConnected { thumbCluster }
        }
        .padding(.horizontal, Theme.spacing(.loose))
        .padding(.bottom, Theme.spacing(.loose))
    }

    private func name(_ slot: SoccerLoadout.Slot) -> String? {
        moves.clips[slot] == nil ? nil : moves.loadout[slot]?.name
    }

    private var thumbCluster: some View {
        VStack(alignment: .trailing, spacing: Theme.spacing(.tight)) {
            HStack(spacing: Theme.spacing(.snug)) {
                HoldButton(label: "SWITCH", size: SoccerMetric.switchPad, role: .redirects,
                           hint: "Hands your stick to the team-mate nearest the ball.") {
                    if $0 { referee.requestSwitch = true }
                }
                HoldButton(label: "SPRINT", size: SoccerMetric.switchPad, role: .redirects,
                           hint: "Held, your duck moves at its top speed.") {
                    referee.sprintHeld = $0
                }
            }
            HStack(spacing: Theme.spacing(.snug)) {
                HoldButton(label: "PASS", size: SoccerMetric.passPad, role: .commands,
                           hint: "Held, your duck plays the ball forward, softly.",
                           subtitle: name(.pass), cooldown: referee.strikeCooldown) {
                    referee.passHeld = $0
                }
                HoldButton(label: "SHOOT", size: SoccerMetric.shootPad, role: .commands,
                           hint: "Held, your duck strikes the ball hard, the way it is facing.",
                           subtitle: name(.shoot), cooldown: referee.strikeCooldown,
                           ready: referee.ballInRange) {
                    referee.kickHeld = $0
                }
            }
            if referee.hasSpecial {
                HoldButton(label: "SPECIAL", size: SoccerMetric.specialPad, role: .commands,
                           hint: "Held, your duck does its Special move.",
                           subtitle: name(.special) ?? (referee.wearing == .legs ? "Roulade" : nil),
                           cooldown: referee.specialCooldown) {
                    referee.specialHeld = $0
                }
            }
        }
    }

    // MARK: - paused, and over

    private var pauseMenu: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Theme.spacing(.snug)) {
                Text("Paused").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                Button { referee.isPaused = false } label: {
                    Text("Resume").frame(maxWidth: 240)
                }
                .buttonStyle(.primaryActionMoves)
                Button { referee.isPaused = false; referee.kickoff() } label: {
                    Text("Restart").frame(maxWidth: 240)
                }
                .buttonStyle(.bordered).tint(.white)
                Button { backToLobby() } label: {
                    Text("Lobby").frame(maxWidth: 240)
                }
                .buttonStyle(.bordered).tint(.white)
                controlsLegend.padding(.top, Theme.spacing(.snug))
            }
            .padding()
        }
    }

    private var controlsLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Controls").font(.caption.weight(.bold))
            Text("Stick: move · SHOOT: strike · PASS: soft ball · SPECIAL: your move · "
               + "SWITCH: take the duck nearest the ball")
            Text("Controller: B shoot · A pass · Y special · L1 switch · R2 sprint")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var results: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: Theme.spacing(.snug)) {
                Text(resultWord).font(.largeTitle.weight(.heavy)).foregroundStyle(.white)
                Text("\(referee.homeGoals) – \(referee.awayGoals)")
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                HStack(spacing: Theme.spacing(.loose)) {
                    stat("Your shots", referee.homeShots)
                    stat("CPU shots", referee.awayShots)
                    stat("Your goals", referee.homeGoals)
                }
                Button { referee.kickoff() } label: { Text("Rematch").frame(maxWidth: 240) }
                    .buttonStyle(.primaryActionMoves)
                Button { backToLobby() } label: { Text("Lobby").frame(maxWidth: 240) }
                    .buttonStyle(.bordered).tint(.white)
            }
            .padding()
        }
    }

    private var practiceResults: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: Theme.spacing(.snug)) {
                if let drill = referee.drill {
                    Text(drill.title).font(.title.weight(.heavy)).foregroundStyle(.white)
                    StarRow(count: referee.practiceStars, size: 40)
                    Text(referee.practiceLine).font(.headline).foregroundStyle(.white)
                    Text("Best: \(SoccerReferee.bestStars(drill)) of 3 stars")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    Button { referee.kickoff() } label: { Text("Try again").frame(maxWidth: 240) }
                        .buttonStyle(.primaryActionMoves)
                    if let next = nextDrill(after: drill) {
                        Button {
                            referee.drill = next
                            begin()
                        } label: { Text("Next: \(next.title)").frame(maxWidth: 240) }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    Button { backToLobby() } label: { Text("Lobby").frame(maxWidth: 240) }
                        .buttonStyle(.bordered).tint(.white)
                }
            }
            .padding()
        }
    }

    private func nextDrill(after d: SoccerPractice.Drill) -> SoccerPractice.Drill? {
        let all = SoccerPractice.Drill.allCases
        guard let i = all.firstIndex(of: d), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold).monospacedDigit())
            Text(title).font(.caption)
        }
        .foregroundStyle(.white)
    }

    private var resultWord: String {
        if referee.homeGoals > referee.awayGoals { return "You win!" }
        if referee.awayGoals > referee.homeGoals { return "CPU wins" }
        return "Draw"
    }

    private func backToLobby() {
        referee.isPaused = false
        resetRequested = true
        withAnimation { inLobby = true }
    }
}

/// Three stars, filled up to `count`.
private struct StarRow: View {
    let count: Int
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i < count ? Color.yellow : Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) of 3 stars"))
    }
}

/// A big word in the middle of the pitch for a moment: GOAL!, Half time.
private struct ToastView: View {
    let toast: SoccerReferee.Toast
    @State private var shown = false

    var body: some View {
        Text(toast.text)
            .font(.system(size: toast.big ? 64 : 34, weight: .heavy))
            .foregroundStyle(toast.colour)
            .shadow(color: .black.opacity(0.6), radius: 6)
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { shown = true } }
            .id(toast.id)
            .accessibilityHidden(true)
    }
}

/// Choosing a match: where, what the duck wears, how long, how hard, and
/// your moves. Everything is remembered for next time.
private struct SoccerLobby: View {
    @ObservedObject var referee: SoccerReferee
    @ObservedObject var moves: SoccerMovesStore
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var benches: BenchStore
    let onStart: () -> Void
    @State private var door = CameraDoor.availability

    var body: some View {
            List {
                Section {
                    Picker("Mode", selection: Binding(
                        get: { referee.drill == nil ? 0 : 1 },
                        set: { referee.drill = $0 == 0 ? nil : (referee.drill ?? .penalties) })) {
                        Text("Match").tag(0)
                        Text("Practice").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    Button { onStart() } label: {
                        HStack {
                            Image(systemName: referee.drill?.symbol ?? "soccerball")
                            Text(moves.preparing ?? (referee.venue == .ar ? "Place the pitch"
                                 : referee.drill.map { "Start: \($0.title)" } ?? "Kick off"))
                        }
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.primaryActionMoves)
                    .disabled(moves.preparing != nil)
                    .listRowBackground(Color.clear)
                }

                if referee.drill != nil {
                    Section {
                        ForEach(SoccerPractice.Drill.allCases) { d in
                            Button { referee.drill = d } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: d.symbol).frame(width: 28)
                                        .foregroundStyle(Theme.actionPrimary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.title).font(.headline).foregroundStyle(Theme.textPrimary)
                                        Text(d.blurb).font(.caption).foregroundStyle(Theme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        StarRow(count: SoccerReferee.bestStars(d), size: 11)
                                        if referee.drill == d {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Theme.actionPrimary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        SectionHeading(text: "Skill challenges")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                Section {
                    NavigationLink {
                        SoccerMovesView(store: moves, library: library, drafts: drafts)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your moves").font(.headline)
                            ForEach(SoccerLoadout.Slot.allCases) { slot in
                                HStack(spacing: 8) {
                                    Image(systemName: slot.symbol).frame(width: 20)
                                        .foregroundStyle(Theme.actionPrimary)
                                    Text(slot.title).font(.subheadline)
                                    Spacer()
                                    Text(moves.loadout[slot]?.name ?? slot.standard)
                                        .font(.subheadline)
                                        .foregroundStyle(moves.loadout[slot] == nil
                                                         ? Theme.textTertiary : Theme.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    Picker("Where", selection: $referee.venue) {
                        Text("Stadium").tag(SoccerReferee.Venue.stadium)
                        Text("Your floor").tag(SoccerReferee.Venue.ar)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!door.canOfferAR)
                    if referee.venue == .stadium {
                        Picker("Stadium", selection: $referee.theme) {
                            ForEach(SoccerTheme.stadiums) { Text($0.name).tag($0) }
                        }
                    }
                    Picker("Your duck wears", selection: $referee.wearing) {
                        Text("Legs").tag(SoccerReferee.Gear.legs)
                        Text("Skates").tag(SoccerReferee.Gear.skates)
                    }
                    Picker("Match", selection: $referee.halfLength) {
                        Text("2 min").tag(60.0)
                        Text("4 min").tag(120.0)
                        Text("10 min").tag(300.0)
                    }
                    Picker("CPU team", selection: $referee.difficulty) {
                        ForEach(DuckSoccer.Difficulty.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    SectionHeading(text: "Match")
                }
                .listRowBackground(Theme.surfacePrimary)

                if GamepadInput.shared.isConnected {
                    Section {
                        Label("Controller connected", systemImage: "gamecontroller.fill")
                            .foregroundStyle(Theme.success)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
        .onAppear { if !door.canOfferAR { referee.venue = .stadium } }
        .refreshingCameraDoor($door)
    }
}

/// A press-and-hold pad. Reports true on touch-down and false on release —
/// the contract the engine's held-control model wants.
///
/// WHY THIS IS NOT A `Button` WEARING `.primaryActionMoves`, which is the style
/// every other robot-moving control in this app uses. Two reasons, and both are
/// about this control rather than about taste. A SwiftUI `Button` fires on
/// TOUCH-UP: the first version of this screen was built that way and the kick
/// registered only when the finger LEFT the glass, and then for a single engine
/// tick — a shoot button that did nothing. And `PrimaryActionStyle` draws a
/// capsule sized by its label's padding, so "SHOOT" in it is about a hundred and
/// forty points wide; two of those beside a stick do not fit on a phone, and a
/// football pad's face buttons are round because a thumb is.
///
/// SO IT TAKES EVERY RULE THAT STYLE ENCODES INSTEAD OF THE STYLE ITSELF.
/// Sixty points minimum, because the person pressing it is watching a duck.
/// Duck Orange for the pads that command the duck. The label in the one fixed
/// ink that is legible on Duck Orange in both schemes. And, most of all,
/// PRESSED DARKENS AND NEVER SCALES: the old `.scaleEffect(0.92)` is the exact
/// treatment `PrimaryActionStyle` exists to forbid, because it moves the target
/// out from under a finger already committed to it, at the moment the person is
/// least able to look at the phone.
///
/// AND IT IS REACHABLE WITHOUT A DRAG. A `Text` carrying a `DragGesture` is, to
/// VoiceOver, Switch Control and Voice Control, a piece of static text: this
/// screen's five most important controls could not be operated at all. The
/// accessibility action below presses and releases as a TOGGLE rather than
/// pulsing, because that is what the control honestly is — the engine reads a
/// held flag, and a hold has to be endable by whoever started it.
private struct HoldButton: View {

    /// What pressing it does, which is what decides how it is drawn.
    ///
    /// EVERYTHING ORANGE MOVES THE DUCK, and this enum is that rule made
    /// structural rather than remembered. It is `DriveView`'s live/quiet pair
    /// under this screen's own names.
    enum Role {
        /// It commands the duck you are driving: shoot, pass, sprint, roll.
        /// Duck Orange, and the only thing on the screen that is.
        case commands
        /// It commands nothing — it hands the stick to a different duck. A
        /// quiet surface, so the four pads that DO move your duck are the only
        /// orange in the cluster.
        case redirects
    }

    let label: String
    let size: CGFloat
    let role: Role
    /// What somebody being read to is told the press will do. Required rather
    /// than defaulted: a pad whose whole face is one word needs the sentence.
    let hint: String
    /// The name of YOUR skill on this button, under the label.
    var subtitle: String? = nil
    /// 0 when ready, up to 1 while cooling down; drawn as a ring.
    var cooldown: Double = 0
    /// The ball is in reach: the button glows.
    var ready = false
    let onChange: (Bool) -> Void

    @State private var down = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(size >= SoccerMetric.shootPad ? .headline : .caption.bold())
            if let subtitle {
                Text(subtitle).font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
            }
        }
            // Only the largest pad earns a headline. The rest are caption-bold,
            // which is what fits a word like ROULADE inside a circle a thumb
            // can cover.
            // THE WORD STOPS GROWING AT THE LARGEST NON-ACCESSIBILITY SIZE, and
            // that is the whole of how a fixed pad survives Dynamic Type. The
            // pad cannot grow with its word — five of them share a phone's width
            // with a stick — and a shrink floor alone was not enough: at the
            // accessibility sizes the caption reaches 43pt, ROULADE wants some
            // 120pt of glyphs, and below the floor SwiftUI truncates, so the
            // five most important controls on the screen read "SH…", "RO…",
            // "SP…" from about AX2 up. At xxxLarge the caption is 18pt and the
            // headline 23pt, and every word here fits its pad without touching
            // the floor. The floor stays as the net under a longer word in
            // another language. VoiceOver is not capped: `accessibilityLabel`
            // below carries the whole word at every size.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .lineLimit(1)
            .minimumScaleFactor(SoccerMetric.padTextFloor)
            .foregroundStyle(role == .commands ? DesignFixed.onAction
                                               : Theme.textPrimary)
            .frame(width: size, height: size)
            .background(fill)
            .overlay(edge)
            .overlay {
                if cooldown > 0.01 {
                    Circle().trim(from: 0, to: cooldown)
                        .stroke(Color.black.opacity(0.45),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                }
            }
            .overlay {
                if ready && cooldown <= 0.01 {
                    Circle().stroke(Color.green, lineWidth: 4).padding(-3)
                }
            }
            // The whole square, not just the glyph: a face button's target is
            // its pad. Stated rather than inherited, because the hit area of a
            // gesture on a `Text` is the one thing here worth being explicit
            // about.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down { down = true; onChange(true) }
                    }
                    .onEnded { _ in
                        down = false; onChange(false)
                    })
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(subtitle.map { "\(label), \($0)" } ?? label))
            .accessibilityValue(Text(down ? "Held" : "Released"))
            .accessibilityHint(Text(hint))
            .accessibilityAction {
                let next = !down
                down = next
                onChange(next)
            }
    }

    /// The pad, darkened while held.
    ///
    /// A BRIGHTNESS DELTA RATHER THAN A SECOND TOKEN — the same argument
    /// `PrimaryActionStyle` makes about its own fill. A press is a moment, not a
    /// colour, and a hard-coded darker orange is a value that drifts the first
    /// time Duck Orange is re-specified.
    private var fill: some View {
        Circle()
            .fill(role == .commands ? Theme.actionPrimary : Theme.surfacePrimary)
            .brightness(down ? SoccerMetric.pressDelta : 0)
    }

    /// The rim a filled shape needs so its EDGE is findable.
    ///
    /// Duck Orange is 2.30:1 on Warm Cream, below the 3:1 SC 1.4.11 asks of a
    /// control's boundary, so an orange pad borrows a hairline of orange ink in
    /// light; `Theme.actionPrimaryEdge` returns nil in dark, where the orange
    /// stands on its own at 7.12:1 and needs nothing. The quiet pad takes the
    /// separator in both schemes, because a `surfacePrimary` circle on a live
    /// 3D pitch has no ground to separate from at all.
    @ViewBuilder private var edge: some View {
        switch role {
        case .commands:
            if let rim = Theme.actionPrimaryEdge(scheme) {
                Circle().strokeBorder(rim, lineWidth: SoccerMetric.hairlineStroke)
            }
        case .redirects:
            Circle().strokeBorder(Theme.separator,
                                  lineWidth: SoccerMetric.hairlineStroke)
        }
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
    /// What the match is doing, copied out of the engine.
    ///
    /// MIRRORED FOR THE SAME REASON THE SCORE IS. `match` is a value type
    /// stepped fifty times a second and is deliberately not `@Published`; the
    /// facts the scoreboard shows are copied out of it here, exactly as
    /// `homeGoals` and `clockText` already were. This one is new because the
    /// scoreboard needs a WORD for the phase, and "Half time" was a word this
    /// screen previously only ever put inside a sentence.
    @Published private(set) var phase: DuckSoccer.Phase = .kickoff(by: .home, in: 0)
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
    @Published var difficulty: DuckSoccer.Difficulty = .normal
    /// Play stops; nothing ticks until resumed.
    @Published var isPaused = false {
        didSet { if !isPaused { accumulatorReset = true } }
    }
    /// A big word in the middle of the pitch, for a moment.
    struct Toast: Equatable {
        let id = UUID()
        let text: String
        let colour: Color
        let big: Bool
    }
    @Published var toast: Toast?
    @Published var homeShots = 0
    @Published var awayShots = 0
    /// 0 when your duck can strike, up to 1 while it recovers.
    @Published var strikeCooldown: Double = 0
    @Published var specialCooldown: Double = 0
    /// Your duck is facing the ball, close enough to strike it.
    @Published var ballInRange = false
    /// Which duck is yours right now; the pitch draws its marker from this.
    @Published private(set) var controlledID: String?
    /// When control last moved to another duck, for the marker's pulse.
    private(set) var switchedAt: CFTimeInterval = 0
    /// Your moves, resolved before kick-off.
    var moves: DuckSoccer.Moves = .standard
    var customClips: [SoccerLoadout.Slot: DuckIntentClip] = [:]
    var hasSpecial: Bool {
        moves.special != nil || wearing.capabilities.canRoll
    }
    private var accumulatorReset = false
    private var toastTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "soccer.venue").flatMap(Venue.init(rawValue:)) { venue = v }
        if let g = d.string(forKey: "soccer.gear").flatMap(Gear.init(rawValue:)) { wearing = g }
        if let t = d.string(forKey: "soccer.theme"),
           let found = SoccerTheme.stadiums.first(where: { $0.name == t }) { theme = found }
        if d.double(forKey: "soccer.half") > 0 { halfLength = d.double(forKey: "soccer.half") }
        if let x = d.string(forKey: "soccer.difficulty").flatMap(DuckSoccer.Difficulty.init(rawValue:)) {
            difficulty = x
        }
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(venue.rawValue, forKey: "soccer.venue")
        d.set(wearing.rawValue, forKey: "soccer.gear")
        d.set(theme.name, forKey: "soccer.theme")
        d.set(halfLength, forKey: "soccer.half")
        d.set(difficulty.rawValue, forKey: "soccer.difficulty")
    }

    func show(_ text: String, colour: Color = .white, big: Bool = false, for seconds: Double = 1.6) {
        let t = Toast(text: text, colour: colour, big: big)
        toast = t
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            if !Task.isCancelled, toast == t { toast = nil }
        }
    }

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

    /// PRACTICE: when a drill is chosen, the pitch runs it instead of a match.
    @Published var drill: SoccerPractice.Drill?
    private(set) var practice: SoccerPractice?
    @Published var practiceLine = ""
    @Published var practiceDone = false
    /// Stars earned this run, and the best ever per drill.
    @Published var practiceStars = 0
    static func bestStars(_ d: SoccerPractice.Drill) -> Int {
        UserDefaults.standard.integer(forKey: "soccer.practice.\(d.rawValue)")
    }
    /// What the pitch draws for the drill: cones, rings, the finish, the lit half.
    var drillProps: [SoccerPractice.Prop] { practice?.props ?? [] }
    var litCorner: ClosedRange<Double>? { practice?.litCorner }
    /// Changes whenever the drill's props change, so the pitch redraws them.
    var drillSignature: String {
        guard let p = practice else { return "" }
        return "\(p.drill.rawValue)-\(p.attempt)-" + p.props.map { $0.done ? "1" : "0" }.joined()
    }

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
        practiceDone = false
        practiceStars = 0
        if let drill {
            let p = SoccerPractice(drill, capabilities: wearing.capabilities, moves: moves)
            practice = p
            match = p.match
            practiceLine = p.progress
            isOver = false
            isPaused = false
            controlledID = match.controlled
            switchedAt = CACurrentMediaTime()
            phase = match.phase
            show(drill.title)
            return
        }
        practice = nil
        match = DuckSoccer.Match(capabilities: wearing.capabilities,
                                 halfLength: halfLength)
        match.moves[.home] = moves
        match.difficulty = difficulty
        homeShots = 0; awayShots = 0
        isPaused = false
        controlledID = match.controlled
        switchedAt = CACurrentMediaTime()
        record = DuckSoccerMatch(participantRRNs: Self.rrns, isPractice: true)
        record.append(.kickoff(atMs: Self.nowMs()))
        isOver = false
        homeGoals = 0; awayGoals = 0
        phase = match.phase
        refreshChain()
        status = ""
        show("Kick off")
    }

    /// Advance the match by however much render time has passed, in exact
    /// 50 Hz engine ticks.
    func tick(dt: Double) {
        guard isPlaced, !isOver, !isPaused else { return }
        if accumulatorReset { accumulator = 0; accumulatorReset = false }
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
        // THE MARKER FOLLOWS CONTROL, and says so when it moves: a pulse on
        // the pitch and a tap in the hand.
        if match.controlled != controlledID {
            controlledID = match.controlled
            switchedAt = CACurrentMediaTime()
            UISelectionFeedbackGenerator().selectionChanged()
        }
        let step = 1.0 / 50.0
        accumulator += min(dt, 0.25)
        if var p = practice {
            while accumulator >= step {
                accumulator -= step
                if let outcome = p.advance(dt: step, control: control) {
                    switch outcome {
                    case .success(let words):
                        show(words, colour: .yellow, big: true, for: 1.6)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    case .miss(let words):
                        show(words, colour: .white, for: 1.6)
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    case .finished:
                        break
                    }
                }
            }
            practice = p
            match = p.match
            practiceLine = p.progress
            phase = match.phase
            if p.isFinished, !practiceDone {
                practiceDone = true
                practiceLine = p.summary
                practiceStars = p.stars
                let key = "soccer.practice.\(p.drill.rawValue)"
                if p.stars > UserDefaults.standard.integer(forKey: key) {
                    UserDefaults.standard.set(p.stars, forKey: key)
                }
            }
            updateCooldowns()
            return
        }
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
                if team == .home {
                    show("GOAL!", colour: .yellow, big: true, for: 2.6)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    show("CPU scores", colour: .teal, for: 2.2)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            case .halfTime:
                show("Half time", for: 2.4)
            case .fullTime:
                record.append(.finalWhistle(atMs: Self.nowMs()))
                refreshChain()
                isOver = true
                status = finalWords()
            case .whistle:
                status = ""
            case .kick(let by):
                if by.hasPrefix("home") { homeShots += 1 } else { awayShots += 1 }
                if by == match.controlled {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            case .roll(let by):
                if by == match.controlled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }

        updateCooldowns()
        homeGoals = match.score[.home] ?? 0
        awayGoals = match.score[.away] ?? 0
        phase = match.phase
        let seconds = Int(match.clock)
        clockText = "H\(match.half) \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    /// The button rings and the in-reach glow, from your duck's state.
    private func updateCooldowns() {
        if let me = match.players.first(where: { $0.id == match.controlled }) {
            let recovery = max(match.capabilities.kickCooldown, 0.001)
            let strike = min(me.kickRecovery / recovery, 1)
            if abs(strike - strikeCooldown) > 0.02 { strikeCooldown = strike }
            let special = min(me.rollRecovery / 2.0, 1)
            if abs(special - specialCooldown) > 0.02 { specialCooldown = special }
            let toBall = match.ball.position - me.position
            let reach = toBall.length <= match.capabilities.kickRange * 1.6
                && abs(DuckSoccer.angleDelta(from: me.heading, to: toBall.heading)) < 1.1
            if reach != ballInRange { ballInRange = reach }
        }
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
///
/// SHARED WITH BOW BRIDGE, GOLF AND SLALOM: one stick, one behaviour, one place
/// to fix it. It was private only because nothing else needed it yet — which
/// also means everything below reaches four screens, so nothing here changes
/// what the stick REPORTS. The clamp, the divisor and the two axes are the ones
/// this view shipped with.
///
/// THE KNOB IS DUCK ORANGE AND THUMB-SIZED. Orange because everything orange on
/// this screen moves the duck and the stick is the thing that moves it most;
/// fifty-two points because that is the disc four screens shipped with and a
/// thumb aims at it. A first pass drew it as a `JointNode`, sixteen points at
/// rest, on the argument that the person is the load — a nice reading that put
/// a mark a third the old size at the centre of the primary movement control
/// on four screens, three of them unreviewed. The ring it travels inside is
/// drawn, so the deflection the mapping treats as full is a thing you can see
/// rather than a divisor hidden in a gesture.
///
/// IT SIZES ITSELF. Three callers framed it and one — Bow Bridge — did not,
/// which left that screen's stick at whatever the knob's intrinsic size
/// happened to be. `side` is the one door now: pass one to fit a tighter deck,
/// or take the default and get the same stick Duck soccer draws.
///
/// IT USED TO BE A YELLOW DISC ON A BLUR. Both halves of that were outside the
/// system: `.yellow` is not a palette value and nothing has ever measured it
/// against anything, and `.ultraThinMaterial` over a live pitch means the well
/// and the knob had whatever contrast the grass gave them that frame.
///
/// DRIVABLE WITHOUT A DRAG. A stick that answers only to `DragGesture` is a
/// duck nobody using VoiceOver, Switch Control or Voice Control can move at
/// all — on a screen whose whole point is moving it. Swipe up and down for
/// forward and back, named actions for left, right and centre.
struct JoystickView: View {
    /// The stick's numbers, its own because the stick is shared: they were in
    /// `SoccerMetric` when this was Duck soccer's private control, and a number
    /// four screens depend on belongs to the thing they share.
    enum Stick {
        /// The well's side, and what every caller gets unless it asks.
        static let side: CGFloat = 130
        /// The knob. The disc the four screens shipped with, restored after a
        /// pass shrank it to a sixteen-point joint node.
        static let knob: CGFloat = 52
        /// How far the knob's centre travels at full deflection, and the divisor
        /// the drag is measured against — ONE number, so the ring on the glass
        /// and the mapping underneath it cannot disagree.
        ///
        /// LEFT AT THE VALUE IT SHIPPED WITH, deliberately. `ThumbPad` derives
        /// its travel from its own radius; this stick is handed a different side
        /// by different screens, and deriving it would change how far a thumb
        /// has to move to ask for full speed on every one of them. That is a
        /// change to what the control reports, which this pass does not make.
        static let travel: CGFloat = 42
        /// One step of the adjustable action: a quarter of full deflection,
        /// which is `ThumbPad`'s step and gives four presses from centre to rim.
        static let step: CGFloat = travel / 4
    }

    var side: CGFloat = Stick.side
    let onChange: (DuckSoccer.Vec2) -> Void
    @State private var offset: CGSize = .zero
    @Environment(\.colorScheme) private var scheme

    /// Whether the knob is against the travel ring, so the rigid tap fires once
    /// on arrival rather than on every frame of a thumb held at the edge.
    ///
    /// THE FLAG IS THE WHOLE FEATURE. `DragGesture` delivers a change per frame,
    /// so firing on the condition alone would buzz sixty times a second for as
    /// long as somebody asked for full speed — which is not a signal, it is the
    /// phone vibrating, and the first thing anybody would do about it is stop
    /// noticing haptics in this app entirely. `ThumbPad` in `DriveView` carries
    /// the same flag for the same reason; this is that behaviour on the other
    /// four screens.
    @State private var atLimit = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.surfaceInteractive)
            Circle().strokeBorder(Theme.separator,
                                  lineWidth: SoccerMetric.hairlineStroke)
            Circle()
                .strokeBorder(Theme.separator,
                              lineWidth: SoccerMetric.hairlineStroke)
                .frame(width: Stick.travel * 2, height: Stick.travel * 2)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.title3)
                .foregroundStyle(Theme.textTertiary)
            knob
                .offset(offset)
        }
        .frame(width: side, height: side)
        // THE ENGINE IS WARMED BY THE STICK, NOT BY THE SCREEN AROUND IT.
        // Bow Bridge, Golf and Slalom each call `Haptic.prepare()` in their own
        // `.task`; Duck soccer did not, so the same control gave a late first
        // tap on one of the four screens it is drawn on and a prompt one on the
        // other three — the kind of inconsistency that reads as the phone being
        // unreliable rather than as a screen missing a line. A shared control
        // that produces haptics should be the thing that prepares for them.
        // `prepare()` is idempotent, so the three screens that already ask lose
        // nothing by asking twice.
        .task { Haptic.prepare() }
        .gesture(
            DragGesture()
                .onChanged { value in
                    settle(width: value.translation.width,
                           height: value.translation.height)
                }
                .onEnded { _ in
                    offset = .zero
                    atLimit = false
                    onChange(.zero)
                })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stick"))
        .accessibilityValue(Text(spoken))
        .accessibilityHint(Text("Drives the duck you are controlling. Up is toward the CPU goal."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            // Screen y runs down and the pitch's forward runs up, which is why
            // "increment" subtracts: it is the same flip the drag makes.
            case .increment: settle(width: offset.width,
                                    height: offset.height - Stick.step)
            case .decrement: settle(width: offset.width,
                                    height: offset.height + Stick.step)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text("Left")) {
            settle(width: offset.width - Stick.step, height: offset.height)
        }
        .accessibilityAction(named: Text("Right")) {
            settle(width: offset.width + Stick.step, height: offset.height)
        }
        // LETTING GO IS THE SAFE DEFAULT AND IT HAS TO BE REACHABLE. A drag
        // springs back when the thumb leaves the glass; an adjustable action
        // has no thumb to leave, so a duck nudged forward would keep walking
        // until it was nudged back. This is the release.
        .accessibilityAction(named: Text("Centre")) {
            offset = .zero
            atLimit = false
            onChange(.zero)
        }
    }

    /// The disc under the thumb: Duck Orange, with the rim an orange fill needs
    /// in light so its edge is findable on a ground it is only 2.30:1 against —
    /// the same pair `HoldButton` and `PrimaryActionStyle` draw.
    private var knob: some View {
        Circle()
            .fill(Theme.actionPrimary)
            .overlay {
                if let rim = Theme.actionPrimaryEdge(scheme) {
                    Circle().strokeBorder(rim, lineWidth: SoccerMetric.hairlineStroke)
                }
            }
            .frame(width: Stick.knob, height: Stick.knob)
    }

    /// Clamp a proposed offset into the travel circle, keep it, and report it.
    ///
    /// ONE PLACE, SO THE GLASS AND THE ENGINE CANNOT DISAGREE. The drag and the
    /// three accessibility actions all arrive here, which is what makes the ring
    /// drawn above the boundary the mapping actually uses.
    ///
    /// AND THEREFORE THE ONE PLACE THAT KNOWS THE STICK HAS HIT THE RING. A
    /// STICK AT ITS LIMIT IS A WALL, AND `.rigid` IS WHAT A WALL FEELS LIKE:
    /// pushing further does nothing, the duck is already going as fast as it
    /// will go, and the person is watching the pitch rather than the pad — so
    /// the only channel left for "that is all of it" is the one under their
    /// thumb. Because the clamp lives here, so does the tap, and the swipe
    /// actions get it as well as the drag. Once, on arrival: `atLimit` is what
    /// makes it an event rather than a vibration.
    ///
    /// `@MainActor` BECAUSE THE TAPTIC ENGINE IS UIKit'S AND UIKit IS. Every
    /// caller is a gesture or accessibility closure written inside `body`, so
    /// each already runs there; saying so is what lets a `Haptic` call sit in a
    /// method rather than only inside those closures. `DriveView.press` carries
    /// the annotation for the same reason.
    @MainActor
    private func settle(width: CGFloat, height: CGFloat) {
        var dx = width, dy = height
        let limit = Stick.travel
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        // Measured from the RAW length rather than from the clamped offset: the
        // clamp puts every pinned knob at exactly `limit`, so asking the
        // question afterwards is asking whether two divisions came out equal.
        // This is the same number the clamp itself tests, one line down.
        let now = length >= limit
        if now, !atLimit { Haptic.stickAtLimit() }
        atLimit = now
        if length > limit { dx *= limit / length; dy *= limit / length }
        offset = CGSize(width: dx, height: dy)
        onChange(vector(for: offset))
    }

    /// Screen up = pitch +x; screen right = pitch −y.
    private func vector(for offset: CGSize) -> DuckSoccer.Vec2 {
        DuckSoccer.Vec2(Double(-offset.height / Stick.travel),
                        Double(-offset.width / Stick.travel))
    }

    /// What VoiceOver says the stick is doing. A drag pad reports nothing on its
    /// own, and "Stick" alone does not say which way it is pushed.
    private var spoken: String {
        let pushed = vector(for: offset)
        if pushed.x == 0 && pushed.y == 0 { return "centred" }
        var parts: [String] = []
        if pushed.x != 0 {
            parts.append(String(format: "%.0f%% %@", abs(pushed.x) * 100,
                                pushed.x > 0 ? "forward" : "back"))
        }
        if pushed.y != 0 {
            parts.append(String(format: "%.0f%% %@", abs(pushed.y) * 100,
                                pushed.y > 0 ? "left" : "right"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - the AR container

private struct SoccerContainer: UIViewRepresentable {
    @ObservedObject var referee: SoccerReferee
    @Binding var startRequested: Bool
    @Binding var resetRequested: Bool

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
        if resetRequested {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                resetRequested = false
                coordinator.teardown()
            }
        }
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
    /// Every duck's ring, and what it last showed, so a ring is only
    /// re-coloured when its state changes.
    private var rings: [String: ModelEntity] = [:]
    private var ringState: [String: Int] = [:]
    /// The arrow over YOUR duck: bright, bobbing, and it follows every switch.
    private var marker: ModelEntity?
    private var gesturesAdded = false
    /// The drill's cones, rings, finish and lit half, redrawn when they change.
    private var drillLayer: Entity?
    private var drillShown = ""

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

        if !gesturesAdded {
            gesturesAdded = true
            view.addGestureRecognizer(UIPanGestureRecognizer(
                target: self, action: #selector(orbit)))
            view.addGestureRecognizer(UIPinchGestureRecognizer(
                target: self, action: #selector(zoom)))
        }

        referee.kickoff()
        buildPitch(on: anchor)
        buildStadiumDressing(on: anchor)
        view.scene.addAnchor(anchor)
        pitch = anchor
        referee.isPlaced = true
        lastTick = CACurrentMediaTime()
        // kicked off before the build, so the ducks are the drill's
    }

    /// A failed session — camera access denied is the common one — says so
    /// instead of leaving a black view under "tap to place".
    func session(_ session: ARSession, didFailWithError error: Error) {
        let code = (error as NSError).code
        referee?.status = code == ARError.Code.cameraUnauthorized.rawValue
            ? "Camera access is switched off for Microduck Studio — allow it in Settings, or play in the Stadium."
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

    /// Take the pitch down so the lobby can start a different match: another
    /// venue, other gear (other ducks), other moves.
    func teardown() {
        if let pitch { view?.scene.removeAnchor(pitch) }
        if venue == .ar { view?.session.pause() }
        pitch = nil; ball = nil; ducks = [:]; rings = [:]; ringState = [:]; marker = nil
        drillLayer = nil; drillShown = ""
        walkPhase = [:]; kickStart = [:]; lastDrawn = [:]; rollAnchor = [:]
        wheelSpin = [:]; skatePhase = [:]; crouchStart = [:]
        cameraEntity = nil
        view?.cameraMode = .nonAR
        view?.environment.background = .color(.black)
        referee?.isPlaced = false
        referee?.isOver = false
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
        referee.kickoff()
        buildPitch(on: anchor)
        view.scene.addAnchor(anchor)
        pitch = anchor
        referee.isPlaced = true
        lastTick = CACurrentMediaTime()
        // kicked off before the build, so the ducks are the drill's
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
        // A PROPER PITCH: every marking a real one has, scaled from 105 m and
        // fitted around this game's goals (the kit's `markings()`).
        let marks = spec.markings()
        for (a, b) in marks.lines {
            let dx = Float(b.x - a.x), dy = Float(b.y - a.y)
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0.0005 else { continue }
            let stripe = ModelEntity(mesh: .generateBox(width: length + 0.004, height: 0.002, depth: 0.006),
                                     materials: [line])
            stripe.position = SIMD3<Float>(Float(a.x + b.x) / 2, 0.001, -Float(a.y + b.y) / 2)
            stripe.orientation = simd_quatf(angle: atan2(-dy, dx) * -1, axis: SIMD3<Float>(0, 1, 0))
            anchor.addChild(stripe)
        }
        for spot in marks.spots {
            let dot = ModelEntity(mesh: .generatePlane(width: 0.018, depth: 0.018, cornerRadius: 0.009),
                                  materials: [line])
            dot.position = SIMD3<Float>(Float(spot.x), 0.0015, -Float(spot.y))
            anchor.addChild(dot)
        }
        for corner in marks.corners {
            let pole = ModelEntity(mesh: .generateBox(width: 0.004, height: 0.10, depth: 0.004),
                                   materials: [UnlitMaterial(color: .white)])
            pole.position = SIMD3<Float>(Float(corner.x), 0.05, -Float(corner.y))
            let flag = ModelEntity(mesh: .generateBox(width: 0.028, height: 0.02, depth: 0.002),
                                   materials: [UnlitMaterial(color: theme.awayGoal)])
            flag.position = SIMD3<Float>(Float(corner.x) + (corner.x > 0 ? -0.016 : 0.016), 0.09,
                                         -Float(corner.y))
            anchor.addChild(pole)
            anchor.addChild(flag)
        }

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
            // A REAL-LOOKING GOAL: back, sides and roof of netting, and the
            // frame's back posts, rather than one tinted block.
            let depth = Float(spec.goalDepth)
            let out: Float = x > 0 ? 1 : -1
            var mesh = UnlitMaterial(color: UIColor(white: 1, alpha: 0.28))
            mesh.blending = .transparent(opacity: 0.28)
            let back = ModelEntity(mesh: .generateBox(width: 0.002, height: height, depth: mouthHalf * 2),
                                   materials: [mesh])
            back.position = SIMD3<Float>(Float(x) + out * depth, height / 2, 0)
            anchor.addChild(back)
            let roof = ModelEntity(mesh: .generateBox(width: depth, height: 0.002, depth: mouthHalf * 2),
                                   materials: [mesh])
            roof.position = SIMD3<Float>(Float(x) + out * depth / 2, height, 0)
            anchor.addChild(roof)
            for z in [-mouthHalf, mouthHalf] {
                let side = ModelEntity(mesh: .generateBox(width: depth, height: height, depth: 0.002),
                                       materials: [mesh])
                side.position = SIMD3<Float>(Float(x) + out * depth / 2, height / 2, z)
                anchor.addChild(side)
                let backPost = ModelEntity(mesh: .generateBox(width: 0.008, height: height, depth: 0.008),
                                           materials: [frame])
                backPost.position = SIMD3<Float>(Float(x) + out * depth, height / 2, z)
                anchor.addChild(backPost)
            }
            // Tinted strip on the goal line, the team's colour.
            let tintBar = ModelEntity(mesh: .generateBox(width: 0.006, height: 0.003, depth: mouthHalf * 2),
                                      materials: [net])
            tintBar.position = SIMD3<Float>(Float(x), 0.002, 0)
            anchor.addChild(tintBar)
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

            let tint: UIColor = player.team == .home ? .systemYellow : .systemTeal
            let ring = ModelEntity(
                mesh: .generatePlane(width: 0.16, depth: 0.16, cornerRadius: 0.08),
                materials: [UnlitMaterial(color: tint.withAlphaComponent(0.3))])
            ring.position = SIMD3<Float>(0, 0.003, 0)
            duck.addChild(ring)
            rings[player.id] = ring
        }

        // THE "YOU" MARKER: a bright diamond over your duck's head. It is its
        // own entity on the pitch, not a child of any duck, so a switch moves
        // it rather than leaving it behind.
        let diamond = ModelEntity(mesh: .generateBox(size: 0.045),
                                  materials: [UnlitMaterial(color: .systemYellow)])
        diamond.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1))
        anchor.addChild(diamond)
        marker = diamond
        ringState = [:]

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
            let strike = yours(player.lastKickWasPass ? .pass : .shoot, player) ?? kickLeft
            if let kick = strike, let start = kickStart[player.id] {
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
    /// Make your duck unmistakable: a bright, pulsing ring under it (green
    /// when the ball is in reach), a bobbing diamond over its head that pops
    /// when control switches, and team-mates' rings dimmed.
    private func drawYou(match: DuckSoccer.Match) {
        let now = CACurrentMediaTime()
        let sinceSwitch = now - (referee?.switchedAt ?? 0)
        let inReach = referee?.ballInRange ?? false
        for player in match.players {
            guard let ring = rings[player.id] else { continue }
            let mine = player.id == match.controlled
            let state = mine ? (inReach ? 2 : 1) : (player.team == .home ? 3 : 4)
            if ringState[player.id] != state {
                ringState[player.id] = state
                let colour: UIColor
                switch state {
                case 1: colour = UIColor.systemYellow
                case 2: colour = UIColor.systemGreen
                case 3: colour = UIColor.systemYellow.withAlphaComponent(0.22)
                default: colour = UIColor.systemTeal.withAlphaComponent(0.3)
                }
                ring.model?.materials = [UnlitMaterial(color: colour)]
            }
            if mine {
                // A slow breath, and a big pop right after a switch.
                let pop = sinceSwitch < 0.5 ? Float(1 - sinceSwitch / 0.5) * 1.2 : 0
                let breathe = Float(0.12 * sin(now * 5))
                ring.scale = SIMD3<Float>(repeating: 1.7 + breathe + pop)
            } else {
                ring.scale = SIMD3<Float>(repeating: 1)
            }
        }
        if let marker, let me = match.players.first(where: { $0.id == match.controlled }) {
            marker.isEnabled = true
            let bob = Float(0.015 * sin(now * 4))
            let pop = sinceSwitch < 0.4 ? Float(1 - sinceSwitch / 0.4) * 1.5 : 0
            marker.position = SIMD3<Float>(Float(me.position.x), 0.36 + bob,
                                           Float(-me.position.y))
            marker.scale = SIMD3<Float>(repeating: 1 + pop)
        } else {
            marker?.isEnabled = false
        }
    }

    /// Practice props: orange cones, target rings, a finish line, and the
    /// lit half of the goal.
    private func drawDrill() {
        guard let referee, let pitch, referee.drillSignature != drillShown else { return }
        drillShown = referee.drillSignature
        drillLayer?.removeFromParent()
        let layer = Entity()
        for prop in referee.drillProps {
            let at = SIMD3<Float>(Float(prop.position.x), 0, -Float(prop.position.y))
            switch prop.kind {
            case .cone:
                let cone = ModelEntity(mesh: .generateBox(width: 0.022, height: 0.05, depth: 0.022,
                                                          cornerRadius: 0.006),
                                       materials: [UnlitMaterial(color: prop.done
                                            ? UIColor.systemGreen : UIColor.systemOrange)])
                cone.position = at + SIMD3<Float>(0, 0.025, 0)
                layer.addChild(cone)
            case .ring:
                let r = Float(prop.radius)
                let disc = ModelEntity(mesh: .generatePlane(width: r * 2, depth: r * 2, cornerRadius: r),
                                       materials: [UnlitMaterial(color: UIColor.systemYellow
                                            .withAlphaComponent(0.35))])
                disc.position = at + SIMD3<Float>(0, 0.002, 0)
                layer.addChild(disc)
            case .finish:
                let bar = ModelEntity(mesh: .generateBox(width: 0.012, height: 0.002,
                                                         depth: Float(prop.radius) * 2),
                                      materials: [UnlitMaterial(color: .systemYellow)])
                bar.position = at + SIMD3<Float>(0, 0.002, 0)
                layer.addChild(bar)
            }
        }
        if let lit = referee.litCorner {
            let spec = DuckSoccer.Pitch.livingRoom
            let width = Float(lit.upperBound - lit.lowerBound)
            let glow = ModelEntity(mesh: .generateBox(width: 0.004, height: 0.2, depth: width),
                                   materials: [UnlitMaterial(color: UIColor.systemYellow
                                        .withAlphaComponent(0.45))])
            glow.position = SIMD3<Float>(Float(spec.halfLength) + 0.01, 0.1,
                                         -Float(lit.lowerBound + lit.upperBound) / 2)
            layer.addChild(glow)
        }
        pitch.addChild(layer)
        drillLayer = layer
    }

    /// Your clip for this moment, when your team has one.
    private func yours(_ slot: SoccerLoadout.Slot, _ player: DuckSoccer.Player) -> DuckIntentClip? {
        player.team == .home ? referee?.customClips[slot] : nil
    }

    private func draw(match: DuckSoccer.Match, dt: Double) {
        if let ball {
            ball.position = SIMD3<Float>(Float(match.ball.position.x), 0.02,
                                         Float(-match.ball.position.y))
        }
        guard let walk, let stand else { return }
        let clipSpeed = max(walk.deltaX / (Double(walk.frames.count) / walk.hz), 0.01)
        drawYou(match: match)
        drawDrill()

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

            // YOUR SPECIAL ON SKATES: the engine carries the duck the clip's
            // distance; the clip's joints are what it does on the way.
            if duck.variant == .rollers, player.motion == .rolling,
               let mine = yours(.special, player), let elapsed = player.rollElapsed {
                duck.apply(jointAngles: mine.pose(at: elapsed).jointAngles)
                continue
            }
            if duck.variant == .rollers {
                drawSkater(duck, player: player, match: match, signed: signed,
                           travelled: travelled, dt: dt, celebration: celebration)
                continue
            }

            // A goal celebration outranks the engine's motion state. YOUR
            // team's scorer performs the motion you authored in Microduck Studio,
            // if you chose one; everyone else — and your team, when you have
            // not — rolls Pollen's own roulade. An authored move is a list of
            // poses smoothstepped between keyframes, so it plays through
            // DuckMove.pose(at:), the same arithmetic the editor previews.
            if let celebration, celebration.id == player.id {
                if let mine = yours(.celebrate, player) {
                    let clipPose = mine.pose(at: celebration.at.truncatingRemainder(
                        dividingBy: max(mine.duration, 0.1)))
                    duck.apply(jointAngles: clipPose.jointAngles)
                    walkPhase[player.id] = 0
                    continue
                }
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
                if let roll = yours(.special, player) ?? roulade, let elapsed = player.rollElapsed {
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
                let strike = yours(player.lastKickWasPass ? .pass : .shoot, player) ?? kickLeft
                if let kick = strike, let start = kickStart[player.id] {
                    duck.apply(jointAngles: kick.pose(at: CACurrentMediaTime() - start)
                        .jointAngles)
                }
            case .walking:
                if !match.capabilities.canRoll {
                    // SKATES GLIDE. No skating gait is recorded in the
                    // trajectory set yet, and a stepping walk under a duck
                    // moving at four times walking speed reads as a cartoon —
                    // the settled stand pose gliding is closer to what
                    // roller actually does.
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

// MARK: - the numbers this screen writes down for itself

/// Dimensions that are layout decisions rather than facts, gathered so the next
/// person can see which ones are load-bearing.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST, which is the line `Theme` draws and
/// this file stays behind: a ratio is a fact about two colours and lives in
/// `Palette`, where `swift test` runs the WCAG formula over it on every build.
/// How wide to let a scoreboard grow is not a fact about anything, it is a
/// judgement about a phone.
private enum SoccerMetric {
    /// The scoreboard, the placement note and the controller legend. A card, on
    /// the scale — the same step `SlalomView` and `DuckGolfView` give their HUD
    /// panels, so the three Lab games have one corner between them.
    static let panel = Palette.Radius.card

    /// The setup sheet's own corner.
    static let sheet = Palette.Radius.sheet

    /// 60pt — the floor for anything that MOVES A DUCK, by reference to the
    /// app's one copy. `PrimaryActionStyle` draws a capsule and a football
    /// pad's face buttons are round, so this screen takes the number rather
    /// than the style — but it takes it by name, so if the floor ever moves it
    /// moves once.
    ///
    /// The reason for sixty rather than the HIG's forty-four is worth repeating
    /// here, because it is what justifies the extra points: the person pressing
    /// SHOOT is looking at the duck, the phone is in one hand, and a miss does
    /// not produce a wrong screen — it produces a duck that did not shoot.
    static let movingTarget = DesignMetric.movingTarget

    /// The face pads, every one of them the floor plus a step on the spacing
    /// scale. Sizes are the hierarchy now that all five share one colour:
    /// SHOOT is the biggest thing on the screen, ROULADE next because it is the
    /// signature move, then PASS, then the two that only change how you move.
    static let switchPad: CGFloat = movingTarget
    static let sprintPad: CGFloat = movingTarget
    static let passPad: CGFloat = movingTarget + Theme.spacing(.hairline)
    static let specialPad: CGFloat = movingTarget + Theme.spacing(.tight)
    static let shootPad: CGFloat = movingTarget + Theme.spacing(.standard)

    /// How far a word inside a pad may shrink before it would rather clip.
    /// Held in reserve rather than relied on: `HoldButton` caps its word at
    /// `.xxxLarge`, where every label here fits without shrinking, so this only
    /// bites on a longer word in another language.
    static let padTextFloor: CGFloat = 0.6

    /// How wide the scoreboard may grow. Wide enough for a telemetry label
    /// beside its value at the default text size, narrow enough that it stays a
    /// card in a corner rather than a lid over the pitch.
    static let scoreboardWidth: CGFloat = 300

    /// A hairline STROKE, the app's one.
    static let hairlineStroke = DesignMetric.hairlineStroke

    /// How far a press darkens a pad: the delta `PrimaryActionStyle` uses, by
    /// name, so a press feels like one press everywhere in the app.
    static let pressDelta = DesignMetric.pressDelta
}

