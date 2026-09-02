import Foundation

extension BallChallenge {

    /// A run, packaged so somebody else can check it.
    ///
    /// WHAT IT CARRIES, AND WHY IT IS NOT THE NUMBER. The number is the easy
    /// part and the part nobody can verify. It carries THE ENTRANT ITSELF,
    /// byte for byte, so the run can be repeated; the FOURTEEN PER-CELL
    /// ANSWERS, unrounded, so a disagreement lands in one row instead of in an
    /// aggregate; the BENCH'S PLANT DIGEST, because every one of these numbers
    /// is a fact about one compiled MuJoCo model; and THE THREE REFUSED TERMS
    /// with their reasons, because a reward table that quietly dropped them
    /// would be a different reward wearing this one's name.
    ///
    /// IT NAMES ITS CHALLENGE. A bundle from this app can now be one of two
    /// things and a reader who has to guess from the field names is a reader
    /// about to score it with the wrong harness — so `challenge` is a field,
    /// and `howToRescore` names `chase_robust` rather than `robust`.
    ///
    /// NOTHING HERE POSTS ANYTHING. `issueURL` opens GitHub's new-issue form
    /// with the text already in it and the file still on the person's device;
    /// `publishCalls` builds Hugging Face requests that only become a write
    /// when a screen attaches a token to them.
    public struct Submission: Equatable, Sendable {

        public let entrant: Entrant
        public let score: Score
        /// What to call the bench on screen and in the bundle.
        public let benchName: String
        public let benchAddress: String?
        /// Whether the bench answered the grid the leaderboard is produced on.
        public let onPublishedGrid: Bool
        /// The leaderboard row this started from, when it started from one.
        public let row: Row?
        public let appVersion: String
        public let date: Date

        public init(entrant: Entrant, score: Score, benchName: String,
                    benchAddress: String? = nil, onPublishedGrid: Bool = true,
                    row: Row? = nil, appVersion: String, date: Date) {
            self.entrant = entrant; self.score = score
            self.benchName = benchName; self.benchAddress = benchAddress
            self.onPublishedGrid = onPublishedGrid; self.row = row
            self.appVersion = appVersion; self.date = date
        }

        // MARK: - the words

        public static let kind = "microduck-ball-challenge-submission"
        public static let formatVersion = 1
        /// The field that says which of the two challenges this is.
        public static let challenge = Challenge.ball

        public static let issueBase = StairsChallenge.Submission.issueBase

        /// Said above the Submit button, once a score exists.
        public static let whatIsSent =
            "The file holds the entrant, all fourteen per-cell answers unrounded, the nine "
          + "reward terms with their weights, the three the bench refused with its reasons, the "
          + "bench's plant digest and the date. It is written to this device and nothing is sent "
          + "until you pick where it goes."

        /// Said when there is no score yet.
        public static let notScoredYet =
            "Score the entrant on a bench first. A submission is the fourteen cells and the "
          + "plant they were scored in; there is nothing to send until they exist."

        public static let issueNote = StairsChallenge.Submission.issueNote
        public static let publishNote = StairsChallenge.Submission.publishNote
        public static let archiveNote = StairsChallenge.Submission.archiveNote

        /// How a maintainer gets the entrant back out of the bundle and scores
        /// it with the harness, which refuses the bundle file itself.
        public static let howToRescore =
            "To re-score: extract the `entrant` object from this file to entrant.json inside "
          + "duck-sounds/sim, then from that directory run node --input-type=module -e 'import { "
          + "scoreChase } from \"../chase/chase_robust.mjs\"; console.log(await "
          + "scoreChase(\"./entrant.json\"))'. Relative paths resolve against the working directory."

        public static let publishLicense = "cc-by-4.0"
        public static let defaultRepositoryName = "microduck-ball-challenge-submissions"

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

        /// `microduck-ball-2f1c0d9ab4e6-5s-2026-09-02.json`. The hash first,
        /// because that is what somebody looking for this run has.
        public var filename: String {
            "microduck-ball-\(hash.prefix(12))-\(Self.trim(entrant.seconds))s-\(dateSaid).json"
        }

        static func trim(_ value: Double) -> String {
            value == value.rounded() ? "\(Int(value))" : "\(value)"
        }

        public func bundle() -> Data { bundleJSON().encoded(.pretty) }

