import SwiftUI
import StudioKit

/// The sequences this phone holds — one file each, keyed by id.
///
/// BY UUID AND NOT BY NAME, WHICH IS THE ONE THING THAT DIFFERS FROM
/// `PlanStore`. A plan is a measurement of an object plus a label, so two plans
/// with one name are the same plan re-measured and keeping both would leave
/// somebody choosing between identical rows. A sequence is not: two takes
/// called "Fast turn" are two different drives, the map binds an ID, and a
/// store that overwrote by name would silently delete the take a button is
/// bound to. `DuckSequence.fileName` is the uuid, so the filesystem enforces it.
///
/// SHAPED LIKE `PlanStore` OTHERWISE: one directory in Application Support, one
/// small JSON file per row, reloaded on launch, no database. A sequence is tens
/// of steps.
///
/// A FILE IT CANNOT READ IS SKIPPED AND THE REST STILL LOAD, which is
/// `ModelEndpoint.decodeList`'s lesson written down: an all-or-nothing decode
/// means one bad row erases everything somebody has, and says nothing.
@MainActor
final class SequenceStore: ObservableObject {

    @Published private(set) var sequences: [DuckSequence] = []

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sequences", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        sequences = urls
            .filter { $0.pathExtension == "ducksequence" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? DuckSequence.decode(data)
            }
            // NEWEST FIRST, because the take somebody just made is the one they
            // are looking for.
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    @discardableResult
    func save(_ sequence: DuckSequence) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            guard let safe = ExportFile.safeName(sequence.fileName) else { return false }
            try sequence.encoded().write(to: directory.appendingPathComponent(safe),
                                         options: .atomic)
            reload()
            return true
        } catch {
            return false
        }
    }

    func delete(_ sequence: DuckSequence) {
        guard let safe = ExportFile.safeName(sequence.fileName) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(safe))
        reload()
    }

    /// Rename in place. The id does not move, so every button bound to this
    /// sequence keeps pointing at it.
    func rename(_ sequence: DuckSequence, to name: String) {
        var renamed = sequence
        renamed.name = name
        save(renamed)
    }

    func named(_ id: UUID) -> String? {
        sequences.first { $0.id == id }?.name
    }
}
