import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// What the app holds, and the one place a file becomes an entry.
@MainActor
final class LibraryModel: ObservableObject {

    @Published private(set) var library = PolicyLibrary()
    @Published var lastImport: String?
    /// Motions somebody sent, kept beside the bundled corpus.
    @Published private(set) var importedClips: [DuckIntentClip] = []

    private var container: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Policies", isDirectory: true)
    }

    private var intents: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Intents", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        library = PolicyLibrary.assembled(
            bundled: Bundle.main.resourceURL, container: container)
        reloadIntents()
    }

    private func reloadIntents() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: intents, includingPropertiesForKeys: nil)) ?? []
        importedClips = urls
            .filter { $0.pathExtension == "duckintent" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let export = try? IntentExport.decode(data) else { return nil }
                return export.clip
            }
            .sorted { $0.name < $1.name }
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
        // TWO KINDS OF FILE ARRIVE HERE and they are not interchangeable. A
        // `.onnx` is a network and belongs in the policy library; a
        // `.duckintent` is a motion and belongs beside the clips. Sending the
        // second down the first path produced "this file does not load" for a
        // file that is perfectly valid and simply is not a policy.
        if url.pathExtension.lowercased() == "duckintent" {
            acceptIntent(data, named: url.lastPathComponent)
        } else {
            accept(data, named: url.lastPathComponent, origin: nil)
        }
    }

    /// A policy from anywhere — a file the system handed over, or bytes
    /// downloaded from a repository. `origin` names the host when it was
    /// fetched; nil means it arrived as a file.
    func accept(_ data: Data, named name: String, origin host: String?) {
        let entry = PolicyLibrary.entry(
            for: data, name: name,
            origin: host.map { PolicyLibrary.Origin.fetched(host: $0) } ?? .imported)
        // Stored under its identity, so two people sending you `policy.onnx`
        // do not overwrite each other.
        try? PolicyLibrary.persist(data, entry: entry, into: container)
        var updated = library
        lastImport = updated.add(entry)
            ? "Added \(entry.displayName)."
            : "\(entry.displayName) is already in your library."
        library = updated
    }

    /// A shared motion.
    ///
    /// Refused BY NAME rather than swallowed: a malformed intent is somebody
    /// else's export bug, and "that file could not be read" sends them looking
    /// in the wrong place. `IntentExport.ImportError` already says which frame
    /// and how many joints.
    func acceptIntent(_ data: Data, named name: String) {
        do {
            let export = try IntentExport.decode(data)
            try FileManager.default.createDirectory(
                at: intents, withIntermediateDirectories: true)
            // Keyed by the motion's name, so re-importing the same file
            // replaces it rather than accumulating copies.
            let url = intents.appendingPathComponent("\(export.name).duckintent")
            try data.write(to: url, options: .atomic)
            reloadIntents()
            lastImport = export.hasRecordedPath
                ? "Added the motion \(export.name)."
                : "Added \(export.name). It carries no path, so it plays on the spot — the sender's app was an older version."
        } catch let error as IntentExport.ImportError {
            lastImport = error.message
        } catch {
            lastImport = "That motion could not be saved."
        }
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
