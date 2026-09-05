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
struct EvalListView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var benches: BenchStore
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var evals: EvalStore

    @State private var importing = false

    var body: some View {
        List {
            preamble
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

    // MARK: - run one

    private var runOne: some View {
        Section {
            NavigationLink {
                EvalSetupView(model: model, benches: benches, evals: evals)
            } label: {
                Label("New evaluation", systemImage: "checklist")
            }
        } header: {
            SectionHeading(text: "Run one")
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
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if let unreadable = evals.unreadable {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    // THE COUNT IS THE `ModelEndpoint.Salvage` SHAPE: one bad
                    // file must not empty the list, and a file that was
                    // swallowed has to be a number on screen rather than
                    // silence.
                    Text(String(unreadable))
                        .font(.footnote.monospacedDigit())
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
            SectionHeading(text: "Saved")
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
    private func headline(_ file: EvalLogFile) -> String? {
        let names = EvalReport.ordered(Array(file.log.results.metrics.keys))
        guard let first = names.first, let value = file.log.results.metrics[first] else {
            return nil
        }
        return "\(first) \(EvalReport.number(value))"
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
                Label("Put two side by side", systemImage: "arrow.left.arrow.right")
            }
            .disabled(evals.comparable.count < 2)

            Text(EvalCompare.whatCanBeComparedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(EvalCompare.neverCombinedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "Compare")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - a log from somewhere else

    private var fromElsewhere: some View {
        Section {
            Button {
                importing = true
            } label: {
                Label("Open a log from elsewhere", systemImage: "square.and.arrow.down")
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
            SectionHeading(text: "Open one from elsewhere")
        } footer: {
            Text(EvalLogFile.howToRead)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }
}
