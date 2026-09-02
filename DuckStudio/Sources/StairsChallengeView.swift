import SwiftUI
import DuckKit
import StudioKit

/// The Stairs Challenge: the published corpus of moves that try to get a duck
/// off the floor and onto a step, and the machinery to score one here.
///
/// WHY THIS SCREEN EXISTS AT ALL. Everything else in Studio is something you
/// made. This is something a search made, in a harness with an audit behind it,
/// and it is the only place in the app where a number this phone produces can
/// be put beside a number somebody else published and be the SAME number. That
/// only works because the bench the phone carries runs the audit's own episode
/// function — `/climb` is `climb/rig3.mjs`'s `scoreSaved` with the intent in the
/// request body instead of in a file — and because the fourteen cells come from
/// the bench rather than from a literal typed here.
///
/// NOTHING ON THIS SCREEN AGGREGATES ANYTHING. Fourteen answers come back and
/// `StairsChallenge.Score` turns them into kCore, kCoreStable, kExt, kExtStable
/// and the ceiling, in the kit, where `swift test` reads them against the same
/// fixtures `climb/robust.mjs` produced. A screen that counted its own cells
/// would be a second scorer, and the entire value of a leaderboard is that
/// there is one.
///
/// AND EVERY CLAIM IS THE KIT'S SENTENCE. The one-liner, the bar, the verdict,
/// the same-criterion line, the not-yet for a bench with no `/climb`, the
/// real-duck caveat and all four submission sentences are `static let`s with
/// assertions on them. What this file writes for itself are the words on
/// controls — "Rise", "Score", "Submit" — which are labels rather than claims.
struct StairsChallengeView: View {
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.spacing(.snug)) {
                    Text(StairsChallenge.oneSentence)
                    // THE BAR IS THE HONEST HALF AND IT IS DRAWN AS PROMINENTLY
                    // AS THE INVITATION. It says the bar has never been met and
                    // why — a screen that printed only the challenge would be
                    // recruiting people to a target the audit already measured
                    // as unreachable at this scale without saying so.
                    Text(StairsChallenge.barSaid)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: "The challenge")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(StairsChallenge.entries) { row in
                    NavigationLink {
                        StairsMoveView(row: row, drafts: drafts, scenes: scenes,
                                       models: models, benches: benches)
                    } label: {
                        StairsRowLabel(row: row)
                    }
                }
            } header: {
                SectionHeading(text: "Leaderboard")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(StairsChallenge.controls) { row in
                    NavigationLink {
                        StairsMoveView(row: row, drafts: drafts, scenes: scenes,
                                       models: models, benches: benches)
                    } label: {
                        StairsRowLabel(row: row)
                    }
                }
            } header: {
                // THE CONTROLS ARE ON THE BOARD, IN THEIR OWN SECTION. Doing
                // nothing scores 0 everywhere and standing on the tread scores
                // 9 of 9 without ever climbing; both are in the published table
                // and both are what stop a number here being read as an
                // achievement on its own. They are separated from the entries
                // rather than dropped, because a leaderboard whose floor and
                // ceiling are invisible is a leaderboard nobody can calibrate.
                SectionHeading(text: "Reference controls")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Link(destination: StairsChallenge.datasetURL) {
                    Label("The dataset on Hugging Face", systemImage: "arrow.up.right.square")
                }
                Link(destination: StairsChallenge.harnessURL) {
                    Label("The harness on GitHub", systemImage: "arrow.up.right.square")
                }
            } header: {
                SectionHeading(text: "Where this comes from")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(StairsChallenge.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One published row: where it ranks, what it is, and what it scored.
///
/// THE RECORD IS MARKED AND THE MARK IS NOT A COLOUR ALONE. It carries the
/// seal glyph and the word, because "which one is the record" is the single
/// fact a person skims this list for, and a row distinguished by hue is a row
/// invisible to a quarter of the people reading it.
private struct StairsRowLabel: View {
    let row: StairsChallenge.Row

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing(.snug)) {
            // THE RANK IS MONO BECAUSE IT IS AN IDENTIFIER IN A COLUMN. Ranks
            // stack down the screen and a proportional "1" beside a "10" makes
            // a ragged edge out of the one thing the eye is scanning.
            Text(row.rankSaid)
                .font(.subheadline.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: Theme.spacing(.loose), alignment: .trailing)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(row.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.moveName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // WHAT THE ROW ACTUALLY DOES, IN ONE WORD, BETWEEN THE NAME AND
                // THE SCORE. `best_r6_ceilvaultB_60mm` is a filename, and a
                // board of nineteen of them is a board only its author can
                // read; the word comes off the file's own `family` string in
                // the kit, so it cannot say something the intent does not.
                //
                // ONLY WHEN THERE IS ONE. `Row.strategy` is optional on
                // purpose: a family this build has never seen gets no badge
                // rather than a guessed one, which is how a screen starts
                // telling people a new search is an old one.
                if let strategy = row.strategy {
                    Label(strategy.word, systemImage: strategy.glyph)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(row.scoreSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if row.isRecord {
                    Label("The record", systemImage: "seal")
                        .font(.caption2)
                        .foregroundStyle(Theme.success)
                }
                // AN ORACLE ROW LOOKS DIFFERENT, because it is: a landing law
                // that read the tread out of the plant is a bound, not a move.
                if row.isOracle {
                    Label(StairsChallenge.oracleWord, systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.spacing(.hairline))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - one move

/// A published move: what it is, how to open it, how to score it here, and how
/// to send the result somewhere.
///
/// THE ORDER IS THE ORDER OF THE WORK. What this is, then edit it, then score
/// it, then submit it, then play it. Submit sits after Score and is a stated
/// not-yet until a score exists on this device, because a submission is the
/// fourteen cells and the plant they were measured in — there is nothing to
/// send before they exist, and a live Submit button over an empty bundle is
/// the enabled-and-inert control this app is built not to ship.
struct StairsMoveView: View {
    let row: StairsChallenge.Row
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    /// The move, or whatever stopped it being read out of the bundle.
    ///
    /// LOADED ONCE INTO STATE RATHER THAN COMPUTED PER PASS. `intentData` goes
    /// to `Bundle.module` and parses a JSON file; a computed property would do
    /// that on every redraw, including every keystroke in the submission sheet
    /// above it.
    @State private var loaded: Result<StairsChallenge.Move, Error>?

    // @StateObject AND NOT @State, for `TuneView`'s reason: the run publishes
    // fourteen times and a `@State` reference would subscribe to none of them,
    // so the progress row would sit on cell one for the whole run.
    @StateObject private var run = StairsRun()

    @State private var rise = StairsChallenge.defaultRise
    /// The draft the editor is open on, if it is.
    @State private var editing: IntentDraft?
    /// The draft `open(_:)` saved, so the edited version can be found again
    /// and scored on the same cells.
    @State private var editedDraftID: UUID?
    /// The bundle being submitted, if the sheet is up.
    @State private var submitting: StairsSubmissionBox?
    @State private var failure: String?

    var body: some View {
        Form {
            whatThisIs
            editor
            edited
            scoring
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
        .navigationTitle(row.moveName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if loaded == nil { loaded = Result { try StairsChallenge.move(for: row) } }
            // ASK THE BENCH FOR ITS GRID BEFORE ANYTHING IS SCORED. Two things
            // come back at once: whether it has `/climb` at all — which is what
            // the not-yet is keyed on — and which fourteen cells it scores, so
            // a bench on a different grid can be said to be on a different grid
            // rather than silently compared with the published table.
            await run.probe(benches: benches)
            Haptic.prepare()
        }
        // A SCORE IS FOURTEEN CELLS AT ONE RISE ON ONE BENCH, and both of those
        // can be changed from under it — the rise by the picker on this screen,
        // the bench by Settings on another tab while this one is still on the
        // stack. Either change puts the score down; a bench change also asks
        // the new bench whether it has `/climb` at all, because the not-yet on
        // screen is about the bench that was selected when it was drawn.
        .onChange(of: rise) { _, _ in run.forget() }
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
            StairsSubmitView(submission: box.submission)
        }
    }

    // MARK: - what this is

    @ViewBuilder private var whatThisIs: some View {
        Section {
            TelemetryRow(label: "Rank", value: row.rankSaid)
            TelemetryRow(label: "Rise", value: row.riseSaid)
            TelemetryRow(label: "Cleared and standing", value: row.scoreSaid)
            TelemetryRow(label: "Over the bar", value: row.ceilingSaid)
            Text(row.note)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // UNDER THE NOTE, BECAUSE IT ANSWERS THE QUESTION THE NOTE RAISES.
            // The note says how this row did; this says what it is — a paragraph
            // per strategy, in the kit, where the three sentences that must not
            // soften ("no robot can", "not a climb", "for free") are asserted
            // letter by letter.
            if let strategy = row.strategy {
                Text(strategy.whatItDoes)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch loaded {
            case .success(let move):
                // THE PROVENANCE IS THE DRAFT'S OWN SENTENCE, which is the one
                // that will travel with the move if it is edited and published.
                // Writing a second version of it here is how the editor and the
                // challenge come to disagree about where a move came from.
                Text(move.toDraft(hash: row.hash, rank: row.rank).provenance)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failure(let error):
                Label(Self.message(error), systemImage: "xmark.octagon")
                    .font(.footnote)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            case .none:
                EmptyView()
            }
        } header: {
            SectionHeading(text: "This move")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the editor

    @ViewBuilder private var editor: some View {
        if case .success(let move) = loaded {
            Section {
                Button("Open in the editor") { open(move) }
                    .buttonStyle(.primaryAction)
            } footer: {
                Text(StairsChallenge.editorNote)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    // MARK: - the edited version: edit, score, keep

    /// THE LOOP THE CHALLENGE IS FOR. A person changes a keyframe's servo
    /// values in the editor, scores the edited version on the same fourteen
    /// cells, and keeps or puts back. The draft is looked up in the store by
    /// the id `open(_:)` saved; the published move's blend, gap, side and
    /// approach travel with it untouched (`Move.applying(draft:)`).
    @ViewBuilder private var edited: some View {
        if case .success(let move) = loaded {
            Section {
                if let draft = drafts.drafts.first(where: { $0.id == editedDraftID }) {
                    if StairsChallenge.Move.movedMouth(in: draft) {
                        Label(StairsChallenge.mouthDroppedNote, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if run.hasProbed, run.notYet == nil, run.unreachable == nil {
                        Button {
                            Task { await run.scoreEdited(move, draft: draft, rise: rise, benches: benches) }
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
                    Text(StairsChallenge.editedVersionNote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(StairsChallenge.editedNotFoundNote)
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

    /// Put the published move in the draft store and open it.
    ///
    /// SAVED BEFORE THE SHEET IS ASKED FOR, in that order and not the other:
    /// the editor looks the draft up in the store by id, so a sheet presented
    /// first would present the empty branch for one pass.
    /// AND THE ROOM COMES WITH IT. A published move opened against bare floor is
    /// a duck waving its beak at nothing: every one of these entries is a launch
    /// at a riser 120 mm in front of the spawn, and the whole of what makes an
    /// edit judgeable is seeing whether the beak lands on the tread. The flight
    /// is built at the ROW's rise — the one the published number was scored
    /// against, not whatever the picker on this screen is set to — from the
    /// harness's own layout, and its id is derived from the challenge and the
    /// rise so that opening this row again attaches the same scene rather than
    /// a second copy of it.
    private func open(_ move: StairsChallenge.Move) {
        // THE SCENE IS THE MOVE'S, NOT THE ROW'S. Two moves at one rise can
        // stand the duck in different places — a wider gap, a placed spawn on
        // the tread — and the scene's id folds every one of those in, so the
        // stage under a move is the room that move was scored in.
        var scene = DuckScene.stairsChallenge(rise: row.riseMetres, count: move.stepCount,
                                              gap: move.gap, side: move.side,
                                              spawn: move.spawn)
        scene.id = DuckScene.challengeSceneID(.stairs, riseMillimetres: row.riseMillimetres,
                                              gap: move.gap, side: move.side,
                                              spawn: move.spawn, stepCount: move.stepCount)
        scenes.ensure(scene)

        var draft = move.toDraft(hash: row.hash, rank: row.rank)
        draft.sceneID = scene.id
        drafts.save(draft)
        editedDraftID = draft.id
        editing = draft
    }

    // MARK: - scoring

    @ViewBuilder private var scoring: some View {
        Section {
            if let bench = benches.selected {
                TelemetryRow(label: "Bench", value: bench.name)
            }
            Picker("Rise", selection: $rise) {
                ForEach(StairsChallenge.rises, id: \.self) { value in
                    Text(StairsChallenge.riseSaid(value)).tag(value)
                }
            }
            .disabled(run.running)

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
                // is not offered greyed out with a tooltip, it is replaced by
                // the sentence that says what to do instead.
                Label(notYet, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if run.hasProbed, case .success(let move) = loaded {
                Button {
                    Task { await run.scoreEveryCell(move, rise: rise, benches: benches) }
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
                Text(progress.said(rise: rise))
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
                    Text(score.extendedSaid)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if run.onPublishedGrid {
                        Text(score.sameCriterion)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(score.against(row))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(Array(score.problems.enumerated()), id: \.offset) { _, problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                    if !run.onPublishedGrid {
                        Label(StairsChallenge.Grid.differentGridNote,
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
            // WHICH GRID IS ABOUT TO BE USED, BEFORE IT IS USED. The bench's
            // answer wins and the pinned copy fills its silence; both sentences
            // are the kit's, so which of the two is on screen is a fact about
            // what happened rather than a guess written here.
            Text(run.gridNote)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - submit

    @ViewBuilder private var submit: some View {
        Section {
            if let score = run.score, score.isPublishable, run.onPublishedGrid,
               case .success(let move) = loaded {
                Button("Submit") { submitting = box(move, score) }
                    .buttonStyle(.primaryAction)
                Text(StairsChallenge.Submission.whatIsSent)
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
                    Label(StairsChallenge.Grid.differentGridNote, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // NOT A DISABLED BUTTON. There is no bundle, so there is
                // nothing for a button to do, and the kit's sentence says
                // exactly what has to happen first.
                Text(StairsChallenge.Submission.notScoredYet)
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
    /// THE BENCH'S IDENTITY GOES IN FROM THE STORE AND THE GRID FLAG FROM THE
    /// PROBE. Both are facts about where the numbers came from, and a bundle
    /// that carried neither would be fourteen unrounded answers about nowhere.
    private func box(_ move: StairsChallenge.Move,
                     _ score: StairsChallenge.Score) -> StairsSubmissionBox {
        StairsSubmissionBox(submission: StairsChallenge.Submission(
            move: move, score: score,
            benchName: run.scoredBenchName ?? "an unnamed bench",
            benchAddress: run.scoredBenchAddress,
            onPublishedGrid: run.onPublishedGrid,
            row: row,
            appVersion: AppVersion.said,
            date: Date()))
    }

    // MARK: - the duck

    @ViewBuilder private var duck: some View {
        Section {
            if case .success(let move) = loaded {
                Button {
                    Task { await run.perform(move, benches: benches) }
                } label: {
                    HStack(spacing: Theme.spacing(.tight)) {
                        Text("Run it in physics on \(benches.selected?.name ?? "this bench")")
                            .frame(maxWidth: .infinity)
                        if run.performing { ProgressView() }
                    }
                }
                // `primaryActionMoves` — THIS IS THE ONE BUTTON ON THE SCREEN
                // THAT MAKES SOMETHING MOVE. Scoring reads physics; this plays
                // the move, and the design system reserves a separate style for
                // an action with a body attached to it.
                .buttonStyle(.primaryActionMoves)
                .disabled(run.performing)
            }
            if let told = run.performed {
                Text(told)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // THE CAVEAT IS BESIDE THE BUTTON AND NOT BEHIND IT. It is the
            // sentence that keeps "send to the duck" from reading as a claim
            // that any of this has been on hardware, which none of it has.
            Label(StairsChallenge.realDuckCaveat, systemImage: "info.circle")
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
    /// 1.)". The ladder is the one `PublishMotionView` and `TuneView` already
    /// use, with the challenge's two resource and parse refusals added.
    static func message(_ error: Error) -> String {
        switch error {
        case let refusal as StairsChallenge.ResourceError: return refusal.message
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
///
/// `Identifiable` SO THE SHEET CANNOT BE PRESENTED WITHOUT ONE. The same
/// argument `ExportedFile` makes: a Bool plus an Optional leaves a state where
/// the sheet is up and the thing it is about is nil, which SwiftUI renders as
/// an `EmptyView` in a card with no way out.
struct StairsSubmissionBox: Identifiable {
    let submission: StairsChallenge.Submission
    var id: String { submission.filename }
}

/// This build, as the submission bundle spells it.
///
/// READ FROM THE BUNDLE RATHER THAN WRITTEN DOWN. The marketing version and the
/// build number are set in `project.yml` and change every upload; a literal
/// here would date-stamp every submission with whatever was true the day this
/// file was last edited.
enum AppVersion {
    static var said: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

// MARK: - the run

/// Fourteen cells, one request each, and the two facts a screen needs before it
/// offers to start: whether this bench has `/climb`, and which grid it scores.
///
/// ONE REQUEST PER CELL IS THE CONTRACT AND NOT AN IMPLEMENTATION CHOICE.
/// `/climb` scores ONE cell of ONE intent, lays the stairs out for it and
/// clears them again afterwards, which is what keeps `/perform`, `/measure` and
/// `/tune` answering exactly what they answered before the endpoint existed. A
/// client that batched them would be asking for an endpoint that does not
/// exist.
///
/// THEY GO IN ORDER AND NOT IN PARALLEL. The bench serialises a climb behind
/// both of its other lanes — a cell borrows the model, not a copy of it — so
/// fourteen concurrent requests would queue anyway, and would arrive back in an
/// order that makes the progress row a lie.
@MainActor
final class StairsRun: ObservableObject {
    @Published private(set) var probing = false
    /// True once the bench has answered the grid probe at least once, so no
    /// Score button is drawn before we know whether this bench can score.
    @Published private(set) var hasProbed = false
    @Published private(set) var running = false
    @Published private(set) var performing = false
    /// The score a new run replaced, for the edit-score-keep sentence.
    @Published private(set) var previousScore: StairsChallenge.Score?
    /// Whether the current score is of the edited draft rather than the
    /// published move.
    @Published private(set) var scoredEdited = false

    /// The cells this run will use: the bench's, or the pinned fallback.
    @Published private(set) var grid: [DuckBench.Cell] = StairsChallenge.Grid.fallback
    /// True while the grid is the app's own copy because the bench has not
    /// answered with one.
    @Published private(set) var gridIsFallback = true
    /// The kit's not-yet, when this bench has no `/climb`.
    @Published private(set) var notYet: String?
    /// The bench did not answer at all, in whatever words the failure had.
    /// NOT the not-yet: see `probe`.
    @Published private(set) var unreachable: String?

    @Published private(set) var progress: StairsChallenge.ScoreProgress?
    @Published private(set) var score: StairsChallenge.Score?
    /// What `/perform` said, in `Pipeline.BenchOutcome`'s own words.
    @Published private(set) var performed: String?

    /// WHICH BENCH THESE CELLS CAME OFF, CAPTURED WHEN THEY WERE SCORED AND NOT
    /// READ BACK OFF THE STORE AT SUBMISSION TIME. The bench is chosen in
    /// Settings, on another tab, while this screen is still on the stack: score
    /// on the phone, switch to the Pi, tap Submit, and a bundle assembled from
    /// `benches.selected` would carry the Pi's name over the phone's fourteen
    /// answers — a wrong provenance, written by the app, in the one file whose
    /// entire job is provenance.
    @Published private(set) var scoredBenchName: String?
    @Published private(set) var scoredBenchAddress: String?

    /// Put down a score that is no longer about what the screen is asking.
    ///
    /// CALLED WHEN THE RISE OR THE BENCH CHANGES. A score is fourteen cells at
    /// ONE rise on ONE bench; leaving it on screen under a picker that now says
    /// something else is an invitation to submit it as if it were that.
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
    var onPublishedGrid: Bool { StairsChallenge.Grid.isPublishedGrid(grid) }

    var gridNote: String {
        gridIsFallback ? StairsChallenge.Grid.fallbackNote : StairsChallenge.sameCriterion(
            plantDigest: plantDigest)
    }

    private var plantDigest: String?

    // MARK: - can this bench score at all

    /// Ask the bench for its grid, which is also how we find out it has one.
    ///
    /// A BENCH WITHOUT `/climb` ANSWERS SOMETHING, and what it answers is the
    /// point: this app's own loopback server 404s an unknown path and an older
    /// Pi bench does the same, so what comes back is not JSON — while a bench
    /// that HAS the endpoint but cannot run it says so in its own words with
    /// `climbable: false`. Both end in the kit's not-yet, which names the bench
    /// and says what to update; neither is reported as a bench that is down.
    func probe(benches: BenchStore) async {
        probing = true
        defer { probing = false; hasProbed = true }
        notYet = nil
        let name = benches.selected?.name ?? "this bench"
        unreachable = nil
        grid = StairsChallenge.Grid.fallback
        gridIsFallback = true

        // THE TWO CATCHES ARE SPLIT AND THE SPLIT IS THE HONESTY. A bench that
        // did not answer at all and a bench that answered something which is
        // not a grid are different facts, and the kit's not-yet makes a CLAIM
        // about the second — "this bench answers /health and /perform but not
        // the stairs challenge". Printed over a bench that is simply off, that
        // sentence is a statement about a machine nobody has heard from. So
        // the send and the read are two `do` blocks: a transport failure is
        // reported in the transport's own words with a way to try again, and
        // only an ANSWER that is not a grid earns the not-yet.
        let data: Data
        do {
            let (address, token) = try Self.armed(benches)
            data = try await Self.ask(DuckBench.climbGrid(address), token: token,
                                      seconds: Self.gridSeconds)
        } catch {
            unreachable = StairsMoveView.message(error)
            return
        }
        do {
            let answered = try DuckBench.readClimbGrid(data)
            grid = answered.cells.isEmpty ? StairsChallenge.Grid.fallback : answered.cells
            gridIsFallback = answered.cells.isEmpty
            plantDigest = answered.plantDigest
            // A BENCH CAN HAVE THE ENDPOINT AND STILL NOT BE ABLE TO SCORE —
            // its scene has no stair bank, or its actuators are not in joint
            // order. It says so with `climbable: false`, and that is the same
            // not-yet as having no `/climb` at all: neither can produce a
            // comparable number here.
            if !answered.climbable { notYet = StairsChallenge.noClimbHere(bench: name) }
        } catch {
            // The bench answered and it was not a grid — an error body, a 404
            // page, an older build. That is the not-yet.
            notYet = StairsChallenge.noClimbHere(bench: name)
        }
    }

    // MARK: - the fourteen

    func scoreEveryCell(_ move: StairsChallenge.Move, rise: Double,
                        benches: BenchStore) async {
        scoredEdited = false
        await scoreAll(move, rise: rise, benches: benches)
    }

    /// The edited draft, put back into the published move's harness fields
    /// and scored on the same cells. A draft the format cannot carry (the
    /// mouth, a bad width) is refused with the kit's sentence, not scored.
    func scoreEdited(_ move: StairsChallenge.Move, draft: IntentDraft, rise: Double,
                     benches: BenchStore) async {
        let edited: StairsChallenge.Move
        do { edited = try move.applying(draft: draft) } catch {
            progress = StairsChallenge.ScoreProgress(grid: grid, done: [],
                                                     failures: [StairsMoveView.message(error)])
            return
        }
        scoredEdited = true
        await scoreAll(edited, rise: rise, benches: benches)
    }

    private func scoreAll(_ move: StairsChallenge.Move, rise: Double,
                          benches: BenchStore) async {
        running = true
        if let score { previousScore = score }
        score = nil
        scoredBenchName = benches.selected?.name
        scoredBenchAddress = benches.selected?.address
        defer { running = false }
        let cells = grid
        var done: [DuckBench.Climbed] = []
        var failures: [String] = []
        progress = StairsChallenge.ScoreProgress(grid: cells)
        do {
            let (address, token) = try Self.armed(benches)
            for cell in cells {
                let call = try DuckBench.climb(address, move: move, rise: rise, cell: cell)
                do {
                    let data = try await Self.ask(call, token: token, seconds: Self.cellSeconds)
                    done.append(try DuckBench.readClimbed(data))
                } catch {
                    // A CELL THAT FAILED IS NAMED AND THE RUN CONTINUES. The
                    // kit counts an unanswered cell as unanswered — `problems`
                    // says how many of fourteen came back — so abandoning the
                    // whole grid on one refusal would throw away thirteen real
                    // measurements to avoid printing one sentence.
                    failures.append(StairsMoveView.message(error))
                }
                progress = StairsChallenge.ScoreProgress(grid: cells, done: done,
                                                         failures: failures)
            }
            score = StairsChallenge.Score(rise: rise, cells: done)
            plantDigest = score?.plantDigest ?? plantDigest
            Haptic.finished()
        } catch {
            failures.append(StairsMoveView.message(error))
            progress = StairsChallenge.ScoreProgress(grid: cells, done: done, failures: failures)
        }
    }

    // MARK: - playing it

    /// Play the move through `/perform` — the app's one path for running an
    /// authored motion, unchanged and not re-implemented here.
    ///
    /// ONE ROLLOUT, NOT EIGHT. `/perform`'s default is a measurement — eight
    /// runs, because one that stays up proves very little — and this button is
    /// not a measurement. The score is the fourteen cells above; this is the
    /// move being played once so somebody can watch it.
    func perform(_ move: StairsChallenge.Move, benches: BenchStore) async {
        performing = true
        performed = nil
        defer { performing = false }
        do {
            let (address, token) = try Self.armed(benches)
            let draft = move.toDraft()
            let track = draft.benchTrack
            guard track.count >= 2 else { throw DuckBench.Refusal.empty }
            let call = try DuckBench.perform(address, keys: track,
                                             seconds: draft.duration + Self.settleSeconds,
                                             rollouts: 1)
            let data = try await Self.ask(call, token: token, seconds: Self.performSeconds)
            performed = try DuckBench.readOutcome(data, when: Date()).told
            Haptic.behaviourStarted()
        } catch {
            performed = StairsMoveView.message(error)
        }
    }

    // MARK: - the wire

    /// How long a client waits for one cell.
    ///
    /// GENEROUS, BECAUSE THE FLOOR IS THE PHONE. A cell is about a second of
    /// physics plus a fifty-tick tail, which a Pi does in a fraction of that
    /// and a phone running MuJoCo in WebAssembly has never been timed. The
    /// bench's own per-request deadline is what decides a wedge — see
    /// `PhoneBenchListener.deadline(for:body:)` — and a client timeout shorter
    /// than that would report a working bench as a dead one.
    private static let cellSeconds: Double = 180
    private static let gridSeconds: Double = 30
    private static let performSeconds: Double = 300

    /// The half-second after the track returns home, so a motion that ends in
    /// a crouch is measured ending in a crouch. `PipelineView` sends the same
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
/// account.
///
/// THREE DESTINATIONS AND NONE OF THEM IS AUTOMATIC. The file is written to
/// this device and handed to the share sheet; the issue form opens pre-filled
/// and says out loud that it cannot carry the file; the dataset commit needs a
/// token this app already holds and a decision about whether the repository is
/// public. Every one of those sentences is the kit's, because each is a claim
/// about what leaves the phone.
struct StairsSubmitView: View {
    let submission: StairsChallenge.Submission
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
                    Text(StairsChallenge.Submission.whatIsSent)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
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
                    Text(StairsChallenge.Submission.issueNote)
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
                    Text(StairsChallenge.Submission.publishNote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(StairsChallenge.Submission.archiveNote)
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
            failure = StairsMoveView.message(error)
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
            failure = StairsMoveView.message(error)
        }
    }
}
