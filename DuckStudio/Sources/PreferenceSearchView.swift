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
///
/// THREE ANSWERS, AND THE THIRD ONE IS QUIETER THAN THE OTHER TWO ON PURPOSE.
/// A and B are the comparison, so they wear the action colour; "too close to
/// call" is a real answer the search acts on, so it keeps a real surface, real
/// ink and the same forty-four point reach — it is not an escape hatch and it
/// is not faded out. What it does not have is orange, because a screen where
/// everything is the action colour is a screen with no action colour.
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
            seam
            side(right, label: "B")

            TransportBar(duration: duration, playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal, Theme.spacing(.snug))
                .padding(.top, Theme.spacing(.hairline))

            controls
        }
        .background(Theme.backgroundPrimary)
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

    /// The line between the two ducks.
    ///
    /// A HAIRLINE IN THE PALETTE'S OWN SEPARATOR, NOT A `Divider`. The system's
    /// divider is a system grey drawn against a system background, and this app
    /// has neither: on Warm Cream it is the one line on the screen whose colour
    /// nothing here chose. `separator` is the token, and the stroke is one point
    /// because that is the thinnest line iOS draws crisply.
    private var seam: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: AuthoringMetric.hairlineStroke)
    }

    /// One of the two candidates, with the letter that names it.
    ///
    /// THE LETTER SITS ON A REAL SURFACE. It used to be set on
    /// `.thinMaterial` — a blur of whatever the 3D stage happened to be
    /// rendering behind it that frame, which is to say a letter whose contrast
    /// was a different number every time the duck moved. `surfacePrimary` is one
    /// of the four grounds `PaletteTests` proves every text token against at
    /// 4.5:1, so an A stays an A over a bright floor and over a dark duck.
    ///
    /// NOT MONOSPACED ANY MORE. "A" is a name and names do not change; tabular
    /// figures on one tell the reader to watch something that is never going to
    /// move, which is the rule `TelemetryRow` exists to state.
    private func side(_ motion: IntentDraft, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            DuckStage(pose: StagePose(jointAngles: motion.pose(at: playhead),
                                      root: StagePose.home.root),
                      environment: scene?.environment ?? .bareFloor,
                      props: scene?.props ?? [],
                      orbit: $orbit)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.spacing(.tight))
                .padding(.vertical, Theme.spacing(.hairline))
                .background(Capsule().fill(Theme.surfacePrimary))
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: AuthoringMetric.hairlineStroke))
                .padding(Theme.spacing(.tight))
                // The duck below is the answer; this only says which of the two
                // it is, and the buttons underneath already say A and B.
                .accessibilityHidden(true)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: Theme.spacing(.snug)) {
            // WHAT IS ACTUALLY DIFFERENT BETWEEN THEM. Without this the person
            // is asked to spot the difference as well as judge it, and a
            // comparison somebody cannot make reliably is worse than none.
            Text("Only \(search.knob.title.lowercased()) differs — it \(search.knob.effect).")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.spacing(.snug))

            HStack(spacing: Theme.spacing(.tight)) {
                Button { answer(.left) } label: {
                    Text("A is better").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .accessibilityHint(Text("Keeps the first duck's setting and asks again."))
                Button { answer(.right) } label: {
                    Text("B is better").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .accessibilityHint(Text("Keeps the second duck's setting and asks again."))
            }
            .padding(.horizontal, Theme.spacing(.snug))

            // A FIRST-CLASS ANSWER, NOT AN ESCAPE HATCH, and it is the same
            // size and the same width as the other two. Forcing a choice
            // between two things somebody cannot tell apart manufactures
            // signal, and the search treats this as information: it moves
            // nothing and steps smaller.
            Button { answer(.cannotTell) } label: {
                Text("Too close to call").frame(maxWidth: .infinity)
            }
            .buttonStyle(AuthoringActionStyle())
            .accessibilityHint(Text("Moves nothing and narrows the next pair."))
            .padding(.horizontal, Theme.spacing(.snug))

            Text(search.standing)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.spacing(.snug))
                .padding(.bottom, Theme.spacing(.tight))
        }
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundPrimary)
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
