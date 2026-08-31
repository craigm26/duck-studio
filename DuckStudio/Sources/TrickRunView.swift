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
struct TrickRunView: View {
    @ObservedObject var model: GhostDuckModel

    @State private var run: TrickRun?
    @State private var last: TrickRun.Attempt?

    var body: some View {
        List {
            if let failure = oddsFailure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } else if let run {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(run.score)").font(.largeTitle.weight(.semibold))
                            Text("\(run.landed) of \(run.attempts.count) landed")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if run.combo > 1 {
                            Text("×\(run.combo)")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    if let last {
                        Label(last.landed
                              ? "\(last.trick.name) landed — \(last.scored) points"
                              : "\(last.trick.name) missed. Combo lost.",
                              systemImage: last.landed ? "checkmark.seal" : "xmark.circle")
                            .font(.footnote)
                            .foregroundStyle(last.landed ? Color.green : Color.orange)
                    }
                } header: {
                    Text("This run")
                }

                Section {
                    ForEach(run.tricks) { trick in
                        Button {
                            attempt(trick)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trick.name).font(.subheadline)
                                    Text("landed \(trick.achieves) of \(trick.rollouts) — "
                                         + trick.criterion)
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text("\(trick.score)×")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(trick.score >= 8 ? Color.orange : .secondary)
                            }
                        }
                        .disabled(!model.isPlaced || model.trick != nil
                                  || model.intents[trick.id] == nil)
                    }
                } header: {
                    Text("The card — hardest first")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A trick pays the inverse of what it actually lands, measured over sixteen randomised rollouts on the real plant. The headspin is worth sixteen because it lands once in sixteen. Moves that never land on flat ground — the stair climbs — are not on the card at all, because they need a step this floor does not have.")
                        Text(TrickRun.whatThisIsMadeOf)
                    }
                }

                Section {
                    Button("Start again", role: .destructive) { start() }
                } footer: {
                    Text("There is one recording of each move and it is a successful one, so a missed attempt plays the same clip as a landed one. This app has no recording of the duck failing, and drawing one would be the first invented motion in the corpus.")
                }
            }
        }
        .navigationTitle("Trick run")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if run == nil { start() } }
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
