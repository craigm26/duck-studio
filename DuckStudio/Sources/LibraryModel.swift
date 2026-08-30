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
    ///
    /// `drafts` IS OPTIONAL ONLY BECAUSE OF WHERE THE STORES ARE BUILT, and
    /// that is a wiring fact rather than a design one. `DuckStudioApp` holds
    /// `LibraryModel` and `DraftStore` as two independent `@StateObject`s, so
    /// this model has no way to reach the live draft list on its own. Both call
    /// sites — `onOpenURL` and the Intents tab's importer — already have
    /// `drafts` in scope and should pass it. Until they do, a `.duckmove`
    /// arriving here is REFUSED BY NAME rather than filed somewhere it is not,
    /// because an import that lands in a list nobody is watching is the same
    /// silent failure in a new costume.
    func open(_ url: URL, into drafts: DraftStore) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            lastImport = "That file could not be read."
            return
        }
        let name = url.lastPathComponent
        // FOUR KINDS OF FILE ARRIVE HERE and they are not interchangeable. A
        // `.onnx` is a network and belongs in the policy library; a
        // `.duckintent` is a recorded motion and belongs beside the clips; a
        // `.duckmove` is a motion somebody WROTE and belongs in the drafts; a
        // `.duck` is a brief for a robot this app is not. Sending the second
        // down the first path produced "this file does not load" for a file
        // that is perfectly valid and simply is not a policy.
        //
        // THE `else` USED TO BE `accept`, AND THAT IS THE WHOLE BUG. Every
        // extension this app did not name went down the ONNX path, so the app's
        // own `.duckmove` was fingerprinted as a broken network, persisted into
        // the Policies container under its digest, and reported as
        // "Added slow bow.duckmove." — an affirmative false success over a row
        // that says the same file is not an ONNX model. A switch with a branch
        // per format and a NAMED refusal for the rest is what stops unrecognised
        // bytes inheriting the policy path by default.
        //
        // `onnx` IS STILL A BRANCH RATHER THAN THE DEFAULT, and it has to stay
        // one: `PolicyReport`'s `.unreadable` outcome — "the export stopped
        // mid-field, this was an interrupted run or a cut-off download" — is
        // this app's headline diagnosis, and it is asserted by test. Routing by
        // extension keeps it: a truncated `walk.onnx` is still named `.onnx` and
        // still gets its remedy. What it no longer catches is a policy handed
        // over under some other name, which the default branch names instead of
        // guessing at.
        switch url.pathExtension.lowercased() {
        case "duckintent":
            acceptIntent(data, named: name)
        case "duckmove":
            acceptMove(data, named: name, into: drafts)
        case "duck":
            // NO READER, AND SAYING SO IS THE HONEST ANSWER. `DuckTask.decode`
            // exists in StudioKit and works, but nothing in this target has a
            // place to put a task: there is no task store and no task screen,
            // and a decode whose success shows up in no list would be the
            // "Added" banner all over again. A `.duck` is written here to be
            // run by quackd elsewhere, so it arrives only through the Intents
            // tab's wildcard picker — which is exactly why this branch exists
            // rather than being left to the default.
            lastImport = "\(name) is a task file. Duck Studio writes these for quackd to run "
                       + "somewhere else and has no reader for one, so nothing was added."
        case "onnx":
            accept(data, named: name, origin: nil)
        default:
            lastImport = "\(name) was not added. Duck Studio opens .onnx policies, .duckintent "
                       + "recordings and .duckmove motions — if this is a policy under another "
                       + "name, rename it to .onnx and hand it over again."
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

    /// A motion somebody WROTE, as opposed to one a policy performed.
    ///
    /// This is the format this app itself exports from the author screen, and
    /// until there was a branch for it, importing one of our own files filed it
    /// in the Policies tab as a network that will not load. `IntentDraft.decode`
    /// reads the same bytes without complaint, so the failure was pure
    /// misrouting — nothing was wrong with the file.
    ///
    /// IT ACCUMULATES, WHICH DELIBERATELY BREAKS `acceptIntent`'s RULE. An
    /// intent is keyed by name so re-importing replaces it. A draft cannot be:
    /// `IntentDraft.decode` mints a fresh id per read and `DraftStore` keys by
    /// id, and matching on the name instead would let an incoming file clobber
    /// a draft somebody is in the middle of editing that happens to share it.
    /// Three imports of the same motion therefore leave three drafts, which is
    /// visible and swipe-deletable; the alternative is silent data loss.
    /// THE STORE IS NOT OPTIONAL, AND THAT IS THE POINT. An earlier shape took
    /// a `DraftStore?` and defaulted it to nil so the call sites could be left
    /// alone — which compiled everywhere and filed a motion nowhere, turning a
    /// finished import path into a door that opens onto a refusal. A parameter
    /// that can be omitted is a parameter that will be.
    func acceptMove(_ data: Data, named name: String, into drafts: DraftStore) {
        do {
            let draft = try IntentDraft.decode(data)
            drafts.save(draft)
            // FLUSHED, NOT LEFT TO SETTLE. `save` defers the write 0.4 s to
            // survive a slider drag; an import is a single event and the app
            // can be swiped away in far less than that, which would show the
            // motion in the list and lose the file.
            drafts.flush()
            lastImport = "Added the motion \(draft.name) to your drafts."
        } catch let error as IntentDraft.ImportError {
            // Refused BY NAME for the same reason `acceptIntent` is: the sender
            // needs to know which frame or which joint count is wrong, and
            // "that file could not be read" sends them to the wrong place.
            lastImport = "\(name) was not added. \(error.message)"
        } catch {
            lastImport = "\(name) could not be read as a motion."
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