        func bundleJSON() -> HarnessJSON {
            var bench: [HarnessJSON.Member] = [
                .init(key: "name", value: .string(benchName)),
                .init(key: "address", value: benchAddress.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "plantName",
                      value: score.plantName.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "plantDigest",
                      value: score.plantDigest.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "publishedGrid", value: .bool(onPublishedGrid)),
            ]
            if let criterion = score.criterion {
                bench.append(.init(key: "criterion", value: .string(criterion)))
            }
            let aggregate = HarnessJSON.object([
                .init(key: "seconds", value: .number(entrant.seconds)),
                .init(key: "kChased", value: .number(Double(score.kChased))),
                .init(key: "kStable", value: .number(Double(score.kStable))),
                .init(key: "kExt", value: .number(Double(score.kExt))),
                .init(key: "kExtStable", value: .number(Double(score.kExtStable))),
                .init(key: "nCore", value: .number(Double(score.coreAnswered))),
                .init(key: "nExt", value: .number(Double(score.extendedAnswered))),
                .init(key: "nCells", value: .number(Double(score.answered))),
                .init(key: "invalidCells", value: .number(Double(score.invalidCells))),
                .init(key: "touchedCells", value: .number(Double(score.touchedCells))),
                .init(key: "bestBallTravel_mm", value: .number(score.bestBallTravelMillimetres)),
                .init(key: "closest_mm", value: .number(score.closestMillimetres)),
                .init(key: "ballPeakSpeed_mps", value: .number(score.ballPeakSpeed)),
                .init(key: "verdict", value: .string(score.verdict)),
                .init(key: "line", value: .string(score.line)),
            ])
            return .object([
                .init(key: "kind", value: .string(Self.kind)),
                .init(key: "formatVersion", value: .number(Double(Self.formatVersion))),
                .init(key: "challenge", value: .string(Self.challenge.rawValue)),
                .init(key: "date", value: .string(Self.stamp.string(from: date))),
                .init(key: "app", value: .string("Microduck Studio \(appVersion)")),
                .init(key: "challengeInfo", value: .object([
                    .init(key: "dataset", value: .string(BallChallenge.datasetURL.absoluteString)),
                    .init(key: "harness", value: .string(BallChallenge.harnessURL.absoluteString)),
                    .init(key: "criterion", value: .string(BallChallenge.criterionSentence)),
                    .init(key: "howToRescore", value: .string(Self.howToRescore)),
                    .init(key: "startedFrom",
                          value: row.map { HarnessJSON.string($0.file) } ?? .null),
                ])),
                .init(key: "bench", value: .object(bench)),
                .init(key: "entrant", value: .object([
                    .init(key: "hash", value: .string(hash)),
                    .init(key: "name", value: .string(entrant.name)),
                    .init(key: "kind", value: .string(entrant.kind.rawValue)),
                    .init(key: "file", value: entrant.json),
                ])),
                .init(key: "score", value: aggregate),
                .init(key: "cells", value: .array(score.cells.map(Self.cellJSON))),
                .init(key: "refused", value: .array(score.refused.map { refusal in
                    HarnessJSON.object([
                        .init(key: "term", value: .string(refusal.term)),
                        .init(key: "weight", value: .number(refusal.weight)),
                        .init(key: "reason", value: .string(refusal.reason)),
                    ])
                })),
                .init(key: "caveat", value: .string(BallChallenge.realDuckCaveat)),
                .init(key: "ballCaveat", value: .string(BallChallenge.ballCaveat)),
            ])
        }

        /// One answered cell, under the bench's own field names, so the bundle
        /// diffs against a `/chase` answer without a translation table.
        ///
        /// THE BENCH'S OWN DIGITS WHEREVER IT WROTE THEM. `literal(_:)` hands
        /// back the number token the answer carried, so a bundle that says it
        /// holds the per-cell answers unrounded actually does.
        static func cellJSON(_ chased: DuckBench.Chased) -> HarnessJSON {
            func number(_ key: String, _ value: Double) -> HarnessJSON {
                chased.literal(key) ?? .number(value)
            }
            return .object([
                .init(key: "cell", value: .object([
                    .init(key: "bearing", value: .number(chased.cell.bearing)),
                    .init(key: "range", value: .number(chased.cell.range)),
                    .init(key: "drop", value: .number(chased.cell.drop)),
                    .init(key: "fmul", value: .number(chased.cell.fmul)),
                    .init(key: "tier", value: .string(chased.cell.tier.rawValue)),
                ])),
                .init(key: "chased", value: .bool(chased.chased)),
                .init(key: "stable", value: .bool(chased.stable)),
                .init(key: "touched", value: .bool(chased.touched)),
                .init(key: "upright", value: .bool(chased.upright)),
                .init(key: "uprightTailTicks", value: .number(Double(chased.uprightTailTicks))),
                .init(key: "ballTravel_mm",
                      value: number("ballTravel_mm", chased.ballTravelMillimetres)),
                .init(key: "ballNet_mm", value: number("ballNet_mm", chased.ballNetMillimetres)),
                .init(key: "closest_mm", value: number("closest_mm", chased.closestMillimetres)),
                .init(key: "final_mm", value: number("final_mm", chased.finalMillimetres)),
                .init(key: "ballPeakSpeed_mps",
                      value: number("ballPeakSpeed_mps", chased.ballPeakSpeed)),
                .init(key: "terms", value: .array(chased.terms.map { term in
                    var members: [HarnessJSON.Member] = [
                        .init(key: "term", value: .string(term.term)),
                        .init(key: "weight", value: .number(term.weight)),
                        .init(key: "value", value: .number(term.value)),
                    ]
                    if let stage0 = term.weightStage0 {
                        members.append(.init(key: "weightStage0", value: .number(stage0)))
                    }
                    if let source = term.actionRateSource {
                        members.append(.init(key: "action_rate_l2_source", value: .string(source)))
                    }
                    if let reference = term.reference {
                        members.append(.init(key: "source", value: .string(reference)))
                    }
                    return .object(members)
                })),
                .init(key: "invalid", value: .bool(chased.invalid)),
                .init(key: "why", value: chased.why.map { HarnessJSON.string($0) } ?? .null),
                .init(key: "seconds", value: number("seconds", chased.seconds)),
            ])
        }

