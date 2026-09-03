import Foundation
import DuckKit

/// A recording of what YOU drove, stamped on the bench's own clock.
///
/// THE THIRD WORD, AND THE TEST THAT KEEPS ALL THREE APART. A **policy** is a
/// trained network on a bench; nothing in this file trains, edits or records
/// one. A **motion** is a keyframe track somebody authored joint by joint, and
/// it travels as `.duckintent`. A **sequence** is neither: it is the stick
/// commands somebody sent, the sim times they were sent at, and the networks
/// the bench reported while they were driving. A macro, not a skill.
/// `IntentExport` chose its file extension specifically so a motion and a
/// network could not be confused; this gets the same protection twice — a unit
/// test over every shipped sentence, and a repo script over the files.
///
/// THE CLOCK IS THE BENCH'S AND THERE IS NO SECOND ONE. `Step.atSim` is an
/// offset into the bench's own sim seconds, which is the same unit
/// `DuckBench.Step.at` is in, which is why `benchSchedule()` is a rename rather
/// than a conversion. Wall time is measured, stored and PRINTED — a person
/// waiting nineteen seconds for three seconds of duck deserves to be told why —
/// and it is never a time base: two takes with identical steps and different
/// wall seconds produce identical schedules, and a test pins that.
///
/// IT STORES THE MEASUREMENT, NOT THE DERIVED THING, which is `DuckPlanFile`'s
/// rule and this follows it. The file holds the captured twists, the times and
/// the bench's own network names; `benchSchedule()`, `summary`, `benchPolicy`
/// and `benchRefusal` are computed on every read, so a sequence written last
/// month cannot disagree with the app that opens it and win.
public struct DuckSequence: Equatable, Sendable, Identifiable {

    public static let format = "duck-sequence/1"
    public static let readableFormats: Set<String> = ["duck-sequence/1"]

    /// The one place the three words are separated, and it is shown in the UI.
    public static let whatThisIs =
        // THE LINE BREAKS MATTER TO A GATE. `check_sequence_is_not_a_policy.sh`
        // reads one quoted chunk at a time, so the clause that earns the word
        // "policy" has to be whole inside one of them. The sentence is
        // unchanged; only where it wraps is.
        "A sequence is a recording of what YOU did — the stick commands, stamped on the bench's "
      + "own sim clock, and the networks the bench said were driving while you drove. "
      + "A policy is a trained network and nothing here trains one; a motion is a track "
      + "somebody authored joint by joint. This is a macro, not a skill."

    /// One captured moment: from `atSim` seconds into the recording, hold this
    /// twist. `atSim` IS the bench's own sim clock offset to the recording's
    /// start — the same unit `DuckBench.Step.at` is in.
    public struct Step: Equatable, Sendable {
        public let atSim: Double
        public let twist: DuckDrive.Twist
        /// What the BENCH said was driving at that moment. Never a guess.
        public let policySaid: String?

        public init(atSim: Double, twist: DuckDrive.Twist, policySaid: String?) {
            self.atSim = atSim
            self.twist = twist
            self.policySaid = policySaid
        }
    }

    public enum Ending: Equatable, Sendable {
        case tapped, paused, stop
        /// A ceiling was reached; the take was closed there and kept.
        case ceiling(String)
    }

    public enum Provenance: Equatable, Sendable {
        case recorded(trips: Int, skipped: Int, endedBy: Ending)
        case said(String)
        case drafted(model: String, asked: String)

        public var sentence: String {
            switch self {
            case .recorded(let trips, let skipped, let endedBy):
                let round = trips == 1 ? "round trip" : "round trips"
                // "0 came back with no clock" is a true sentence and a bad one.
                let clocks = skipped == 0 ? "every one of them stamped"
                    : skipped == 1 ? "one of them with no clock on it"
                    : "\(skipped) of them with no clock on them"
                return "Driven here over \(trips) \(round), \(clocks). "
                     + PadPilot.endedBy(endedBy)
            case .said(let sentence):
                return "Read on this phone from what you typed — \"\(sentence)\". "
                     + DuckTalk.notAModel
            case .drafted(let model, let asked):
                return "\(model) wrote this from \"\(asked)\". Every number in it was re-derived "
                     + "against this app's own driving limits before it became a sequence, so "
                     + "nothing the model said about a speed was taken on trust."
            }
        }
    }

