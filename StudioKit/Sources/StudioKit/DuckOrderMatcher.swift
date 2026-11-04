import Foundation
import DuckKit

/// Turns a final transcript into one `DuckOrder` when the sentence is plainly one, with no
/// model: the deterministic fast path of the Tell voice path (docs/plans/native-first-redesign.md,
/// "Voice path" step 3).
///
/// NIL MEANS "NOT SURE", AND NIL IS CHEAP. A sentence this cannot read exactly goes on to the
/// on-device model, or to the "I heard: ..." tiles. So every rule here is narrow: the words left
/// after the fillers must be exactly a known phrase. "Kick" on a duck with a left and a right
/// kick is nil, because picking one would be a guess.
///
/// WALKS ARE READ BY `DuckTalk`, NOT HERE. It is the existing closed grammar for driving, and a
/// second one would drift from it. A walk is matched only when DuckTalk reads exactly one move
/// in a direction, with no speed word (a command walks at its own fixed share), no angle (a
/// command commands a time) and no word it could not read beyond the walk fillers.
///
/// ANY STOP WORD MAKES THE WHOLE SENTENCE A STOP. "No, sit down" stops: `StopWords` has already
/// fired on the partial transcript, and answering it with a motion would undo the one thing the
/// person certainly said.
public enum DuckOrderMatcher {

    /// Words that carry nothing about which command was meant.
    public static let fillers: Set<String> = [
        "please", "the", "duck", "microduck", "hey", "ok", "okay", "now", "can", "could", "would",
        "you", "will", "go", "do", "a", "an", "just", "little", "for", "me", "us", "and", "then",
        "make", "let", "lets", "s", "it", "its", "your", "some", "again",
    ]

    /// Extra words that may sit around a phrase for each kind of command.
    static let soundFillers: Set<String> = ["play", "say", "sound", "noise", "give", "us"]
    static let skillFillers: Set<String> = ["perform", "try", "show", "with", "move", "skill"]
    static let walkFillers: Set<String> = ["walk", "move", "go", "please", "the", "duck",
                                           "microduck", "now", "a", "little", "bit", "and",
                                           "then", "hey", "ok", "okay", "for"]

    /// Spoken names for the duck's sounds. Each tag's own name also matches.
    public static let soundWords: [String: DuckSound] = [
        "quack": .chirp, "chirp": .chirp, "honk": .alarm, "alarm": .alarm, "greet": .greet,
        "hello": .greet, "inquire": .inquire, "peck": .peck, "coo": .coo, "wheee": .wheee,
        "whee": .wheee,
    ]

    /// Read `text`. `skills` is what `robot.skills` listed (or the practice duck's list); `names`
    /// are the duck's own names ("Puddle"), which are fillers too.
    public static func match(_ text: String, skills: [String] = [], names: [String] = []) -> DuckOrder? {
        let all = StopWords.tokens(text)
        guard !all.isEmpty else { return nil }

        // 1. Stop wins over everything.
        if all.contains(where: StopWords.words.contains) || all.contains("halt") { return .stop }

        let nameWords = Set(names.flatMap(StopWords.tokens))
        let words = all.filter { !fillers.contains($0) && !nameWords.contains($0) }
        guard !words.isEmpty else { return nil }

        // 2. Sit and stand (one skill on the robot, two commands here).
        switch words {
        case ["sit"], ["sit", "down"]: return .sit
        case ["stand"], ["stand", "up"], ["get", "up"], ["wake", "up"]: return .stand
        default: break
        }

        // 3. A skill by its own name, the whole name and nothing else.
        if let skill = skill(words, among: skills) { return .skill(skill) }

        // 4. Look. v1 aims up and ahead whatever was asked, so only phrases that mean that go:
        //    "look at me", "look here", "look ahead", "look up".
        if words.first == "look" {
            let rest = Array(words.dropFirst())
            if rest == ["at"] || rest == ["up", "at"], all.contains("me") { return .look(.me) }
            if rest.isEmpty || rest == ["ahead"] || rest == ["here"] || rest == ["forward"]
                || rest == ["up"] {
                return .look(.ahead)
            }
            return nil
        }

        // 5. A sound.
        let soundRest = words.filter { !soundFillers.contains($0) }
        if soundRest.count == 1, let sound = soundWords[soundRest[0]] ?? DuckSound(rawValue: soundRest[0]) {
            return .sound(sound)
        }

        // 6. A single walk, read by DuckTalk.
        return walk(text, tokens: all, nameWords: nameWords)
    }

    /// The skill a set of words names, if exactly one does. Word order is free ("left kick" is
    /// `kick_left`); `sit_toggle` is never matched here, because Sit and Stand read it.
    static func skill(_ words: [String], among skills: [String]) -> String? {
        let said = words.filter { !skillFillers.contains($0) }.sorted()
        guard !said.isEmpty else { return nil }
        let hits = skills.filter { name in
            name != DuckOrder.sitToggle
                && DuckCall.isSkillName(name)
                && name.split(separator: "_").map(String.init).sorted() == said
        }
        return hits.count == 1 ? hits[0] : nil
    }

    static func walk(_ text: String, tokens: [String], nameWords: Set<String>) -> DuckOrder? {
        // A speed or an angle would be silently changed by a command's own fixed walk.
        let refused = Set(DuckTalk.gentleWords + DuckTalk.quickWords + DuckTalk.degreeWords + ["half"])
        guard !tokens.contains(where: refused.contains), !text.contains("°") else { return nil }

        let reading = DuckTalk.read(text)
        guard reading.moves.count == 1, let move = reading.moves.first, move.speed == nil else { return nil }
        let unread = reading.unread.flatMap(StopWords.tokens)
        guard unread.allSatisfy({ walkFillers.contains($0) || nameWords.contains($0) }) else { return nil }

        let direction: DuckOrder.Direction
        switch move.go {
        case "forward": direction = .forward
        case "back": direction = .back
        case "left": direction = .left
        case "right": direction = .right
        case "turn left": direction = .turnLeft
        case "turn right": direction = .turnRight
        default: return nil
        }
        return .walk(direction, seconds: DuckOrder.walkSeconds(move.seconds))
    }
}
