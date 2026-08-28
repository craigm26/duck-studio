import SwiftUI
import DuckKit
import StudioKit

/// The motions being written on this phone.
@MainActor
final class DraftStore: ObservableObject {

    @Published private(set) var drafts: [IntentDraft] = []

    /// WRITING TO DISK IS NOT FREE AND THE EDITOR CALLS THIS PER FRAME. The
    /// author screen saves on every change so that nothing is lost to a
    /// swipe-down, and a joint slider being dragged produces a change every
    /// frame — so the first version encoded the draft and wrote a file, on the
    /// main actor, sixty times a second while a finger was down. The list
    /// updates immediately because that is what the UI reads; the file catches
    /// up shortly afterwards, or at once when `flush()` is called.
    private var pendingWrite: [UUID: Task<Void, Never>] = [:]

    /// How long to wait for the finger to stop. Long enough to coalesce a
    /// drag, short enough that a crash loses a moment rather than a session.
    private static let settleSeconds: Double = 0.4

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
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        drafts.sort { $0.name < $1.name }

        pendingWrite[draft.id]?.cancel()
        pendingWrite[draft.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleSeconds))
            guard !Task.isCancelled else { return }
            self?.write(draft)
            self?.pendingWrite[draft.id] = nil
        }
    }

    /// Write everything outstanding now. Called when an editor closes, so
    /// leaving the screen is the moment the file is definitely current.
    func flush() {
        for (_, task) in pendingWrite { task.cancel() }
        pendingWrite.removeAll()
        for draft in drafts { write(draft) }
    }

    private func write(_ draft: IntentDraft) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(draft) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keyed by id, not by name: renaming a draft should rename it, not
        // leave a second copy under the old name.
        try? data.write(to: directory.appendingPathComponent("\(draft.id.uuidString).json"),
                        options: .atomic)
    }

    func delete(_ draft: IntentDraft) {
        pendingWrite[draft.id]?.cancel()
        pendingWrite[draft.id] = nil
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(draft.id.uuidString).json"))
        drafts.removeAll { $0.id == draft.id }
    }
}
