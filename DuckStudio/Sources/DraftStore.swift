import SwiftUI
import DuckKit
import StudioKit

/// The motions being written on this phone.
@MainActor
final class DraftStore: ObservableObject {

    @Published private(set) var drafts: [IntentDraft] = []

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Drafts", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        drafts = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(IntentDraft.self, from: data)
            }
            .sorted { $0.name < $1.name }
    }

    func save(_ draft: IntentDraft) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(draft) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keyed by id, not by name: renaming a draft should rename it, not
        // leave a second copy under the old name.
        try? data.write(to: directory.appendingPathComponent("\(draft.id.uuidString).json"),
                        options: .atomic)
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        drafts.sort { $0.name < $1.name }
    }

    func delete(_ draft: IntentDraft) {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(draft.id.uuidString).json"))
        drafts.removeAll { $0.id == draft.id }
    }
}
