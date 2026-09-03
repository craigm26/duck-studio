import SwiftUI
import StudioKit

/// The one pad map this phone holds.
///
/// `SceneStore`-SHAPED WITHOUT THE DEBOUNCE, and the absence is the decision. A
/// scene is edited by a slider under a finger, sixty times a second, so its
/// store coalesces writes; a map is edited by taps — a picker, a bind sheet, a
/// "put the pad back" — and there is never a burst. A debounce here would be
/// copying `SceneStore`'s complexity rather than its shape, and would leave a
/// window in which the map on screen and the map on disk disagree for no
/// reason.
///
/// ONE FILE, WRITTEN THROUGH THE KIT'S OWN ENCODER. `DuckPadMap.encoded()` is
/// hand-built JSON with a `format` string, which is house style and also the
/// only way a `[DuckPad.Control: Effect]` comes out readable by eye — see that
/// type's own note about what synthesised `Codable` does to a dictionary with a
/// non-string key.
///
/// AN UNREADABLE FILE IS THE SHIPPED MAP, NOT AN EMPTY ONE. A map written by a
/// newer build, or half-written by a crash, must not leave somebody with a pad
/// that does nothing: `reload` falls back to `DuckPadMap.defaults(in: .walk)`,
/// which is exactly what a fresh install gets, and the sticks still drive.
@MainActor
final class PadMapStore: ObservableObject {

    @Published private(set) var map: DuckPadMap = .defaults(in: .walk)

    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("padmap.json")
    }

    init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: file),
              let stored = try? DuckPadMap.decode(data) else {
            map = .defaults(in: .walk)
            return
        }
        map = stored
    }

    /// Write now. Every caller is a tap, so there is nothing to wait for.
    @discardableResult
    func save(_ map: DuckPadMap) -> Bool {
        self.map = map
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try map.encoded().write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Back to what the app ships with. The sequences are untouched — this
    /// changes what is bound to what and nothing else.
    func putThePadBack() {
        save(.defaults(in: .walk))
    }
}
