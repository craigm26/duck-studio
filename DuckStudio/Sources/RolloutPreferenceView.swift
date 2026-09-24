import SwiftUI
import DuckKit
import StudioKit

/// Two trained walkers doing the same thing, recorded, and a person saying
/// which one looks better.
///
/// THE POLICY SCREEN `PreferenceSearchView` SAID WAS IMPOSSIBLE HERE, made
/// possible by not running the policies here. That screen's header is right: a
/// walking network cannot be rolled out on a phone. duckbatch's p001 rolled
/// four of them out in MuJoCo from one seed, and `RolloutPairs` carries the
/// frames, so this screen draws recordings and decides nothing about physics.
///
/// THE SAME LAYOUT AS `PreferenceSearchView`, ON PURPOSE: two stages stacked,
/// one playhead, one orbit. Its reasons carry over unchanged — two clocks would
/// be comparing the clock, two cameras would be comparing the camera.
///
/// BLIND. The ducks are Left and Right; which network is on which side is
/// drawn at random per pair and written into the record, and the names never
/// reach the screen.
///
/// EVERY ANSWER IS ONE RECORD, written as it is given, with the sharing choice
/// from Settings. Nothing on this screen sends anything.
struct RolloutPreferenceView: View {

    @StateObject private var feedback = FeedbackStore()
    @State private var pairs: RolloutPairs?
    @State private var deck: PreferenceDeck?
    @State private var showing: RolloutPairs.Showing?
    @State private var reasons: Set<String> = []
    @State private var answered = 0
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = true
    @State private var orbit = OrbitState()

    var body: some View {
        Group {
            if let pairs, let showing {
                screen(pairs, showing)
            } else if pairs != nil {
                message(RolloutPreferenceWords.finished)
            } else {
                message(RolloutPreferenceWords.unreadable)
            }
        }
        .background(Theme.backgroundPrimary)
        .navigationTitle(RolloutPreferenceWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        guard pairs == nil,
              let url = Bundle.main.url(forResource: "p001-pairs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let read = try? RolloutPairs.read(data) else { return }
        pairs = read
        var fresh = PreferenceDeck(read)
        showing = fresh.next()
        deck = fresh
    }

    private func message(_ line: String) -> some View {
        VStack {
            Text(line)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(Theme.spacing(.snug))
            Text(RolloutPreferenceWords.tally(answered))
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func screen(_ pairs: RolloutPairs, _ showing: RolloutPairs.Showing) -> some View {
        let duration = max(pairs.duration(showing.left, showing.command, env: showing.env),
                           pairs.duration(showing.right, showing.command, env: showing.env))
        return VStack(spacing: 0) {
            stage(pairs.stance(showing.left, showing.command, env: showing.env, at: playhead),
                  side: RolloutPreferenceWords.left)
            Rectangle().fill(Theme.separator).frame(height: AuthoringMetric.hairlineStroke)
            stage(pairs.stance(showing.right, showing.command, env: showing.env, at: playhead),
                  side: RolloutPreferenceWords.right)
            TransportBar(duration: duration, playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal, Theme.spacing(.snug))
                .padding(.top, Theme.spacing(.hairline))
            controls(pairs, showing)
        }
    }

    /// One duck. The side's name is for VoiceOver only: the buttons below say
    /// Left and Right, and the picture is the answer.
    private func stage(_ pose: DuckStance, side: String) -> some View {
        DuckStage(pose: pose, environment: .bareFloor, props: [], orbit: $orbit)
            .frame(maxHeight: .infinity)
            .accessibilityLabel(Text(side))
    }

    private func controls(_ pairs: RolloutPairs, _ showing: RolloutPairs.Showing) -> some View {
        VStack(spacing: Theme.spacing(.snug)) {
            Text(RolloutPreferenceWords.asked(pairs.commands[showing.command] ?? []))
                .font(.footnote).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(RolloutPreferenceWords.simulated)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacing(.tight)) {
                    ForEach(DuckFeedback.Reason.allCases, id: \.rawValue) { reason in
                        let on = reasons.contains(reason.rawValue)
                        Button(RolloutPreferenceWords.reason(reason)) {
                            if on { reasons.remove(reason.rawValue) } else { reasons.insert(reason.rawValue) }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? Theme.actionPrimary : Theme.textSecondary)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .accessibilityLabel(Text(RolloutPreferenceWords.reasonsHeading))

            HStack(spacing: Theme.spacing(.tight)) {
                Button { answer(.left, pairs, showing) } label: {
                    Text(RolloutPreferenceWords.left).frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                Button { answer(.right, pairs, showing) } label: {
                    Text(RolloutPreferenceWords.right).frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
            }
            // TWO FIRST-CLASS ANSWERS BESIDE THE PAIR, the same size as the
            // pair: `PreferenceSearchView`'s reason for its "too close to
            // call", and "neither" is information a forced choice would erase.
            HStack(spacing: Theme.spacing(.tight)) {
                Button { answer(.tie, pairs, showing) } label: {
                    Text(RolloutPreferenceWords.tie).frame(maxWidth: .infinity)
                }
                .buttonStyle(AuthoringActionStyle())
                Button { answer(.bothBad, pairs, showing) } label: {
                    Text(RolloutPreferenceWords.bothBad).frame(maxWidth: .infinity)
                }
                .buttonStyle(AuthoringActionStyle())
            }
            Text(RolloutPreferenceWords.tally(answered))
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.bottom, Theme.spacing(.tight))
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundPrimary)
    }

    private func answer(_ pick: RolloutPairs.Pick, _ pairs: RolloutPairs,
                        _ showing: RolloutPairs.Showing) {
        let chosen = DuckFeedback.Reason.allCases.filter { reasons.contains($0.rawValue) }
        if let record = try? pairs.record(pick, reasons: chosen, for: showing,
                                          share: feedback.share, client: FeedbackStore.client) {
            feedback.append([record])
            answered += 1
        }
        reasons = []
        self.showing = deck?.next()
        // BACK TO THE START, both ducks at their shared first frame.
        playhead = 0
        isRunning = true
    }
}
