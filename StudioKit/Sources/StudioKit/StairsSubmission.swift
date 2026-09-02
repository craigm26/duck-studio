import Foundation

extension StairsChallenge {

    /// A run, packaged so somebody else can check it.
    ///
    /// WHAT A SUBMISSION HAS TO CARRY TO BE WORTH ANYTHING. Not the number:
    /// the number is the easy part and the part nobody can verify. It carries
    /// THE INTENT ITSELF, byte for byte, so the run can be repeated; the
    /// FOURTEEN PER-CELL ANSWERS, unrounded, so a disagreement lands in one
    /// row instead of in an aggregate; and the BENCH'S PLANT DIGEST, because
    /// every one of these numbers is a fact about one compiled MuJoCo model
    /// and means nothing without it. A submission without the plant digest is
    /// a screenshot.
    ///
    /// AND IT SAYS WHERE IT WAS RUN. A score from the bench inside the phone
    /// and a score from a Pi across the room are the same physics and are not
    /// the same machine, and the person reading the issue is entitled to know
    /// which before they try to reproduce it.
    ///
    /// NOTHING HERE POSTS ANYTHING. `issueURL` opens GitHub's new-issue form
    /// with the text already in it and the file still on the person's device;
    /// `publishCalls` builds Hugging Face requests that only become a write
    /// when a screen attaches a token to them. Both leave the last move to a
    /// person, which is the same rule the rest of this app publishes under.
    public struct Submission: Equatable, Sendable {

        public let move: Move
        public let score: Score
        /// What to call the bench on screen and in the bundle — "This iPhone",
        /// or the Pi's address.
        public let benchName: String
        public let benchAddress: String?
        /// Whether the bench answered the grid the leaderboard was produced on.
        public let onPublishedGrid: Bool
        /// The leaderboard row this started from, when it started from one.
        public let row: Row?
        public let appVersion: String
        public let date: Date

        public init(move: Move, score: Score, benchName: String, benchAddress: String? = nil,
                    onPublishedGrid: Bool = true, row: Row? = nil,
                    appVersion: String, date: Date) {
            self.move = move; self.score = score
            self.benchName = benchName; self.benchAddress = benchAddress
            self.onPublishedGrid = onPublishedGrid; self.row = row
            self.appVersion = appVersion; self.date = date
        }

        // MARK: - the words

        public static let kind = "microduck-stairs-challenge-submission"
        public static let formatVersion = 1

        /// Where an entry actually goes.
        public static let issueBase =
            "https://github.com/craigm26/duck-sounds/issues/new"

        /// Said above the Submit button, once a score exists.
        public static let whatIsSent =
            "The file holds the move, all fourteen per-cell answers unrounded, the bench's plant "
          + "digest and the date. It is written to this device and nothing is sent until you "
          + "pick where it goes."

        /// Said when there is no score yet. Submit is not offered before one
        /// exists: a submission with nothing measured in it is a claim.
        public static let notScoredYet =
            "Score the move on a bench first. A submission is the fourteen cells and the plant "
          + "they were scored in; there is nothing to send until they exist."

        /// The sentence the GitHub row carries.
        public static let issueNote =
            "Opens the issue form with the move's hash and the score line already written. The "
          + "file does not travel in a link — attach it to the issue yourself. You will need a "
          + "GitHub account to open the issue; this is the submission a maintainer sees."

        /// The sentence the Hugging Face row carries.
        public static let publishNote =
            "Commits the file to a dataset repository under your own account, using the write "
          + "token this app already holds, published under CC BY 4.0, the same licence the "
          + "challenge's data carries."
        /// Said beside the Hugging Face row, so nobody mistakes an archive for
        /// a submission.
        public static let archiveNote =
            "A Hugging Face commit is your own archive of the run. It submits nothing to anyone: "
          + "the GitHub issue is what a maintainer sees."
        /// How a maintainer gets the intent back out of the bundle and scores
        /// it with the harness, which refuses the bundle file itself.
        public static let howToRescore =
            "To re-score: extract the `intent` object from this file to intent.json, then from "
          + "duck-sounds/sim run node --input-type=module -e 'import { scoreRobust } from "
          + "\"../climb/robust.mjs\"; console.log(await scoreRobust(\"intent.json\", { rise: "
          + "<rise in metres> }))'."

        public static let publishLicense = "cc-by-4.0"
        public static let defaultRepositoryName = "microduck-stairs-challenge-submissions"

        // MARK: - the file

        public var hash: String { score.hash ?? "unhashed" }

        public var dateSaid: String { Self.day.string(from: date) }

        static let day: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        static let stamp: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }()

        /// `microduck-stairs-a56d459fb649-60mm-2026-09-02.json`. The hash
        /// first, because that is what somebody looking for this run has.
        public var filename: String {
            "microduck-stairs-\(hash)-\(Int((score.rise * 1000).rounded()))mm-\(dateSaid).json"
        }

