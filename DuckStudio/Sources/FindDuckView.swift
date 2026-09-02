import SwiftUI
import StudioKit

/// Find a real Microduck and complete its handshake.
///
/// THE ONLY SCREEN IN THIS APP THAT TOUCHES HARDWARE, and the only one nobody
/// here can test. Every UUID, byte layout and step order is transcribed from
/// `btd`'s source in `pollen-robotics/microduck`; none of it has met a robot,
/// because none of us has one until deliveries start. So the screen is built to
/// be useful to the FIRST PERSON WHO POINTS IT AT A DUCK: every step is named,
/// shown in order, and keeps its own failure, so "it didn't work" comes back as
/// "it failed at the version read, saying X" — which is a bug report somebody
/// can act on rather than a shrug.
///
/// THE LENS IS THE MOTIF HERE BECAUSE THIS IS WHERE THE LINK IS. `LensIndicator`
/// exists for exactly this screen's problem: a spinner claims "the software is
/// busy", which is a statement about this phone, and what is actually happening
/// is that something across the room is being reached. The iris narrows while
/// the radio is listening and opens when a duck answers, so the moment of
/// connection is a thing you watch happen. There are two of them and they say
/// different things — the one in the toolbar is the SCREEN's link, and the one
/// on a row is THAT DUCK's, which is why `reaching` exists.
///
/// EVERY STATE IS A WORD. The handshake's step rows used to be a coloured glyph
/// and nothing else, so "done" and "failed" were a green tick and an orange
/// cross to anybody who could separate them and identical to anybody who could
/// not (SC 1.4.1). Each row now carries a `StateBadge`, which is a dot AND the
/// word beside it, and the failure keeps the kit's own sentence underneath.
struct FindDuckView: View {
    @StateObject private var scanner = DuckLinkScanner()

    /// Which duck the person reached for.
    ///
    /// PRESENTATIONAL ONLY, AND IT HAD TO LIVE HERE. `DuckLinkScanner` publishes
    /// one `progress` for the whole screen and keeps the peripheral it is
    /// talking to private, so there is nothing to ask which of the rows the
    /// handshake belongs to. Without that, a lens opening on connect would have
    /// to open on every row at once — which would say that four ducks answered
    /// when one did. This changes nothing about what is sent: it is set beside
    /// the same `handshake(with:)` call the button always made.
    ///
    /// AN ATTEMPT'S NAME HAS TO END WHEN THE ATTEMPT DOES, and this was set on
    /// tap and never cleared. `startIfReady()` empties `found` and refills it
    /// from a fresh scan, and a peripheral identifier survives that — so a duck
    /// re-sighted after a finished attempt came back still wearing it, and the
    /// row inherited a lens belonging to an attempt that was over. Three
    /// transitions clear it, and they are the three the scanner actually
    /// publishes: a failure, a return to idle, and a new scan starting. It also
    /// clears when the screen goes away, because `onDisappear` cancels the
    /// connection — after that no row is being reached, whatever `progress`
    /// still says.
    ///
    /// SUCCESS DELIBERATELY DOES NOT CLEAR IT. `.done` is the one state where
    /// the row's iris is supposed to be open: that duck answered, and clearing
    /// here would put the lens back to sleep at the exact moment the thing it
    /// exists to show happened.
    ///
    /// WHAT WOULD BE BETTER IS THE SCANNER SAYING WHOSE ATTEMPT IT IS. A
    /// published peripheral identifier alongside `progress` would make this
    /// derived rather than mirrored, and the mirror can still be wrong in one
    /// way the screen cannot see: the everyday path has no deadline — only the
    /// spike arms one — so a handshake that hangs stays `.running` until the
    /// link drops, and the row narrows its iris for as long as that takes. A
    /// timeout belongs in `DuckLinkScanner`, which this change does not own.
    @State private var reaching: UUID?

