import SwiftUI
import DuckKit
import StudioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Describe a rule in a sentence; get a rule back, or a reason you did not.
///
/// THE MODEL IS A PROPOSER AND NOTHING MORE. It runs entirely on device
/// (Apple Intelligence, iOS 26+), it is given the exact vocabulary it may use,
/// and everything it emits goes through `AutomationProposal.resolve` and then
/// `AutomationValidator` — the same two steps a rule typed by hand takes.
/// Guided generation shapes what comes out; it is not a promise about it, and a
/// drafted rule naming a motion nobody recorded is refused exactly as a typed
/// one would be.
///
/// AND THE RULES DO NOT RUN YET. `DuckToF` and `DuckState` are inbound decoders
/// with no output channel, so "then play X" has no execution path until there
/// is a robot and `DuckRPC` to reach it. That is said on the screen rather than
/// left for someone to find out, because a rule that looks live and is not is
/// the worst thing this could ship.
struct AutomationChatView: View {

    @State private var typed = ""
    @State private var entries: [Entry] = []
    @State private var thinking = false
    @State private var clips: [String: DuckIntentClip] = [:]

    struct Entry: Identifiable {
        let id = UUID()
        let asked: String
        let rule: Automation?
        let refusal: String?
    }

    private var knownIntents: Set<String> { Set(clips.keys) }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text(availability.explanation)
                        .font(.footnote)
                        .foregroundStyle(availability.isUsable ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                }

                Section {
                    Text("A rule you draft here is one you can read, check and share. It does not fire: reaching a robot needs hardware that does not exist yet, so nothing here is live.")
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
                        }
                        if let refusal = entry.refusal {
                            Label(refusal, systemImage: "xmark.circle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("When something is close, sit down", text: $typed, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .disabled(!availability.isUsable || thinking)
                Button {
                    Task { await draft() }
                } label: {
                    Image(systemName: thinking ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty
                          || !availability.isUsable || thinking)
            }
            .padding()
        }
        .navigationTitle("Draft a rule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { clips = (try? DuckIntentClip.bundled()) ?? [:] }
    }

    // MARK: - the model

    private struct Availability {
        let isUsable: Bool
        let explanation: String
    }

    /// Whether there is a model to ask, and if not, why — a disabled field with
    /// no reason is the worst version of this screen.
    private var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return Availability(isUsable: true, explanation:
                    "Drafted by Apple's on-device model. Nothing you type leaves this phone, and "
                    + "every rule it writes is checked against the motions you actually have.")
            case .unavailable(.deviceNotEligible):
                return Availability(isUsable: false, explanation:
                    "This device does not have Apple Intelligence, so there is no on-device model "
                    + "to draft with. You can still write rules by hand.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return Availability(isUsable: false, explanation:
                    "Turn on Apple Intelligence in Settings to draft rules from a sentence.")
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
    /// The shape the model must fill. Flat and small, because that is what a
    /// small on-device model can satisfy reliably — and because every field
    /// here is re-checked afterwards regardless.
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
    #endif

    private func draft() async {
        let asked = typed.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty else { return }
        typed = ""
        thinking = true
        defer { thinking = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let instructions = """
                You turn one sentence into one rule for a small robot duck.

                \(AutomationProposal.grounding(knownIntents: knownIntents))
                """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let drafted = try await session.respond(to: asked, generating: DraftedRule.self).content
                let proposal = AutomationProposal(name: drafted.name,
                                                  predicate: drafted.predicate,
                                                  value: drafted.value,
                                                  intent: drafted.intent)
                // The choke-point. Whatever came back, it is judged here.
                let rule = try proposal.resolve(knownIntents: knownIntents)
                entries.append(Entry(asked: asked, rule: rule, refusal: nil))
            } catch let error as AutomationProposal.Unresolvable {
                entries.append(Entry(asked: asked, rule: nil, refusal: error.message))
            } catch let error as AutomationValidator.Refusal {
                entries.append(Entry(asked: asked, rule: nil, refusal: error.message))
            } catch {
                entries.append(Entry(asked: asked, rule: nil,
                                     refusal: "The model could not answer: \(error.localizedDescription)"))
            }
            return
        }
        #endif
        entries.append(Entry(asked: asked, rule: nil,
                             refusal: "There is no on-device model available on this device."))
    }
}
