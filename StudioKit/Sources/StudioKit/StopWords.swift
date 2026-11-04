import Foundation

/// Listens to the speech recognizer's partial transcripts for "stop", "freeze" or "no", and
/// fires the moment one appears, before the person has finished talking.
///
/// NO LANGUAGE MODEL IS INVOLVED. This is keyword matching on the recognizer's own output
/// (docs/plans/native-first-redesign.md, Tell, "Voice path" step 2). A model would add latency
/// to the one sentence where latency matters most, and could decide a "stop" meant something
/// else.
///
/// WHOLE WORDS ONLY. The text is folded for case and diacritics ("STOP", "Stóp") and split on
/// anything that is not a letter or a digit, so "stop!", "stop," and "no-no" all fire while
/// "stopwatch", "know" and "nobody" do not. A split on punctuation means "non-stop" also fires;
/// a false stop costs a person one tap to start again, a missed one costs the duck a fall.
///
/// ONCE PER UTTERANCE. A recognizer sends the same partial many times as it refines it, and
/// each would otherwise be a fresh press. `hear` answers true the first time a stop word shows
/// up and false for the rest of that utterance; `begin()` starts the next one. StopPath is
/// idempotent anyway, so this keeps the journal honest rather than keeping the duck safe.
public struct StopWords: Equatable, Sendable {

    /// The words that stop the duck. Spoken, folded, whole.
    public static let words: Set<String> = ["stop", "freeze", "no"]

    /// Whether this utterance has already fired.
    public private(set) var fired = false

    public init() {}

    /// A new utterance: the mic was pressed again, or the recognizer said the last one ended.
    public mutating func begin() { fired = false }

    /// Feed a volatile (partial) or final transcript. True exactly once per utterance, on the
    /// first text holding a stop word. The caller then calls `StopPath.stop()`.
    public mutating func hear(_ transcript: String) -> Bool {
        guard !fired, Self.containsStop(transcript) else { return false }
        fired = true
        return true
    }

    /// Feed a transcript and, on the first stop word of the utterance, stop through the path
    /// every other surface uses. Returns the press when it fired.
    @discardableResult
    public mutating func hear(_ transcript: String, stopping path: StopPath) -> StopPath.Pressed? {
        hear(transcript) ? path.stop() : nil
    }

    /// Whether the text holds a stop word as a whole word.
    public static func containsStop(_ text: String) -> Bool {
        tokens(text).contains(where: words.contains)
    }

    /// The text as folded whole words: lowercased, accents gone, split on anything that is not
    /// a letter or a digit. `DuckOrderMatcher` reads sentences through the same function, so
    /// what counts as a word cannot differ between the two.
    public static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX")).lowercased()
        return folded
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }
}