    var body: some View {
        List {
            if let radio = scanner.radio { radioSection(radio) }

            ducksSection

            if case .idle = scanner.progress {} else { handshakeSection }

            if case .done(let hello, let apiByte) = scanner.progress {
                answeredSection(hello, apiByte: apiByte)
            }

            scanSection
            spikeSection

            Section {
                Text(DuckLink.whatThisCanDo)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY,
        // and every row keeps a real `surfacePrimary` card under it — so no word
        // on this screen is ever set on `backgroundSecondary`, which the palette
        // documents as short of 4.5:1 for the four inks.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Find a duck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // THE SCREEN'S LINK, WHERE NOTHING SCROLLS. A person who has
                // scrolled past the duck rows still needs to know whether the
                // radio is reaching for something.
                LensIndicator(state: linkState)
            }
        }
        // WARMED BEFORE THE FIRST EVENT, NOT AT IT. The taptic engine spins up
        // on demand and the first tap of a session lands after the thing it is
        // about, which teaches the person that the buzz and the duck are
        // unrelated.
        .task { Haptic.prepare() }
        // A ROBOT ANSWERED, WHICH IS A THING THAT HAPPENED IN THE WORLD — the
        // one category `Haptic` exists for. Nothing here fires on a tap.
        //
        // AND THE SAME TRANSITION IS WHERE THE ROW'S NAME IS LET GO. Every way
        // the everyday path can end lands here: `didFailToConnect` and a
        // mid-handshake disconnect both come through as `.failed`, and `.done`
        // is the one ending that keeps its row lit — see `reaching`.
        .onChange(of: scanner.progress) { _, now in
            switch now {
            case .done: Haptic.connected()
            case .failed, .idle: reaching = nil
            case .running: break
            }
        }
        // A NEW SCAN IS A NEW QUESTION. `begin()` empties `found` and listens
        // again, so whatever was being reached for before is history — and this
        // fires only on the way up, because `handshake(with:)` stops the scan
        // itself and would otherwise clear the row it had just set.
        .onChange(of: scanner.scanning) { _, nowScanning in
            if nowScanning { reaching = nil }
        }
        // `stop()` CANCELS THE CONNECTION, so nothing is being reached once
        // this has run — including the duck that answered, whose lens would
        // otherwise still be open on the way back from the spike screen.
        .onDisappear {
            scanner.stop()
            reaching = nil
        }
    }

    // MARK: - what the radio says about itself

