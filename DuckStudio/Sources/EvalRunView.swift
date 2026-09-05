import SwiftUI
import DuckKit
import StudioKit

/// One evaluation while it is happening, and what it left behind.
///
/// A SCENE IS THE UNIT OF PROGRESS, AND THE SCREEN SAYS SO RATHER THAN HIDING
/// IT. One `/tune` call answers every drop height of a scene, so the epochs of a
/// scene arrive together and a progress bar counting trials would sit still for
/// fifty seconds and then jump by eight. `EvalEpochs.wholeSceneAtOnceSaid` is
/// under the bar, because a progress bar that moves in steps somebody cannot
/// predict is a progress bar they stop believing.
///
/// STOP IS NEVER DISABLED WHILE THERE IS SOMETHING TO STOP. Not after it has
/// been tapped, not while a request is in flight, not while a scene is halfway
/// through. A greyed out Stop in front of somebody watching three minutes of
/// physics they no longer want is the one control this screen must never take
/// away, and `EvalTask.stopIsNotAFailure` under it says what stopping keeps.
///
/// THE SHARE IS OFFERED FOR A CANCELLED RUN TOO. `EvalRunner` files the log the
/// moment there is nothing left to judge, whether the run finished or somebody
/// stopped it, and a stopped run is real data about what happened up to the
/// stop. Withholding the share would make `stopIsNotAFailure` a slogan.
///
/// NOTHING HERE COMPUTES A RESULT. Every number on this screen is one the bench
/// sent, formatted by `EvalReport.number`, and every sentence is a kit constant.
/// The only arithmetic in the file is a playhead: which recorded tick of a clip
/// is on screen, worked out from the clip's own duration and tick count.
struct EvalRunView: View {
    @ObservedObject var runner: EvalRunner
    @ObservedObject var evals: EvalStore

    /// The two files a finished log is handed over as, held as one value so
    /// there is no state in which a sheet is up and the files are not.
    @State private var sharing: EvalExport.Pair?
    @State private var shareFailure: String?

