import SwiftUI
import StudioKit
import DuckEvidence

/// Every sequence this phone holds, and the five things to do with one.
///
/// PLAY PUTS THE PILOT INTO `.playing` AND NOTHING ELSE HAPPENS HERE. There is
/// never a second loop: the drive loop consults `PadPilot` once per round trip
/// and sends whatever it hands back, so a replay is a STATE of `drive()` rather
/// than a rival `Task` — which is what stops two intent streams arriving at one
/// bench with Stop able to cancel only the newest. `play` is a closure the
/// Control tab passes in, and all it does there is engage the loop if it is not
/// already running.
///
/// STOP CUTS IT, AND STOP IS NEVER DISABLED. `halt()` calls
/// `pilot.cutOff(.stop)` and cancels the errand in flight; when a replay runs
/// off its own end the sticks take over with no announcement, because somebody
/// with a thumb on the pad wants their duck back rather than a sentence.
///
/// THE BENCH ROW IS ABSENT WITH ITS REASON IN ITS PLACE. A take that changed
/// network cannot become a Motion — `POST /record` takes one policy — and a
/// take the bench never named a network for has nothing to file against.
/// Neither is a disabled button; both are a sentence where the button was.
struct SequenceListView: View {

    @ObservedObject var desk: PadDesk
    let play: (UUID) -> Void
    /// Filing a take as a Motion needs a bench to re-run it on. Absent when
    /// this list was pushed from a surface that has none; pressing the row then
    /// prints `DuckBench.Refusal.empty`, which names what to do.
    var bench: BenchEndpoint?
    var token: String?
    var library: LibraryModel?

    @State private var renaming: DuckSequence?
    @State private var newName = ""
    @State private var failure: String?
    @State private var filed: String?
    @State private var busy = false

    var body: some View {
        List {
            if desk.sequences.isEmpty {
                Section {
                    Text(DuckSequence.whatThisIs)
                    Text(PadPilot.recordStartsDriving)
                } header: {
                    SectionHeading(text: "Nothing recorded yet")
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }
            ForEach(desk.sequences) { sequence in
                Section {
                    row(sequence)
                } header: {
                    SectionHeading(text: sequence.name)
                }
            }
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                } header: {
                    SectionHeading(text: "That did not work")
                }
            }
            if let filed {
                Section {
                    Label(DuckSequence.keptAsAMotion(filed), systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.success)
                } header: {
                    SectionHeading(text: "On the bench")
                }
            }
            Section {
                Text(DuckSequence.replayIsARerun)
                Text(DuckSequence.sharingIsNotYet)
            } header: {
                SectionHeading(text: "What a sequence is")
            } footer: {
                Text(DuckSequence.whatThisIs).foregroundStyle(Theme.textSecondary)
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        }
        .navigationTitle("Sequences")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename", isPresented: Binding(get: { renaming != nil },
                                              set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Keep the old name", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let renaming, !newName.isEmpty { desk.rename(renaming, to: newName) }
                renaming = nil
            }
        } message: {
            Text(DuckSequence.renamingKeepsTheBindings)
        }
    }

    private func row(_ sequence: DuckSequence) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Text(sequence.summary)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Text(DuckSequence.bothClocks(simSeconds: sequence.simSeconds,
                                         wallSeconds: sequence.wallSeconds))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(sequence.provenance.sentence)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: Theme.spacing(.snug)) {
                Button("Play") { play(sequence.id) }
                    .buttonStyle(.primaryActionMoves)
                bindMenu(sequence)
            }

            if let why = sequence.cannotBeKept {
                Label(why, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            } else {
                Button("Keep on the bench as a Motion") {
                    Task { await fileAsMotion(sequence) }
                }
                .buttonStyle(.primaryAction)
                .disabled(busy)
            }

            Menu("Rename or delete") {
                Button("Rename") {
                    newName = sequence.name
                    renaming = sequence
                }
                Button("Delete", role: .destructive) { desk.delete(sequence) }
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    private func bindMenu(_ sequence: DuckSequence) -> some View {
        Menu("Bind to…") {
            ForEach(DuckPadMap.remappable, id: \.rawValue) { control in
                Button(control.face) {
                    desk.bind(.play(sequence: sequence.id, thenLoading: nil), to: control)
                }
            }
        }
        .frame(minHeight: DesignMetric.minimumTarget)
    }

    @MainActor private func fileAsMotion(_ sequence: DuckSequence) async {
        busy = true
        defer { busy = false }
        failure = nil
        filed = nil
        switch await BenchMotion.file(sequence, bench: bench, token: token,
                                      library: library) {
        case .kept(let title): filed = title
        case .refused(let why): failure = why
        }
    }
}