    /// Bluetooth off, or not permitted. `Theme.warning` rather than
    /// `Theme.refused`: nothing refused anything, and every one of these
    /// sentences is a thing the person can go and fix.
    private func radioSection(_ radio: String) -> some View {
        Section {
            Label(radio, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the ducks

    private var ducksSection: some View {
        Section {
            if scanner.found.isEmpty { listeningRow }
            ForEach(scanner.found) { duck in
                Button {
                    reaching = duck.id
                    scanner.handshake(with: duck)
                } label: {
                    row(duck)
                }
                .buttonStyle(.plain)
                // THE SIGHTING IS THE LABEL, THE LENS IS THE VALUE, AND WHAT THE
                // ROW DOES IS THE HINT. An explicit label on a Button REPLACES
                // what its subtree would have said — so with the name alone the
                // address, the signal and the evidence tier were absorbed and
                // discarded, for the one person who cannot read them off the
                // row. The kit's line carries all three.
                .accessibilityLabel(Text(duck.sighting.line))
                .accessibilityValue(Text(lens(for: duck).spoken))
                .accessibilityHint(Text("Connects to this duck and runs the handshake."))
            }
        } header: {
            SectionHeading(text: "Ducks in range")
        } footer: {
            // WHY A SCAN IS WORTH HAVING ON ITS OWN. Pollen's `duckctl scan`
            // deliberately connects to nothing for this reason, and it is
            // the command they reach for when a robot is unreachable.
            Text("Scanning connects to nothing, so this works on a duck that is not answering anything else. The address comes out of the advertisement itself — which is the only way a listing can tell you where to ssh.")
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Nothing found yet.
    ///
    /// AN EYE RATHER THAN A SPINNER, for the reason `LensIndicator` is written
    /// down at length: a spinner says this phone is busy, and what is happening
    /// is that the room is being listened to. The iris is hidden from VoiceOver
    /// because its own word is "Connecting" and nothing is being connected to —
    /// the sentence beside it is the accurate one, which makes the picture
    /// decoration in SC 1.4.11's exact sense.
    private var listeningRow: some View {
        HStack(spacing: Theme.spacing(.tight)) {
            LensIndicator(state: scanner.scanning ? .connecting : .asleep)
                .accessibilityHidden(true)
            Text(scanner.scanning ? "Listening for a duck…" : "Not scanning.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One duck.
    ///
    /// STACKED RATHER THAN THREE COLUMNS. The name, the address and the signal
    /// used to share one row's width, which at an accessibility text size is a
    /// fight the number on the right always loses — so the app hid the signal
    /// strength from the people who had most enlarged the type in order to read
    /// it. `TelemetryRow` stacks its own pair at those sizes, and the address
    /// gets the whole width on its own line.
    private func row(_ duck: DuckLinkScanner.Found) -> some View {
        let sighting = duck.sighting
        return VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(spacing: Theme.spacing(.tight)) {
                LensIndicator(state: lens(for: duck))
                Text(sighting.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.spacing(.tight))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            // MONO BECAUSE IT IS AN ADDRESS. This is the one thing on the row
            // somebody retypes into a terminal character by character, and the
            // three cases below are not all addresses — but they all occupy the
            // place an address would, and a sentence that moves when the type
            // changes is not the failure being avoided here.
            Text(address(sighting.address))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // RSSI IS TELEMETRY IN THE STRICT SENSE — it is different on every
            // advertisement, which is exactly the claim monospace makes and the
            // reason tabular figures stop the row twitching as it updates.
            if let rssi = sighting.rssi {
                TelemetryRow(label: "Signal", value: "\(rssi)", unit: "dBm")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// What the lens on THIS row is doing. A duck nobody reached for is asleep,
    /// however busy the radio is — an eye opening on four rows at once would
    /// say four ducks answered when one did.
    private func lens(for duck: DuckLinkScanner.Found) -> LensIndicator.Connection {
        guard reaching == duck.id else { return .asleep }
        switch scanner.progress {
        case .running: return .connecting
        case .done: return .connected
        case .idle, .failed: return .asleep
        }
    }

    /// What the lens in the toolbar is doing: a duck has answered, one is being
    /// reached, or the radio is listening to a room with nothing in it.
    private var linkState: LensIndicator.Connection {
        switch scanner.progress {
        case .done: return .connected
        case .running: return .connecting
        case .idle, .failed: return scanner.scanning ? .connecting : .asleep
        }
    }

    /// The three cases `adv.rs` insists are different, kept different.
    private func address(_ address: DuckLink.Address) -> String {
        switch address {
        case .at(let ip): return ip
        case .none: return "no address — the duck has no wifi"
        case .notBroadcast: return "no address broadcast — an older release"
        }
    }

    // MARK: - the handshake, step by step

    private var handshakeSection: some View {
        Section {
            ForEach(DuckLink.Step.allCases.filter { $0 != .scan }, id: \.self) { step in
                stepRow(step)
            }
        } header: {
            SectionHeading(text: "The handshake")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func stepRow(_ step: DuckLink.Step) -> some View {
        let state = state(of: step)
        return VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(spacing: Theme.spacing(.tight)) {
                // THE GLYPH AND THE BADGE SAY THE SAME THING IN TWO CHANNELS —
                // shape and word — and neither of them is the colour. The
                // spinner that used to sit on the trailing edge is gone: the
                // lens in the toolbar is already breathing while a step runs,
                // and a row with a glyph, a badge and a spinner on it is three
                // marks for one fact.
                Image(systemName: state.symbol)
                    .foregroundStyle(state.badge.color)
                Text(step.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.spacing(.tight))
                StateBadge(text: state.word, state: state.badge)
            }
            if state == .running || state == .failed {
                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .failed(let failed, let why) = scanner.progress, failed == step {
                // THE REFUSAL'S OWN WORDS, IN THE REFUSAL COLOUR. This is the
                // only thing on the screen a bug report can be written from, so
                // it is the one line here that is allowed to be loud.
                Text(why)
                    .font(.caption)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// How far a step got, as this screen reads `scanner.progress`.
    ///
    /// THE WORD IS THE STATE AND THE COLOUR IS A HINT. `RobotState` carries the
    /// palette's guarantee that each of its four values clears 4.5:1 on every
    /// ground the app sets words on, which is what makes it safe for a badge;
    /// what it does not carry is a case for "failed", so the mapping below picks
    /// the loudest of the four for it and lets the word do the work. See the
    /// same argument, at greater length, in `StateBadge`.
    private enum StepState: Equatable {
        case waiting, running, done, failed

        var symbol: String {
            switch self {
            case .waiting: return "circle"
            case .running: return "circle.dotted"
            case .done: return "checkmark.circle.fill"
            case .failed: return "xmark.octagon.fill"
            }
        }

        /// One word, lower case, because it is a value and not a sentence.
        var word: String {
            switch self {
            case .waiting: return "waiting"
            case .running: return "running"
            case .done: return "done"
            case .failed: return "failed"
            }
        }

        /// Teal for a step that answered, because teal is what a machine
        /// measured; yellow while it is being asked; grey for a step nobody has
        /// reached; and the active colour for a failure, which is the only one
        /// of the four that anybody has to act on.
        var badge: RobotState {
            switch self {
            case .waiting: return .offline
            case .running: return .scanning
            case .done: return .idle
            case .failed: return .active
            }
        }
    }

    private func state(of step: DuckLink.Step) -> StepState {
        switch scanner.progress {
        case .idle:
            return .waiting
        case .running(let now):
            if step == now { return .running }
            return step.rawValue < now.rawValue ? .done : .waiting
        case .failed(let at, _):
            if step == at { return .failed }
            return step.rawValue < at.rawValue ? .done : .waiting
        case .done:
            return .done
        }
    }

    // MARK: - what it said back

    private func answeredSection(_ hello: DuckLink.Hello, apiByte: UInt8) -> some View {
        Section {
            // EVERY ONE OF THESE IS A DIFFERENT ANSWER FROM A DIFFERENT DUCK, so
            // every one of them is a `TelemetryRow`: mono, tabular, and stacked
            // rather than truncated once the type is large enough that a label
            // and a value cannot share a line.
            TelemetryRow(label: "API version", value: "\(hello.apiVersion)")
            if UInt32(apiByte) != hello.apiVersion {
                // Two layers answered differently — see `apiByte`. A warning
                // rather than a refusal: nothing said no, and what has happened
                // is that two things which should agree do not.
                Label("The GATT read said \(apiByte) and hello said \(hello.apiVersion). "
                      + "Those come from different layers and should agree.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let daemon = hello.daemonVersion {
                TelemetryRow(label: "Daemon", value: daemon)
            }
            TelemetryRow(label: "Revision", value: hello.revision ?? "not from CI")
            Text(DuckLink.verdict(for: hello.apiVersion))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "It answered")
        } footer: {
            Text("A duck built on somebody's laptop reports no revision, and that is normal rather than a fault.")
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - starting and stopping

    private var scanSection: some View {
        Section {
            // THE THING SOMEBODY CAME HERE TO DO, so it is a capsule in the
            // action colour and everything else on the screen is a row. It is
            // `.primaryAction` and not `.primaryActionMoves`: a scan changes
            // the app, not the robot — nothing moves when this is pressed.
            Button {
                scanner.begin()
            } label: {
                Label(scanner.scanning ? "Scanning…" : "Scan for ducks",
                      systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            // RESTORED. The restyle dropped this, and `startIfReady()` begins
            // with `found.removeAll()` — so a second tap on "Scanning…" wiped
            // every duck already listed while looking like it did nothing.
            .disabled(scanner.scanning)
            .listRowSeparator(.hidden)
            .accessibilityLabel(Text("Scan for ducks"))
            .accessibilityValue(Text(scanner.scanning ? "Scanning" : ""))

            if scanner.scanning {
                // THE GLYPH CARRIES THE ACTION COLOUR AND THE WORD DOES NOT, so
                // there is exactly one orange capsule in this section and the
                // second door beside it stays a row.
                Button(role: .cancel) {
                    scanner.stop()
                } label: {
                    Label {
                        Text("Stop").foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "stop.circle").foregroundStyle(Theme.actionSecondary)
                    }
                }
                .accessibilityLabel(Text("Stop scanning"))
            }
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // THE SECOND, DELIBERATELY SEPARATE DOOR. Everything above is the
    // everyday path — find my duck, is it there, where do I ssh. This is
    // a diagnostic run for Pollen's own blocker: it takes longer, it
    // asks a question out loud, and it ends in a report rather than an
    // answer. Putting it behind its own screen keeps the ordinary case
    // ordinary and stops a timed experiment from ever being the thing
    // somebody taps by accident.
    private var spikeSection: some View {
        Section {
            NavigationLink { PairingSpikeView() } label: {
                Label {
                    Text("Run the pairing spike").foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "stopwatch").foregroundStyle(Theme.actionSecondary)
                }
            }
        } footer: {
            Text("A timed diagnostic run that ends in a report you can hand over, rather than "
                 + "an answer about your duck. It takes minutes, it asks you a question part "
                 + "way through, and the everyday path above is untouched by it.")
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }
}

// MARK: - the numbers and the one button the connectivity screens share

/// Dimensions the four connectivity and catalogue screens write down for
/// themselves.
///
/// NOT IN `Palette` BECAUSE `Palette` HAS NO SCALE FOR THEM YET, and inventing
/// one from the app side would put the design system in two files. This is the
/// same arrangement `DesignComponents` makes for the components, `DriveView`
/// makes for the drive screen and `AuthoringMetric` makes for the six authoring
/// screens — gathered here so there is one of each across the four rather than
/// four, and so the next person can see which numbers are load-bearing.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST. A ratio is a fact about two colours
/// and lives in `Palette`, where a test runs the WCAG formula over it. How thick
/// to draw a rule is a judgement about a screen.
enum ConnectivityMetric {
    /// A hairline STROKE, the app's one.
    static let hairlineStroke = DesignMetric.hairlineStroke

    /// 44pt — the smallest thing a finger is asked to hit, the app's one, by
    /// name. Nothing on these four screens moves a robot, so nothing here takes
    /// the 60pt floor `PrimaryActionStyle` keeps for controls that do.
    static let minimumTarget = DesignMetric.minimumTarget

    // THE FOCUS RING'S GEOMETRY IS GONE FROM HERE, and it is not coming back to
    // this file. It aliased `DesignMetric.focusRingWidth` and `.focusRingOffset`
    // for a ring `ConnectivityActionStyle` drew on `@Environment(\.isFocused)`
    // — a value a `ButtonStyle` on iOS is never handed, so the ring never drew,
    // and Full Keyboard Access draws the system's own around whatever it lands
    // on anyway. `DesignComponents` says those two constants are "kept only
    // until their last caller in `FindDuckView` goes"; this was that caller.
    // They now have one left, `AuthoringMetric` in `IntentAuthorView`, for a
    // ring with exactly the same defect.
}

/// The second-loudest button on these four screens.
///
/// QUIET IS THE ABSENCE OF THE ACTION COLOUR, NOT THE ABSENCE OF CONTRAST. The
/// usual treatment for a secondary button is half opacity, which takes its label
/// to roughly two to one and leaves "what does this do" unanswerable. This keeps
/// `surfacePrimary` under `textPrimary` — a pairing `PaletteTests` proves at
/// 4.5:1 in both schemes — and says "not the main thing here" by having no
/// orange in it at all.
///
/// IT EXISTS BECAUSE `.bordered` AT `.controlSize(.small)` IS ABOUT 28 POINTS.
/// Five inline actions across the catalogue screens were drawn that way: an
/// "Open" beside a policy, a "Read" beside a repository, three answers to the
/// pairing question. Every one of them was under the HIG's 44pt floor, on
/// screens somebody is using one-handed while holding a robot.
///
/// PRESSED IS A STEP UP THE PALETTE and nothing scales. `surfaceInteractive` is
/// the next surface along, which is the size of change a press needs to be seen
/// and no larger; a control that moves out from under a committed finger is the
/// one thing this app's button styles refuse to do.
///
/// IT IS NOT `PrimaryActionStyle` UNDER ANOTHER NAME, and the difference is the
/// whole point of it rather than a detail: that style fills its capsule with
/// `Theme.actionPrimary` and sets the label in `DesignFixed.onAction` at
/// `.headline`, because it is the one thing on a screen somebody came to press.
/// This one has no orange in it at all, sets a `.footnote` in `Theme.textPrimary`
/// on `surfacePrimary`, and exists so that a screen can carry FIVE inline doors
/// without five of them shouting. Both keep the same 44pt floor, and a screen
/// that used this for its main action would be a screen with no main action.
///
/// THE ONE THAT IS A DUPLICATE IS `AuthoringActionStyle`, in `IntentAuthorView`.
/// It is this style with two different paddings and its own metric enum — same
/// font, same inks, same surfaces, same press, same floor. One of the two should
/// go, into `DesignComponents` beside `PrimaryActionStyle`, with the padding as
/// a `Reach`-shaped parameter; that is a single style serving both, not a
/// preference between them. It is not done here because this change owns the
/// four connectivity screens and not the authoring ones, and a style deleted out
/// from under a file somebody else is editing is a merge conflict rather than a
/// cleanup. Written down so the next person finds the pair rather than the half.
struct ConnectivityActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    /// A nested `View` rather than the style itself, because `@Environment` only
    /// resolves inside one — a `ButtonStyle` is not a view, so a style that
    /// needs to know whether it is enabled has to hand its body to something
    /// that is. `PrimaryActionStyle` is built the same way and says so at
    /// greater length.
    ///
    /// AND BEING INSIDE A VIEW MAKES A VALUE READABLE, NOT MEANINGFUL. This
    /// read `\.isFocused` here too, and drew three points of teal around the
    /// capsule when it was true. It was never true: `isFocused` reports on a
    /// focusable container, and iOS hands a plain `Button` nothing to put in a
    /// style's body, so the ring was a claim rather than a feature. What
    /// actually indicates focus here is Full Keyboard Access, which draws the
    /// system's ring — in the shape and colour the person set in Settings —
    /// around whatever it has landed on, in every app on the phone. A second,
    /// hand-drawn ring on the handful of controls that happened to use this
    /// style would not have added contrast; it would have taught somebody that
    /// focus looks like two different things. `PrimaryActionStyle` had the same
    /// ring removed for the same reason and argues it at length.
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.spacing(.standard))
                .padding(.vertical, Theme.spacing(.tight))
                .frame(minWidth: ConnectivityMetric.minimumTarget,
                       minHeight: ConnectivityMetric.minimumTarget)
                .background(Capsule().fill(configuration.isPressed
                                           ? Theme.surfaceInteractive
                                           : Theme.surfacePrimary))
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: ConnectivityMetric.hairlineStroke))
                .contentShape(Capsule())
        }
    }
}

extension ButtonStyle where Self == ConnectivityActionStyle {
    /// The quiet capsule, at the HIG's 44pt floor.
    static var connectivityAction: ConnectivityActionStyle { ConnectivityActionStyle() }
}
