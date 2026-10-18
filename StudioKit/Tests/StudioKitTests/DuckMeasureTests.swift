import XCTest
import DuckKit
@testable import StudioKit

/// "Measure my duck": the protocol, a row run on a fake duck, the duck-measure/0 report, and the
/// evaluation against docs/PACKS.md "Acceptance".
final class DuckMeasureTests: XCTestCase {

    typealias FakeDuck = DuckCardLoopTests.FakeDuck

    // MARK: - acceptance, pinned

    func testAcceptanceIsWhatPacksMdPreRegistered() {
        // docs/PACKS.md, "Acceptance (pre-registered 2026-10-15)". Change both together, with a
        // dated paragraph there.
        XCTAssertEqual(DuckMeasure.Acceptance.positionShareOfSquare, 1.0 / 3.0)
        XCTAssertEqual(DuckMeasure.Acceptance.positionCm, 10, accuracy: 1e-9)
        XCTAssertEqual(DuckMeasure.Acceptance.headingDegrees, 15)
        XCTAssertEqual(DuckMeasure.Acceptance.walkSeconds, 8)
        XCTAssertEqual(DuckMeasure.Acceptance.turnSeconds, 6)
        XCTAssertEqual(DuckMeasure.Acceptance.rowShare, 0.95)
        XCTAssertEqual(DuckMeasure.Acceptance.fallUpperBound, 0.01)
        XCTAssertEqual(DuckMeasure.Acceptance.simulatorRows, 200)
    }

    func testTheWilsonBoundNeeds381CleanRowsAsPacksMdSays() {
        let w = { (k: Int, n: Int) in DuckMeasure.Acceptance.wilsonUpper(k, of: n) }
        XCTAssertGreaterThan(w(0, 380), 0.01)
        XCTAssertLessThanOrEqual(w(0, 381), 0.01)
        XCTAssertGreaterThan(w(0, 200), 0.018)
        XCTAssertGreaterThan(w(1, 562), 0.01)
        XCTAssertLessThanOrEqual(w(1, 563), 0.01)
        XCTAssertGreaterThan(w(2, 725), 0.01)
        XCTAssertLessThanOrEqual(w(2, 726), 0.01)
        XCTAssertEqual(w(0, 0), 1)
    }

    // MARK: - the protocol

    func testTheRowsAreOneToFourWalksAndFourTurns() throws {
        XCTAssertEqual(DuckMeasure.runs.map(\.id), ["walk-1", "walk-2", "walk-3", "walk-4", "turn-4"])
        XCTAssertEqual(DuckMeasure.runs[3].expect, .init(forwardCm: 120, leftCm: 0, headingDeg: 0))
        XCTAssertEqual(DuckMeasure.runs[4].expect, .init(forwardCm: 0, leftCm: 0, headingDeg: 0))
        for run in DuckMeasure.runs {
            let plan = try DuckMeasure.plan(run)
            XCTAssertTrue(plan.closesOnOdometry, "measured cards run here, and only here")
            XCTAssertFalse(plan.cardsTimed)
            XCTAssertEqual(plan.beats.count, run.cards.count)
        }
    }

    // MARK: - one row on a duck

    private final class Lines: @unchecked Sendable {
        private let lock = NSLock(); private var _all: [String] = []
        func add(_ s: String) { lock.withLock { _all.append(s) } }
        var all: [String] { lock.withLock { _all } }
    }

    private func measure(_ run: DuckMeasure.Run, on duck: FakeDuck, lines: Lines = Lines()) async throws
        -> DuckMeasure.RunRecord {
        try await DuckMeasure.run(run, on: duck, interval: 0.05, sleep: { duck.advance($0) },
                                  state: { duck.state() }, now: { duck.clock }, said: { lines.add($0) })
    }

    func testTwoWalkCardsAreRecordedCardByCardOnOdometry() async throws {
        let duck = FakeDuck()
        let r = try await measure(DuckMeasure.runs[1], on: duck)
        XCTAssertEqual(r.ended, .finished)
        XCTAssertEqual(r.cardLog.count, 2)
        for log in r.cardLog {
            XCTAssertEqual(log.ended, .reached)
            XCTAssertNotNil(log.before); XCTAssertNotNil(log.after)
            XCTAssertGreaterThan(try XCTUnwrap(log.seconds), 0.5)
        }
        XCTAssertEqual(try XCTUnwrap(r.cardLog[1].before).xM, try XCTUnwrap(r.cardLog[0].after).xM, accuracy: 0.03)
        let o = try XCTUnwrap(r.odometry)
        XCTAssertEqual(o.forwardCm, 60, accuracy: 3)
        XCTAssertEqual(o.leftCm, 0, accuracy: 1)
        XCTAssertTrue(r.inTime)
        XCTAssertEqual(duck.calls.last, "robot.stop")
    }

