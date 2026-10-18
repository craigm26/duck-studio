import Foundation
import Crypto
import DuckKit

/// "Measure my duck": the closed-loop cards run on a tester's real duck, as a test, with robotd's
/// own odometry and a tape measure, into a report the tester shares.
///
/// THE ONE PLACE MEASURED CARDS RUN ON A ROBOT. Closed-loop Walk and Turn cards ship off for real
/// ducks (`DuckCardLoop.spec.enabledOnRobot`); everywhere else in Studio a duck's Walk and Turn are
/// timed. This screen turns them on for its own rows only, says it is a test, and offers Stop. It
/// is rung 3 of docs/PACKS.md "Acceptance": a real duck on a taped 30 cm grid, judged by
/// tape-measured end positions and headings, never by the duck's own odometry, which is recorded
/// beside them so the two can be compared.
///
/// THE SAME CARDS, THE SAME ENVELOPE, THE SAME EXITS. Every row is a `RobotPlan` of `.card` beats
/// run by `RobotPlanRunner`, so it is the controller the duck would run if the switch were on:
/// `duck-card-loop.json`, held to Pollen's pad envelope (a spec past it is refused here before
/// anything moves), and ended by the controller's own exits (out of time, trimmed out), a pose
/// gone stale, or robotd saying the duck fell. Any of those ends the row with the duck still and
/// one sentence.
///
/// PURE BUT FOR `run`. The protocol, the report (`duck-measure/0`, docs/PACKS.md) and the
/// evaluation against Acceptance are values, tested on Linux; the view only draws them.
public enum DuckMeasure {

    public static let format = "duck-measure/0"

    // MARK: - acceptance, as docs/PACKS.md pre-registers it

    /// The numbers in docs/PACKS.md "Acceptance" (pre-registered 2026-10-15). A change there is a
    /// change here, and the test that pins these says so.
    public enum Acceptance {
        /// End position within this share of a square of the board's square.
        public static let positionShareOfSquare = 1.0 / 3.0
        /// End heading within this many degrees of the board's heading.
        public static let headingDegrees = 15.0
        /// Each Walk card done within this many seconds.
        public static let walkSeconds = 8.0
        /// Each Turn card done within this many seconds.
        public static let turnSeconds = 6.0
        /// The share of rows that must pass position, and heading, in every condition.
        public static let rowShare = 0.95
        /// The most the fall rate's 95% Wilson upper bound may be.
        public static let fallUpperBound = 0.01
        /// Rows per condition in the simulator rung.
        public static let simulatorRows = 200
        /// z for a two-sided 95% interval.
        public static let z = 1.96

        /// One square's tolerance, cm, at the spec's square.
        public static var positionCm: Double { DuckCardLoop.spec.squareM * 100 * positionShareOfSquare }

        /// The Wilson score interval's upper bound for `k` of `n`.
        public static func wilsonUpper(_ k: Int, of n: Int, z: Double = z) -> Double {
            guard n > 0 else { return 1 }
            let n = Double(n), p = Double(k) / n, z2 = z * z
            let centre = p + z2 / (2 * n)
            let spread = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot()
            return min(1, (centre + spread) / (1 + z2 / n))
        }
    }

    // MARK: - the protocol

    /// Where a row should leave the duck, in its start frame: forward along the start facing, to
    /// the left of that line, and turned left from the start facing.
    public struct Expect: Equatable, Sendable, Codable {
        public let forwardCm: Double
        public let leftCm: Double
        public let headingDeg: Double
        enum CodingKeys: String, CodingKey { case forwardCm = "forward_cm", leftCm = "left_cm", headingDeg = "heading_deg" }
    }

    /// One row of the protocol.
    public struct Run: Equatable, Sendable, Identifiable {
        public let id: String
        public let cards: [String]
        public var expect: Expect {
            let walks = Double(cards.filter { $0 == "walk_forward" }.count)
            let turns = Double(cards.filter { $0 == "turn_left" }.count)
            let heading = (turns * 90).truncatingRemainder(dividingBy: 360)
            return Expect(forwardCm: walks * DuckCardLoop.spec.squareM * 100, leftCm: 0, headingDeg: heading)
        }
    }

