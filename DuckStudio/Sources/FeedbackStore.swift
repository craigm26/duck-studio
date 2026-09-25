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

    @Published var share: DuckFeedback.Share {
        didSet { UserDefaults.standard.set(share.rawValue, forKey: Self.shareKey) }
    }
    @Published var routerAddress: String {
        didSet { UserDefaults.standard.set(routerAddress, forKey: Self.routerKey) }
    }
    @Published private(set) var counts: (all: Int, exportable: Int) = (0, 0)

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