    func testFourTurnsComeBackToTheStartHeading() async throws {
        let duck = FakeDuck()
        let r = try await measure(DuckMeasure.runs[4], on: duck)
        XCTAssertEqual(r.ended, .finished)
        XCTAssertEqual(r.cardLog.compactMap(\.ended), Array(repeating: .reached, count: 4))
        XCTAssertLessThan(abs(try XCTUnwrap(r.odometry).headingDeg), DuckCardLoop.spec.turn.toleranceDeg + 3)
    }

    func testAFallEndsTheRowStillAndIsRecorded() async throws {
        let duck = FakeDuck(fallsAt: 0.4), lines = Lines()
        let r = try await measure(DuckMeasure.runs[2], on: duck, lines: lines)
        XCTAssertEqual(r.ended, .stopped)
        XCTAssertEqual(r.said, DuckCardLoop.fellNote)
        XCTAssertTrue(r.fell)
        XCTAssertEqual(r.cardLog.map(\.ended), [.reached, .fell, nil])
        XCTAssertEqual(lines.all.last, DuckCardLoop.fellNote)
        XCTAssertEqual(duck.moves.last, .still)
        XCTAssertEqual(duck.calls.last, "robot.stop")
    }

    func testRefusedBeforeMovingWithoutOdometryOrWhenDown() async throws {
        let blind = FakeDuck(odom: false)
        do { _ = try await measure(DuckMeasure.runs[0], on: blind); XCTFail("ran without odometry") }
        catch let r as DuckMeasure.Refusal { XCTAssertEqual(r, .noOdometry) }
        XCTAssertTrue(blind.moves.isEmpty, "nothing was sent")
        let down = FakeDuck(fallsAt: 0)
        do { _ = try await measure(DuckMeasure.runs[0], on: down); XCTFail("ran a fallen duck") }
        catch let r as DuckMeasure.Refusal { XCTAssertEqual(r, .fallen) }
        XCTAssertTrue(down.moves.isEmpty)
    }