    /// One, two, three and four Walk forward cards, then four Turn left cards: the rows
    /// docs/PACKS.md "Acceptance" names for a real duck.
    public static let runs: [Run] = [
        Run(id: "walk-1", cards: ["walk_forward"]),
        Run(id: "walk-2", cards: Array(repeating: "walk_forward", count: 2)),
        Run(id: "walk-3", cards: Array(repeating: "walk_forward", count: 3)),
        Run(id: "walk-4", cards: Array(repeating: "walk_forward", count: 4)),
        Run(id: "turn-4", cards: Array(repeating: "turn_left", count: 4)),
    ]

    /// A row as the runner takes it: closed-loop cards at Normal, measured cards on for this row
    /// only.
    public static func plan(_ run: Run) throws -> RobotPlan {
        let steps: [[String: Any]] = run.cards.map {
            ["clause": Words.cardName($0), "labels": ["action": $0], "confidence": ["action": 1.0]]
        }
        let json: [String: Any] = ["format": DuckIntentPlan.format, "request": "Measure my duck, \(run.id)",
                                   "model": DuckCards.model, "steps": steps]
        let plan = try DuckIntentPlan.read(try JSONSerialization.data(withJSONObject: json))
        return try RobotPlan(plan, measuredCards: true)
    }

    // MARK: - the record

    /// robotd's odometry at one moment: `odom.position` and `odom.yaw`, the trunk IMU's yaw.
    public struct Odom: Equatable, Sendable, Codable {
        public let xM: Double, yM: Double, yawRad: Double
        public init(xM: Double, yM: Double, yawRad: Double) { self.xM = xM; self.yM = yM; self.yawRad = yawRad }
        public init(_ pose: DuckCardLoop.Pose) { self.init(xM: pose.x, yM: pose.y, yawRad: pose.h) }
        enum CodingKeys: String, CodingKey { case xM = "x_m", yM = "y_m", yawRad = "yaw_rad" }
    }

    /// Where `end` is in the frame of `start`, as the tester measures it: cm forward, cm left,
    /// degrees turned left.
    public static func relative(_ end: Odom, from start: Odom) -> Expect {
        let dx = end.xM - start.xM, dy = end.yM - start.yM
        let forward = dx * cos(start.yawRad) + dy * sin(start.yawRad)
        let left = -dx * sin(start.yawRad) + dy * cos(start.yawRad)
        return Expect(forwardCm: forward * 100, leftCm: left * 100,
                      headingDeg: DuckCardLoop.wrap(end.yawRad - start.yawRad) * 180 / .pi)
    }

    /// One card of a row: odometry before and after, how long, how it ended.
    public struct CardLog: Equatable, Sendable, Codable {
        public let card: String
        public var before: Odom?
        public var after: Odom?
        public var seconds: Double?
        public var ended: RobotPlanRunner.CardEnd?
        public init(card: String, before: Odom? = nil, after: Odom? = nil, seconds: Double? = nil,
                    ended: RobotPlanRunner.CardEnd? = nil) {
            self.card = card; self.before = before; self.after = after; self.seconds = seconds; self.ended = ended
        }
    }

    /// The tester's tape-measured marks: the duck's middle against the middle of the start square
    /// and the start arrow.
    public struct Marks: Equatable, Sendable, Codable {
        public var forwardCm: Double
        public var leftCm: Double
        public var headingDeg: Double
        public init(forwardCm: Double, leftCm: Double, headingDeg: Double) {
            self.forwardCm = forwardCm; self.leftCm = leftCm; self.headingDeg = headingDeg
        }
        enum CodingKeys: String, CodingKey { case forwardCm = "forward_cm", leftCm = "left_cm", headingDeg = "heading_deg" }
    }

    /// How a row ended, as the report writes it.
    public enum Ended: String, Equatable, Sendable, Codable {
        case finished, stopped, refused, cancelled
    }

    /// One row as run.
    public struct RunRecord: Equatable, Sendable, Codable {
        public let id: String
        public let cards: [String]
        public let expect: Expect
        public let ranAt: Date
        public var cardLog: [CardLog]
        /// robotd's odometry at the start and the end of the row, and the end in the start's frame.
        public var odomStart: Odom?
        public var odomEnd: Odom? {
            didSet { odometry = odomStart.flatMap { s in odomEnd.map { DuckMeasure.relative($0, from: s) } } }
        }
        public private(set) var odometry: Expect?
        public var ended: Ended
        /// The sentence a row that did not finish ended with.
        public var said: String?
        public var tester: Marks?

