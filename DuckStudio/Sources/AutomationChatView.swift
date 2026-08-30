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
    /// Which model writes the draft. Apple's, a box on your network, or
    /// another app on this phone — the draft lands in the same checker either
    /// way, so this is a choice about privacy and speed, not about trust.
    @ObservedObject var models: EndpointStore

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
        case motion = "Motion", rule = "Rule", fetch = "Fetch", train = "Train"
        var id: String { rawValue }

        var draftKind: ChatDraft.Kind {
            switch self {
            case .motion: return .motion
            case .rule: return .rule
            case .fetch: return .retrieval
            case .train: return .training
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let asked: String
        var rule: Automation? = nil
        var motionDraftID: UUID? = nil
        var motionSummary: String? = nil
        var refusal: String? = nil
        /// A fetch, checked against measurements rather than asked about.
        var plan: Retrieval.Plan? = nil
        var planObject: String? = nil
        /// A request to train a new policy — written here, run elsewhere.
        var request: TrainingRequest? = nil
        /// What the model cost in wall-clock, when it was not Apple's. A local
        /// model on a small board is slow, and saying so beats a spinner.
        var timing: String? = nil
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
                    NavigationLink {
                        ModelSettingsView(store: models)
                    } label: {
                        Label(models.selected.name, systemImage: "brain")
                            .font(.footnote)
                    }
                }

                Section {
                    Text(blurb).font(.caption).foregroundStyle(.secondary)
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

                        if let plan = entry.plan {
                            Label(plan.isPossible
                                  ? "It can do this — \(String(format: "%.0f s", plan.seconds))"
                                  : "It cannot do this",
                                  systemImage: plan.isPossible ? "checkmark.seal" : "xmark.octagon")
                                .font(.footnote)
                                .foregroundStyle(plan.isPossible ? Color.green : Color.orange)
                            Text(String(format: "%@%.0f g, %.0f mm thick, %.1f m away",
                                        entry.planObject.map { "\($0): " } ?? "",
                                        plan.stick.grams, plan.stick.thicknessMillimetres,
                                        plan.stick.metresAway))
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(plan.refusals, id: \.message) { refusal in
                                Text(refusal.message).font(.caption2)
                                    .foregroundStyle(refusal.isFatal ? Color.orange : Color.secondary)
                            }
                            NavigationLink {
                                RetrieveView()
                            } label: {
                                Label("Open the plan", systemImage: "list.bullet.rectangle")
                                    .font(.footnote)
                            }
                        }

                        if let request = entry.request {
                            Label(request.isTrainable
                                  ? "Worth training — \(request.rewards.count) rewards"
                                  : "Not worth training",
                                  systemImage: request.isTrainable
                                  ? "checkmark.seal" : "xmark.octagon")
                                .font(.footnote)
                                .foregroundStyle(request.isTrainable ? Color.green : Color.orange)
                            Text("Forks \(request.base.rawValue)").font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(request.rewards) { reward in
                                Text("\(reward.function) × \(String(format: "%g", reward.weight)) — \(reward.reason)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            ForEach(request.refusals, id: \.message) { refusal in
                                Text(refusal.message).font(.caption2)
                                    .foregroundStyle(refusal.isFatal ? Color.orange : Color.secondary)
                            }
                            NavigationLink {
                                TrainingRequestView(request: request)
                            } label: {
                                Label("Open the request", systemImage: "doc.text")
                                    .font(.footnote)
                            }
                        }

                        if let timing = entry.timing {
                            Text(timing).font(.caption2).foregroundStyle(.secondary)
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
                        draft: current, scenes: scenes, models: models, isNew: false,
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

    private var blurb: String {
        switch mode {
        case .motion:
            return "Describe a motion and the robot performs your words in 3D, immediately — then open the keyframes and see the sliders the sentence moved. Drafts land in your Intents tab."
        case .rule:
            return "A rule you draft here is one you can read, check and share. It does not fire: reaching a robot needs hardware that does not exist yet, so nothing here is live."
        case .train:
            return trainBlurb
        case .fetch:
            let mine = sceneProps
            let names = mine.isEmpty ? "" :
                " Things in your scenes: " + mine.map(\.name).joined(separator: ", ") + "."
            return "Say what you want fetched or dragged. The model only sizes the object; "
                 + "whether the duck can manage it is decided here, against measurements — the "
                 + "jaw closes 20 mm above the floor, the lift was trained against 10–40 g, and "
                 + "the pull runs out around 5 N.\(names)"
        }
    }

    private var trainBlurb: String {
        "Describe a NEW SKILL and this writes the request to train one: which "
        + "existing task to fork, what to reward, how long an episode runs. "
        + "Nothing here trains anything — a phone has no Python, no mjlab and no "
        + "GPU. What it can do is check the request against things already known, "
        + "so \"lift two kilos\" is refused in a second rather than after a day "
        + "of training that was never going to converge."
    }

    private var availability: Availability {
        // A configured server outranks Apple's model: somebody who has pointed
        // this at their own Pi has said which model they want.
        if models.selected.kind == .openAICompatible {
            let endpoint = models.selected
            return Availability(isUsable: !endpoint.model.isEmpty, explanation:
                "Drafted by \(endpoint.model) on \(endpoint.name). \(endpoint.privacyNote) "
                + "Everything it writes is resolved and checked by the same code a hand-made "
                + "draft goes through, so a model that invents a joint is refused, not believed.")
        }
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

        // A configured server handles every mode through one path. Apple's
        // model keeps its own, because @Generable guarantees the shape and
        // guessing at JSON when the platform will hand over a typed value
        // would be throwing away the better answer.
        if models.selected.kind == .openAICompatible {
            await draftOnServer(asked)
            return
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch mode {
            case .rule:     await draftRule(asked)
            case .motion:   await draftMotion(asked)
            case .fetch:    draftFetchLocally(asked)
            case .train:
                entries.append(Entry(asked: asked, refusal:
                    "Writing a training request needs a model that can pick reward "
                    + "functions from a list. Point the app at one in Models — a small "
                    + "local one is plenty, because the choice is checked here afterwards."))
            }
            return
        }
        #endif
        // No Apple model and no server: the deterministic reader still works
        // for a fetch, because sizing a stick does not need a model at all.
        if mode == .fetch { draftFetchLocally(asked); return }
        entries.append(Entry(asked: asked, refusal:
            "There is no on-device model on this device. Add one in Models — anything "
            + "speaking the OpenAI chat API will do, including one running on this phone."))
    }

    /// Everything a configured server does, in one path.
    ///
    /// THE MODEL WRITES; THIS CHECKS. Whatever comes back is pulled out of
    /// whatever costume it arrived in, read into a proposal, and resolved
    /// against the real joints and travels. A model that invents a joint gets
    /// the refusal a person would — which is what makes it safe to let anybody
    /// point this at any model they like.
    private func draftOnServer(_ asked: String) async {
        let endpoint = models.armed(models.selected)
        do {
            let answer = try await DraftEngine.ask(endpoint, kind: mode.draftKind,
                                                   prompt: asked, knownIntents: knownIntents)
            var timing = String(format: "%@ took %.0f s", endpoint.model, answer.seconds)
            if let rate = answer.tokensPerSecond {
                timing += String(format: " (%.1f tokens/s)", rate)
            }
            switch mode {
            case .rule:
                let proposal = try ChatDraft.rule(fromJSON: answer.json)
                let rule = try proposal.resolve(knownIntents: knownIntents)
                entries.append(Entry(asked: asked, rule: rule, timing: timing))
            case .motion:
                let proposal = try ChatDraft.motion(fromJSON: answer.json)
                // THE SAME GATE AND THE SAME JUDGE the Apple path faces. A
                // server-drafted motion is not a different kind of draft.
                let draft: IntentDraft
                switch gate.draft(proposal) {
                case .drafted(let resolved):
                    draft = resolved
                case .feedback(let reason), .stopped(let reason):
                    entries.append(Entry(asked: asked, refusal: reason, timing: timing))
                    return
                }
                if let broken = draft.problems.first(where: { $0.severity == .broken }) {
                    entries.append(Entry(asked: asked, refusal: broken.text, timing: timing))
                    return
                }
                drafts.save(draft)
                let notes = draft.problems.map(\.text).joined(separator: " ")
                entries.append(Entry(asked: asked, motionDraftID: draft.id,
                                     motionSummary: "\(draft.name) — \(draft.keys.count) keyframes"
                                         + (notes.isEmpty ? "" : ". \(notes)"),
                                     timing: timing))
                previewing = DraftID(id: draft.id)
            case .train:
                // The prop the sentence names, so the request is about a real
                // object rather than an idea of one.
                let named = sceneProps.first { asked.lowercased().contains($0.name.lowercased()) }
                let request = try ChatDraft.training(fromJSON: answer.json, prop: named)
                entries.append(Entry(asked: asked, request: request, timing: timing))
            case .fetch:
                // THE MODEL SIZES THE OBJECT; IT DOES NOT JUDGE THE ROBOT.
                // Whether a duck can lift the thing is decided here, against
                // measurements, offline. Letting a language model answer
                // "can it?" would hand it the one part that is actually known.
                // A PROP YOU BUILT BEATS ANYTHING THE MODEL ESTIMATED. If the
                // sentence names something in one of your scenes, that object's
                // own numbers win — the model's job was to read the sentence,
                // not to guess at a broom you have already described.
                if let mine = Retrieval.plan(for: asked, props: sceneProps).reading.object,
                   sceneProps.contains(where: { $0.name.lowercased() == mine.lowercased() }) {
                    let (reading, plan) = Retrieval.plan(for: asked, props: sceneProps)
                    entries.append(Entry(asked: asked, plan: plan,
                                         planObject: reading.object, timing: timing))
                } else {
                    let (object, stick) = try ChatDraft.stick(fromJSON: answer.json)
                    entries.append(Entry(asked: asked,
                                         plan: Retrieval.plan(for: stick),
                                         planObject: object, timing: timing))
                }
            }
        } catch let wire as ChatWire.WireError {
            entries.append(Entry(asked: asked, refusal: wire.message))
        } catch let draft as ChatDraft.DraftError {
            entries.append(Entry(asked: asked, refusal: draft.message))
        } catch let refusal as ModelEndpoint.Refusal {
            entries.append(Entry(asked: asked, refusal: refusal.message))
        } catch let error as MotionProposal.Unresolvable {
            entries.append(Entry(asked: asked, refusal: error.message))
        } catch let error as AutomationProposal.Unresolvable {
            entries.append(Entry(asked: asked, refusal: error.message))
        } catch let error as AutomationValidator.Refusal {
            entries.append(Entry(asked: asked, refusal: error.message))
        } catch {
            entries.append(Entry(asked: asked,
                                 refusal: "The model could not answer: \(error.localizedDescription)"))
        }
    }

    /// A fetch, read without any model at all.
    ///
    /// SIZING A STICK DOES NOT NEED A LANGUAGE MODEL, and on a device with no
    /// Apple Intelligence and no server configured this is still the whole
    /// feature. A model only makes the sentence freer.
    private func draftFetchLocally(_ asked: String) {
        let (reading, plan) = Retrieval.plan(for: asked, props: sceneProps)
        entries.append(Entry(asked: asked,
                             plan: plan,
                             planObject: reading.object,
                             timing: reading.assumed.isEmpty ? nil
                                 : "Guessed: " + reading.assumed.joined(separator: "; ")))
    }

    /// Everything in every scene the duck could take hold of.
    private var sceneProps: [DuckScene.Prop] { scenes.scenes.flatMap(\.props) }

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
