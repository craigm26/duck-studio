import Foundation

// MARK: - who a brain is

/// Where a brain runs. `.thisPhone` is the only place that keeps everything on the device.
public enum RunsOn: Equatable, Hashable, Sendable, Codable {
    case thisPhone
    /// The duck's own computer (the bridge host).
    case robotComputer
    /// A machine on the person's network, such as a Mac running Ollama.
    case lanComputer
    /// A vendor's service, by name.
    case hosted(vendor: String)
}

/// What key a brain needs.
public enum KeyNeed: Equatable, Hashable, Sendable, Codable {
    case none
    /// The person's own key for this provider, kept in this device's Keychain.
    case byok(provider: String)
    /// A key held on the duck's computer.
    case onBridge
}

/// Where a brain was measured or may run. The practice duck is the simulated one.
public enum BrainVenue: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    case practice, real

    public init(_ kind: DuckIdentity.Kind) { self = kind == .real ? .real : .practice }
}

/// The two modes a brain can be offered in. Drive is the stick and never has a brain.
public enum BrainMode: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    case tell, auto
}

/// What camera frames leave the device, and how often. The card states it (section 4).
public enum FramePolicy: Equatable, Hashable, Sendable, Codable {
    case none
    /// A window of `frames` pictures about every `everySeconds`, e.g. Dream-1's 9 every 2 s.
    case window(frames: Int, everySeconds: Double)
}

/// The fields every brain's card is built from. `OfferRule` reads only these.
public protocol BrainCard: Sendable {
    /// "phone.ducknet-s1", "dreamlabs.dream-1", "byok.anthropic"
    var id: String { get }
    /// A checkpoint hash or the vendor's model id. Pins the evidence row.
    var modelVersion: String { get }
    /// "Dream-1 + assist" only when the assist is on and its row exists.
    var label: String { get }
    var runsOn: RunsOn { get }
    var key: KeyNeed { get }
    var trainedOn: Set<BrainVenue> { get }
    /// Nil means not offered (section 7).
    var evidence: EvidenceRow? { get }
    /// Nil means not offered (section 7).
    var terms: TermsRow? { get }
    /// Whether it may run on a real duck. Off until a tester's run says otherwise.
    var realDuck: RealDuckRow { get }
}

/// An action source: something that hands back chunks of twists (3.1).
public struct ActionSourceInfo: BrainCard, Equatable, Hashable, Codable {
    public let id: String
    public let modelVersion: String
    public let label: String
    public let runsOn: RunsOn
    public let key: KeyNeed
    public let trainedOn: Set<BrainVenue>
    /// A chunk later than this is refused and the duck holds still. It is never replayed.
    public let chunkDeadline: Duration
    public let framesSent: FramePolicy
    public let evidence: EvidenceRow?
    public let terms: TermsRow?
    public let realDuck: RealDuckRow

    public init(id: String, modelVersion: String, label: String, runsOn: RunsOn, key: KeyNeed,
                trainedOn: Set<BrainVenue>, chunkDeadline: Duration, framesSent: FramePolicy,
                evidence: EvidenceRow? = nil, terms: TermsRow? = nil, realDuck: RealDuckRow = .off) {
        self.id = id
        self.modelVersion = modelVersion
        self.label = label
        self.runsOn = runsOn
        self.key = key
        self.trainedOn = trainedOn
        self.chunkDeadline = chunkDeadline
        self.framesSent = framesSent
        self.evidence = evidence
        self.terms = terms
        self.realDuck = realDuck
    }
}

/// A planner: something that picks one `DuckDecision` (3.2). The same fields as an action
/// source, with a decision deadline in place of a chunk deadline.
public struct PlannerInfo: BrainCard, Equatable, Hashable, Codable {
    public let id: String
    public let modelVersion: String
    public let label: String
    public let runsOn: RunsOn
    public let key: KeyNeed
    public let trainedOn: Set<BrainVenue>
    /// A decision later than this is dropped and the duck holds still.
    public let decisionDeadline: Duration
    public let framesSent: FramePolicy
    public let evidence: EvidenceRow?
    public let terms: TermsRow?
    public let realDuck: RealDuckRow

    public init(id: String, modelVersion: String, label: String, runsOn: RunsOn, key: KeyNeed,
                trainedOn: Set<BrainVenue> = [], decisionDeadline: Duration, framesSent: FramePolicy = .none,
                evidence: EvidenceRow? = nil, terms: TermsRow? = nil, realDuck: RealDuckRow = .off) {
        self.id = id
        self.modelVersion = modelVersion
        self.label = label
        self.runsOn = runsOn
        self.key = key
        self.trainedOn = trainedOn
        self.decisionDeadline = decisionDeadline
        self.framesSent = framesSent
        self.evidence = evidence
        self.terms = terms
        self.realDuck = realDuck
    }

    /// The deterministic reader that runs first on Tell. No model, no key, nothing leaves.
    public static let duckTalk = PlannerInfo(
        id: "phone.ducktalk", modelVersion: "ducktalk-1", label: "Understood on this phone",
        runsOn: .thisPhone, key: .none, decisionDeadline: .milliseconds(50))
}

/// An action source with its descriptor. `DreamRows` itself does not change, so its three
/// conformers do not either; a source opts in by adding `info`.
public protocol ActionSource: DreamRows {
    var info: ActionSourceInfo { get }
}