        public init(run: Run, ranAt: Date, cardLog: [CardLog] = [], odomStart: Odom? = nil, odomEnd: Odom? = nil,
                    ended: Ended = .finished, said: String? = nil, tester: Marks? = nil) {
            self.id = run.id; self.cards = run.cards; self.expect = run.expect; self.ranAt = ranAt
            self.cardLog = cardLog; self.odomStart = odomStart; self.odomEnd = odomEnd
            self.odometry = odomStart.flatMap { s in odomEnd.map { DuckMeasure.relative($0, from: s) } }
            self.ended = ended; self.said = said; self.tester = tester
        }

        public var fell: Bool { cardLog.contains { $0.ended == .fell } }

        /// Every card done inside its pre-registered bound.
        public var inTime: Bool {
            !cardLog.isEmpty && cardLog.allSatisfy { log in
                guard let s = log.seconds else { return false }
                return s <= (log.card.hasPrefix("walk") ? Acceptance.walkSeconds : Acceptance.turnSeconds)
            }
        }

        /// Tape against the board: cm off the board's square, degrees off its heading. Nil until
        /// the tester has marked the row.
        public var positionErrorCm: Double? {
            guard let m = tester else { return nil }
            let df: Double = m.forwardCm - expect.forwardCm
            let dl: Double = m.leftCm - expect.leftCm
            return (df * df + dl * dl).squareRoot()
        }
        public var headingErrorDeg: Double? {
            guard let m = tester else { return nil }
            let radians: Double = (m.headingDeg - expect.headingDeg) * Double.pi / 180
            return abs(DuckCardLoop.wrap(radians)) * 180 / Double.pi
        }

        enum CodingKeys: String, CodingKey {
            case id, cards, expect, ranAt = "ran_at", cardLog = "card_log", odomStart = "odom_start",
                 odomEnd = "odom_end", odometry, ended, said, tester
        }
    }

    // MARK: - running one row

    public enum Refusal: Error, Equatable {
        case notConnected
        case noOdometry
        case fallen
        case pastTheEnvelope([String])

        public var message: String {
            switch self {
            case .notConnected:
                return "Connect a duck on the Robot tab first. Nothing was sent."
            case .noOdometry:
                return "This duck does not report where it is (no odom in robotd's state), so it cannot be "
                     + "measured. Nothing was sent."
            case .fallen:
                return "robotd says the duck is down. Stand it up in the start square and try again. Nothing was sent."
            case .pastTheEnvelope(let problems):
                return "The card spec asks for more than Pollen's pad allows ("
                     + problems.joined(separator: "; ") + "), so nothing was sent."
            }
        }
    }

    /// Checked before anything moves: a spec inside Pollen's envelope, a duck reporting odometry,
    /// and not down.
    public static func check(_ state: DuckState?, spec: DuckCardLoop.Spec = DuckCardLoop.spec,
                             envelope: DuckCardLoop.Envelope = DuckCardLoop.envelope) -> Refusal? {
        let problems = DuckCardLoop.envelopeProblems(spec, envelope: envelope)
        if !problems.isEmpty { return .pastTheEnvelope(problems) }
        if state?.safety?.fallen == true { return .fallen }
        if DuckCardLoop.pose(of: state) == nil { return .noOdometry }
        return nil
    }

    private actor Recorder {
        var record: RunRecord
        var began: [Int: Date] = [:]
        init(_ record: RunRecord) { self.record = record }
        func begin(_ i: Int, at: Date, odom: Odom?) {
            began[i] = at
            if record.cardLog.indices.contains(i) { record.cardLog[i].before = odom }
        }
        func end(_ i: Int, _ how: RobotPlanRunner.CardEnd, at: Date, odom: Odom?) {
            guard record.cardLog.indices.contains(i) else { return }
            record.cardLog[i].after = odom
            record.cardLog[i].ended = how
            if let t0 = began[i] { record.cardLog[i].seconds = at.timeIntervalSince(t0) }
        }
        func finish(_ ended: Ended, said: String?, odom: Odom?) {
            record.ended = ended; record.said = said; record.odomEnd = odom
        }
        func start(_ odom: Odom?) { record.odomStart = odom }
    }

