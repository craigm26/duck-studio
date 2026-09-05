import Foundation
import DuckKit

/// What ran the policy: a body, a world, and the digest of the bytes that world
/// was compiled from.
///
/// THE DIGEST IS INSIDE THE IDENTITY AND NOT BESIDE IT. `eval.embodiment` is
/// one string, and it is the string a person compares two logs by. If the plant
/// digest sat next to it in `embodiment_info` instead, two runs against two
/// different worlds would show the same embodiment on their report and on ours,
/// and the whole point of this app's existing plant sentences would be undone
/// by a schema decision. So the identity reads
/// `network-bench/duck-bench-5/scene.mjb@3f8c9ab9b409`, and a bench that will
/// not say which bytes it is running cannot be evaluated at all.
///
/// `capabilities` is drawn only from the six words `embodiment.py` defines, and
/// `seedable` is never one of them: see `notSeedable`.
public struct EvalEmbodiment: Equatable, Sendable {

    /// The three bodies this app can name today. Two of them can run something.
    public enum Body: String, Equatable, Sendable, CaseIterable {
        case networkBench
        case thisPhoneBench
        case realMicroduck

        /// The first component of the identity string, so the machine that ran
        /// it is inside the value two logs are compared by. A phone bench
        /// number and a desk bench number are not the same trajectory, and the
        /// identity has to say so on its own.
        public var slug: String {
            switch self {
            case .networkBench: return "network-bench"
            case .thisPhoneBench: return "this-phone-bench"
            case .realMicroduck: return "real-microduck"
            }
        }

        public var said: String {
            switch self {
            case .networkBench: return "A bench on your network"
            case .thisPhoneBench: return "This phone's own bench"
            case .realMicroduck: return "A real Microduck"
            }
        }
    }

    public let body: Body
    /// The bench's own word for itself, `duck-bench/5`.
    public let bench: String?
    /// Host and port, for a reader who wants to know where the number came
    /// from. Never branched on.
    public let address: String?
    public let plantName: String?
    public let plantDigest: String?
    public let tickHz: Double
    public let host: DuckBench.Health.Host?
    /// What `/health` said this bench answers, so a task can be refused before
    /// a Start button rather than after a spinner.
    public let answeredRoutes: Set<String>
    /// Why this one cannot be used, or nil. A real Microduck always has one.
    public let refusal: String?

    public var isUsable: Bool { refusal == nil }

    init(body: Body, bench: String?, address: String?, plantName: String?, plantDigest: String?,
         tickHz: Double, host: DuckBench.Health.Host?, answeredRoutes: Set<String>,
         refusal: String?) {
        self.body = body
        self.bench = bench
        self.address = address
        self.plantName = plantName
        self.plantDigest = plantDigest
        self.tickHz = tickHz
        self.host = host
        self.answeredRoutes = answeredRoutes
        self.refusal = refusal
    }

    // MARK: - building one

    public enum Refusal: Error, Equatable {
        case noDigest
        case realMicroduck

        public var message: String {
            switch self {
            case .noDigest: return EvalEmbodiment.noDigestRefusal
            case .realMicroduck: return EvalEmbodiment.realMicroduckRefusal
            }
        }
    }

    /// A bench that answered `/health`, checked before anything is run.
    ///
    /// The digest test is here rather than at the writer, because a run that
    /// gets as far as producing a log has already spent the minutes. A bench
    /// that will not name its world is refused in front of the Start button.
    /// `answeredRoutes` is passed in rather than read off `Health`, because
    /// `/health` does not list routes: what a bench answers is learned by
    /// asking, and the caller is the half that has asked.
    public static func checked(body: Body, health: DuckBench.Health, address: String?,
                               answeredRoutes: Set<String>) throws -> EvalEmbodiment {
        guard body != .realMicroduck else { throw Refusal.realMicroduck }
        guard let digest = health.plantDigest, !digest.isEmpty,
              let name = health.plantName, !name.isEmpty else {
            throw Refusal.noDigest
        }
        return EvalEmbodiment(body: body, bench: health.bench, address: address,
                              plantName: name, plantDigest: digest,
                              tickHz: health.tickHz, host: health.host,
                              answeredRoutes: answeredRoutes, refusal: nil)
    }

    /// The one that always refuses, so a screen can draw it disabled with the
    /// reason under the name rather than hide it and leave a person wondering.
    public static let realMicroduck = EvalEmbodiment(
        body: .realMicroduck, bench: nil, address: nil, plantName: nil, plantDigest: nil,
        tickHz: DuckModel.tickHz, host: nil, answeredRoutes: [],
        refusal: realMicroduckRefusal)

    // MARK: - identity

