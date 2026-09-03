import SwiftUI
import StudioKit

/// What is unlocked on each move, kept between visits.
///
/// EVERYTHING STARTS HELD, AND THAT IS WHAT AN ABSENT FILE MEANS. A move nobody
/// has opened has no spec, and `MoveSearch.Spec.everythingHeld` is what it gets
/// — not a default set of handles somebody would then have to find and turn
/// off.
///
/// A HANDLE WHOSE KEYFRAME HAS LEFT THE MOVE IS DROPPED AND COUNTED, NEVER
/// RE-HOMED ONTO A NEIGHBOUR. `MoveSearch.draft(of:)` derives a keyframe's
/// identity from the keyframe itself — its ordinal, its time and its pose — so
/// an edited keyframe stops being the keyframe a saved handle named, which is
/// exactly when that handle's measured headroom went stale. Moving it to the
/// nearest surviving keyframe would put a lock on the wrong pose for a whole
/// run and nobody would see it; `MoveSearch.handlesDropped` says how many went.
///
/// THE COALESCED WRITE IS `DraftStore`'S, for the same reason it has one: a
/// stepper being dragged produces a change every frame, and a file write per
/// frame on the main actor is a stutter nobody can explain afterwards.
@MainActor
final class SearchSpecStore: ObservableObject {

    /// Keyed by the move's file name, which is the one string a spec is about.
    @Published private(set) var specs: [String: MoveSearch.Spec] = [:]
    /// How many handles the last load dropped, per file, so the screen can say
    /// so once rather than silently.
    @Published private(set) var dropped: [String: Int] = [:]

    private var pendingWrite: [String: Task<Void, Never>] = [:]
    private static let settleSeconds: Double = 0.4

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("SearchSpecs", isDirectory: true)
    }

    private func url(for file: String) -> URL {
        // The move's file name with its extension taken off, so a spec is
        // `best_r3_vault_60mm.json` next to nothing else.
        let stem = file.hasSuffix(".json") ? String(file.dropLast(5)) : file
        return directory.appendingPathComponent("\(stem).spec.json")
    }

    // MARK: - reading

    /// A pure read: safe to call from `body`. What is held, or everything
    /// held if nothing has been loaded for this move yet.
    func held(_ file: String, rise: Double) -> MoveSearch.Spec {
        specs[file] ?? MoveSearch.Spec.everythingHeld(file, rise: rise)
    }

    /// Loads and prunes, with every handle checked against the move it is
    /// about. Call from `.task` or `.onChange`, never from `body`: it
    /// publishes, and a publish from inside a view update is undefined.
    func load(file: String, rise: Double, in move: StairsChallenge.Move) {
        guard specs[file] == nil else { return }
        var loaded = load(file) ?? MoveSearch.Spec.everythingHeld(file, rise: rise)
        let living = Set(MoveSearch.draft(of: move).keys.map(\.id))
        let before = loaded.handles.count
        loaded.handles = loaded.handles.filter { handle in
            guard let keyframe = handle.keyframe else { return true }
            return living.contains(keyframe)
        }
        // A shape handle on a file that no longer declares bounds is the same
        // kind of stale, and the same answer.
        loaded.handles = loaded.handles.filter { handle in
            guard case .shape(let key) = handle.kind else { return true }
            return MoveSearch.declaredBounds(for: key, in: move) != nil
        }
        dropped[file] = before - loaded.handles.count
        specs[file] = loaded
    }

    private func load(_ file: String) -> MoveSearch.Spec? {
        guard let data = try? Data(contentsOf: url(for: file)) else { return nil }
        return try? JSONDecoder().decode(MoveSearch.Spec.self, from: data)
    }

    // MARK: - writing

    func save(_ spec: MoveSearch.Spec) {
        specs[spec.moveFile] = spec
        pendingWrite[spec.moveFile]?.cancel()
        pendingWrite[spec.moveFile] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleSeconds))
            guard !Task.isCancelled else { return }
            self?.write(spec)
            self?.pendingWrite[spec.moveFile] = nil
        }
    }

    /// Everything outstanding, now. Called when the screen closes, so leaving
    /// it is the moment the file is definitely current.
    func flush() {
        for (_, task) in pendingWrite { task.cancel() }
        pendingWrite.removeAll()
        for (_, spec) in specs { write(spec) }
    }

    private func write(_ spec: MoveSearch.Spec) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(spec) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: spec.moveFile), options: .atomic)
    }

    /// What to say about handles a move no longer has, or nil when none went.
    func droppedNote(for file: String) -> String? {
        guard let count = dropped[file], count > 0 else { return nil }
        return MoveSearch.handlesDropped(count)
    }
}
