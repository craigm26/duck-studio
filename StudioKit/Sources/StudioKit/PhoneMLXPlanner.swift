import Foundation

/// Runs a downloaded model in this process and returns its text. The app's `PhoneModelRuntime`
/// is the real one; tests pass a stub, so everything a planner does with the text is held on
/// Linux.
public protocol PhoneModelRunning: Sendable {
    /// One answer from `repository`'s weights, given within `deadline` seconds or thrown.
    func respond(repository: String, instructions: String, prompt: String,
                 deadline: TimeInterval) async throws -> String
}

/// A planner backed by MLX weights downloaded to this phone (`ModelEndpoint.Kind.downloadedMLX`,
/// brains-layer.md 4: "MLX `PhoneModelRuntime`, closed set; text parsed and validated").
///
/// NO GRAMMAR ON THE PHONE. The in-process runtime cannot constrain decoding to a schema, so the
/// model is shown the closed set as a short list of example answers (`LocalDecisionPrompt`) and
/// its text is read strictly. Anything outside the set becomes `.ask`. Nothing leaves the phone.
public struct PhoneMLXPlanner: Planner {
    public let info: PlannerInfo
    public let repository: String
    public let version: LocalModelVersion
    let runner: any PhoneModelRunning

    /// The longest an on-phone decision may take. The plan's budget is "under 5 s, labelled
    /// slower". The first device runs managed under a token a second on a 0.6B, so this is twice
    /// the budget until a bench row says what a phone really does. Craig to confirm.
    public static let decisionDeadline: Duration = .seconds(10)

    public init(repository: String, version: LocalModelVersion, runner: any PhoneModelRunning,
                evidence: EvidenceRow? = nil, terms: TermsRow? = nil,
                deadline: Duration = PhoneMLXPlanner.decisionDeadline) {
        self.repository = repository
        self.version = version
        self.runner = runner
        self.info = PlannerInfo(
            id: LocalPlannerWords.providerId(transport: .thisDevice, model: repository),
            modelVersion: KeyScrub.scrub(version.string),
            label: LocalPlannerWords.label(.thisDevice),
            runsOn: .thisPhone, key: .none, trainedOn: [], decisionDeadline: deadline,
            framesSent: .none, evidence: evidence, terms: terms, realDuck: .off)
    }

    /// The planner for a stored endpoint of the downloaded kind.
    public init(endpoint: ModelEndpoint, version: LocalModelVersion, runner: any PhoneModelRunning,
                evidence: EvidenceRow? = nil, terms: TermsRow? = nil) throws {
        guard endpoint.kind == .downloadedMLX else { throw ModelEndpoint.Refusal.notARepository(endpoint.model) }
        try endpoint.validate()
        self.init(repository: endpoint.model.trimmingCharacters(in: .whitespaces), version: version,
                  runner: runner, evidence: evidence, terms: terms)
    }

    public func decide(_ ask: PlannerAsk) async throws -> Decided {
        try await decideWithReading(ask).decided
    }

    /// One decision and how it was read, for the bench.
    public func decideWithReading(_ ask: PlannerAsk) async throws -> (decided: Decided, refusal: AllowedDecisions.Refusal?) {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = info.decisionDeadline
        let seconds = Double(deadline.components.seconds) + Double(deadline.components.attoseconds) / 1e18
        let instructions = LocalDecisionPrompt.instructions(for: ask.allowed)
        let prompt = LocalDecisionPrompt.userText(ask)
        let (repository, runner) = (self.repository, self.runner)
        let text: String
        do {
            text = try await LocalDeadline.run(deadline) {
                try await runner.respond(repository: repository, instructions: instructions,
                                         prompt: prompt, deadline: seconds)
            }
        } catch let e as LocalPlannerError {
            throw e
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalPlannerError.runnerFailed(KeyScrub.scrub(String(String(describing: error).prefix(200))))
        }
        let reading = try LocalDecisionPrompt.read(reply: text, allowed: ask.allowed)
        let decided = Decided(decision: reading.decision, why: reading.why, provider: info, latency: clock.now - start)
        return (decided, reading.refusal)
    }
}
