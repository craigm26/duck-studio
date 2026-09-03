import Foundation
import DuckKit

/// A small closed grammar that turns "forward for two seconds then turn left"
/// into moves, on the phone, offline, for nothing.
///
/// IT RUNS FIRST, AND THAT IS THE WHOLE DESIGN. A model is the fallback, not
/// the front door: driving is the one kind of request in this app that is
/// MEASURED rather than written — every word here resolves to a number
/// `DuckDrive` already enforces — so asking a language model to produce it
/// would be spending a round trip, a battery and somebody's privacy on
/// arithmetic this package can do exactly. `notAModel` is that claim, on
/// screen, where somebody would otherwise assume a model answered.
///
/// NOTHING HERE UNDERSTANDS ANYTHING, AND THE SENTENCES SAY SO. This is a fixed
/// table of words matched against the drive limits; it has no model of a duck,
/// no idea what a room is, and no way to tell a good idea from a bad one. What
/// it can do is show the numbers BEFORE anything moves, and name every one it
/// had to guess at — which is the difference between a tool and a wish.
///
/// THE GUESSES ARE LISTED RATHER THAN HIDDEN. A missing time becomes one
/// second and says so; a bare direction becomes the full mapped limit and says
/// why (a stick at full deflection sends exactly that, and this app has nothing
/// faster); an angle becomes a duration and says the loudest thing in the file,
/// which is that this app commands a rate and not an angle.
public enum DuckTalk {

    // MARK: - the table `read` matches against

    /// One direction and every word that means it.
    public struct Direction: Equatable, Sendable {
        public let words: [String]
        /// One of `SequenceProposal.offeredWords`.
        public let go: String
    }

    public static let directions: [Direction] = [
        Direction(words: ["forward", "ahead", "straight"], go: "forward"),
        Direction(words: ["back", "backward", "backwards", "reverse"], go: "back"),
        Direction(words: ["left"], go: "left"),
        Direction(words: ["right"], go: "right"),
        Direction(words: ["stop", "wait", "stand", "still", "pause"], go: "stop"),
    ]

    /// A verb that turns the next `left` or `right` into a yaw rather than a
    /// strafe. `padd` puts translation on one stick and heading on the other,
    /// and a sentence has to be able to say which it meant.
    public static let turnWords = ["turn", "spin", "rotate"]
    public static let gentleWords = ["gently", "slowly"]
    public static let quickWords = ["quickly", "fast"]
    public static let secondWords = ["second", "seconds", "sec", "secs", "s"]
    public static let degreeWords = ["degree", "degrees"]

