import SwiftUI
import DuckKit
import StudioKit

/// The door the brief screen was missing: a run that happens HERE.
///
/// This screen exists because `TrainingRequestView` could only ever hand its
/// work to somebody else. It named a task, wrote a config a machine with mjlab
/// could run, and offered three ways to send that file somewhere — which is the
/// right answer for learning a network from nothing and the wrong one for the
/// thing a phone and a bench can actually do between them.
///
/// WHAT IT CLAIMS IS WHAT IT DOES, and both halves are on the screen before
/// anything starts: it searches the weights of a network you already have, and
/// it does not learn one from nothing.
struct WeightSearchView: View {

    @ObservedObject var library: LibraryModel
    @ObservedObject var benches: BenchStore
    @StateObject private var run = WeightSearchRun()

    /// Which network the search starts FROM. Only policies that load: a search
    /// starting from a file this app refused would be a search over nothing.
    @State private var baseID: String?

    private var candidates: [PolicyLibrary.Entry] {
        library.library.entries.filter(\.isRunnable)
    }

    private var base: PolicyLibrary.Entry? {
        baseID.flatMap { wanted in candidates.first { $0.id == wanted } }
    }

    @State private var step = 0.05
    @State private var pairs = 10.0
    @State private var generations = 8.0
    @State private var outgoing: ExportedFile?
    @State private var failure: String?

    private var settings: WeightSearch.Settings? {
        try? WeightSearch.Settings(step: step, rate: 0.05,
                                   pairs: Int(pairs), generations: Int(generations))
    }

    var body: some View {
        List {
            Section {
                Text(WeightSearch.whatThisIs)
                    .font(.footnote).foregroundStyle(Theme.textPrimary)
                Text(WeightSearch.howItRuns)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } header: {
                SectionHeading(text: WeightSearch.whatThisRunIsHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                let labels = PolicyLibrary.pickerLabels(candidates)
                Picker(WeightSearch.startFromSaid, selection: $baseID) {
                    Text(WeightSearch.noBaseSaid).tag(String?.none)
                    ForEach(candidates) { entry in
                        Text(labels[entry.id] ?? entry.title).tag(String?.some(entry.id))
                    }
                }
                .disabled(run.isRunning)
            } header: {
                SectionHeading(text: WeightSearch.theNetworkHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            settingsSection
            if run.isRunning || !run.generations.isEmpty { progressSection }
            if let said = run.said { verdictSection(said) }
            if let failure = run.failure {
                Section {
                    Text(failure).font(.caption).foregroundStyle(Theme.refused)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Search its weights")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { transport }
        .task { if baseID == nil { baseID = candidates.first?.id } }
        .sheet(item: $outgoing) { ShareSheet(items: [$0.url]) }
        .alert("That did not send", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private var settingsSection: some View {
        Section {
            LabeledContent(WeightSearch.stepSaid) {
                Text(WeightSearch.percentSaid(step))
                    .monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            // THE SLIDER CANNOT LEAVE THE MEASURED BAND. `Settings` refuses a
            // step outside it by name, and a control that can ask for a refusal
            // is a control that will.
            Slider(value: $step,
                   in: WeightSearch.stepBand.lowerBound...WeightSearch.stepBand.upperBound)
                .disabled(run.isRunning)
            Text(WeightSearch.theStepSaid)
                .font(.caption2).foregroundStyle(Theme.textSecondary)

            Stepper("\(WeightSearch.pairsSaid): \(Int(pairs))", value: $pairs, in: 3...24)
                .disabled(run.isRunning)
            Stepper("\(WeightSearch.generationsSetSaid): \(Int(generations))", value: $generations, in: 1...40)
                .disabled(run.isRunning)
            if let settings {
                Text(WeightSearch.costSaid(settings))
                    .font(.caption).foregroundStyle(Theme.asked)
            }
        } header: {
            SectionHeading(text: WeightSearch.howFarToLookHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var progressSection: some View {
        Section {
            ForEach(run.generations) { line in
                Text(line.said)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(line.id == 0 ? Theme.textSecondary : Theme.textPrimary)
            }
            if run.isRunning, let settings {
                ProgressView(value: Double(run.scored),
                             total: Double(settings.callsPerGeneration * settings.generations))
                Text(WeightSearch.benchRunsSaid(run.scored))
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        } header: {
            SectionHeading(text: WeightSearch.generationsHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func verdictSection(_ said: String) -> some View {
        Section {
            Text(said).font(.footnote)
                .foregroundStyle(run.verdict?.survived == true ? Theme.textPrimary : Theme.asked)
            if let result = run.result, result.verdict.survived {
                Button {
                    export(result)
                } label: {
                    Label(WeightSearch.keepThisNetworkSaid, systemImage: "square.and.arrow.down")
                }
            }
        } header: {
            SectionHeading(text: WeightSearch.whatCameOutHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var transport: some View {
        HStack {
            // STOP IS NEVER DISABLED, and a stopped run keeps what it has —
            // the same rule the Control tab's Stop lives under.
            if run.isRunning {
                Button(WeightSearch.stopSaid) { run.stop() }
                    .buttonStyle(.primaryActionMoves)
            } else {
                Button {
                    guard let settings else { return }
                    Task { await start(settings) }
                } label: {
                    Label(WeightSearch.runItHereSaid, systemImage: "play.circle")
                }
                .buttonStyle(.primaryActionMoves)
                .disabled(settings == nil || base == nil || benches.selected == nil)
            }
        }
        .padding()
        .background(Theme.surfacePrimary)
    }

    private func start(_ settings: WeightSearch.Settings) async {
        guard let base, let bytes = PolicyStore.data(for: base) else {
            run.failure = WeightSearch.baseIsGoneSaid
            return
        }
        Haptic.behaviourStarted()
        await run.search(base: bytes, settings: settings, benches: benches)
    }

    private func export(_ result: WeightSearchRun.Result) {
        do {
            outgoing = ExportedFile(url: try ExportFile.write(result.onnx, named: result.filename))
        } catch let refusal as ExportFile.Failure {
            run.failure = refusal.message
        } catch {
            run.failure = error.localizedDescription
        }
    }
}
