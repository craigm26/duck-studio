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

    var body: some View {
        Menu {
            Section(ControllerWords.driveOn) {
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
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.spacing(.snug))
            .frame(minHeight: DesignMetric.minimumTarget)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(live.spoken))
    }

    /// Green when the last request was answered, amber while waiting, grey otherwise. Never a
    /// heartbeat claim.
    private var dot: Color {
        switch live {
        case .connected: return .green
        case .connecting: return .orange
        case .asleep: return .gray
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

/// Tell: a typed sentence or a tile, read by `DuckOrderMatcher` and run by `DuckOrderRunner`.
/// The stick stays live under it.
struct TellPanel: View {
    let caption: String?
    let busy: Bool
    let send: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacing(.tight)) {
                    ForEach(ControllerWords.tiles, id: \.said) { tile in
                        Button { send(tile.said) } label: {
                            Label(tile.said.capitalized, systemImage: tile.symbol)
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                    }
                }
            }
            HStack(spacing: Theme.spacing(.tight)) {
                TextField(ControllerWords.tellPlaceholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(submit)
                Button(ControllerWords.tellSend, action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.spacing(.snug))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func submit() {
        let said = text.trimmingCharacters(in: .whitespaces)
        guard !said.isEmpty, !busy else { return }
        send(said)
        text = ""
        focused = false
    }
}

/// Auto: one row of goal cards over the picture, and a second Stop in the thumb zone while a
/// goal runs.
struct AutoPanel: View {
    let duck: DuckIdentity.Kind?
    let driverInstalled: Bool
    let running: Bool
    let caption: String?
    let go: (AutoGoal) -> Void
    let stop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.spacing(.tight)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacing(.tight)) {
                    ForEach(AutoGoal.allCases) { card($0) }
                }
            }
            if running {
                StopDisc(size: ControllerMetric.thumbStop, action: stop)
            }
        }
    }

    private func card(_ goal: AutoGoal) -> some View {
        let availability = goal.availability(on: duck, driverInstalled: driverInstalled)
        return VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Label(goal.title, systemImage: goal.symbol)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(2)
            Text(goal.subtitle(on: duck, driverInstalled: driverInstalled))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(goal.provenance)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                if running, goal == .dream, let caption {
                    Text(caption).font(.caption2).lineLimit(1)
                }
                Spacer()
                Button(running ? AutoGoal.Words.running : AutoGoal.Words.go) { go(goal) }
                    .buttonStyle(.borderedProminent)
                    .disabled(availability != .ready || running)
            }
        }
        .padding(Theme.spacing(.snug))
        .frame(width: ControllerMetric.cardWidth, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(availability == .ready ? 1 : 0.8)
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
                            .buttonStyle(.borderedProminent)
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
    /// The second Stop, in the right-thumb zone, while Auto runs.
    static let thumbStop: CGFloat = 64
}
