import SwiftUI
import StudioKit

/// The retrieval plans kept on this phone.
///
/// IT EXISTS BECAUSE THE LOOP WAS OPEN. A fetch drafted here could only leave
/// as a `.duck` — quackd's format — and re-importing one was answered with
/// "nothing was added", because there was no store and no screen to put it in.
/// A plan the app writes and cannot take back is not a saved plan; it is a
/// receipt for one.
///
/// SHAPED LIKE `DraftStore`, deliberately: one JSON file per plan in Application
/// Support, reloaded on launch, no database. A plan is small — a name and four
/// measurements — so none of the coalescing `DraftStore` needs is warranted
/// here, and pretending otherwise would be copying its complexity rather than
/// its shape.
@MainActor
final class PlanStore: ObservableObject {

    @Published private(set) var plans: [DuckPlanFile] = []

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plans", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        plans = urls
            .filter { $0.pathExtension == "duckplan" }
            .compactMap { try? DuckPlanFile.read(try Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    /// Save, replacing any plan of the same name.
    ///
    /// BY NAME, NOT BY ID, BECAUSE A PLAN HAS NO ID. It is a measurement of an
    /// object plus a label; two plans with the same name are the same plan
    /// re-measured, and keeping both would leave somebody choosing between two
    /// identical rows.
    @discardableResult
    func save(_ plan: DuckPlanFile) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            // THE EXTENSION HAS TO SURVIVE `safeName`, and for one name it did
            // not. An empty title makes `fileName` ".duckplan" — non-empty, so
            // the nil guard passes — and `safeName`'s leading-dot rule strips
            // the dot and returns "duckplan", a file with no extension at all.
            // `reload()` filters on `pathExtension == "duckplan"`, so `save`
            // returned true for a plan that was never going to appear: the
            // silent success this whole format exists to stop.
            guard let safe = ExportFile.safeName(plan.fileName),
                  (safe as NSString).pathExtension == "duckplan" else { return false }
            try plan.encoded().write(to: directory.appendingPathComponent(safe), options: .atomic)
            reload()
            return true
        } catch {
            return false
        }
    }

    func delete(_ plan: DuckPlanFile) {
        guard let safe = ExportFile.safeName(plan.fileName) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(safe))
        reload()
    }
}
