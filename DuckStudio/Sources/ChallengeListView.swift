import SwiftUI
import StudioKit

/// The challenges, as a list.
///
/// WHY THIS SCREEN REPLACED THE STAIRS SCREEN RATHER THAN SITTING BESIDE IT.
/// Until the ball arrived, "the challenge" was a place — one row under Measure,
/// one door out of the Behaviours tab — and `StairsChallengeView` was the thing
/// that lived there. A second challenge given its own row in both places would
/// have split one habit into two: open a published entrant, edit a keyframe,
/// score it, keep what helps. So the place stays, and what is behind it is this
/// list. A third challenge is a `Challenge` case and a line in `screen(_:)`.
///
/// EVERY WORD ON A ROW IS THE KIT'S. `Challenge` answers the name, the one
/// sentence and what the build actually carries for each case, so this file
/// holds no copy about either challenge and cannot drift from the screen the
/// row opens. The one thing it decides is which SF Symbol goes beside a name,
/// which is a picture and not a claim.
struct ChallengeListView: View {
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    var body: some View {
        List {
            Section {
                ForEach(Challenge.allCases) { challenge in
                    NavigationLink {
                        screen(challenge)
                    } label: {
                        ChallengeRowLabel(challenge: challenge, symbol: Self.symbol(challenge))
                    }
                }
            } header: {
                SectionHeading(text: Challenge.listTitle)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(Challenge.listTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The screen behind one row.
    ///
    /// A `switch` HERE AND NOWHERE ELSE. The kit's whole point is that a row
    /// needs no `switch` to be drawn — but the two screens are two view types
    /// with two sets of machinery behind them, and a protocol wrapping them
    /// would be a layer whose only job was to hide four lines.
    @ViewBuilder private func screen(_ challenge: Challenge) -> some View {
        switch challenge {
        case .stairs:
            StairsChallengeView(drafts: drafts, scenes: scenes,
                                models: models, benches: benches)
        case .ball:
            BallChallengeView(drafts: drafts, scenes: scenes,
                              models: models, benches: benches)
        }
    }

    /// The glyph beside a name. Not in the kit, because a symbol is a picture
    /// and the kit's rule is about sentences.
    static func symbol(_ challenge: Challenge) -> String {
        switch challenge {
        case .stairs: return "stairs"
        case .ball: return "soccerball"
        }
    }
}

/// One challenge on the list: what it is, and what this build carries for it.
///
/// THREE LINES AND THE THIRD ONE IS THE HONEST ONE. `rowsSaid` says how many
/// published rows are in the build — or, when there are none, says that out
/// loud instead of leaving a row that looks like a leaderboard with nothing
/// behind it.
private struct ChallengeRowLabel: View {
    let challenge: Challenge
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing(.tight)) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.actionSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(challenge.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(challenge.oneSentence)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(challenge.rowsSaid)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.spacing(.hairline))
        .accessibilityElement(children: .combine)
    }
}