    /// Run one row on a duck, recording odometry before and after each card. Throws a `Refusal`
    /// before moving; cancelling (Stop) ends it with the duck commanded still, as the runner always
    /// does, and is recorded as `cancelled`.
    public static func run(_ run: Run, on peer: any DuckPeer, interval: Double,
                           sleep: @escaping RobotPlanRunner.Sleep,
                           state: @escaping RobotPlanRunner.State,
                           now: @escaping @Sendable () -> Date = { Date() },
                           said: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> RunRecord {
        if let refusal = check(await state()) { throw refusal }
        let plan = try DuckMeasure.plan(run)
        let odom: @Sendable () async -> Odom? = {
            DuckCardLoop.pose(of: await state()).map { Odom($0) }
        }
        let recorder = Recorder(RunRecord(run: run, ranAt: now(), cardLog: run.cards.map { CardLog(card: $0) }))
        await recorder.start(await odom())
        do {
            let outcome = try await RobotPlanRunner.run(
                plan, on: peer, interval: interval, sleep: sleep,
                event: { event in
                    switch event {
                    case .began(let i, _): await recorder.begin(i, at: now(), odom: await odom())
                    case .cardEnded(let i, let how): await recorder.end(i, how, at: now(), odom: await odom())
                    case .said(let line): await said(line)
                    }
                },
                state: state, now: now)
            switch outcome {
            case .finished: await recorder.finish(.finished, said: nil, odom: await odom())
            case .stopped(_, let reason): await recorder.finish(.stopped, said: reason, odom: await odom())
            case .refused(_, let reason): await recorder.finish(.refused, said: reason, odom: await odom())
            }
        } catch is CancellationError {
            await recorder.finish(.cancelled, said: Words.cancelled, odom: await odom())
        }
        return await recorder.record
    }

    // MARK: - standing still

    /// How long the stand-still step holds the duck still.
    public static let stillSeconds = 30.0
    /// How often it keeps a sample of robotd's odometry while it does.
    public static let stillSampleS = 0.5

    /// One moment of the stand-still step: seconds since it began, and robotd's odometry.
    public struct StillSample: Equatable, Sendable, Codable {
        public let tS: Double, xM: Double, yM: Double, yawRad: Double
        public init(tS: Double, xM: Double, yM: Double, yawRad: Double) {
            self.tS = tS; self.xM = xM; self.yM = yM; self.yawRad = yawRad
        }
        enum CodingKeys: String, CodingKey { case tS = "t_s", xM = "x_m", yM = "y_m", yawRad = "yaw_rad" }
    }

    /// THE STAND-STILL STEP: how far a real duck's sensed heading moves while it is told to stand
    /// still (docs/PACKS.md, "Measure my duck"). The simulator's drift conditions were guessed;
    /// this is the number that would replace a guess, through a new, pre-registered condition.
    /// robotd's yaw rate standing still is drift plus whatever the duck truly turned; the tester's
    /// tape heading afterwards separates the two.
    public struct StillRecord: Equatable, Sendable, Codable {
        public let ranAt: Date
        public let seconds: Double
        public var samples: [StillSample]
        public var ended: Ended
        public var said: String?
        /// Degrees the duck truly turned left while standing, by the tape. Absent until typed.
        public var testerHeadingDeg: Double?

        public init(ranAt: Date, seconds: Double = DuckMeasure.stillSeconds, samples: [StillSample] = [],
                    ended: Ended = .finished, said: String? = nil, testerHeadingDeg: Double? = nil) {
            self.ranAt = ranAt; self.seconds = seconds; self.samples = samples
            self.ended = ended; self.said = said; self.testerHeadingDeg = testerHeadingDeg
        }

        /// robotd's yaw over the samples, unwrapped, in degrees from the first.
        public var yawDeg: [Double] {
            guard let first = samples.first else { return [] }
            var out: [Double] = [0], last = first.yawRad, total = 0.0
            for s in samples.dropFirst() {
                total += DuckCardLoop.wrap(s.yawRad - last); last = s.yawRad
                out.append(total * 180 / .pi)
            }
            return out
        }
        /// How far robotd's yaw moved from the first sample to the last, degrees.
        public var yawChangeDeg: Double? { samples.count >= 2 ? yawDeg.last : nil }
        /// The least-squares slope of robotd's yaw on time, degrees a second.
        public var yawRateDegPerS: Double? {
            guard samples.count >= 3 else { return nil }
            let t = samples.map(\.tS), y = yawDeg
            let n = Double(t.count), mt = t.reduce(0, +) / n, my = y.reduce(0, +) / n
            let sxx = zip(t, t).map { ($0 - mt) * ($1 - mt) }.reduce(0, +)
            guard sxx > 0 else { return nil }
            return zip(t, y).map { ($0 - mt) * ($1 - my) }.reduce(0, +) / sxx
        }
        /// How far robotd's odometry says the duck crept, cm.
        public var creepCm: Double? {
            guard let a = samples.first, let b = samples.last, samples.count >= 2 else { return nil }
            return ((b.xM - a.xM) * (b.xM - a.xM) + (b.yM - a.yM) * (b.yM - a.yM)).squareRoot() * 100
        }
        /// robotd's heading change less the tape's, over the time: the sensor's drift, degrees a second.
        public var driftDegPerS: Double? {
            guard let change = yawChangeDeg, let tape = testerHeadingDeg, let a = samples.first,
                  let b = samples.last, b.tS > a.tS else { return nil }
            return (change - tape) / (b.tS - a.tS)
        }

        enum CodingKeys: String, CodingKey {
            case ranAt = "ran_at", seconds, samples, ended, said, testerHeadingDeg = "tester_heading_deg",
                 yawChangeDeg = "yaw_change_deg", yawRateDegPerS = "yaw_rate_deg_per_s", creepCm = "creep_cm",
                 driftDegPerS = "drift_deg_per_s"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ranAt = try c.decode(Date.self, forKey: .ranAt)
            seconds = try c.decode(Double.self, forKey: .seconds)
            samples = try c.decode([StillSample].self, forKey: .samples)
            ended = try c.decode(Ended.self, forKey: .ended)
            said = try c.decodeIfPresent(String.self, forKey: .said)
            testerHeadingDeg = try c.decodeIfPresent(Double.self, forKey: .testerHeadingDeg)
        }

        /// The summaries are written into the file beside the samples, not only computed.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ranAt, forKey: .ranAt)
            try c.encode(seconds, forKey: .seconds)
            try c.encode(samples, forKey: .samples)
            try c.encode(ended, forKey: .ended)
            try c.encodeIfPresent(said, forKey: .said)
            try c.encodeIfPresent(testerHeadingDeg, forKey: .testerHeadingDeg)
            try c.encodeIfPresent(yawChangeDeg, forKey: .yawChangeDeg)
            try c.encodeIfPresent(yawRateDegPerS, forKey: .yawRateDegPerS)
            try c.encodeIfPresent(creepCm, forKey: .creepCm)
            try c.encodeIfPresent(driftDegPerS, forKey: .driftDegPerS)
        }
    }