    public static let numberWords: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]

    /// A stick pushed all the way is what a bare direction means; "gently"
    /// halves it.
    public static let gently = 0.5

    /// What a move lasts when nobody said.
    public static let defaultSeconds = 1.0

    // MARK: - the reading

    public struct Reading: Equatable, Sendable {
        public let moves: [SequenceProposal.Move]
        /// Facts taken from the sentence, in the sentence's own terms.
        public let understood: [String]
        /// Facts nobody supplied. THE UI MUST SHOW THESE.
        public let assumed: [String]
        /// Words that were not read at all.
        public let unread: [String]

        public init(moves: [SequenceProposal.Move], understood: [String],
                    assumed: [String], unread: [String]) {
            self.moves = moves
            self.understood = understood
            self.assumed = assumed
            self.unread = unread
        }

        public enum Confidence: Equatable, Sendable {
            case understood, understoodWithGuesses, notUnderstood
        }

        public var confidence: Confidence {
            if moves.isEmpty { return .notUnderstood }
            if assumed.isEmpty, unread.isEmpty { return .understood }
            return .understoodWithGuesses
        }

        public var sentence: String {
            switch confidence {
            case .understood:
                return "Every number in this sequence came out of your sentence."
            case .understoodWithGuesses:
                return "Read here on the phone, with no model. Where you did not say a speed or a "
                     + "time, this used its own — those are listed below. Say the number and the "
                     + "guess goes away."
            case .notUnderstood:
                return "This app could not read that as driving. On its own it understands "
                     + "\(DuckTalk.vocabulary). A model can read the rest — Apple's on-device one, "
                     + "one downloaded onto this phone, or anything on your network speaking the "
                     + "OpenAI chat API — and you add one in Settings."
            }
        }
    }

    /// Deterministic. No model, no network, no cost, and it runs FIRST.
    public static func read(_ sentence: String) -> Reading {
        var moves: [SequenceProposal.Move] = []
        var understood: [String] = []
        var assumed: [String] = []
        var unread: [String] = []

        for clause in clauses(in: sentence) {
            var go: String?
            var turning = false
            var number: Double?
            var numberWord: String?
            var sawSeconds = false
            var sawDegrees = false
            var share: Double?
            var quick = false
            var leftovers: [String] = []

            let tokens = words(in: clause)
            var index = 0
            while index < tokens.count {
                let token = tokens[index]
                let next = index + 1 < tokens.count ? tokens[index + 1] : nil
                index += 1

                if turnWords.contains(token) { turning = true; continue }
                if gentleWords.contains(token) { share = gently; continue }
                if quickWords.contains(token) { quick = true; continue }
                if secondWords.contains(token) { sawSeconds = true; continue }
                if degreeWords.contains(token) { sawDegrees = true; continue }
                if token == "for" || token == "then" { continue }
                if token == "a" || token == "an" {
                    // "a bit" is the third way of saying gently; "a second" is
                    // a time nobody put a digit on.
                    if next == "bit" { share = gently; index += 1; continue }
                    if let next, secondWords.contains(next), number == nil {
                        number = 1
                        numberWord = "a second"
                        sawSeconds = true
                        index += 1
                    }
                    continue
                }
                if token == "bit" { share = gently; continue }
                if token == "half" {
                    if number == nil { number = 0.5; numberWord = "half" }
                    continue
                }
                if let direction = directions.first(where: { $0.words.contains(token) }) {
                    if turning, direction.go == "left" || direction.go == "right" {
                        go = "turn \(direction.go)"
                    } else {
                        go = direction.go
                    }
                    continue
                }
                if let value = numberWords[token] {
                    if number == nil { number = value; numberWord = token }
                    continue
                }
                if let value = digits(in: token) {
                    if number == nil { number = value.value; numberWord = token }
                    if value.hadSecondSuffix { sawSeconds = true }
                    continue
                }
                leftovers.append(token)
            }

            guard let go else {
                unread.append(contentsOf: leftovers)
                continue
            }

            var seconds = defaultSeconds
            if sawDegrees, go.hasPrefix("turn"), let number {
                seconds = (number * .pi / 180) / DuckDrive.maxTurn
                assumed.append(degreesAssumption(number, seconds: seconds))
            } else if let number {
                if sawDegrees { leftovers.append("degrees") }
                seconds = number
                understood.append(timeUnderstood(numberWord ?? "", seconds: seconds,
                                                 saidSeconds: sawSeconds))
            } else {
                assumed.append(timeAssumed(go))
            }

            if let share {
                understood.append(speedUnderstood(share))
            } else {
                assumed.append(quick ? quicklyAssumed : speedAssumed(go))
            }

            unread.append(contentsOf: leftovers)
            moves.append(SequenceProposal.Move(go: go, seconds: seconds, speed: share))
        }

        return Reading(moves: moves, understood: understood, assumed: assumed, unread: unread)
    }

    // MARK: - the sentences the reading is made of

    public static func degreesAssumption(_ degrees: Double, seconds: Double) -> String {
        String(format: "\"%g degrees\" at %.2f rad/s is %.2f s of command. Whether the duck turns "
             + "%g degrees is the policy's business — this app commands a rate, not an angle.",
               degrees, DuckDrive.maxTurn, seconds, degrees)
    }

    public static func timeUnderstood(_ word: String, seconds: Double,
                                      saidSeconds: Bool) -> String {
        String(format: "\"%@\"%@ — %.2f s of the bench's clock.", word,
               saidSeconds ? "" : ", read as seconds", seconds)
    }

    public static func timeAssumed(_ go: String) -> String {
        String(format: "You did not say how long to %@, so it holds for %.1f s.",
               go, defaultSeconds)
    }

    public static func speedUnderstood(_ share: Double) -> String {
        String(format: "Half speed — %.2f m/s forward, %.2f rad/s turning.",
               DuckDrive.maxForward * share, DuckDrive.maxTurn * share)
    }

    public static func speedAssumed(_ go: String) -> String {
        String(format: "You did not say how fast, so \"%@\" goes at the fastest this app sends — "
             + "%.2f m/s, which is a stick pushed all the way.", go, DuckDrive.maxForward)
    }

    public static var quicklyAssumed: String {
        String(format: "\"quickly\" — already at the fastest this app sends, %.2f m/s.",
               DuckDrive.maxForward)
    }

    public static func notRead(_ words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        return "Not read: \(words.joined(separator: ", ")). Those words were matched against "
             + "nothing this app can send, so they changed none of the numbers above."
    }

    /// Built from the table `read` matches against, so the words a person is
    /// offered and the words that resolve cannot drift apart.
    public static var vocabulary: String {
        (directions.flatMap(\.words) + ["turn left", "turn right"]).joined(separator: ", ")
    }

    /// What to tell a model when the grammar could not read it.
    ///
    /// IT ENDS IN THE HOUSE SHAPE — one sample object, no fence, no prose —
    /// which is `ChatDraft`'s own ending for every kind it builds, because a
    /// small model that has been shown exactly one object emits exactly one.
    public static var instructions: String {
        "You turn one sentence into a list of driving moves for a 25 cm robot duck. You are not "
      + "driving anything; the app clamps every number you give it against its own limits before "
      + "anything moves.\n\n"
      + SequenceProposal.grounding() + "\n\n"
      + "Use one of these exact words for \"go\": "
      + SequenceProposal.offeredWords.joined(separator: ", ") + ".\n"
      + "\"seconds\" is how long to hold that move. \"speed\" is a share of the limit between 0 "
      + "and 1 and may be left out, which means the fastest the app sends.\n\n"
      + "Answer with JSON and nothing else. No explanation, no markdown fence.\n"
      + "Exactly this shape:\n"
      + "{\"name\":\"Forward then left\",\"moves\":[{\"go\":\"forward\",\"seconds\":2.0,"
      + "\"speed\":1.0},{\"go\":\"turn left\",\"seconds\":1.5}]}"
    }

    public static var withoutAModel: String {
        "There is no model configured, so only the words this app reads for itself will work here: "
      + "\(vocabulary). That is enough for most driving. For anything else, add a model in Settings."
    }

    public static let simSecondsNote =
        "Those seconds are the bench's clock. On a slow link the same command takes longer for you "
      + "and exactly as long for the duck."

    public static let notAModel =
        "No model was asked. This is a fixed list of words matched against the drive limits this "
      + "app already enforces, which is why it works on a phone with nothing configured."

    /// The heading and caption of the sheet, here for the same reason the rest
    /// of them are.
    public static let sayItTitle = "Say it"
    public static let sayItPlaceholder = "forward for two seconds then turn left"
    public static let dictationNote =
        "The microphone on your keyboard types into this box like any other field. This app asks "
      + "for no microphone of its own and records no audio."

    public static let allSentences: [String] = [
        vocabulary, instructions, withoutAModel, simSecondsNote, notAModel,
        sayItTitle, sayItPlaceholder, dictationNote,
        degreesAssumption(90, seconds: 1.05),
        timeUnderstood("two", seconds: 2, saidSeconds: true),
        timeUnderstood("2", seconds: 2, saidSeconds: false),
        timeAssumed("forward"),
        speedUnderstood(gently),
        speedAssumed("forward"),
        quicklyAssumed,
        notRead(["xyzzy"]) ?? "",
        Reading(moves: [SequenceProposal.Move(go: "forward", seconds: 1, speed: 1)],
                understood: [], assumed: [], unread: []).sentence,
        Reading(moves: [SequenceProposal.Move(go: "forward", seconds: 1, speed: nil)],
                understood: [], assumed: ["a guess"], unread: []).sentence,
        Reading(moves: [], understood: [], assumed: [], unread: ["xyzzy"]).sentence,
    ]

    // MARK: - small readers

    /// Split on the separators a person actually uses. `and then` first, so
    /// the bare `and` rule cannot eat half of it.
    private static func clauses(in sentence: String) -> [String] {
        // THE DEGREE SIGN IS A WORD HERE. Somebody who types "90°" means what
        // somebody who types "90 degrees" means, and the alternative is a
        // second number reader that has to know about suffixes.
        var text = sentence.lowercased().replacingOccurrences(of: "°", with: " degrees ")
        for separator in [",", " and then ", " and ", ";"] {
            text = text.replacingOccurrences(of: separator, with: " then ")
        }
        return text.components(separatedBy: " then ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func words(in clause: String) -> [String] {
        clause.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map { token in
                String(token).trimmingCharacters(in: CharacterSet(charactersIn: ".!?;:\"'()"))
            }
            .filter { !$0.isEmpty }
    }

    /// A token that is a number, with or without the `s` a person types in
    /// "2s".
    private static func digits(in token: String)
        -> (value: Double, hadSecondSuffix: Bool)? {
        if let value = Double(token) { return (value, false) }
        if token.hasSuffix("s"), let value = Double(String(token.dropLast())) {
            return (value, true)
        }
        return nil
    }
}
