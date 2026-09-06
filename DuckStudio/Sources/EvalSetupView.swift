import SwiftUI
import StudioKit

/// Setting up one evaluation, and refusing the combinations that cannot be run
/// before a minute of physics is spent on them.
///
/// EVERY REFUSAL IS UNDER THE CONTROL THAT CAUSED IT, WITH START DISABLED.
/// That is the house rule this app already keeps at `StudioHubView.swift:293`:
/// the reason goes under the name rather than into a dialog after the tap. It
/// matters more here than anywhere else, because the tap it prevents costs
/// three minutes of somebody's afternoon and ends on the bench's own error
/// message, which is a failure this project has already paid for once with
/// `/tune` and the phone bench.
///
/// A PRESET IS A WHOLE PLAN. There is no epoch count, no seed field and no
/// reducer picker, because `EvalTask`'s four factories fill the scenes, the
/// axis, the reducer, the horizon and the scorers, and a control that could
/// disagree with them would be a second opinion about what a preset means.
/// What a person picks is the preset and the thing being evaluated, and
/// everything else on this screen is the plan reading itself out.
///
/// NOTHING HERE THROWS AND NOTHING HERE COMPUTES. Every kit factory in this
/// feature throws; they are all called inside `EvalRunner`, which catches, so a
/// `View` property initialiser cannot be the thing that fails. Every number is
/// the kit's and every sentence is a `static let` in it.
///
/// THE STRUCTURAL LABELS ARE IN THE KIT TOO. The section headings, the toggle
/// and the Start button are `EvalScreen` constants, pinned character for
/// character by `EvalScreenTests`, so this file draws no word of its own and
/// `scripts/check_stage_sentences.sh` holds it to that with nothing in the
/// allow-list.
struct EvalSetupView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var benches: BenchStore
    @ObservedObject var evals: EvalStore
    /// HANDED IN AND NOT MADE HERE. It was a `@StateObject` on this screen,
    /// which meant the run belonged to a view somebody could pop: two taps on
    /// Back left the bench working for minutes with no Stop anywhere in the
    /// app, and a run that was still asking for verdicts could never file its
    /// log, because the queue is drained by a sheet that no longer had a
    /// screen. It is owned where `EvalStore` is owned now, so this screen sets
    /// a run up and never holds its life.
    @ObservedObject var runner: EvalRunner
    @State private var showRun = false

    var body: some View {
        Form {
            whatToEvaluate
            whatIsBeingRun
            theEmbodiment
            theEpochs
            howItIsScored
            watchAndJudge
            startIt
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(EvalTask.rowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            runner.prepare()
            if runner.policyID == nil { runner.policyID = candidates.first?.id }
            await runner.probe(benches: benches)
            Haptic.prepare()
        }
        // THE RUN SCREEN IS `EvalRunView`, WHICH TAKES THE RUNNER THIS SCREEN
        // SET UP. Building a second runner there would be a second probe, a
        // second embodiment and a second answer to what was chosen here.
        .navigationDestination(isPresented: $showRun) {
            EvalRunView(runner: runner, evals: evals)
        }
    }

    // MARK: - what to evaluate

    private var whatToEvaluate: some View {
        Section {
            // A PRESET THAT WOULD NOT BUILD IS NOT LISTED. Every name in this
            // picker is its own task's `name`, so a row for a task that does
            // not exist would have to be titled by something typed here.
            Picker(selection: presetBinding) {
                ForEach(EvalPreset.allCases.filter { runner.catalogue[$0] != nil }) { preset in
                    Text(runner.catalogue[preset]?.name ?? "").tag(preset)
                }
            } label: {
                Text(EvalTask.rowTitle)
            }
            .disabled(runner.running)

            if let said = runner.task?.said {
                paragraph(said, tone: Theme.textSecondary)
            }
            if let refusal = runner.taskRefusal {
                paragraph(refusal, tone: Theme.refused)
            }
            paragraph(EvalTask.whyNotMeasure, tone: Theme.textTertiary, size: .caption)
            paragraph(EvalTask.whyNotPerform, tone: Theme.textTertiary, size: .caption)
            paragraph(EvalScorer.notEmittedHere, tone: Theme.textTertiary, size: .caption)
        } header: {
            SectionHeading(text: EvalScreen.whatToEvaluateHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// THE SETTER MOVES THE STATE NOW AND ASKS THE BENCH AFTERWARDS. A binding
    /// whose `get` does not answer with what was just set makes a `Picker` snap
    /// back to the old row while the probe is in flight, which reads as a
    /// control that ignored the tap.
    private var presetBinding: Binding<EvalPreset> {
        Binding(get: { runner.preset },
                set: { chosen in
                    runner.settle(on: chosen)
                    Task { await runner.choose(chosen, benches: benches) }
                })
    }

    // MARK: - the thing being evaluated

    /// The policy for a walk preset, the published entrant for a grid.
    ///
    /// THE PICKER IS FILTERED AND THE FILTER IS EXPLAINED. `/tune` folds a gain
    /// into the last layer, which means holding the network's parameters, so a
    /// file this app could not load has nothing to fold and the bench refuses
    /// it by name before any physics. Listing those files and refusing after
    /// the tap is the dead end this screen exists to prevent, so they are not
    /// listed and `canonicalParametersSaid` says why.
    @ViewBuilder private var whatIsBeingRun: some View {
        if runner.preset.evaluatesANetwork {
            Section {
                Picker(selection: $runner.policyID) {
                    ForEach(candidates) { entry in
                        Text(pickerLabels[entry.id] ?? entry.title)
                            .tag(String?.some(entry.id))
                    }
                } label: {
                    Text(EvalPolicy.Kind.libraryNetwork.said)
                }
                .disabled(runner.running)

                // THE LABEL IS THE VALUE AND THE SENTENCE IS THE HINT. This row
                // is the only statement on the screen of WHICH network is about
                // to consume three minutes, and it read the plant's sentence in
                // place of it: a paragraph about the world's sha256, spoken over
                // the policy's own name and digest. `spokenLogName` is the same
                // twelve characters said as a person can check them, and the
                // hint is the policy's sentence rather than the world's.
                if let policy {
                    Text(policy.logName)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.measured)
                        .accessibilityLabel(Text(policy.spokenLogName))
                        .accessibilityHint(Text(EvalPolicy.digestIsIdentitySaid))
                }
                // THE SAME SENTENCE, IN THE REFUSAL'S COLOUR WHEN IT IS THE
                // REASON THERE IS NOTHING TO PICK. A library with no network
                // this app could digest leaves an empty picker and a dead
                // Start button, and the reason has to be under the control
                // rather than absent.
                paragraph(EvalPolicy.canonicalParametersSaid,
                          tone: candidates.isEmpty ? Theme.refused : Theme.textSecondary,
                          size: .caption)
                if holdsAFileOnlyPolicy {
                    paragraph(EvalPolicy.fileOnlySaid, tone: Theme.textTertiary, size: .caption)
                }
            } header: {
                SectionHeading(text: EvalScreen.whatIsBeingEvaluatedHeading)
            }
            .listRowBackground(Theme.surfacePrimary)
        } else {
            Section {
                Picker(selection: $runner.entrantFile) {
                    ForEach(runner.entrants) { entrant in
                        Text(entrant.title).tag(String?.some(entrant.file))
                    }
                } label: {
                    Text(EvalPolicy.Kind.challengeEntrant.said)
                }
                .disabled(runner.running)

                paragraph(EvalReport.leaderboardIsTheChallengeScreen,
                          tone: Theme.textSecondary, size: .caption)
                if runner.preset == .stairsGrid {
                    paragraph(StairsChallenge.riseSaid(runner.rise),
                              tone: Theme.textTertiary, size: .caption)
                    if runner.stairsIsFallback {
                        paragraph(StairsChallenge.Grid.fallbackNote,
                                  tone: Theme.warning, size: .caption)
                    }
                } else if runner.ballIsFallback {
                    paragraph(BallChallenge.Grid.fallbackNote,
                              tone: Theme.warning, size: .caption)
                }
            } header: {
                SectionHeading(text: EvalScreen.whatIsBeingEvaluatedHeading)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    // MARK: - the embodiment

    /// The bench that will run it, and the body that cannot.
    ///
    /// THE REAL MICRODUCK IS A ROW AND NOT AN ABSENCE. Hiding it would leave
    /// somebody wondering whether the app can drive one; the row says it cannot
    /// and says when the first ones ship, which is the answer to the question
    /// they were about to ask.
    private var theEmbodiment: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(bodySaid)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let name = benches.selected?.name {
                    Text(name)
                        .font(.footnote)
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
            }
            .padding(.vertical, Theme.spacing(.hairline))

            // NO BARE `ProgressView()` HERE. A spinner with no words is a
            // spinner VoiceOver reads as nothing at all, which is the rule the
            // Start section states forty lines down; the probe is reported
            // there, in words, and saying it twice would teach a person to
            // read neither.
            if let refusal = runner.embodimentRefusal {
                paragraph(refusal, tone: Theme.refused, size: .footnote)
            }
            if let unreachable = runner.unreachable {
                paragraph(unreachable, tone: Theme.refused, size: .footnote)
            }
            if let notYet = runner.notYet {
                paragraph(notYet, tone: Theme.warning, size: .footnote)
            }

            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(EvalEmbodiment.Body.realMicroduck.said)
                    .font(.body)
                    .foregroundStyle(Theme.textTertiary)
                Text(EvalEmbodiment.realMicroduckRefusal)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Theme.spacing(.hairline))
            .accessibilityElement(children: .combine)
        } header: {
            SectionHeading(text: EvalScreen.whereItRunsHeading)
        } footer: {
            Text(EvalEmbodiment.notSeedable)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the epochs

    private var theEpochs: some View {
        Section {
            if let epochs = runner.task?.epochs {
                paragraph(epochs.said, tone: Theme.textPrimary, size: .footnote)
                paragraph(epochs.reducer.said, tone: Theme.measured, size: .footnote)
            }
            paragraph(EvalEpochs.noSeedSaid, tone: Theme.textSecondary, size: .caption)
            paragraph(EvalEpochs.noPassAtK, tone: Theme.textTertiary, size: .caption)
        } header: {
            SectionHeading(text: EvalScreen.whatVariesHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the scorers

    /// Read only, because a scorer set is part of the plan and not a choice.
    ///
    /// SUCCESS AND MOTION EVIDENCE ARE ADJACENT, which is `EvalReport.ordered`'s
    /// whole argument: `success_at_end` is passed perfectly by a duck that
    /// never moves, so a list with the success scorer alone at the top would be
    /// a list whose first row is a lie by omission.
    private var howItIsScored: some View {
        Section {
            ForEach(runner.task?.scorers.scorers ?? []) { scorer in
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(scorer.name)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                    Text(scorer.said)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.spacing(.hairline))
                .accessibilityElement(children: .combine)
            }
            paragraph(EvalScorer.termsAreNotScoresSaid, tone: Theme.textTertiary, size: .caption)
        } header: {
            SectionHeading(text: EvalScreen.howItIsScoredHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the verdict path

    /// THE TOGGLE IS DISABLED ON A GRID AND THE REASON IS THE ROW UNDER IT,
    /// rather than the section being hidden. Only `/tune` answers with a
    /// trajectory, so on a grid preset there is no episode anybody could watch
    /// and no verdict to be asked for. A section that disappeared would leave
    /// somebody who had used it once looking for it.
    private var watchAndJudge: some View {
        Section {
            Toggle(isOn: $runner.wantsVerdicts) {
                Text(EvalScreen.askMeAboutTheTrialSaid)
            }
            .disabled(runner.task?.wantsTrace != true || runner.running)

            // THE REASON UNDER THE TOGGLE IS ABOUT THE ROUTE THAT IS ACTUALLY
            // SELECTED. `firstDropOnlySaid` describes a trajectory the bench
            // returns for one drop of each call, which is `/tune` and nothing
            // else: printed on a grid preset it asserted there was an episode
            // to watch on exactly the two presets where there is none, under a
            // control that had disabled itself for that very reason.
            if runner.task?.wantsTrace == true {
                paragraph(EvalTrace.firstDropOnlySaid, tone: Theme.textSecondary, size: .caption)
            } else {
                paragraph(EvalTrace.noTraceOnAGridSaid, tone: Theme.refused, size: .caption)
            }
            paragraph(EvalVerdict.recordedNotScoredSaid, tone: Theme.textTertiary,
                      size: .caption)
            paragraph(EvalVerdict.vocabularySaid, tone: Theme.textTertiary, size: .caption)
        } header: {
            SectionHeading(text: EvalScreen.watchAndJudgeHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - Start

    /// NO START BUTTON BEFORE THE PROBE, which is `StairsRun.hasProbed`'s rule:
    /// a control offered before the bench has said what it can do is a control
    /// that finds out afterwards.
    ///
    /// AND NOT DURING A LATER ONE EITHER. `hasProbed` latches on the first
    /// answer and never clears, so every re-probe, which is every change of
    /// preset and for a walk preset a real one second episode on the bench,
    /// drew a live Start button over an embodiment the probe had just set back
    /// to nil. The tap returned before it set anything and pushed a run screen
    /// with one heading and nothing under it. This branches on `probing`, which
    /// is what every sibling screen in this app already gates on.
    ///
    /// A RUN IN FLIGHT REPLACES START WITH THE WAY BACK TO IT. The runner
    /// outlives this screen now, so the honest thing under it is the run that
    /// is happening rather than a button that silently does nothing.
    private var startIt: some View {
        Section {
            if runner.running {
                Button {
                    showRun = true
                } label: {
                    Label(runner.task?.name ?? EvalTask.rowTitle,
                          systemImage: "waveform.path.ecg")
                }
                TelemetryRow(label: EvalScreen.scenesSaid, value: scenesCounted)
                Button(role: .destructive) {
                    runner.stop()
                } label: {
                    Text(runner.stopped ? EvalScreen.stoppingAfterThisSceneSaid
                                        : EvalScreen.stopSaid)
                        .frame(maxWidth: .infinity)
                }
            } else if runner.probing || !runner.hasProbed {
                // NO START BUTTON AND NO PROMISE OF ONE while the bench is
                // still being asked. A spinner with no words is a spinner
                // VoiceOver reads as nothing at all.
                HStack(spacing: Theme.spacing(.tight)) {
                    ProgressView()
                    Text(EvalScreen.askingThisBenchSaid)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if let refusal = startRefusalToDraw {
                    paragraph(refusal, tone: Theme.refused, size: .footnote)
                }
                Button {
                    start()
                } label: {
                    Text(EvalScreen.startSaid).frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                // THE EMBODIMENT IS IN THE GATE BECAUSE `start` GUARDS ON IT.
                // A button whose tap is a no operation is a button that told
                // somebody something happened.
                .disabled(startRefusal != nil || policy == nil || runner.task == nil
                          || runner.embodiment == nil)
                .accessibilityLabel(Text(EvalTask.rowTitle))
            }
            if let failure = runner.failure {
                paragraph(failure, tone: Theme.refused, size: .footnote)
            }
        } footer: {
            Text(EvalTask.stopIsNotAFailure)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Where the run has got to, said the way the run screen and the shelf say
    /// it, because three answers to one question is two too many.
    private var scenesCounted: String {
        "\(runner.scenesDone) of \(runner.scenesTotal)"
    }

    private func start() {
        guard let policy else { return }
        Haptic.behaviourStarted()
        showRun = true
        Task {
            await runner.start(policy: policy, library: model, benches: benches, evals: evals)
        }
    }

    // MARK: - what the pickers are over

    /// Only networks whose PARAMETERS this app could digest, which is what
    /// `/tune` needs to fold a gain into the last layer.
    private var candidates: [PolicyLibrary.Entry] {
        model.library.entries.filter { $0.isRunnable && $0.identity.isNetworkIdentity }
    }

    /// Whether the library holds a file this app could not load, so the
    /// sentence explaining the filter is about an absence somebody can notice
    /// rather than about nothing.
    private var holdsAFileOnlyPolicy: Bool {
        model.library.entries.contains { !$0.identity.isNetworkIdentity }
    }

    /// Titles, with eight hex only where two of them collide, worked out once
    /// rather than per row: `pickerLabels` has to see the whole list to know
    /// which two titles clash.
    private var pickerLabels: [String: String] { PolicyLibrary.pickerLabels(candidates) }

    private var selectedEntry: PolicyLibrary.Entry? {
        candidates.first { $0.id == runner.policyID } ?? candidates.first
    }

    /// What is being evaluated, as the kit's own value.
    ///
    /// `residualIsIdentity` IS TRUE AND IT IS TRUE FOR A REASON. This screen
    /// never folds a gain: every `/tune` call it makes carries
    /// `DuckTuner.TuningVector.identity`, so the network the bench ran is the
    /// network the file was trained as, which is exactly what
    /// `EvalPolicy.identityResidualSaid` claims in the log.
    private var policy: EvalPolicy? {
        if runner.preset.evaluatesANetwork {
            guard let entry = selectedEntry else { return nil }
            var kind = EvalPolicy.Kind.libraryNetwork
            switch entry.origin {
            case .tuned, .searched: kind = .tunedCandidate
            case .bundled, .imported, .fetched: break
            }
            return EvalPolicy(kind: kind, title: entry.title, identity: entry.identity,
                              benchPolicyName: entry.fileName, residualIsIdentity: true)
        }
        guard let entrant = runner.entrant else { return nil }
        return EvalPolicy(kind: .challengeEntrant, title: entrant.title, identity: nil,
                          benchPolicyName: entrant.file, residualIsIdentity: true)
    }

    private var startRefusal: String? {
        runner.refusal(policy: policy, bundled: bundledNames)
    }

    /// The refusal, unless one of the controls above is already carrying it.
    ///
    /// EVERY REFUSAL IS UNDER THE CONTROL THAT CAUSED IT, WHICH IS ALSO WHY IT
    /// IS NOT UNDER TWO. A bench that did not answer says so under the bench;
    /// repeating the same sentence over the Start button would teach a person
    /// to stop reading both.
    private var startRefusalToDraw: String? {
        guard let refusal = startRefusal else { return nil }
        let alreadyDrawn = [runner.unreachable, runner.notYet,
                            runner.embodimentRefusal, runner.taskRefusal].compactMap { $0 }
        return alreadyDrawn.contains(refusal) ? nil : refusal
    }

    /// The networks the phone's own bench can score, which are the ones the app
    /// ships: its bench runs canonical parameter bytes exported from those
    /// files and has no ONNX reader at all.
    private var bundledNames: Set<String> {
        Set(model.library.entries.filter { $0.origin == .bundled }.map(\.fileName))
    }

    private var bodySaid: String {
        (benches.selected?.isThisPhone == true ? EvalEmbodiment.Body.thisPhoneBench
                                               : EvalEmbodiment.Body.networkBench).said
    }

    // MARK: - one paragraph, one shape

    private enum Size { case footnote, caption }

    private func paragraph(_ text: String, tone: Color,
                           size: Size = .footnote) -> some View {
        Text(text)
            .font(size == .footnote ? .footnote : .caption)
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
    }
}
