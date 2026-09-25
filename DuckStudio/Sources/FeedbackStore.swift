import SwiftUI
import StudioKit

/// The feedback log on this phone, the person's sharing choice, and where the
/// plan router lives.
///
/// USERDEFAULTS-BACKED AND CONSTRUCTED WHERE IT IS USED, `EndpointStore`'s
/// trade: two instances read the same keys, so a choice made in Settings is
/// what the next screen opened reads. The log itself is one file, appended, so
/// two instances cannot disagree about it.
///
/// THE SHARING CHOICE DEFAULTS TO `.local`. Nothing a person does in this app
/// becomes shareable until they say so in Settings, and the choice is copied
/// into each record as it is written — see `FeedbackLog.exportable`.
@MainActor
final class FeedbackStore: ObservableObject {

    private static let shareKey = "duckstudio.feedback.share"
    private static let routerKey = "duckstudio.planRouter.address"
    private static let contributedKey = "duckstudio.feedback.contributed"

    @Published var share: DuckFeedback.Share {
        didSet { UserDefaults.standard.set(share.rawValue, forKey: Self.shareKey) }
    }
    @Published var routerAddress: String {
        didSet { UserDefaults.standard.set(routerAddress, forKey: Self.routerKey) }
    }
    @Published private(set) var counts: (all: Int, exportable: Int) = (0, 0)
    /// Public records not yet contributed to the community dataset.
    @Published private(set) var pendingContribution = 0
    /// The last contribution's outcome, in the kit's words.
    @Published private(set) var contributionLine: String?
    @Published private(set) var contributing = false
    /// The Hugging Face account a contribution would come from, when known.
    @Published private(set) var account: String?

    /// Ask Hugging Face whose token this is, so the form can say before the
    /// button which account the pull request will come from.
    func learnAccount(token: String?) async {
        guard let token, !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            account = nil
            return
        }
        let request = HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(), token: token)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { account = nil; return }
        account = HuggingFacePublish.parseWhoami(data)
    }

    init() {
        share = DuckFeedback.Share(
            rawValue: UserDefaults.standard.string(forKey: Self.shareKey) ?? "") ?? .local
        routerAddress = UserDefaults.standard.string(forKey: Self.routerKey) ?? ""
        recount()
    }

    /// The client string every record carries: the app and its version, nothing more.
    static var client: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "Microduck Studio \(version)"
    }

    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(FeedbackLog.fileName)
    }

    /// The router's base address, if what was typed is one.
    var routerURL: URL? {
        let typed = routerAddress.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: typed), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    /// Append records. A failure to write is swallowed on purpose: a correction
    /// that could not be logged must never stop the duck from running the plan.
    func append(_ records: [DuckFeedback]) {
        guard !records.isEmpty else { return }
        let data = FeedbackLog.appending(records)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: file, options: .atomic)
            }
        } catch {}
        recount()
    }

    private func recount() {
        let log = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        counts = FeedbackLog.counts(log)
        pendingContribution = CommunityFeedback.pending(log, alreadySent: contributed).count
    }

    /// Record ids already in a pull request. Kept so the button never sends one twice.
    private var contributed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.contributedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.contributedKey) }
    }

    /// Open a pull request on the community dataset with the person's own token.
    ///
    /// IDS ARE MARKED SENT ONLY AFTER HUGGING FACE SAYS YES. A failed request
    /// leaves every record pending, so the next press tries the same ones.
    func contribute(token: String?) async {
        guard !contributing else { return }
        guard account != nil else {
            contributionLine = CommunityFeedback.accountUnknown
            return
        }
        guard let token, !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            contributionLine = CommunityFeedback.Refusal.noToken.message
            return
        }
        let log = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let pending = CommunityFeedback.pending(log, alreadySent: contributed)
        contributing = true
        defer { contributing = false; recount() }
        do {
            let call = try CommunityFeedback.contribution(pending.map(\.line))
            let (data, response) = try await URLSession.shared.data(
                for: HuggingFacePublish.urlRequest(for: call, token: token))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                contributionLine = CommunityFeedback.failed(status)
                return
            }
            contributed.formUnion(pending.map(\.id))
            contributionLine = CommunityFeedback.pullRequest(from: data).map(CommunityFeedback.opened)
                ?? HuggingFacePublish.answered(status)
        } catch let refusal as CommunityFeedback.Refusal {
            contributionLine = refusal.message
        } catch {
            contributionLine = error.localizedDescription
        }
    }

    /// A temporary file of only the records allowed to leave, for the share sheet.
    func exportFile() -> URL? {
        let log = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let lines = FeedbackLog.exportable(log)
        guard !lines.isEmpty else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(FeedbackLog.fileName)
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
            return out
        } catch {
            return nil
        }
    }
}
