import SwiftUI
import StudioKit
import DuckEvidence

/// Name what you just drove, or throw it away.
///
/// THE TWO CLOCKS COME FIRST, ABOVE EVERYTHING ELSE. A person who spent
/// nineteen seconds recording three seconds of duck will otherwise conclude the
/// app dropped most of it. It did not: the bench only advances physics while it
/// is answering a request, so a take made over a slow link holds fewer seconds
/// of duck than seconds of you, and playing it back sends the same commands at
/// the same SIM times and will take whatever the link takes. That is
/// `DuckSequence.bothClocks`, and it is the first thing on the sheet.
///
/// `.medium` DETENT, DUCK BEHIND IT. You are not driving while you are typing;
/// the picture stays visible so the thing you just recorded is still on screen
/// while you name it.
///
/// A TAKE THAT CHANGED NETWORK SHOWS ITS REFUSAL INSTEAD OF THE BENCH BUTTON.
/// `POST /record` takes ONE policy and runs the whole schedule against it, so
/// filing a two-network take as a Motion would be filing a run that is not this
/// one. The sentence goes where the button was — a named refusal, not a
/// disabled control.
///
/// AND `acceptIntent`'S OWN FAILURE MESSAGE IS SHOWN AS IT COMES BACK. That
/// door names the field that failed to decode; composing a cheerful line here
/// would replace the only useful sentence in the failure.
struct SequenceKeepSheet: View {

    @ObservedObject var desk: PadDesk
    let bench: BenchEndpoint?
    let token: String?
    /// Start the drive loop if it is not already running. Playing a take from
    /// here is one press, exactly as recording one was.
    let engage: () -> Void
    /// The Motions library Behaviours actually shows, when a caller has one.
    /// See `BenchMotion.file` for what happens when nobody handed one over.
    var library: LibraryModel?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kept: DuckSequence?
    @State private var failure: String?
    @State private var filed: String?
    @State private var busy = false

    private var take: DuckSequenceRecording? { desk.pilot.pending }

