import SwiftUI
import DuckKit
import StudioKit

/// Trick run: play the duck's moves against the odds they actually have.
///
/// THE ODDS ON SCREEN ARE THE ODDS IN THE FILE. Every move here carries a
/// success rate from sixteen randomised MuJoCo rollouts under Pollen's own
/// randomisation, and the scoring is nothing but the inverse of that number: a
/// roulade lands sixteen times out of sixteen and pays one, a headspin lands
/// once and pays sixteen. No balance pass, no designer's guess — which is the
/// only kind of trick game this app could honestly ship.
///
/// WHAT THE ANIMATION CAN AND CANNOT SHOW. There is exactly ONE recording of
/// each move and it is a successful one, so a missed attempt plays the same
/// clip as a landed one. That is said on screen rather than papered over with
/// an invented stumble: this app does not have a recording of the duck failing,
/// and drawing one would be the first fabricated motion in the corpus.
///
/// THE SCORE IS A `TelemetryRow` AND THE CARD IS A LIST OF THEM. A score, a
/// combo and a landed-of-attempted count are three numbers that change, set
/// beside three labels that do not, which is the one thing that component is
/// for — and stacked rather than truncated at an accessibility size, where a
/// large title and a caption used to fight for the same width.
struct TrickRunView: View {
    @ObservedObject var model: GhostDuckModel

    @State private var run: TrickRun?
    @State private var last: TrickRun.Attempt?

