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
///
/// AND THE COLOUR SAYS SO TOO, WHICH IS THE POINT OF THE PALETTE'S PROVENANCE
/// ALIASES. This is the screen where a sentence somebody typed turns into
/// something that looks like an answer, so every card has to be legible as one
/// of three things at a glance. `Theme.asked` — yellow — is what somebody asked
/// for and what has not happened: a rule that resolved and cannot fire, a
/// reading the app guessed at. `Theme.measured` is a number a machine produced.
/// `Theme.success` is a result that exists, and `Theme.refused` is a no.
/// Nothing wears a colour without a glyph beside it, because a seal is exactly
/// the shape a person stops reading.
///
/// THE GREEN SEAL ON AN UNREAD SENTENCE IS THE BUG THIS SCREEN EXISTS NOT TO
/// HAVE, and the drawing now backs the check that prevents it. When the reader
/// got nothing out of a sentence the card takes the caveat token and a question
/// mark rather than the verdict's green or red — because nothing was refused
/// either; the reading failed, not the duck.
struct AutomationChatView: View {

    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    /// Which model writes the draft. Apple's, a box on your network, or
    /// another app on this phone — the draft lands in the same checker either
    /// way, so this is a choice about privacy and speed, not about trust.
    @ObservedObject var models: EndpointStore
    /// HELD AND NOT READ, WHICH IS DELIBERATE AND SHOULD NOT LAST. It existed
    /// to hand to Settings from this screen's own gear, and the gear is gone —
    /// drafting is a row inside Studio now, and Studio's root carries the one
    /// gear. It stays because `StudioHubView` constructs this view exactly as
    /// the old shell did, and because a drafted motion wanting a bench to run
    /// on is the obvious next thing this screen asks for. Whoever needs neither
    /// should delete it and the argument label with it, in one change rather
    /// than by removing the call site first.
    @ObservedObject var benches: BenchStore
    @ObservedObject var plans: PlanStore

    @State private var typed = ""
    /// WHAT THE ROUTER LAST DECIDED, not what somebody picked in advance.
    ///
    /// This used to be a segmented control at the top of the screen, so before
    /// anybody could say what they wanted they had to know which of four
    /// internal categories it fell into. Those are the app's categories: a
    /// person who wants the duck to bow when the door opens has written a rule
    /// whose action is a motion that does not exist yet, and no tab was right
    /// for that sentence. The model reads the sentence instead — see
    /// `DraftRouting` — and this holds what it concluded, so the placeholder
    /// and the stop-gate still have something to key on.
    @State private var mode: Mode = .motion
    /// The one thing the router wanted to know before it could tell. Shown as
    /// a question in the transcript; answering it is just typing again.
    @State private var routerQuestion: String?
    /// What the router concluded and why, shown above the transcript so a wrong
    /// turn can be corrected in one sentence instead of started again.
    @State private var reading: String?
    @State private var entries: [Entry] = []
    @State private var thinking = false
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var previewing: DraftID?
    /// A `.duck` task on its way out, presented on the file itself rather than
    /// on a flag beside it — see `ExportedFile`, which exists because the pair
    /// it replaced could reach a state where the sheet was open and the file
    /// was not there.
    /// Why a task could not be written. This screen refuses things for a
    /// living; it does not get to fail quietly when it is the one that failed.
    @State private var exportFailure: String?
    /// Named once a plan has been kept, so the card can say so.
    @State private var kept: String?
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