    var body: some View {
        NavigationStack {
            List {
                if let take {
                    twoClocks(take)
                    nameField
                    provenance
                    steps(take)
                }
                // THE ACTIONS OUTLIVE THE TAKE. A successful Keep clears the
                // pending take, and the bind menu and "Keep on the bench as a
                // Motion" hang off the KEPT sequence — hiding them with the
                // take would close both doors the moment they became usable.
                if take != nil || kept != nil {
                    actions
                }
                if take == nil, kept == nil {
                    Section {
                        Text(DuckSequence.Refusal.empty.message)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    } header: {
                        SectionHeading(text: "Nothing to keep")
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
                        Label(filed, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.success)
                    } header: {
                        SectionHeading(text: "Kept on the bench")
                    }
                }
            }
            .navigationTitle(PadPilot.nameItChip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let take, name.isEmpty { name = desk.suggestedName(for: take) }
        }
    }

    // MARK: - the sections

    private func twoClocks(_ take: DuckSequenceRecording) -> some View {
        Section {
            Text(DuckSequence.bothClocks(simSeconds: take.simSeconds,
                                         wallSeconds: wallSeconds(take)))
                .font(.footnote)
            if let note = DuckSequence.droppedNote(take.skipped) {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        } header: {
            SectionHeading(text: "The two clocks")
        }
    }

    private var nameField: some View {
        Section {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.never)
                .frame(minHeight: DesignMetric.minimumTarget)
        } header: {
            SectionHeading(text: PadPilot.nameItChip)
        }
    }

    private var provenance: some View {
        Section {
            if let ending = desk.pilot.pendingEnding {
                Text(PadPilot.endedBy(ending))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(DuckSequence.whatThisIs)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            SectionHeading(text: "Where it came from")
        }
    }

    private func steps(_ take: DuckSequenceRecording) -> some View {
        Section {
            ForEach(Array(take.steps.enumerated()), id: \.offset) { pair in
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                    Text(String(format: "%.1f s", pair.element.atSim))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.measured)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(DuckDrive.says(pair.element.twist))
                            .font(.caption)
                        if let said = pair.element.policySaid {
                            Text(said)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        } header: {
            SectionHeading(text: "What went out")
        } footer: {
            Text(DuckSequence.replayIsARerun).foregroundStyle(Theme.textSecondary)
        }
    }

    private var actions: some View {
        Section {
            // `replayIsARerun` SITS ABOVE THE TWO RUN BUTTONS, not after them:
            // a caveat under a button is a caveat read after the press.
            Text(DuckSequence.replayIsARerun)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Button("Play it") {
                keepThen {
                    desk.pilot.play($0, thenLoading: nil)
                    engage()
                }
            }
            .buttonStyle(.primaryActionMoves)
            Button("Keep") { keepThen { _ in } }
                .buttonStyle(.primaryAction)
            if let kept {
                bindMenu(kept)
                if let why = kept.cannotBeKept {
                    // THE SENTENCE GOES WHERE THE BUTTON WAS.
                    Label(why, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                } else {
                    Button("Keep on the bench as a Motion") {
                        Task { await fileAsMotion(kept) }
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(busy)
                }
            }
            Button("Discard", role: .destructive) {
                desk.pilot.discardPending()
                dismiss()
            }
            Text(DuckSequence.sharingIsNotYet)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            SectionHeading(text: "What to do with it")
        }
    }

    private func bindMenu(_ sequence: DuckSequence) -> some View {
        Menu {
            ForEach(DuckPadMap.remappable, id: \.rawValue) { control in
                Button(control.face) {
                    desk.bind(.play(sequence: sequence.id, thenLoading: nil), to: control)
                }
            }
        } label: {
            Label("Put it on a button", systemImage: "gamecontroller")
                .frame(minHeight: DesignMetric.minimumTarget)
        }
    }

    // MARK: - doing it

    /// Nothing is auto-saved. Both run buttons keep first, so a take that was
    /// played and liked is already on disk rather than gone the moment the
    /// sheet closes.
    private func keepThen(_ next: (DuckSequence) -> Void) {
        failure = nil
        do {
            let sequence = try desk.keep(named: name.isEmpty ? "a take" : name)
            kept = sequence
            next(sequence)
        } catch let refusal as DuckSequence.Refusal {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
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

    /// Wall time so far, straight off the recording's own two `Date`s.
    private func wallSeconds(_ take: DuckSequenceRecording) -> Double {
        max(0, (take.lastSampledAt ?? take.startedAt).timeIntervalSince(take.startedAt))
    }
}

// MARK: - the one copy of the bench-recording path

/// `/record` → `readClip` → `IntentExport` → `LibraryModel.acceptIntent`.
///
/// LIFTED FROM `RemoteRunView.keepRecording` AND NOT REWRITTEN. That is the same
/// door a `.duckintent` arriving from Files or AirDrop goes through — it
/// decodes, writes, reloads and reports — so a recording made here gets exactly
/// the checks an imported one gets and lands in exactly the same place.
///
/// THE CLIP'S OWN CREDIT, NOT A FRESHER-LOOKING ONE. `DuckBench.readClip` builds
/// a credit from the `/record` answer — the world that recording actually ran in
/// — and composing one from a later `/health` answers a different question. So
/// `note` is left nil and `IntentExport` falls back to the clip's own, which is
/// what `RemoteRunView` argues for at length.
///
/// AND `acceptIntent`'S FAILURE MESSAGE IS RETURNED AS IT CAME BACK.
@MainActor
enum BenchMotion {

    enum Outcome {
        case kept(String)
        case refused(String)
    }

    static func file(_ sequence: DuckSequence, bench: BenchEndpoint?, token: String?,
                     library: LibraryModel?) async -> Outcome {
        guard let policy = sequence.benchPolicy else {
            return .refused(sequence.cannotBeKept ?? DuckSequence.benchNeverNamedANetwork)
        }
        guard let bench else { return .refused(DuckBench.Refusal.empty.message) }
        do {
            let address = try bench.resolved()
            let call = try DuckBench.record(address, policy: policy,
                                            seconds: sequence.simSeconds,
                                            schedule: sequence.benchSchedule())
            let (data, _) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token))
            let clip = try DuckBench.readClip(data, named: policy)
            let export = IntentExport(clip: clip, policyFingerprint: nil,
                                      named: sequence.name)
            // A SECOND `LibraryModel` ONLY WHEN NOBODY HANDED ONE OVER, and the
            // divergence is real rather than hidden: the file lands in the same
            // Application Support folder either way, and the shared instance
            // shows it after its next reload rather than immediately. The
            // alternative was an inert button on a screen whose whole value is
            // that it explains its refusals — see `DriveView.ownModels` for the
            // same trade made for the same reason.
            let motions = library ?? LibraryModel()
            guard motions.acceptIntent(try export.encoded(), named: sequence.name) else {
                // ITS MESSAGE, NOT A NEW ONE.
                return .refused(motions.lastImport ?? "That recording could not be kept.")
            }
            Haptic.finished()
            return .kept(sequence.name)
        } catch let refusal as DuckBench.Refusal {
            return .refused(refusal.message)
        } catch let error as DuckBench.ReadError {
            return .refused(error.message)
        } catch {
            return .refused(error.localizedDescription)
        }
    }
}
