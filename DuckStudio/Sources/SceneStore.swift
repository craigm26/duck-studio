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

    /// Put this scene in the library at its own id: replace what is there, or
    /// add it.
    ///
    /// NEITHER `add` NOR `update` WOULD DO, AND THAT IS THE POINT. A challenge
    /// row builds the room it was scored in from a DETERMINISTIC id — the same
    /// rise gives the same UUID on every launch — so opening that row a second
    /// time must land on the scene that is already there rather than beside it.
    /// `add` would grow a new "Stairs challenge, 60 mm" per tap until the
    /// Author-against menu was a list of identical names; `update` would do
    /// nothing at all the first time, and the draft would open pointing at a
    /// scene that does not exist, which the editor draws as bare floor under a
    /// warning about a deleted scene.
    func ensure(_ scene: DuckScene) {
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes[index] = scene
        } else {
            scenes.append(scene)
        }
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