    public let id: UUID
    public var name: String
    public let steps: [Step]
    public let provenance: Provenance
    /// Wall-clock seconds the person spent. STORED AND PRINTED, NEVER USED AS
    /// A TIME BASE. Zero for a sequence that was typed rather than driven.
    public let wallSeconds: Double
    public let recordedAt: Date
    public let venue: DriveVenue

    public init(id: UUID, name: String, steps: [Step], provenance: Provenance,
                wallSeconds: Double, recordedAt: Date, venue: DriveVenue) {
        self.id = id
        self.name = name
        self.steps = steps
        self.provenance = provenance
        self.wallSeconds = wallSeconds
        self.recordedAt = recordedAt
        self.venue = venue
    }

    // MARK: - ceilings, all three of which bite during capture

    public static let maximumSeconds = 120.0
    public static let maximumSteps = 600
    public static let maximumMoveSeconds = 30.0
    public static let smallestGapSeconds = DuckDrive.holdSeconds

    public var simSeconds: Double { steps.last?.atSim ?? 0 }

    public var policiesNamed: [String] {
        Array(Set(steps.compactMap(\.policySaid))).sorted()
    }

    /// Non-nil only when exactly one network was named throughout.
    public var benchPolicy: String? {
        let named = policiesNamed
        return named.count == 1 ? named[0] : nil
    }

    public var canBeRecordedOnTheBench: Bool { benchPolicy != nil && !steps.isEmpty }

    public var benchRefusal: String? {
        guard benchPolicy == nil, !policiesNamed.isEmpty else { return nil }
        return "This sequence changed which network was driving partway through, and one bench "
             + "recording names one policy — POST /record takes a single policy and runs the whole "
             + "schedule against it. It plays here exactly as it was driven; keeping it as a Motion "
             + "would mean filing a run that is not this one. Record the parts separately, or drive "
             + "it again without changing networks."
    }

    /// The bench never told this take what was driving.
    ///
    /// IT IS A SEPARATE SENTENCE BECAUSE IT IS A SEPARATE FACT. `benchRefusal`
    /// is about a take that changed network; this is about one that was never
    /// told any network at all — a sequence written from words, or driven
    /// against a bench too old to name what it is running. Both end with no
    /// bench button, and a button that is absent for two different reasons owes
    /// two different sentences.
    public static let benchNeverNamedANetwork =
        "This sequence never heard the bench name what was driving, so there is nothing to file a "
      + "bench recording against — POST /record takes one network by name and this take has none. "
      + "A sequence written from words has none by construction; a driven one has none when the "
      + "bench is older than the field. It plays here exactly as it is."

    /// Why this cannot be kept on the bench as a Motion, or nil when it can.
    /// The one door a view asks, so no view has to coalesce two.
    public var cannotBeKept: String? {
        if canBeRecordedOnTheBench { return nil }
        return benchRefusal ?? DuckSequence.benchNeverNamedANetwork
    }

    public func benchSchedule() -> [DuckBench.Step] {
        steps.map {
            DuckBench.Step(at: $0.atSim, vx: $0.twist.vx, vy: $0.twist.vy, vyaw: $0.twist.vyaw)
        }
    }

    public var summary: String {
        String(format: "%.1f s of physics, %d steps%@", simSeconds, steps.count,
               benchPolicy.map { ", driven by \($0)" } ?? "")
    }

    public static func bothClocks(simSeconds s: Double, wallSeconds w: Double) -> String {
        String(format: "%.1f s of sim, captured over %.1f s of your time. The bench only advances "
             + "physics while it is answering a request, so a recording made over a slow link holds "
             + "fewer seconds of duck than seconds of you. Playing it back sends the same commands "
             + "at the same sim times; it will take whatever your link takes.", s, w)
    }

    public static func droppedNote(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        return "\(n) round \(n == 1 ? "trip" : "trips") came back with no clock on "
             + "\(n == 1 ? "it" : "them") and \(n == 1 ? "is" : "are") not in this take. The bench "
             + "reports sim time in its reply; without one there is no honest place to put a step."
    }

    public static let replayIsARerun =
        "Playing this sends the same commands at the same points on the bench's own clock. It is a "
      + "re-run and not the recording: the physics is computed again, the link paces it, and how "
      + "long it takes on the wall depends on your network. Every second printed here is a second "
      + "of simulated time, which is the only clock either end of this agrees about."

