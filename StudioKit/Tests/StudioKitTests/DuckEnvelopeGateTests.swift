import XCTest
@testable import StudioKit

/// The envelope gate (brains-layer.md 6.2): bind before act, the rules in order, the golden
/// cases, the decision checks, and the summary chip.
final class DuckEnvelopeGateTests: XCTestCase {

    typealias Gate = DuckEnvelopeGate

    static let phone = PlannerInfo(id: "phone.ducktalk", modelVersion: "ducktalk-1", label: "Understood on this phone",
                                   runsOn: .thisPhone, key: .none, decisionDeadline: .milliseconds(50))
    static let hosted = PlannerInfo(id: "byok.vendor", modelVersion: "model-2026-10", label: "Hosted",
                                    runsOn: .hosted(vendor: "vendor"), key: .byok(provider: "vendor"),
                                    decisionDeadline: .seconds(8))

    static func bound(_ venue: BrainVenue = .practice, mode: BrainMode = .auto, planner: PlannerInfo = phone,
                      allowed: AllowedDecisions? = nil) -> Gate {
        var gate = Gate()
        let set = allowed ?? AllowedDecisions(kinds: [.walk, .turn, .sound, .skill], skills: ["kick_left", "kick_right"],
                                              sounds: ["greet"])
        gate.bind(Gate.Binding(planner, venue: venue, mode: mode, allowed: set))
        return gate
    }

    static func row(_ t: Double, _ vx: Double, _ vy: Double = 0, _ vyaw: Double = 0) -> Gate.Row {
        Gate.Row(t: t, twist: GateTwist(vx: vx, vy: vy, vyaw: vyaw), odomAgeMs: 20,
                 pose: Gate.Pose(x: 0, y: 0, yaw: 0), tiltDeg: 0)
    }

    func decided(_ d: DuckDecision, _ p: PlannerInfo = phone, confidence: Double? = nil) -> Decided {
        Decided(decision: d, why: "test", confidence: confidence, provider: p, latency: .milliseconds(5))
    }

    // MARK: bind before act

    func testActBeforeBindThrows() {
        var gate = Gate()
        XCTAssertThrowsError(try gate.act(Self.row(0, 0.1))) { XCTAssertEqual($0 as? Gate.GateError, .notBound) }
        XCTAssertThrowsError(try gate.check(decided(.walk(forwardM: 1, sideM: 0)), at: 0)) {
            XCTAssertEqual($0 as? Gate.GateError, .notBound)
        }
        XCTAssertTrue(gate.events.isEmpty)
    }

    func testBindingAgainStartsAFreshRun() throws {
        var gate = Self.bound()
        _ = try gate.act(Self.row(0, 0.1, 0, 0).with(tilt: 90))
        XCTAssertEqual(try gate.act(Self.row(0.1, 0.1)).verdict, .cut)
        gate.bind(Gate.Binding(Self.phone, venue: .practice, mode: .auto, allowed: AllowedDecisions(kinds: [.walk])))
        XCTAssertEqual(try gate.act(Self.row(0, 0.1)).verdict, .pass)
        XCTAssertEqual(gate.stats.total, 0)
    }

    // MARK: limits

    func testSourcedLimitsComeFromTheKitAndThePlaceholdersAreNamed() {
        let l = Gate.Limits.placeholderV1
        XCTAssertEqual(l.maxForward, DuckDrive.maxForward)
        XCTAssertEqual(l.maxTurn, DuckDrive.maxTurn)
        XCTAssertEqual(l.runCapRealS, ControlArbiter.Caps.realDuckDefault)
        XCTAssertEqual(l.runCapPracticeS, ControlArbiter.Caps.practiceDuckDefault)
        let fields = Set(Mirror(reflecting: l).children.compactMap(\.label))
        for name in l.placeholders { XCTAssertTrue(fields.contains(name), "\(name) is not a field") }
        XCTAssertFalse(l.placeholders.contains("maxForward"), "the stick limits are sourced")
    }

    // MARK: golden cases

    struct Golden {
        let id: String
        let venue: BrainVenue
        let rows: [(Gate.Row, [String: Any])]
    }

    static func number(_ v: Any?) -> Double? {
        switch v {
        case let s as String: return s == "nan" ? .nan : s == "inf" ? .infinity : s == "-inf" ? -.infinity : nil
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        default: return nil
        }
    }

    static func triple(_ v: Any?) -> [Double]? {
        guard let a = v as? [Any], a.count == 3 else { return nil }
        let out = a.compactMap(number)
        return out.count == 3 ? out : nil
    }

