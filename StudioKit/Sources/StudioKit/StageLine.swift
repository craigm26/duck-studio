import Foundation

/// One line of words over the live picture on Play: collapsed to a single short line, the whole
/// sentence one tap away.
///
/// WHY THIS EXISTS (build 96, Craig's screenshot of Play > Drive on the practice duck). A run's
/// report, "1 of 1, stayed upright to the end, dropped from 0.120 m. On scene.mjb, sha256 ...
/// frame for frame.", was drawn TWICE and both times in full: as the controller's caption across
/// the top half of the picture, and as the readout panel's last line, a card that grew down over
/// the sticks and the buttons. The press handler hands the same text to both on purpose, and
/// neither had a height budget. The house rule from build 42 (the legend that hid the duck) is
/// that an overlay on a live picture ships COLLAPSED, one row and 60 points at most, with the
/// rest one tap away. This is that rule as a type, so every line Play floats over the picture
/// goes through one door.
public struct StageLine: Equatable, Sendable {
    /// Everything, for the tap and for VoiceOver.
    public let full: String
    /// One line, for the picture.
    public let short: String

    /// - Parameter short: a summary written by whoever knows what the line means (a run's
    ///   outcome says "Stayed upright to the end"); nil takes the first sentence of `full`.
    public init(_ full: String, short: String? = nil) {
        self.full = full
        let given = short?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.short = StageLine.fitted((given?.isEmpty == false ? given : nil) ?? StageLine.firstSentence(of: full))
    }

    /// Whether a tap shows anything the collapsed line does not.
    public var hasMore: Bool { short != full }

    /// The tallest a collapsed line may be, points: the stage-overlay rule.
    public static let collapsedMaxHeight = 60.0

    /// The most characters the short line keeps before an ellipsis. A footnote line on the
    /// narrowest phone still supported holds about this many; the view also truncates.
    public static let shortMaxCharacters = 60

    /// The share of the stage an expanded line may take. A quarter, so a line expanded at the top
    /// of the picture can never reach the pad at the bottom (`StageViewport.drawerHeight` keeps
    /// the pad's own share well under the other three).
    public static let expandedMaxShare = 0.25

    /// The tallest an expanded line may be on a stage this tall, points.
    public static func expandedMaxHeight(stage: Double) -> Double {
        max(collapsedMaxHeight, stage * expandedMaxShare)
    }

    /// What VoiceOver says a tap does.
    public static let expandHint = "Shows the whole line."
    public static let collapseHint = "Folds it back to one line."

    /// The first sentence of `text`: up to the first ". ", or all of it.
    public static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stop = trimmed.range(of: ". ") else { return trimmed }
        return String(trimmed[..<stop.lowerBound])
    }

    /// `text` held to `shortMaxCharacters`, cut at a word and marked with an ellipsis. A full
    /// stop at the end of a single sentence is dropped: the line is a label, not prose.
    public static func fitted(_ text: String) -> String {
        var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasSuffix("."), !line.dropLast().contains(". ") { line.removeLast() }
        guard line.count > shortMaxCharacters else { return line }
        let cut = line.prefix(shortMaxCharacters - 1)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")) + "\u{2026}"
    }
}

extension Pipeline.BenchOutcome {
    /// A run's outcome as one line for the picture: the bench's own criterion when every
    /// rollout met it ("Stayed upright to the end, dropped from 0.120 m"), the count when some
    /// did not, and "ends low" when it finished crouched. `told` is the whole story, on tap.
    public var short: String {
        let met = criterion.prefix(1).uppercased() + criterion.dropFirst()
        var line = isClean ? met : "\(achieves) of \(rollouts) \(criterion)"
        if endedLow { line += ", ends low" }
        return line
    }
}
