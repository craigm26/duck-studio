import Foundation
import DuckKit

/// What Microduck Studio publishes, and what its card has to admit.
///
/// A MOVE IS A DATASET, NOT A MODEL. This app published motions as model
/// repositories, and that was wrong in a way anyone can check: on the live
/// Hub, `/api/datasets?filter=reachy_mini_community_moves` returns 30+
/// repositories and `/api/models?filter=reachy_mini_community_moves` returns
/// none. Pollen never put a trajectory in a model repo — a trajectory is data,
/// and the Hub sorts data from networks. Publishing as a model put every move
/// this app made in the one place nobody's loader looks.
///
/// A MOTION IS STILL NOT A POLICY, AND THE REPOSITORY SAYS SO. Pollen's
/// sharing format for a network describes an observation width, an action
/// width, what each command slot means. A motion has none of those — it is
/// keyframes and times — so publishing one with an invented `obs_len` would be
/// a lie an importer would then act on. The manifest declares
/// `artifact: "motion"`, and `PolicyManifest` refuses it by name.
///
/// THE SENTENCE THAT USED TO STAND HERE WAS "THIS APP TRAINS NOTHING", AND IT
/// HAS TO BE SAID MORE CAREFULLY NOW. It was written when the only things this
/// app could make were keyframes and recordings, and it was doing two jobs:
/// saying that no network is learned here, and — by implication — saying that
/// no network leaves here. The first is still exactly true and is the more
/// important half. The second stopped being true twice: `PolicyBlend` averages
/// two networks into a third, and `DuckTuner` searches a per-joint gain and
/// trim and folds it into somebody else's last layer. Both produce a valid
/// `.onnx`. Neither computes a gradient, sees a frame of training data, or
/// changes what any network learned.
///
/// So the claim this file makes is `trainsNothing` below, which says the
/// precise thing, and the reason a motion repository carries no `.onnx` is no
/// longer "the app cannot make one" — it is that a motion is not a policy and
/// shipping a network beside one would tell an importer it was.
///
/// THE CARD LEADS WITH WHAT IS NOT TRUE OF IT. An authored motion is a
/// request, not a result: the same keyframes fed through a standing policy
/// come out shallower — measured at 40-60% of the authored depth for a crouch,
/// because the policy resists leg offsets it did not ask for. Somebody
/// downloading this needs that before they need anything else.
///
/// WHERE THAT NUMBER COMES FROM, AND WHERE IT DOES NOT. It was measured in
/// MuJoCo, riding the standing policy, and it is written down in the
/// provenance field of OpenCastor's bundled `Victory bounce.duckmove`:
/// "verified in MuJoCo riding the standing policy: 16 of 16 randomised
/// rollouts end standing, peak joint rate 6.0 rad/s. One honest caveat from
/// the verification: the standing policy resists the leg offsets, so the
/// physical crouch is 40-60% of what was authored". Introduced by OpenCastor
/// commit 78fa0ff.
///
/// This file used to attribute it to "the real robot". That was wrong, and it
/// was wrong in the direction this app exists to avoid: a simulation result
/// promoted to a hardware result, published to strangers on the Hub, in a card
/// whose very next line says "Never run on hardware. Everything here was
/// authored and previewed in simulation." The card contradicted itself two
/// lines apart. Nobody has measured an authored motion on a Microduck, because
/// nobody has a Microduck.
public struct MotionPublication: Equatable, Sendable {

    /// What this app does and does not do to a network, in one sentence a test
    /// pins.
    ///
    /// IT LIVES WHERE `swift test` CAN SEE IT, for the reason `Provenance`
    /// exists at all: a claim about capability that only appears in a comment
    /// is a claim nobody renders and everybody believes. This one is published
    /// — it goes on the card of anything this app puts on the Hub — because the
    /// person reading it is deciding whether the weights in front of them were
    /// learned here, and the answer is no and has always been no.
    public static let trainsNothing =
        "Microduck Studio trains no network. It computes no gradient and has never seen a frame "
      + "of anybody's training data. What it can do to a network is arithmetic on a finished "
      + "one: average two into a third, or fold a per-joint gain and trim into the last layer. "
      + "Whatever a policy from here does well, somebody else's optimiser found."

    /// The tag that makes a move findable, and the repository type it has to
    /// be published as for the tag to mean anything.
    ///
    /// OUR OWN TAG, THEIR SHAPE. Pollen's community moves carry
    /// `reachy_mini_community_moves`; this is the same shape — underscores,
    /// `<robot>_community_moves` — for a different robot, because we are not
    /// Reachy Mini and tagging a duck's keyframes as one would put a motion
    /// that no Reachy Mini can play into the results of everybody searching
    /// for one.
    public static let hubTag = "microduck_community_moves"

    /// Datasets. Stated here rather than at the call site so the one decision
    /// this type exists to get right lives beside the tag it goes with.
    public static let repositoryKind = HuggingFacePublish.Repository.Kind.dataset

    public let name: String
    /// The move's name on the other side, because a loader that globs
    /// `*.json` takes the move's name from the file name. See `slug(for:)`.
    public let slug: String
    /// One sentence saying when to play this move.
    public let whenToUse: String
    public let files: [HuggingFacePublish.File]
    public let summary: String