        // MARK: - GitHub

        public var issueTitle: String { "Ball challenge: \(entrant.name)" }

        public var issueBody: String {
            var lines = [
                "Entrant `\(hash)` — \(entrant.name) (\(entrant.kind.said)).",
                score.verdict,
                score.line,
                score.factsSaid,
                "Scored on \(benchName)"
                    + (score.plantDigest.map { ", plant \($0.prefix(DuckBench.digestShown))" } ?? "")
                    + ", \(dateSaid), with Microduck Studio \(appVersion).",
            ]
            if let row {
                lines.append("Started from `\(row.file)` (published \(row.kChased) of "
                           + "\(Grid.coreCount) chased).")
            }
            if !onPublishedGrid { lines.append(Grid.differentGridNote) }
            for problem in score.problems { lines.append(problem) }
            lines.append("PLEASE ATTACH `\(filename)` TO THIS ISSUE — it carries the entrant, all "
                       + "\(score.answered) per-cell answers unrounded, the reward terms and the "
                       + "plant digest, and none of that fits in a link.")
            lines.append(Self.howToRescore)
            lines.append(BallChallenge.ballCaveat)
            lines.append(BallChallenge.realDuckCaveat)
            return lines.joined(separator: "\n\n")
        }

        public var issueURL: URL {
            var components = URLComponents(string: Self.issueBase)!
            components.queryItems = [
                URLQueryItem(name: "title", value: issueTitle),
                URLQueryItem(name: "body", value: issueBody),
            ]
            return components.url ?? URL(string: Self.issueBase)!
        }

        // MARK: - Hugging Face

        public func repository(namespace: String,
                               name: String = defaultRepositoryName)
        throws -> HuggingFacePublish.Repository {
            try HuggingFacePublish.repository(namespace: namespace, name: name, kind: .dataset)
        }

        public func files() -> [HuggingFacePublish.File] {
            [
                HuggingFacePublish.File(path: filename, contents: bundle(), isText: true),
                HuggingFacePublish.File(path: "README.md", contents: Data(card().utf8),
                                        isText: true),
            ]
        }

        /// The dataset card. Written here rather than on a screen because it
        /// carries claims — the criterion, the plant, both caveats — and every
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
              - ball
            ---

            # Microduck ball challenge — submissions

            Runs of the [Microduck Ball Challenge](\(BallChallenge.datasetURL.absoluteString)) \
            scored from Microduck Studio. Each file holds one entrant, all fourteen per-cell \
            answers unrounded, the reward terms with their weights, the terms the bench refused \
            with its reasons, and the digest of the plant they were scored in.

            Latest: entrant `\(hash)` — \(score.verdict)

            \(BallChallenge.criterionSentence)

            \(score.sameCriterion)

            \(BallChallenge.ballCaveat)

            \(BallChallenge.realDuckCaveat)

            The data is CC BY 4.0; the harness that produced it is Apache-2.0 at \
            \(BallChallenge.harnessURL.absoluteString).
            """
        }

        /// Create-then-commit, credential-free. `isPrivate` HAS NO DEFAULT:
        /// whether a run is public is the whole question a submission asks,
        /// and a default is how it would get answered by nobody.
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
                summary: "Ball challenge \(hash) — \(score.line)",
                description: score.verdict,
                files: files())
            return (repository, create, commit)
        }
    }
}
