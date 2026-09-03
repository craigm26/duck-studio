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
        // THE FOLDER KEEPS THE OLD NAME ON PURPOSE, and it is the one place the
        // rename stops. The tab is "Motions" now — Pollen's "intent" means a
        // command sent to the robot, not a recording — but this path is where
        // every motion a TestFlight tester already has is sitting. Renaming the
        // directory without moving the files empties their library; renaming it
        // WITH a migration is a data move to buy a word nobody can see. The
        // word was the point, and it was free everywhere it was visible.
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

    /// `rememberManifest` IS GONE, AND ITS LOOKUP WAS THE BUG. It matched the
    /// library on a display name while the community installer handed it
    /// `"\(manifest.name).onnx"` — a string the installer invented — so
    /// re-installing over an already-held, digest-named entry hit the silent
    /// `else { return }`, the manifest was never written, and the bench fell
    /// back to guessing the action scale from a file name that matched nothing.
    /// A wrong number on a working screen.
    ///
    /// The manifest now goes in with the weights, in ONE call: see
    /// `accept(_:named:origin:title:manifest:)` and `PolicyLibrary.persist`.

    /// The manifest stored with a policy, if it came with one.
    func manifest(for entry: PolicyLibrary.Entry) -> PolicyManifest? {
        PolicyLibrary.manifest(for: entry, in: container)
    }

    /// The action scale that policy declared, or nil to let the caller guess.
    func declaredScale(for entry: PolicyLibrary.Entry) -> Double? {
        PolicyLibrary.declaredScale(for: entry, in: container)
    }

    /// Remove a motion somebody brought in — sent to them, or kept from their
    /// own bench.
    ///
    /// EVERY MOTION IN THIS LIST IS THE PERSON'S OWN AND NONE OF IT COULD BE
    /// REMOVED. Recordings arrived by AirDrop, by Files, or from a bench, and
    /// once in they were permanent: there was no delete anywhere on the screen
    /// that listed them. Only the bundled clips are the app's, and those are
    /// not in this array.
    ///
    /// BY THE NAME ON DISK, WHICH IS THE EXPORT'S NAME. `acceptIntent` writes
    /// `intents/<export.name>.duckintent`, so that is the file to remove — and
    /// re-reading the directory afterwards is what makes the list agree with
    /// the disk rather than with what this method believes it did.
    @discardableResult
    func removeIntent(_ clip: DuckIntentClip) -> Bool {
        let url = intents.appendingPathComponent("\(clip.name).duckintent")
        defer { reloadIntents() }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            lastImport = "\(clip.name) could not be removed."
            return false
        }
    }

    /// Remove a policy the person brought in themselves.
    ///
    /// REFUSED FOR THE NINE THAT SHIPPED WITH THE APP, and `Entry.isRemovable`
    /// is where that is decided — their bytes are inside the read-only bundle,
    /// so this is what the filesystem allows rather than a rule invented here.
    @discardableResult
    func removePolicy(_ entry: PolicyLibrary.Entry) -> Bool {
        let gone = PolicyLibrary.remove(entry, from: container)
        if gone { reload() }
        return gone
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
    /// sites — `onOpenURL` and the Motions screen's importer — already have
    /// `drafts` in scope and should pass it. Until they do, a `.duckmove`
    /// arriving here is REFUSED BY NAME rather than filed somewhere it is not,
    /// because an import that lands in a list nobody is watching is the same
    /// silent failure in a new costume.
    func open(_ url: URL, into drafts: DraftStore, plans: PlanStore) {
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
        case "duckplan":
            // NOTHING CAN REACH THIS YET, AND THE BRANCH STAYS. `.duckplan` is
            // undeclared — no UTType, no CFBundleDocumentTypes row — and no
            // screen exports one, so iOS will not hand this app a plan and no
            // plan can leave it. Both halves are in `project.yml`'s comment,
            // written down rather than left for somebody to rediscover. It is
            // here so that the day a plan CAN travel between two phones, it
            // lands in Plans instead of in the Behaviours tab as a network that
            // will not load — which is what the default branch would call it.
            acceptPlan(data, named: name, into: plans)
        case "duck":
            // THIS APP NO LONGER WRITES ONE EITHER. The branch stays because
            // somebody may still have a `.duck` an older build exported, and
            // being told which of your files this app reads is more use than
            // the default's "not a policy".
            lastImport = "\(name) is a task file for other robot software. Microduck Studio keeps "
                       + "plans in its own format now — a `.duckplan` — and does not read this "
                       + "one."
        case "onnx":
            accept(data, named: name, origin: nil)
        default:
            lastImport = "\(name) was not added. Microduck Studio opens .onnx policies, .duckintent "
                       + "recordings and .duckmove motions — if this is a policy under another "
                       + "name, rename it to .onnx and hand it over again."
        }
    }

    /// A policy from anywhere — a file the system handed over, or bytes
    /// downloaded from a repository. `origin` names the host when it was
    /// fetched; nil means it arrived as a file.
    ///
    /// THE NAME AND THE MANIFEST GO IN WITH THE WEIGHTS. Both used to be lost
    /// on the way: the file name because `persist` wrote `<identity>.onnx` and
    /// nothing else, the manifest because it was a second call that looked the
    /// entry back up by a name that did not match. One call writes all three,
    /// so there is no window in which the bytes are on disk and what they are
    /// called is not.
    ///
    /// - Parameter title: the author's own word for the policy, when the caller
    ///   has one — the community installer reads it out of the manifest. It is
    ///   NOT a typed title: nobody has typed anything at this point, and the
    ///   ladder decides whether the author's claim is the one to show.
    /// - Returns: the entry, so a caller that needs to keep working with what it
    ///   just installed does not have to go looking for it by name.
    @discardableResult
    func accept(_ data: Data, named name: String, origin host: String?,
                title: String? = nil, manifest: Data? = nil) -> PolicyLibrary.Entry {
        let plate = PolicyNameplate(fileName: name, originHost: host)
        let entry = PolicyLibrary.entry(
            for: data, name: name,
            origin: host.map { PolicyLibrary.Origin.fetched(host: $0) } ?? .imported,
            nameplate: plate, authorName: title, arrivalWasRecorded: true)
        // Stored under its identity, so two people sending you `policy.onnx`
        // do not overwrite each other.
        try? PolicyLibrary.persist(data, entry: entry, into: container,
                                   manifest: manifest)
        var updated = library
        // BY IDENTITY, WHICH IS THE ONLY THING THAT ANSWERS "DO I ALREADY HAVE
        // THESE WEIGHTS". Looking the held entry up by name would find the
        // wrong one exactly when two files share a name, which is the case the
        // digest identity exists for.
        let held = library.entries.first { $0.identity == entry.identity }
        let added = updated.add(entry)
        lastImport = PolicyLibrary.arrivalMessage(added: added, incoming: entry, held: held)
        library = updated
        return added ? entry : (held ?? entry)
    }

    /// Rename a policy — a title only, and nothing else moves.
    ///
    /// NO `reload()`. A rename does not touch the weights, the identity, the
    /// manifest sidecar or the file name, so re-parsing nine ONNX files to see
    /// a string change would be the app doing eight hundred milliseconds of
    /// work to redraw one row.
    ///
    /// - Returns: the kit's refusal when there is one, so the sheet can show
    ///   the sentence rather than inventing a second wording of it.
    @discardableResult
    func rename(_ entry: PolicyLibrary.Entry, to typed: String?) -> PolicyTitleRule.Refusal? {
        switch PolicyLibrary.rename(entry, to: typed, in: container) {
        case .success(let renamed):
            var updated = library
            updated.replace(renamed)
            library = updated
            return nil
        case .failure(let refusal):
            return refusal
        }
    }

    /// A shared motion.
    ///
    /// Refused BY NAME rather than swallowed: a malformed intent is somebody
    /// else's export bug, and "that file could not be read" sends them looking
    /// in the wrong place. `IntentExport.ImportError` already says which frame
    /// and how many joints.
    /// - Returns: Whether the motion is now in the library.
    ///
    /// IT RETURNED VOID, AND A CALLER BELIEVED IT. Every failure here — a
    /// decode refusal, a directory that would not create, a write that threw —
    /// lands in `lastImport`, which the Behaviours tab renders. A screen that
    /// calls this and then reports its own success is reporting that it made
    /// the call, and `RemoteRunView` said "Kept — it is in your Motions" over
    /// every one of those failures, with the real message on a tab nobody was
    /// looking at.
    @discardableResult
    func acceptIntent(_ data: Data, named name: String) -> Bool {
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
            return true
        } catch let error as IntentExport.ImportError {
            lastImport = error.message
            return false
        } catch {
            lastImport = "That motion could not be saved."
            return false
        }
    }

    /// A plan written by this app, coming home.
    func acceptPlan(_ data: Data, named name: String, into plans: PlanStore) {
        do {
            let plan = try DuckPlanFile.read(data)
            guard plans.save(plan) else {
                lastImport = "\(plan.name) could not be written to this phone."
                return
            }
            lastImport = "\(plan.name) is in your Motions, under Plans."
        } catch let error as DuckPlanFile.ReadError {
            lastImport = error.message
        } catch {
            lastImport = error.localizedDescription
        }
    }

    /// A motion somebody WROTE, as opposed to one a policy performed.
    ///
    /// This is the format this app itself exports from the author screen, and
    /// until there was a branch for it, importing one of our own files filed it
    /// in the Behaviours tab as a network that will not load. `IntentDraft.decode`
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
