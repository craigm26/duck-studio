import Foundation
import DuckKit
import DuckEvidence

/// A plan as a real duck runs it: twists for their seconds, sounds by tag, and skills by the
/// name robotd answers to.
///
/// WHY THIS IS NOT THE BENCH'S PATH. On a bench a plan becomes a `DuckSequence` the pilot plays
/// against the bench's sim clock, and its one skill is a network loaded when the moves finish.
/// A robot has neither: there is no sim clock on a duck standing on a floor, and robotd owns its
/// slots. What robotd has instead is `robot.do`, which runs a configured skill and hands the duck
/// back to its gait when it ends — so on a robot a skill may sit anywhere in a plan, and a
/// plan may hold more than one.
///
/// THE NUMBERS ARE STILL THIS APP'S. Every twist comes from `SequenceProposal.twist(for:share:)`,
/// the same door the bench path resolves through, so slow, normal and fast mean the same thing
/// on both and nothing a model said about a velocity reaches a motor.
///
/// A DUCK CARD'S WALK AND TURN ARE TIMED ON A DUCK FOR NOW. Closed-loop cards ship off for real
/// ducks (`DuckCardLoop.spec.enabledOnRobot`, docs/PACKS.md "Acceptance"): a plan read off Duck
/// Cards runs Walk and Turn as `.move` beats, two seconds each, and says `DuckCardLoop.offNote`
/// once (`cardsTimed`). With measured cards on (the spec's switch, or `measuredCards: true`, which
/// only "Measure my duck" passes), they become `.card` beats, which `RobotPlanRunner` closes on
/// robotd's odometry (`DuckCardLoop`) when the duck reports it, and runs as the timed twist they
/// carry when it does not. Every other plan, and every other card, is unchanged.
///
/// WHAT `robot.stop` DOES AND DOES NOT DO, read from robotd (`intents.rs` `stop`, 1fa8438): it
/// zeroes the twist. It does not cancel a skill already running — a kick is half a second and
/// runs to its end. Every screen that runs one of these says so beside the button.
public struct RobotPlan: Equatable, Sendable {

    public enum Beat: Equatable, Sendable {
        /// Drive this twist for this long.
        case move(DuckDrive.Twist, seconds: Double, clause: String)
        /// A Duck Card's Walk or Turn: one board square or a quarter turn on odometry
        /// (`DuckCardLoop`), or, on a duck that does not report odometry, `timed` for `seconds`.
        case card(String, speed: String?, timed: DuckDrive.Twist, seconds: Double, clause: String)
        /// Play one voice-bank sound.
        case sound(DuckSound, clause: String)
        /// Run one of the robot's skills by robotd's name, then wait for it.
        case skill(String, seconds: Double, clause: String)

        public var clause: String {
            switch self {
            case .move(_, _, let c), .sound(_, let c), .skill(_, _, let c), .card(_, _, _, _, let c): return c
            }
        }
    }

    public let request: String
    public let beats: [Beat]
    /// Parts of the plan that stay in it but are not sent, each said once.
    public let notSent: [String]
    /// A Duck Cards plan whose Walk and Turn run timed because measured cards are off: the screen
    /// and the runner say `DuckCardLoop.offNote`.
    public let cardsTimed: Bool
    /// Which beats are a Duck Card's Walk or Turn, timed or closed on odometry: what a row's
    /// chapters count (duck-card-loop/6, `chapters`).
    public let cardBeats: [Bool]

    /// The plan's skill labels as the names a stock robotd answers to (`do_names`, robotd
    /// 1fa8438: `ground_pick` and `sit_toggle` are built in; the kicks and the roll are the
    /// configured one-shots of Pollen's set).
    public static let robotdName: [DuckOfficialPolicies.Slot: String] = [
        .kickLeft: "kick_left", .kickRight: "kick_right", .sitstand: "sit_toggle",
        .roulade: "roulade", .groundPick: "ground_pick",
    ]

    /// How long each skill holds the duck, from Pollen's set manifest (d5a8b55): kicks 0.5 s,
    /// roulade 1.0 s, ground pick 2.8 s; sit/stand is scripted with a 1.0 s unwind and the
    /// posture change before it, so two seconds. A configured skill's own `duration` from
    /// `robot.skills` wins over these when the robot reports one.
    public static let skillSeconds: [String: Double] = [
        "kick_left": 0.5, "kick_right": 0.5, "roulade": 1.0, "ground_pick": 2.8, "sit_toggle": 2.0,
    ]

