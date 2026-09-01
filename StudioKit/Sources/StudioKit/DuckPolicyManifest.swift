import Foundation
import DuckKit

/// The `manifest.json` a self-published Microduck policy carries.
///
/// A CONVENTION THIS PROJECT DID NOT INVENT AND SHOULD NOT FORK. People are
/// already publishing policies to the Hub with it — `joanfox/microduck-happy-hop`
/// is the one this was read from — as a MODEL repository tagged
/// `microduck-policy`, with `policy.onnx` and `manifest.json` at the root and a
/// preview video beside them. This app had no idea any of that existed: it
/// could import the `.onnx` and nothing else, which meant throwing away
/// everything the author took the trouble to write down.
///
/// THE FIELD THAT MATTERS MOST IS `action_scale`, AND GUESSING IT IS A REAL
/// BUG. `robotd` multiplies a policy's output by a scale before it reaches the
/// servos, and the scale is per-network: 0.9 for walking and the kicks, 1.0 for
/// standing, sit/stand, ground pick and roulade. With no manifest this app
/// picks the scale by matching the FILE NAME against the seven policies Pollen
/// ship — so a community policy matches nothing and silently gets walking's
/// 0.9. `happy-hop` declares 1.0. Showing it at 0.9 is the same error
/// `BenchView` already documents for roulade: "targets 10% short of what the
/// robot would actually be sent".
///
/// IT IS ALSO WHERE THE HONESTY LIVES. `status` and `eval.known_limits` are the
/// author telling you what they did not test — happy-hop says "never tested on
/// hardware" and calls itself `sim-only-hardware-candidate` — and this app's
/// whole argument is that those sentences belong on the screen rather than in a
/// README nobody opens after the download.
public struct DuckPolicyManifest: Equatable, Sendable {

    /// The Hub tag a policy repository carries, and what to search for.
    public static let hubTag = "microduck-policy"

    /// The manifest schema this reader was written against.
    public static let schemaVersion = 2
    /// The robot API generation the manifest declares itself against.
    public static let modelAPI = 1

    /// Where the file sits in a policy repository. AT THE ROOT, unlike the
    /// motion manifests this app publishes, which live at `meta/manifest.json`
    /// to stay out of Pollen's `*.json` move glob. A model repository has no
    /// such glob and the community convention puts it at the top.
    public static let path = "manifest.json"

    public let schemaVersion: Int
    public let modelAPI: Int?
    public let name: String
    /// "episodic" for a one-shot move, or a continuous controller.
    public let kind: String?
    public let obsLength: Int
    public let actionLength: Int
    /// What `robotd` multiplies the network's output by. THE REASON TO READ
    /// THIS FILE AT ALL — see the type's own doc.
    public let actionScale: Double?
    /// The posture the policy expects to be handed. happy-hop needs a stable
    /// stand and says it "was not trained to take off directly from an active
    /// walking stride".
    public let entryPose: String?
    /// How long one shot lasts.
    public let durationSeconds: Double?
    /// The author's own word on how far this has been taken —
    /// `sim-only-hardware-candidate` and so on. Free text on purpose: a fixed
    /// enum would force somebody else's honesty into this app's categories.
    public let status: String?
    public let summary: String?
    /// What the author says has NOT been established.
    public let knownLimits: String?
    /// Digest of the artifact the manifest was written about.
    public let sourceDigest: String?
    /// Low-pass coefficients the runtime must use for a matched test. A policy
    /// trained unfiltered needs these at 1.0 — pass-through — and running it
    /// under the daemon's defaults is a different experiment.
    public let headLowpass: Double?
    public let legsLowpass: Double?
    /// Relative path to a preview video, if the repository ships one.
    public let previewPath: String?
    /// Where the weights came from.
    public let trainingRepo: String?
    public let trainingTask: String?
    public let upstreamBase: String?

    public init(schemaVersion: Int, modelAPI: Int?, name: String, kind: String?,
                obsLength: Int, actionLength: Int, actionScale: Double?,
                entryPose: String?, durationSeconds: Double?, status: String?,
                summary: String?, knownLimits: String?, sourceDigest: String?,
                headLowpass: Double?, legsLowpass: Double?, previewPath: String?,
                trainingRepo: String?, trainingTask: String?, upstreamBase: String?) {
        self.schemaVersion = schemaVersion; self.modelAPI = modelAPI
        self.name = name; self.kind = kind
        self.obsLength = obsLength; self.actionLength = actionLength
        self.actionScale = actionScale; self.entryPose = entryPose
        self.durationSeconds = durationSeconds; self.status = status
        self.summary = summary; self.knownLimits = knownLimits
        self.sourceDigest = sourceDigest
        self.headLowpass = headLowpass; self.legsLowpass = legsLowpass
        self.previewPath = previewPath
        self.trainingRepo = trainingRepo; self.trainingTask = trainingTask
        self.upstreamBase = upstreamBase
    }

    public enum ReadError: Error, Equatable {
        case notJSON
        case missing(String)

        public var message: String {
            switch self {
            case .notJSON: return "That manifest is not JSON."
            case .missing(let field):
                return "That manifest has no \(field), so it does not describe a policy."
            }
        }
    }