        public func bundle() -> Data { bundleJSON().encoded(.pretty) }

        func bundleJSON() -> HarnessJSON {
            var bench: [HarnessJSON.Member] = [
                .init(key: "name", value: .string(benchName)),
                .init(key: "address", value: benchAddress.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "plantName", value: score.plantName.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "plantDigest", value: score.plantDigest.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "publishedGrid", value: .bool(onPublishedGrid)),
            ]
            if let criterion = score.criterion {
                bench.append(.init(key: "criterion", value: .string(criterion)))
            }
            let aggregate = HarnessJSON.object([
                .init(key: "rise_mm", value: .number((score.rise * 1000).rounded())),
                .init(key: "kCore", value: .number(Double(score.kCore))),
                .init(key: "kCoreStable", value: .number(Double(score.kCoreStable))),
                .init(key: "kExt", value: .number(Double(score.kExt))),
                .init(key: "kExtStable", value: .number(Double(score.kExtStable))),
                .init(key: "ceilingCore", value: .number(Double(score.ceilingCore))),
                .init(key: "nCore", value: .number(Double(score.coreAnswered))),
                .init(key: "nCells", value: .number(Double(score.answered))),
                .init(key: "invalidCells", value: .number(Double(score.invalidCells))),
                .init(key: "bar", value: .number(Double(StairsChallenge.bar))),
                .init(key: "meetsBar", value: .bool(score.meetsBar)),
                .init(key: "maxTq", value: .number(score.maxTorque)),
                .init(key: "verdict", value: .string(score.verdict)),
                .init(key: "line", value: .string(score.line)),
            ])
            return .object([
                .init(key: "kind", value: .string(Self.kind)),
                .init(key: "formatVersion", value: .number(Double(Self.formatVersion))),
                .init(key: "date", value: .string(Self.stamp.string(from: date))),
                .init(key: "app", value: .string("Microduck Studio \(appVersion)")),
                .init(key: "challenge", value: .object([
                    .init(key: "dataset", value: .string(StairsChallenge.datasetURL.absoluteString)),
                    .init(key: "harness", value: .string(StairsChallenge.harnessURL.absoluteString)),
                    .init(key: "bar", value: .number(Double(StairsChallenge.bar))),
                    .init(key: "howToRescore", value: .string(Self.howToRescore)),
                    .init(key: "startedFrom", value: row.map { HarnessJSON.string($0.file) } ?? .null),
                ])),
                .init(key: "bench", value: .object(bench)),
                .init(key: "move", value: .object([
                    .init(key: "hash", value: .string(hash)),
                    .init(key: "name", value: .string(move.name)),
                    .init(key: "intent", value: move.json),
                ])),
                .init(key: "score", value: aggregate),
                .init(key: "cells", value: .array(score.cells.map(Self.cellJSON))),
                .init(key: "caveat", value: .string(StairsChallenge.realDuckCaveat)),
            ])
        }

        /// One answered cell, under the bench's own field names, so the bundle
        /// diffs against a `/climb` answer without a translation table.
        static func cellJSON(_ climbed: DuckBench.Climbed) -> HarnessJSON {
            // THE BENCH'S OWN DIGITS WHEREVER IT WROTE THEM. `literal(_:)`
            // hands back the number token the answer carried, so a bundle that
            // says it holds the per-cell answers unrounded actually does —
            // rather than a re-formatted `Double` that agrees to fifteen
            // places and not to seventeen.
            func number(_ key: String, _ value: Double) -> HarnessJSON {
                climbed.literal(key) ?? .number(value)
            }
            func optional(_ key: String, _ value: Double?) -> HarnessJSON {
                if let literal = climbed.literal(key) { return literal }
                return value.map { HarnessJSON.number($0) } ?? .null
            }
            return .object([
                .init(key: "cell", value: .object([
                    .init(key: "dh", value: .number(climbed.cell.dh)),
                    .init(key: "drop", value: .number(climbed.cell.drop)),
                    .init(key: "fmul", value: .number(climbed.cell.fmul)),
                    .init(key: "tier", value: .string(climbed.cell.tier.rawValue)),
                ])),
                .init(key: "honest", value: .bool(climbed.honest)),
                .init(key: "stable", value: .bool(climbed.stable)),
                .init(key: "uprightTailTicks", value: .number(Double(climbed.uprightTailTicks))),
                .init(key: "above_mm", value: number("above_mm", climbed.aboveMillimetres)),
                .init(key: "x_mm", value: number("x_mm", climbed.xMillimetres)),
                .init(key: "dy_mm", value: number("dy_mm", climbed.dyMillimetres)),
                .init(key: "feetOnTread", value: .number(Double(climbed.feetOnTread))),
                .init(key: "peakAboveTread_mm",
                      value: number("peakAboveTread_mm", climbed.peakAboveTreadMillimetres)),
                .init(key: "maxTq", value: number("maxTq", climbed.maxTorque)),
                .init(key: "penetrationAtScore_mm",
                      value: optional("penetrationAtScore_mm",
                                      climbed.penetrationAtScoreMillimetres)),
                .init(key: "minPenetrationEpisode_mm",
                      value: optional("minPenetrationEpisode_mm",
                                      climbed.minPenetrationEpisodeMillimetres)),
                .init(key: "maxAbsDY_mm", value: number("maxAbsDY_mm", climbed.maxAbsDYMillimetres)),
                .init(key: "reachedFlight", value: .bool(climbed.reachedFlight)),
                .init(key: "invalid", value: .bool(climbed.invalid)),
                .init(key: "why", value: climbed.why.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "seconds", value: number("seconds", climbed.seconds)),
            ])
        }

