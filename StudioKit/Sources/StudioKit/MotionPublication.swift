import Foundation
import DuckKit

/// What Duck Studio publishes, and what its card has to admit.
///
/// A MOTION IS NOT A POLICY, AND THE REPOSITORY SAYS SO. Pollen's sharing
/// format describes a trained network: an observation width, an action width,
/// what each command slot means. This app trains nothing — it authors
/// keyframes and records what a policy did — so publishing under
/// `microduck-policy` with an invented `obs_len` would be a lie that an
/// importer would then act on. The manifest declares `artifact: "motion"`, the
/// tag is `microduck-motion`, and `PolicyManifest` refuses it by name.
///
/// THE CARD LEADS WITH WHAT IS NOT TRUE OF IT. An authored motion is a
/// request, not a result: the same keyframes fed through a standing policy on
/// the real robot come out shallower — measured at 40-60% of the authored
/// depth for a crouch, because the policy resists leg offsets it did not ask
/// for. Somebody downloading this needs that before they need anything else.
public struct MotionPublication: Equatable, Sendable {

    public let name: String
    public let files: [HuggingFacePublish.File]
    public let summary: String

    public var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }

    /// Everything the author is told to expect, in the card and the manifest.
    public static func cautions(for draft: IntentDraft) -> [String] {
        var out = [
            "Authored keyframes are a request, not a result: driven through a policy on the "
          + "robot, leg offsets come out shallower than authored — measured at 40-60% of the "
          + "authored depth for a crouch.",
            "Never run on hardware. Everything here was authored and previewed in simulation.",
            "The joint order in the file IS the contract. A file whose joints are in another "
          + "order is a plausible-looking motion for a different robot.",
        ]
        // The editor's own verdicts travel with it rather than being left
        // behind on the machine that made it.
        out.append(contentsOf: draft.problems
            .filter { $0.severity != .broken }
            .map { $0.text })
        return out
    }

    public init(draft: IntentDraft, note: String? = nil) throws {
        name = draft.name
        let move = try draft.exported()
        let manifest = Self.manifest(for: draft, note: note)
        let card = Self.card(for: draft, note: note)
        files = [
            .init(path: "motion.duckmove", contents: move, isText: true),
            .init(path: "manifest.json", contents: manifest, isText: true),
            .init(path: "README.md", contents: Data(card.utf8), isText: true),
        ]
        summary = "Add \(draft.name) — a Microduck motion authored in Duck Studio"
    }

    static func manifest(for draft: IntentDraft, note: String?) -> Data {
        let body: [String: Any] = [
            "schema_version": 1,
            // The field an importer reads FIRST. Without it a motion and a
            // policy are both "a file in a microduck repository".
            "artifact": "motion",
            "name": draft.name,
            "authored_in": "Duck Studio",
            "robot": ["model": "microduck", "hw_rev": 1,
                      "servos": "xl330", "control_hz": DuckModel.tickHz],
            "motion": [
                "format": DuckMoveFile.format,
                "joints": DuckModel.jointNames,
                "keyframes": draft.keys.count,
                "duration_s": draft.duration,
            ],
            "provenance": [
                "how": draft.provenance,
                "note": note ?? "",
            ],
            "cautions": cautions(for: draft),
        ]
        return (try? JSONSerialization.data(withJSONObject: body,
                                            options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    static func card(for draft: IntentDraft, note: String?) -> String {
        let cautionLines = cautions(for: draft).map { "- \($0)" }.joined(separator: "\n")
        let keyLines = draft.keys.enumerated().map { index, key in
            String(format: "| %d | %.2f s |", index + 1, key.time)
        }.joined(separator: "\n")
        return """
        ---
        library_name: duckkit
        tags: [microduck, microduck-motion, robotics]
        license: apache-2.0
        ---

        # \(draft.name)

        A motion for the Pollen Robotics [Microduck](https://github.com/pollen-robotics/microduck), \
        authored in Duck Studio. \(note ?? "")

        **This is a motion, not a policy.** It is a list of poses with times — \
        `\(DuckMoveFile.format)` — not a trained network. There is no observation, no action \
        space and no command block: you play it, you do not drive it.

        ## What is in it

        | | |
        |---|---|
        | Keyframes | \(draft.keys.count) |
        | Duration | \(String(format: "%.2f s", draft.duration)) |
        | Joints | \(DuckModel.jointCount), in the wire order below |
        | Rate | \(Int(DuckModel.tickHz)) Hz |

        Joint order — **this is the contract**:

        `\(DuckModel.jointNames.joined(separator: ", "))`

        ### Keyframes

        | # | at |
        |---|---|
        \(keyLines)

        ## Before you use it

        \(cautionLines)

        ## How it was made

        \(draft.provenance)

        ## Files

        - `motion.duckmove` — the motion, in the format DuckKit reads and writes
        - `manifest.json` — the same facts, machine-readable
        - `README.md` — this card
        """
    }
}