    /// Time after a skill for the gait to take the duck back before the next beat.
    public static let settleSeconds = 1.0

    public static let soundTags: [String: DuckSound] =
        Dictionary(uniqueKeysWithValues: DuckSound.allCases.map { ($0.rawValue, $0) })

    public enum Refusal: Error, Equatable {
        case nothingToRun
        case tooLong(Double)

        public var message: String {
            switch self {
            case .nothingToRun:
                return "Every step is discarded or refused, so there is nothing to send. Keep at "
                     + "least one movement, sound or skill."
            case .tooLong(let s):
                return String(format: "This plan runs %.0f s, and a plan on a duck is held to "
                            + "%.0f s so somebody is still watching when it ends. Shorten a "
                            + "step or discard one.", s, DuckSequence.maximumSeconds)
            }
        }
    }

    /// The kept nodes, in their current order. `measuredCards` is the spec's off switch unless a
    /// caller that runs a test on purpose says otherwise.
    public init(_ plan: DuckIntentPlan, measuredCards: Bool = DuckCardLoop.spec.enabledOnRobot) throws {
        var beats: [Beat] = []
        var isCard: [Bool] = []
        var heads = false
        var timed = false
        let cards = plan.model == DuckCards.model
        var total = 0.0
        for node in plan.nodes where !node.discarded && !node.isRefusal {
            if let slot = DuckIntentPlan.skills[node.action], let name = RobotPlan.robotdName[slot] {
                let s = RobotPlan.skillSeconds[name] ?? 1
                beats.append(.skill(name, seconds: s, clause: node.clause))
                isCard.append(false)
                total += s + RobotPlan.settleSeconds
                continue
            }
            if node.action == "make_sound" {
                let tag = RobotPlan.soundTags[node.labels["sound"] ?? "chirp"] ?? .chirp
                beats.append(.sound(tag, clause: node.clause))
                isCard.append(false)
                continue
            }
            guard let go = DuckIntentPlan.goes[node.action] else { continue }
            if (node.labels["head"] ?? "straight") != "straight" { heads = true }
            let share = node.action == "stop" ? 1
                : DuckIntentPlan.shares[node.labels["speed"] ?? "normal"] ?? 2.0 / 3.0
            let seconds = min(max(node.seconds, DuckDrive.holdSeconds), DuckSequence.maximumMoveSeconds)
            let twist = try SequenceProposal.twist(for: go, share: share)
            if cards && DuckCardLoop.cards.contains(node.action) && measuredCards {
                beats.append(.card(node.action, speed: node.labels["speed"], timed: twist, seconds: seconds,
                                   clause: node.clause))
            } else {
                if cards && DuckCardLoop.cards.contains(node.action) { timed = true }
                beats.append(.move(twist, seconds: seconds, clause: node.clause))
            }
            isCard.append(cards && DuckCardLoop.cards.contains(node.action))
            total += seconds
        }
        guard !beats.isEmpty else { throw Refusal.nothingToRun }
        guard total <= DuckSequence.maximumSeconds else { throw Refusal.tooLong(total) }
        self.request = plan.request
        self.beats = beats
        self.cardsTimed = timed
        self.cardBeats = isCard
        self.notSent = heads
            ? ["Where the head looks is kept in the plan but not sent yet: a plan drives the body, "
             + "and the head stays where it is."]
            : []
    }

    /// The chapters a duck plays this row in, as beats each (duck-card-loop/6): one unless it
    /// has more Walk and Turn cards than the spec's `chapters.cards`.
    public var chapters: [Int] { DuckCardLoop.chapters(cardBeats) }

    /// Whether any beat is a Duck Card's Walk or Turn, which closes on robotd's odometry and so
    /// wants the state stream while the plan runs.
    public var closesOnOdometry: Bool {
        beats.contains { if case .card = $0 { return true } else { return false } }
    }

    public var skillNames: [String] {
        beats.compactMap { if case .skill(let n, _, _) = $0 { return n } else { return nil } }
    }

    public var methods: Set<DuckMethod> {
        var m: Set<DuckMethod> = [.stop]
        for beat in beats {
            switch beat {
            case .move, .card: m.insert(.move)
            case .sound: m.insert(.sound)
            case .skill: m.formUnion([.skills, .doSkill, .move])
            }
        }
        return m
    }

