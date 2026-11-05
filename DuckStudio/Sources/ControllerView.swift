import SwiftUI
import StudioKit

/// The controller that floats over Play's stage on every venue: the duck pill, the
/// Drive | Tell | Auto switch and the solid red Stop disc along the top, and the mode's own
/// panel along the bottom (docs/plans/native-first-redesign.md, build 91).
///
/// IT DRAWS AND ROUTES; DriveView OWNS THE DUCK. Every action is a closure the host hands in,
/// so the loop, the peer and the stop stay in one place, and this file adds no second way to
/// move or stop anything. Every word is the kit's (`ControllerWords`, `AutoGoal`).
struct ControllerTopBar: View {
    @Binding var mode: ControlArbiter.Mode
    let pill: DuckPill
    let stop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing(.tight)) {
            pill
            Spacer(minLength: Theme.spacing(.tight))
            ModeSwitch(mode: $mode)
            Spacer(minLength: Theme.spacing(.tight))
            StopDisc(action: stop)
        }
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.top, Theme.spacing(.tight))
    }
}

/// Drive | Tell | Auto. Symbols carry the modes, not colour.
struct ModeSwitch: View {
    @Binding var mode: ControlArbiter.Mode

    var body: some View {
        Picker("Mode", selection: $mode) {
            ForEach(ControlArbiter.Mode.allCases, id: \.self) { m in
                Label(ControllerWords.title(m), systemImage: ControllerWords.symbol(m))
                    .labelStyle(.titleAndIcon)
                    .accessibilityHint(Text(ControllerWords.line(m)))
                    .tag(m)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: ControllerMetric.switchWidth)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

/// The duck pill, top left: which duck, and whether the last thing asked was answered.
///
/// THE VENUE CHANGES ONLY HERE, on an explicit pick (the plan's input-safe switch); nothing
/// that reconnects in the background moves it. The live dot replaces the toolbar lens.
struct DuckPill: View {
    let name: String
    let live: LensIndicator.Connection
    /// The venues a person may pick, in order, with the one in force.
    let venues: [DriveVenue]
    let current: DriveVenue
    let pick: (DriveVenue) -> Void
    let details: () -> Void
    /// The practice duck's "Put it back on its feet", or nil on a duck it cannot reach.
    var putBack: (() -> Void)? = nil

    var body: some View {
        Menu {
            Section {
                ForEach(venues) { venue in
                    Button {
                        pick(venue)
                    } label: {
                        if venue == current {
                            Label(Self.name(of: venue), systemImage: "checkmark")
                        } else {
                            Text(Self.name(of: venue))
                        }
                    }
                }
            } header: {
                SectionHeading(text: ControllerWords.driveOn)
            }
            if let putBack {
                Button(action: putBack) {
                    Label(ControllerWords.putBack, systemImage: "figure.stand")
                }
                .accessibilityHint(Text(ControllerWords.putBackHint))
            }
            Button(action: details) {
                Label(ControllerWords.duckDetails, systemImage: "info.circle")
            }
        } label: {
            HStack(spacing: Theme.spacing(.hairline)) {
                Circle()
                    .fill(dot)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.spacing(.snug))
            .frame(minHeight: DesignMetric.minimumTarget)
            .background(Theme.surfacePrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: DesignMetric.outlineStroke))
            .shadow(color: PondShadow.colour, radius: PondShadow.blur, y: PondShadow.y)
        }
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(live.spoken))
    }

    /// Green when the last request was answered, yellow while waiting, grey otherwise. Never a
    /// heartbeat claim. Not orange: on Pond Day orange means "press me".
    private var dot: Color {
        switch live {
        case .connected: return Theme.success
        case .connecting: return Theme.warning
        case .asleep: return Theme.textTertiary
        }
    }

    static func name(of venue: DriveVenue) -> String {
        switch venue {
        case .sim: return ControllerWords.practiceDuck
        case .ar: return ControllerWords.yourFloor
        case .real: return ControllerWords.yourDuck
        }
    }
}

/// Tell: a spoken or typed sentence, or a tile, read by `DuckOrderMatcher` and run by
/// `DuckOrderRunner`.
///
/// BUILD 92: THE PANEL TAKES THE STICKS' PLACE, so the duck stays in view, and the tiles wrap
/// instead of scrolling off the edge. Only tiles this duck can do are drawn
/// (`ControllerWords.tiles(for:)`). Refusals and results show in the panel's own caption line,
/// which goes away on its own.
struct TellPanel: View {
    let duck: DuckIdentity.Kind?
    let caption: String?
    let busy: Bool
    @ObservedObject var listener: DuckListener
    let send: (String) -> Void
    let stop: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: ControllerMetric.tileMinimum), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(ControllerWords.tiles(for: duck), id: \.said) { tile in
                    Button { send(tile.said) } label: {
                        Label(tile.said.capitalized, systemImage: tile.symbol)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.pondChip)
                    .disabled(busy)
                }
            }
            HStack(spacing: Theme.spacing(.tight)) {
                MicButton(listener: listener, onStop: stop, onFinal: { said in send(said) })
                TextField(ControllerWords.tellPlaceholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(submit)
                Button(ControllerWords.tellSend, action: submit)
                    .buttonStyle(.primaryActionInline)
                    .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let line = listener.listening ? MicWords.listening : (listener.problem ?? caption) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.spacing(.snug))
        .pondPanel()
    }

    private func submit() {
        let said = text.trimmingCharacters(in: .whitespaces)
        guard !said.isEmpty, !busy else { return }
        send(said)
        text = ""
        focused = false
    }
}