    func testASpecPastPollensEnvelopeIsRefusedHereToo() throws {
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(contentsOf: try XCTUnwrap(DuckCardLoop.specURL))) as? [String: Any])
        var turn = try XCTUnwrap(json["turn"] as? [String: Any])
        turn["trim_rate"] = 1.5
        json["turn"] = turn
        let bad = try DuckCardLoop.Spec.read(try JSONSerialization.data(withJSONObject: json))
        let state = DuckState(odom: .init(position: [0, 0, 0], yaw: 0), receivedAt: Date())
        XCTAssertEqual(DuckMeasure.check(state, spec: bad),
                       .pastTheEnvelope(["turn.trim_rate is 1.5, past Pollen's pad envelope of 1"]))
        XCTAssertNil(DuckMeasure.check(state))
    }

    // MARK: - the report

    private func marked(_ id: Int, _ marks: DuckMeasure.Marks?, ended: DuckMeasure.Ended = .finished,
                        seconds: Double = 2.5, fell: Bool = false) -> DuckMeasure.RunRecord {
        let run = DuckMeasure.runs[id]
        var logs = run.cards.map { DuckMeasure.CardLog(card: $0, seconds: seconds, ended: .reached) }
        if fell { logs[0].ended = .fell }
        return DuckMeasure.RunRecord(run: run, ranAt: Date(timeIntervalSince1970: 1_800_000_000), cardLog: logs,
                                     odomStart: .init(xM: 0, yM: 0, yawRad: 0),
                                     odomEnd: .init(xM: 0.3, yM: 0.01, yawRad: 0.02),
                                     ended: ended, said: ended == .finished ? nil : DuckCardLoop.fellNote,
                                     tester: marks)
    }

    func testTheReportRoundTripsAndCarriesWhatTheDocSays() throws {
        let runs = [marked(0, .init(forwardCm: 33, leftCm: -2, headingDeg: 4)), marked(1, nil)]
        let report = DuckMeasure.report(runs, madeAt: Date(timeIntervalSince1970: 1_800_000_000), app: "1.1 (85)",
                                        bridge: "microduck-bridge 0.4", robotd: nil, policy: "velstand")
        let data = try report.json()
        XCTAssertEqual(try DuckMeasure.Report.read(data), report)
        let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(top["format"] as? String, "duck-measure/0")
        for key in ["made_at", "app", "bridge", "policy", "envelope", "spec", "grid_cm", "runs", "evaluation"] {
            XCTAssertNotNil(top[key], key)
        }
        let spec = try XCTUnwrap(top["spec"] as? [String: Any])
        XCTAssertEqual(spec["enabled_on_robot"] as? Bool, false)
        XCTAssertTrue((spec["digest"] as? String ?? "").hasPrefix("sha256:"))
        XCTAssertEqual((spec["digest"] as? String)?.count, 7 + 64)
        let env = try XCTUnwrap(top["envelope"] as? [String: Any])
        XCTAssertEqual(env["vyaw"] as? [Double], [-1.0, 1.0])
        XCTAssertEqual(env["commit"] as? String, DuckCardLoop.envelope.commit)
        let run0 = try XCTUnwrap((top["runs"] as? [[String: Any]])?.first)
        XCTAssertNotNil(run0["odometry"], "the odometry summary is in the file, not only computed")
        XCTAssertNotNil(run0["card_log"])
        XCTAssertEqual((run0["tester"] as? [String: Any])?["forward_cm"] as? Double, 33)
        XCTAssertEqual(report.fileName, "duck-measure-20270115-0800.json")
    }

    func testTheEvaluationJudgesByTapeWithTheAcceptanceNumbers() throws {
        let runs = [
            marked(0, .init(forwardCm: 33, leftCm: -2, headingDeg: 4)),          // 3.6 cm, 4 degrees: in
            marked(1, .init(forwardCm: 48, leftCm: 5, headingDeg: -20)),         // 13 cm, 20 degrees: out
            marked(2, nil, seconds: 9),                                          // not marked; slow
            marked(3, .init(forwardCm: 120, leftCm: 0, headingDeg: 0), ended: .stopped, fell: true),
            marked(4, .init(forwardCm: 0, leftCm: 0, headingDeg: 359)),          // a full turn, 1 degree off
        ]
        let e = DuckMeasure.evaluate(runs)
        XCTAssertEqual(e.ran, 5); XCTAssertEqual(e.judged, 4)
        XCTAssertEqual(e.positionWithin, 3); XCTAssertEqual(e.headingWithin, 3)
        XCTAssertEqual(e.inTime, 4); XCTAssertEqual(e.fell, 1)
        XCTAssertEqual(e.endedBadly, 1); XCTAssertEqual(e.endedBadlySaid, 1)
        XCTAssertEqual(try XCTUnwrap(runs[4].headingErrorDeg), 1, accuracy: 1e-9)
        XCTAssertTrue(e.said.contains("4 of 5 runs marked by tape. Position: 3 of 4 within 10 cm. Heading: 3 of 4 within 15 degrees."),
                      "\(e.said)")
        XCTAssertTrue(e.said.contains { $0.hasPrefix("1 fell.") })
        XCTAssertTrue(e.said.last?.contains("cannot pass Acceptance alone") == true)
        XCTAssertTrue(DuckMeasure.Words.result(runs[2]).contains("Card 1, 2, 3 took longer than its time bound"))
    }

    func testCancelledAndRefusedRowsAreNotJudged() {
        let e = DuckMeasure.evaluate([marked(0, .init(forwardCm: 30, leftCm: 0, headingDeg: 0), ended: .cancelled)])
        XCTAssertEqual(e.ran, 0)
        XCTAssertEqual(e.said, ["No run has finished yet."])
    }

    // MARK: - standing still

    /// The fake duck's state with a heading sensor drifting at `degPerS`, and from `fallsAfter` s
    /// down, and from `staleAfter` s a frame that never updates.
    private func drifting(_ duck: FakeDuck, degPerS: Double, fallsAfter: Double? = nil,
                          staleAfter: Double? = nil) -> RobotPlanRunner.State {
        let t0 = duck.clock
        return {
            let t = duck.clock.timeIntervalSince(t0)
            let (x, y, h) = duck.where_
            let at = staleAfter.map { t > $0 ? t0.addingTimeInterval($0) : duck.clock } ?? duck.clock
            let fallen = fallsAfter.map { t >= $0 } ?? false
            return DuckState(safety: .init(fallen: fallen),
                             odom: .init(position: [x, y, 0.12], yaw: h + degPerS * t * .pi / 180), receivedAt: at)
        }
    }

    func testStandingStillMeasuresTheHeadingSensorsDrift() async throws {
        let duck = FakeDuck()
        var r = try await DuckMeasure.standStill(on: duck, sleep: { duck.advance($0) },
                                                 state: drifting(duck, degPerS: 0.2), now: { duck.clock })
        XCTAssertEqual(r.ended, .finished)
        XCTAssertEqual(r.samples.count, 61, "every half second for 30 s, both ends")
        XCTAssertEqual(try XCTUnwrap(r.yawRateDegPerS), 0.2, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(r.yawChangeDeg), 6, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(r.creepCm), 0, accuracy: 1e-9)
        XCTAssertNil(r.driftDegPerS, "not without the tape")
        r.testerHeadingDeg = 1.5
        XCTAssertEqual(try XCTUnwrap(r.driftDegPerS), 0.15, accuracy: 2e-3)
        XCTAssertTrue(duck.moves.allSatisfy { $0 == .still }, "nothing but a zero twist is sent")
        XCTAssertGreaterThan(duck.moves.count, 100, "at the spec's rate, so the deadmen never fire")
        XCTAssertEqual(duck.calls.last, "robot.stop")
        XCTAssertTrue(DuckMeasure.Words.stillResult(r).contains("drifted 0.150 degrees a second, 9 degrees a minute"),
                      DuckMeasure.Words.stillResult(r))
    }

    func testStandingStillEndsOnAFallOrAStalePoseAndIsRefusedWhenDown() async throws {
        let duck = FakeDuck()
        let fell = try await DuckMeasure.standStill(on: duck, sleep: { duck.advance($0) },
                                                    state: drifting(duck, degPerS: 0, fallsAfter: 10), now: { duck.clock })
        XCTAssertEqual(fell.ended, .stopped); XCTAssertEqual(fell.said, DuckCardLoop.fellNote)
        XCTAssertEqual(try XCTUnwrap(fell.samples.last).tS, 9.5, accuracy: 0.06)
        XCTAssertEqual(duck.calls.last, "robot.stop")
        let other = FakeDuck()
        let lost = try await DuckMeasure.standStill(on: other, sleep: { other.advance($0) },
                                                    state: drifting(other, degPerS: 0, staleAfter: 5), now: { other.clock })
        XCTAssertEqual(lost.ended, .stopped); XCTAssertEqual(lost.said, DuckCardLoop.lostNote)
        let down = FakeDuck(fallsAt: 0)
        do {
            _ = try await DuckMeasure.standStill(on: down, sleep: { down.advance($0) }, state: { down.state() },
                                                 now: { down.clock })
            XCTFail("stood a fallen duck")
        } catch let r as DuckMeasure.Refusal { XCTAssertEqual(r, .fallen) }
        XCTAssertTrue(down.moves.isEmpty, "nothing was sent")
    }

    func testTheReportCarriesTheStandStillStepAndOldReportsStillRead() throws {
        var still = DuckMeasure.StillRecord(ranAt: Date(timeIntervalSince1970: 1_800_000_000),
                                            samples: (0...60).map { i in
                                                .init(tS: Double(i) / 2, xM: 0, yM: 0, yawRad: Double(i) * 0.001) })
        still.testerHeadingDeg = 0
        let report = DuckMeasure.report([marked(0, nil)], madeAt: Date(timeIntervalSince1970: 1_800_000_000),
                                        app: "1.1 (86)", bridge: nil, robotd: nil, policy: "velstand", still: still)
        let data = try report.json()
        XCTAssertEqual(try DuckMeasure.Report.read(data), report)
        let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let s = try XCTUnwrap(top["still"] as? [String: Any])
        for key in ["ran_at", "seconds", "samples", "ended", "tester_heading_deg", "yaw_change_deg",
                    "yaw_rate_deg_per_s", "creep_cm", "drift_deg_per_s"] {
            XCTAssertNotNil(s[key], key)
        }
        var old = top
        old.removeValue(forKey: "still")
        let read = try DuckMeasure.Report.read(try JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(read.still, "a report from before the step reads, without it")
    }

    // MARK: - words

    func testEverySentenceIsInTheAppsVoiceWithoutADash() {
        typealias W = DuckMeasure.Words
        var sentences: [String] = [W.title, W.entryFooter, W.thisIsATest, W.grid(), W.marks, W.safety,
                                   W.cancelled, W.needsDuck, W.reportFooter, W.stillHeading, W.still(), W.stillMark]
        sentences += DuckMeasure.runs.map(DuckMeasure.Words.expect) + DuckMeasure.runs.map(DuckMeasure.Words.runTitle)
        sentences += [DuckMeasure.Refusal.notConnected, .noOdometry, .fallen, .pastTheEnvelope(["x"])].map(\.message)
        sentences += DuckMeasure.evaluate([marked(0, .init(forwardCm: 30, leftCm: 0, headingDeg: 0))]).said
        for s in sentences {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s)
            XCTAssertNil(s.range(of: "(will|would) (land|stop) on", options: .regularExpression), s)
        }
        XCTAssertTrue(DuckMeasure.Words.thisIsATest.hasPrefix("This is a test."))
        XCTAssertTrue(DuckMeasure.Words.grid().contains("30 cm squares"))
        XCTAssertEqual(DuckMeasure.Words.runTitle(DuckMeasure.runs[0]), "1 Walk forward card")
        XCTAssertEqual(DuckMeasure.Words.runTitle(DuckMeasure.runs[4]), "4 Turn left cards")
    }
}
