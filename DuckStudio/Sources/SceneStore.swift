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
        save()
    }

    func update(_ scene: DuckScene) {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        scenes[index] = scene
        save()
    }

    func delete(at offsets: IndexSet) {
        scenes.remove(atOffsets: offsets)
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