    /// Hold the duck still for `seconds`, `robot.move` with a zero twist at the spec's rate (the
    /// deadmen need it), keeping robotd's odometry every `stillSampleS`. Refused before anything is
    /// sent as a row is; ends early, the duck still, on a fall or a pose gone stale; always ends in
    /// `robot.stop`. Stop (cancelling) is recorded as `cancelled`.
    public static func standStill(seconds: Double = stillSeconds, on peer: any DuckPeer,
                                  sleep: @escaping RobotPlanRunner.Sleep,
                                  state: @escaping RobotPlanRunner.State,
                                  now: @escaping @Sendable () -> Date = { Date() }) async throws -> StillRecord {
        if let refusal = check(await state()) { throw refusal }
        let t0 = now()
        var record = StillRecord(ranAt: t0, seconds: seconds)
        let tick = 1 / DuckCardLoop.spec.controlHz
        var nextSample = 0.0
        do {
            while true {
                try Task.checkCancellation()
                let t = now().timeIntervalSince(t0)
                let s = await state()
                if s?.safety?.fallen == true {
                    record.ended = .stopped; record.said = DuckCardLoop.fellNote; break
                }
                guard let s, now().timeIntervalSince(s.receivedAt) <= DuckCardLoop.spec.staleS,
                      let p = DuckCardLoop.pose(of: s) else {
                    record.ended = .stopped; record.said = DuckCardLoop.lostNote; break
                }
                if t + 1e-9 >= nextSample {
                    record.samples.append(.init(tS: t, xM: p.x, yM: p.y, yawRad: p.h))
                    nextSample += stillSampleS
                }
                if t >= seconds { break }
                try await peer.notify(.move(.still))
                try await sleep(tick)
            }
            try await peer.notify(.move(.still))
        } catch is CancellationError {
            record.ended = .cancelled; record.said = Words.cancelled
        } catch {
            _ = try? await peer.call(.stop)
            throw error
        }
        _ = try? await peer.call(.stop)
        return record
    }

