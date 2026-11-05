import SwiftUI
import StudioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ask the duck: on-device Apple Intelligence as a DECIDER over the kit's closed set
/// (docs/plans/brains-layer.md 3.2; build 92).
///
/// IT PLANS, IT NEVER DRIVES. The model answers with a few steps, each one action from
/// `DuckDecider`'s closed set; `DuckDecider.validate` reads them into `DuckOrder`s or refuses the
/// plan in a sentence. The plan shows as chips for `DuckDecider.previewSeconds` with Cancel, then
/// the host runs it through `DuckRuns.runPlan` under the arbiter's cap and the one Stop.
///
/// A PLAN ON ITS WAY IS A RUN (build 93). From the sentence to the first step it is `PendingPlan`,
/// registered with the one Stop, so Stop, Siri, the Control and leaving the screen all end it
/// before a late answer could re-open the latch and walk the duck.
///
/// THE FAST PATH COMES FIRST. A sentence the deterministic matcher reads exactly ("sit down",
/// "quack") is planned without the model. Without Apple Intelligence that is all that runs, and
/// the card says so in the kit's words.
@MainActor
final class AskTheDuck: ObservableObject {

    enum Phase: Equatable {
        case idle
        case thinking
        /// Showing the plan before it runs.
        case preview([DuckOrder])
        /// Running step `Int` of the plan.
        case running(Int, [DuckOrder])

        var activeStep: Int? {
            if case .running(let i, _) = self { return i }
            return nil
        }
    }

    @Published var phase: Phase = .idle
    private lazy var pending = PendingPlan(register: { DuckRuns.shared.track(.plan, cancel: $0) },
                                           finished: { DuckRuns.shared.finished($0) })

    /// Whether Apple Intelligence can plan here, in the kit's words.
    var availability: DuckDecider.Availability {
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

    /// What planning answered: the plan, or the sentence to show instead.
    enum Planned {
        case plan([DuckOrder])
        case said(String)
    }

    /// Plan from a sentence. Answers the plan, or the sentence to show instead.
    func plan(_ text: String, on duck: DuckIdentity.Kind, skills: [String]?) async -> Planned {
        // THE FAST PATH: a sentence the matcher reads exactly needs no model.
        if let order = DuckOrderMatcher.match(text, skills: skills ?? Array(RobotPlan.skillSeconds.keys)) {
            if let why = order.notOn(duck) { return .said(why) }
            return .plan([order])
        }
        guard availability.isReady else { return .said(ControllerWords.heard(text)) }
        phase = .thinking
        defer { if phase == .thinking { phase = .idle } }
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: DuckDecider.instructions(on: duck, skills: skills))
                let drafted = try await session.respond(to: text, generating: AskedPlan.self).content
                let steps = drafted.steps.map { s in
                    DuckDecider.Step(action: s.action,
                                     direction: s.direction == "none" ? nil : s.direction,
                                     seconds: s.seconds,
                                     name: s.name == "none" ? nil : s.name)
                }
                switch DuckDecider.validate(steps, on: duck, skills: skills) {
                case .success(let orders): return .plan(orders)
                case .failure(let refusal): return .said(refusal.says)
                }
            } catch {
                return .said(DuckDecider.Words.modelFailed)
            }
        }
#endif
        return .said(ControllerWords.heard(text))
    }

    /// Work out a plan, show it for the preview beat, then hand it to `run`. A nil answer ends it
    /// here. Cancel, or any Stop, at any point before `run` sends nothing.
    func begin(asking: @escaping @MainActor () async -> [DuckOrder]?,
               then run: @escaping @MainActor ([DuckOrder]) -> Void) {
        pending.begin(asking: asking, show: { [weak self] in self?.phase = .preview($0) },
                      beat: DuckDecider.previewSeconds,
                      gone: { [weak self] in self?.cancelPreview() }, run: run)
    }

    /// Drop a plan that has not started: one still being thought about, or one on show.
    func cancelPreview() {
        pending.cancel()
        if phase.activeStep == nil { phase = .idle }
    }

    func running(step i: Int, of orders: [DuckOrder]) { phase = .running(i, orders) }

    /// The running plan finished. A newer sentence already on its way is left alone.
    func runEnded() {
        if phase.activeStep != nil { phase = .idle }
    }

    /// Stop or Take over: nothing is planned, shown or running any more.
    func ended() {
        pending.cancel()
        phase = .idle
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct AskedStep {
        // ENFORCED AT DECODE: the guided decoder can only write a word from these lists, and the
        // kit reads every word again before anything runs.
        @Guide(description: "One action from the listed actions.", .anyOf(DuckDecider.actionWords))
        var action: String
        @Guide(description: "The direction for walk or turn, otherwise none.", .anyOf(DuckDecider.directionWords))
        var direction: String
        @Guide(description: "Seconds for walk or turn, 1 to 5. 0 for any other action.")
        var seconds: Double
        @Guide(description: "The skill or sound name for skill or sound, otherwise none.", .anyOf(DuckDecider.nameWords))
        var name: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct AskedPlan {
        @Guide(description: "One to six steps, in the order the duck should do them.")
        var steps: [AskedStep]
    }
#endif
}