    var body: some View {
        List {
            if runner.running { progressSection }
            whatHasLanded
            theBench
            if runner.running { stopIt }
            if let file = runner.finishedFile { finished(file) }
            if let failure = runner.failure { failed(failure) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(runner.task?.name ?? EvalTask.rowTitle)
        .navigationBarTitleDisplayMode(.inline)
        // THE VERDICT QUEUE ONLY GROWS WHILE SOMETHING CAN DRAIN IT, and the
        // only thing that can is the sheet this screen presents. The runner
        // outlives this screen, so a queue filled after somebody walked away
        // would be a run that never filed its log: the guard on the write is
        // "nothing left to judge", and nothing could ever answer. Leaving says
        // so, which files what was measured with the rest unjudged.
        .onAppear { runner.somebodyIsWatching() }
        .onDisappear { runner.nobodyIsWatching() }
        // THE VERDICT SHEET IS PRESENTED ON THE TRIAL, NOT ON A `Bool`. An
        // identity per trial is what makes the stage, the playhead and the
        // note start again for each one; a Bool with the trial read out of the
        // runner underneath would replay the second trial with the first one's
        // playhead still at the end and its note still typed.
        .sheet(item: judging) { judging in
            EvalVerdictSheet(scene: judging.scene, trial: judging.trial,
                             onAnswer: { runner.record($0) },
                             onSkipOne: { runner.skipOne() },
                             onStopWatching: { runner.skipJudging() })
        }
        .sheet(item: $sharing) { pair in
            ShareSheet(items: pair.items) { sharing = nil }
        }
    }

    // MARK: - where it has got to

    private var progressSection: some View {
        Section {
            ProgressView(value: Double(runner.scenesDone),
                         total: Double(max(runner.scenesTotal, 1))) {
                Text(runner.currentScene?.instruction ?? EvalTask.rowTitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Theme.measured)
            .accessibilityValue(Text(scenesCounted))

            TelemetryRow(label: EvalScreen.scenesSaid, value: scenesCounted)
        } header: {
            SectionHeading(text: EvalScreen.runningHeading)
        } footer: {
            Text(EvalEpochs.wholeSceneAtOnceSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Two numbers the runner keeps apart, said the way this app already says a
    /// count out of a total: `TuneView`'s "Stayed up" row is the same shape.
    private var scenesCounted: String {
        "\(runner.scenesDone) of \(runner.scenesTotal)"
    }

    // MARK: - what has landed

    /// Every trial that has answered, oldest scene first.
    ///
    /// A FAILED TRIAL IS A ROW AND NOT A GAP. It is drawn in `Theme.refused`
    /// carrying the bench's own message through `EvalText.foreign`, which caps
    /// it and strips whatever control characters a JavaScript harness put in
    /// it. A run that quietly dropped its failures would be a run whose screen
    /// disagrees with its own log, where every one of them is recorded.
    @ViewBuilder private var whatHasLanded: some View {
        ForEach(runner.scenes) { result in
            Section {
                Text(result.scene.instruction)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = result.error {
                    Text(EvalText.foreign(error))
                        .font(.footnote)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(result.trials, id: \.epoch) { trial in
                    trialRow(trial)
                }
            } header: {
                SectionHeading(text: result.scene.id)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    private func trialRow(_ trial: EvalTrial) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(spacing: Theme.spacing(.tight)) {
                Text(dropSaid(trial))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(trial.wasScored ? Theme.textPrimary : Theme.refused)
                Spacer(minLength: Theme.spacing(.tight))
                if let reason = trial.terminationReason {
                    Text(EvalText.foreign(reason))
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            ForEach(EvalReport.ordered(Array(trial.scores.keys)), id: \.self) { name in
                if let value = trial.scores[name] {
                    HStack(spacing: Theme.spacing(.tight)) {
                        Text(name)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: Theme.spacing(.tight))
                        Text(EvalReport.number(value))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.measured)
                    }
                }
            }
            if let error = trial.error {
                Text(EvalText.foreign(error))
                    .font(.caption)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let verdict = trial.verdict {
                Text(verdict.answer.said)
                    .font(.caption)
                    .foregroundStyle(Theme.asked)
                if let note = EvalText.foreign(verdict.note) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if trial.trace != nil {
                Text(EvalTrace.firstDropOnlySaid)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
        .accessibilityElement(children: .combine)
    }

    /// The drop height this trial ran from, or how it ended when the axis is a
    /// grid and there is no height to name.
    ///
    /// THE WORD FOR HOW IT ENDED IS INSPECT-ROBOTS' OWN, through
    /// `EvalReport.statusShown`, so a row on this screen and a row in their
    /// viewer call the same trial the same thing. `EvalTrial.Status` and
    /// `EvalLog.Status` share their three raw values for that reason.
    private func dropSaid(_ trial: EvalTrial) -> String {
        if let drop = trial.metadata[EvalMeta.dropMetres]?.doubleValue {
            return "\(EvalMeta.dropMetres) \(EvalReport.number(drop))"
        }
        guard let status = EvalLog.Status(rawValue: trial.status.rawValue) else {
            return trial.status.rawValue
        }
        return EvalReport.statusShown(status)
    }

    // MARK: - the bench, frozen at Start

    /// Everything about where this ran, captured when Start was tapped.
    ///
    /// READ OFF THE RUNNER AND NOT OFF THE BENCH STORE, which is the fix
    /// `StairsRun.scoredBenchName` already documents: the bench is chosen on
    /// another tab, and a screen that read the selection at the end would name
    /// whichever bench happened to be selected then.
    private var theBench: some View {
        Section {
            if let name = runner.ranOnBench {
                TelemetryRow(label: EvalScreen.benchSaid, value: name)
            }
            if let address = runner.ranOnAddress {
                Text(EvalText.foreign(address))
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.textSecondary)
            }
            if let embodiment = runner.embodiment {
                Text(embodiment.plantSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
                Text(embodiment.hostSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: EvalScreen.whereItRanHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - Stop

    /// NEVER `.disabled`. Not after it has been tapped, not while a request is
    /// in flight. `runner.stop()` sets a flag the loop reads between scenes, so
    /// a second tap is a no operation rather than an error, and a Stop that
    /// greyed itself out the moment it was pressed would leave somebody
    /// watching physics they have already said they do not want.
    ///
    /// THE WORD CHANGES, WHICH IS THE ONLY ACKNOWLEDGEMENT AVAILABLE. A scene
    /// is one request and the flag is read at the end of it, so for up to fifty
    /// seconds after the tap the progress row goes on saying the run is going.
    /// The button said "Stop" throughout, and the reading of a control that
    /// answers nothing is that the tap was missed.
    private var stopIt: some View {
        Section {
            Button(role: .destructive) {
                runner.stop()
            } label: {
                Text(runner.stopped ? EvalScreen.stoppingAfterThisSceneSaid
                                    : EvalScreen.stopSaid)
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text(EvalTask.stopIsNotAFailure)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the log it left

    /// The finished log, whatever the status is.
    private func finished(_ file: EvalLogFile) -> some View {
        Section {
            Text(EvalReport.statusShown(file.log.status))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tone(file.log.status))
            NavigationLink {
                EvalLogDetailView(file: file, evals: evals)
            } label: {
                Label(EvalScreen.openTheLogSaid, systemImage: "doc.text.magnifyingglass")
            }
            Button {
                share(file)
            } label: {
                Label(EvalScreen.shareTheLogAndTheReportSaid, systemImage: "square.and.arrow.up")
            }
            if let shareFailure {
                Text(shareFailure)
                    .font(.footnote)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: EvalScreen.whatItWroteHeading)
        } footer: {
            Text(EvalLogFile.aLogIsFinished)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func failed(_ failure: String) -> some View {
        Section {
            Text(failure)
                .font(.footnote)
                .foregroundStyle(Theme.refused)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func share(_ file: EvalLogFile) {
        do {
            sharing = try EvalExport.write(file)
            shareFailure = nil
        } catch {
            shareFailure = EvalMessage.of(error)
        }
    }

    private func tone(_ status: EvalLog.Status) -> Color {
        switch status {
        case .success: return Theme.success
        case .error: return Theme.critical
        case .cancelled, .started: return Theme.textSecondary
        }
    }

    // MARK: - the verdict queue

    /// The trial the sheet is about, wrapped so `.sheet(item:)` has an identity
    /// to present on.
    private struct Judging: Identifiable {
        let scene: EvalScene
        let trial: EvalTrial
        var id: String { "\(scene.id)#\(trial.epoch)" }
    }

    /// A one way binding: the queue is the runner's and this screen only reads
    /// it.
    ///
    /// THE SHEET IS A FUNCTION OF THE QUEUE AND NOTHING DISMISSES IT BY HAND.
    /// Every button in it changes the queue, and the queue is what decides
    /// whether a sheet is up and which trial it is about, so there is no state
    /// in which the sheet and the runner disagree about what is being judged. A
    /// `dismiss()` beside each answer would be a second opinion, and the one it
    /// gets wrong is the middle of a queue: answering the first of three would
    /// take the sheet down while two trials were still waiting.
    ///
    /// THE SETTER IGNORES WHAT SwiftUI WRITES BACK, which is safe only because
    /// the sheet carries `.interactiveDismissDisabled()`. A swipe is not an
    /// answer, and a dismissal that silently meant "stop watching" would take a
    /// decision nobody made.
    private var judging: Binding<Judging?> {
        Binding(get: {
            guard let pair = runner.judgeable else { return nil }
            return Judging(scene: pair.scene, trial: pair.trial)
        }, set: { _ in })
    }
}

// MARK: - the verdict sheet

/// One recorded trial, played, and then judged.
///
/// THE THREE BUTTONS ARRIVE AFTER THE PLAYBACK AND NOT BEFORE IT. A verdict on
/// a trial nobody watched is exactly the number this whole feature exists to
/// keep out of a log, so the answers are not drawn until the clip has run to
/// the end at least once, and `EvalVerdict.watchBeforeYouJudge` says why they
/// were not there a moment ago.
///
/// THE STAGE IS GIVEN THE CLIP'S OWN ENVIRONMENT, WHICH IS BARE FLOOR. `/tune`
/// answers with a plant name and a digest and no scene geometry, so
/// `EvalStageClip` carries an empty environment as a stored value and this
/// screen has no way to substitute the world the app happens to have selected.
/// Drawing a staircase under an episode that never saw one is the falsehood
/// this arrangement exists to prevent.
///
/// THE CLIP IS BUILT ONCE. Turning a five hundred tick trace into poses is
/// fifteen joint angles a tick, and doing it inside `body` would redo it at
/// every frame of the playback it is driving.
struct EvalVerdictSheet: View {
    let scene: EvalScene
    let trial: EvalTrial
    let onAnswer: (EvalVerdict) -> Void
    let onSkipOne: () -> Void
    let onStopWatching: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var clip: EvalStageClip?
    @State private var orbit = OrbitState()
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = false
    /// Whether the recording has run to its end at least once, which is what
    /// the three answers wait for.
    @State private var hasPlayed = false
    @State private var note = ""

    /// The stage's height when the text is not at an accessibility size. Not
    /// capped at those sizes, the rule `DriveView` documents: the duck shrinks
    /// to make room and the words under it do not disappear.
    private static let stageHeight: CGFloat = 260

    var body: some View {
        NavigationStack {
            List {
                if let clip, !clip.isEmpty {
                    stage(clip)
                    playback(clip)
                }
                whatWasAsked
                answers
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle(scene.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EvalScreen.stopWatchingSaid) { onStopWatching() }
                }
            }
            // A SWIPE IS NOT AN ANSWER. Both ways out of this sheet are
            // buttons that say what they do, because a dismissal that silently
            // meant "stop watching" would take a decision nobody made.
            .interactiveDismissDisabled()
            .onAppear {
                if clip == nil, let trace = trial.trace { clip = EvalStageClip.of(trace) }
            }
            .onReceive(Timer.publish(every: 1.0 / DuckModel.tickHz,
                                     on: .main, in: .common).autoconnect()) { _ in
                advance()
            }
        }
    }

    // MARK: - the picture

    private func stage(_ clip: EvalStageClip) -> some View {
        Section {
            DuckStage(pose: clip.pose(at: frame(clip)),
                      environment: clip.environment,
                      trail: clip.trail,
                      progress: revealed(clip),
                      orbit: $orbit)
                .frame(maxHeight: typeSize.isAccessibilitySize ? nil : Self.stageHeight)
                .listRowInsets(EdgeInsets())
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func playback(_ clip: EvalStageClip) -> some View {
        Section {
            TransportBar(duration: clip.duration, playhead: $playhead, isRunning: $isRunning)
            TelemetryRow(label: EvalMeta.dropMetres,
                         value: EvalReport.number(clip.dropHeight))
            if clip.wasCapped {
                Text(EvalTrace.firstDropOnlySaid)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // THE BENCH'S OWN CAPTION, WHEN IT SENT ONE. Drawn through
            // `EvalText.foreign` because nobody here wrote it and it has no
            // length bound of its own.
            if let why = EvalText.foreign(clip.why) {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: EvalScreen.watchItHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - what the scene asked for

    private var whatWasAsked: some View {
        Section {
            Text(scene.instruction)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = trial.terminationReason {
                Text(EvalText.foreign(reason))
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(EvalReport.ordered(Array(trial.scores.keys)), id: \.self) { name in
                if let value = trial.scores[name] {
                    TelemetryRow(label: name, value: EvalReport.number(value))
                }
            }
        } header: {
            SectionHeading(text: EvalScreen.whatItWasAskedToDoHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the three answers

    @ViewBuilder private var answers: some View {
        Section {
            if hasPlayed {
                // THE NOTE IS THE OPERATOR'S OWN WORDS AND GOES INTO THE LOG
                // WHOLE. It is drawn back through `EvalText.foreign` everywhere
                // it is read, which is what caps it on a row without touching
                // what was written down.
                TextField(EvalScreen.noteSaid, text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityLabel(Text(EvalScreen.noteSaid))
                ForEach(EvalVerdict.Answer.allCases, id: \.rawValue) { answer in
                    Button {
                        onAnswer(EvalVerdict(answer: answer, note: trimmedNote))
                    } label: {
                        Text(answer.said).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel(Text(answer.said))
                }
                Button(EvalScreen.skipThisOneSaid) { onSkipOne() }
            } else {
                Text(EvalVerdict.watchBeforeYouJudge)
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: EvalScreen.yourVerdictHeading)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                Text(EvalVerdict.recordedNotScoredSaid)
                Text(EvalVerdict.vocabularySaid)
            }
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The operator's own words, or nothing. An empty note written as an empty
    /// string would put a `""` in `operator_notes` where their schema means
    /// `null`, which is the difference between "they said nothing" and "they
    /// were never asked".
    private var trimmedNote: String? {
        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - the playhead

    /// One tick of the clock, and the one place `hasPlayed` becomes true.
    ///
    /// PLAYING TO THE END IS WHAT COUNTS, not pressing play. Somebody who
    /// scrubs to the last frame has also seen the ending, and the flag is set
    /// wherever the playhead reaches the end, which is why the check is here
    /// rather than in the Play button.
    private func advance() {
        guard let clip, !clip.isEmpty else { return }
        // EVERY FLAG IS WRITTEN ONCE. This runs fifty times a second for as
        // long as the sheet is up, and a state write on every one of those
        // would redraw the screen at fifty hertz while nothing on it moved.
        if !hasPlayed, playhead >= clip.duration { hasPlayed = true }
        guard isRunning else { return }
        let next = playhead + 1.0 / DuckModel.tickHz
        guard next < clip.duration else {
            playhead = clip.duration
            isRunning = false
            hasPlayed = true
            return
        }
        playhead = next
    }

    /// Which recorded tick is on screen.
    ///
    /// THE CLIP'S OWN TWO NUMBERS AND NO RATE SPELLED HERE. `EvalStageClip`
    /// knows how many ticks it holds and how long they take at the bench's
    /// control rate; the playhead is a position inside that duration, so the
    /// index is the same fraction of the ticks. `pose(at:)` clamps both ends,
    /// so a rounding that lands one past the last frame is a held last frame
    /// rather than a trap.
    private func frame(_ clip: EvalStageClip) -> Int {
        guard clip.duration > 0 else { return 0 }
        let fraction = min(max(playhead / clip.duration, 0), 1)
        return Int((fraction * Double(clip.ticks - 1)).rounded())
    }

    /// How much of the trail the stage has revealed, as the fraction the stage
    /// itself takes.
    private func revealed(_ clip: EvalStageClip) -> Double {
        guard clip.duration > 0 else { return 0 }
        return min(max(playhead / clip.duration, 0), 1)
    }
}
