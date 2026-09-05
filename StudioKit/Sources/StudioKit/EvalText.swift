import Foundation

/// Text this app did not write, on its way to a screen.
///
/// WHY A GATE ROUND SOMEBODY ELSE'S WORDS. Almost every sentence in this app is
/// a constant with a test, and `scripts/check_stage_sentences.sh` is what keeps
/// it that way. The evaluation feature is the first place where strings nobody
/// here authored reach a row: the bench's own `criterion` and its refusal
/// reasons, every field of a log written elsewhere, the operator's own note,
/// the harness's grid cell labels, and an imported file's original name. Those
/// have to be shown, because paraphrasing a measurement is how a placeholder
/// gets shipped, and they cannot be tested, because nothing here wrote them.
///
/// So they all pass through here, and what this promises is small and checkable:
/// no control characters, and never longer than `cap`. The point of the cap is
/// not tidiness. A JavaScript-authored `why` has no length bound at all, and a
/// four-thousand-character paragraph inside a `List` row is a screen a person
/// cannot get out of. The marker is there so a reader can tell a sentence that
/// was cut from a sentence that ended.
///
/// IT IS FOR DRAWING AND NEVER FOR WRITING. A log carries the bench's words
/// whole: truncating a criterion on the way into a file would put a sentence in
/// the record that the bench never said. `EvalReport` escapes rather than caps,
/// for the same reason.
public enum EvalText {

    /// Two hundred and forty characters is about four lines on the narrowest
    /// phone this app supports, which is enough for the bench's longest real
    /// sentence and short enough that a row stays a row.
    public static let cap = 240

    /// One character, appended when and only when something was cut.
    public static let marker = "\u{2026}"

    /// Somebody else's string, ready to be drawn.
    ///
    /// Control characters go first, because a tab or a stray carriage return
    /// inside a `Text` is a layout nobody can predict, and U+2028 and U+2029 in
    /// particular are line breaks that survive being pasted into a report. Then
    /// the length, counted in Characters rather than scalars, because that is
    /// what a person sees.
    ///
    /// A LINE BREAK BECOMES A SPACE AND IS NOT DELETED. A bench writes a `why`
    /// over two lines often enough, and dropping the newline outright ran the
    /// last word of one line into the first word of the next: "the cell is
    /// invalidthe tail was 60 ticks". The layout argument is against the raw
    /// break, not against the word boundary, so every whitespace class control
    /// character collapses to one space and the rest are still dropped.
    public static func foreign(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x09...0x0D, 0x20, 0x2028, 0x2029:
                // Leading whitespace never opens a space, and a run of it is
                // one space, so a trailing run is simply never flushed.
                pendingSpace = !scalars.isEmpty
            case 0x00...0x1F, 0x7F...0x9F:
                continue
            default:
                if pendingSpace {
                    scalars.append(" ")
                    pendingSpace = false
                }
                scalars.append(scalar)
            }
        }
        let cleaned = String(scalars).trimmingCharacters(in: .whitespaces)
        guard cleaned.count > cap else { return cleaned }
        return String(cleaned.prefix(cap - marker.count)) + marker
    }

    /// The same thing for a string that might not be there, so a call site
    /// never writes an empty row for a missing field.
    public static func foreign(_ value: String?) -> String? {
        guard let value else { return nil }
        let capped = foreign(value)
        return capped.isEmpty ? nil : capped
    }

    /// Last line of the HTML report this app draws, and of the Hugging Face
    /// card. `EvalReport` reads it rather than re-wording it, because two
    /// sentences denying the same thing differently is how a denial stops being
    /// believed.
    public static let notTheirRender =
        "This page was drawn by Microduck Studio and not by inspect-robots. The JSON file beside "
      + "it is what their tools read. Run inspect-robots view on it for their own rendering, "
      + "which is the one to trust if the two ever disagree."
}
