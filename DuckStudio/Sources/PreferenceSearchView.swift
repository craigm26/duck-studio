import SwiftUI
import DuckKit
import StudioKit

/// Two ducks, and you say which one is better.
///
/// THIS IS THE WHOLE OF RLHF THAT FITS ON A PHONE, and it is worth being plain
/// about which part that is. No reward function is written down, no reward
/// model is fitted and no gradient is taken: `PreferenceSearch` proposes two
/// variants of the motion you are editing, you choose, and it moves. You are
/// the objective function.
///
/// IT WORKS BECAUSE A MOTION IS OPEN LOOP. Playing keyframes needs kinematics
/// and nothing else, so a phone can draw both sides. The same screen for a
/// POLICY is not possible here and the reason is measured rather than guessed:
/// `DuckSimulation` records, with tests, that closing a policy's loop without
/// contact gives "a fixed point or an oscillation, never a walk". Preferring
/// two policies needs a bench to roll them out.
///
/// BOTH SIDES PLAY ON ONE CLOCK. Two players running independently would drift,
/// and a person comparing a duck at 0.3 s against a duck at 0.5 s is comparing
/// the clock rather than the motion. One playhead drives both.
///
/// THE ORBIT IS SHARED FOR THE SAME REASON. Judging a bow from the front
/// against a bow from the side is not judging the bow.
struct PreferenceSearchView: View {
    let draft: IntentDraft
    let scene: DuckScene?
    /// Called with the motion the person settled on, once.
    let onKeep: (IntentDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = PreferenceSearch()
    @State private var pair: (left: PreferenceSearch.Settings, right: PreferenceSearch.Settings)
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = true
    @State private var orbit = OrbitState()

    init(draft: IntentDraft, scene: DuckScene?, onKeep: @escaping (IntentDraft) -> Void) {
        self.draft = draft
        self.scene = scene
        self.onKeep = onKeep
        _pair = State(initialValue: PreferenceSearch().nextPair())
    }

    private var left: IntentDraft { PreferenceSearch.apply(pair.left, to: draft) }
    private var right: IntentDraft { PreferenceSearch.apply(pair.right, to: draft) }
    private var best: IntentDraft { PreferenceSearch.apply(search.best, to: draft) }

    /// The longer of the two, so neither side is cut short by the other's clock.
    private var duration: TimeInterval { max(left.duration, right.duration, 0.01) }

    var body: some View {
        VStack(spacing: 0) {
            side(left, label: "A")
            Divider()
            side(right, label: "B")

            TransportBar(duration: duration, playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal).padding(.top, 6)

            controls
        }
        .navigationTitle("Which is better?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Keep") { onKeep(best); dismiss() }
                    .disabled(search.decided == 0)
            }
        }
    }

    private func side(_ motion: IntentDraft, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            DuckStage(pose: StagePose(jointAngles: motion.pose(at: playhead),
                                      root: StagePose.home.root),
                      environment: scene?.environment ?? .bareFloor,
                      props: scene?.props ?? [],
                      orbit: $orbit)
            Text(label)
                .font(.caption.weight(.semibold).monospaced())
                .padding(6)
                .background(.thinMaterial, in: Capsule())
                .padding(8)
                .accessibilityHidden(true)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 10) {
            // WHAT IS ACTUALLY DIFFERENT BETWEEN THEM. Without this the person
            // is asked to spot the difference as well as judge it, and a
            // comparison somebody cannot make reliably is worse than none.
            Text("Only \(search.knob.title.lowercased()) differs — it \(search.knob.effect).")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            HStack(spacing: 10) {
                Button { answer(.left) } label: {
                    Text("A is better").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { answer(.right) } label: {
                    Text("B is better").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            // A FIRST-CLASS ANSWER, NOT AN ESCAPE HATCH, and it is styled like
            // the other two on purpose. Forcing a choice between two things
            // somebody cannot tell apart manufactures signal, and the search
            // treats this as information: it moves nothing and steps smaller.
            Button { answer(.cannotTell) } label: {
                Text("Too close to call").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)

            Text(search.standing)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal).padding(.bottom, 8)
        }
    }

    private func answer(_ answer: PreferenceSearch.Answer) {
        search.record(answer, left: pair.left, right: pair.right)
        pair = search.nextPair()
        // BACK TO THE START OF THE NEXT PAIR. Leaving the playhead where it was
        // would show the next question already half-played, and the first
        // moment of a motion is where most of these knobs are visible.
        playhead = 0
        isRunning = true
    }
}
