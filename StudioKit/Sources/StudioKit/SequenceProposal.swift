import Foundation
import DuckKit

/// A list of moves as somebody's words — or a model's JSON — states it, before
/// anything decides it is drivable.
///
/// FLAT STRINGS AND DOUBLES ON PURPOSE — the shape a small on-device model can
/// reliably fill. `MotionProposal` and `AutomationProposal` make the same
/// argument at length: a model cannot be asked to construct a Swift enum with
/// associated values, and the interesting, dangerous part is turning those
/// loose primitives into something that moves a duck. That happens HERE, where
/// `swift test` can check it on Linux, rather than in a view where the only way
/// to exercise it is to talk to a phone.
///
/// NOTHING A MODEL SAYS ABOUT A SPEED IS TRUSTED. `resolve` re-derives every
/// velocity from `DuckDrive`'s own limits and clamps against them: `speed: 5.0`
/// comes out at exactly `DuckDrive.maxForward`, not at five times it. A speed
/// below zero is not clamped but REFUSED BY NAME, because a negative fraction
/// is not a slower version of what was asked for — it is the other direction,
/// and silently turning the duck round would be the worst kind of helpful.
///
/// THE SAMPLING MAKES IT INDISTINGUISHABLE FROM A RECORDING. Each move is
/// sampled every `DuckDrive.holdSeconds` of sim, which is the same grid the
/// drive loop writes a take on, so a sequence written from words and one driven
/// with a thumb are the same kind of thing to everything downstream — the
/// playhead, the bench schedule, the file.
public struct SequenceProposal: Equatable, Sendable {

    public struct Move: Equatable, Sendable {
        public let go: String          // one of `offeredWords`
        public let seconds: Double
        /// 0…1 of the driving limit. Absent means full.
        public let speed: Double?

        public init(go: String, seconds: Double, speed: Double? = nil) {
            self.go = go
            self.seconds = seconds
            self.speed = speed
        }
    }

    public let name: String
    public let moves: [Move]

    public init(name: String, moves: [Move]) {
        self.name = name
        self.moves = moves
    }

    public static let offeredWords = ["forward", "back", "left", "right",
                                      "turn left", "turn right", "stop"]

    public enum Unresolvable: Error, Equatable {
        case noMoves
        case unknownDirection(String, closest: String?)
        case secondsOutOfRange(Double)
        case speedOutOfRange(Double)
        case tooLong(Double)

        public var message: String {
            switch self {
            case .noMoves:
                return "There is nothing to drive in that. A sequence is at least one move — a "
                     + "direction and how long to hold it."
            case .unknownDirection(let word, let closest):
                let hint = closest.map { " The nearest one is \"\($0)\"." } ?? ""
                return "\"\(word)\" is not something this app can send. The sticks produce a "
                     + "velocity twist and nothing else, so the words that resolve are "
                     + "\(SequenceProposal.offeredWords.joined(separator: ", ")).\(hint)"
            case .secondsOutOfRange(let s):
                return String(format: "%.2f seconds is not a length a move can be. One move lasts "
                            + "between %.1f and %.1f seconds — shorter than that is less than one "
                            + "round trip, and longer is a run rather than a step.",
                              s, DuckDrive.holdSeconds, DuckSequence.maximumMoveSeconds)
            case .speedOutOfRange(let value):
                return String(format: "%.2f is not a share of the driving limit. A speed is "
                            + "between 0 and 1, where 1 is the fastest this app sends; a negative "
                            + "one would be the other direction, which is a different move and "
                            + "not a slower one.", value)
            case .tooLong(let s):
                return String(format: "That is %.1f s of driving. A sequence holds at most %.0f s, "
                            + "and a written one is sampled every %.1f s of sim so it holds at "
                            + "most %d steps — %.0f s of commands. Say a shorter one, or drive it "
                            + "and record.",
                              s, DuckSequence.maximumSeconds, DuckDrive.holdSeconds,
                              DuckSequence.maximumSteps,
                              Double(DuckSequence.maximumSteps) * DuckDrive.holdSeconds)
            }
        }
    }

    /// Map, CLAMP, and refuse by name. Every velocity is re-derived against
    /// `DuckDrive`'s limits; nothing a model said about a speed is trusted.
    /// Samples each move every `DuckDrive.holdSeconds` of sim, so the result is
    /// exactly the shape a drive-loop recording has.
    public func resolve(named: String, provenance: DuckSequence.Provenance,
                        venue: DriveVenue, at when: Date) throws -> DuckSequence {
        guard !moves.isEmpty else { throw Unresolvable.noMoves }
        var total = 0.0
        var resolved: [(twist: DuckDrive.Twist, seconds: Double)] = []
        for move in moves {
            guard move.seconds.isFinite,
                  move.seconds >= DuckDrive.holdSeconds,
                  move.seconds <= DuckSequence.maximumMoveSeconds else {
                throw Unresolvable.secondsOutOfRange(move.seconds)
            }
            var share = 1.0
            if let speed = move.speed {
                guard speed.isFinite, speed >= 0 else {
                    throw Unresolvable.speedOutOfRange(speed)
                }
                share = min(speed, 1)
            }
            resolved.append((try SequenceProposal.twist(for: move.go, share: share),
                             move.seconds))
            total += move.seconds
        }
        let ceiling = min(DuckSequence.maximumSeconds,
                          Double(DuckSequence.maximumSteps) * DuckDrive.holdSeconds)
        guard total <= ceiling else { throw Unresolvable.tooLong(total) }

        // COUNTED, NOT ACCUMULATED. Adding 0.1 twenty times lands on
        // 2.0000000000000004, and a loop that compares that against a ceiling
        // gains or loses a step depending on which way the last bit went. The
        // index is exact and the stamp is derived from it.
        var steps: [DuckSequence.Step] = []
        var index = 0
        for one in resolved {
            let held = max(1, Int((one.seconds / DuckDrive.holdSeconds).rounded()))
            for _ in 0..<held {
                steps.append(DuckSequence.Step(atSim: Double(index) * DuckDrive.holdSeconds,
                                               twist: one.twist, policySaid: nil))
                index += 1
            }
        }
        return try DuckSequence.make(steps: steps, named: named, provenance: provenance,
                                     wallSeconds: 0, venue: venue, at: when)
    }