    /// One beat as a person reads it before pressing Run.
    public static func spelled(_ beat: Beat) -> String {
        switch beat {
        case .move(let t, let s, _):
            return String(format: "%.1f s at vx %.2f, vy %.2f, vyaw %.2f", s, t.vx, t.vy, t.vyaw)
        case .card(let action, let speed, let t, let s, _):
            return DuckCardLoop.spelled(action, speed: speed) + String(
                format: "; without odometry, %.1f s at vx %.2f, vyaw %.2f", s, t.vx, t.vyaw)
        case .sound(let tag, _):
            return "Sound: \(tag.rawValue)"
        case .skill(let name, let s, _):
            return String(format: "Skill: %@, about %.1f s", name, s)
        }
    }

    /// Said beside the Run button, every time.
    public static let stopDoesNotCancelASkill =
        "Stop ends the plan and zeroes the twist. It does not cancel a skill already running: a "
      + "kick or a roll runs to its end, so stand within reach of the duck."
}

// MARK: - what a robot says it can do

/// `robot.skills`, read (`SkillsResult {skills: [SkillParams], built_in}`, duck-ipc-proto).
public struct RobotSkills: Equatable, Sendable {
    /// Every name `robot.do` answers to: the configured table, then the built-ins.
    public let names: [String]
    /// Seconds per configured skill, where the robot says.
    public let seconds: [String: Double]

    public init(names: [String], seconds: [String: Double] = [:]) {
        self.names = names; self.seconds = seconds
    }

    public static func read(_ reply: DuckReply) -> RobotSkills? {
        guard let data = reply.result,
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var names: [String] = [], seconds: [String: Double] = [:]
        for row in top["skills"] as? [[String: Any]] ?? [] {
            guard let n = row["name"] as? String else { continue }
            names.append(n)
            if let d = row["duration"] as? Double { seconds[n] = d }
            else if let d = row["duration"] as? Int { seconds[n] = Double(d) }
        }
        names += (top["built_in"] as? [String] ?? []).filter { !names.contains($0) }
        return RobotSkills(names: names, seconds: seconds)
    }
}

/// robotd's `IntentResult {accepted, reason?}`: a refusal is a normal answer with a reason.
public struct RobotIntentAnswer: Equatable, Sendable {
    public let accepted: Bool
    public let reason: String?

    public static func read(_ reply: DuckReply) -> RobotIntentAnswer {
        if let failure = reply.failure { return .init(accepted: false, reason: failure.says) }
        guard let accepted: Bool = reply.field("accepted") else {
            return .init(accepted: false, reason: "The duck answered without saying whether it accepted.")
        }
        return .init(accepted: accepted, reason: reply.field("reason"))
    }
}

// MARK: - running one

/// Runs a `RobotPlan` on a peer that reaches robotd, on the wall clock.
///
/// CHECKED BEFORE ANYTHING MOVES. The link must carry every method the plan uses, and every
/// skill it names must be one this robot listed in `robot.skills`. A plan that would kick
/// halfway through and then find the duck has no kick is refused at the start, with the list.
///
/// THE LINK IS FED THROUGHOUT. A move streams `robot.move` at `interval`; a skill is followed
/// by `.still` at the same rate until it has had its time. The bridge's deadman sends a stop on
/// 700 ms of silence, and robotd's own twist deadman is shorter still, so a gap here would be
/// a plan that stops itself.
///
/// IT ALWAYS ENDS IN `robot.stop`, finished, refused or cancelled.
public enum RobotPlanRunner {

    public typealias Sleep = @Sendable (Double) async throws -> Void

    public enum Event: Equatable, Sendable {
        case began(Int, RobotPlan.Beat)
        case said(String)
        /// A closed-loop card ended: how (`CardEnd`), before the still moment after it.
        case cardEnded(Int, CardEnd)
    }

    /// How a closed-loop Walk or Turn card ended. Anything but `reached` ends the row there, with
    /// the duck commanded still and one sentence (docs/PACKS.md, "Acceptance": a stuck, stale,
    /// fallen or cannot-reach row ends safely and says which).
    public enum CardEnd: String, Equatable, Sendable, Codable {
        case reached
        /// The pose stopped arriving, or was older than the spec's `stale_s`.
        case lost
        /// robotd's `safety.fallen` said the duck is down.
        case fell
        case outOfTime = "out of time"
        case trimmedOut = "trimmed out"
        /// No progress for the spec's `stall_s` (DuckCardLoop.Done.stuck).
        case stuck

