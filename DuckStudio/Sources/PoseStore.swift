import Foundation
import SwiftUI
import StudioKit

/// The poses this phone holds, one `.duckpose` file each, keyed by id.
///
/// SHAPED LIKE `SequenceStore`: one directory in Application Support, one small
/// JSON file per row, reloaded on launch, a file it cannot read skipped so the
/// rest still load. Unlike a sequence, a pose's NAME is how the chat finds it,
/// so `keep` makes names unique (`PoseLibrary.uniqueName`) rather than letting
/// two "Wing up"s hide one another.
///
/// Injected as an environment object at the app's root, beside the router,
/// because Play, Moves and the chat all read it and none of them owns it.
@MainActor
final class PoseStore: ObservableObject {

    @Published private(set) var poses: [DuckPose] = []

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Poses", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        poses = urls
            .filter { $0.pathExtension == DuckPose.fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? DuckPose.decode(data)
            }
            .sorted { $0.madeAt > $1.madeAt }
    }

    /// Keep a new pose under a name nobody else in the library has.
    @discardableResult
    func keep(named name: String, about: String = "", angles: [Double],
              source: DuckPose.Source = .posed) -> DuckPose? {
        let pose = DuckPose(name: PoseLibrary.uniqueName(name, in: poses), about: about,
                            angles: angles, source: source)
        return save(pose) ? pose : nil
    }

    /// Keep a pose made elsewhere (mirrored, between, or opened from a file),
    /// renamed if its name is taken by a different pose.
    @discardableResult
    func keep(_ pose: DuckPose) -> DuckPose? {
        var kept = pose
        let others = poses.filter { $0.id != pose.id }
        kept.name = PoseLibrary.uniqueName(pose.name, in: others)
        return save(kept) ? kept : nil
    }

    @discardableResult
    private func save(_ pose: DuckPose) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            guard let safe = ExportFile.safeName(pose.fileName) else { return false }
            try pose.encoded().write(to: directory.appendingPathComponent(safe), options: .atomic)
            reload()
            return true
        } catch {
            return false
        }
    }

    func delete(_ pose: DuckPose) {
        guard let safe = ExportFile.safeName(pose.fileName) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(safe))
        reload()
    }

    /// Rename and re-describe in place; the id does not move.
    func edit(_ pose: DuckPose, name: String, about: String) {
        var changed = pose
        changed.name = PoseLibrary.uniqueName(name, in: poses.filter { $0.id != pose.id })
        changed.about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        save(changed)
    }

    /// The file to hand to the share sheet, written to the temporary folder.
    func exportURL(for pose: DuckPose) -> URL? {
        guard let data = try? pose.encoded() else { return nil }
        let name = (ExportFile.safeName(pose.name) ?? "pose") + "." + DuckPose.fileExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }
}
