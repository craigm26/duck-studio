import SwiftUI
import StudioKit

/// The two files one evaluation log leaves the phone as, written where the
/// share sheet can reach them.
///
/// A PAIR AND NOT A FILE, because `EvalReport.whatIsShared` promises two: the
/// log, which is the artefact their tools read, and this app's own report of
/// it, which is one page with no network in it. Handing over one of them would
/// make that sentence false, and handing them over in two taps would leave the
/// report behind whenever somebody stopped after the first.
///
/// ONE VALUE AND NOT A `Bool` BESIDE TWO OPTIONAL URLS, which is the shape
/// `ExportedFile` exists to prevent: presenting a sheet on the value itself
/// means there is no state in which the sheet is up and the files are not.
enum EvalExport {

    struct Pair: Identifiable {
        let log: URL
        let report: URL
        /// The log's URL, because a run is identified by its log everywhere
        /// else in this feature too.
        var id: String { log.absoluteString }
        var items: [Any] { [log, report] }
    }

    /// THE LOG'S OWN BYTES, NEVER RE ENCODED. `EvalLogFile.bytes` is what the
    /// writer wrote or what arrived, and running an imported file back through
    /// this app's encoder on the way out would hand somebody a different file
    /// from the one they gave us.
    static func write(_ file: EvalLogFile) throws -> Pair {
        Pair(log: try ExportFile.write(file.bytes, named: file.name),
             report: try ExportFile.write(Data(EvalReport.html(file).utf8), named: file.htmlName))
    }
}

/// One evaluation log, read the way a lab notebook is read.
///
/// NOT A SCOREBOARD. A scoreboard answers "did it win"; this answers "what
/// happened, and what would somebody need to believe the numbers". So the
/// headline carries the status word before any metric, the per scene grid shows
/// every epoch rather than the collapsed value alone, the errors are listed
/// with their messages instead of counted, and the last section before the
/// share is the one that says what this log is not.
///
/// EVERY FOREIGN STRING GOES THROUGH `EvalText.foreign`. The bench's criterion,
/// an imported log's task name, a scene id somebody else chose, a termination
/// reason, an operator's own note: none of them was written by this app, all of
/// them can be any length and carry any control character, and each is capped
/// and stripped on the way to a row. The file keeps them whole;
/// `EvalLogFile.fromTheFile` is drawn over the blocks that came out of it.
///
/// THE GRID FALLS BACK AT ACCESSIBILITY SIZES. A table whose columns are epochs
/// is a column of single characters at AX5, so past that threshold it becomes
/// one card per epoch. The horizontal scroll is inside its own container either
/// way, so the page never scrolls sideways.
///
/// NOTHING HERE COMPUTES. Every number is `EvalLog`'s, formatted by
/// `EvalReport.number`; every ordering is `EvalReport.ordered`; every sentence
/// is a kit constant.
struct EvalLogDetailView: View {
    let file: EvalLogFile
    @ObservedObject var evals: EvalStore

    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var sharing: EvalExport.Pair?
    @State private var shareFailure: String?
    @State private var destination: ExportedFile?

    // The publish form, in the shape `StairsSubmitView` already established.
    @State private var token = ""
    @State private var account: String?
    @State private var isPrivate = false
    @State private var busy = false
    @State private var publishFailure: String?
    @State private var published: String?
    /// The four files as they will be committed, built once.
    ///
    /// `EvalLogFile.files()` RENDERS THE WHOLE HTML REPORT AND THE WHOLE CARD.
    /// Calling it from a `ForEach` inside `body` would rebuild both on every
    /// pass of a screen that redraws whenever a character is typed into the
    /// token field.
    @State private var previews: [HuggingFacePublish.File] = []

    private var log: EvalLog { file.log }