    /// One word, as the twist the sticks would produce for it.
    ///
    /// THE SIGNS COME OUT OF `DuckDrive.twist(for:)` AND NOT OUT OF A GUESS.
    /// Pollen's contract fixes `vy` positive to the LEFT and `vyaw` positive
    /// turning LEFT, while a stick pushed left reads negative — both negations
    /// are load-bearing and neither is obvious. A test drives the same word
    /// through both readers and compares, so the two can never disagree about a
    /// sign.
    public static func twist(for word: String, share: Double) throws -> DuckDrive.Twist {
        switch word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "forward":    return DuckDrive.Twist(vx: DuckDrive.maxForward * share, vy: 0, vyaw: 0)
        case "back":       return DuckDrive.Twist(vx: -DuckDrive.maxBackward * share, vy: 0, vyaw: 0)
        case "left":       return DuckDrive.Twist(vx: 0, vy: DuckDrive.maxSideways * share, vyaw: 0)
        case "right":      return DuckDrive.Twist(vx: 0, vy: -DuckDrive.maxSideways * share, vyaw: 0)
        case "turn left":  return DuckDrive.Twist(vx: 0, vy: 0, vyaw: DuckDrive.maxTurn * share)
        case "turn right": return DuckDrive.Twist(vx: 0, vy: 0, vyaw: -DuckDrive.maxTurn * share)
        case "stop":       return .still
        default:
            throw Unresolvable.unknownDirection(
                word, closest: AutomationValidator.closest(to: word,
                                                           in: Set(offeredWords)))
        }
    }

    /// One move as the numbers that will go on the wire.
    ///
    /// THE NUMBERS, NOT THE WORDS, AND NOT IN A VIEW. A box that takes a
    /// sentence and shows it back has proved nothing; what a person needs
    /// before something moves is the twist, said in `DuckDrive`'s own sentence
    /// — including the dead-zone line, so a gentle move reads as "the gait
    /// working, not a stall" rather than as a broken link.
    public static func spelled(_ move: Move) -> String {
        guard let twist = try? SequenceProposal.twist(for: move.go,
                                                      share: min(move.speed ?? 1, 1)) else {
            return move.go
        }
        return String(format: "%@ for %.1f s — %@", move.go, move.seconds, DuckDrive.says(twist))
    }

    /// Built from the same constants `resolve` clamps against.
    ///
    /// FORMATTED, NEVER TYPED TWICE. A grounding that quoted 0.3 m/s in prose
    /// would be a second copy of `DuckDrive.maxForward`, and the day somebody
    /// changed the limit the model would be told the old one.
    public static func grounding() -> String {
        String(format: "The duck drives with a velocity twist. Forward and back are at most "
             + "%.2f m/s, sideways at most %.2f m/s, turning at most %.2f rad/s. ",
               DuckDrive.maxForward, DuckDrive.maxSideways, DuckDrive.maxTurn)
        + String(format: "Below a twist magnitude of %.2f the standing policy takes over and it "
               + "stays where it is — that is the gait working, not a stall. ", DuckDrive.deadZone)
        + String(format: "One move lasts between %.1f and %.1f seconds; a whole sequence is at "
               + "most %.0f seconds.", DuckDrive.holdSeconds, DuckSequence.maximumMoveSeconds,
                 DuckSequence.maximumSeconds)
    }

    public static func read(fromJSON json: String) throws -> SequenceProposal {
        guard let data = json.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DraftError.wrongType("the reply")
        }
        guard let raw = top["moves"] as? [[String: Any]] else { throw DraftError.missing("moves") }
        let moves: [Move] = try raw.map { body in
            guard let go = body["go"] as? String else { throw DraftError.missing("go") }
            return Move(go: go,
                        seconds: number(body["seconds"]) ?? 1.0,
                        speed: number(body["speed"]))
        }
        return SequenceProposal(name: (top["name"] as? String) ?? "A sequence", moves: moves)
    }

    public enum DraftError: Error, Equatable {
        case missing(String), wrongType(String)

        public var message: String {
            switch self {
            case .missing(let key): return "The model left out \(key)."
            case .wrongType(let key): return "\(key) came back as the wrong kind of value."
            }
        }
    }

    /// Numbers arrive as numbers, or as strings, because small models quote
    /// them about a third of the time — `ChatDraft`'s own reason, and its own
    /// tolerance.
    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    public static let allSentences: [String] = [
        grounding(),
        spelled(Move(go: "forward", seconds: 2, speed: 1)),
        spelled(Move(go: "turn left", seconds: 1.5)),
        spelled(Move(go: "xyzzy", seconds: 1)),
        Unresolvable.noMoves.message,
        Unresolvable.unknownDirection("forwards", closest: "forward").message,
        Unresolvable.unknownDirection("xyzzy", closest: nil).message,
        Unresolvable.secondsOutOfRange(0.01).message,
        Unresolvable.speedOutOfRange(-1).message,
        Unresolvable.tooLong(200).message,
        DraftError.missing("moves").message,
        DraftError.wrongType("the reply").message,
    ]
}