    // MARK: - the report

    public struct Report: Equatable, Sendable, Codable {
        public struct EnvelopeUsed: Equatable, Sendable, Codable {
            public let source: String, commit: String
            public let vx: [Double], vy: [Double], vyaw: [Double]
        }
        public struct SpecUsed: Equatable, Sendable, Codable {
            public let digest: String
            public let enabledOnRobot: Bool
            public let squareM: Double
            enum CodingKeys: String, CodingKey { case digest, enabledOnRobot = "enabled_on_robot", squareM = "square_m" }
        }
        public let format: String
        public let madeAt: Date
        /// The app's version and build, as the app reports it.
        public let app: String
        /// The bridge's own name and version, if connected through one.
        public let bridge: String?
        /// robotd's version, when robotd says it; today it does not.
        public let robotd: String?
        /// The policy robotd said it was running (`robot.state` `policy`).
        public let policy: String?
        public let envelope: EnvelopeUsed
        public let spec: SpecUsed
        public let gridCm: Double
        public let runs: [RunRecord]
        /// The stand-still step, when it ran. Not judged by Acceptance.
        public let still: StillRecord?
        public let evaluation: Evaluation

        enum CodingKeys: String, CodingKey {
            case format, madeAt = "made_at", app, bridge, robotd, policy, envelope, spec, gridCm = "grid_cm", runs,
                 still, evaluation
        }

        /// The report as the tester shares it: sorted keys, ISO 8601 dates, pretty.
        public func json() throws -> Data {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            e.dateEncodingStrategy = .iso8601
            return try e.encode(self)
        }

        public static func read(_ data: Data) throws -> Report {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            let r = try d.decode(Report.self, from: data)
            guard r.format == DuckMeasure.format else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not \(DuckMeasure.format)"))
            }
            return r
        }

