import SwiftUI
import Foundation
import DuckKit
import StudioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Say what you want; watch the robot try it. The drafting hub.
///
/// ONE SCREEN, TWO KINDS OF DRAFT. A MOTION — "take a slow bow, then look
/// left" — becomes real keyframes, opens IMMEDIATELY in the 3D editor, and is
/// yours to scrub, tweak and keep. A RULE — "when something is close, sit
/// down" — becomes a checkable when/then. Both go through the same on-device
/// model, and everything it emits is resolved and judged by the same tested
/// code a hand-made draft goes through, because a generated draft is not a
/// special kind of draft.
///
/// THE PREVIEW IS THE LESSON. The point of drafting from a sentence is not
/// saving taps — it is seeing what your words became: the editor opens on the
/// drafted keyframes with every slider where the sentence put it, which is how
/// somebody learns the robot's joints without reading a manual.
///
/// The rules still do not fire — `DuckToF` and `DuckState` are inbound
/// decoders with no output channel — and the screen says so.
struct AutomationChatView: View {

    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore

    @State private var typed = ""
    @State private var mode: Mode = .motion
    @State private var entries: [Entry] = []
    @State private var thinking = false
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var previewing: DraftID?
    /// How many tries the model gets, how long it gets, and when to stop
    /// asking it. Every one of those decisions lives in StudioKit where a test
    /// drives it; this screen only calls it and shows what it says.
    ///
    /// THE CLOCK IS `systemUptime`, NOT A DATE. It counts forward from boot
    /// and nothing a person does to the phone's calendar moves it, so a
    /// deadline cannot be lengthened or expired by crossing a time zone.
    @State private var gate = DraftGate(now: { ProcessInfo.processInfo.systemUptime })
    /// THE WAY OUT OF THE KEYBOARD. The first version had none: the field
    /// focused, the keyboard rose, and nothing on screen dismissed it.
    @FocusState private var typing: Bool

    /// Drafting motions has stopped for this sitting. Rules are unaffected —
    /// they go through a different resolver and have their own outcome.
    private var motionDraftingStopped: Bool { mode == .motion && gate.isStopped }

    enum Mode: String, CaseIterable, Identifiable {
        case motion = "Motion", rule = "Rule"
        var id: String { rawValue }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let asked: String
        var rule: Automation? = nil
        var motionDraftID: UUID? = nil
        var motionSummary: String? = nil
        var refusal: String? = nil
    }