        /// What a person hears when a card ends some other way than arriving. The card reader
        /// says the same sentences (`runner.ENDED`).
        public var said: String? {
            switch self {
            case .reached: return nil
            case .lost: return DuckCardLoop.lostNote
            case .fell: return DuckCardLoop.fellNote
            case .outOfTime: return "The card ran out of time before it got there, so the row stopped there."
            case .trimmedOut: return "The card stopped short of a quarter turn after its trims, so the row stopped there."
            case .stuck: return "The duck could not do this card at the speeds it may be sent, so the row stopped there."
            }
        }
    }

    /// Asked before chapter `k` of `of` (duck-card-loop/6), the duck still and
    /// `DuckCardLoop.nestNote` said: returns once a person has put the duck back on the nest.
    public typealias Nest = @Sendable (_ k: Int, _ of: Int) async throws -> Void

    /// The latest `robot.state` the link has seen, or nil. Walk and Turn cards close on its
    /// `odom` (`DuckCardLoop`); a duck that sends none runs them timed.
    public typealias State = @Sendable () async -> DuckState?

    public enum Outcome: Equatable, Sendable {
        case finished
        /// The robot refused a beat; the plan stopped there.
        case refused(beat: Int, reason: String)
        /// A closed-loop card did not arrive (lost, fell, out of time, trimmed out); the plan
        /// stopped there, the duck commanded still.
        case stopped(beat: Int, reason: String)
    }

    public enum Refusal: Error, Equatable {
        case outOfReach(DuckMethod, DuckTransportKind)
        case noSkillList(String)
        case missingSkills([String], has: [String])

        public var message: String {
            switch self {
            case .outOfReach(let m, let t):
                return DuckCall.Misuse.outOfReach(m, t).message + " This plan needs it."
            case .noSkillList(let why):
                return "The duck did not say which skills it has, so a plan that asks for one was "
                     + "not started. \(why)"
            case .missingSkills(let missing, let has):
                return "This duck has no \(missing.joined(separator: ", ")). It has "
                     + (has.isEmpty ? "no skills configured" : has.joined(separator: ", "))
                     + ". Nothing was sent."
            }
        }
    }

