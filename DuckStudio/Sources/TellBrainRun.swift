import CoreGraphics
import SwiftUI
import StudioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// Typed Tell with a model (build 91). The kit decides everything (`TellRouter`, `BrainRunner`,
// `TellGoCard`, `TellSummary`); this file builds the planner the person chose, holds the Go card
// and the question while a run waits on the person, and draws them.
//
// STOP IS NOT HERE. The red disc, the pill and every other Stop go through `DuckRuns.stop` and
// `StopPath` exactly as before; the runner is registered with that path and is cancelled by it.

// MARK: - Apple's on-device model as a planner

/// Apple's on-device model, asked for ONE decision from the closed set with guided generation.
/// The decoder can only write a v1 kind and a name from the duck's list; the kit then reads the
/// answer again against this run's set (`OnDeviceDecision.read`). Nothing leaves the device.
struct ApplePlanner: Planner {
    let info: PlannerInfo = .appleOnDevice(system: ApplePlanner.system)

    static var system: String {
#if os(macOS)
        "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
#else
        "iOS " + ProcessInfo.processInfo.operatingSystemVersionString
#endif
    }

    func decide(_ ask: PlannerAsk) async throws -> Decided {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let clock = ContinuousClock()
            let start = clock.now
            let session = LanguageModelSession(instructions: OnDeviceDecision.instructions(for: ask.allowed))
            let out = try await session.respond(to: LocalDecisionPrompt.userText(ask), generating: AppleStep.self).content
            let reading = OnDeviceDecision.read(kind: out.kind, forwardM: out.forwardM, sideM: out.sideM,
                                                degrees: out.degrees, name: out.name, text: out.text, why: out.why,
                                                allowed: ask.allowed)
            return Decided(decision: reading.decision, why: reading.why, provider: info, latency: clock.now - start)
        }
#endif
        throw TellPlannerProblem(says: DuckDecider.Availability.needsNewerSystem.says)
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct AppleStep {
        // ENFORCED AT DECODE: only these words can be written, and the kit reads them again.
        @Guide(description: "Exactly one kind of step, from the kinds the instructions allow.", .anyOf(OnDeviceDecision.kindWords))
        var kind: String
        @Guide(description: "For walk: metres forward, negative for back. Otherwise 0.")
        var forwardM: Double
        @Guide(description: "For walk: metres to the left, negative for right. Otherwise 0.")
        var sideM: Double
        @Guide(description: "For turn: degrees, positive to the left. Otherwise 0.")
        var degrees: Double
        @Guide(description: "For skill or sound: the name from the instructions. Otherwise none.", .anyOf(DuckDecider.nameWords))
        var name: String
        @Guide(description: "For ask: the question. For done or stop: the reason. Otherwise empty.")
        var text: String
        @Guide(description: "Why this step, in one short sentence.")
        var why: String
    }
#endif
}

/// Why a Tell planner could not be built or asked, in a sentence.
struct TellPlannerProblem: Error, CustomStringConvertible {
    let says: String
    var description: String { says }
}

// MARK: - building the planner the person chose

@MainActor
enum TellPlanners {
    /// Whether Apple's on-device model can answer here, in the kit's words.
    static var appleAvailability: DuckDecider.Availability {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.deviceNotEligible): return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
            case .unavailable(.modelNotReady): return .modelNotReady
            default: return .unavailable
            }
        }
