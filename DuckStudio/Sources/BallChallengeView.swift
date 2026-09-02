import SwiftUI
import DuckKit
import StudioKit

/// The Ball Challenge: get the duck to reach a ball and move it, from wherever
/// the ball is put down, and stay standing.
///
/// IT IS THE STAIRS SCREEN, ONE CHALLENGE ALONG, AND THAT IS DELIBERATE. The
/// same loop is the point — open a published entrant, change a keyframe's servo
/// values in the editor, score the edited version on the same fourteen cells,
/// keep what helps — so the sections are in the same order, the run object has
/// the same shape, and a person who has done this once on the stairs does not
/// have to learn a second vocabulary. What differs is what the bench is asked:
/// `/chase` instead of `/climb`, an entrant instead of an intent, and a ball.
///
/// TWO KINDS OF ENTRANT, AND ONE OF THEM CANNOT BE EDITED. An authored move is
/// keyframes and opens in the editor; a policy is a trained network under a
/// command schedule and has no authored pose in it to change. The three policy
/// rows are scored and played here exactly like the move, and where the move
/// gets "Open in the editor" they get `BallChallenge.policyNotEditable` — a
/// sentence, not a greyed-out button. `Entrant.toDraft` throws for a policy,
/// which is the second lock behind the first.
///
/// NOTHING ON THIS SCREEN AGGREGATES ANYTHING. Fourteen answers come back and
/// `BallChallenge.Score` counts them — nine core, five extended, kept apart
/// because `chase_robust` keeps them apart. A screen that counted its own cells
/// would be a second scorer, and the whole value of a published table is that
/// there is one.
///
/// AND EVERY CLAIM IS THE KIT'S SENTENCE. The criterion, the ball caveat, the
/// bearing convention, the not-yet for a bench with no `/chase`, the verdict,
/// the change sentence, the real-duck caveat and every submission sentence are
/// `static let`s with tests on them. What this file writes for itself are the
/// words on controls — "Score", "Submit", "Play it" — which are labels rather
/// than claims.
struct BallChallengeView: View {
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.spacing(.snug)) {
                    Text(BallChallenge.oneSentence)
                    Text(BallChallenge.criterionSentence)
                        .foregroundStyle(Theme.textSecondary)
                    // THE BEARING SIGN IS PART OF THE GRID. A table of ±20°
                    // with no stated sign is a table nobody can reproduce, so
                    // the convention is on the first screen and not in a
                    // footnote three taps in.
                    Text(BallChallenge.bearingConvention)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                // THE CAVEAT THE STAIRS CHALLENGE DOES NOT HAVE, and the one
                // that has to travel with every absolute number below: the
                // reward terms come from a config trained against a different
                // ball from the one in this plant.
                Label(BallChallenge.ballCaveat, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: "The challenge")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // ONE LINE ABOVE THE TABLE, AND IT IS THE KIT'S. Today it says
                // four controls and no entries; a build whose leaderboard was
                // empty would say so instead, rather than drawing an empty
                // table that looks like a table nobody has filled in.
                Text(BallChallenge.leaderboard.isEmpty
                     ? BallChallenge.leaderboardPending
                     : BallChallenge.leaderboardSaid)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(BallChallenge.entries) { row in
                    BallRowLabel(row: row)
                }
            } header: {
                SectionHeading(text: "Leaderboard")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(BallChallenge.controls) { control in
                    NavigationLink {
                        BallEntrantView(control: control, drafts: drafts, scenes: scenes,
                                        models: models, benches: benches)
                    } label: {
                        BallControlLabel(control: control)
                    }
                }
            } header: {
                // THE CONTROLS ARE THE WHOLE LIST TODAY AND THEY ARE LABELLED
                // AS CONTROLS. Standing still scores nothing, both of Pollen's
                // kick policies score nothing, and walking straight ahead takes
                // four of nine — which is the line somebody is being asked to
                // cross. A board that hid its floor would be a board nobody
                // could calibrate.
                SectionHeading(text: "Reference controls")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Link(destination: BallChallenge.datasetURL) {
                    Label("The dataset on Hugging Face", systemImage: "arrow.up.right.square")
                }
                Link(destination: BallChallenge.harnessURL) {
                    Label("The harness on GitHub", systemImage: "arrow.up.right.square")
                }
            } header: {
                SectionHeading(text: "Where this comes from")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(BallChallenge.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A published entry, if there is ever one.
private struct BallRowLabel: View {
    let row: BallChallenge.Row

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing(.snug)) {
            Text(row.rankSaid)
                .font(.subheadline.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: Theme.spacing(.loose), alignment: .trailing)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(row.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(row.entrantName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textTertiary)
                Text(row.scoreSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.spacing(.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// One bundled entrant: who it is, what it is, and what it measured.
private struct BallControlLabel: View {
    let control: BallChallenge.Control

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(control.who)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(control.name)
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.textTertiary)
            // THE KIND IS IN THE SUBTITLE AND THAT IS HOW A ROW SAYS IT CANNOT
            // BE EDITED before somebody taps into it. "policy · 4 s ·
            // alpha_walking.onnx · vx 0.5" is the whole entrant in one line.
            Text(control.entrant.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let row = control.row {
                Text(row.scoreSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - one entrant

/// A bundled entrant: what it is, how to open it, how to score it here, and how
/// to send the result somewhere.
///
/// THE ORDER IS THE ORDER OF THE WORK, the same order `StairsMoveView` uses:
/// what this is, then edit it, then score it, then submit it, then play it.
/// Submit sits after Score and is a stated not-yet until a score exists on this
/// device, because a submission IS the fourteen cells and the plant they came
/// out of — there is nothing to send before they exist.
struct BallEntrantView: View {
    let control: BallChallenge.Control
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    // @StateObject AND NOT @State, for `TuneView`'s reason: the run publishes
    // fourteen times and a `@State` reference would subscribe to none of them,
    // so the progress row would sit on cell one for the whole run.
    @StateObject private var run = BallRun()

    /// The draft `open()` saved, so the edited version can be found again and
    /// scored on the same cells.
    @State private var editedDraftID: UUID?
    @State private var editing: IntentDraft?
    @State private var submitting: BallSubmissionBox?
    @State private var failure: String?

    private var entrant: BallChallenge.Entrant { control.entrant }

    var body: some View {
        Form {
            whatThisIs
            prediction
            editor
            edited
            scoring
            terms
            submit
            duck
            if let failure {
                Section {
                    Label(failure, systemImage: "xmark.octagon")
                        .font(.footnote)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionHeading(text: "That did not work")
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(entrant.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // ASK THE BENCH FOR ITS GRID BEFORE ANYTHING IS SCORED. Two facts
            // arrive at once: whether it has `/chase` at all — which is what
            // the not-yet is keyed on — and which fourteen cells it scores, so
            // a bench on a different grid can be SAID to be on a different grid
            // rather than silently compared with the published table.
            await run.probe(benches: benches)
            Haptic.prepare()
        }
        // A SCORE IS FOURTEEN CELLS OF ONE ENTRANT ON ONE BENCH, and the bench
        // can be changed from under it — in Settings, on another tab, while
        // this screen is still on the stack. That change puts the score down
        // and asks the new bench whether it can score at all.
        .onChange(of: benches.selectedID) { _, _ in
            run.forget()
            Task { await run.probe(benches: benches) }
        }
        .sheet(item: $editing) { opened in
            NavigationStack {
                // LOOKED UP FRESH IN THE STORE, the arrangement `IntentListView`
                // arrived at the hard way: the editor must open on what is
                // actually stored, and a failed lookup must end in a sentence
                // rather than in a blank, toolbar-less stack nobody can leave.
                if let current = drafts.drafts.first(where: { $0.id == opened.id }) {
                    IntentAuthorView(
                        draft: current, scenes: scenes, models: models,
                        isNew: false,
                        onSave: { drafts.save($0) },
                        onDiscard: { doomed in
                            editing = nil
                            drafts.delete(doomed)
                        })
                        .onDisappear { drafts.flush() }
                } else {
                    ContentUnavailableView {
                        Label("That motion is not here", systemImage: "questionmark.square.dashed")
                    } description: {
                        Text("The draft was taken out of the store while its editor was opening. "
                           + "Open it from the challenge again — nothing was lost.")
                    } actions: {
                        Button("Close") { editing = nil }
                    }
                }
            }
        }
        .sheet(item: $submitting) { box in
            BallSubmitView(submission: box.submission)
        }
    }

    // MARK: - what this is

    @ViewBuilder private var whatThisIs: some View {
        Section {
            TelemetryRow(label: "Entrant", value: entrant.kind.said)
            TelemetryRow(label: "Episode", value: BallChallenge.secondsSaid(entrant.seconds))
            if let policy = entrant.policy {
                TelemetryRow(label: "Network", value: policy)
            }
            if let command = entrant.commandSaid {
                TelemetryRow(label: "Command", value: command)
            }
            if let row = control.row {
                TelemetryRow(label: "Hash", value: row.hash)
                TelemetryRow(label: "Published", value: row.scoreSaid)
                TelemetryRow(label: "Scored", value: row.scored)
                Text(row.note)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // THE PROVENANCE IS THE DRAFT'S OWN SENTENCE for a move, which is
            // the one that will travel with it if it is edited and published.
            // A policy has no draft and therefore no provenance line: it gets
            // the sentence that says why, in the editor section below.
            if let provenance = try? BallChallenge.draft(for: control).provenance {
                Text(provenance)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "This entrant")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - what it was expected to do

    /// THE PREDICTION WAS WRITTEN BEFORE THE RUN AND IT IS ON SCREEN WITH THE
    /// RESULT BESIDE IT. Four control rows are the only reason anybody should
    /// believe the criterion measures chasing; a prediction printed after the
    /// numbers arrived would be a caption.
    @ViewBuilder private var prediction: some View {
        Section {
            Text(control.expected)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(control.establishes)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // THE KIT'S VERDICT, BOTH HALVES WHEN THEY DIFFER. A seal over a
            // count that landed in its range would claim a shape the cells
            // disprove; the sentence says what held and what did not.
            if let held = control.predictionHeld, let said = control.predictionSaid {
                Label(said, systemImage: held ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(held ? Theme.success : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "What it was expected to do")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the editor

    @ViewBuilder private var editor: some View {
        Section {
            if entrant.isEditable {
                Button("Open in the editor") { open() }
                    .buttonStyle(.primaryAction)
                Text(BallChallenge.editorNote)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // NOT A DISABLED BUTTON. There are no keyframes in a policy, so
                // there is nothing for an editor to open, and the kit's
                // sentence says exactly that. It is scored and played on this
                // screen like everything else.
                Label(BallChallenge.policyNotEditable, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "Edit it")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the edited version: edit, score, keep

    /// THE LOOP THE CHALLENGE IS FOR. A person changes a keyframe's servo
    /// values in the editor, scores the edited version on the same fourteen
    /// cells, and keeps or puts back. The draft is looked up in the store by
    /// the id `open()` saved; everything in the entrant that is not keyframes —
    /// its kind, its seconds, its blend — travels with it untouched
    /// (`Entrant.applying(draft:)`).
    @ViewBuilder private var edited: some View {
        if entrant.isEditable {
            Section {
                if let draft = drafts.drafts.first(where: { $0.id == editedDraftID }) {
                    if BallChallenge.Entrant.movedMouth(in: draft) {
                        Label(BallChallenge.mouthDroppedNote, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if run.hasProbed, run.notYet == nil, run.unreachable == nil {
                        Button {
                            Task { await run.scoreEdited(entrant, draft: draft, benches: benches) }
                        } label: {
                            HStack(spacing: Theme.spacing(.tight)) {
                                Text("Score your edited version").frame(maxWidth: .infinity)
                                if run.running { ProgressView() }
                            }
                        }
                        .buttonStyle(.primaryAction)
                        .disabled(run.running)
                    }
                    if let score = run.score, let previous = run.previousScore, run.scoredEdited {
                        Text(score.change(from: previous))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(BallChallenge.editedVersionNote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(BallChallenge.editedNotFoundNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeading(text: "Your edited version")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    /// Put the published entrant in the draft store and open it.
    ///
    /// SAVED BEFORE THE SHEET IS ASKED FOR, in that order and not the other:
    /// the editor looks the draft up in the store by id, so a sheet presented
    /// first would present the empty branch for one pass.
    private func open() {
        do {
            let draft = try BallChallenge.draft(for: control)
            drafts.save(draft)
            editedDraftID = draft.id
            editing = draft
        } catch {
            failure = BallEntrantView.message(error)
        }
    }

    // MARK: - scoring

    @ViewBuilder private var scoring: some View {
        Section {
            if let bench = benches.selected {
                TelemetryRow(label: "Bench", value: bench.name)
            }

            if run.probing {
                ProgressView()
            } else if let unreachable = run.unreachable {
                // A BENCH THAT DID NOT ANSWER IS NOT A BENCH THAT CANNOT
                // SCORE. It gets the failure's own words and a way to ask
                // again, rather than the not-yet — which would be this app
                // telling somebody to update software on a machine it has not
                // heard a syllable from.
                Label(unreachable, systemImage: "xmark.octagon")
                    .font(.footnote)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ask this bench again") {
                    Task { await run.probe(benches: benches) }
                }
                .buttonStyle(.primaryAction)
            } else if let notYet = run.notYet {
                // THE NOT-YET, WHICH NAMES THE BENCH AND WHAT TO UPDATE. No
                // Score button is drawn beside it: a control that cannot work
                // is not offered greyed out, it is replaced by the sentence
                // that says what to do instead.
                Label(notYet, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if run.hasProbed {
                Button {
                    Task { await run.scoreEveryCell(entrant, benches: benches) }
                } label: {
                    HStack(spacing: Theme.spacing(.tight)) {
                        Text("Score on \(benches.selected?.name ?? "this bench")")
                            .frame(maxWidth: .infinity)
                        if run.running { ProgressView() }
                    }
                }
                .buttonStyle(.primaryAction)
                .disabled(run.running)
            }

            if let progress = run.progress, run.score == nil {
                Text(progress.said)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textSecondary)
            }
            // INDEXED, NOT `id: \.self`. Fourteen cells refused by one bench
            // for one reason produce fourteen IDENTICAL strings, and a ForEach
            // keyed on the value itself would draw one of them and silently
            // drop the other thirteen — a partial failure that looks like a
            // single failure.
            ForEach(Array((run.progress?.failures ?? []).enumerated()), id: \.offset) { _, why in
                Label(why, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let score = run.score {
                VStack(alignment: .leading, spacing: Theme.spacing(.snug)) {
                    Text(score.verdict)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(score.line)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                    Text(score.factsSaid)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(score.extendedSaid)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if run.onPublishedGrid {
                        Text(score.sameCriterion)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let row = control.row {
                        Text(score.against(row))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(Array(score.problems.enumerated()), id: \.offset) { _, problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                    if !run.onPublishedGrid {
                        Label(BallChallenge.Grid.differentGridNote,
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "Score it")
        } footer: {
            // WHICH GRID IS ABOUT TO BE USED, BEFORE IT IS USED, and what its
            // two halves are for. The bench's answer wins and the pinned copy
            // fills its silence; all three sentences are the kit's.
            VStack(alignment: .leading, spacing: Theme.spacing(.snug)) {
                Text(run.gridNote)
                Text(BallChallenge.Grid.coreNote)
                Text(BallChallenge.Grid.extendedNote)
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the reward terms

    /// The nine terms the bench could compute, the ones it refused by name, and
    /// the sentence that says none of them is the verdict.
    ///
    /// THE REFUSALS ARE DRAWN EVEN WHEN EVERY CELL PASSED. Three named terms
    /// with reasons are what makes the nine reported ones a transcription of
    /// Pollen's config rather than a selection from it — the same posture
    /// `/tune` takes, and the reason a term nobody can compute here is never
    /// quietly replaced with a zero.
    @ViewBuilder private var terms: some View {
        if let score = run.score, !score.terms.isEmpty {
            Section {
                ForEach(score.terms) { term in
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        TelemetryRow(label: term.term, value: Self.said(term.value))
                        Text("weight \(term.weightSaid) · weighted \(Self.said(term.weighted))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.textTertiary)
                        if let reference = term.reference {
                            Text(reference)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(score.refused) { refusal in
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        Text(refusal.term)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.refused)
                        Text(refusal.reason)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(BallChallenge.actionRateSaid(score.actionRateSource))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat = BallChallenge.rewardCaveat(forPolicy: entrant.policy) {
                    Label(caveat, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeading(text: "The reward terms")
            } footer: {
                VStack(alignment: .leading, spacing: Theme.spacing(.snug)) {
                    // THE TERMS ARE REPORTED AND THEY ARE NOT THE VERDICT, and
                    // that sentence sits with them rather than three sections
                    // away, because a person reading nine weighted numbers is
                    // entitled to know which of them the table is sorted on.
                    Text(BallChallenge.whyNotTheReward)
                    Text(BallChallenge.ballCaveat)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    /// A term's number, formatted. FORMATTING AND NOT ARITHMETIC: the value is
    /// the bench's, the mean across cells is the kit's, and this decides how
    /// many digits fit on a phone.
    static func said(_ value: Double) -> String { String(format: "%.4f", value) }

    // MARK: - submit

    @ViewBuilder private var submit: some View {
        Section {
            if let score = run.score, score.isPublishable, run.onPublishedGrid {
                Button("Submit") { submitting = box(score) }
                    .buttonStyle(.primaryAction)
                Text(BallChallenge.Submission.whatIsSent)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let score = run.score {
                // A SCORE THAT IS NOT COMPARABLE IS NOT OFFERED FOR SUBMISSION,
                // and the reasons are the kit's, drawn where the button was.
                ForEach(Array(score.problems.enumerated()), id: \.offset) { _, problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !run.onPublishedGrid {
                    Label(BallChallenge.Grid.differentGridNote, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // NOT A DISABLED BUTTON. There is no bundle, so there is
                // nothing for a button to do, and the kit's sentence says
                // exactly what has to happen first.
                Text(BallChallenge.Submission.notScoredYet)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: "Submit")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The submission, wrapped so a `.sheet(item:)` can present it.
    ///
    /// THE BENCH'S IDENTITY GOES IN FROM THE RUN AND NOT FROM THE STORE. The
    /// bench is chosen in Settings, on another tab, while this screen is still
    /// on the stack: score on the phone, switch to the Pi, tap Submit, and a
    /// bundle assembled from `benches.selected` would carry the Pi's name over
    /// the phone's fourteen answers — a wrong provenance, written by the app,
    /// in the one file whose entire job is provenance.
    private func box(_ score: BallChallenge.Score) -> BallSubmissionBox {
        BallSubmissionBox(submission: BallChallenge.Submission(
            entrant: entrant, score: score,
            benchName: run.scoredBenchName ?? "an unnamed bench",
            benchAddress: run.scoredBenchAddress,
            onPublishedGrid: run.onPublishedGrid,
            row: control.row,
            appVersion: AppVersion.said,
            date: Date()))
    }

    // MARK: - the duck

    @ViewBuilder private var duck: some View {
        Section {
            Button {
                Task { await run.play(entrant, benches: benches) }
            } label: {
                HStack(spacing: Theme.spacing(.tight)) {
                    Text("Run it in physics on \(benches.selected?.name ?? "this bench")")
                        .frame(maxWidth: .infinity)
                    if run.performing { ProgressView() }
                }
            }
            // `primaryActionMoves` — THIS IS THE ONE BUTTON ON THE SCREEN THAT
            // MAKES SOMETHING MOVE. Scoring reads physics; this plays the
            // entrant, and the design system reserves a separate style for an
            // action with a body attached to it.
            .buttonStyle(.primaryActionMoves)
            .disabled(run.performing)
            if let told = run.performed {
                Text(told)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // THE CAVEAT IS BESIDE THE BUTTON AND NOT BEHIND IT. It is the
            // sentence that keeps "run it" from reading as a claim that any of
            // this has been on hardware, which none of it has.
            Label(BallChallenge.playNote, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Label(BallChallenge.realDuckCaveat, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "Play it")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Every refusal in this screen, asked for its own words.
    ///
    /// `localizedDescription` IS NOT AN OPTION for any of these: a kit refusal
    /// has no localisation and renders as "(StudioKit.DuckBench.Refusal error
    /// 1.)". The ladder is `StairsMoveView`'s with the ball entrant's own
    /// refusals — including `notEditable`, whose message IS
    /// `BallChallenge.policyNotEditable` — added at the top.
    static func message(_ error: Error) -> String {
        switch error {
        case let refusal as BallChallenge.Entrant.Refusal: return refusal.message
        case let refusal as StairsChallenge.Move.Refusal: return refusal.message
        case let refusal as HarnessJSON.ParseError: return refusal.message
        case let refusal as DuckBench.Refusal: return refusal.message
        case let refusal as DuckBench.ReadError: return refusal.message
        case let refusal as BenchEndpoint.Refusal: return refusal.message
        case let refusal as HuggingFacePublish.Refusal: return refusal.message
        case let refusal as ExportFile.Failure: return refusal.message
        default: return error.localizedDescription
        }
    }
}

/// A submission on its way to a sheet.
struct BallSubmissionBox: Identifiable {
    let submission: BallChallenge.Submission
    var id: String { submission.filename }
}

// MARK: - the run

/// Fourteen cells, one request each, and the two facts a screen needs before it
/// offers to start: whether this bench has `/chase`, and which grid it scores.
///
/// ONE REQUEST PER CELL IS THE CONTRACT AND NOT AN IMPLEMENTATION CHOICE.
/// `/chase` scores ONE cell of ONE entrant: it places the ball for that cell,
/// runs the episode and puts the world back, which is what keeps `/state`,
/// `/perform` and `/tune` answering exactly what they answered before the
/// endpoint existed. A client that batched them would be asking for an endpoint
/// that does not exist.
///
/// THEY GO IN ORDER AND NOT IN PARALLEL. The bench serialises a chase behind
/// its other lanes — a cell borrows the model, not a copy of it — so fourteen
/// concurrent requests would queue anyway, and would arrive back in an order
/// that makes the progress row a lie.
@MainActor
final class BallRun: ObservableObject {
    @Published private(set) var probing = false
    /// True once the bench has answered the grid probe at least once, so no
    /// Score button is drawn before we know whether this bench can score.
    @Published private(set) var hasProbed = false
    @Published private(set) var running = false
    @Published private(set) var performing = false
    /// The score a new run replaced, for the edit-score-keep sentence.
    @Published private(set) var previousScore: BallChallenge.Score?
    /// Whether the current score is of the edited draft rather than the
    /// bundled entrant.
    @Published private(set) var scoredEdited = false

    /// The cells this run will use: the bench's, or the pinned fallback.
    @Published private(set) var grid: [DuckBench.ChaseCell] = BallChallenge.Grid.fallback
    /// True while the grid is the app's own copy because the bench has not
    /// answered with one.
    @Published private(set) var gridIsFallback = true
    /// The kit's not-yet, when this bench has no `/chase`.
    @Published private(set) var notYet: String?
    /// The bench did not answer at all, in whatever words the failure had.
    /// NOT the not-yet: see `probe`.
    @Published private(set) var unreachable: String?

    @Published private(set) var progress: BallChallenge.ScoreProgress?
    @Published private(set) var score: BallChallenge.Score?
    /// What the play said, in `Pipeline.BenchOutcome`'s own words.
    @Published private(set) var performed: String?

    /// WHICH BENCH THESE CELLS CAME OFF, CAPTURED WHEN THEY WERE SCORED AND NOT
    /// READ BACK OFF THE STORE AT SUBMISSION TIME. See `BallEntrantView.box`.
    @Published private(set) var scoredBenchName: String?
    @Published private(set) var scoredBenchAddress: String?

    private var plantDigest: String?

    /// Put down a score that is no longer about what the screen is asking.
    func forget() {
        score = nil
        progress = nil
        performed = nil
        scoredBenchName = nil
        scoredBenchAddress = nil
        // A SCORE PUT DOWN BECAUSE THE BENCH CHANGED IS NOT A BASELINE. Keeping
        // it would let the edit-score-keep sentence attribute a cross-bench
        // difference to the edit.
        previousScore = nil
        scoredEdited = false
    }

    /// Whether the grid actually scored is the one every published number was
    /// produced on. Read by the screen and written into the bundle.
    var onPublishedGrid: Bool { BallChallenge.Grid.isPublishedGrid(grid) }

    var gridNote: String {
        gridIsFallback ? BallChallenge.Grid.fallbackNote
                       : BallChallenge.sameCriterion(plantDigest: plantDigest)
    }

    // MARK: - can this bench score at all

    /// Ask the bench for its grid, which is also how we find out it has one.
    ///
    /// A BENCH WITHOUT `/chase` ANSWERS SOMETHING, and what it answers is the
    /// point: this app's own loopback server 404s an unknown path and an older
    /// Pi bench does the same, so what comes back is not JSON — while a bench
    /// that HAS the endpoint and no free ball in its scene says so in its own
    /// words with `chaseable: false`. Both end in the kit's not-yet, which
    /// names the bench and says what to update; neither is reported as a bench
    /// that is down.
    func probe(benches: BenchStore) async {
        probing = true
        defer { probing = false; hasProbed = true }
        notYet = nil
        let name = benches.selected?.name ?? "this bench"
        unreachable = nil
        grid = BallChallenge.Grid.fallback
        gridIsFallback = true

        // THE TWO CATCHES ARE SPLIT AND THE SPLIT IS THE HONESTY. A bench that
        // did not answer at all and a bench that answered something which is
        // not a grid are different facts, and the kit's not-yet makes a CLAIM
        // about the second — "this bench answers /health and /perform but not
        // the ball challenge". Printed over a bench that is simply off, that
        // sentence is a statement about a machine nobody has heard from.
        let data: Data
        do {
            let (address, token) = try Self.armed(benches)
            data = try await Self.ask(DuckBench.chaseGrid(address), token: token,
                                      seconds: Self.gridSeconds)
        } catch {
            unreachable = BallEntrantView.message(error)
            return
        }
        do {
            let answered = try DuckBench.readChaseGrid(data)
            grid = answered.cells.isEmpty ? BallChallenge.Grid.fallback : answered.cells
            gridIsFallback = answered.cells.isEmpty
            plantDigest = answered.plantDigest
            // A BENCH CAN HAVE THE ENDPOINT AND STILL NOT BE ABLE TO SCORE —
            // its scene has no free ball, or its actuators are not in joint
            // order. It says so with `chaseable: false`, and that is the same
            // not-yet as having no `/chase` at all: neither can produce a
            // comparable number here.
            if !answered.chaseable { notYet = BallChallenge.noChaseHere(bench: name) }
        } catch {
            // The bench answered and it was not a grid — an error body, a 404
            // page, an older build. That is the not-yet.
            notYet = BallChallenge.noChaseHere(bench: name)
        }
    }

    // MARK: - the fourteen

    func scoreEveryCell(_ entrant: BallChallenge.Entrant, benches: BenchStore) async {
        scoredEdited = false
        await scoreAll(entrant, benches: benches)
    }

    /// The edited draft, put back into the bundled entrant's own JSON and
    /// scored on the same cells. A draft the format cannot carry (the mouth, a
    /// bad width) is refused with the kit's sentence, not scored — and a policy
    /// never reaches here, because there is no editor behind it.
    func scoreEdited(_ entrant: BallChallenge.Entrant, draft: IntentDraft,
                     benches: BenchStore) async {
        let edited: BallChallenge.Entrant
        do { edited = try entrant.applying(draft: draft) } catch {
            progress = BallChallenge.ScoreProgress(grid: grid, done: [],
                                                   failures: [BallEntrantView.message(error)])
            return
        }
        scoredEdited = true
        await scoreAll(edited, benches: benches)
    }

    private func scoreAll(_ entrant: BallChallenge.Entrant, benches: BenchStore) async {
        running = true
        if let score { previousScore = score }
        score = nil
        scoredBenchName = benches.selected?.name
        scoredBenchAddress = benches.selected?.address
        defer { running = false }
        let cells = grid
        var done: [DuckBench.Chased] = []
        var failures: [String] = []
        progress = BallChallenge.ScoreProgress(grid: cells)
        do {
            let (address, token) = try Self.armed(benches)
            for cell in cells {
                let call = try DuckBench.chase(address, entrant: entrant, cell: cell)
                do {
                    let data = try await Self.ask(call, token: token, seconds: Self.cellSeconds)
                    done.append(try DuckBench.readChased(data))
                } catch {
                    // A CELL THAT FAILED IS NAMED AND THE RUN CONTINUES. The
                    // kit counts an unanswered cell as unanswered — `problems`
                    // says how many of fourteen came back — so abandoning the
                    // whole grid on one refusal would throw away thirteen real
                    // measurements to avoid printing one sentence.
                    failures.append(BallEntrantView.message(error))
                }
                progress = BallChallenge.ScoreProgress(grid: cells, done: done,
                                                       failures: failures)
            }
            score = BallChallenge.Score(cells: done)
            plantDigest = score?.plantDigest ?? plantDigest
            Haptic.finished()
        } catch {
            failures.append(BallEntrantView.message(error))
            progress = BallChallenge.ScoreProgress(grid: cells, done: done, failures: failures)
        }
    }

    // MARK: - playing it

    /// Play the entrant once, through the app's existing path for its kind.
    ///
    /// TWO KINDS, TWO ENDPOINTS, ONE SENTENCE BACK. An authored move goes to
    /// `/perform`, which is this app's only path for running a written track in
    /// real physics; a policy under a command schedule goes to `/measure` with
    /// ONE rollout, which is the same schedule shape `RemoteRunView` sends.
    /// Both answer `rollouts` and `achieves`, so both end in
    /// `Pipeline.BenchOutcome.told` and neither has a sentence written here.
    ///
    /// ONE ROLLOUT, NOT EIGHT. `/measure`'s default is a measurement — eight
    /// runs, because one that stays up proves very little — and this button is
    /// not a measurement. The score is the fourteen cells above; this is the
    /// entrant being played once so somebody can watch it.
    func play(_ entrant: BallChallenge.Entrant, benches: BenchStore) async {
        performing = true
        performed = nil
        defer { performing = false }
        do {
            let (address, token) = try Self.armed(benches)
            let call: DuckBench.Call
            if let policy = entrant.policy {
                call = try DuckBench.measure(address, policy: policy,
                                             seconds: entrant.seconds, rollouts: 1,
                                             schedule: entrant.schedule)
            } else {
                let draft = try entrant.toDraft()
                let track = draft.benchTrack
                guard track.count >= 2 else { throw DuckBench.Refusal.empty }
                call = try DuckBench.perform(address, keys: track,
                                             seconds: draft.duration + Self.settleSeconds,
                                             rollouts: 1)
            }
            let data = try await Self.ask(call, token: token, seconds: Self.performSeconds)
            performed = try DuckBench.readOutcome(data, when: Date()).told
            Haptic.behaviourStarted()
        } catch {
            performed = BallEntrantView.message(error)
        }
    }

    // MARK: - the wire

    /// How long a client waits for one cell.
    ///
    /// GENEROUS, BECAUSE THE FLOOR IS THE PHONE. A cell is a settle, up to five
    /// seconds of physics and a fifty-tick tail, which a Pi does in a fraction
    /// of that and a phone running MuJoCo in WebAssembly has never been timed.
    /// The bench's own per-request deadline is what decides a wedge — see
    /// `PhoneBenchListener.deadline(for:body:)` — and a client timeout shorter
    /// than that would report a working bench as a dead one.
    private static let cellSeconds: Double = 180
    private static let gridSeconds: Double = 30
    private static let performSeconds: Double = 300

    /// The half-second after a track returns home, so a motion that ends in a
    /// crouch is measured ending in a crouch. `PipelineView` sends the same
    /// tail for the same reason.
    private static let settleSeconds: Double = 0.5

    private static func armed(_ benches: BenchStore) throws -> (DuckBench.Address, String?) {
        guard let chosen = benches.selected else { throw DuckBench.Refusal.empty }
        let armed = benches.armed(chosen)
        return (try armed.resolved(), armed.token)
    }

    private static func ask(_ call: DuckBench.Call, token: String?,
                            seconds: Double) async throws -> Data {
        var request = DuckBench.urlRequest(for: call, token: token)
        request.timeoutInterval = seconds
        return try await URLSession.shared.data(for: request).0
    }
}

// MARK: - submitting

/// Where a scored run can go: a file, an issue, or a dataset under your own
/// account. `StairsSubmitView`'s three destinations, with the ball challenge's
/// own sentences and its own submissions repository.
struct BallSubmitView: View {
    let submission: BallChallenge.Submission
    @Environment(\.dismiss) private var dismiss

    @State private var outgoing: ExportedFile?
    @State private var token = ""
    @State private var account: String?
    @State private var isPrivate = false
    @State private var busy = false
    @State private var failure: String?
    @State private var published: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TelemetryRow(label: "File", value: submission.filename)
                    Text(submission.score.verdict)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BallChallenge.Submission.whatIsSent)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BallChallenge.Submission.howToRescore)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionHeading(text: "What is in it")
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    Button("Share the file") { share() }
                        .buttonStyle(.primaryAction)
                    Link(destination: submission.issueURL) {
                        Label("Open the GitHub issue", systemImage: "arrow.up.right.square")
                    }
                    Text(BallChallenge.Submission.issueNote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionHeading(text: "Send it")
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    SecureField("hf_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Check this token") { Task { await check() } }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    if let account {
                        Label("Publishing as \(account)",
                              systemImage: "person.crop.circle.badge.checkmark")
                            .font(.footnote)
                            .foregroundStyle(Theme.success)
                    }
                    Toggle("Private repository", isOn: $isPrivate)
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack(spacing: Theme.spacing(.tight)) {
                            Text(isPrivate ? "Commit to a private dataset"
                                           : "Commit to a public dataset")
                                .frame(maxWidth: .infinity)
                            if busy { ProgressView() }
                        }
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(busy || account == nil || published != nil)
                    Text(BallChallenge.Submission.publishNote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BallChallenge.Submission.archiveNote)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionHeading(text: "Publish it")
                } footer: {
                    // PUBLIC IS A CAVEAT AND PRIVATE IS NOT, the distinction
                    // `PublishMotionView` draws: one of these is reversible and
                    // the other is not, and a person skimming a form reads the
                    // shape before the words.
                    if !isPrivate {
                        Label(HuggingFacePublish.publicWarning,
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)

                if let published {
                    Section {
                        if let url = URL(string: published) {
                            Link(destination: url) {
                                Label("Open it on Hugging Face", systemImage: "arrow.up.right.square")
                            }
                        }
                        Text(published)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                    } header: {
                        SectionHeading(text: "Published")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.octagon")
                            .font(.footnote)
                            .foregroundStyle(Theme.refused)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        SectionHeading(text: "That did not work")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle("Submit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { token = TokenStore.load() ?? "" }
            .sheet(item: $outgoing) { file in
                ShareSheet(items: [file.url]) { outgoing = nil }
            }
        }
    }

    /// Write the bundle where the share sheet can reach it.
    private func share() {
        do {
            outgoing = ExportedFile(url: try ExportFile.write(submission.bundle(),
                                                              named: submission.filename))
        } catch {
            failure = BallEntrantView.message(error)
        }
    }

    private func check() async {
        busy = true; failure = nil
        defer { busy = false }
        let request = HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(), token: token)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = http.statusCode == 401
                    ? HuggingFacePublish.tokenRefused
                    : HuggingFacePublish.answered(http.statusCode)
                return
            }
            guard let name = HuggingFacePublish.parseWhoami(data) else {
                failure = HuggingFacePublish.noAccountNamed
                return
            }
            account = name
            TokenStore.save(token)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Create-then-commit, exactly as every other publish in this app does it —
    /// and the calls themselves are the kit's, so the licence, the card and the
    /// commit summary are the ones `swift test` reads.
    private func publish() async {
        guard let account else { return }
        busy = true; failure = nil
        defer { busy = false }
        do {
            let calls = try submission.publishCalls(namespace: account, isPrivate: isPrivate)
            let (_, createResponse) = try await URLSession.shared.data(
                for: HuggingFacePublish.urlRequest(for: calls.create, token: token))
            if let http = createResponse as? HTTPURLResponse,
               http.statusCode != 200, http.statusCode != 409 {   // 409: it already exists
                failure = HuggingFacePublish.creating(http.statusCode)
                return
            }
            let (data, commitResponse) = try await URLSession.shared.data(
                for: HuggingFacePublish.urlRequest(for: calls.commit, token: token))
            if let http = commitResponse as? HTTPURLResponse, http.statusCode >= 300 {
                let detail = String(decoding: data.prefix(200), as: UTF8.self)
                failure = "Publishing answered \(http.statusCode). \(detail)"
                return
            }
            published = calls.repository.webURL
        } catch {
            failure = BallEntrantView.message(error)
        }
    }
}
