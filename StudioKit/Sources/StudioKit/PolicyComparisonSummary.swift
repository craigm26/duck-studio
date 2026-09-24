import Foundation

/// A distilled policy's comparison with its teacher, as sentences a card can show.
///
/// WRITTEN BY CODE FROM THE NUMBERS, NOT TAKEN FROM THE FILE. A manifest can
/// carry a `verdict.summary` its publisher wrote, and this reads it only as a
/// fallback: the same sentence rules applied to every community policy are the
/// only way two cards can be compared, and a publisher's prose is free to be
/// generous. Every line names both numbers, so a reader can disagree with the
/// wording and still have the measurement.
///
/// WHAT IS SAID AND WHAT IS NOT. Tracking error and falls are ratios to the
/// teacher from the same evaluation; getting up is a share of prone spawns.
/// The judge line is labelled as a model's judgement with the model named,
/// because a decision model's gap score is an opinion over these numbers, not
/// a fifth number. And simulation stays simulation: nothing here says a robot.
public enum PolicyComparisonSummary {

    /// Plain lines, most decisive first. Empty when nothing both sides measured
    /// is a metric this knows how to phrase.
    public static func lines(_ comparison: PolicyManifest.Comparison) -> [String] {
        let m = comparison.metrics
        var out: [String] = []

        func ratio(_ key: String) -> Double? {
            guard let pair = m[key], pair.teacher > 0 else { return nil }
            return pair.student / pair.teacher
        }

        if let falls = m["falls_per_min"], let r = ratio("falls_per_min") {
            let numbers = "\(format(falls.student, 2)) vs \(format(falls.teacher, 2)) a minute in sim"
            if r >= 1.15 {
                out.append("Falls \(format(r, 1))× as often as its teacher (\(numbers))")
            } else if r <= 0.87 {
                out.append("Falls less often than its teacher (\(numbers))")
            } else {
                out.append("Falls about as often as its teacher (\(numbers))")
            }
        }

        let planar = ratio("lin_err"), yaw = ratio("ang_err")
        if let p = planar, let y = yaw {
            out.append("Tracks velocity within \(percentOver(p)) (planar) and "
                       + "\(percentOver(y)) (turning) of its teacher")
        } else if let p = planar {
            out.append("Tracks velocity within \(percentOver(p)) of its teacher (planar)")
        }

        if let up = m["recovered_frac"] {
            out.append("Gets up from a fall \(percent(up.student)) of the time "
                       + "(teacher \(percent(up.teacher)))")
        }
        return out
    }

    /// The judge's line, e.g. "Jev judges: small gap to the teacher (1.1 of 3)".
    /// The score is an expected level, so it is rounded to name the nearest.
    public static func verdictLine(_ verdict: PolicyManifest.Verdict) -> String {
        let words = ["no gap", "small gap", "material gap", "severe gap"]
        let level = min(max(Int(verdict.gap.rounded()), 0), words.count - 1)
        let who = verdict.model.hasPrefix("jev") ? "Jev" : verdict.model
        return "\(who) judges: \(words[level]) to the teacher (\(format(verdict.gap, 1)) of 3)"
    }

    /// "5%" for a ratio of 1.05; "0%" at or below 1 (better than the teacher
    /// is still within 0% of it, and says no more than was measured).
    static func percentOver(_ r: Double) -> String {
        "\(Int(max(r - 1, 0) * 100 + 0.5))%"
    }

    static func percent(_ x: Double) -> String { "\(Int(x * 100 + 0.5))%" }

    static func format(_ x: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", x)
    }
}
