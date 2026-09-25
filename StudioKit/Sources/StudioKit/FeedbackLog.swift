import Foundation

/// Where a person's corrections and preferences are kept on the phone: one
/// `duck-feedback/0` record per line, appended, never rewritten.
///
/// NOTHING HERE SENDS ANYTHING. GATES.md commits this app to "Data Not
/// Collected": every request it makes goes to an address the person typed. So
/// the log is a file on the device, and the only way a record leaves is the
/// person exporting it through the share sheet — and even then `exportable`
/// hands over only the records whose consent says they may travel. A record
/// marked `local` is written (the person can see what they told the app) and
/// is never in an export.
///
/// APPEND-ONLY, BECAUSE A RECORD IS A THING THAT HAPPENED. Editing a line would
/// be rewriting what somebody said; a changed mind is a new record.
public enum FeedbackLog {

    public static let fileName = "duck-feedback.jsonl"

    /// The bytes to append for some records: one line each, newline-terminated.
    public static func appending(_ records: [DuckFeedback]) -> Data {
        Data(records.map { $0.jsonLine() + "\n" }.joined().utf8)
    }

    /// Lines in a log whose consent allows them to leave the device.
    ///
    /// READ FROM THE LINE, NOT FROM TODAY'S SETTING. A record written while the
    /// setting said `local` stays local after the person changes it to
    /// `research`; consent is what was agreed when the record was made.
    public static func exportable(_ log: String) -> [String] {
        log.split(separator: "\n").map(String.init).filter { line in
            guard let data = line.data(using: .utf8),
                  let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let consent = top["consent"] as? [String: Any],
                  consent["opt_in"] as? Bool == true,
                  let share = consent["share"] as? String,
                  let level = DuckFeedback.Share(rawValue: share) else { return false }
            return level != .local
        }
    }

    /// How many records a log holds, and how many of them may be exported.
    public static func counts(_ log: String) -> (all: Int, exportable: Int) {
        (log.split(separator: "\n").count, exportable(log).count)
    }

    // MARK: - the words

    /// The setting's title and its three choices, in a person's words.
    public static let settingTitle = "Share what you teach it"
    public static func settingChoice(_ share: DuckFeedback.Share) -> String {
        switch share {
        case .local: return "Keep on this phone"
        case .research: return "May be used for research"
        case .public: return "Share with the community"
        }
    }
    public static let settingFooter =
        "When you correct a plan or choose between two ducks, the app writes down what you "
      + "chose. It stays on this phone. Exporting sends only the records you allowed to leave; "
      + "contributing sends only records shared with the community, as a pull request on the "
      + "community dataset from your own Hugging Face account. Nothing is ever sent "
      + "automatically. A record carries no name, account or device identifier."
    public static func exportLine(all: Int, exportable: Int) -> String {
        let records = all == 1 ? "record" : "records"
        return "\(all) \(records) on this phone, \(exportable) of them allowed to leave it."
    }
    public static let exportButton = "Export shareable records"
}
