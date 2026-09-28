import XCTest
import DuckKit
@testable import StudioKit

final class CompareTests: XCTestCase {

    private func contender(_ n: Int, kind: Compare.Contender.Kind = .motion) -> Compare.Contender {
        Compare.Contender(kind: kind, name: "m\(n)", digest: "sha256:\(n)", source: .yours, key: "\(n)")
    }

    // MARK: - what can be compared

    func testMotionsAndDraftsCompareButNotWithNetworks() {
        let recorded = contender(1, kind: .motion)
        let draft = contender(2, kind: .draft)
        let network = contender(3, kind: .behaviour)
        XCTAssertTrue(Compare.canCompare(recorded, draft))
        XCTAssertFalse(Compare.canCompare(recorded, network))
        XCTAssertFalse(Compare.canCompare(recorded, recorded), "a thing against itself says nothing")
    }

    func testAClipDigestIgnoresTheName() {
        func clip(_ name: String, _ v: Double) -> DuckIntentClip {
            DuckIntentClip(name: name, hz: 50, frames: [[0.1, v]], roots: [],
                           netYaw: 0, loops: false, startsFrom: .standing, endsIn: .standing,
                           policy: "p", authored: true, environment: .bareFloor)
        }
        let a = clip("one", 0.2), b = clip("two", 0.2), c = clip("one", 0.3)
        XCTAssertEqual(Compare.digest(of: a), Compare.digest(of: b))
        XCTAssertNotEqual(Compare.digest(of: a), Compare.digest(of: c))
        XCTAssertTrue(Compare.digest(of: a).hasPrefix("sha256:"))
    }

    // MARK: - the tournament

    func testATournamentRefusesWhatCannotBeRanked() {
        XCTAssertThrowsError(try Compare.Tournament([contender(1), contender(2)]))
        XCTAssertThrowsError(try Compare.Tournament((0..<9).map { contender($0) }))
        XCTAssertThrowsError(try Compare.Tournament([contender(1), contender(2),
                                                     contender(3, kind: .behaviour)]))
        XCTAssertThrowsError(try Compare.Tournament([contender(1), contender(1), contender(2)]))
    }

    func testASmallFieldPlaysEveryPairOnce() throws {
        var t = try Compare.Tournament((0..<4).map { contender($0) })
        XCTAssertEqual(t.length, 6)
        var seen = Set<[Int]>()
        while let pair = t.nextPair() {
            seen.insert([pair.a, pair.b].sorted())
            t.record(a: pair.a, b: pair.b, choice: .tie)
        }
        XCTAssertEqual(seen.count, 6, "a round robin, no repeats")
        XCTAssertTrue(t.isFinished)
        XCTAssertNotNil(t.champion)
    }

    func testTheOneThatAlwaysWinsIsChampion() throws {
        var t = try Compare.Tournament((0..<6).map { contender($0) })
        XCTAssertEqual(t.length, 12)
        while let pair = t.nextPair() {
            // Contender 4 always wins; otherwise the lower index does.
            let aWins = pair.a == 4 || (pair.b != 4 && pair.a < pair.b)
            t.record(a: pair.a, b: pair.b, choice: aWins ? .a : .b)
        }
        XCTAssertEqual(t.champion?.name, "m4")
        let shares = t.ranking().map(\.share)
        XCTAssertEqual(shares.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(shares, shares.sorted(by: >))
    }

    func testNeitherIsGoodMovesNothing() throws {
        var t = try Compare.Tournament((0..<3).map { contender($0) })
        let before = t.strengths()
        t.record(a: 0, b: 1, choice: .bothBad)
        XCTAssertEqual(t.strengths(), before)
    }

    // MARK: - the record

    func testAPreferenceRecordSaysWhatEachSideIs() throws {
        let record = try DuckFeedback.preference(
            a: contender(1, kind: .draft), b: contender(2, kind: .motion), choice: .a,
            where: .phoneBench, order: .aLeft, context: "tournament", tournament: "t1",
            share: .public, client: "test")
        let line = record.jsonLine()
        XCTAssertTrue(line.contains("\"kind\":\"preference\""))
        XCTAssertTrue(line.contains("\"kind\":\"motion\""))
        XCTAssertTrue(line.contains("\"digest\":\"sha256:1\""))
        XCTAssertTrue(line.contains("\"context\":\"tournament\""))
        XCTAssertThrowsError(try DuckFeedback.preference(
            a: contender(1), b: contender(1), choice: .a, where: .sim, order: .aLeft,
            context: "duel", share: .local, client: "test"))
    }

    // MARK: - improving by choosing

    func testSequenceVariantsKeepTheOriginalAndStayInsideThePad() {
        let seq = DuckSequence(
            id: UUID(), name: "loop",
            steps: [.init(atSim: 0, twist: .init(vx: 0.3, vy: 0, vyaw: 1.4), policySaid: "walk"),
                    .init(atSim: 2, twist: .init(vx: 0, vy: 0, vyaw: 0), policySaid: "walk")],
            provenance: .said("go"), wallSeconds: 2, recordedAt: Date(), venue: .sim)
        let variants = Compare.variants(of: seq)
        XCTAssertEqual(variants.first?.sequence.steps, seq.steps, "the original is one of them")
        XCTAssertEqual(Set(variants.map { $0.sequence.compareDigest }).count, variants.count)
        for v in variants {
            for step in v.sequence.steps {
                XCTAssertLessThanOrEqual(step.twist.vx, DuckDrive.maxForward)
                XCTAssertLessThanOrEqual(abs(step.twist.vyaw), DuckDrive.maxTurn)
            }
        }
    }

    // MARK: - fun, honestly

    func testAStreakCountsConsecutiveDaysEndingTodayOrYesterday() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        XCTAssertEqual(Compare.streak(days: ["2026-09-28", "2026-09-27", "2026-09-25"],
                                      today: today, calendar: cal), 2)
        XCTAssertEqual(Compare.streak(days: ["2026-09-27", "2026-09-26"], today: today, calendar: cal), 2)
        XCTAssertEqual(Compare.streak(days: ["2026-09-25"], today: today, calendar: cal), 0)
    }

    /// RLHF, but only with what it means here.
    func testTheIntroSaysHumanFeedbackAndThatTrainingIsOffThePhone() {
        XCTAssertTrue(CompareWords.intro.contains("RLHF"))
        XCTAssertTrue(CompareWords.intro.contains("human feedback"))
        XCTAssertTrue(CompareWords.intro.contains("off the phone"))
    }

    /// Duels run at a speed Pollen's walker actually walks at.
    func testMovingCommandsClearTheWalkersDeadBand() {
        for (_, twist) in CompareWords.commands where twist.vx != 0 {
            XCTAssertGreaterThanOrEqual(twist.vx, 0.25)
        }
    }
}
