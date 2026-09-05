import Foundation

/// The thing being evaluated, and the spec strip that travels with it.
///
/// `policy_config` IS WHERE THE HONESTY LIVES, and that is a measured decision
/// rather than a preference. `inspect-robots view` renders every key of
/// `policy_config` as a sorted definition list and renders `embodiment_info`
/// only through `default_fps`. So a sentence a stranger has to read before they
/// can trust a number goes in `policy_config`, and a machine fact a program
/// reads goes in `embodiment_info`. The cost is admitted: eleven definition
/// rows is a tall strip on their page. The alternative is the caveat living
/// where nobody looks, which is the failure `Provenance.swift` was written
/// about.
///
/// Three of the eleven, `action_horizon`, `replan_interval` and `temperature`,
/// are their own `PolicyConfig` fields, so a log from this app has the shape
/// their reference log has. `action_horizon: 1` is literally true: the bench
/// asks the network for an action every control tick.
public struct EvalPolicy: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable, CaseIterable {
        /// A network from the library, by digest.
        case libraryNetwork
        /// A candidate the tuner or the weight search produced.
        case tunedCandidate
        /// A move authored in the app, scored through a challenge grid.
        case authoredMotion
        /// An entrant already published to a challenge.
        case challengeEntrant

        public var said: String {
            switch self {
            case .libraryNetwork: return "A network from your library"
            case .tunedCandidate: return "A candidate from a search on this phone"
            case .authoredMotion: return "A move authored in this app"
            case .challengeEntrant: return "An entrant from a published challenge"
            }
        }
    }

    public let kind: Kind
    /// What a PERSON calls it, which is never what the log calls it and never
    /// what the bench matches on. The repository's rule, enforced by
    /// `scripts/check_no_policy_name_keys.sh`: a name is either the file's or
    /// the person's, and every site says which. `benchPolicyName` below is the
    /// file's.
    public let title: String
    /// How this app knows one network from another. Nil for a move, which is
    /// identified by its own hash rather than by parameters.
    public let identity: PolicyLibrary.Identity?
    /// The name the bench knows it by, which is what goes on the wire.
    public let benchPolicyName: String
    /// Whether the gains are all 1 and the trims are all 0.
    public let residualIsIdentity: Bool

    public init(kind: Kind, title: String, identity: PolicyLibrary.Identity?,
                benchPolicyName: String, residualIsIdentity: Bool) {
        self.kind = kind
        self.title = title
        self.identity = identity
        self.benchPolicyName = benchPolicyName
        self.residualIsIdentity = residualIsIdentity
    }

    /// `eval.policy`: `alpha_walking.onnx@27b1f53d1f26`.
    ///
    /// THE DIGEST IS IN THE NAME FOR THE SAME REASON THE PLANT DIGEST IS IN THE
    /// EMBODIMENT. Two files can carry the same filename and be different
    /// networks, and a person comparing two logs by their `policy` field would
    /// never find out. Twelve characters, which is what every other digest in
    /// this app is shown at.
    public var logName: String {
        guard let identity else { return benchPolicyName }
        return "\(benchPolicyName)@\(identity.value.prefix(DuckBench.digestShown))"
    }

    /// Whether `/tune` will take it at all. The bench folds a gain into the
    /// last layer, which means holding the parameters, and it cannot produce
    /// them for a file it could not load.
    public var isNetworkIdentity: Bool { identity?.isNetworkIdentity ?? false }

    // MARK: - the spec strip

    /// The eleven keys their viewer renders, plus two that appear only when
    /// there is something to say.
    ///
    /// `criterion` and `bench_host` are NOT authored here. The criterion is the
    /// bench's own sentence, carried verbatim, which is why an evaluation log
    /// can contain characters this repository's own copy rules forbid: a
    /// measurement quoted exactly is not this app's prose. `bench_host` is
    /// `PhoneBenchReport.ranOn`, which this app already owns and which is not
    /// going to be reworded here.
    /// `tracing` IS THE TASK'S OWN ANSWER AND NOT A GUESS FROM THE EPOCHS.
    /// Only `/tune` returns a trajectory, so on a grid the trace sentence and
    /// the step count sentence both describe a mechanism the run never used:
    /// a log that carried them would say an episode was recorded and a verdict
    /// offered on it beside fourteen cells where `traced` is false on every
    /// trial and `total_steps` is zero.
    public func config(embodiment: EvalEmbodiment, epochs: EvalEpochs,
                       criterion: String, tracing: Bool,
                       refusedTerms: [(name: String, why: String)] = []) -> [String: EvalLogJSON] {
        var config: [String: EvalLogJSON] = [
            "action_horizon": .integer(1),
            "bench_host": .string(embodiment.hostSaid),
            "bench_world": .string(embodiment.plantSaid),
            "criterion": .string(criterion),
            "epoch_axis": .string(epochs.said),
            "replan_interval": .null,
            "residual": .string(residualSaid),
            "seed_note": .string(epochs.seedNote),
            "step_counts": .string(tracing ? EvalRun.stepCountsSaid
                                           : EvalRun.noStepsOnAGridSaid),
            "temperature": .null,
            "trace_note": .string(tracing ? EvalTrace.firstDropOnlySaid
                                          : EvalTrace.noTraceOnAGridSaid),
        ]
        if case .fileOnly = identity { config["identity_note"] = .string(Self.fileOnlySaid) }
        if !refusedTerms.isEmpty {
            let listed = refusedTerms.map { "\($0.name): \($0.why)" }.joined(separator: " ")
            config["refused_terms"] = .string(listed)
        }
        return config
    }

    /// What was folded in for THIS run, and what the file already was.
    ///
    /// A CANDIDATE'S FILE IS ALREADY A FOLD, which is the half the identity
    /// sentence used to get wrong. The tuner and the weight search save their
    /// winner by folding a per joint gain and trim into the last layer, so a
    /// run of one of those with an identity residual has folded nothing in
    /// today and is still not running the network as it was trained. Saying
    /// otherwise put a claim about somebody else's training in a log about this
    /// phone's arithmetic.
    public var residualSaid: String {
        guard residualIsIdentity else { return Self.foldedResidualSaid }
        return kind == .tunedCandidate ? Self.identityOverACandidateSaid
                                       : Self.identityResidualSaid
    }

    // MARK: - the sentences

    public static let identityResidualSaid =
        "Identity. The gains are all 1 and the trims are all 0, so the network the bench ran is "
      + "the network as it was trained."

    public static let identityOverACandidateSaid =
        "Identity. Nothing was folded in for this run, and the file itself is a candidate this "
      + "phone folded a gain and a trim into earlier, so what the bench ran is not the network "
      + "the base file was trained as."

    /// A2: the policy's own digest, said where a person is looking at the
    /// policy rather than at the world.
    ///
    /// IT IS NOT `EvalEmbodiment.digestIsIdentitySaid`. That one is about the
    /// plant's sha256 being inside the embodiment's name; this one is about the
    /// parameters' digest being inside the policy's. A row that borrowed the
    /// other sentence would tell a person the hex they are looking at is the
    /// world's.
    public static let digestIsIdentitySaid =
        "The characters after the file name are the digest of the network's parameters. Two "
      + "files can carry one name and be two different networks, and the digest is what tells "
      + "them apart."

    /// `logName` for a screen reader: the name, the word digest, then the hex,
    /// because a run of twelve characters read as a word is not a digest a
    /// person can check.
    public var spokenLogName: String {
        guard let identity else { return benchPolicyName }
        return "\(benchPolicyName), digest \(identity.value.prefix(DuckBench.digestShown))"
    }

    public static let foldedResidualSaid =
        "A per joint gain and trim were folded into the last layer before the run, so the "
      + "network the bench ran is not the one the file was trained as. The fold is arithmetic on "
      + "parameters and nothing was learned."

    /// Under the policy picker, because the bench refuses by name before any
    /// physics and a Start button that dead ends on that error is a failure
    /// this project has already paid for.
    public static let canonicalParametersSaid =
        "This route folds a gain into the last layer, which means holding the network's "
      + "parameters, so it only takes a file this app could load and digest. A file that would "
      + "not open has no parameters to fold, and the bench says so rather than guessing."

    public static let fileOnlySaid =
        "This policy is identified by the digest of its file rather than of its parameters, "
      + "because the file would not load here. Two files with different bytes and the same "
      + "network would look like two policies."
}