/// Auto, Apple Intelligence first (build 92, the owner's ask after 2.0 (91)).
///
/// ONE PANEL DOCKED WHERE THE PAD WAS, NOTHING SCROLLING SIDEWAYS. Leading: the Ask the duck card,
/// where on-device Apple Intelligence plans a few steps from a sentence. Trailing: a narrow column
/// of the other helpers (Dream-1, then the phone driver once it ships). Every card is fully on
/// screen. While a goal runs, the panel collapses to one status line with Take over; the red disc
/// top right is the Stop.
struct AutoPanel: View {
    let duck: DuckIdentity.Kind?
    let driverInstalled: Bool
    let dreamReady: Bool
    @ObservedObject var ask: AskTheDuck
    @ObservedObject var listener: DuckListener
    let caption: String?
    /// The status line while something runs, or nil.
    let running: String?
    let plan: (String) -> Void
    /// A "Try saying" sentence tapped: planned with no model and run.
    let example: (String) -> Void
    let go: (AutoGoal) -> Void
    let takeOver: () -> Void
    let stop: () -> Void

    var body: some View {
        if let running {
            HStack(spacing: Theme.spacing(.tight)) {
                Image(systemName: "sparkles").foregroundStyle(Theme.training).accessibilityHidden(true)
                Text(running)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(ControllerWords.takeOver, action: takeOver)
                    .buttonStyle(.raisedAction)
                    .accessibilityHint(Text(ControllerWords.takeOverHint))
            }
            .padding(.horizontal, Theme.spacing(.snug))
            .frame(minHeight: ControllerMetric.statusHeight)
            .background(Theme.surfacePrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: DesignMetric.outlineStroke))
            .shadow(color: PondShadow.colour, radius: PondShadow.blur, y: PondShadow.y)
        } else {
            HStack(alignment: .top, spacing: Theme.spacing(.tight)) {
                AskCard(duck: duck, ask: ask, listener: listener, caption: caption, plan: plan, example: example,
                        stop: stop)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                    Text(ControllerWords.otherHelpers)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(AutoGoal.allCases) { helper($0) }
                }
                .frame(width: ControllerMetric.helperColumn, alignment: .leading)
            }
        }
    }

    private func helper(_ goal: AutoGoal) -> some View {
        let availability = goal.availability(on: duck, driverInstalled: driverInstalled, dreamReady: dreamReady)
        let action = goal.action(on: duck, driverInstalled: driverInstalled, dreamReady: dreamReady)
        // "Add your key" is a way forward, so it stays pressable; a helper that has not shipped is not.
        let pressable = availability == .ready || action == AutoGoal.Words.addKey
        return VStack(alignment: .leading, spacing: 4) {
            Label(goal.title, systemImage: goal.symbol)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(goal.subtitle(on: duck, driverInstalled: driverInstalled, dreamReady: dreamReady))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if pressable {
                Button(action) { go(goal) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(Theme.spacing(.tight))
        .frame(maxWidth: .infinity, alignment: .leading)
        .pondPanel(.control)
        .opacity(pressable ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(goal.provenance))
    }
}

/// The leading card in Auto: say or type a goal, Apple Intelligence plans a few steps from the
/// closed set, the plan shows as chips for a moment with Cancel, then runs.
struct AskCard: View {
    let duck: DuckIdentity.Kind?
    @ObservedObject var ask: AskTheDuck
    @ObservedObject var listener: DuckListener
    let caption: String?
    let plan: (String) -> Void
    let example: (String) -> Void
    let stop: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private let chipColumns = [GridItem(.adaptive(minimum: 96), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").accessibilityHidden(true)
                Text(DuckDecider.Words.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(ask.availability.isReady ? DuckDecider.Words.provenance
                                          : [ask.availability.says, ask.availability.instead ?? ""].joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            switch ask.phase {
            case .preview(let orders), .running(_, let orders):
                LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 6) {
                    ForEach(Array(orders.enumerated()), id: \.offset) { i, order in
                        let chip = DuckDecider.chip(for: order)
                        Label(chip.title, systemImage: chip.symbol)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(ask.phase.activeStep == i ? Theme.onFill
                                                                       : Theme.textPrimary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(ask.phase.activeStep == i ? Theme.actionYellow
                                                                   : Theme.surfaceInteractive,
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(ask.phase.activeStep == i
                                                            ? Theme.outline : Color.clear,
                                                            lineWidth: DesignMetric.outlineStroke))
                    }
                }
                if case .preview = ask.phase {
                    HStack {
                        Text(DuckDecider.Words.startingSoon).font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                        Button(DuckDecider.Words.cancel) { ask.cancelPreview() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            default:
                HStack(spacing: Theme.spacing(.tight)) {
                    MicButton(listener: listener, onStop: stop, onFinal: { said in plan(said) })
                    TextField(DuckDecider.Words.placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...2)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(submit)
                    Button(DuckDecider.Words.go, action: submit)
                        .buttonStyle(.primaryActionInline)
                        .disabled(ask.phase == .thinking || duck == nil
                                  || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if duck != nil { trySaying }
            }
            if let line = listener.listening ? MicWords.listening
                : (ask.phase == .thinking ? DuckDecider.Words.thinking : (listener.problem ?? caption)) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(DuckDecider.Words.siriLine)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacing(.snug))
        .frame(maxWidth: .infinity, alignment: .leading)
        .pondPanel()
    }

    /// "Try saying": two sentences that work on this duck, one tap each (build 93). A first-time
    /// owner sees what to say, and the tap works with Apple Intelligence on or off.
    private var trySaying: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { trySayingParts }
            VStack(alignment: .leading, spacing: 6) { trySayingParts }
        }
    }

    @ViewBuilder private var trySayingParts: some View {
        Text(DuckDecider.Words.trySaying)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        ForEach(DuckDecider.Words.examples(on: duck, modelReady: ask.availability.isReady), id: \.self) { said in
            Button { example(said) } label: {
                Label(said, systemImage: "quote.bubble").lineLimit(1)
            }
            .buttonStyle(.pondChip)
            .accessibilityHint(Text(DuckDecider.Words.readyLine))
        }
    }

    private func submit() {
        let said = text.trimmingCharacters(in: .whitespaces)
        guard !said.isEmpty, ask.phase != .thinking else { return }
        plan(said)
        text = ""
        focused = false
    }
}

/// The real duck's picture, full-bleed, or a calm poster with its state sentence. Never a list.
struct DuckPictureStage: View {
    @ObservedObject var feed: DuckCameraFeed
    let connected: Bool
    let hasAddress: Bool
    let connect: () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundSecondary
            if let picture = feed.picture, feed.running {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityLabel(Text(DuckCamera.Words.pictureLabel))
            } else {
                VStack(spacing: Theme.spacing(.standard)) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                    Text(sentence)
                        .font(.system(.body, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.spacing(.loose))
                    if !connected {
                        Button(ControllerWords.connectYourDuck, action: connect)
                            .buttonStyle(.primaryAction)
                    } else if let problem = feed.problem {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.spacing(.loose))
                    }
                }
            }
        }
    }

    private var sentence: String {
        if !connected { return ControllerWords.noDuckYet }
        return hasAddress ? ControllerWords.waitingForPicture : ControllerWords.noCameraAddress
    }
}

enum ControllerMetric {
    static let switchWidth: CGFloat = 300
    static let cardWidth: CGFloat = 250
    /// The trailing column of other helpers in Auto: narrow, so Ask the duck leads.
    static let helperColumn: CGFloat = 132
    /// Tell's tiles wrap at this width, two or three to a row on a phone.
    static let tileMinimum: CGFloat = 130
    /// Auto's one status line while a goal runs: under the 60 pt cap for chrome over the picture.
    static let statusHeight: CGFloat = 52
    /// The second Stop, in the right-thumb zone, while Auto runs.
    static let thumbStop: CGFloat = 64
}