    func golden() throws -> (limits: Gate.Limits, cases: [Golden]) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/gate/golden-cases", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let limitsData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(top["limits"]))
        let limits = try JSONDecoder().decode(Gate.Limits.self, from: limitsData)
        let defaults = try XCTUnwrap(top["defaults"] as? [String: Any])
        var cases: [Golden] = []
        for c in try XCTUnwrap(top["cases"] as? [[String: Any]]) {
            var rows: [(Gate.Row, [String: Any])] = []
            for raw in try XCTUnwrap(c["rows"] as? [[String: Any]]) {
                var r = defaults
                for (k, v) in raw { r[k] = v }
                let tw = try XCTUnwrap(Self.triple(r["twist"]))
                let pose = Self.triple(r["pose"]).map { Gate.Pose(x: $0[0], y: $0[1], yaw: $0[2]) }
                let row = Gate.Row(t: try XCTUnwrap(Self.number(r["t"])),
                                   twist: GateTwist(vx: tw[0], vy: tw[1], vyaw: tw[2]),
                                   odomAgeMs: Self.number(r["odom_age_ms"]),
                                   observationAgeS: Self.number(r["observation_age_s"]),
                                   chunkLate: r["chunk_late"] as? Bool ?? false, pose: pose,
                                   tiltDeg: Self.number(r["tilt_deg"]),
                                   phoneUnlocked: r["phone_unlocked"] as? Bool ?? true)
                rows.append((row, try XCTUnwrap(r["expect"] as? [String: Any])))
            }
            cases.append(Golden(id: try XCTUnwrap(c["id"] as? String),
                                venue: try XCTUnwrap(BrainVenue(rawValue: c["venue"] as? String ?? "")), rows: rows))
        }
        return (limits, cases)
    }

    func testTheGoldenCasesUseTheseLimits() throws {
        XCTAssertEqual(try golden().limits, .placeholderV1)
    }

    func testTheGoldenCasesPass() throws {
        let (limits, cases) = try golden()
        XCTAssertGreaterThanOrEqual(cases.count, 20)
        var seenRules: Set<String> = []
        var seenVerdicts: Set<String> = []
        for c in cases {
            var gate = Gate(limits: limits)
            gate.bind(Gate.Binding(providerId: "golden", modelVersion: "1", venue: c.venue, mode: .auto,
                                   remote: false, allowed: AllowedDecisions(kinds: [.walk, .turn])))
            for (i, (row, expect)) in c.rows.enumerated() {
                let where_ = "\(c.id) row \(i)"
                let got = try gate.act(row)
                XCTAssertEqual(got.verdict.rawValue, expect["verdict"] as? String, where_)
                XCTAssertEqual(got.rule?.rawValue, expect["rule"] as? String, where_)
                XCTAssertEqual(got.stopPath, expect["stop_path"] as? Bool, where_)
                let sent = try XCTUnwrap(Self.triple(expect["sent"]), where_)
                XCTAssertEqual(got.sent.vx, sent[0], accuracy: 1e-9, where_)
                XCTAssertEqual(got.sent.vy, sent[1], accuracy: 1e-9, where_)
                XCTAssertEqual(got.sent.vyaw, sent[2], accuracy: 1e-9, where_)
                if let m = Self.number(expect["keep_in_margin_m"]) {
                    XCTAssertEqual(try XCTUnwrap(got.keepInMarginM, where_), m, accuracy: 1e-9, where_)
                }
                XCTAssertEqual(got.proximity, .unmet, "rule 11 is never passed")
                seenVerdicts.insert(got.verdict.rawValue)
                if let r = got.rule { seenRules.insert(r.rawValue) }
            }
        }
        XCTAssertEqual(seenVerdicts, Set(Gate.Verdict.allCases.map(\.rawValue)), "every verdict has a golden case")
        XCTAssertEqual(seenRules, ["finite", "stick", "rate", "stale", "keep-in", "tilt", "run"],
                       "every row rule has a golden case")
    }

    // MARK: the run summary

    func testTheChipReadsLikeThePlan() {
        var stats = GateStats()
        for _ in 0..<9 { stats.count(.keepIn) }
        for _ in 0..<5 { stats.count(.rate) }
        XCTAssertEqual(stats.chip, "Gate stepped in 14 times (keep-in 9, rate 5)")
        var once = GateStats()
        once.count(.rate)
        XCTAssertEqual(once.chip, "Gate stepped in once (rate 1)")
        XCTAssertEqual(GateStats().chip, "Gate did not step in.")
        var asked = GateStats()
        asked.count(.confirm)
        XCTAssertEqual(asked.total, 0, "a Go card is not the gate stepping in")
    }

    func testTheGateCountsWhatItDid() throws {
        var gate = Self.bound()
        _ = try gate.act(Self.row(0, 0.3))           // rate
        _ = try gate.act(Self.row(0.1, 0.3))         // rate
        _ = try gate.act(Self.row(0.2, 0.3))         // pass
        XCTAssertEqual(gate.stats.chip, "Gate stepped in 2 times (rate 2)")
        XCTAssertEqual(gate.events.count, 3)
    }

    func testTheSummarySaysWhatTheGateCannotDo() {
        let practice = GateStats().summary(venue: .practice, limits: .placeholderV1)
        XCTAssertTrue(practice.contains(GateWords.noObstacleSensing))
        XCTAssertFalse(practice.contains(GateWords.keepInApproximate))
        XCTAssertTrue(practice.contains(GateWords.placeholders))
        XCTAssertTrue(GateStats().summary(venue: .real, limits: .placeholderV1).contains(GateWords.keepInApproximate))
    }

    func testTheGateIsNeverCalledSafety() {
        for line in GateWords.all + [GateStats().chip] {
            XCTAssertFalse(line.lowercased().contains("safe"), line)
            XCTAssertFalse(line.contains("\u{2014}"), line)
        }
    }

    // MARK: decisions

    func testStopIsNeverRefusedAndNeverWaits() throws {
        var gate = Self.bound(mode: .tell)
        let got = try gate.check(decided(.stop(reason: "x")), at: 999, phoneUnlocked: false)
        XCTAssertEqual(got.verdict, .pass)
        XCTAssertTrue(got.stopPath)
        XCTAssertTrue(got.confirmations.isEmpty)
    }

    func testTellAlwaysShowsTheCountdown() throws {
        var gate = Self.bound(mode: .tell)
        let walk = decided(.walk(forwardM: 0.3, sideM: 0))
        XCTAssertTrue(try gate.check(walk, at: 0).confirmations.contains(.tellCountdown))
        XCTAssertEqual(try gate.confirm(walk, at: 0).verdict, .pass)
        XCTAssertEqual(try gate.check(walk, at: 1).confirmations, [.tellCountdown])
    }

    func testAutoAsksOncePerNewKindThenRuns() throws {
        var gate = Self.bound(mode: .auto)
        let walk = decided(.walk(forwardM: 0.3, sideM: 0))
        let first = try gate.check(walk, at: 0)
        XCTAssertEqual(first.verdict, .held)
        XCTAssertEqual(first.rule, .confirm)
        XCTAssertEqual(Set(first.confirmations), [.newKind(.walk), .newSource("phone.ducktalk")])
        XCTAssertEqual(try gate.confirm(walk, at: 0).verdict, .pass)
        XCTAssertEqual(try gate.check(decided(.walk(forwardM: 0.5, sideM: 0)), at: 1).verdict, .pass)
        let turn = try gate.check(decided(.turn(degrees: 30)), at: 2)
        XCTAssertEqual(turn.confirmations, [.newKind(.turn)])
        XCTAssertEqual(gate.stats.total, 0, "Go cards are not counted as the gate stepping in")
    }

    func testEachNewSkillNameAsksAgain() throws {
        var gate = Self.bound(.real, mode: .auto)
        _ = try gate.confirm(decided(.skill(name: "kick_left")), at: 0)
        XCTAssertEqual(try gate.check(decided(.skill(name: "kick_right")), at: 1).confirmations, [.newSkill("kick_right")])
    }

    func testABigClampAsksFirstAndTheDecisionIsClamped() throws {
        var gate = Self.bound(mode: .auto)
        let far = decided(.walk(forwardM: 3, sideM: 0))
        XCTAssertTrue(try gate.check(far, at: 0).confirmations.contains(.bigClamp))
        let ran = try gate.confirm(far, at: 0)
        XCTAssertEqual(ran.verdict, .clamped)
        XCTAssertEqual(ran.decision, .walk(forwardM: DuckDecision.maxForwardM, sideM: 0))
    }

    func testConfidenceCanOnlyAddConfirmations() throws {
        let decisions: [DuckDecision] = [.walk(forwardM: 0.2, sideM: 0), .walk(forwardM: 4, sideM: 0),
                                         .turn(degrees: 10), .sound(name: "greet"), .skill(name: "kick_left"),
                                         .ask(question: "?"), .done(reason: "x"), .stop(reason: "x")]
        let confidences: [Double] = [0, 0.3, 0.59, 0.6, 0.9, 1, 1.5, -1, .nan, .infinity]
        for mode in BrainMode.allCases {
            var gate = Self.bound(.real, mode: mode)
            for warm in [false, true] {
                if warm {
                    for d in decisions { _ = try gate.confirm(decided(d), at: 0) }
                }
                for d in decisions {
                    let base = Set(gate.confirmations(for: decided(d)))
                    for c in confidences {
                        let with = Set(gate.confirmations(for: decided(d, confidence: c)))
                        XCTAssertTrue(with.isSuperset(of: base), "\(mode) \(d) confidence \(c) removed a confirmation")
                    }
                    if !d.kind.onlyStops && d.kind != .ask {
                        XCTAssertTrue(gate.confirmations(for: decided(d, confidence: 0.1)).contains(.lowConfidence))
                    }
                }
            }
        }
    }

    func testAHostedPlannerGetsNoSkillsOnARealDuck() throws {
        var gate = Self.bound(.real, mode: .auto, planner: Self.hosted)
        let got = try gate.confirm(decided(.skill(name: "kick_left"), Self.hosted), at: 0)
        XCTAssertEqual(got.verdict, .held)
        XCTAssertEqual(got.rule, .allowlist)
    }

    func testASkillOffTheListIsHeld() throws {
        var gate = Self.bound(.real)
        XCTAssertEqual(try gate.confirm(decided(.skill(name: "backflip")), at: 0).rule, .allowlist)
    }

    func testSkillsPerMinuteAreCapped() throws {
        var gate = Self.bound(.real)
        let names = ["kick_left", "kick_right"]
        for i in 0..<Gate.Limits.placeholderV1.skillsPerMinute {
            XCTAssertEqual(try gate.confirm(decided(.skill(name: names[i % 2])), at: Double(i)).verdict, .pass)
        }
        XCTAssertEqual(try gate.confirm(decided(.skill(name: "kick_left")), at: 10).rule, .allowlist)
    }

    func testTheRunLimitsCut() throws {
        var gate = Self.bound()
        for i in 0..<Gate.Limits.placeholderV1.maxDecisions {
            XCTAssertEqual(try gate.confirm(decided(.walk(forwardM: Double(i) / 100, sideM: 0)), at: 1).verdict, .pass)
        }
        let over = try gate.confirm(decided(.turn(degrees: 5)), at: 1)
        XCTAssertEqual(over.verdict, .cut)
        XCTAssertTrue(over.stopPath)
        XCTAssertEqual(try gate.confirm(decided(.turn(degrees: 6)), at: 1).verdict, .cut, "a cut latches")
    }

    func testTheSameDecisionFourTimesInARowCuts() throws {
        var gate = Self.bound()
        let same = decided(.turn(degrees: 15))
        for _ in 0..<Gate.Limits.placeholderV1.maxIdenticalInARow {
            XCTAssertEqual(try gate.confirm(same, at: 1).verdict, .pass)
        }
        XCTAssertEqual(try gate.confirm(same, at: 1).verdict, .cut)
    }

    func testHostedCallsAreCapped() throws {
        var gate = Self.bound(planner: Self.hosted)
        let cap = Gate.Limits.placeholderV1.maxHostedCalls
        for i in 0..<cap {
            XCTAssertEqual(try gate.confirm(decided(.turn(degrees: Double(i + 1)), Self.hosted), at: 1).verdict, .pass)
        }
        let over = try gate.confirm(decided(.turn(degrees: 99), Self.hosted), at: 1)
        XCTAssertEqual(over.verdict, .cut)
        XCTAssertEqual(over.rule, .run)
    }

    func testTheWallClockAndTheVenueCapCut() throws {
        var practice = Self.bound(.practice)
        XCTAssertEqual(try practice.confirm(decided(.turn(degrees: 5)), at: 61).verdict, .cut)
        var real = Self.bound(.real)
        XCTAssertEqual(try real.confirm(decided(.turn(degrees: 5)), at: 31).verdict, .cut)
    }

    func testOneAskAtATime() throws {
        var gate = Self.bound()
        XCTAssertEqual(try gate.check(decided(.ask(question: "which?")), at: 0).verdict, .pass)
        XCTAssertEqual(try gate.check(decided(.ask(question: "and?")), at: 1).rule, .run)
        gate.answered()
        XCTAssertEqual(try gate.check(decided(.ask(question: "and?")), at: 2).verdict, .pass)
    }

    func testALockedPhoneHoldsMotionButNotASound() throws {
        var gate = Self.bound(.real)
        XCTAssertEqual(try gate.confirm(decided(.walk(forwardM: 0.2, sideM: 0)), at: 0, phoneUnlocked: false).verdict, .held)
        XCTAssertEqual(try gate.confirm(decided(.sound(name: "greet")), at: 0, phoneUnlocked: false).verdict, .pass)
    }

    func testANonFiniteDecisionIsInvalid() throws {
        var gate = Self.bound()
        let got = try gate.confirm(decided(.walk(forwardM: .nan, sideM: 0)), at: 0)
        XCTAssertEqual(got.verdict, .invalid)
        XCTAssertTrue(got.stopPath)
    }
}

extension DuckEnvelopeGate.Row {
    func with(tilt: Double) -> DuckEnvelopeGate.Row {
        DuckEnvelopeGate.Row(t: t, twist: twist, odomAgeMs: odomAgeMs, observationAgeS: observationAgeS,
                             chunkLate: chunkLate, pose: pose, tiltDeg: tilt, phoneUnlocked: phoneUnlocked, phase: phase)
    }
}