    public static func read(_ data: Data) throws -> DuckPolicyManifest {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        func int(_ key: String) throws -> Int {
            guard let v = top[key] as? Int else { throw ReadError.missing(key) }
            return v
        }
        let training = top["training"] as? [String: Any] ?? [:]
        let eval = top["eval"] as? [String: Any] ?? [:]
        let deployment = top["deployment"] as? [String: Any] ?? [:]
        let lowpass = deployment["runtime_lowpass_pass_through"] as? [String: Any] ?? [:]
        let media = top["media"] as? [String: Any] ?? [:]
        return DuckPolicyManifest(
            schemaVersion: top["schema_version"] as? Int ?? 0,
            modelAPI: top["model_api"] as? Int,
            name: top["name"] as? String ?? "",
            kind: top["kind"] as? String,
            obsLength: try int("obs_len"),
            actionLength: try int("action_len"),
            actionScale: top["action_scale"] as? Double,
            entryPose: top["entry_pose"] as? String,
            durationSeconds: top["duration_s"] as? Double,
            status: top["status"] as? String,
            summary: top["description"] as? String,
            knownLimits: eval["known_limits"] as? String,
            sourceDigest: top["source_artifact_sha256"] as? String,
            headLowpass: lowpass["head_lowpass"] as? Double,
            legsLowpass: lowpass["legs_lowpass"] as? Double,
            previewPath: media["preview"] as? String,
            trainingRepo: training["repo"] as? String,
            trainingTask: training["task_id"] as? String,
            upstreamBase: training["upstream_base"] as? String)
    }

    // MARK: - what it lets this app stop guessing

    /// Whether the widths match what this app and `robotd` both require.
    ///
    /// A MANIFEST CAN BE WRONG ABOUT ITS OWN FILE, which is why this is a
    /// question and not an assumption. The weights are the truth; this is the
    /// author's claim about them, and `PolicyReport` reads the actual graph.
    /// When the two disagree, the disagreement is the finding.
    public var claimsTheRightShape: Bool {
        obsLength == DuckObservation.length && actionLength == DuckModel.policyJointCount
    }

    /// What to say when the manifest's claimed widths are not this robot's.
    public var shapeComplaint: String? {
        guard !claimsTheRightShape else { return nil }
        return "This manifest describes a \(obsLength) → \(actionLength) network. A Microduck "
             + "policy is \(DuckObservation.length) → \(DuckModel.policyJointCount). Pollen's own "
             + "runtime checks that at load rather than discovering it mid-stride, and so does "
             + "this app."
    }

    /// Whether the runtime must be told to pass actions through unfiltered.
    ///
    /// happy-hop was "trained unfiltered, following the `microduck_rl/AGENTS.md`
    /// invariant" and says a matched runtime test needs both low-passes at 1.0.
    /// A policy run under the daemon's smoothing defaults when it asked for
    /// pass-through is a different experiment from the one its author ran, and
    /// silence about that is how a policy gets blamed for a filter.
    public var wantsUnfilteredActions: Bool {
        headLowpass == 1.0 && legsLowpass == 1.0
    }

    /// The scale to run this policy at, and where the number came from.
    ///
    /// - Parameter fallback: what the app would have guessed on its own.
    public func scale(orGuessed fallback: Double) -> (value: Double, fromManifest: Bool) {
        guard let actionScale else { return (fallback, false) }
        return (actionScale, true)
    }

    /// The action scale as a row, and what it would have been without this file.
    ///
    /// COMPOSED HERE BECAUSE IT IS A CLAIM ABOUT THE ROBOT. The app-target gate
    /// caught `manifest.actionScale` being read in a view and was right to: the
    /// interesting part is not the number but the COMPARISON — a community
    /// policy that declares 1.0 where this app would have guessed
    /// `DuckModel.actionScale` is a policy that would have been driven 10%
    /// short, and saying so is the whole reason to read a manifest.
    public var scaleLine: (title: String, value: String)? {
        guard let actionScale else { return nil }
        let guess = DuckModel.actionScale
        let value = String(format: "%g", actionScale)
        guard actionScale != guess else { return ("Action scale", value) }
        return ("Action scale",
                value + String(format: " — this app would have guessed %g", guess))
    }

    /// The sentence to put under a policy that came with one of these.
    ///
    /// THE AUTHOR'S OWN CAVEATS, VERBATIM AND FIRST. This app spends its whole
    /// surface refusing to overstate what a network does; when the person who
    /// trained it has already written down what they did not test, quoting them
    /// beats anything this app could infer from the weights.
    public var honesty: String {
        var lines: [String] = []
        if let status { lines.append("Status the author gave it: \(status).") }
        if let knownLimits { lines.append("Their words on what is not established: \(knownLimits)") }
        if let entryPose {
            lines.append("It expects to be handed a \(entryPose) robot; starting it from anything "
                       + "else is outside what was trained.")
        }
        if wantsUnfilteredActions {
            lines.append("It was trained unfiltered and asks for the runtime low-pass to be "
                       + "pass-through. Run under the daemon's smoothing defaults, it is not the "
                       + "policy its author measured.")
        }
        if lines.isEmpty {
            return "The manifest records no status and no known limits, so there is nothing here "
                 + "the author has said about what they did not test."
        }
        return lines.joined(separator: "\n\n")
    }
}