    /// `network-bench/duck-bench-5/scene.mjb@3f8c9ab9b409`.
    ///
    /// Every component is something a bench said. The digest is truncated to
    /// the same twelve characters every other digest in this app is shown at
    /// (`DuckBench.digestShown`), and the whole digest is in `embodiment_info`
    /// and on the report, so a reader who needs all sixty-four has them.
    public var identity: String {
        var parts = [body.slug]
        if let bench, !bench.isEmpty { parts.append(bench.replacingOccurrences(of: "/", with: "-")) }
        let world: String
        if let plantName, let plantDigest {
            world = "\(plantName)@\(plantDigest.prefix(DuckBench.digestShown))"
        } else {
            world = "no-world-stated"
        }
        parts.append(world)
        return parts.joined(separator: "/")
    }

    /// Their six capability words, and the five this bench can honestly claim.
    ///
    /// `renderable` DEPENDS ON THE RUN, which is why this is a function. The
    /// bench returns a trajectory only when one was asked for and only for the
    /// first drop of a call, so a run that got none is a run nothing could be
    /// rendered from, and claiming otherwise would be a capability nobody used.
    public func capabilities(traced: Bool) -> [String] {
        var words = ["auto_reset", "privileged_success", "self_paced"]
        if answeredRoutes.contains("/reset") { words.append("resettable") }
        if traced { words.append("renderable") }
        return words.sorted()
    }

    /// The machine facts, for a program. Their viewer reads only `control_hz`
    /// out of this block, so nothing here is written for a person to read: the
    /// sentences all live in `policy_config`, which their viewer does render.
    public func info(traced: Bool) -> [String: EvalLogJSON] {
        var info: [String: EvalLogJSON] = [
            "capabilities": .strings(capabilities(traced: traced)),
            "control_hz": .number(tickHz),
            "is_simulated": .bool(body != .realMicroduck),
        ]
        if let bench { info["bench"] = .string(bench) }
        if let address { info["bench_address"] = .string(address) }
        if let plantName { info["plant_name"] = .string(plantName) }
        if let plantDigest { info["plant_sha256"] = .string(plantDigest) }
        if let millis = host?.tickMillis { info["tick_ms_measured"] = .number(millis) }
        return info
    }

    /// The world sentence this app already owns, reused rather than reworded.
    public var plantSaid: String {
        DuckBench.plantSaid(name: plantName, digest: plantDigest)
    }

    /// Which machine ran it, in the words this app already uses for that.
    public var hostSaid: String { PhoneBenchReport.ranOn(host) }

    // MARK: - before Start

    /// Everything that has to be true before a Start button is allowed to
    /// appear, in one function, returning the sentence to draw under the
    /// control that is wrong.
    ///
    /// WHY IT IS ONE FUNCTION AND NOT FIVE CALL SITES. A setup screen that
    /// checks four of five conditions offers a combination that dead ends on
    /// the bench's own error three minutes later, which is a failure this
    /// project has already paid for once with `/tune` and the phone bench.
    public func refusalBeforeStart(route: String, policyIsNetworkIdentity: Bool,
                                   policyName: String,
                                   bundledPolicyNames: Set<String>) -> String? {
        if let refusal { return refusal }
        if !answeredRoutes.isEmpty, !answeredRoutes.contains(route) {
            return "This bench does not answer \(route), so it cannot run this task."
        }
        if body == .thisPhoneBench, !bundledPolicyNames.contains(policyName) {
            return Self.phoneBenchOnlyBundled
        }
        if !policyIsNetworkIdentity { return EvalPolicy.canonicalParametersSaid }
        return nil
    }

    // MARK: - the sentences

    public static let digestIsIdentitySaid =
        "The world's sha256 is part of what this run is called, not a note beside it. Two "
      + "numbers measured against different worlds are two different measurements, and putting "
      + "the digest inside the name is what stops them being read as one."

    public static let noDigestRefusal =
        "This bench will not say which bytes its world was built from, so nothing measured here "
      + "could be compared with anything measured anywhere else. An evaluation needs a world it "
      + "can name."

    /// L4, on screen, where the absent control would otherwise look like an
    /// oversight.
    public static let notSeedable =
        "There is no seed here, and the log does not claim one. No route on this bench takes a "
      + "seed, so the word seedable is left out of what this embodiment says it can do rather "
      + "than written down and ignored."

    public static let realMicroduckRefusal =
        "Nothing here has run on a real Microduck. This app cannot drive one over Bluetooth, "
      + "and the first ones ship around Christmas 2026, so a real duck is a row that says why "
      + "rather than a row that runs."

    /// B7: the phone bench can only ever score the networks it ships with.
    public static let phoneBenchOnlyBundled =
        "This phone's bench runs canonical parameter bytes rather than an ONNX file, so it can "
      + "only score the networks that ship with the app. Pick one of those, or run this on a "
      + "bench on your network."
}
