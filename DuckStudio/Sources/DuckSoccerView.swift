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
                    placementNote
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
        // NO GOAL-CELEBRATION PICKER, and no empty `.toolbar` left standing
        // where it was. It offered one option and told people to "author a
        // motion in Microduck Studio and open the .duckmove here to celebrate
        // with it" — which this build cannot do: `CelebrationStore.importFile(at:)`
        // has no caller anywhere, no .duckmove is bundled, and `LibraryModel`
        // routes that extension to drafts. So `imported` is permanently empty
        // and the sentence was instructions for a door that does not exist. A
        // setting that cannot be set is not a placement problem; it comes out
        // until the import is real. `CelebrationStore` stays: its readers are
        // correct code with a nil input, and the roulade still plays.
        .alert("Not exportable", isPresented: $referee.showingRefusal) {
            Button("I see", role: .cancel) {}
        } message: { Text(referee.refusalExplanation) }
    }

    /// The match, drawn the way this design system draws a match: one word for
    /// what the game is doing, one row per number that changes, and the
    /// referee's own sentence under them.
    ///
    /// EVERY NUMBER HERE MOVES, WHICH IS WHY EVERY ONE IS A `TelemetryRow`. The
    /// score, the clock and the chain head are the three things on this screen a
    /// person watches change, and that component's whole claim is exactly that
    /// distinction — tabular figures for a value, SF for the label that names
    /// it, and the pair stacked rather than truncated when the text is enlarged.
    /// The old scoreboard set "YOU 3" and "4 CPU" as one monospaced title with
    /// the team carried by a raw `.yellow` and a raw `.cyan`: a colour doing a
    /// word's job, between the only two teams on the pitch, for a distinction
    /// roughly one man in twelve cannot make (SC 1.4.1). The words "You" and
    /// "CPU" are now the labels, and no colour is asked to say which is which.
    ///
    /// THE CHAIN HEAD IS TELEMETRY AND NOT DECORATION. It changes on every goal,
    /// which is the entire reason it is on the glass — the record is being
    /// written while you play — so it is a value beside a label like the rest.
    ///
    /// AN OPAQUE CARD OVER A LIVE PICTURE, the same decision `DriveView`,
    /// `SlalomView` and `DuckGolfView` all make about their readouts: on
    /// `.ultraThinMaterial` the contrast of every word here was whatever the
    /// grass, the carpet or a duck happened to be that frame, which is to say it
    /// was never checked by anything. `surfacePrimary` is one of the four
    /// grounds `PaletteTests` proves every text token against at 4.5:1.
    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            // A WORD, NOT A `StateBadge`. A match phase is not a `RobotState`:
            // the badge would have spoken "You score, Active" and "Half time,
            // Idle" — a robot's four-word vocabulary bolted onto football — and
            // it would have been Duck Orange for the whole of play, on the one
            // screen that has just declared orange means "moves your duck". The
            // phase is carried by the word alone, in the ink every other label
            // here uses.
            Text(matchWord)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .top, spacing: Theme.spacing(.standard)) {
                TelemetryRow(label: "You", value: "\(referee.homeGoals)")
                TelemetryRow(label: "CPU", value: "\(referee.awayGoals)")
            }
            TelemetryRow(label: "Match clock", value: referee.clockText)
            TelemetryRow(label: "Chain head", value: referee.chainHeadPrefix)
            Text(referee.status)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacing(.snug))
        .frame(maxWidth: SoccerMetric.scoreboardWidth, alignment: .leading)
        .background(Theme.surfacePrimary, in: panel)
        .overlay(panel.strokeBorder(Theme.separator,
                                    lineWidth: SoccerMetric.hairlineStroke))
        .padding(.top, Theme.spacing(.tight))
    }

    /// The one sentence on screen before a pitch exists — the instruction for
    /// the only thing a person can do here, so it gets a real ground rather than
    /// a blur over a camera feed.
    private var placementNote: some View {
        Text(referee.status)
            .font(.footnote)
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.spacing(.snug))
            .background(Theme.surfacePrimary, in: panel)
            .overlay(panel.strokeBorder(Theme.separator,
                                        lineWidth: SoccerMetric.hairlineStroke))
            .padding(.horizontal, Theme.spacing(.standard))
            .padding(.bottom, Theme.spacing(.loose))
            .accessibilityLabel(Text("Pitch placement"))
            .accessibilityValue(Text(referee.status))
    }

    private var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(SoccerMetric.panel),
                         style: .continuous)
    }

    /// What the match is doing, in a word.
    ///
    /// THE TEAM IS IN THE WORD, which is where the yellow and the cyan went. A
    /// goal and a full-time whistle both belong to somebody, and "You score" is
    /// a readout a person can hear as well as glance at; a coloured numeral was
    /// neither. The kickoff phase names its team too, because whose kickoff it
    /// is decides whether your stick is about to do anything.
    private var matchWord: String {
        guard referee.isPlaced else { return "Placing" }
        switch referee.phase {
        case .kickoff(let team, _):
            return team == .home ? "Your kick off" : "CPU kick off"
        case .playing:
            return "Playing"
        case .goal(let team, _, _):
            return team == .home ? "You score" : "CPU score"
        case .halfTime:
            return "Half time"
        case .fullTime:
            return finalWord
        }
    }

    /// Who won, in three words or fewer. The long version is in
    /// `referee.status` underneath; this is the one a glance gets.
    private var finalWord: String {
        if referee.homeGoals > referee.awayGoals { return "You win" }
        if referee.awayGoals > referee.homeGoals { return "CPU win" }
        return "Full time draw"
    }

    /// A game controller, because that is what a football game is played on:
    /// stick on the left, the face pads on the right. Every hold button uses a
    /// zero-distance drag gesture, NOT a Button — a SwiftUI Button fires on
    /// TOUCH-UP, so the first version's kick registered only when the finger
    /// left the screen and then for a single engine tick, which played exactly
    /// like a kick button that does nothing. `HoldButton` carries the rest of
    /// that argument, and what it takes from `PrimaryActionStyle` instead.
    private var controls: some View {
        HStack(alignment: .bottom) {
            JoystickView { vector in referee.stick = vector }

            Spacer()

            if referee.isOver {
                VStack(spacing: Theme.spacing(.tight)) {
                    // NOT ORANGE, AND THAT IS THE POINT OF THE RULE. Everything
                    // orange on this screen moves a duck; this one opens an
                    // alert that explains why a match of ten simulations cannot
                    // be called evidence. It keeps the stock `.bordered` shape
                    // and takes the app's tint, which `MicroduckTheme` sets to
                    // `Theme.actionSecondary` — the orange INK, at 4.52:1 on
                    // cream, because a tint sets words rather than filling a
                    // shape. `.large` is what carries it past the forty-four
                    // point floor without this file writing that number down.
                    Button("Export as evidence") { referee.attemptExport() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityHint(Text("Tries to sign this match out as evidence. A practice match refuses, and says why."))
                    // IT PUTS TEN DUCKS BACK ON THE HALFWAY LINE, so it is the
                    // sixty-point variant, exactly like "Run it again" in
                    // Slalom and "Next hole" in Golf.
                    Button("Rematch") { referee.kickoff() }
                        .buttonStyle(.primaryActionMoves)
                        .accessibilityHint(Text("Puts all ten ducks back on the halfway line and starts a new match at the same settings."))
                }
            } else if referee.gamepadConnected {
                gamepadLegend
            } else {
                thumbCluster
            }
        }
        .padding(.horizontal, Theme.spacing(.loose))
        .padding(.bottom, Theme.spacing(.loose))
    }

    /// The controller has the buttons; the screen keeps only the legend, so
    /// nothing competes with the pad in hand.
    ///
    /// A CARD RATHER THAN A BLUR, for the reason the scoreboard is: this is five
    /// button names over a moving picture, and on `.ultraThinMaterial` their
    /// contrast was the pitch's.
    private var gamepadLegend: some View {
        Label("A pass · B shoot · Y roulade/crouch · L1 switch · R2 sprint",
              systemImage: "gamecontroller.fill")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.spacing(.snug))
            .background(Theme.surfacePrimary, in: panel)
            .overlay(panel.strokeBorder(Theme.separator,
                                        lineWidth: SoccerMetric.hairlineStroke))
            .accessibilityLabel(Text("Controller buttons"))
            .accessibilityValue(Text("A passes, B shoots, Y is the roulade or crouch, L1 switches duck, R2 sprints."))
    }

    /// The FIFA cluster, thumb-shaped: SHOOT outside where the thumb rests,
    /// PASS beside it, the skill below, SPRINT above them, SWITCH on top — the
    /// L1 of a screen. ROULADE holds the prime bottom spot: it is the signature
    /// move, the measured forward roll, and it earned the thumb's resting place.
    /// (Roulade: French for "roll", and Pollen's own name for the clip.)
    ///
    /// FIVE HUES BECAME ONE, AND THE HIERARCHY IS NOW SIZE AND WORD. These pads
    /// were white, orange, cyan, yellow and purple — five sampled colours, none
    /// of them in the palette, four of them filling a shape with a value that no
    /// contrast test has ever seen. `DriveView` states the rule this screen now
    /// follows: everything orange moves the duck and nothing else is orange. So
    /// the four pads that command your duck are Duck Orange and differ by
    /// diameter, and SWITCH — which commands nothing, it hands the stick to a
    /// different duck — keeps a quiet surface. That is the same live/quiet pair
    /// `DriveView` draws across its pad, and it survives colour blindness,
    /// because the word on each pad was always doing the work.
    ///
    /// ALL FIVE CLEAR SIXTY POINTS. SWITCH was fifty and SPRINT fifty-six; the
    /// person pressing either is watching a duck, not the glass.
    private var thumbCluster: some View {
        VStack(alignment: .trailing, spacing: Theme.spacing(.tight)) {
            HoldButton(label: "SWITCH", size: SoccerMetric.switchPad,
                       role: .redirects,
                       hint: "Hands your stick to the team-mate nearest the ball.") {
                if $0 { referee.requestSwitch = true }
            }
            HoldButton(label: "SPRINT", size: SoccerMetric.sprintPad,
                       role: .commands,
                       hint: "Held, your duck moves at the top speed its gear was measured at.") {
                referee.sprintHeld = $0
            }
            HStack(spacing: Theme.spacing(.snug)) {
                HoldButton(label: "PASS", size: SoccerMetric.passPad,
                           role: .commands,
                           hint: "Held, your duck plays the ball to a team-mate.") {
                    referee.passHeld = $0
                }
                HoldButton(label: "SHOOT", size: SoccerMetric.shootPad,
                           role: .commands,
                           hint: "Held, your duck strikes the ball at the CPU goal.") {
                    referee.kickHeld = $0
                }
            }
            // On legs the roulade; on wheels Pollen's crouch-glide trick — each
            // the special move its policy set has.
            HoldButton(label: referee.wearing == .legs ? "ROULADE" : "CROUCH",
                       size: SoccerMetric.specialPad,
                       role: .commands,
                       hint: referee.wearing == .legs
                           ? "Held, your duck rolls forward — the measured roulade, faster than running."
                           : "Held, your duck drops into the recorded roller crouch.") {
                referee.specialHeld = $0
            }
        }
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

    /// EVERY CONTROL HERE IS THE STOCK ONE, which is a decision and not a
    /// shortcut. A segmented `Picker` already announces its label and its
    /// selected value, already grows with Dynamic Type, and already works under
    /// Switch Control and Voice Control; a hand-rolled row of capsules would
    /// have to be given all four back and would get one of them wrong. So the
    /// design work here is the GROUND under them — the palette's surfaces
    /// instead of the system's grey — and a caption under each switch saying
    /// what the choice will cost, which is the one thing a stock picker cannot
    /// know. A CAPTION, NOT AN ACCESSIBILITY HINT: a segmented picker is a
    /// container whose children are the segments, and a label or hint set on
    /// the container is handed down to every segment — so "Venue" would have
    /// replaced "Stadium" and "Your floor (AR)" as what each segment is called,
    /// and the hint would most likely never have been spoken at all. The
    /// visible sentence reaches everyone, VoiceOver included.
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
                        Text(refusal).font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if referee.venue == .stadium {
                        Picker("Stadium", selection: $referee.theme) {
                            ForEach(SoccerTheme.stadiums) { theme in
                                Text(theme.name).tag(theme)
                            }
                        }
                        Text("A whole palette, not an accent — pastel sherbet, the grid-sunset nineties, bowling-alley carpet, Saturday cartoon.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("The camera pitch on your carpet: point at the floor and tap to place it, facing the way you look.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)

                Section("Your duck wears") {
                    Picker("Gear", selection: $referee.wearing) {
                        Text("Legs").tag(SoccerReferee.Gear.legs)
                        Text("Skates").tag(SoccerReferee.Gear.skates)
                    }
                    .pickerStyle(.segmented)
                    Text(referee.wearing == .legs
                         ? "Walks 0.11 m/s, sprints 0.15, and can ROULADE — the measured forward roll, faster than running."
                         : "Pollen's roller blades: glides 0.45 m/s, tops out at 0.6, propelled by the real swizzle recorded from the roller policy — and the CROUCH trick instead of a roulade. Speeds are the older rollers scene's; its training-parameter rebuild is pending.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                Section("Match") {
                    Picker("Half length", selection: $referee.halfLength) {
                        Text("1 min").tag(60.0)
                        Text("2 min").tag(120.0)
                        Text("5 min").tag(300.0)
                    }
                    .pickerStyle(.segmented)
                    Text("Seconds of play in each of the two halves. A match is twice this.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                if GamepadInput.shared.isConnected {
                    Section {
                        // `Theme.success` because a paired controller is a good
                        // thing that has already happened — the same token
                        // `DriveView` sets its own "controller connected" line
                        // in, so the two screens say it the same way.
                        Label("Controller connected — A pass · B shoot · Y roulade/crouch · L1 switch · R2 sprint",
                              systemImage: "gamecontroller.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.success)
                            .accessibilityLabel(Text("Controller connected"))
                            .accessibilityValue(Text("A passes, B shoots, Y is the roulade or crouch, L1 switches duck, R2 sprints."))
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                Section {
                    // IT STARTS TEN DUCKS MOVING, so it is the sixty-point
                    // variant rather than `.borderedProminent` at whatever
                    // height that happened to be. The row's own background is
                    // cleared because the capsule is the surface here: a
                    // `surfacePrimary` card behind an orange capsule would put a
                    // second corner radius nobody chose around it.
                    Button {
                        onStart()
                    } label: {
                        Text(referee.venue == .ar ? "Place the pitch" : "Kick off")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryActionMoves)
                    .accessibilityHint(Text(referee.venue == .ar
                        ? "Opens the camera so you can tap the floor and lay the pitch out."
                        : "Kicks off in \(referee.theme.name)."))
                    .listRowBackground(Color.clear)
                }
            }
            // THE FORM SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
            // GREY, and every row on a real `surfacePrimary` card above it —
            // which is what `DriveView` does with its list and why no word in
            // either screen is ever set on a ground the palette says is short of
            // 4.5:1. The section's own corner is the system's: a `Form` will not
            // be told its radius, and hand-rolling one to win a corner would
            // cost the four things the stock control does correctly.
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
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
        // THE SHEET'S OWN CORNER, ON THE SCALE. `Palette.Radius.sheet` is the
        // step the design system reserves for exactly this shape; left alone,
        // the sheet takes UIKit's own radius, which is a number nothing in this
        // app chose. The rows inside it keep the system's grouped corner —
        // a `Form` cannot be told its radius, and hand-rolling one to win that
        // corner would cost the label, the value, the Dynamic Type and the
        // Switch Control support a stock `Picker` already has.
        .presentationCornerRadius(Theme.radius(SoccerMetric.sheet))
    }

    private func coerce() {
        if !door.canOfferAR && referee.venue != .stadium { referee.venue = .stadium }
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
    let onChange: (Bool) -> Void

    @State private var down = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(label)
            // Only the largest pad earns a headline. The rest are caption-bold,
            // which is what fits a word like ROULADE inside a circle a thumb
            // can cover.
            .font(size >= SoccerMetric.shootPad ? .headline : .caption.bold())
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
            .accessibilityLabel(Text(label))
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
        phase = match.phase
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
        phase = match.phase
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
            // team's scorer performs the motion you authored in Microduck Studio,
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