    /// Run it. Throws a `Refusal` before moving, or whatever the link threw mid-run (after
    /// sending a best-effort stop).
    public static func run(_ plan: RobotPlan, on peer: any DuckPeer, interval: Double,
                           sleep: @escaping Sleep,
                           event: @escaping @Sendable (Event) async -> Void = { _ in },
                           state: State? = nil,
                           now: @escaping @Sendable () -> Date = { Date() },
                           nest: Nest? = nil,
                           merge: Bool = true)
        async throws -> Outcome {
        for m in plan.methods.sorted(by: { $0.rawValue < $1.rawValue }) where !peer.reach.contains(m) {
            throw Refusal.outOfReach(m, peer.transportKind)
        }
        var skills = RobotSkills(names: [])
        if !plan.skillNames.isEmpty {
            let reply = try await peer.call(.skills)
            if let failure = reply.failure { throw Refusal.noSkillList(failure.says) }
            guard let read = RobotSkills.read(reply) else {
                throw Refusal.noSkillList("Its answer had no skill list in it.")
            }
            let missing = plan.skillNames.filter { !read.names.contains($0) }
            var seen = Set<String>()
            let unique = missing.filter { seen.insert($0).inserted }
            guard unique.isEmpty else { throw Refusal.missingSkills(unique, has: read.names) }
            skills = read
        }
        let tick = max(interval, 0.02)
        var board: DuckCardLoop.Pose?
        var timedSaid = false
        // Every Turn card's measured coast this row; their mean is each later Turn card's lead.
        var coasts: [Double] = []
        if plan.cardsTimed { await event(.said(DuckCardLoop.offNote)) }
        let rawPose: @Sendable () async -> (t: Double, pose: DuckCardLoop.Pose)? = {
            guard let state, let s = await state(),
                  now().timeIntervalSince(s.receivedAt) <= DuckCardLoop.spec.staleS,
                  let p = DuckCardLoop.pose(of: s) else { return nil }
            return (s.receivedAt.timeIntervalSince1970, p)
        }
        // duck-card-loop/3: the drift measured standing still is taken out of every pose.
        let cal: Calibration? = DuckCardLoop.spec.calibrate.map { Calibration(DuckCardLoop.DriftCal($0)) }
        let pose: @Sendable () async -> DuckCardLoop.Pose? = {
            guard let got = await rawPose() else { return nil }
            guard let cal else { return got.pose }
            return await cal.correct(t: got.t, got.pose)
        }
        let fallen: @Sendable () async -> Bool = {
            guard let state, let s = await state() else { return false }
            return s.safety?.fallen == true
        }
        do {
            if let cal, let c = DuckCardLoop.spec.calibrate,
               plan.beats.contains(where: { if case .card = $0 { return true } else { return false } }),
               await rawPose() != nil {
                try await still(for: c.beforeS, cal: cal, rawPose: rawPose, on: peer, tick: tick, sleep: sleep)
            }
            // duck-card-loop/6: where each later chapter begins, as a beat index. Only with a `nest`
            // to ask for the re-seat; without one a row plays whole. Timed cards are counted too:
            // a timed duck lands on no square, so the nest is where a child puts it back on one.
            let parts = nest != nil ? plan.chapters : [plan.beats.count]
            let starts = parts.dropLast().reduce(into: [Int]()) { $0.append(($0.last ?? 0) + $1) }
            // duck-card-loop/5: each beat's card and speed, for runs of cards that go as one.
            let runs: [(action: String, speed: String?)?] = plan.beats.map {
                if case .card(let a, let sp, _, _, _) = $0 { return (a, sp) } else { return nil }
            }
            var i = -1
            while i + 1 < plan.beats.count {
                i += 1
                let beat = plan.beats[i]
                if let k = starts.firstIndex(of: i), let nest {
                    // A CHAPTER ENDS STILL, AND THE NEXT BEGINS WHERE THE DUCK WAS PUT DOWN.
                    _ = try await peer.call(.stop)
                    await event(.said(DuckCardLoop.nestNote(k + 2, of: parts.count)))
                    try await nest(k + 2, parts.count)
                    board = nil
                    coasts = []
                }
                await event(.began(i, beat))
                switch beat {
                case .move(let twist, let seconds, _):
                    try await hold(twist, for: seconds, on: peer, tick: tick, sleep: sleep)
                case .card(let action, let speed, let timed, let seconds, _):
                    // A ROW THAT HAS BEEN CLOSING ON ODOMETRY DOES NOT FALL BACK TO TIMED MID-ROW.
                    // The pose going missing between cards is the duck losing its state: the row ends.
                    if board != nil, await pose() == nil {
                        await event(.cardEnded(i, .lost))
                        await event(.said(DuckCardLoop.lostNote))
                        _ = try await peer.call(.stop)
                        return .stopped(beat: i, reason: DuckCardLoop.lostNote)
                    }
                    let end = starts.first(where: { $0 > i }) ?? plan.beats.count
                    let n = merge ? DuckCardLoop.merged(Array(runs[..<end]), at: i) : 1
                    guard let here = await pose(),
                          var card = DuckCardLoop.Card(action: action, board: board ?? here, speed: speed,
                                                       leadDeg: coasts.isEmpty ? nil : coasts.reduce(0, +) / Double(coasts.count),
                                                       cards: n) else {
                        if !timedSaid { await event(.said(DuckCardLoop.timedNote)); timedSaid = true }
                        try await hold(timed, for: seconds, on: peer, tick: tick, sleep: sleep)
                        board = nil
                        continue
                    }
                    for later in (i + 1)..<(i + n) { await event(.began(later, plan.beats[later])) }
                    i += n - 1
                    let ended = try await drive(&card, on: peer, pose: pose, fallen: fallen, sleep: sleep)
                    board = card.boardAfter
                    if let c = card.coastDeg { coasts.append(c) }
                    await event(.cardEnded(i, ended))
                    if let words = ended.said {
                        await event(.said(words))
                        _ = try await peer.call(.stop)
                        return .stopped(beat: i, reason: words)
                    }
                    if let cal {
                        try await still(for: DuckCardLoop.spec.betweenS, cal: cal, rawPose: rawPose,
                                        on: peer, tick: tick, sleep: sleep)
                    } else {
                        try await hold(.still, for: DuckCardLoop.spec.betweenS, on: peer, tick: tick, sleep: sleep)
                    }
                case .sound(let tag, _):
                    let answer = RobotIntentAnswer.read(try await peer.call(.sound(tag)))
                    if !answer.accepted {
                        // A SOUND IS NOT WORTH STOPPING A PLAN FOR. Said, and carried on.
                        await event(.said(answer.reason ?? "The duck did not play \(tag.rawValue)."))
                    }
                case .skill(let name, let seconds, _):
                    // A SKILL STARTS FROM A ZERO TWIST, as a button press on padd does.
                    _ = try await peer.call(.stop)
                    let answer = RobotIntentAnswer.read(try await peer.call(.doSkill(name)))
                    guard answer.accepted else {
                        _ = try? await peer.call(.stop)
                        return .refused(beat: i, reason: answer.reason ?? "The duck refused \(name).")
                    }
                    let wait = (skills.seconds[name] ?? seconds) + RobotPlan.settleSeconds
                    try await hold(.still, for: wait, on: peer, tick: tick, sleep: sleep)
                    // A SKILL MOVES THE DUCK IN WAYS THE BOARD DOES NOT COUNT: the board's square
                    // is put back where the duck stands, and its heading is kept.
                    if let b = board {
                        board = await pose().map { DuckCardLoop.Pose(x: $0.x, y: $0.y, h: b.h) }
                    }
                }
            }
        } catch {
            _ = try? await peer.call(.stop)
            throw error
        }
        _ = try await peer.call(.stop)
        return .finished
    }

