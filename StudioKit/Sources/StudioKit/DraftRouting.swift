import Foundation
import DuckKit

/// Working out what somebody is asking for, instead of making them pick first.
///
/// THE FOUR TABS ARE THE WRONG QUESTION. The Draft tab opened on a segmented
/// control — Motion, Rule, Fetch, Train — so before anybody could say what they
/// wanted, they had to know which of four internal categories it fell into.
/// Those are the app's categories, not a person's: somebody who wants the duck
/// to bow when the door opens has written a RULE whose action is a MOTION they
/// have not authored yet, and no tab is right for that sentence.
///
/// So the model reads the sentence and decides. That is what it is for, and it
/// is better at this than a menu is.
///
/// IT MAY ALSO REFUSE TO DECIDE, WHICH IS THE HALF THAT MATTERS. Guessing wrong
/// costs a whole round trip and produces a confident answer to a question
/// nobody asked — a training brief when somebody wanted a bow. So `Routed`
/// carries a question as a first-class outcome, and the screen asks it rather
/// than picking the likeliest kind. One question, answerable in a few words:
/// this is a conversation, not a form with the fields hidden.
public enum DraftRouting {

    /// What the router came back with.
    public enum Routed: Equatable, Sendable {
        /// It knows what this is. The reason is kept because the screen shows
        /// it — being told "reading this as a motion" is what lets somebody
        /// correct a wrong turn in one sentence instead of starting again.
        case kind(ChatDraft.Kind, because: String)
        /// It does not know, and this is the one thing that would settle it.
        case ask(String)
    }

    /// What each kind is, in the terms a person would use rather than the
    /// terms the code uses.
    ///
    /// SPELLED OUT BECAUSE THE MODEL IS THE ONE READING IT, and "retrieval" is
    /// a word nobody types. The examples are the load-bearing part: a router
    /// given only category names sorts by vocabulary, and a person describing
    /// a bow does not use the word "motion".
    public static let catalogue = """
    motion — a movement of the duck's own body, to be authored keyframe by \
    keyframe. "take a slow bow", "look left then right", "nod twice". \
    Nothing about picking things up, nothing conditional.

    rule — something the duck should do WHEN something else happens. Always \
    has a trigger and an action. "when something is close, sit down", \
    "if the battery is low, stop".

    retrieval — fetching or dragging an OBJECT that is somewhere in the room. \
    Always involves a thing that is not the duck. "fetch the stick", "get me \
    the pencil", "drag the broom".

    training — asking for a NEW ABILITY the duck does not have, which would \
    have to be learned on a GPU rather than authored. "teach it to jump", \
    "train a policy that climbs stairs", "learn to balance on one leg".
    """

    /// The instructions the router runs on.
    public static func instructions(knownIntents: Set<String> = []) -> String {
        let known = knownIntents.sorted().joined(separator: ", ")
        let intentNote = known.isEmpty ? ""
            : "\n\nMotions that already exist, which a rule can play: \(known)."
        return """
        You are sorting one sentence about a 25 cm robot duck into exactly one \
        of four kinds, or asking one question if you genuinely cannot tell.

        \(catalogue)\(intentNote)

        DECIDE IF YOU CAN. Most sentences are obvious and a question wastes the \
        person's time. Ask only when the sentence would send you down two \
        different roads — not merely when it is short.

        If a sentence needs a motion that does not exist yet AND a trigger, it \
        is a rule: the motion can be written afterwards.

        Answer with JSON and nothing else. No explanation, no markdown fence. \
        Either:
        {"kind":"motion","because":"a short reason, one clause"}
        or:
        {"question":"the one thing you need to know"}
        """
    }

    public enum RoutingError: Error, Equatable {
        case unreadable
        case unknownKind(String)

        public var message: String {
            switch self {
            case .unreadable:
                return "The model's answer could not be read as a routing decision."
            case .unknownKind(let k):
                return "The model asked for \"\(k)\", which is not one of the four kinds."
            }
        }
    }

