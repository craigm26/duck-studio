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
/// WHAT `robot.stop` DOES AND DOES NOT DO, read from robotd (`intents.rs` `stop`, 1fa8438): it
/// zeroes the twist. It does not cancel a skill already running — a kick is half a second and
/// runs to its end. Every screen that runs one of these says so beside the button.
public struct RobotPlan: Equatable, Sendable {

    public enum Beat: Equatable, Sendable {
        /// Drive this twist for this long.
        case move(DuckDrive.Twist, seconds: Double, clause: String)
        /// Play one voice-bank sound.
        case sound(DuckSound, clause: String)
        /// Run one of the robot's skills by robotd's name, then wait for it.
        case skill(String, seconds: Double, clause: String)

        public var clause: String {
            switch self {
            case .move(_, _, let c), .sound(_, let c), .skill(_, _, let c): return c
            }
        }
    }

    public let request: String
    public let beats: [Beat]
    /// Parts of the plan that stay in it but are not sent, each said once.
    public let notSent: [String]

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

    /// The kept nodes, in their current order.
    public init(_ plan: DuckIntentPlan) throws {
        var beats: [Beat] = []
        var heads = false
        var total = 0.0
        for node in plan.nodes where !node.discarded && !node.isRefusal {
            if let slot = DuckIntentPlan.skills[node.action], let name = RobotPlan.robotdName[slot] {
                let s = RobotPlan.skillSeconds[name] ?? 1
                beats.append(.skill(name, seconds: s, clause: node.clause))
                total += s + RobotPlan.settleSeconds
                continue
            }
            if node.action == "make_sound" {
                let tag = RobotPlan.soundTags[node.labels["sound"] ?? "chirp"] ?? .chirp
                beats.append(.sound(tag, clause: node.clause))
                continue
            }
            guard let go = DuckIntentPlan.goes[node.action] else { continue }
            if (node.labels["head"] ?? "straight") != "straight" { heads = true }
            let share = node.action == "stop" ? 1
                : DuckIntentPlan.shares[node.labels["speed"] ?? "normal"] ?? 2.0 / 3.0
            let seconds = min(max(node.seconds, DuckDrive.holdSeconds), DuckSequence.maximumMoveSeconds)
            beats.append(.move(try SequenceProposal.twist(for: go, share: share),
                               seconds: seconds, clause: node.clause))
            total += seconds
        }
        guard !beats.isEmpty else { throw Refusal.nothingToRun }
        guard total <= DuckSequence.maximumSeconds else { throw Refusal.tooLong(total) }
        self.request = plan.request
        self.beats = beats
        self.notSent = heads
            ? ["Where the head looks is kept in the plan but not sent yet: a plan drives the body, "
             + "and the head stays where it is."]
            : []
    }

    public var skillNames: [String] {
        beats.compactMap { if case .skill(let n, _, _) = $0 { return n } else { return nil } }
    }

    public var methods: Set<DuckMethod> {
        var m: Set<DuckMethod> = [.stop]
        for beat in beats {
            switch beat {
            case .move: m.insert(.move)
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
    }

    public enum Outcome: Equatable, Sendable {
        case finished
        /// The robot refused a beat; the plan stopped there.
        case refused(beat: Int, reason: String)
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
                           event: @escaping @Sendable (Event) async -> Void = { _ in })
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
        do {
            for (i, beat) in plan.beats.enumerated() {
                await event(.began(i, beat))
                switch beat {
                case .move(let twist, let seconds, _):
                    try await hold(twist, for: seconds, on: peer, tick: tick, sleep: sleep)
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
                }
            }
        } catch {
            _ = try? await peer.call(.stop)
            throw error
        }
        _ = try await peer.call(.stop)
        return .finished
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