    var body: some View {
        List {
            headline
            whatRan
            metrics
            scenes
            errors
            fromTheFileStats
            whatThisIsNot
            shareIt
            publishIt
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(EvalText.foreign(log.eval.task))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            token = TokenStore.load() ?? ""
            if previews.isEmpty { previews = file.files() }
        }
        .sheet(item: $sharing) { pair in
            ShareSheet(items: pair.items) { sharing = nil }
        }
        .sheet(item: $destination) { file in
            NavigationStack {
                ShareDestinationsView(title: EvalText.foreign(log.eval.task),
                                      file: file.url,
                                      message: EvalReport.shareSentence(self.file))
            }
        }
    }

    // MARK: - the headline

    private var headline: some View {
        Section {
            Text(EvalReport.statusShown(log.status))
                .font(.title3.weight(.bold))
                .foregroundStyle(tone(log.status))
            if let error = log.error {
                Text(EvalText.foreign(error))
                    .font(.footnote)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(EvalReport.reproduceSaid(log))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if file.origin == .imported {
                Text(EvalLogFile.importedSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.asked)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the spec strip

    /// What ran, in the file's own field names.
    ///
    /// THE LABELS ARE THE WIRE KEYS AND THAT IS DELIBERATE. This screen is the
    /// notebook for one file; naming its fields anything other than what the
    /// file calls them would mean a person reading this beside
    /// `inspect-robots view` has to translate. Every key comes from
    /// `EvalLog.Key`, which is the one place in either tree allowed to spell
    /// one.
    private var whatRan: some View {
        Section {
            TelemetryRow(label: EvalLog.Key.task, value: EvalText.foreign(log.eval.task))
            TelemetryRow(label: EvalLog.Key.policy, value: EvalText.foreign(log.eval.policy))
            TelemetryRow(label: EvalLog.Key.embodiment,
                         value: EvalText.foreign(log.eval.embodiment))
            TelemetryRow(label: EvalLog.Key.created, value: EvalText.foreign(log.eval.created))
            TelemetryRow(label: EvalLog.Key.startedAt,
                         value: EvalText.foreign(log.stats.startedAt))
            TelemetryRow(label: EvalLog.Key.completedAt,
                         value: EvalText.foreign(log.stats.completedAt))
            TelemetryRow(label: EvalLog.Key.durationSeconds,
                         value: EvalReport.number(log.stats.durationSeconds, places: 2))
            TelemetryRow(label: EvalLog.Key.totalScenes, value: String(log.results.totalScenes))
            TelemetryRow(label: EvalLog.Key.totalTrials, value: String(log.results.totalTrials))
            TelemetryRow(label: EvalLog.Key.totalSteps, value: String(log.stats.totalSteps))
            if let seconds = log.eval.maxSeconds, let steps = log.eval.maxSteps {
                Text(EvalReport.horizonSaid(seconds: seconds, steps: steps))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A SEED IS SHOWN AS THE FILE HAS IT AND NEVER EXPLAINED AWAY. Our
            // own logs carry none, and the sentence for that is the app's; a
            // log that does carry one came from a run somewhere else that had
            // one, and its own sentence says exactly that. There is one chooser
            // between the two, in the kit, and it has a third answer this
            // screen had no room for: a log from elsewhere with no seed gets
            // nothing, because "no route on this bench reads one" is a claim
            // about this bench and nobody here ran that file.
            if let seed = log.eval.seed {
                TelemetryRow(label: EvalLog.Key.seed, value: String(seed))
            }
            if let said = EvalReport.seedSaid(log) {
                Text(said)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            foreignBlock(EvalLog.Key.policyConfig, log.eval.policyConfig)
            foreignBlock(EvalLog.Key.embodimentInfo, log.eval.embodimentInfo)
        } header: {
            SectionHeading(text: EvalScreen.whatRanHeading)
        } footer: {
            Text(EvalLogFile.fromTheFile)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// One free form block of the file, key by key, sorted the way the file
    /// sorts them so the screen and the bytes are in the same order.
    @ViewBuilder private func foreignBlock(_ name: String,
                                           _ block: [String: EvalLogJSON]) -> some View {
        if !block.isEmpty {
            DisclosureGroup {
                ForEach(block.keys.sorted(), id: \.self) { key in
                    if let value = block[key] {
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                            Text(EvalText.foreign(key))
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                            Text(said(value))
                                .font(.caption)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, Theme.spacing(.hairline))
                        .accessibilityElement(children: .combine)
                    }
                }
            } label: {
                Text(name)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    /// One value of a free form block as a person reads it: a string as its own
    /// words, anything else as the JSON the file holds. Foreign either way.
    private func said(_ value: EvalLogJSON) -> String {
        EvalText.foreign(value.stringValue ?? value.encodedText())
    }

    // MARK: - the metrics

    /// The aggregate numbers, in reading order.
    ///
    /// SUCCESS AND THE EVIDENCE THAT KEEPS IT HONEST ARE ADJACENT, which is
    /// `EvalReport.ordered`'s whole argument: `success_at_end` is passed
    /// perfectly by a duck that never moves, so a block with the success tile
    /// alone at the top is a block whose first number is a lie by omission.
    private var metrics: some View {
        Section {
            if log.results.metrics.isEmpty {
                Text(EvalRun.erroredNotScoredSaid)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(EvalReport.ordered(Array(log.results.metrics.keys)), id: \.self) { name in
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    HStack(spacing: Theme.spacing(.tight)) {
                        Text(EvalText.foreign(name))
                            .font(.footnote.monospaced())
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.spacing(.tight))
                        Text(numberSaid(log.results.metrics[name]))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Theme.measured)
                    }
                    if let said = EvalReport.scorer(named: name)?.said {
                        Text(said)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Theme.spacing(.hairline))
                .accessibilityElement(children: .combine)
            }
            TelemetryRow(label: EvalLog.Key.erroredTrials,
                         value: String(log.results.erroredTrials))
        } header: {
            SectionHeading(text: EvalScreen.metricsHeading)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                Text(EvalReport.meanOverScenesSaid)
                Text(EvalRun.erroredNotScoredSaid)
            }
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// A metric that is present, or the word for one that is not a number.
    /// A metric that quietly became null is a metric nobody investigates.
    private func numberSaid(_ value: Double?) -> String {
        guard let value else { return EvalReport.notFinite }
        return EvalReport.number(value)
    }

    // MARK: - the scenes

    @ViewBuilder private var scenes: some View {
        // BY POSITION AND NOT BY `scene_id`. Ours are unique; an imported log's
        // are somebody else's strings and nothing in their schema stops two
        // samples sharing one, and two rows with one identity is a list SwiftUI
        // is entitled to draw wrong.
        ForEach(Array(log.samples.enumerated()), id: \.offset) { _, sample in
            Section {
                if let instruction = sample.instruction {
                    Text(EvalText.foreign(instruction))
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(EvalReport.statusShown(sample.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone(sample.status))
                if let error = sample.error {
                    Text(EvalText.foreign(error))
                        .font(.caption)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                reducedRows(sample)
                if typeSize.isAccessibilitySize {
                    epochCards(sample)
                } else {
                    epochGrid(sample)
                }
                // THE SPREAD SENTENCE IS THE SCENE'S AND NOT A LIST OF NUMBERS
                // WITH A CLAIM ATTACHED. The kit reads the axis off the scene
                // itself, so a grid cell, which is one episode with no drop
                // height, is not told that the drop height changed nothing;
                // and one epoch agreeing with itself says nothing at all.
                if let name = EvalReport.ordered(scorerNames(sample)).first,
                   let said = EvalReport.spreadSaid(sample, scorer: name) {
                    Text(said)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                verdicts(sample)
            } header: {
                SectionHeading(text: EvalText.foreign(sample.sceneID))
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    private func reducedRows(_ sample: EvalLog.Sample) -> some View {
        ForEach(EvalReport.ordered(Array(sample.reduced.keys)), id: \.self) { name in
            TelemetryRow(label: EvalText.foreign(name),
                         value: numberSaid(sample.reduced[name]))
        }
    }

    /// Columns are epochs, rows are scorers, and the whole thing scrolls inside
    /// its own container so the page never scrolls sideways.
    ///
    /// AN ERRORED EPOCH IS AN EMPTY CELL WITH THE WORD UNDER ITS COLUMN AND
    /// NEVER A ZERO. Zero is a measurement; an errored trial has none, and a
    /// column of zeros is the reading this grid exists to prevent.
    private func epochGrid(_ sample: EvalLog.Sample) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                HStack(spacing: Theme.spacing(.snug)) {
                    Text(EvalLog.Key.epochs)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: scorerColumn, alignment: .leading)
                    ForEach(sample.epochs.indices, id: \.self) { index in
                        Text(columnHead(sample, index))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: cellColumn, alignment: .trailing)
                    }
                }
                ForEach(scorerNames(sample), id: \.self) { name in
                    HStack(spacing: Theme.spacing(.snug)) {
                        Text(EvalText.foreign(name))
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: scorerColumn, alignment: .leading)
                        ForEach(sample.epochs.indices, id: \.self) { index in
                            Text(cell(sample, index, name))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(sample.epochs[index].isEmpty
                                                 ? Theme.refused : Theme.measured)
                                .frame(width: cellColumn, alignment: .trailing)
                        }
                    }
                    // ONE ELEMENT PER SCORER, NOT ONE PER CELL. VoiceOver walked
                    // the table cell by cell and read "1, 1, 0" with nothing
                    // saying which epoch or which drop height each belonged to,
                    // and the card layout that carries those labels is only
                    // reached at accessibility text sizes. The kit pairs every
                    // cell with its own column head, and names the empty ones,
                    // because a silence in that list reads as a zero.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(EvalText.foreign(name)))
                    .accessibilityValue(Text(EvalReport.spokenEpochs(sample, scorer: name)))
                }
            }
            .padding(.vertical, Theme.spacing(.hairline))
        }
        .accessibilityElement(children: .contain)
    }

    /// The same numbers as one card per epoch, for a text size where a table
    /// would be a column of single characters.
    private func epochCards(_ sample: EvalLog.Sample) -> some View {
        ForEach(sample.epochs.indices, id: \.self) { index in
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(columnHead(sample, index))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                if sample.epochs[index].isEmpty {
                    Text(EvalReport.statusShown(.error))
                        .font(.caption)
                        .foregroundStyle(Theme.refused)
                }
                ForEach(scorerNames(sample), id: \.self) { name in
                    TelemetryRow(label: EvalText.foreign(name),
                                 value: cell(sample, index, name))
                }
            }
            .padding(.vertical, Theme.spacing(.hairline))
            .accessibilityElement(children: .combine)
        }
    }

    /// The two column widths, in points at the default text size.
    ///
    /// `@ScaledMetric` AND NOT A CONSTANT, which is the fix `BenchView`'s
    /// `sigmaWidth` and `IntentListView`'s `angleColumn` both already carry: a
    /// hard 132 held about eighteen monospaced characters at Large and twelve
    /// at xxxLarge, so `peak_above_tread_mm` and `closest_approach_mm` were
    /// clipped at the DEFAULT size and `travelled_m` against
    /// `net_displacement_m` became two stubs on the one table that says which
    /// reading is which. The width still has to be a width rather than a
    /// minimum, because a column that grows per row is a table whose columns no
    /// longer line up under their own heads.
    @ScaledMetric(relativeTo: .caption) private var scorerColumn: CGFloat = 152
    @ScaledMetric(relativeTo: .caption) private var cellColumn: CGFloat = 76

    /// Every scorer either the reduced values or any epoch carries, in reading
    /// order.
    private func scorerNames(_ sample: EvalLog.Sample) -> [String] {
        var names = Set(sample.reduced.keys)
        for epoch in sample.epochs { names.formUnion(epoch.keys) }
        return EvalReport.ordered(Array(names))
    }

    /// What a column is: the drop height that epoch ran from when the scene
    /// recorded one, and the epoch's own number when it did not.
    private func columnHead(_ sample: EvalLog.Sample, _ index: Int) -> String {
        let drops = EvalReport.drops(sample)
        if index < drops.count { return EvalReport.number(drops[index]) }
        return String(index)
    }

    private func cell(_ sample: EvalLog.Sample, _ index: Int, _ name: String) -> String {
        guard index < sample.epochs.count else { return EvalReport.statusShown(.error) }
        guard let value = sample.epochs[index][name] else {
            return sample.epochs[index].isEmpty ? EvalReport.statusShown(.error) : ""
        }
        return EvalReport.number(value)
    }

    /// The verdicts recorded beside this scene's trials, if anybody watched
    /// one. Recorded and never scored, which the footer says out loud.
    @ViewBuilder private func verdicts(_ sample: EvalLog.Sample) -> some View {
        let given = sample.operatorJudgements.enumerated().filter { $0.element != nil }
        if !given.isEmpty {
            ForEach(given.map(\.offset), id: \.self) { index in
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(verdictSaid(sample, index))
                        .font(.caption)
                        .foregroundStyle(Theme.asked)
                    if index < sample.operatorNotes.count,
                       let note = EvalText.foreign(sample.operatorNotes[index]) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Theme.spacing(.hairline))
                .accessibilityElement(children: .combine)
            }
            Text(EvalVerdict.recordedNotScoredSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A verdict as this app words it when it knows the answer, and as the file
    /// has it when it does not: an imported log may carry a word from a path
    /// this app has never offered.
    private func verdictSaid(_ sample: EvalLog.Sample, _ index: Int) -> String {
        guard index < sample.operatorJudgements.count,
              let raw = sample.operatorJudgements[index] else { return "" }
        guard let answer = EvalVerdict.Answer(rawValue: raw) else { return EvalText.foreign(raw) }
        return answer.said
    }

    // MARK: - the errors

    /// Listed, never counted.
    ///
    /// A COUNT WITH NO MESSAGES IS A PROGRESS BAR WEARING A LAB COAT. The
    /// number is already in the metrics block; what belongs here is what each
    /// one actually said, in the bench's own words.
    @ViewBuilder private var errors: some View {
        let messages = log.samples.compactMap(\.error)
        if !messages.isEmpty {
            Section {
                ForEach(messages.indices, id: \.self) { index in
                    Text(EvalText.foreign(messages[index]))
                        .font(.footnote)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeading(text: EvalScreen.errorsHeading)
            } footer: {
                Text(EvalLogFile.fromTheFile)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    // MARK: - what this is not

    private var whatThisIsNot: some View {
        Section {
            ForEach(caveats, id: \.self) { sentence in
                Text(sentence)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: EvalScreen.whatThisIsNotHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Every claim this log does not make, in one list so nothing can be added
    /// to the screen without being added to the reading.
    ///
    /// THE FIRST PERSON HALF IS THE KIT'S AND IT IS CHOSEN BY THE FILE. "No
    /// frames were stored", "nothing here timed the policy", "the terms under
    /// each trial are the bench's" are all this app describing its own bench,
    /// and this screen printed them over imported logs too, including two that
    /// the file's own stats flatly contradicted. `EvalReport.caveats(for:)`
    /// returns nothing for a log this app did not write, and picks the
    /// recording sentences by route for one it did, so a grid is not described
    /// as having recorded a trajectory it never had.
    private var caveats: [String] {
        var lines: [String] = []
        // THE TWO MACHINE FACTS, NOT THE IDENTITY STRING. `DuckBench.plantSaid`
        // takes the name and the digest apart and says the right thing about
        // each absence, including a log with no world block at all, which is
        // what an imported one may be.
        lines.append(DuckBench.plantSaid(
            name: log.eval.embodimentInfo[EvalMeta.plantName]?.stringValue,
            digest: log.eval.embodimentInfo[EvalMeta.plantDigest]?.stringValue))
        lines.append(contentsOf: EvalReport.caveats(for: file))
        if let challenge = EvalReport.challenge(log) {
            lines.append(EvalReport.leaderboardIsTheChallengeScreen)
            lines.append(challenge.realDuckCaveat)
        } else {
            lines.append(EvalEmbodiment.realMicroduckRefusal)
        }
        lines.append(EvalLogFile.aLogIsFinished)
        lines.append(EvalText.notTheirRender)
        lines.append(Provenance.independenceShort)
        return lines
    }

    /// The two `stats` fields this app never fills, drawn only when the file
    /// that arrived does fill them.
    ///
    /// A LABEL AND THE FILE'S OWN VALUE, WITH NO SENTENCE OF OURS OVER IT. The
    /// page used to assert that nothing timed the policy and no frames were
    /// stored, over files whose `mean_inference_latency_s` and `frames_dir`
    /// said otherwise two sections up.
    @ViewBuilder private var fromTheFileStats: some View {
        if log.stats.meanInferenceLatencySeconds != nil || log.stats.framesDir != nil {
            Section {
                if let latency = log.stats.meanInferenceLatencySeconds {
                    TelemetryRow(label: EvalReport.latencyLabel,
                                 value: EvalReport.number(latency, places: 4))
                }
                if let frames = log.stats.framesDir {
                    TelemetryRow(label: EvalReport.framesLabel,
                                 value: EvalText.foreign(frames))
                }
            } footer: {
                Text(EvalLogFile.fromTheFile)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    // MARK: - share

    private var shareIt: some View {
        Section {
            Button {
                share()
            } label: {
                Label(EvalScreen.shareTheLogAndTheReportSaid, systemImage: "square.and.arrow.up")
            }
            Button {
                sendSomewhere()
            } label: {
                Label(EvalScreen.sendItSomewhereSaid, systemImage: "paperplane")
            }
            if let shareFailure {
                Text(shareFailure)
                    .font(.footnote)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(EvalReport.whatIsShared)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: EvalScreen.shareHeading)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                Text(EvalLogFile.howToRead)
                Text(EvalLogFile.oneLogAtATimeSaid)
            }
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func share() {
        do {
            sharing = try EvalExport.write(file)
            shareFailure = nil
        } catch {
            shareFailure = EvalMessage.of(error)
        }
    }

    /// The paragraph plus the file, through the sheet this app already uses for
    /// a message worth pasting and a place to paste it. Nothing is posted for
    /// anybody: `CommunityShare.destinations` are links and the sheet says so.
    private func sendSomewhere() {
        do {
            destination = ExportedFile(url: try ExportFile.write(file.bytes, named: file.name))
            shareFailure = nil
        } catch {
            shareFailure = EvalMessage.of(error)
        }
    }

    // MARK: - publish

    /// A dataset under the operator's own account, or the refusal for a log
    /// this app did not write.
    ///
    /// EVERY BYTE OF EVERY FILE IS ON SCREEN BEFORE THE COMMIT. An operator's
    /// own note goes into the log and from there into the card, and publishing
    /// one unseen is how somebody finds out what they wrote by reading it on
    /// Hugging Face.
    @ViewBuilder private var publishIt: some View {
        if file.canPublish {
            Section {
                // THE FIVE WORDS OF THIS FORM ARE THE KIT'S, like every other
                // word on this screen. They were typed here in shapes
                // `check_stage_sentences.sh` could not see, which is how a file
                // whose header says it draws no sentence of its own shipped
                // four of them; the guard reads those shapes now.
                SecureField(EvalScreen.tokenFieldSaid, text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // A PLACEHOLDER IS NOT A LABEL. VoiceOver reads the
                    // placeholder, so the field announced itself as "hf",
                    // which names nothing.
                    .accessibilityLabel(Text(EvalScreen.tokenLabelSaid))
                Button(EvalScreen.checkThisTokenSaid) { Task { await check() } }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                if let account {
                    Label(HuggingFacePublish.publishingAs(account),
                          systemImage: "person.crop.circle.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(Theme.success)
                }
                Toggle(EvalScreen.privateRepositorySaid, isOn: $isPrivate)
                // PUBLIC IS A CAVEAT AND PRIVATE IS NOT, the distinction
                // `StairsSubmitView` draws: one of these is reversible and the
                // other is not. It is a row and not the section's footer,
                // because a footer is drawn on the list's own ground, where
                // `Theme.warning` measures 4.25:1 and owes 4.5:1; on the card
                // this row sits on it clears.
                if !isPrivate {
                    Label(HuggingFacePublish.publicWarning,
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                filePreviews
                Button {
                    Task { await publish() }
                } label: {
                    HStack(spacing: Theme.spacing(.tight)) {
                        Text(isPrivate ? EvalScreen.commitPrivateSaid
                                       : EvalScreen.commitPublicSaid)
                            .frame(maxWidth: .infinity)
                        if busy { ProgressView() }
                    }
                }
                .buttonStyle(.primaryAction)
                .disabled(busy || account == nil || published != nil)
                if let published, let url = URL(string: published) {
                    Link(destination: url) {
                        Label(HuggingFacePublish.openItOnHuggingFace,
                              systemImage: "arrow.up.right.square")
                    }
                }
                if let publishFailure {
                    Text(publishFailure)
                        .font(.footnote)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeading(text: EvalScreen.publishItHeading)
            }
            .listRowBackground(Theme.surfacePrimary)
        } else {
            Section {
                Text(EvalLogFile.cannotPublishImported)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: EvalScreen.publishItHeading)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    /// The four files as they will be committed, each openable, each with its
    /// own byte count beside it.
    private var filePreviews: some View {
        ForEach(previews, id: \.path) { outgoing in
            DisclosureGroup {
                Text(String(decoding: outgoing.contents, as: UTF8.self))
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                TelemetryRow(label: outgoing.path, value: String(outgoing.bytes))
            }
        }
    }

    private func check() async {
        busy = true; publishFailure = nil
        defer { busy = false }
        let request = HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(), token: token)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                publishFailure = http.statusCode == 401
                    ? HuggingFacePublish.tokenRefused
                    : HuggingFacePublish.answered(http.statusCode)
                return
            }
            guard let name = HuggingFacePublish.parseWhoami(data) else {
                publishFailure = HuggingFacePublish.noAccountNamed
                return
            }
            account = name
            TokenStore.save(token)
        } catch {
            publishFailure = EvalMessage.of(error)
        }
    }

    /// Create then commit, and the calls themselves are the kit's, so the
    /// licence, the card and the commit summary are the ones `swift test`
    /// reads.
    private func publish() async {
        guard let account else { return }
        busy = true; publishFailure = nil
        defer { busy = false }
        do {
            let calls = try file.publishCalls(namespace: account, isPrivate: isPrivate)
            let (_, createResponse) = try await URLSession.shared.data(
                for: HuggingFacePublish.urlRequest(for: calls.create, token: token))
            if let http = createResponse as? HTTPURLResponse,
               http.statusCode != 200, http.statusCode != 409 {   // 409: it already exists
                publishFailure = HuggingFacePublish.creating(http.statusCode)
                return
            }
            let (data, commitResponse) = try await URLSession.shared.data(
                for: HuggingFacePublish.urlRequest(for: calls.commit, token: token))
            if let http = commitResponse as? HTTPURLResponse, http.statusCode >= 300 {
                let detail = String(decoding: data.prefix(200), as: UTF8.self)
                publishFailure = HuggingFacePublish.answered(http.statusCode)
                    + " " + EvalText.foreign(detail)
                return
            }
            published = calls.repository.webURL
            Haptic.finished()
        } catch {
            publishFailure = EvalMessage.of(error)
        }
    }

    private func tone(_ status: EvalLog.Status) -> Color {
        switch status {
        case .success: return Theme.success
        case .error: return Theme.critical
        case .cancelled, .started: return Theme.textSecondary
        }
    }
}