    /// One Walk or Turn card on odometry, `robot.move` at the spec's rate, ending in a zero twist.
    /// Answers how it ended: the controller's own exits, a pose gone stale, or a fall.
    private static func drive(_ card: inout DuckCardLoop.Card, on peer: any DuckPeer,
                              pose: @Sendable () async -> DuckCardLoop.Pose?,
                              fallen: @Sendable () async -> Bool, sleep: Sleep) async throws -> CardEnd {
        let tick = 1 / DuckCardLoop.spec.controlHz
        var n = 0
        while true {
            try Task.checkCancellation()
            if await fallen() {
                try await peer.notify(.move(.still))
                return .fell
            }
            guard let here = await pose() else {
                try await peer.notify(.move(.still))
                return .lost
            }
            switch card.step(here, t: Double(n) * tick) {
            case .done(let done):
                try await peer.notify(.move(.still))
                switch done {
                case .reached: return .reached
                case .outOfTime: return .outOfTime
                case .trimmedOut: return .trimmedOut
                case .stuck: return .stuck
                }
            case .send(let vx, let vyaw):
                try await peer.notify(.move(DuckDrive.Twist(vx: vx, vy: 0, vyaw: vyaw)))
            }
            try await sleep(tick)
            n += 1
        }
    }

    /// `DuckCardLoop.DriftCal`, shared between the pose the controller reads and the still windows.
    actor Calibration {
        var cal: DuckCardLoop.DriftCal
        init(_ cal: DuckCardLoop.DriftCal) { self.cal = cal }
        func correct(t: Double, _ pose: DuckCardLoop.Pose) -> DuckCardLoop.Pose { cal.correct(t: t, pose) }
        func begin() { cal.beginStill() }
        func sample(t: Double, yaw: Double) { cal.sampleStill(t: t, yaw: yaw) }
        func end() { cal.endStill() }
    }

    /// `hold(.still)`, feeding each raw odometry yaw to the calibration as one still window.
    private static func still(for seconds: Double, cal: Calibration,
                              rawPose: @Sendable () async -> (t: Double, pose: DuckCardLoop.Pose)?,
                              on peer: any DuckPeer, tick: Double, sleep: Sleep) async throws {
        await cal.begin()
        for _ in 0..<max(1, Int((seconds / tick).rounded())) {
            try Task.checkCancellation()
            try await peer.notify(.move(.still))
            if let got = await rawPose() { await cal.sample(t: got.t, yaw: got.pose.h) }
            try await sleep(tick)
        }
        await cal.end()
    }

    private static func hold(_ twist: DuckDrive.Twist, for seconds: Double, on peer: any DuckPeer,
                             tick: Double, sleep: Sleep) async throws {
        let n = max(1, Int((seconds / tick).rounded()))
        for _ in 0..<n {
            try Task.checkCancellation()
            try await peer.notify(.move(twist))
            try await sleep(tick)
        }
    }
}