#endif
        return .needsNewerSystem
    }

    static var stored: TellPlannerChoice {
        TellPlannerChoice(stored: UserDefaults.standard.string(forKey: TellPlannerChoice.storageKey))
    }

    /// The planner card a choice would run as, for the offer rule. Nil for no model, and for
    /// Apple's, which the rule does not cover (`TellOffer`).
    static func card(_ choice: TellPlannerChoice, models: EndpointStore) -> PlannerInfo? {
        switch choice {
        case .wordsOnly, .apple: return nil
        case .draftModel: return TellOffer.draftCard(models.selected)
        case .anthropic, .openai: return choice.hostedVendor?.info()
        }
    }

    static func status(_ choice: TellPlannerChoice, models: EndpointStore, venue: BrainVenue) -> TellOffer.Status {
        TellOffer.status(choice, card: card(choice, models: models), venue: venue)
    }

    /// What `TellRouter` needs to know right now. A saved choice the offer rule does not pass at
    /// this duck's venue is "Only what this device reads".
    static func setup(duck: DuckIdentity.Kind?, models: EndpointStore, skills: [String]) -> TellSetup {
        let saved = stored
        let choice = TellOffer.effective(saved, status: status(saved, models: models,
                                                               venue: duck == .real ? .real : .practice))
        return TellSetup(duck: duck, choice: choice, agreement: PlannerSafetyStore.shared.settings.agreementStatus(),
                         apple: appleAvailability, draftModel: models.selected.kind,
                         hostedKeySaved: choice.hostedVendor.map { HostedKeyStore.load($0) != nil } ?? false,
                         skills: skills)
    }

    /// The planner, wrapped so it refuses without the adult's agreement.
    static func make(_ choice: TellPlannerChoice, models: EndpointStore) async throws -> AgreedPlanner {
        let settings = PlannerSafetyStore.shared.settings
        let inner: any Planner
        switch choice {
        case .wordsOnly:
            throw TellPlannerProblem(says: TellWords.title(.wordsOnly))
        case .apple:
            inner = ApplePlanner()
        case .draftModel:
            let endpoint = models.armed(models.selected)
            switch endpoint.kind {
            case .downloadedMLX:
                inner = try PhoneMLXPlanner(endpoint: endpoint, version: PhoneMLXRunner.version(for: endpoint.model),
                                            runner: PhoneMLXRunner())
            case .openAICompatible:
                // The pinned version when the server says which build it holds; otherwise unpinned.
                let version = (try? await LANPlanner.identifyOllama(endpoint)) ?? LocalModelVersion(model: endpoint.model)
                inner = try LANPlanner(endpoint: endpoint, version: version)
            case .appleOnDevice:
                inner = ApplePlanner()
            }
        case .anthropic, .openai:
            guard let vendor = choice.hostedVendor, let key = HostedKeyStore.load(vendor) else {
                throw PlannerError.noKey
            }
            let camera = settings.cameraConsent(vendor.providerId)
            if vendor == .anthropic {
                inner = AnthropicPlanner(key: key, cameraConsent: camera)
            } else {
                inner = OpenAIPlanner(key: key, cameraConsent: camera)
            }
        }
        return AgreedPlanner(inner, settings: settings)
    }
}

// MARK: - the run's state on screen

/// What a Tell run with a model shows: the Go card, the question, the steps so far, and at the
/// end the summary. The runner waits on the person through `AnswerSlot`s, so a Stop that abandons
/// a card or a question leaves nothing parked.
@MainActor
final class TellBrainModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case thinking
        case card(TellGoCard)
        case asking(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var steps: [BrainStep] = []
    /// Who is picking the steps, for the status line.
    @Published private(set) var who = ""
    /// When a counting-down card goes by itself.
    @Published private(set) var goesAt: Date?
    @Published var summary: TellSummary?
    @Published var showingSteps = false

    private var card: AnswerSlot<Bool>?
    private var question: AnswerSlot<String?>?
    private var countdown: Task<Void, Never>?

    var running: Bool { phase != .idle }

    var asking: String? {
        if case .asking(let q) = phase { return q }
        return nil
    }

    func begin(_ who: String) {
        self.who = who
        steps = []
        summary = nil
        showingSteps = false
        phase = .thinking
    }

    func end(_ summary: BrainRunSummary?) {
        countdown?.cancel()
        countdown = nil
        goesAt = nil
        card?.give(false)
        question?.give(nil)
        card = nil
        question = nil
        phase = .idle
        self.summary = summary.map(TellSummary.init)
    }

    func step(_ s: BrainStep) { steps.append(s) }

    /// The Go card. Answers true for Go, false for Cancel, a Stop or the end of the run.
    func confirm(_ raw: BrainRunner.ConfirmCard) async -> Bool {
        let slot = AnswerSlot<Bool>()
        let shown = TellGoCard(raw)
        card = slot
        phase = .card(shown)
        if let seconds = shown.countdown {
            goesAt = Date().addingTimeInterval(seconds)
            countdown = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if !Task.isCancelled { slot.give(true) }
            }
        }
        let answer = await slot.wait(ifCancelled: false)
        countdown?.cancel()
        countdown = nil
        goesAt = nil
        if card === slot {
            card = nil
            if phase != .idle { phase = .thinking }
        }
        return answer
    }

    func go() { card?.give(true) }
    func cancelCard() { card?.give(false) }

    /// The planner's question. Nil when the person closes it without answering.
    func ask(_ q: String) async -> String? {
        let slot = AnswerSlot<String?>()
        question = slot
        phase = .asking(q)
        let answer = await slot.wait(ifCancelled: nil)
        if question === slot {
            question = nil
            if phase != .idle { phase = .thinking }
        }
        return answer
    }

    func answer(_ text: String?) { question?.give(text) }
}

// MARK: - the panel while a run goes

/// Takes the Tell panel's place while a model picks the steps: the Go card when one is up,
/// otherwise who is thinking, the last step, and Take over. Stop stays the red disc top right.
struct TellRunPanel: View {
    @ObservedObject var model: TellBrainModel
    let venue: BrainVenue
    let takeOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            if case .card(let card) = model.phase {
                TellGoCardView(card: card, goesAt: model.goesAt, go: model.go, cancel: model.cancelCard)
            } else {
                RunStatusLine(symbol: "sparkles",
                              line: model.asking == nil ? TellWords.thinking(model.who) : TellWords.askTitle,
                              takeOver: takeOver)
            }
            if let last = model.steps.last {
                Text(TellWords.stepLine(last, venue: venue))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Theme.spacing(.snug))
            }
        }
    }
}

