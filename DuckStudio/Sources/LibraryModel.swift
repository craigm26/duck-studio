import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// What the app holds, and the one place a file becomes an entry.
@MainActor
final class LibraryModel: ObservableObject {

    @Published private(set) var library = PolicyLibrary()
    @Published var lastImport: String?

    private var container: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Policies", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        library = PolicyLibrary.assembled(
            bundled: Bundle.main.resourceURL, container: container)
    }

    /// Take a file the system handed us.
    ///
    /// A security-scoped resource, because the URL points outside this app's
    /// container: without the start/stop pair the read fails on a file picked
    /// from iCloud Drive, and it fails silently as "no such file" rather than
    /// as a permission error, which sends you looking in the wrong place.
    func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            lastImport = "That file could not be read."
            return
        }
        let entry = PolicyLibrary.entry(for: data, name: url.lastPathComponent, origin: .imported)
        // Stored under its identity, so two people sending you `policy.onnx`
        // do not overwrite each other.
        try? PolicyLibrary.persist(data, entry: entry, into: container)
        var updated = library
        lastImport = updated.add(entry)
            ? "Added \(entry.displayName)."
            : "\(entry.displayName) is already in your library."
        library = updated
    }

    /// Where a policy came from, answered from its weights rather than from
    /// which folder it arrived in.
    func standing(for entry: PolicyLibrary.Entry) -> DuckOfficialPolicies.Standing {
        guard case .parameters(let fingerprint) = entry.identity else {
            // A file that will not load has no parameters to fingerprint, so
            // the question cannot be asked of it at all.
            return .unrecognised
        }
        return DuckOfficialPolicies.standing(ofFingerprint: fingerprint)
    }
}