    private var knownIntents: Set<String> { Set(clips.keys) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Draft", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            List {
                Section {
                    Text(availability.explanation)
                        .font(.footnote)
                        .foregroundStyle(availability.isUsable
                            ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                }

                Section {
                    Text(mode == .motion
                         ? "Describe a motion and the robot performs your words in 3D, immediately — then open the keyframes and see the sliders the sentence moved. Drafts land in your Intents tab."
                         : "A rule you draft here is one you can read, check and share. It does not fire: reaching a robot needs hardware that does not exist yet, so nothing here is live.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                ForEach(entries) { entry in
                    Section {
                        Text(entry.asked).font(.subheadline)

                        if let rule = entry.rule {
                            Label(rule.sentence, systemImage: "checkmark.seal")
                                .font(.footnote)
                            Text("\(rule.name) · \(rule.origin.described)")
                                .font(.caption2).foregroundStyle(.secondary)
                            // THE RULE'S OTHER HALF: what it would actually
                            // do. A when/then whose "then" you can watch is a
                            // rule; one you cannot is a sentence.
                            if case .play(let intentName) = rule.then,
                               let clip = clips[intentName] {
                                NavigationLink {
                                    IntentPlayerView(clip: clip, store: scenes,
                                                     drafts: drafts)
                                } label: {
                                    Label("Watch what it would play",
                                          systemImage: "play.circle")
                                        .font(.footnote)
                                }
                            }
                        }

                        if let summary = entry.motionSummary {
                            Label(summary, systemImage: "figure.dance")
                                .font(.footnote)
                            if let id = entry.motionDraftID {
                                Button {
                                    previewing = DraftID(id: id)
                                } label: {
                                    Label("Preview again", systemImage: "play.circle")
                                        .font(.footnote)
                                }
                            }
                        }

                        if let refusal = entry.refusal {
                            Label(refusal, systemImage: "xmark.circle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 8) {
                TextField(mode == .motion
                          ? "Take a slow bow, then look left"
                          : "When something is close, sit down",
                          text: $typed, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .focused($typing)
                    .disabled(!availability.isUsable || thinking || motionDraftingStopped)
                Button {
                    Task { await draft() }
                } label: {
                    Image(systemName: thinking ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                // A STOP THAT DOES NOT STOP ANYTHING IS A MESSAGE. When the
                // gate has given up, the field goes with it — the reason is
                // already the last thing in the list.
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty
                          || !availability.isUsable || thinking || motionDraftingStopped)
            }
            .padding()
        }
        .navigationTitle("Draft with words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The keyboard's own Done key. Drag-down on the list works too;
            // both exist because a trapped keyboard was this screen's first
            // shipped bug.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { typing = false }
            }
        }
        .sheet(item: $previewing) { wrapper in
            NavigationStack {
                if let current = drafts.drafts.first(where: { $0.id == wrapper.id }) {
                    IntentAuthorView(
                        draft: current, scenes: scenes, isNew: false,
                        onSave: { drafts.save($0) },
                        onDiscard: { doomed in
                            previewing = nil
                            drafts.delete(doomed)
                        })
                        .onDisappear { drafts.flush() }
                }
            }
        }
        .onAppear { clips = (try? DuckIntentClip.bundled()) ?? [:] }
    }

    // MARK: - the model

    private struct Availability {
        let isUsable: Bool
        let explanation: String
    }

    private var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return Availability(isUsable: true, explanation:
                    "Drafted by Apple's on-device model. Nothing you type leaves this phone, and "
                    + "everything it writes is resolved and checked by the same code a hand-made "
                    + "draft goes through.")
            case .unavailable(.deviceNotEligible):
                return Availability(isUsable: false, explanation:
                    "This device does not have Apple Intelligence, so there is no on-device model "
                    + "to draft with. Motions can still be written by hand in the Intents tab.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return Availability(isUsable: false, explanation:
                    "Turn on Apple Intelligence in Settings to draft from a sentence.")
            case .unavailable(.modelNotReady):
                return Availability(isUsable: false, explanation:
                    "The on-device model is still downloading. Try again shortly.")
            default:
                return Availability(isUsable: false, explanation:
                    "The on-device model is not available right now.")
            }
        }
        #endif
        return Availability(isUsable: false, explanation:
            "Drafting from a sentence needs Apple Intelligence, which this version of iOS does not have.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct DraftedRule {
        @Guide(description: "A short name for the rule, three or four words.")
        var name: String
        @Guide(description: "Exactly one of the listed predicate words. Do not invent one.")
        var predicate: String
        @Guide(description: "Metres for a distance predicate, a fraction for battery, 0 otherwise.")
        var value: Double
        @Guide(description: "Exactly one of the listed motion names. Do not invent one.")
        var intent: String
    }

    @available(iOS 26.0, *)
    @Generable
    struct DraftedMove {
        // ENFORCED AT DECODE, not just described: the guided decoder can only
        // emit a word from this list, so the model cannot invent a joint the
        // resolver has to refuse. The list is the resolver's own.
        @Guide(description: "One of the listed joint or pair words.",
               .anyOf(MotionProposal.offeredWords))
        var joint: String
        @Guide(description: "Degrees away from the standing pose, inside the listed travel.")
        var degrees: Double
    }

    @available(iOS 26.0, *)
    @Generable
    struct DraftedKey {
        @Guide(description: "Seconds from the start, increasing.")
        var atSeconds: Double
        @Guide(description: "The joints that move at this moment. Empty means back toward standing.")
        var moves: [DraftedMove]
        @Guide(description: "Beak: 0 closed to 1 open.")
        var mouthOpen: Double
    }

    @available(iOS 26.0, *)
    @Generable
    struct DraftedMotion {
        @Guide(description: "A short, friendly name for the motion.")
        var name: String
        @Guide(description: "Two to six keyframes over one to four seconds, ending back at standing.")
        var keys: [DraftedKey]
    }
    #endif

    private func draft() async {
        let asked = typed.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty else { return }
        typed = ""
        typing = false
        thinking = true
        defer { thinking = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch mode {
            case .rule:     await draftRule(asked)
            case .motion:   await draftMotion(asked)
            }
            return
        }
        #endif
        entries.append(Entry(asked: asked,
                             refusal: "There is no on-device model available on this device."))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func draftRule(_ asked: String) async {
        let instructions = """
            You turn one sentence into one rule for a small robot duck.

            \(AutomationProposal.grounding(knownIntents: knownIntents))
            """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let drafted = try await session.respond(to: asked,
                                                    generating: DraftedRule.self).content
            let proposal = AutomationProposal(name: drafted.name,
                                              predicate: drafted.predicate,
                                              value: drafted.value,
                                              intent: drafted.intent)
            let rule = try proposal.resolve(knownIntents: knownIntents)
            entries.append(Entry(asked: asked, rule: rule))
        } catch let error as AutomationProposal.Unresolvable {
            entries.append(Entry(asked: asked, refusal: error.message))
        } catch let error as AutomationValidator.Refusal {
            entries.append(Entry(asked: asked, refusal: error.message))
        } catch {
            entries.append(Entry(asked: asked,
                                 refusal: "The model could not answer: \(error.localizedDescription)"))
        }
    }

    @available(iOS 26.0, *)
    private func draftMotion(_ asked: String) async {
        let instructions = """
            You turn one sentence into one short motion for a small robot duck.

            \(MotionProposal.grounding())
            """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let drafted = try await session.respond(to: asked,
                                                    generating: DraftedMotion.self).content
            let proposal = MotionProposal(
                name: drafted.name,
                keys: drafted.keys.map { key in
                    MotionProposal.Key(
                        atSeconds: key.atSeconds,
                        moves: key.moves.map {
                            MotionProposal.Move(joint: $0.joint, degrees: $0.degrees)
                        },
                        mouthOpen: key.mouthOpen)
                })
            // THE CHOKE-POINT, AND NOW ALSO THE BUDGET. Names, units and
            // travel are judged in tested code exactly as a typed draft would
            // be — and the gate around that counts the try, holds the
            // deadline, and stops asking a model that keeps failing the same
            // way. A refusal and a stop look the same on screen; the
            // difference is that after a stop the field is closed.
            let draft: IntentDraft
            switch gate.draft(proposal) {
            case .drafted(let resolved):
                draft = resolved
            case .feedback(let reason), .stopped(let reason):
                entries.append(Entry(asked: asked, refusal: reason))
                return
            }
            // THE SAME JUDGE A HAND-MADE DRAFT FACES. A broken draft is a
            // refusal, not a preview; an impossible or cautioned one previews
            // with its problems named, so the chat matches the editor.
            if let broken = draft.problems.first(where: { $0.severity == .broken }) {
                entries.append(Entry(asked: asked, refusal: broken.text))
                return
            }
            drafts.save(draft)
            let notes = draft.problems.map(\.text).joined(separator: " ")
            entries.append(Entry(asked: asked,
                                 motionDraftID: draft.id,
                                 motionSummary: "\(draft.name) — \(draft.keys.count) keyframes, "
                                     + String(format: "%.1f s", draft.duration)
                                     + (notes.isEmpty ? "" : " · " + notes)))
            // THE PREVIEW, IMMEDIATELY. The editor opens on what the words
            // became — playing, scrubable, every slider where the sentence
            // put it. Keep it, change it, or throw it away.
            previewing = DraftID(id: draft.id)
        } catch {
            // `MotionProposal.Unresolvable` no longer arrives here: resolution
            // happens inside the gate, which turns it into feedback or a stop
            // so that it is counted. What is left is the model itself failing.
            entries.append(Entry(asked: asked,
                                 refusal: "The model could not answer: \(error.localizedDescription)"))
        }
    }
    #endif
}