/// The Go card: the label, the step in plain words, why, why it is asking, then Cancel and Go.
struct TellGoCardView: View {
    let card: TellGoCard
    let goesAt: Date?
    let go: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Text(TellWords.cardTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            if let label = card.label { PlannerStepLabelView(label: label) }
            Text(card.step)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let why = card.why {
                Text(TellWords.why(why))
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(card.reasons, id: \.self) { reason in
                Label(reason, systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TimelineView(.periodic(from: Date(), by: 0.5)) { context in
                Text(goesAt.map { TellWords.goingIn(max(0, Int($0.timeIntervalSince(context.date).rounded(.up)))) }
                     ?? TellWords.tapGo)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: Theme.spacing(.tight)) {
                Button(TellWords.cancel, action: cancel)
                    .buttonStyle(.bordered)
                    .frame(minHeight: DesignMetric.minimumTarget)
                Spacer(minLength: 0)
                Button(TellWords.go, action: go)
                    .buttonStyle(.primaryActionInline)
            }
        }
        .padding(Theme.spacing(.snug))
        .frame(maxWidth: .infinity, alignment: .leading)
        .pondPanel()
        .accessibilityElement(children: .contain)
    }
}

/// The summary chip at the end of a run: steps, the gate's count and how it ended. Tapping it shows
/// each step with its label.
struct TellSummaryChip: View {
    @ObservedObject var model: TellBrainModel

    var body: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                HStack(alignment: .top, spacing: Theme.spacing(.tight)) {
                    Button { model.showingSteps.toggle() } label: {
                        Label(summary.chip, systemImage: model.showingSteps ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityHint(Text(TellWords.showSteps))
                    Spacer(minLength: 0)
                    Button(TellWords.dismiss) { model.summary = nil }
                        .font(.caption)
                }
                if model.showingSteps {
                    ForEach(summary.rows, id: \.number) { row in
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                            Text(row.heading)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(row.outcome)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            if let why = row.why {
                                Text(TellWords.why(why)).font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            if let label = row.label { PlannerStepLabelView(label: label) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(summary.lines, id: \.self) { line in
                        Text(line).font(.caption2).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Theme.spacing(.tight))
            .frame(maxWidth: .infinity, alignment: .leading)
            .pondPanel(.control)
        }
    }
}

/// The planner's question, as a sheet. One is open at a time (the kit's rule). Closing it without
/// an answer ends the run.
struct TellAskSheet: View {
    let question: String
    let answer: (String?) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(question)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(TellWords.answerPlaceholder, text: $text)
                        .submitLabel(.send)
                        .onSubmit(send)
                } footer: {
                    Text(TellWords.askFootnote)
                }
            }
            .navigationTitle(TellWords.askTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TellWords.closeUnanswered) { answer(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(TellWords.answer, action: send)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func send() {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return }
        answer(said)
    }
}

// MARK: - the choice, on Models

/// "Tell with": which planner Tell asks when the phone cannot read a sentence. Apple's on-device
/// model is the default. Every other model shows only when the offer rule passes for it
/// (`TellOffer`); until then it is listed, greyed, with the rule's reason, and cannot be picked.
struct TellPlannerSection: View {
    @AppStorage(TellPlannerChoice.storageKey) private var stored = TellPlannerChoice.standard.rawValue
    @ObservedObject var models: EndpointStore

    /// The choice in force: a saved one the rule hides counts as "Only what this device reads".
    private var current: TellPlannerChoice {
        let saved = TellPlannerChoice(stored: stored)
        return TellOffer.effective(saved, status: TellPlanners.status(saved, models: models, venue: .practice))
    }

    var body: some View {
        Section {
            ForEach(TellPlannerChoice.allCases, id: \.self) { choice in
                let status = TellPlanners.status(choice, models: models, venue: .practice)
                Button { stored = choice.rawValue } label: {
                    HStack(spacing: Theme.spacing(.tight)) {
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                            Text(TellWords.title(choice)).foregroundStyle(Theme.textPrimary)
                            Text(TellWords.detail(choice))
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if case .notOfferedYet(let why) = status {
                                Text(why)
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Theme.spacing(.tight))
                        if current == choice {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.brandPrimary)
                                .accessibilityLabel(Text("Selected"))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!status.isOffered)
                .opacity(status.isOffered ? 1 : 0.6)
            }
        } header: {
            SectionHeading(text: TellWords.pickerHeading)
        } footer: {
            Text(TellWords.pickerFooter)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }
}
