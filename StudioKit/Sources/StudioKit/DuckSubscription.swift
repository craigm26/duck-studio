import Foundation

/// What a duck answers when it is asked to start talking — `robot.subscribe`'s
/// result, decoded.
///
/// WHY THIS TYPE EXISTS AT ALL, WHEN A REPLY IS ALREADY READABLE. `DuckReply`
/// hands back the `result` member as bytes and `field(_:)` pulls one key out of
/// it, which is enough for a screen that wants one number. This answer is not
/// that: it is six independent facts about a robot, three of them absent when
/// they are absent for opposite reasons, and every screen that read it with
/// `field(_:)` would be re-deciding what an absent `stand` means. It means "no
/// standing network is configured, so the walking network runs at every
/// velocity" — a real configuration, and one worth being able to see — and
/// deciding that in a view is how two views come to disagree about a robot.
///
/// TRANSCRIBED FROM `SubscribeResult`, NOT FROM A SUMMARY OF IT
/// (`duck-ipc-proto/src/lib.rs`, `pub struct SubscribeResult`). The wire names
/// are snake_case because that is what serde derives with no rename on the
/// fields: `ground_pick` is `ground_pick`, and a Swift-cased `groundPick` on
/// the wire is a key nothing would ever fill in. The Swift names are camelCase
/// and the mapping is in one place, below.
///
/// WHAT IT REPLACES. On a bench, "which networks does this thing hold" is
/// `GET /health`, and the Control tab has always read it there. A robot has no
/// such endpoint and never will: `robotd` owns its policy slots and reports
/// them exactly once, here, because they are constant for the life of the
/// process. So this is the honest answer to the same question over a link to
/// hardware, and it is a different answer rather than the same one wearing a
/// robot's name — the bench lists FILES IT COULD LOAD, and this names the
/// NETWORKS ALREADY RUNNING.
public struct DuckSubscription: Equatable, Sendable {

    /// Ask for every tick. The proto's own default: `SubscribeParams.hz` is
    /// documented "Absent means every tick", so nil is not a missing value
    /// here, it is a request for 50 Hz.
    public static let everyTick: Int? = nil

    /// What a screen that draws a line of text should ask for.
    ///
    /// TEN, AND THE NUMBER IS A DECISION ABOUT A PHONE RATHER THAN ABOUT A
    /// ROBOT. Decimation is per-subscriber and server-side — the proto says a
    /// dashboard asking for 10 Hz costs the robot a tenth of what a digital
    /// twin asking for 50 Hz does, and that neither can slow the control loop —
    /// so the only thing 50 Hz would buy a readout is forty extra states a
    /// second to throw away, on a battery.
    public static let watchingRateHz = 10

    /// Whether the daemon accepted the subscription. False is not an error:
    /// it is a robot saying no, which is a different thing from a link that
    /// broke, and `DuckReply` keeps that distinction for the same reason.
    public let accepted: Bool

    /// The walking network's file name, when one is loaded.
    public let walk: String?

    /// The standing network's file name. NIL IS A CONFIGURATION AND NOT A
    /// FAULT: without it the walking policy runs at every velocity.
    public let stand: String?

    /// Why nothing is driving, when nothing is — the policy is disabled in
    /// params, or it was wanted and could not be loaded. The proto is explicit
    /// that those are different situations and that both are invisible in a
    /// stream whose `policy` field just says `held`.
    public let unavailable: String?

    public let sitstand: String?
    public let groundPick: String?

    /// The one-shot skills this robot has, in priority order, and the names
    /// `robot.do` answers to. A LIST RATHER THAN A FIELD PER SKILL, because
    /// which skills a robot has is config: a client learns them here instead of
    /// assuming five.
    public let skills: [String]

    public init(accepted: Bool, walk: String? = nil, stand: String? = nil,
                unavailable: String? = nil, sitstand: String? = nil,
                groundPick: String? = nil, skills: [String] = []) {
        self.accepted = accepted
        self.walk = walk
        self.stand = stand
        self.unavailable = unavailable
        self.sitstand = sitstand
        self.groundPick = groundPick
        self.skills = skills
    }

    /// Read the answer to `DuckCall.subscribe`.
    ///
    /// IT DOES NOT THROW FOR A REFUSAL. A robot that answered `error` has
    /// answered, and `DuckReply.failure` already carries that sentence to the
    /// screen; this only throws when a reply that claimed to be a result was
    /// not one this app can read.
    public static func read(_ reply: DuckReply) throws -> DuckSubscription {
        guard let result = reply.result,
              let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any]
        else { throw ReadError.notASubscription }
        return DuckSubscription(
            accepted: object["accepted"] as? Bool ?? false,
            walk: object["walk"] as? String,
            stand: object["stand"] as? String,
            unavailable: object["unavailable"] as? String,
            sitstand: object["sitstand"] as? String,
            groundPick: object["ground_pick"] as? String,
            skills: object["skills"] as? [String] ?? [])
    }

    public enum ReadError: Error, Equatable {
        case notASubscription

        public var message: String {
            "That duck answered robot.subscribe with something this app could not read as a "
          + "subscription. Nothing is being streamed, so the state line below stays empty rather "
          + "than showing a robot that was never described."
        }
    }

    // MARK: - what it says

    /// The networks, in one line, or nil when the robot named none.
    ///
    /// NIL RATHER THAN "none": a robot that named no networks at all is a
    /// robot whose `unavailable` is the interesting field, and printing "none"
    /// over the top of it would bury the reason.
    public var networksSaid: String? {
        var parts: [String] = []
        if let walk { parts.append("walk \(walk)") }
        if let stand { parts.append("stand \(stand)") }
        if let sitstand { parts.append("sitstand \(sitstand)") }
        if let groundPick { parts.append("ground pick \(groundPick)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What a person should read about this robot's policy slots, said in the
    /// robot's own terms and never inventing a slot it did not name.
    public var says: String {
        if !accepted {
            return "This robot did not accept the subscription, so nothing is streaming from it. "
                 + "Driving still works — a twist is a notification and needs no stream — but "
                 + "nothing below will change while it walks."
        }
        if let unavailable {
            return "Nothing is driving this robot: \(unavailable). It will hold its pose under a "
                 + "twist rather than walk, and that is the robot reporting a configuration "
                 + "rather than a link going wrong."
        }
        guard let networksSaid else {
            return "This robot accepted the subscription and named no networks. With no walking "
                 + "policy loaded it holds its pose; robot.init still works, because standing up "
                 + "is a reasonable thing to ask of a robot with no walking network."
        }
        var line = "Running: \(networksSaid)."
        if stand == nil, walk != nil {
            line += " No standing network is configured, so the walking one runs at every velocity."
        }
        if !skills.isEmpty {
            line += " Skills: \(skills.joined(separator: ", "))."
        }
        return line
    }

    /// The sentence for a link that has not asked yet.
    ///
    /// SAID RATHER THAN LEFT BLANK, because an empty panel under a connected
    /// robot reads as a robot that has nothing to say, and this one has not
    /// been asked.
    public static let notAskedYet =
        "Nothing has been asked of this robot yet. robotd answers no method that reads its state "
      + "— it pushes robot.state to connections that subscribed — so until this app subscribes, a "
      + "silent link and a still duck look exactly the same."
}