    var body: some View {
        List {
            if let failure = oddsFailure {
                Section {
                    // NOT A REFUSAL AND NOT AN ERROR. Nothing said no: either a
                    // file did not load or the duck is not on the floor yet, and
                    // both are things that stop being true. `Theme.warning` is
                    // the token for that, and the triangle and the sentence are
                    // what carry it for anybody who cannot see the colour —
                    // `.orange` was a raw literal, 2.30:1 on cream, which is the
                    // one contrast this palette refuses to set words in.
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            } else if let run {
                Section {
                    TelemetryRow(label: "Score", value: "\(run.score)")
                    TelemetryRow(label: "Landed",
                                 value: "\(run.landed) of \(run.attempts.count)")
                    if run.combo > 1 {
                        // A COMBO IS A NUMBER THAT CHANGES, so it is a row like
                        // the two above it rather than a large orange glyph in
                        // the corner. Orange on this screen now means one thing
                        // — a control that moves the duck — which is the rule
                        // `DriveView` states and the reason the multiplier lost
                        // it.
                        TelemetryRow(label: "Combo", value: "×\(run.combo)")
                    }
                    if let last {
                        // THE WORD IS THE STATE, AND THE COLOUR AGREES WITH IT.
                        // "landed" and "missed" are already in the sentence and
                        // in the symbol; the token behind them is `success` or
                        // `warning` rather than `.green`/`.orange`, so the pair
                        // is one the contrast tests have seen.
                        Label(last.landed
                              ? "\(last.trick.name) landed — \(last.scored) points"
                              : "\(last.trick.name) missed. Combo lost.",
                              systemImage: last.landed ? "checkmark.seal" : "xmark.circle")
                            .font(.footnote)
                            .foregroundStyle(last.landed ? Theme.success : Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("This run")
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    ForEach(run.tricks) { trick in
                        Button {
                            attempt(trick)
                        } label: {
                            row(trick)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.isPlaced || model.trick != nil
                                  || model.intents[trick.id] == nil)
                    }
                } header: {
                    Text("The card — hardest first")
                } footer: {
                    VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                        Text("A trick pays the inverse of what it actually lands, measured over sixteen randomised rollouts on the real plant. The headspin is worth sixteen because it lands once in sixteen. Moves that never land on flat ground — the stair climbs — are not on the card at all, because they need a step this floor does not have.")
                        Text(TrickRun.whatThisIsMadeOf)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    // THE ROLE STAYS AND THE COLOUR COMES FROM THE PALETTE.
                    // `.destructive` is what tells VoiceOver and the system what
                    // this is, and it is worth keeping — a run is lost here. Its
                    // red, though, is UIKit's, resolved against whatever is
                    // behind it; `Theme.critical` is the app's refusal colour and
                    // is proved at 4.5:1 on every ground this app sets words on.
                    Button(role: .destructive) { start() } label: {
                        Text("Start again").foregroundStyle(Theme.critical)
                    }
                    .accessibilityHint(Text("Clears the score and deals the card again."))
                } footer: {
                    Text("There is one recording of each move and it is a successful one, so a missed attempt plays the same clip as a landed one. This app has no recording of the duck failing, and drawing one would be the first invented motion in the corpus.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
        // GREY, and every row keeps a real `surfacePrimary` card under its
        // words — the arrangement `Theme.backgroundSecondary` documents as the
        // only correct one, since the inks fall short of 4.5:1 on that ground
        // and clear it on a card.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Trick run")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if run == nil { start() } }
    }

    /// One trick on the card: what it is, what it actually lands, and what it
    /// pays.
    ///
    /// IT IS A CONTROL THAT MOVES THE DUCK, AND IT IS SIZED LIKE ONE — `.snug`
    /// above and below two lines of text is a row well past the sixty points
    /// this design system asks of anything that moves a machine, taken off the
    /// spacing scale so that the floor stays written down in exactly one place.
    /// It is NOT drawn as an action capsule: the multiplier, the name and the
    /// measured criterion are three different things to read, and a single
    /// headline-weight label on Duck Orange would flatten all three.
    ///
    /// THE MULTIPLIER IS THE ONE NUMBER THAT NEVER MOVES. A trick's odds come
    /// out of a file of sixteen rollouts and stay put for the life of the
    /// build, so it is NOT set in tabular figures — the rule the design system
    /// states is that monospace claims "this will change", and this does not.
    /// `.headline.monospacedDigit()` used to say the opposite.
    private func row(_ trick: TrickRun.Trick) -> some View {
        let playable = model.isPlaced && model.trick == nil
            && model.intents[trick.id] != nil
        return HStack(alignment: .top, spacing: Theme.spacing(.snug)) {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(trick.name)
                    .font(.subheadline)
                    .foregroundStyle(playable ? Theme.textPrimary : Theme.textSecondary)
                // NO LINE LIMIT. `criterion` is the measured sentence that says
                // what "landed" MEANT for this move, and two lines of caption2
                // holds it at the default text size and cuts it in half at AX5
                // — which hides the evidence from the person who enlarged the
                // type in order to read it. It wraps instead.
                Text("landed \(trick.achieves) of \(trick.rollouts) — " + trick.criterion)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.spacing(.tight))
            Text("\(trick.score)×")
                .font(.headline)
                // THE HARD ONES ARE THE MEASURED ONES. Teal is what a machine
                // measured, which is exactly what a multiplier is here — the
                // inverse of a success rate from sixteen rollouts — so a payout
                // worth noticing takes the provenance colour rather than an
                // orange that would claim it moves something.
                .foregroundStyle(trick.score >= TrickMetric.worthNoticing
                                 ? Theme.measured : Theme.textSecondary)
        }
        .padding(.vertical, Theme.spacing(.snug))
        .contentShape(Rectangle())
    }

    private var oddsFailure: String? {
        if model.success == nil {
            return "The measured success rates did not load, so there are no odds — and without odds there is no game."
        }
        if !model.isPlaced { return "Place the duck on the floor first, then pick a trick." }
        return nil
    }

    private func start() {
        guard let success = model.success else { return }
        let measured = success.intents.mapValues {
            TrickRun.Measurement(achieves: $0.achieves, rollouts: $0.rollouts,
                                 criterion: $0.criterion)
        }
        // Seeded from the clock ONCE, so a run varies between sittings while
        // staying reproducible within one — the engine itself never reads a
        // clock, which is what makes it testable.
        run = TrickRun(measured: measured, seed: UInt64(Date().timeIntervalSince1970))
        last = nil
    }

    private func attempt(_ trick: TrickRun.Trick) {
        guard var current = run, let clip = model.intents[trick.id] else { return }
        let outcome = current.attempt(trick.id)
        run = current
        last = outcome
        model.trick = clip
        model.trickStarted = CACurrentMediaTime()
    }
}

/// The one number this screen writes down for itself.
///
/// IT IS NOT A COLOUR AND NOT A CONTRAST — a ratio is a fact and lives in
/// `Palette`, where a test runs the formula over it. Where a payout stops being
/// ordinary is a judgement about a card, and it was already being made in this
/// file; it is written down here so that it is visible rather than buried in a
/// ternary.
private enum TrickMetric {
    /// The multiplier at which a trick is worth picking out of the list. Eight
    /// is half the headspin's sixteen — the hardest move in the corpus — which
    /// is where the card stops being ordinary.
    static let worthNoticing = 8
}