    /// Read what came back, from the model's raw reply.
    ///
    /// A STRING, LIKE EVERY OTHER READER HERE. `DraftEngine.Answer.json` is
    /// text, and `ChatDraft.motion(fromJSON:)` and its siblings all take text;
    /// a router taking a dictionary would be the one door in this family with a
    /// different handle.
    public static func read(fromJSON json: String) throws -> Routed {
        guard let data = json.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RoutingError.unreadable
        }
        return try read(fromJSON: top)
    }

    /// Read what came back, already parsed.
    public static func read(fromJSON json: [String: Any]) throws -> Routed {
        if let question = json["question"] as? String,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .ask(question.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let raw = json["kind"] as? String else { throw RoutingError.unreadable }
        // `tweak` and `search` are deliberately absent: both edit something
        // already on a screen and are reached from that screen, never from a
        // sentence typed here. The list is DATA — `ChatDraft.Kind.routable` —
        // so a seventh kind cannot quietly become routable by being added to
        // the enum.
        guard let kind = ChatDraft.Kind(rawValue: raw.lowercased()),
              ChatDraft.Kind.routable.contains(kind) else {
            throw RoutingError.unknownKind(raw)
        }
        let because = (json["because"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .kind(kind, because: because)
    }

    // MARK: - with no model at all

    /// The one kind that can be routed without a model.
    ///
    /// THE PICKER WAS ALSO A NO-MODEL PATH, and removing it would have taken
    /// something away. Fetch never needed a model: `Retrieval` reads a sentence
    /// against measurements, which is why a phone with nothing configured could
    /// still size a stick — the person just had to know to press "Fetch"
    /// first. This keeps that working without the tab.
    ///
    /// It only claims a fetch when `Retrieval` actually recognised something,
    /// which is the same test the fetch screen itself now uses to decide
    /// whether it may show a green seal. Anything else returns nil rather than
    /// guessing, because a deterministic reader that guessed at the other three
    /// kinds would be a worse router than no router.
    public static func withoutAModel(_ sentence: String) -> Routed? {
        let reading = Retrieval.read(sentence)
        guard reading.confidence != .notUnderstood else { return nil }
        return .kind(.retrieval, because: "it names something to fetch, which this app can size "
                                        + "without a model")
    }

    /// What to say when there is no model and the sentence is not a fetch.
    /// What to say when Apple's model is not there.
    ///
    /// LIFTED OUT OF THE APP because these are sentences and sentences are
    /// tested here — and because both named exactly two remedies, "a local or
    /// remote model", written when there were two. A person on a device without
    /// Apple Intelligence is precisely the person a downloaded model is for,
    /// and it was the one option they were not told about.
    public static let appleUnavailable =
        "Apple Intelligence is not available on this device. In Settings you can download a "
      + "model onto this phone, or point this app at one on your network."

    public static let appleTooOld =
        "This version of iOS has no on-device model. In Settings you can download a model onto "
      + "this phone, or point this app at one on your network."

    /// NAMES THREE ROUTES, NOT TWO. It used to end "anything speaking the
    /// OpenAI chat API will do, including one running on this phone", which
    /// meant the localhost preset — another app serving a model — and now reads
    /// as the downloaded kind, which speaks no HTTP at all. Both exist, so both
    /// are named.
    ///
    /// TWO KINDS, NOT ONE, SINCE THE CONTROL TAB GREW A DRIVING GRAMMAR.
    /// `DuckPadMap`/`PadPilot` read a driving sentence against measurements the
    /// same way `Retrieval` reads a fetching one, so the old "one kind of
    /// request" was a sentence the app had outgrown. Nothing in the pad track
    /// prints this — the Control tab prints `DuckTalk.withoutAModel` — but the
    /// Draft tab does, and a Draft tab telling somebody the app can do one
    /// thing when it can do two is a smaller claim than the truth.
    public static let needsAModel =
        "Without a model this app can only work out two kinds of request on its own — fetching "
      + "something, and driving, because both are measured rather than written. For a motion, a "
      + "rule or a training brief, add one in Settings: Apple's on-device model, a model "
      + "downloaded onto this phone, or anything on your network speaking the OpenAI chat API."
}