    public var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }

    /// The move file's path in the repository: `<slug>.json`.
    public var movePath: String { "\(slug).json" }

    /// Where the manifest goes — DELIBERATELY NOT THE ROOT. Pollen's loader
    /// globs `*.json` and treats every hit as a move, so a `manifest.json`
    /// sitting beside the move would be loaded as a second move called
    /// "manifest" that cannot parse. `*.json` is not `**/*.json`, so one
    /// directory down is out of its reach and still one click away for a
    /// person.
    public static let manifestPath = "meta/manifest.json"

    /// A name that survives being a filename — and it becomes the move's name
    /// on the other side, so this is not cosmetic.
    ///
    /// ASCII ONLY, which is stricter than a filename needs. The same slug is
    /// offered as the repository name, and `HuggingFacePublish.repository`
    /// refuses anything outside letters, digits, dots, dashes and
    /// underscores — so a motion called "élan" would slug to a filename that
    /// is fine and a repository name that is refused at the last moment.
    public static func slug(for name: String) -> String {
        var out = ""
        for character in name.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                out.append(character)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "microduck-motion" : out
    }

    /// Everything the author is told to expect, in the card and the manifest.
    public static func cautions(for draft: IntentDraft) -> [String] {
        var out = [
            "Authored keyframes are a request, not a result: driven through the standing "
          + "policy in MuJoCo, leg offsets come out shallower than authored — measured at "
          + "40-60% of the authored depth for a crouch. That figure is from simulation. No "
          + "authored motion has been measured on a Microduck, because none has shipped yet.",
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

    /// - Parameter whenToUse: one sentence saying WHEN to play this move —
    ///   "when you discover something extraordinary", not "the head nods".
    ///   Pollen's emotions library gives every move exactly this and keys its
    ///   `metadata.jsonl` on it, and it is the difference between a library
    ///   somebody can browse and a folder of filenames. It is also the only
    ///   thing a model choosing a move to play has to read. Required, and
    ///   refused when blank, because a move without it is not findable.
    public init(draft: IntentDraft, whenToUse: String, note: String? = nil) throws {
        let sentence = whenToUse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { throw HuggingFacePublish.Refusal.noWhenToUse }
        name = draft.name
        self.whenToUse = sentence
        let stem = Self.slug(for: draft.name)
        slug = stem
        let move = try draft.exported()
        let manifest = Self.manifest(for: draft, whenToUse: sentence, note: note)
        let card = Self.card(for: draft, slug: stem, whenToUse: sentence, note: note)
        files = [
            // `<slug>.json`, NOT `motion.duckmove`. Pollen's
            // `RecordedMoves.process()` globs `*.json` and nothing else, so a
            // `.duckmove` is invisible to it however correct the repository
            // type and the tags are — and the name it shows for the move is
            // the file's own stem. The bytes are unchanged: a `.duckmove` was
            // always JSON, so this is a rename, not a re-encoding.
            .init(path: "\(stem).json", contents: move, isText: true),
            .init(path: Self.manifestPath, contents: manifest, isText: true),
            .init(path: "README.md", contents: Data(card.utf8), isText: true),
        ]
        summary = "Add \(draft.name) — a Microduck move authored in Microduck Studio"
    }

    static func manifest(for draft: IntentDraft, whenToUse: String, note: String?) -> Data {
        let body: [String: Any] = [
            "schema_version": 1,
            // The field an importer reads FIRST. Without it a motion and a
            // policy are both "a file in a microduck repository".
            "artifact": "motion",
            "name": draft.name,
            // The same sentence the card leads with, where something reading
            // the repository rather than the page can find it.
            "when_to_use": whenToUse,
            "authored_in": "Microduck Studio",
            "robot": ["model": "microduck", "hw_rev": 1,
                      "servos": "xl330", "control_hz": DuckModel.tickHz],
            "motion": [
                "format": DuckMoveFile.format,
                "file": "\(slug(for: draft.name)).json",
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

    /// A YAML double-quoted scalar's two escapes. A move called `the "big" bow`
    /// would otherwise close the quote early and make the whole front matter
    /// unparseable, which on the Hub means an untagged, unfindable repository
    /// rather than a visible error.
    static func yamlQuoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func card(for draft: IntentDraft, slug: String,
                     whenToUse: String, note: String?) -> String {
        let cautionLines = cautions(for: draft).map { "- \($0)" }.joined(separator: "\n")
        let keyLines = draft.keys.enumerated().map { index, key in
            String(format: "| %d | %.2f s |", index + 1, key.time)
        }.joined(separator: "\n")
        // FRONT MATTER IN A DATASET CARD'S SHAPE, copied from Pollen's
        // community-moves convention: license, task_categories, language,
        // tags, pretty_name. No `library_name` and no `pipeline_tag` — both
        // are model-card fields, and on a dataset they are noise that says
        // "whoever wrote this thought it was a model". No `configs:` block
        // either: that is the audiofolder viewer's configuration, this ships
        // no audio, and a viewer config pointing at files that do not exist
        // renders as a broken dataset preview.
        return """
        ---
        license: apache-2.0
        task_categories: [robotics]
        language: [en]
        tags: [\(Self.hubTag)]
        pretty_name: \(yamlQuoted("\(draft.name) • Microduck Moves"))
        ---

        # \(draft.name)

        A move for the Pollen Robotics [Microduck](https://github.com/pollen-robotics/microduck), \
        authored in Microduck Studio. \(note ?? "")

        ## When to play it

        \(whenToUse)

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

        - `\(slug).json` — the move itself, in the `\(DuckMoveFile.format)` format DuckKit \
        reads and writes. It is `.json` and not `.duckmove` because a loader that globs \
        `*.json` cannot see anything else, and the move's name is this file's own name.
        - `\(Self.manifestPath)` — the same facts, machine-readable. Kept out of the root so \
        that same glob does not pick it up as a move called "manifest".
        - `README.md` — this card
        """
    }
}
