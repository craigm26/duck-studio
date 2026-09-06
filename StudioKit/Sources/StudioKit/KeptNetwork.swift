import Foundation
import DuckKit

/// What this app writes down about a network it MADE, at the moment it is kept.
///
/// WHY A KEPT NETWORK HAS TO LAND IN THE LIBRARY. "Keep this network" on the
/// weight-search screen wrote the file to a temporary URL and opened the share
/// sheet, and the tuner's "Save the tuned policy" did the same. Once the sheet
/// closed the app had forgotten the network existed: not on the Behaviours
/// shelf, no manifest, none of the two numbers the screen had just measured,
/// no record of which bench or which base. Sharing is the second step; the
/// first is that the thing exists here, under an origin that says who made it,
/// with a manifest that says how — which is what the Community card reads
/// back when the same file is published, and what a bench upload or a robot
/// install is handed.
///
/// THE MANIFEST IS POLLEN'S FORMAT WITH ONE EXTRA KEY. Everything a reader
/// needs to run the file is in the fields `PolicyManifest.decode` already
/// reads; what this app knows about the making of it goes under `made_here`,
/// which an older reader ignores by construction. The caution is in
/// `cautions`, where the card shows it, because that is the one sentence a
/// stranger has to see before running this on anything.
public enum KeptNetwork {

    /// A weight search, as the screen measured it.
    public struct Search: Equatable, Sendable {
        public let baseTitle: String
        public let baseIdentity: String
        public let generations: Int
        public let pairs: Int
        public let step: Double
        /// `Verdict.gained`: travel under the searched command, as a ratio.
        public let gained: Double
        /// `Verdict.keptElsewhere`: what survived under a command it never saw.
        public let keptElsewhere: Double
        public let plantName: String?
        public let plantDigest: String?
        public let build: String

        public init(baseTitle: String, baseIdentity: String, generations: Int, pairs: Int,
                    step: Double, gained: Double, keptElsewhere: Double,
                    plantName: String?, plantDigest: String?, build: String) {
            self.baseTitle = baseTitle; self.baseIdentity = baseIdentity
            self.generations = generations; self.pairs = pairs; self.step = step
            self.gained = gained; self.keptElsewhere = keptElsewhere
            self.plantName = plantName; self.plantDigest = plantDigest; self.build = build
        }
    }

    /// A tune, as the tuner said it.
    public struct Tune: Equatable, Sendable {
        public let baseTitle: String
        public let verdict: String
        public let residual: String
        public let provenance: String
        public let build: String

        public init(baseTitle: String, verdict: String, residual: String,
                    provenance: String, build: String) {
            self.baseTitle = baseTitle; self.verdict = verdict; self.residual = residual
            self.provenance = provenance; self.build = build
        }
    }

    // MARK: - the sentences

    public static let searchedCaution =
        "Made by a search over this network's weights on a physics bench, not by a trained "
      + "optimiser. Every number behind it is a simulator's, and it has never run on hardware."

    public static let tunedCaution =
        "Made by folding a searched per-joint gain and trim into a finished network on a "
      + "physics bench. Nothing was trained. Every number behind it is a simulator's, and it "
      + "has never run on hardware."

    /// The two buttons under a result, before and after it is kept.
    public static let keepTheTunedSaid = "Keep the tuned policy"
    public static let shareTheFileSaid = "Share the file"

    /// What the screen says once the network is on the shelf.
    public static func keptSaid(_ title: String) -> String {
        "Kept in Behaviours as \(title). Share it, publish it, or put it on a bench from there."
    }

    /// The title a kept network gets, so two searches from the same base do
    /// not answer to one name.
    public static func title(from base: String, how: String, at when: Date) -> String {
        let clock = DateFormatter()
        clock.dateFormat = "MM-dd HH:mm"
        return "\(base), \(how) \(clock.string(from: when))"
    }

    // MARK: - the manifests

    public static func manifest(for search: Search, named name: String,
                                kind: String? = nil) throws -> Data {
        let summary = String(format: "Searched from %@ over %d generations of %d pairs at a "
                                   + "%.0f%% step: %.1f%% further under the command it was "
                                   + "searched against, %.0f%% kept under one it never saw.",
                             search.baseTitle, search.generations, search.pairs,
                             search.step * 100, (search.gained - 1) * 100,
                             search.keptElsewhere * 100)
        var made: [String: Any] = [
            "how": "weight search",
            "base": search.baseTitle,
            "base_sha256": search.baseIdentity,
            "generations": search.generations,
            "pairs": search.pairs,
            "step": search.step,
            "gained": search.gained,
            "kept_elsewhere": search.keptElsewhere,
            "app": "Microduck Studio",
            "build": search.build,
        ]
        if let plant = search.plantName { made["bench_plant"] = plant }
        if let digest = search.plantDigest { made["bench_plant_sha256"] = digest }
        return try PolicyManifest.encode(PolicyManifest.Written(
            name: name, summary: summary, actionScale: nil, kind: kind,
            durationSeconds: nil, entryPose: nil, twist: [], idle: [],
            cautions: [searchedCaution], extra: ["made_here": made]))
    }

    public static func manifest(for tune: Tune, named name: String,
                                kind: String? = nil) throws -> Data {
        let made: [String: Any] = [
            "how": "tune",
            "base": tune.baseTitle,
            "verdict": tune.verdict,
            "residual": tune.residual,
            "provenance": tune.provenance,
            "app": "Microduck Studio",
            "build": tune.build,
        ]
        return try PolicyManifest.encode(PolicyManifest.Written(
            name: name, summary: "Tuned from \(tune.baseTitle). \(tune.verdict)",
            actionScale: nil, kind: kind, durationSeconds: nil, entryPose: nil,
            twist: [], idle: [], cautions: [tunedCaution], extra: ["made_here": made]))
    }
}
