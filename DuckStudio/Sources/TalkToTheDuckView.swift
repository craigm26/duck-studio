import SwiftUI
import StudioKit
import DuckEvidence

/// Type a sentence; see the numbers before anything moves.
///
/// THE GRAMMAR RUNS FIRST, AND MOST OF THE TIME IT IS THE ANSWER.
/// `DuckTalk.read` is deterministic, offline, free, and it resolves against the
/// same `DuckDrive` limits the sticks do — driving is the one kind of request
/// in this app that is MEASURED rather than written, so spending a round trip,
/// a battery and somebody's privacy on it would be paying a language model to
/// do arithmetic. `DuckTalk.notAModel` says so on the card, because a box that
/// takes a sentence and produces a plan looks exactly like a model answered.
///
/// A MODEL IS THE FALLBACK, ONE PRESS IS ONE CALL, AND THERE IS NO RETRY. That
/// is why `DraftGate` — the budget, the deadline, the five-consecutive-failure
/// stop — is deliberately not involved: those are instruments for an autonomous
/// drafting loop, and this box cannot spend without a press. The property has
/// to stay true.
///
/// AND IT ASKS FOR `.motion` WITH ITS OWN INSTRUCTIONS RATHER THAN A FIFTH
/// `ChatDraft.Kind`. `DraftEngine.ask` consults `kind` only to build the
/// instructions a caller has just overridden, so no router round trip, no new
/// row in `DraftRouting.catalogue`, and the reply is read by
/// `SequenceProposal.read(fromJSON:)`, which is the only thing that decides
/// what came back.
///
/// NOTHING HERE SAYS THE DUCK UNDERSTOOD ANYTHING. Every guess the reader had
/// to make is printed as its own line, and a test pins that the only sentence
/// in the file containing the word "understand" is the one denying it.
///
/// THE DICTATION IS THE KEYBOARD'S OWN MICROPHONE KEY. It needs no entitlement,
/// no usage string and no code — `SFSpeechRecognizer` would need two Info.plist
/// strings in a file this track does not own AND a re-read of the "Data Not
/// Collected" commitment, because Apple's recognition can be server-backed.
struct TalkToTheDuckView: View {

    @ObservedObject var desk: PadDesk
    let venue: DriveVenue
    /// Start the drive loop if it is not already running.
    let engage: () -> Void
    @ObservedObject var models: EndpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var reading: DuckTalk.Reading?
    @State private var proposal: SequenceProposal?
    @State private var made: DuckSequence?
    @State private var refusal: String?
    @State private var timing: String?
    @State private var thinking = false

    /// Whether anything has been ADDED. Apple's on-device model is reachable
    /// only once it is a row like any other, which is the same door the Draft
    /// tab uses, so "none configured" is a fact about this app's settings and
    /// not a guess about the platform.
    private var hasAModel: Bool { !models.endpoints.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(DuckTalk.sayItPlaceholder, text: $typed, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .lineLimit(1...4)
                        .frame(minHeight: DesignMetric.minimumTarget)
                    Button("Read it") { Task { await send() } }
                        .buttonStyle(.primaryAction)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                    Text(DuckTalk.dictationNote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } header: {
                    SectionHeading(text: DuckTalk.sayItTitle)
                } footer: {
                    Text(PadPilot.sayItCaption).foregroundStyle(Theme.textSecondary)
                }

                if let reading { readingSection(reading) }
                if let proposal, made == nil { proposalSection(proposal) }
                if let made { madeSection(made) }
                if let refusal {
                    Section {
                        Label(refusal, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    } header: {
                        SectionHeading(text: "Not driven")
                    }
                }
            }
            .navigationTitle(DuckTalk.sayItTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - what came back

    private func readingSection(_ reading: DuckTalk.Reading) -> some View {
        Section {
            // THE RESOLVED NUMBERS, NOT THE WORDS. What a person needs to see
            // before something moves is what will be SENT.
            ForEach(Array(reading.moves.enumerated()), id: \.offset) { pair in
                Text(SequenceProposal.spelled(pair.element))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.measured)
            }
            Text(reading.sentence)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(reading.assumed, id: \.self) { line in
                Label(line, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.asked)
            }
            if let missed = DuckTalk.notRead(reading.unread) {
                Label(missed, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.asked)
            }
            Text(DuckTalk.simSecondsNote)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(DuckTalk.notAModel)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            SectionHeading(text: "Read on this phone")
        }
    }

    private func proposalSection(_ proposal: SequenceProposal) -> some View {
        Section {
            ForEach(Array(proposal.moves.enumerated()), id: \.offset) { pair in
                Text(SequenceProposal.spelled(pair.element))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.measured)
            }
            if let timing {
                Text(timing).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        } header: {
            SectionHeading(text: "A model wrote this")
        } footer: {
            Text(SequenceProposal.grounding()).foregroundStyle(Theme.textSecondary)
        }
    }

    private func madeSection(_ sequence: DuckSequence) -> some View {
        Section {
            Text(sequence.summary)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Text(DuckSequence.replayIsARerun)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Button("Play it") {
                desk.pilot.play(sequence, thenLoading: nil)
                engage()
                dismiss()
            }
            .buttonStyle(.primaryActionMoves)
            Menu("Put it on a button") {
                ForEach(DuckPadMap.remappable, id: \.rawValue) { control in
                    Button(control.face) {
                        desk.bind(.play(sequence: sequence.id, thenLoading: nil), to: control)
                    }
                }
            }
            .frame(minHeight: DesignMetric.minimumTarget)
            if let why = sequence.cannotBeKept {
                Label(why, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        } header: {
            SectionHeading(text: "Kept as \(sequence.name)")
        }
    }

    // MARK: - the one press

    @MainActor private func send() async {
        let asked = typed.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty else { return }
        reading = nil; proposal = nil; made = nil; refusal = nil; timing = nil

        // ONE: the grammar, always, first.
        let read = DuckTalk.read(asked)
        if read.confidence != .notUnderstood {
            reading = read
            keep(SequenceProposal(name: asked, moves: read.moves),
                 provenance: .said(asked))
            return
        }

        // THREE, checked before TWO because it costs nothing: no model, no call.
        guard hasAModel else {
            reading = read
            refusal = DuckTalk.withoutAModel
            return
        }

        // TWO: exactly one call, no retry.
        thinking = true
        defer { thinking = false }
        let endpoint = models.armed(models.selected)
        do {
            let answer = try await DraftEngine.ask(
                endpoint, kind: .motion, prompt: asked, knownIntents: [],
                instructions: DuckTalk.instructions)
            timing = String(format: "%@ took %.0f s", endpoint.model, answer.seconds)
            let written = try SequenceProposal.read(fromJSON: answer.json)
            proposal = written
            keep(written, provenance: .drafted(model: endpoint.model, asked: asked))
        } catch let error as SequenceProposal.DraftError {
            refusal = error.message
        } catch {
            refusal = error.localizedDescription
        }
    }

    /// Resolve and store, or print the refusal by name.
    private func keep(_ written: SequenceProposal,
                      provenance: DuckSequence.Provenance) {
        do {
            let sequence = try written.resolve(named: written.name, provenance: provenance,
                                               venue: venue, at: Date())
            desk.add(sequence)
            made = sequence
        } catch let unresolvable as SequenceProposal.Unresolvable {
            refusal = unresolvable.message
        } catch let sequenceRefusal as DuckSequence.Refusal {
            refusal = sequenceRefusal.message
        } catch {
            refusal = error.localizedDescription
        }
    }
}