        public var fileName: String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd-HHmm"
            return "duck-measure-\(f.string(from: madeAt)).json"
        }
    }

    /// The sha256 of the shipped `duck-card-loop.json`, so a report names exactly which spec ran.
    public static var specDigest: String {
        guard let url = DuckCardLoop.specURL, let data = try? Data(contentsOf: url) else { return "unknown" }
        return digest(data)
    }

    static func digest(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func report(_ runs: [RunRecord], madeAt: Date, app: String, bridge: String?, robotd: String?,
                              policy: String?, spec: DuckCardLoop.Spec = DuckCardLoop.spec,
                              envelope env: DuckCardLoop.Envelope = DuckCardLoop.envelope,
                              specDigest: String = DuckMeasure.specDigest, still: StillRecord? = nil) -> Report {
        Report(format: format, madeAt: madeAt, app: app, bridge: bridge, robotd: robotd, policy: policy,
               envelope: .init(source: env.source, commit: env.commit, vx: env.vx, vy: env.vy, vyaw: env.vyaw),
               spec: .init(digest: specDigest, enabledOnRobot: spec.enabledOnRobot, squareM: spec.squareM),
               gridCm: spec.squareM * 100, runs: runs, still: still, evaluation: evaluate(runs))
    }

    // MARK: - against Acceptance

    public struct Evaluation: Equatable, Sendable, Codable {
        /// Rows that ran (not refused before moving, not cancelled).
        public let ran: Int
        /// Rows the tester marked with the tape.
        public let judged: Int
        public let positionWithin: Int
        public let headingWithin: Int
        /// Rows whose every card was inside its time bound.
        public let inTime: Int
        public let fell: Int
        /// Rows that ended some other way than finishing, and how many of them said why.
        public let endedBadly: Int
        public let endedBadlySaid: Int
        /// What it says, sentence by sentence.
        public let said: [String]

        enum CodingKeys: String, CodingKey {
            case ran, judged, positionWithin = "position_within", headingWithin = "heading_within",
                 inTime = "in_time", fell, endedBadly = "ended_badly", endedBadlySaid = "ended_badly_said", said
        }
    }

    public static func evaluate(_ runs: [RunRecord]) -> Evaluation {
        let ran = runs.filter { $0.ended == .finished || $0.ended == .stopped }
        let judged = ran.filter { $0.tester != nil }
        let position = judged.filter { ($0.positionErrorCm ?? .infinity) <= Acceptance.positionCm }.count
        let heading = judged.filter { ($0.headingErrorDeg ?? .infinity) <= Acceptance.headingDegrees }.count
        let inTime = ran.filter(\.inTime).count
        let fell = ran.filter(\.fell).count
        let badly = ran.filter { $0.ended == .stopped }
        let badlySaid = badly.filter { !($0.said ?? "").isEmpty }.count
        return Evaluation(ran: ran.count, judged: judged.count, positionWithin: position, headingWithin: heading,
                          inTime: inTime, fell: fell, endedBadly: badly.count, endedBadlySaid: badlySaid,
                          said: Words.evaluation(ran: ran.count, judged: judged.count, position: position,
                                                 heading: heading, inTime: inTime, fell: fell,
                                                 badly: badly.count, badlySaid: badlySaid))
    }

    // MARK: - words

    /// Every sentence the screen says, in the app's voice. No em dashes (`DuckMeasureTests`).
    public enum Words {
        public static let title = "Measure my duck"
        public static let entry = "Measure my duck"
        public static let entryFooter =
            "A test for a real duck: measured Walk and Turn cards on a taped grid, and a report you can share."

        public static let thisIsATest =
            "This is a test. On a duck, Walk and Turn cards are timed for now. This screen runs the measured "
          + "ones instead, which nothing else in the app does: the duck walks until its own odometry says one "
          + "square, and turns until its yaw says a quarter turn. You measure where it really ended with a tape. "
          + "Your report helps decide whether measured cards can be switched on for everyone."

        public static let gridHeading = "Lay the grid"
        public static func grid(squareCm: Double = DuckCardLoop.spec.squareM * 100) -> String {
            let sq = String(format: "%.0f", squareCm)
            return "On a flat, hard floor, tape a grid of \(sq) cm squares, five long and three wide. Mark the "
                 + "middle square of one short end as the start, and draw an arrow in it pointing down the long "
                 + "side. Before every run, stand the duck in the middle of the start square, facing the arrow. "
                 + "Film each run if you can, from above or from the side."
        }

        public static let marksHeading = "After each run, measure"
        public static let marks =
            "Forward: how far the middle of the duck is from the middle of the start square, along the arrow, "
          + "in cm. Behind the start is negative. Left: how far it is to the left of the arrow's line, in cm. "
          + "Right is negative. Heading: how far the duck has turned left from the arrow, in degrees. Right is negative."

        public static let safety =
            "Stay within reach of the duck. Stop zeroes the twist at once. A row also stops on its own, with the "
          + "duck told to stand still, if the duck falls, stops reporting where it is, or a card runs out of time."

        public static let runsHeading = "The runs"
        public static let forward = "Forward, cm"
        public static let left = "Left, cm"
        public static let heading = "Heading, degrees"
        public static let run = "Run"
        public static let stop = "Stop"
        public static let cancelled = "You pressed Stop, so the row stopped there."
        public static let needsDuck = "Connect a duck on the Robot tab to run these."
        public static let reportHeading = "Report"
        public static let share = "Share the report"
        public static let reportFooter =
            "A duck-measure/0 file: this app's build, the policy robotd reported, Pollen's envelope and the card "
          + "spec used, robotd's odometry before and after every card, and your marks. Nothing is sent anywhere "
          + "until you share it."

        public static let stillHeading = "Stand still"
        public static func still(seconds: Double = DuckMeasure.stillSeconds) -> String {
            String(format: "Stand the duck in the start square facing the arrow, press Run and leave it alone "
                 + "for %.0f s. It is told to stand still the whole time. This measures how far its own sense of "
                 + "heading wanders when nothing turns it, which is what makes long rows miss. Afterwards, type "
                 + "how far it really turned left from the arrow by the tape, in degrees (0 if it did not).", seconds)
        }
        public static let stillMark = "Turned by the tape, degrees"

        /// The stand-still step's line once it has run, and once it has been marked.
        public static func stillResult(_ r: StillRecord) -> String {
            var parts: [String] = []
            switch r.ended {
            case .finished: parts.append("Finished.")
            case .stopped, .refused, .cancelled: parts.append(r.said ?? "It stopped.")
            }
            if let change = r.yawChangeDeg, let rate = r.yawRateDegPerS, let creep = r.creepCm,
               let a = r.samples.first, let b = r.samples.last {
                parts.append(String(format: "Over %.0f s robotd's heading moved %.1f degrees (%.3f degrees a second) "
                                    + "and its position %.1f cm.", b.tS - a.tS, change, rate, creep))
            }
            if let drift = r.driftDegPerS {
                parts.append(String(format: "With your tape, its heading sensor drifted %.3f degrees a second, "
                                    + "%.0f degrees a minute.", drift, drift * 60))
            }
            return parts.joined(separator: " ")
        }

        public static func cardName(_ action: String) -> String {
            switch action {
            case "walk_forward": return "Walk forward"
            case "walk_backward": return "Walk back"
            case "turn_left": return "Turn left"
            case "turn_right": return "Turn right"
            default: return action
            }
        }

        public static func runTitle(_ run: Run) -> String {
            let n = run.cards.count
            let name = cardName(run.cards.first ?? "")
            return "\(n) \(name) card\(n == 1 ? "" : "s")"
        }

        public static func expect(_ run: Run) -> String {
            let e = run.expect
            if run.cards.allSatisfy({ $0.hasPrefix("turn") }) {
                return "On the board: back where it started, facing the arrow, after a full turn."
            }
            let squares = run.cards.count
            return String(format: "On the board: %d square%@ forward, %.0f cm, facing the arrow.",
                          squares, squares == 1 ? "" : "s", e.forwardCm)
        }

        /// What robotd's odometry said about a row, beside the tester's tape.
        public static func odometry(_ r: RunRecord) -> String? {
            guard let o = r.odometry else { return nil }
            return String(format: "robotd's odometry: %.1f cm forward, %.1f cm left, turned %.0f degrees.",
                          o.forwardCm, o.leftCm, o.headingDeg)
        }

        /// One row's line once it has run, and once it has been marked.
        public static func result(_ r: RunRecord) -> String {
            var parts: [String] = []
            switch r.ended {
            case .finished: parts.append("Finished.")
            case .stopped, .refused, .cancelled: parts.append(r.said ?? "It stopped.")
            }
            if let p = r.positionErrorCm, let h = r.headingErrorDeg {
                let pOK = p <= Acceptance.positionCm, hOK = h <= Acceptance.headingDegrees
                parts.append(String(format: "By your tape it ended %.1f cm from the board's square (%@ %.0f cm) and "
                                    + "%.0f degrees off its heading (%@ 15).", p, pOK ? "within" : "past",
                                    Acceptance.positionCm, h, hOK ? "within" : "past"))
            }
            let slow = r.cardLog.enumerated().filter { _, log in
                guard let s = log.seconds else { return false }
                return s > (log.card.hasPrefix("walk") ? Acceptance.walkSeconds : Acceptance.turnSeconds)
            }
            if !slow.isEmpty {
                parts.append("Card \(slow.map { String($0.offset + 1) }.joined(separator: ", ")) took longer than "
                             + "its time bound (Walk 8 s, Turn 6 s).")
            }
            return parts.joined(separator: " ")
        }

        static func evaluation(ran: Int, judged: Int, position: Int, heading: Int, inTime: Int, fell: Int,
                               badly: Int, badlySaid: Int) -> [String] {
            guard ran > 0 else { return ["No run has finished yet."] }
            var out: [String] = []
            let cm = String(format: "%.0f", Acceptance.positionCm)
            if judged == 0 {
                out.append("No run is marked yet, so nothing is judged. Odometry is recorded, but Acceptance judges by tape.")
            } else {
                out.append("\(judged) of \(ran) run\(ran == 1 ? "" : "s") marked by tape. Position: \(position) of "
                           + "\(judged) within \(cm) cm. Heading: \(heading) of \(judged) within 15 degrees.")
            }
            out.append("Time: \(inTime) of \(ran) with every card in its bound (Walk 8 s, Turn 6 s).")
            out.append(fell == 0 ? "No fall." : "\(fell) fell. Any fall on a real duck sends measured cards back to the simulator.")
            if badly > 0 {
                out.append("\(badly) ended early, \(badlySaid) of them saying why, with the duck told to stand still.")
            }
            out.append("One duck and a few runs cannot pass Acceptance alone: this is one tester's evidence for its "
                       + "last rung, judged with the same numbers.")
            return out
        }
    }
}