        /// The tab a routed kind lands on. `tweak` has none: it edits a motion
        /// already on screen and is never routed from a typed sentence.
        init?(_ kind: ChatDraft.Kind) {
            switch kind {
            case .motion:    self = .motion
            case .rule:      self = .rule
            case .retrieval: self = .fetch
            case .training:  self = .train
            case .tweak:     return nil
            }
        }

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
        /// What the reader actually got out of the sentence. CARRIED, NOT
        /// RECOMPUTED: the card must say the same thing about a sentence that
        /// `RetrieveView` does, and re-reading it here is how the two screens
        /// would drift. Nil on an entry that is not a fetch.
        var planConfidence: Retrieval.Reading.Confidence? = nil
        /// The reader's own sentence about how it read this, pinned in
        /// StudioKit so a test asserts it letter by letter.
        var planReading: String? = nil
        /// A request to train a new policy — written here, run elsewhere.
        var request: TrainingRequest? = nil
        /// What the model cost in wall-clock, when it was not Apple's. A local
        /// model on a small board is slow, and saying so beats a spinner.
        var timing: String? = nil
        /// The model that read this sentence, or nil when nothing did.
        ///
        /// NIL IS THE COMMON CASE FOR A FETCH, AND `provenance` USED TO LIE
        /// ABOUT IT. `DuckPlanFile.provenance` is "where it came from — a
        /// person, or a named model", and `save` filled it unconditionally with
        /// `models.selected.name`. Two of the three routes to a fetch card run
        /// no model at all: `draftFetchLocally` is pure `Retrieval` — its own
        /// comment says sizing a stick does not need a language model — and it
        /// is reached both from the Apple branch and from the no-model
        /// fallback, where `models.selected` is merely whatever is picked and
        /// may never have been contacted. Plans were being stamped with the
        /// name of a model that never saw them.
        var drafter: String? = nil
    }

    private var knownIntents: Set<String> { Set(clips.keys) }

    var body: some View {
        VStack(spacing: 0) {
            List {
                // HOW THE SENTENCE WAS READ, above everything else. Losing the
                // picker means nobody chooses the kind any more, so the app has
                // to say which one it took — otherwise a wrong turn is
                // invisible until a training brief arrives for a bow.
                if let reading {
                    Section {
                        Label(reading, systemImage: "arrow.triangle.branch")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
                Section {
                    // A MODEL THAT CANNOT BE USED IS A CAVEAT WITH A GLYPH, not
                    // an orange paragraph. `AnyShapeStyle` was here only to make
                    // the system's `.secondary` and a raw `Color.orange` share a
                    // ternary; both sides are palette tokens now, so the
                    // erasure goes with them — and the branch buys the triangle,
                    // which is what carries the state for somebody who reads
                    // shape before hue.
                    if availability.isUsable {
                        Text(availability.explanation)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Label(availability.explanation,
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                    NavigationLink {
                        ModelSettingsView(store: models)
                    } label: {
                        Label(models.selected.name, systemImage: "brain")
                            .font(.footnote)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    Text(blurb).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                ForEach(entries) { entry in
                    Section {
                        // THE PERSON'S OWN WORDS ARE THE CARD'S HEADING, so
                        // they are set in ink at a heading's weight rather than
                        // in the provenance colour. Everything under them is
                        // what the app made of them, and if the question wore
                        // the same yellow as the answers there would be no
                        // question and no answers, just a yellow card.
                        Text(entry.asked)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)

                        if let rule = entry.rule {
                            // A RULE THAT RESOLVED AND CANNOT FIRE IS THE
                            // PUREST "ASKED, NOT MEASURED" THING THE APP
                            // PRODUCES. The seal is true — the sentence became a
                            // legal when/then — and the yellow is what stops it
                            // reading as a rule that is now running. The blurb
                            // above says the same thing in words; this says it
                            // in the one channel somebody skimming actually
                            // uses.
                            Label(rule.sentence, systemImage: "checkmark.seal")
                                .font(.footnote)
                                .foregroundStyle(Theme.asked)
                            Text("\(rule.name) · \(rule.origin.described)")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                            // THE RULE'S OTHER HALF: what it would actually
                            // do. A when/then whose "then" you can watch is a
                            // rule; one you cannot is a sentence.
                            if case .play(let intentName) = rule.then,
                               let clip = clips[intentName] {
                                NavigationLink {
                                    IntentPlayerView(clip: clip, store: scenes,
                                                     drafts: drafts, models: models)
                                } label: {
                                    Label("Watch what it would play",
                                          systemImage: "play.circle")
                                        .font(.footnote)
                                }
                            }
                        }

                        if let summary = entry.motionSummary {
                            // A DRAFTED MOTION IS A RESULT: it is in the store,
                            // it opens in the editor, and every slider in it is
                            // where the sentence put it. That is the one thing
                            // on this screen that actually happened, so it is
                            // the only success token on the card.
                            Label(summary, systemImage: "figure.dance")
                                .font(.footnote)
                                .foregroundStyle(Theme.success)
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
                            // A GREEN SEAL FOR A SENTENCE NOBODY READ IS THE
                            // BUG THIS APP EXISTS TO NOT HAVE. `plan.isPossible`
                            // is perfectly true of the invented 20 g object the
                            // reader falls back to, so asking it alone answers
                            // "it can do this" to "fetch me a beer". The seal
                            // now requires that something was actually read out
                            // of the sentence, and `RetrieveView` makes the
                            // same check against the same enum.
                            if entry.planConfidence == .notUnderstood {
                                // NEITHER GREEN NOR RED, BECAUSE NEITHER
                                // HAPPENED. Nothing was refused — the duck was
                                // never asked about anything, since no object
                                // came out of the sentence — so this is the
                                // caveat token and a question mark. Painting it
                                // in the refusal colour would put a robot's
                                // verdict on a parser's shrug, which is the
                                // other half of the same bug as the green seal.
                                Label(entry.planReading ?? "",
                                      systemImage: "questionmark.circle")
                                    .font(.footnote).foregroundStyle(Theme.warning)
                            } else {
                                Label(plan.isPossible
                                      ? "It can do this — \(String(format: "%.0f s", plan.seconds))"
                                      : "It cannot do this",
                                      systemImage: plan.isPossible ? "checkmark.seal" : "xmark.octagon")
                                    .font(.footnote)
                                    .foregroundStyle(plan.isPossible ? Theme.success : Theme.refused)
                            }
                            // THE OBJECT'S NUMBERS ARE WHAT WAS MEASURED, or
                            // what stands in for it — `Theme.measured` is the
                            // palette's claim that a number came off a bench or
                            // out of the kinematics rather than out of a
                            // sentence, and the "Guessed" line above says which
                            // of the two this is when it is not.
                            Text(String(format: "%@%.0f g, %.0f mm thick, %.1f m away",
                                        entry.planObject.map { "\($0): " } ?? "",
                                        plan.stick.grams, plan.stick.thicknessMillimetres,
                                        plan.stick.metresAway))
                                .font(.caption).foregroundStyle(Theme.measured)
                            // FATAL IS A REFUSAL AND THE REST ARE CAVEATS, and
                            // both now carry a glyph. They were bare `Text` in
                            // two colours, which is precisely the thing the
                            // design system refuses: a person who cannot
                            // separate the two hues had no way at all to tell a
                            // "this will not work" from a "watch out for this".
                            ForEach(plan.refusals, id: \.message) { refusal in
                                Label(refusal.message,
                                      systemImage: refusal.isFatal
                                      ? "xmark.octagon" : "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(refusal.isFatal ? Theme.refused : Theme.warning)
                            }
                            // THE PLAN ON THIS CARD, NOT A DIFFERENT ONE.
                            //
                            // This was a NavigationLink to `RetrieveView()`,
                            // which takes no arguments and cannot be told
                            // anything: it opens on its own literal default,
                            // "fetch the stick 1 m away", and its "Save as a
                            // .duck task" writes THAT stick under THAT name.
                            // So somebody who typed "fetch the carrot", read
                            // "60 g is more than it can lift" right here, and
                            // tapped through to export, got fetch-the-stick.duck
                            // saying "Inside every envelope." A task file
                            // carries its constraints in its own body — that is
                            // the whole reason the format exists — so the wrong
                            // body is not a cosmetic wrong. It is a file that
                            // tells whoever runs it the job is fine at the
                            // exact moment this screen said it is not.
                            //
                            // Exporting from here instead makes the file and
                            // the card the same thing by construction: one
                            // `plan`, computed once in `draftFetchLocally` or
                            // `draftOnServer` with the scene's own props, shown
                            // above and written below. Nothing re-reads the
                            // sentence and nothing can disagree.
                            //
                            // THAT LIMITATION IS LIFTED. `RetrieveView` now
                            // takes an `opening: DuckPlanFile` and restores the
                            // measurement it was kept with, so a plan kept here
                            // opens there showing these numbers rather than
                            // whatever the sentence-only reader makes of the
                            // words a second time.
                            Button {
                                save(plan, named: entry.asked, by: entry.drafter)
                            } label: {
                                Label("Keep this plan",
                                      systemImage: "tray.and.arrow.down")
                                    .font(.footnote)
                            }
                            // REFUSED FOR THE SAME REASON `RetrieveView` refuses
                            // it: a kept plan states its object's weight and
                            // thickness as facts — they are the whole file, and
                            // the schedule is derived from them every time it is
                            // opened — and for a sentence nothing was read out
                            // of, those numbers are this app's invented 20 g /
                            // 20 mm dowel. Writing them down makes an invention
                            // into a measurement somebody comes back to.
                            .disabled(entry.planConfidence == .notUnderstood)
                            // WRITTEN AND RENDERED NOWHERE, for one revision.
                            // `kept` was set on success and read in no `body`,
                            // so the entire success path of the button above it
                            // was: press, nothing changes, go and look in
                            // another tab. Only the failure had a voice.
                            if kept == entry.asked {
                                // A FILE ON THE PHONE IS A RESULT, which is the
                                // one thing the success token is for.
                                // THE PATH, NOT THE TAB. Motions stopped being
                                // a tab and became a row inside Studio, and
                                // "your Motions" was already asking somebody to
                                // know that. An arrow is the shortest true way
                                // to say where a thing went.
                                Label("Kept — it is in Studio → Motions, under Plans.",
                                      systemImage: "checkmark.circle")
                                    .font(.caption).foregroundStyle(Theme.success)
                            }
                        }

                        if let request = entry.request {
                            // WORTH TRAINING IS A VERDICT AND THE VERDICT IS
                            // ABOUT A REQUEST — the same pair `TrainingRequestView`
                            // draws on the screen this row opens, in the same two
                            // tokens, so the card and the request cannot say
                            // different things about the same brief.
                            Label(request.isTrainable
                                  ? "Worth training — \(request.rewards.count) rewards"
                                  : "Not worth training",
                                  systemImage: request.isTrainable
                                  ? "checkmark.seal" : "xmark.octagon")
                                .font(.footnote)
                                .foregroundStyle(request.isTrainable ? Theme.success : Theme.refused)
                            Text("Forks \(request.base.rawValue)").font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            ForEach(request.rewards) { reward in
                                Text("\(reward.function) × \(String(format: "%g", reward.weight)) — \(reward.reason)")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            ForEach(request.refusals, id: \.message) { refusal in
                                Label(refusal.message,
                                      systemImage: refusal.isFatal
                                      ? "xmark.octagon" : "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(refusal.isFatal ? Theme.refused : Theme.warning)
                            }
                            NavigationLink {
                                TrainingRequestView(request: request)
                            } label: {
                                Label("Open the request", systemImage: "doc.text")
                                    .font(.footnote)
                            }
                        }

                        if let timing = entry.timing {
                            // NOT MONOSPACED, THOUGH IT IS ALL NUMBERS. This is
                            // what one finished call cost, written down once; it
                            // never changes again, and tabular figures on it
                            // would tell the reader to watch a stopwatch that
                            // has already stopped.
                            Text(timing).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }

                        if let refusal = entry.refusal {
                            // EVERY WAY THIS SCREEN CAN SAY NO ARRIVES HERE —
                            // the wire, the model, the router's question, the
                            // gate giving up — and all of them are a no, so all
                            // of them are the refusal token.
                            Label(refusal, systemImage: "xmark.octagon")
                                .font(.footnote).foregroundStyle(Theme.refused)
                        }
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
            // EVERY CARD ON A REAL SURFACE, AND THE CARDS ON THE RECESSED
            // GROUND. `Theme` records that the four inks land short of 4.5:1
            // against `backgroundSecondary` and clear it against
            // `surfacePrimary`, which is what makes every provenance colour on
            // these cards a legible claim rather than a hopeful one.
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .scrollDismissesKeyboard(.interactively)
            // The house pattern: present on the value, and put the sheet down
            // again when UIKit says the share is over. Hung on the list rather
            // than on the enclosing stack because the draft preview already
            // owns a sheet there.
            .alert("That did not save",
                   isPresented: .constant(exportFailure != nil),
                   presenting: exportFailure) { _ in
                Button("OK") { exportFailure = nil }
            } message: { Text($0) }

            // THE COMPOSER IS FURNITURE AND SITS ON THE PAGE, NOT IN THE LIST.
            // A hairline of the palette's separator along its top edge is what
            // separates it from the cards above; without one it floats on the
            // same ground as the list it is not part of. `DriveView`'s pinned
            // transport is built the same way and for the same reason.
            HStack(spacing: Theme.spacing(.tight)) {
                // ONE PLACEHOLDER, NOT ONE PER TAB. It shows the range rather
                // than one kind, because the point of losing the picker is that
                // nobody has to know which kind theirs is.
                TextField(routerQuestion ?? "Take a slow bow — or fetch the stick, or sit when something is close",
                          text: $typed, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .focused($typing)
                    .disabled(!availability.isUsable || thinking || motionDraftingStopped)
                Button {
                    Task { await draft() }
                } label: {
                    // A GLYPH IS NOT A TARGET. This was a title-sized symbol
                    // with no frame — about twenty-two points, half the Human
                    // Interface Guidelines' floor, on the one control that
                    // sends anything. The frame and the content shape make the
                    // hit area the button rather than the ink.
                    Image(systemName: thinking ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.title2)
                        .frame(minWidth: Theme.spacing(.loose) + Theme.spacing(.loose),
                               minHeight: Theme.spacing(.loose) + Theme.spacing(.loose))
                        .contentShape(Rectangle())
                }
                // THE ONLY WAY OFF THIS SCREEN'S TEXT FIELD, and an
                // icon-only one: unlabelled it announces the symbol name, and
                // while the model is thinking the symbol CHANGES, so it would
                // announce a different one. The name stays put and the
                // system's own "dimmed" carries the wait — the button is
                // disabled for every reason it cannot be pressed, and the
                // reason itself is already the last card in the list.
                .accessibilityLabel(Text("Send"))
                // A STOP THAT DOES NOT STOP ANYTHING IS A MESSAGE. When the
                // gate has given up, the field goes with it — the reason is
                // already the last thing in the list.
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty
                          || !availability.isUsable || thinking || motionDraftingStopped)
            }
            .padding(Theme.spacing(.snug))
            .background(alignment: .top) {
                Rectangle().fill(Theme.separator)
                    .frame(height: AuthoringMetric.hairlineStroke)
            }
            .background(Theme.backgroundPrimary)
        }
        .background(Theme.backgroundPrimary)
        .navigationTitle("Draft with words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // NO GEAR HERE ANY MORE. ONE PER TAB ROOT, AND THIS IS NO LONGER
            // ONE. Drafting with words is a row inside Studio, whose own root
            // carries the gear — so a gear here put two of them one tap apart,
            // in the same corner, leading to the same screen, which reads as
            // two different Settings until somebody opens both to find out.
            // The model picker in this screen's own header is untouched: that
            // one chooses WHO writes the draft, which is a decision about this
            // conversation rather than about the app.
            //
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
                } else {
                    // A SHEET A PERSON CANNOT LEAVE IS THE WORST STATE THIS APP
                    // CAN REACH, and this had the same missing `else` that
                    // IntentListView documented and fixed. Chat cards are never
                    // pruned, so a card keeps its draft id after the draft is
                    // deleted and "Preview again" presented a blank rectangle:
                    // no title, no Cancel, no Done.
                    ContentUnavailableView {
                        Label("That motion is not here", systemImage: "questionmark.square.dashed")
                    } description: {
                        Text("It was written from this conversation and has since been deleted "
                           + "from your drafts. The conversation above is unchanged.")
                    } actions: {
                        Button("Close") { previewing = nil }
                    }
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
            return "Describe a motion and the robot performs your words in 3D, immediately — then open the keyframes and see the sliders the sentence moved. Drafts land in Studio → Motions."
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
        // A DOWNLOADED MODEL IS USABLE TOO. This read `== .openAICompatible`,
        // so a phone holding weights somebody had just spent two gigabytes on
        // fell into Apple's branch and was told "this device does not have
        // Apple Intelligence" — the one sentence guaranteed to make them think
        // the download was wasted.
        if models.selected.kind == .openAICompatible || models.selected.kind == .downloadedMLX {
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
                    + "to draft with. Motions can still be written by hand in Studio → Motions.")
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
        // Both non-Apple kinds go through DraftEngine, which switches on kind
        // itself; only Apple's needs the typed-value path below.
        if models.selected.kind != .appleOnDevice {
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
        // FETCH NEVER NEEDED A MODEL, and losing the picker must not lose that.
        // `DraftRouting.withoutAModel` claims a fetch only when `Retrieval`
        // actually recognised something — the same test the fetch screen uses
        // before it will show a green seal — and refuses to guess at the other
        // three.
        if case .kind(.retrieval, _)? = DraftRouting.withoutAModel(asked) {
            mode = .fetch
            draftFetchLocally(asked)
            return
        }
        entries.append(Entry(asked: asked, refusal: DraftRouting.needsAModel))
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
            // ROUTE FIRST, and let it decline. A second call costs a few
            // seconds; guessing wrong costs a whole round trip AND produces a
            // confident answer to a question nobody asked — a training brief
            // for somebody who wanted a bow. The router may come back with one
            // question instead, which is the thing a segmented control could
            // never do: ask.
            let routing = try await DraftEngine.ask(
                endpoint, kind: .motion, prompt: asked, knownIntents: knownIntents,
                instructions: DraftRouting.instructions(knownIntents: knownIntents))
            switch try DraftRouting.read(fromJSON: routing.json) {
            case .ask(let question):
                routerQuestion = question
                entries.append(Entry(asked: asked, refusal: question))
                return
            case .kind(let kind, let because):
                routerQuestion = nil
                mode = Mode(kind) ?? mode
                reading = because.isEmpty ? nil : "Reading this as \(kind.spoken) — \(because)."
            }

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
                                         planObject: reading.object,
                                         planConfidence: reading.confidence,
                                         planReading: reading.sentence, timing: timing,
                                         drafter: endpoint.name))
                } else {
                    // A MODEL READ THIS ONE, SO THE LOCAL READER'S CONFIDENCE
                    // WOULD BE THE WRONG ANSWER. `ChatDraft.stick` got a named
                    // object and real dimensions out of the sentence by a route
                    // this app's own parser does not have, so asking
                    // `Retrieval.read` what IT would have made of the sentence
                    // and reporting that would refuse a plan that was in fact
                    // understood. `.understood` here is a claim about the
                    // model's reading, and `timing` above already says a model
                    // was involved.
                    let (object, stick) = try ChatDraft.stick(fromJSON: answer.json)
                    entries.append(Entry(asked: asked,
                                         plan: Retrieval.plan(for: stick),
                                         planObject: object,
                                         planConfidence: .understood, timing: timing,
                                         drafter: endpoint.name))
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
                             planConfidence: reading.confidence,
                             planReading: reading.sentence,
                             timing: reading.assumed.isEmpty ? nil
                                 : "Guessed: " + reading.assumed.joined(separator: "; ")))
    }

    /// Write the plan a card is showing, titled with the sentence that made it.
    ///
    /// Keep a plan drafted in this conversation, in this app's own format.
    ///
    /// IT USED TO EXPORT A `.duck` — quackd's task file — which this app could
    /// not read back, so a fetch worked out here left as a file that returned
    /// "nothing was added" if anyone tried to bring it home. `DuckPlanFile` is
    /// ours and round-trips, and a kept plan appears in Studio → Motions beside
    /// the motions.
    ///
    /// THE TITLE IS THE PERSON'S OWN WORDS, not a phrase composed here.
    private func save(_ plan: Retrieval.Plan, named title: String, by drafter: String?) {
        let file = DuckPlanFile(name: title, stick: plan.stick, asked: title,
                                provenance: drafter.map { "Drafted by \($0)" }
                                         ?? "Read on this phone, no model")
        guard plans.save(file) else {
            exportFailure = "That plan could not be kept on this phone."
            return
        }
        kept = title
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