    /// What renaming does and does not touch, said where somebody is renaming.
    ///
    /// THE ID IS WHAT A BUTTON HOLDS, not the name — `SequenceStore` is keyed by
    /// UUID for exactly this reason — so a rename cannot orphan a binding, and
    /// somebody about to rename the take three of their buttons play deserves to
    /// be told that before they do it rather than after.
    public static let renamingKeepsTheBindings =
        "The name changes and nothing else does. Every button bound to this sequence holds its "
      + "id rather than its name, so all of them keep pointing at it."

    /// What the bench filed, once `acceptIntent` has said yes.
    public static func keptAsAMotion(_ name: String) -> String {
        "Kept as the motion \(name). It is in Behaviours with every other motion, and it is a "
      + "recording of a run the bench just made rather than of the drive you did here."
    }

    public static let sharingIsNotYet =
        "Sending a sequence to somebody else is not built yet. A format that travels needs a "
      + "declared file type, a document row and a share sheet — all three or none — and this app "
      + "already carries one format that has only some of them. The file is written in its final "
      + "shape, so it is a plist entry away rather than a rewrite."

    /// A name no other take of the same network will take.
    ///
    /// `RemoteRunView.keepName`'S SHAPE, AND FOR ITS REASON. A bench recording
    /// named after the network it ran is a name two recordings share, and
    /// `LibraryModel.acceptIntent` writes `intents/<name>.duckintent` with no
    /// existence check — so the second take silently destroyed the first. The
    /// clock reading is what makes two takes two names.
    public static func suggestedName(policy: String?, simSeconds: Double,
                                     steps: Int, at when: Date) -> String {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        return String(format: "%@ — bench %@, %.1f s, %d steps",
                      policy ?? "unknown network", clock.string(from: when),
                      simSeconds, steps)
    }

    public enum Refusal: Error, Equatable {
        case empty
        case noSimClock
        case tooLong(Double)
        case tooManySteps(Int)
        case heldTooLong(Double)

        public var message: String {
            switch self {
            case .empty:
                return "Nothing was recorded. The sticks stayed centred for the whole take, so "
                     + "there is no schedule to send."
            case .noSimClock:
                return "Nothing was recorded: the bench had not answered yet, so there was no "
                     + "clock to stamp these commands with. A recording stamped with this phone's "
                     + "clock would play back at the wrong speed on any link but the one it was "
                     + "made on."
            case .tooLong(let s):
                return "The take reached \(Int(s)) seconds on the bench's clock, which is the "
                     + "ceiling, so it was closed there and kept. Longer than that is a run rather "
                     + "than a macro."
            case .tooManySteps(let n):
                return "The take reached \(n) steps, which is the ceiling, so it was closed there "
                     + "and kept. A bench recording that long is a measurement rather than a macro."
            case .heldTooLong(let s):
                return "One command was held for \(Int(s)) seconds, which is as long as a single "
                     + "step may last, so the take was closed there and kept. A step is a command "
                     + "to hold, and one held longer than this is a schedule with nothing in it."
            }
        }
    }

    public static func make(steps: [Step], named: String, provenance: Provenance,
                            wallSeconds: Double, venue: DriveVenue,
                            at when: Date) throws -> DuckSequence {
        guard !steps.isEmpty, steps.contains(where: { $0.twist != .still }) else {
            throw Refusal.empty
        }
        guard steps.count <= maximumSteps else { throw Refusal.tooManySteps(maximumSteps) }
        let last = steps.last?.atSim ?? 0
        guard last <= maximumSeconds else { throw Refusal.tooLong(maximumSeconds) }
        return DuckSequence(id: UUID(), name: named, steps: steps, provenance: provenance,
                            wallSeconds: wallSeconds, recordedAt: when, venue: venue)
    }

    // MARK: - the file

