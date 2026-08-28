import SwiftUI
import DuckKit
import StudioKit

/// The scenes this phone holds.
///
/// Kept as one JSON file rather than one per scene: a scene is a few hundred
/// bytes, the whole library is read at launch, and a directory of files is a
/// directory that can be half-written.
@MainActor
final class SceneStore: ObservableObject {

    @Published private(set) var scenes: [DuckScene] = []

    /// THE WHOLE LIBRARY IS ONE FILE, and the editor calls `update` on every
    /// slider tick, so the first version encoded and wrote every scene sixty
    /// times a second on the main actor while a finger was down. The published
    /// list changes at once; the file settles a moment later, or immediately on
    /// `flush()`.
    private var pendingWrite: Task<Void, Never>?
    private static let settleSeconds: Double = 0.4

    private var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("scenes.json")
    }

    init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode([DuckScene].self, from: data) else {
            // First launch: the starters, so the editor opens onto something
            // rather than onto an empty list and a plus button.
            scenes = DuckScene.starters
            save()
            return
        }
        scenes = stored
    }

    func add(_ scene: DuckScene) {
        scenes.append(scene)
        scheduleSave()
    }

    func update(_ scene: DuckScene) {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        scenes[index] = scene
        scheduleSave()
    }

    func delete(at offsets: IndexSet) {
        scenes.remove(atOffsets: offsets)
        // A deletion is worth writing at once: it is the one edit somebody
        // would be surprised to find undone.
        flush()
    }

    private func scheduleSave() {
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleSeconds))
            guard !Task.isCancelled else { return }
            self?.save()
            self?.pendingWrite = nil
        }
    }

    /// Write now. Called when an editor closes.
    func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(scenes) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