        // MARK: - GitHub

        public var issueTitle: String {
            "Stairs challenge: \(Int((score.rise * 1000).rounded())) mm"
        }

        public var issueBody: String {
            var lines = [
                "Move `\(hash)` — \(move.name).",
                score.verdict,
                score.line,
                "Scored on \(benchName)"
                    + (score.plantDigest.map { ", plant \($0.prefix(DuckBench.digestShown))" } ?? "")
                    + ", \(dateSaid), with Microduck Studio \(appVersion).",
            ]
            if let row {
                lines.append("Started from `\(row.file)` (published \(row.kCoreStable) of "
                           + "\(Grid.coreCount) stable).")
            }
            if !onPublishedGrid { lines.append(Grid.differentGridNote) }
            for problem in score.problems { lines.append(problem) }
            lines.append("PLEASE ATTACH `\(filename)` TO THIS ISSUE — it carries the intent, all "
                       + "\(score.answered) per-cell answers unrounded and the plant digest, and "
                       + "none of that fits in a link.")
            lines.append(Self.howToRescore)
            lines.append(StairsChallenge.realDuckCaveat)
            return lines.joined(separator: "\n\n")
        }

        /// GitHub's new-issue form, pre-filled. A URL and nothing more: it
        /// cannot carry the file, which is why the body says so out loud.
        public var issueURL: URL {
            var components = URLComponents(string: Self.issueBase)!
            components.queryItems = [
                URLQueryItem(name: "title", value: issueTitle),
                URLQueryItem(name: "body", value: issueBody),
            ]
            return components.url ?? URL(string: Self.issueBase)!
        }

        // MARK: - Hugging Face

        /// The dataset repository this goes to, under the signed-in account.
        public func repository(namespace: String,
                               name: String = defaultRepositoryName)
        throws -> HuggingFacePublish.Repository {
            // A dataset, never a model: a scored run is data. The kind has no
            // default in `HuggingFacePublish` for exactly this reason.
            try HuggingFacePublish.repository(namespace: namespace, name: name, kind: .dataset)
        }

        /// The one file committed, plus the card that says what it is.
        public func files() -> [HuggingFacePublish.File] {
            [
                HuggingFacePublish.File(path: filename, contents: bundle(), isText: true),
                HuggingFacePublish.File(path: "README.md", contents: Data(card().utf8),
                                        isText: true),
            ]
        }

        /// The dataset card. Written here rather than on a screen because it
        /// carries claims — the criterion, the plant, the caveat — and every
        /// claim in this app is a string with a test on it.
        public func card() -> String {
            """
            ---
            license: \(Self.publishLicense)
            tags:
              - microduck
              - robotics
              - mujoco
              - benchmark
              - stairs
            ---

            # Microduck stairs challenge — submissions

            Runs of the [Microduck Stairs Challenge](\(StairsChallenge.datasetURL.absoluteString)) \
            scored from Microduck Studio. Each file holds one move, all fourteen per-cell answers \
            unrounded, and the digest of the plant they were scored in.

            Latest: move `\(hash)` — \(score.verdict)

            \(score.sameCriterion)

            \(StairsChallenge.realDuckCaveat)

            The data is CC BY 4.0; the harness that produced it is Apache-2.0 at \
            \(StairsChallenge.harnessURL.absoluteString).
            """
        }

        /// Create-then-commit, credential-free, exactly as
        /// `HuggingFacePublish` builds every other publish in this app.
        ///
        /// `isPrivate` HAS NO DEFAULT. Whether a run is public is the whole
        /// question a submission asks, and a default is how it would get
        /// answered by nobody.
        public func publishCalls(namespace: String, name: String = defaultRepositoryName,
                                 isPrivate: Bool)
        throws -> (repository: HuggingFacePublish.Repository,
                   create: HuggingFacePublish.Call,
                   commit: HuggingFacePublish.Call) {
            let repository = try repository(namespace: namespace, name: name)
            let create = HuggingFacePublish.create(repository,
                                                   license: Self.publishLicense,
                                                   isPrivate: isPrivate)
            let commit = try HuggingFacePublish.commit(
                repository,
                summary: "Stairs challenge \(hash) — \(score.line)",
                description: score.verdict,
                files: files())
            return (repository, create, commit)
        }
    }
}