    public func encoded() throws -> Data {
        var object: [String: Any] = [
            "format": DuckSequence.format,
            "id": id.uuidString,
            "name": name,
            "wallSeconds": wallSeconds,
            "recordedAt": recordedAt.timeIntervalSince1970,
            "venue": venue.rawValue,
            "steps": steps.map { step -> [String: Any] in
                var body: [String: Any] = ["atSim": step.atSim,
                                           "vx": step.twist.vx,
                                           "vy": step.twist.vy,
                                           "vyaw": step.twist.vyaw]
                if let said = step.policySaid { body["said"] = said }
                return body
            },
        ]
        switch provenance {
        case .recorded(let trips, let skipped, let endedBy):
            var body: [String: Any] = ["kind": "recorded", "trips": trips, "skipped": skipped]
            switch endedBy {
            case .tapped: body["endedBy"] = "tapped"
            case .paused: body["endedBy"] = "paused"
            case .stop: body["endedBy"] = "stop"
            case .ceiling(let why):
                body["endedBy"] = "ceiling"
                body["why"] = why
            }
            object["provenance"] = body
        case .said(let sentence):
            object["provenance"] = ["kind": "said", "sentence": sentence]
        case .drafted(let model, let asked):
            object["provenance"] = ["kind": "drafted", "model": model, "asked": asked]
        }
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    public static func decode(_ data: Data) throws -> DuckSequence {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        guard let format = top["format"] as? String else { throw ReadError.missing("a format") }
        guard readableFormats.contains(format) else { throw ReadError.wrongFormat(format) }
        guard let raw = top["steps"] as? [[String: Any]] else {
            throw ReadError.missing("its steps")
        }
        // EVERY FIELD BUT THE STEPS DEFAULTS, `SimDuck`-style, so a file
        // written before a field existed still opens. The steps are the
        // measurement and a sequence without them is not one.
        let steps: [Step] = raw.map { body in
            Step(atSim: body["atSim"] as? Double ?? 0,
                 twist: DuckDrive.Twist(vx: body["vx"] as? Double ?? 0,
                                        vy: body["vy"] as? Double ?? 0,
                                        vyaw: body["vyaw"] as? Double ?? 0),
                 policySaid: body["said"] as? String)
        }
        let told = top["provenance"] as? [String: Any] ?? [:]
        let provenance: Provenance
        switch told["kind"] as? String {
        case "said":
            provenance = .said(told["sentence"] as? String ?? "")
        case "drafted":
            provenance = .drafted(model: told["model"] as? String ?? "a model",
                                  asked: told["asked"] as? String ?? "")
        default:
            let ending: Ending
            switch told["endedBy"] as? String {
            case "paused": ending = .paused
            case "stop": ending = .stop
            case "ceiling": ending = .ceiling(told["why"] as? String ?? "")
            default: ending = .tapped
            }
            provenance = .recorded(trips: told["trips"] as? Int ?? steps.count,
                                   skipped: told["skipped"] as? Int ?? 0,
                                   endedBy: ending)
        }
        return DuckSequence(
            id: (top["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
            name: top["name"] as? String ?? "a sequence",
            steps: steps,
            provenance: provenance,
            wallSeconds: top["wallSeconds"] as? Double ?? 0,
            recordedAt: Date(timeIntervalSince1970: top["recordedAt"] as? Double ?? 0),
            venue: (top["venue"] as? String).flatMap(DriveVenue.init(rawValue:)) ?? .sim)
    }

    public var fileName: String { "\(id.uuidString).ducksequence" }

    public enum ReadError: Error, Equatable {
        case notJSON, wrongFormat(String), missing(String)

        public var message: String {
            switch self {
            case .notJSON:
                return "That file is not a sequence this app wrote — it is not even JSON."
            case .wrongFormat(let found):
                return "That sequence is in format \"\(found)\", which this version does not read. "
                     + "It reads \(DuckSequence.readableFormats.sorted().joined(separator: ", "))."
            case .missing(let field):
                return "That sequence is missing \(field), so there is nothing to play. It may "
                     + "have been written by a newer version."
            }
        }
    }

    /// Every sentence this track ships, gathered so one test can scan them all.
    ///
    /// IT IS A COLLECTION AND NOT A GREP OVER SOURCE, because the thing worth
    /// checking is what a person READS. `check_sequence_is_not_a_policy.sh`
    /// runs the same anchored pattern over the files themselves, so a sentence
    /// added to a type this list forgot is still caught.
    public static var allSentences: [String] {
        var out: [String] = [
            whatThisIs, replayIsARerun, sharingIsNotYet, benchNeverNamedANetwork,
            renamingKeepsTheBindings, keptAsAMotion("a take"),
            bothClocks(simSeconds: 3.4, wallSeconds: 19.2),
            droppedNote(1) ?? "", droppedNote(2) ?? "",
            suggestedName(policy: "a.onnx", simSeconds: 1, steps: 2, at: Date()),
            ReadError.notJSON.message,
            ReadError.wrongFormat("duck-sequence/9").message,
            ReadError.missing("its steps").message,
        ]
        for refusal: Refusal in [.empty, .noSimClock, .tooLong(120), .tooManySteps(600),
                                 .heldTooLong(30)] {
            out.append(refusal.message)
        }
        for ending: Ending in [.tapped, .paused, .stop, .ceiling("a ceiling was reached")] {
            out.append(PadPilot.endedBy(ending))
            out.append(Provenance.recorded(trips: 2, skipped: 1, endedBy: ending).sentence)
            out.append(Provenance.recorded(trips: 1, skipped: 0, endedBy: ending).sentence)
            out.append(Provenance.recorded(trips: 9, skipped: 3, endedBy: ending).sentence)
        }
        out.append(Provenance.said("forward for two seconds").sentence)
        out.append(Provenance.drafted(model: "a model", asked: "go forward").sentence)
        out.append(contentsOf: PadPilot.allSentences)
        out.append(contentsOf: DuckTalk.allSentences)
        out.append(contentsOf: SequenceProposal.allSentences)
        out.append(contentsOf: DuckPadMap.allSentences)
        return out
    }
}

/// The recorder's arithmetic, in the kit so the app has none.
///
/// ONE SAMPLE PER ROUND TRIP, TAKEN BEFORE THE NOTIFY. `atSim` is the bench's
/// clock as it stands BEFORE this twist is applied, which is exactly what
/// `DuckBench.Step.at` means — "from `at` seconds, hold this twist" — so a take
/// converts to a bench schedule without anybody subtracting anything. Stamping
/// after the reply would put every command one round trip late, which on a slow
/// link is a recording of a different drive.
///
/// A STEP IS WRITTEN ONLY WHEN SOMETHING CHANGED. Two minutes of driving is
/// tens of steps rather than thousands, because the wire's own shape is "from
/// here, hold this" and a repeat of the same command carries no information.
public struct DuckSequenceRecording: Equatable, Sendable {

    public enum Sampled: Equatable, Sendable {
        /// Same command, same network — nothing to write.
        case ignored
        case wrote(steps: Int, simSeconds: Double)
        /// No clock on this trip. COUNTED, NOT STAMPED; the take goes on.
        case skipped(total: Int)
        /// A ceiling was reached. The take is CLOSED here and keeps everything
        /// up to this point; the caller stops sampling and offers it.
        case closed(DuckSequence.Refusal)
    }

    public let startedAt: Date
    public let venue: DriveVenue
    public private(set) var trips = 0
    public private(set) var skipped = 0
    public private(set) var steps: [DuckSequence.Step] = []
    public private(set) var closedBy: DuckSequence.Refusal?
    /// The last wall-clock moment a sample arrived, so the wall reading is the
    /// span somebody spent DRIVING rather than the span up to whenever they got
    /// round to naming it.
    public private(set) var lastSampledAt: Date?
    /// The bench's clock at the last stamped trip, relative to the origin.
    /// THE END OF THE FINAL HOLD: a step is written only when the command
    /// changes, so without this the last thing a person drove would have no
    /// length at all.
    public private(set) var lastAtSim: Double?
    private var origin: Double?

    public init(startedAt: Date, venue: DriveVenue) {
        self.startedAt = startedAt
        self.venue = venue
    }

    /// What the live pill counts: the take as it will be saved, the final
    /// hold included, so the pill keeps counting while a stick is held.
    public var simSeconds: Double { closed.last?.atSim ?? 0 }

    /// The steps with the final hold closed by a terminating step at the last
    /// stamped moment — what `finish` saves and what the keep sheet shows.
    /// Guarded three ways: a take that already wrote a step on its last trip
    /// is left byte-identical, and the extra step never pushes a take past
    /// `make`'s own ceilings, where it would throw and lose the recording.
    public var closed: [DuckSequence.Step] {
        guard let last = steps.last, let end = lastAtSim, end > last.atSim,
              steps.count < DuckSequence.maximumSteps,
              end <= DuckSequence.maximumSeconds else { return steps }
        return steps + [DuckSequence.Step(atSim: end, twist: last.twist,
                                          policySaid: last.policySaid)]
    }

    /// ONE CALL PER ROUND TRIP, BEFORE THE NOTIFY.
    @discardableResult
    public mutating func sample(_ twist: DuckDrive.Twist,
                                atSim: Double?, policySaid: String?,
                                now: Date? = nil) -> Sampled {
        if let now { lastSampledAt = now }
        trips += 1
        guard let atSim else {
            skipped += 1
            return .skipped(total: skipped)
        }
        if origin == nil { origin = atSim }
        let at = atSim - (origin ?? atSim)
        lastAtSim = at
        if let last = steps.last {
            if last.twist == twist, last.policySaid == policySaid {
                // A COMMAND HELD PAST THE MOVE CEILING CLOSES THE TAKE AND
                // KEEPS IT. A step is a command to hold, and one held longer
                // than this is a schedule with nothing in it.
                if at - last.atSim > DuckSequence.maximumMoveSeconds {
                    closedBy = .heldTooLong(DuckSequence.maximumMoveSeconds)
                    return .closed(.heldTooLong(DuckSequence.maximumMoveSeconds))
                }
                return .ignored
            }
        }
        steps.append(DuckSequence.Step(atSim: at, twist: twist, policySaid: policySaid))
        if steps.count >= DuckSequence.maximumSteps {
            closedBy = .tooManySteps(DuckSequence.maximumSteps)
            return .closed(.tooManySteps(DuckSequence.maximumSteps))
        }
        if at >= DuckSequence.maximumSeconds {
            closedBy = .tooLong(DuckSequence.maximumSeconds)
            return .closed(.tooLong(DuckSequence.maximumSeconds))
        }
        return .wrote(steps: steps.count, simSeconds: at)
    }

    /// What `finish` would throw if it were called now, so a sheet can say why
    /// there is nothing to keep before it offers to keep it.
    public var refusalIfOfferedNow: DuckSequence.Refusal? {
        if steps.isEmpty, skipped > 0 { return .noSimClock }
        if steps.isEmpty || !steps.contains(where: { $0.twist != .still }) { return .empty }
        return nil
    }

    public func finish(named: String, endedBy: DuckSequence.Ending,
                       at now: Date) throws -> DuckSequence {
        if steps.isEmpty, skipped > 0 { throw DuckSequence.Refusal.noSimClock }
        let wall = (lastSampledAt ?? now).timeIntervalSince(startedAt)
        return try DuckSequence.make(
            steps: closed, named: named,
            provenance: .recorded(trips: trips, skipped: skipped, endedBy: endedBy),
            wallSeconds: max(0, wall), venue: venue, at: now)
    }
}

/// The playhead. A replay is the SAME loop reading a list instead of a thumb.
///
/// IT TAKES ITS ORIGIN FROM THE FIRST CLOCK IT IS GIVEN, so the caller never
/// subtracts anything and a replay started at sim t = 900 behaves exactly like
/// one started at t = 0. The bench's world has been running since somebody
/// connected; a playhead that assumed zero would fast-forward to the end on its
/// first beat.
public struct DuckSequenceRun: Equatable, Sendable {

    public enum Beat: Equatable, Sendable {
        case command(DuckDrive.Twist)
        /// The recording changed network here, so a faithful replay does too.
        case swap(to: String, then: DuckDrive.Twist)
        case finished
    }

    public let name: String
    private let steps: [DuckSequence.Step]
    private var origin: Double?
    private var lastIndex: Int?
    public private(set) var simElapsed: Double = 0

    public init(_ sequence: DuckSequence) {
        name = sequence.name
        steps = sequence.steps
    }

    public var duration: Double { steps.last?.atSim ?? 0 }

    public var fraction: Double {
        guard duration > 0 else { return simElapsed > 0 ? 1 : 0 }
        return min(1, max(0, simElapsed / duration))
    }

    public mutating func advance(toSimClock t: Double) -> Beat {
        guard !steps.isEmpty else { return .finished }
        if origin == nil { origin = t }
        let elapsed = max(0, t - (origin ?? t))
        simElapsed = min(elapsed, duration)
        guard elapsed <= duration else { return .finished }
        var index = 0
        for (i, step) in steps.enumerated() where step.atSim <= elapsed { index = i }
        let twist = steps[index].twist
        let arrived = index != lastIndex
        lastIndex = index
        if arrived, index > 0, let said = steps[index].policySaid,
           said != steps[index - 1].policySaid {
            return .swap(to: said, then: twist)
        }
        return .command(twist)
    }
}
