import Foundation

/// Contributing what people taught the app to one public dataset, as a pull
/// request each person opens with their own Hugging Face account.
///
/// WHY A PULL REQUEST AND NOT AN UPLOAD. The community's corrections and
/// preferences belong in one place anyone can train from — Craig's call,
/// 2026-09-24 — and GATES.md forbids any endpoint this project runs. Hugging
/// Face's commit endpoint answers both: with `create_pr=1`, a person's own
/// write token opens a pull request on a public dataset they do not own. The
/// request goes to a service the person signed into, with their credential;
/// the dataset's maintainer reviews and merges; nothing passes through a
/// server of ours.
///
/// ONLY `public` RECORDS GO. A pull request on a public repository is readable
/// by everyone the moment it is opened, before anyone merges it, so a record
/// whose consent says `research` (a private dataset) is not eligible here —
/// that one stays export-only. Consent is read from each line as it was
/// written, not from today's setting.
///
/// THE PULL REQUEST CARRIES THE PERSON'S USERNAME. The records inside carry no
/// name, account or device identifier, but Hugging Face shows who opened the
/// pull request. The screen says so before anything is sent.
///
/// EACH RECORD IS CONTRIBUTED ONCE. The caller keeps the ids already sent and
/// passes them in; `pending` leaves those out, so pressing the button twice
/// does not put the same correction in the dataset twice.
public enum CommunityFeedback {

    public static let repository = HuggingFacePublish.Repository(
        namespace: "craigm26", name: "microduck-feedback", kind: .dataset)
    public static var datasetURL: URL {
        URL(string: "https://huggingface.co/datasets/\(repository.id)")!
    }
    public static let license = "CC0-1.0"

    /// Lines in a log that may go to the community dataset and have not yet.
    public static func pending(_ log: String, alreadySent: Set<String>) -> [(id: String, line: String)] {
        log.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard let data = line.data(using: .utf8),
                  let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  top["format"] as? String == DuckFeedback.format,
                  let id = top["id"] as? String, !alreadySent.contains(id),
                  let consent = top["consent"] as? [String: Any],
                  consent["opt_in"] as? Bool == true,
                  consent["share"] as? String == DuckFeedback.Share.public.rawValue else { return nil }
            return (id, line)
        }
    }

    /// Where a contribution lands in the dataset: dated, and named by a fresh
    /// UUID so two people contributing on one day never collide and the path
    /// says nothing about who they are.
    public static func path(at when: Date, contribution: UUID = UUID()) -> String {
        let day = ISO8601DateFormatter.string(from: when, timeZone: TimeZone(identifier: "UTC")!,
                                              formatOptions: [.withFullDate])
        return "contributions/\(day)/\(contribution.uuidString.lowercased()).jsonl"
    }

    public enum Refusal: Error, Equatable {
        case nothingToSend
        case noToken

        public var message: String {
            switch self {
            case .nothingToSend:
                return "There is nothing new to contribute. Only records written while sharing "
                     + "was set to \"\(FeedbackLog.settingChoice(.public))\" can go to the "
                     + "community dataset, and each goes once."
            case .noToken:
                return "Contributing opens a pull request from your Hugging Face account, so it "
                     + "needs a write token. Add one under Hugging Face in Settings."
            }
        }
    }

    /// The commit, as a pull request against the community dataset.
    public static func contribution(_ lines: [String], at when: Date = Date(),
                                    contribution: UUID = UUID()) throws -> HuggingFacePublish.Call {
        guard !lines.isEmpty else { throw Refusal.nothingToSend }
        let records = lines.count == 1 ? "record" : "records"
        let base = try HuggingFacePublish.commit(
            repository, summary: "Contribute \(lines.count) duck-feedback/0 \(records)",
            description: "Opened from Microduck Studio. Every record carries consent share=public; "
                       + "validate with `duckbatch feedback validate` before merging.",
            files: [HuggingFacePublish.File(path: path(at: when, contribution: contribution),
                                            contents: Data((lines.joined(separator: "\n") + "\n").utf8),
                                            isText: true)])
        var parts = URLComponents(url: base.url, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "create_pr", value: "1")]
        return HuggingFacePublish.Call(method: base.method, url: parts.url!,
                                       contentType: base.contentType, body: base.body)
    }

    /// The pull request Hugging Face opened, from the commit's answer.
    public static func pullRequest(from data: Data) -> URL? {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let link = top["pullRequestUrl"] as? String else { return nil }
        return URL(string: link)
    }

    // MARK: - the words

    public static let button = "Contribute to the community dataset"
    public static func explain(pending n: Int) -> String {
        let records = n == 1 ? "record" : "records"
        return "\(n) \(records) marked \"\(FeedbackLog.settingChoice(.public))\" not yet contributed. "
             + "Contributing opens a pull request on \(repository.id) from your Hugging Face "
             + "account, so your username is on the request; the records themselves carry no "
             + "name, account or device identifier. Contributed under \(license)."
    }
    /// The account the pull request will come from, shown BEFORE the button —
    /// Apple's terms for optional, user-initiated submissions ask that the
    /// person's name or account be prominent on the form, and it is simply
    /// the honest thing to show.
    public static func contributingAs(_ account: String) -> String {
        "Contributing as \(account) on Hugging Face"
    }
    public static let accountUnknown =
        "Add a Hugging Face write token under Hugging Face in Settings to contribute; the pull "
      + "request is opened from that account."
    public static func opened(_ url: URL) -> String { "Pull request opened: \(url.absoluteString)" }
    public static func failed(_ status: Int) -> String {
        "Hugging Face answered \(status), so nothing was contributed. Nothing was marked as sent."
    }
}
