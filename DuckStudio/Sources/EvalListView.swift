import SwiftUI
import UniformTypeIdentifiers
import StudioKit

/// The shelf: every evaluation log this phone wrote, and every one it was
/// handed.
///
/// THE SIXTH DOOR UNDER MEASURE, AND THE ONLY ONE THAT ENDS IN A FILE SOMEBODY
/// ELSE'S TOOL READS. Tune, the weight search and the move search all end on
/// this phone; a challenge ends in a submission this project's own harness
/// re-scores. This ends in an EvalLog v1, which is inspect-robots' format, so a
/// number measured here can be read by a program that has never heard of this
/// app.
///
/// THE IMPORT DOOR IS HERE AND NOT IN `onOpenURL`. `.json` is not this app's
/// type to own, which is the argument `DuckStudioApp.swift:359-361` already
/// makes about ONNX: claiming it would put this app in front of every JSON file
/// on the phone, and most of them are not evaluation logs.
///
/// ONE LOG AT A TIME, AND THE FOOTER SAYS SO. There is no export of the whole
/// shelf in this build, and a Share button that silently handed over one file
/// would be a person wondering where the other nine went.
///
/// `drafts` AND `scenes` ARE HELD AND NOT READ. `place(.evaluations)` hands
/// every Studio place the same stores; nothing on this screen or the ones it
/// opens needs a draft or a scene, because a grid preset runs a PUBLISHED
/// challenge entrant rather than something authored here.
///
/// A RUN IN FLIGHT IS ON THIS SCREEN, WITH ITS STOP. The runner is owned above
/// both this screen and the setup screen, so a run survives being walked away
/// from; what it must never survive is being walked away from with no way back
/// to it and no way to end it. The banner is that way back, and the Stop under
/// it is the same one the run screen draws.
struct EvalListView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var benches: BenchStore
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var evals: EvalStore
    @ObservedObject var runner: EvalRunner

    @State private var importing = false

    var body: some View {
        List {
            preamble
            runningNow
            runOne
            saved
            compare
            fromElsewhere
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(EvalTask.rowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { evals.reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): evals.importLog(at: url)
            case .failure(let error): evals.failure = EvalMessage.of(error)
            }
        }
    }

    // MARK: - what this is

    private var preamble: some View {
        Section {
            Text(EvalTask.whatAnEvaluationIs)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - a run that is still going

    /// The run in flight, from wherever it was started.
    ///
    /// THE STOP IS HERE BECAUSE THE RUN OUTLIVES THE SCREEN THAT STARTED IT.
    /// Somebody who backs out of the run screen and then out of the setup
    /// screen used to leave three minutes of bench work going with no control
    /// anywhere in the app and no sentence saying it was still happening. The
    /// row leads back to the same runner, never to a second one, and the
    /// button under it is the same `stop()` the run screen calls.
    @ViewBuilder private var runningNow: some View {
        if runner.running {
            Section {
                NavigationLink {
                    EvalRunView(runner: runner, evals: evals)
                } label: {
                    Label(runner.task?.name ?? EvalTask.rowTitle,
                          systemImage: "waveform.path.ecg")
                }
                TelemetryRow(label: EvalScreen.scenesSaid, value: scenesCounted)
                stopIt
            } header: {
                SectionHeading(text: EvalScreen.runningHeading)
            } footer: {
                Text(EvalTask.stopIsNotAFailure)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    /// Two numbers the runner keeps apart, said the way the run screen says
    /// them, because a count that read differently in two places would be two
    /// answers to where the run has got to.
    private var scenesCounted: String {
        "\(runner.scenesDone) of \(runner.scenesTotal)"
    }

    /// NEVER `.disabled`, and the word changes only because the tap landed.
    /// The run screen's own Stop makes the same promise in the same words.
    private var stopIt: some View {
        Button(role: .destructive) {
            runner.stop()
        } label: {
            Text(runner.stopped ? EvalScreen.stoppingAfterThisSceneSaid
                                : EvalScreen.stopSaid)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - run one

    private var runOne: some View {
        Section {
            NavigationLink {
                EvalSetupView(model: model, benches: benches, evals: evals,
                              runner: runner)
            } label: {
                Label(EvalScreen.newEvaluationSaid, systemImage: "checklist")
            }
        } header: {
            SectionHeading(text: EvalScreen.runOneHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the shelf

    private var saved: some View {
        Section {
            if evals.files.isEmpty {
                Text(EvalTask.nothingRunYet)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(evals.files) { file in
                NavigationLink {
                    EvalLogDetailView(file: file, evals: evals)
                } label: {
                    row(file)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        evals.delete(file)
                    } label: {
                        Label(EvalScreen.deleteSaid, systemImage: "trash")
                    }
                }
            }
            if let unreadable = evals.unreadable {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    // THE COUNT IS THE `ModelEndpoint.Salvage` SHAPE: one bad
                    // file must not empty the list, and a file that was
                    // swallowed has to be a number on screen rather than
                    // silence. `Salvage.note` is a whole sentence with the
                    // count inside it, and this was the numeral alone: an
                    // orange 3 over a paragraph about strictness, which
                    // VoiceOver read as "3" followed by an unrelated claim.
                    Text(EvalLogReader.unreadableSaid(unreadable))
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                    Text(EvalLogReader.asStrictAsTheirs)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.spacing(.hairline))
                .accessibilityElement(children: .combine)
            }
            if let failure = evals.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: EvalScreen.savedHeading)
        } footer: {
            Text(EvalLogFile.oneLogAtATimeSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// One log, said in the order somebody scanning the shelf reads it: what it
    /// was, how it ended, the one number that leads, and the world it means
    /// anything in.
    ///
    /// THE STATUS IS A WORD AND A COLOUR AND NEVER A COLOUR ALONE, and the word
    /// is inspect-robots' own, so this shelf and their viewer agree about what
    /// a run is called.
    private func row(_ file: EvalLogFile) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(spacing: Theme.spacing(.tight)) {
                Text(title(file))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.spacing(.tight))
                Text(EvalReport.statusShown(file.log.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone(file.log.status))
            }
            if let headline = headline(file) {
                Text(headline)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.measured)
            }
            Text(EvalText.foreign(file.log.eval.embodiment))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.spacing(.tight)) {
                Text(EvalText.foreign(file.log.stats.startedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                if file.origin == .imported {
                    Text(EvalLogFile.importedBadge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.asked)
                        .padding(.horizontal, Theme.spacing(.hairline))
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius(.chip))
                                .strokeBorder(Theme.asked))
                }
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
        .accessibilityElement(children: .combine)
    }

    /// A written log's task name is this app's own; an imported one's came out
    /// of somebody else's file and is capped and stripped on the way to a row.
    private func title(_ file: EvalLogFile) -> String {
        file.origin == .imported ? EvalText.foreign(file.log.eval.task) : file.log.eval.task
    }

    /// The one metric a row leads with, in reading order: the success scorer
    /// first, then the evidence that keeps it honest. `EvalReport.ordered` owns
    /// that order and this reads it.
    ///
    /// THE NAME IS FOREIGN EVEN WHEN THE LOG IS OURS. A metric key is a scorer
    /// name, and an imported log's came out of somebody else's file with no
    /// bound on its length and nothing stopping a control character in it. The
    /// detail screen already caps the same names; a row on a `List` is the last
    /// place that can afford not to.
    private func headline(_ file: EvalLogFile) -> String? {
        let names = EvalReport.ordered(Array(file.log.results.metrics.keys))
        guard let first = names.first, let value = file.log.results.metrics[first] else {
            return nil
        }
        return "\(EvalText.foreign(first)) \(EvalReport.number(value))"
    }

    private func tone(_ status: EvalLog.Status) -> Color {
        switch status {
        case .success: return Theme.success
        case .error: return Theme.critical
        case .cancelled, .started: return Theme.textSecondary
        }
    }

    // MARK: - two side by side

    private var compare: some View {
        Section {
            NavigationLink {
                EvalCompareView(evals: evals)
            } label: {
                Label(EvalScreen.putTwoSideBySideSaid, systemImage: "arrow.left.arrow.right")
            }
            .disabled(evals.comparable.count < 2)

            // THE REASON THE ROW IS DIM GOES UNDER THE ROW, which is the house
            // rule at `StudioHubView.swift:293`. The rule about tasks and
            // worlds below answers a different question, and a person with one
            // log read it and still could not tell which of the two situations
            // they were in.
            if evals.comparable.count < 2 {
                Text(EvalCompare.notEnoughLogsSaid(evals.comparable.count))
                    .font(.caption)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(EvalCompare.whatCanBeComparedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(EvalCompare.neverCombinedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: EvalScreen.compareHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - a log from somewhere else

    private var fromElsewhere: some View {
        Section {
            Button {
                importing = true
            } label: {
                Label(EvalScreen.openALogFromElsewhereSaid, systemImage: "square.and.arrow.down")
            }
            Text(EvalLogFile.whatAnImportedLogMustBe)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(EvalLogFile.importedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: EvalScreen.openOneFromElsewhereHeading)
        } footer: {
            Text(EvalLogFile.howToRead)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }
}
