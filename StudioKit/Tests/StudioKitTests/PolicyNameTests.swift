import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// What a policy is CALLED, as opposed to what it is.
///
/// THE BUG THIS FILE EXISTS FOR IS INVISIBLE UNTIL THE SECOND LAUNCH. `persist`
/// wrote `<identity>.onnx` and nothing else, and `read(directory:)` named every
/// entry after the file it found — so the name a policy arrived under lived
/// exactly as long as the process that imported it. `reload()` runs at init and
/// after every successful removal, which is why deleting one imported policy
/// renamed every other imported entry to its own hash, mid-session, in front of
/// somebody.
///
/// So most of these are relaunch tests: persist, read back, and assert on what
/// came out — because the in-memory answer was always right and was never the
/// one people saw.
final class PolicyNameTests: XCTestCase {

    // MARK: - fixtures and scratch space

    private func policy(_ name: String) throws -> Data {
        let subdirectory = name.hasPrefix("synthetic") ? "Fixtures/refusals" : "Fixtures/policies"
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name.replacingOccurrences(of: ".onnx", with: ""),
            withExtension: "onnx", subdirectory: subdirectory), "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The fingerprint a set of bytes is filed under, which is also the name
    /// `persist` gives the file — and therefore the name a build-46 container
    /// hands back.
    private func identity(_ data: Data) -> String {
        PolicyLibrary.identityValue(for: data)
    }

    private func write(_ data: Data, as name: String, into dir: URL) throws {
        try data.write(to: dir.appendingPathComponent(name))
    }

    private func manifestBytes(named name: String) -> Data {
        Data("""
        {"schema_version":2,"model_api":1,"name":"\(name)","obs_len":61,
         "action_len":14,"action_scale":1.0}
        """.utf8)
    }

    // MARK: - 1. the relaunch that used to eat the name

    func testANameSurvivesTheRelaunchThatUsedToEatIt() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: dir)

        let reread = try XCTUnwrap(
            PolicyLibrary.read(directory: dir, origin: .imported, nameplatesIn: dir).first)
        XCTAssertEqual(reread.fileName, "flamingo.onnx")
        XCTAssertEqual(reread.title, "flamingo")
        XCTAssertEqual(reread.titleSource, .fileName)
    }

    // MARK: - 2-5. the ladder, rung by rung

    func testWithoutANameplateTheTitleSaysNothingIsKnown() throws {
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "\(identity(data)).onnx",
                                        origin: .imported)
        XCTAssertEqual(entry.titleSource, .digest)
        XCTAssertTrue(entry.title.hasPrefix("Unnamed policy "), entry.title)
        let explanation = try XCTUnwrap(entry.titleExplanation)
        XCTAssertTrue(explanation.contains("fingerprint"), explanation)
    }

    /// A CHECKED FACT ABOUT THE WEIGHTS BEATS A STRANGER'S CLAIM ABOUT THEM. A
    /// repo republishing Pollen's walk as "SuperWalk" does not get to relabel
    /// their network in somebody else's library.
    func testAPollenReleaseNamesItselfEvenWhenAManifestSaysOtherwise() throws {
        let data = try policy("alpha_walking.onnx")
        let entry = PolicyLibrary.entry(
            for: data, name: "\(identity(data)).onnx", origin: .imported,
            nameplate: nil, manifest: try PolicyManifest.decode(manifestBytes(named: "SuperWalk")),
            arrivalWasRecorded: false)
        XCTAssertEqual(entry.title, "alpha_walking")
        XCTAssertEqual(entry.titleSource, .release)
    }

    func testAManifestNamesAPolicyWhoseWeightsArentPollens() throws {
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(
            for: data, name: "\(identity(data)).onnx", origin: .imported,
            nameplate: nil,
            manifest: try PolicyManifest.decode(manifestBytes(named: "Flamingo cycle")),
            arrivalWasRecorded: false)
        XCTAssertEqual(entry.title, "Flamingo cycle")
        XCTAssertEqual(entry.titleSource, .manifest)
    }

    /// A manifest whose `name` is itself a hash names nothing, and using it
    /// would show a digest under a label claiming somebody wrote it.
    func testADigestShapedManifestNameIsNotUsedAsATitle() throws {
        let data = try policy("synthetic_valid.onnx")
        let hash = identity(data)
        let entry = PolicyLibrary.entry(
            for: data, name: "\(hash).onnx", origin: .imported,
            nameplate: nil, manifest: try PolicyManifest.decode(manifestBytes(named: hash)),
            arrivalWasRecorded: false)
        XCTAssertEqual(entry.titleSource, .digest)
    }

    // MARK: - 6-7. the file-name repair, and where it is refused

    func testAReleaseRepairNeverOverwritesARealFileName() throws {
        let data = try policy("alpha_walking.onnx")
        let entry = PolicyLibrary.entry(
            for: data, name: "\(identity(data)).onnx", origin: .imported,
            nameplate: PolicyNameplate(fileName: "mine.onnx"), manifest: nil,
            arrivalWasRecorded: true)
        XCTAssertEqual(entry.fileName, "mine.onnx",
                       "there was a name to lose, so the repair must not run")
    }

    /// A `.fileOnly` digest means the file would not load, so there are no
    /// parameters that could have matched — repairing there would name an
    /// unloadable file after a Pollen network.
    func testAReleaseRepairIsRefusedForAFileThatWouldNotLoad() throws {
        let data = Data("not a policy at all".utf8)
        let name = "\(identity(data)).onnx"
        let entry = PolicyLibrary.entry(for: data, name: name, origin: .imported)
        XCTAssertFalse(entry.identity.isNetworkIdentity)
        XCTAssertEqual(entry.fileName, name)
        XCTAssertEqual(entry.titleSource, .digest)
    }

    // MARK: - 8-9. where it came from

    /// `assembled` hard-coded `.imported` for the whole container, so
    /// "From huggingface.co/owner/name" became "Imported" at the next launch
    /// and the pill flipped from Community to Yours — the app crediting the
    /// phone's owner with somebody else's work.
    func testTheOriginComesBackInsteadOfDegradingToImported() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = "huggingface.co/RemiFabre/microduck-flamingo-cycle"
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "policy.onnx",
                                        origin: .fetched(host: host))
        try PolicyLibrary.persist(data, entry: entry, into: dir)

        let reread = try XCTUnwrap(
            PolicyLibrary.read(directory: dir, origin: .imported, nameplatesIn: dir).first)
        XCTAssertEqual(reread.origin, .fetched(host: host))
        XCTAssertTrue(reread.arrivalWasRecorded)
    }

    /// A BUNDLED FILE'S ORIGIN IS A FACT ABOUT THE BUNDLE. A sidecar in the
    /// container may hold a nickname for it — bundled policies are renamable —
    /// but it may not claim the app's own file came off a server.
    func testANameplateNeverOverridesBundled() throws {
        let bundle = try scratch()
        let container = try scratch()
        defer {
            try? FileManager.default.removeItem(at: bundle)
            try? FileManager.default.removeItem(at: container)
        }
        let data = try policy("alpha_walking.onnx")
        try write(data, as: "alpha_walking.onnx", into: bundle)
        PolicyLibrary.persistNameplate(
            PolicyNameplate(fileName: "alpha_walking.onnx", title: "Waddle v3",
                            originHost: "example.com/not-true"),
            forIdentity: identity(data), into: container)

        let entry = try XCTUnwrap(PolicyLibrary.read(directory: bundle, origin: .bundled,
                                                     nameplatesIn: container).first)
        XCTAssertEqual(entry.origin, .bundled)
        XCTAssertEqual(entry.title, "Waddle v3")
        XCTAssertEqual(entry.titleSource, .typed)
    }

    // MARK: - 10-15. renaming

    func testRenamingChangesTheTitleAndNothingElse() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: dir)

        let renamed = try XCTUnwrap(try? PolicyLibrary.rename(entry, to: "Waddle v3", in: dir).get())
        XCTAssertEqual(renamed.title, "Waddle v3")
        XCTAssertEqual(renamed.titleSource, .typed)
        XCTAssertEqual(renamed.fileName, entry.fileName)
        XCTAssertEqual(renamed.identity, entry.identity)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("\(entry.id).onnx").path),
            "the weights stay exactly where they were")
    }

    func testAnEmptyNameIsRefusedAndTheSentenceSaysWhatItStaysCalled() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "walk.onnx", origin: .imported)
        guard case .failure(let refusal) = PolicyLibrary.rename(entry, to: "   ", in: dir) else {
            return XCTFail("an empty name must be refused")
        }
        XCTAssertEqual(refusal, .empty)
        XCTAssertTrue(refusal.message(keeping: entry.title)
            .contains("It is still called \u{201C}walk\u{201D}"),
            refusal.message(keeping: entry.title))
    }

    /// It states the limit without claiming it is what a row can show: a row's
    /// capacity is a width under Dynamic Type, and at accessibility sizes it
    /// shows far fewer.
    func testALongNameIsRefusedWithItsLimit() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "walk.onnx", origin: .imported)
        let long = String(repeating: "a", count: PolicyTitleRule.maxLength + 1)
        guard case .failure(let refusal) = PolicyLibrary.rename(entry, to: long, in: dir) else {
            return XCTFail("a name over the limit must be refused")
        }
        XCTAssertEqual(refusal, .tooLong)
        let message = refusal.message(keeping: entry.title)
        XCTAssertTrue(message.contains("60"), message)
        XCTAssertFalse(message.contains("row can show"), message)
    }

    /// A title is never a file name any more, so a slash or a colon costs
    /// nothing — and refusing one would be this app enforcing a filesystem
    /// constraint on a string that never reaches a filesystem.
    func testNothingIsRefusedForASlashOrAColon() {
        guard case .success(let cleaned) = PolicyTitleRule.check("up/down: v2") else {
            return XCTFail("a slash and a colon are both fine in a title")
        }
        XCTAssertEqual(cleaned, "up/down: v2")
    }

    func testClearingANameReturnsToTheLadder() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: dir)
        let renamed = try XCTUnwrap(try? PolicyLibrary.rename(entry, to: "Waddle v3", in: dir).get())
        let cleared = try XCTUnwrap(try? PolicyLibrary.rename(renamed, to: nil, in: dir).get())
        XCTAssertEqual(cleared.titleSource, .fileName)
        XCTAssertEqual(cleared.title, "flamingo")
    }

    /// Clearing a title must NOT delete the plate: the plate is also where the
    /// file name lives, and throwing it away to clear a nickname would lose the
    /// one record of what the file was called.
    func testClearingAContainerNameKeepsThePlateBecauseItHoldsTheFileName() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: dir)
        _ = PolicyLibrary.rename(entry, to: "Waddle v3", in: dir)
        _ = PolicyLibrary.rename(entry, to: nil, in: dir)

        let plate = try XCTUnwrap(PolicyLibrary.nameplate(forIdentity: entry.id, in: dir))
        XCTAssertNil(plate.title)
        XCTAssertEqual(plate.fileName, "flamingo.onnx")
    }

    // MARK: - 16-18. the sidecar on disk

    func testANameplateIsNotReadBackAsAPolicy() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: dir)
        XCTAssertEqual(PolicyLibrary.read(directory: dir, origin: .imported).count, 1,
                       "the sidecar is not an .onnx and must not become an entry")
    }

    func testRemovingAPolicyTakesItsNameplateWithIt() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: dir,
                                  manifest: manifestBytes(named: "flamingo"))
        XCTAssertTrue(PolicyLibrary.remove(entry, from: dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [],
                       "the weights, the manifest and the name all go together")
    }

    /// Re-importing a policy you renamed must not wipe the name, the same way
    /// `persist`'s `fileExists` guard already protects the bytes.
    func testReImportingAPolicyDoesNotWipeTheNameYouGaveIt() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: dir)
        _ = PolicyLibrary.rename(entry, to: "Waddle v3", in: dir)

        // The same bytes arrive again, under the name they were sent with.
        let again = PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: again, into: dir)

        let reread = try XCTUnwrap(
            PolicyLibrary.read(directory: dir, origin: .imported, nameplatesIn: dir).first)
        XCTAssertEqual(reread.title, "Waddle v3")
        XCTAssertEqual(reread.titleSource, .typed)
    }

    // MARK: - 19-21. what the list and the pickers say

    /// TWO FILES CALLED `walk.onnx` IS THE COMMON CASE, not a contrived one: it
    /// is what a training run produces, and `add` keeps both because they are
    /// two networks. A picker showing one word twice is a picker that has
    /// stopped answering the question it was opened to answer.
    func testTwoPoliciesWithOneTitleAreDistinguishedInAPicker() throws {
        let a = PolicyLibrary.entry(for: Data("one set of weights".utf8),
                                    name: "walk.onnx", origin: .imported)
        let b = PolicyLibrary.entry(for: Data("another set of weights".utf8),
                                    name: "walk.onnx", origin: .imported)
        XCTAssertEqual(a.title, b.title, "they really do collide")
        let labels = PolicyLibrary.pickerLabels([a, b])
        XCTAssertNotEqual(labels[a.id], labels[b.id])
        XCTAssertTrue(try XCTUnwrap(labels[a.id]).contains(String(a.identity.value.prefix(8))))
        XCTAssertTrue(try XCTUnwrap(labels[b.id]).contains(String(b.identity.value.prefix(8))))
    }

    /// AND NOT ONE HEX CHARACTER OTHERWISE. Eight of them beside every row is
    /// the digest-as-a-name problem coming back through the picker.
    func testAPickerLabelIsJustTheTitleWhenNothingCollides() throws {
        let a = PolicyLibrary.entry(for: Data("one set of weights".utf8),
                                    name: "walk.onnx", origin: .imported)
        let b = PolicyLibrary.entry(for: Data("another set of weights".utf8),
                                    name: "spin.onnx", origin: .imported)
        let labels = PolicyLibrary.pickerLabels([a, b])
        XCTAssertEqual(labels[a.id], "walk")
        XCTAssertEqual(labels[b.id], "spin")
    }

    /// Being told "policy.onnx is already in your library" while the row says
    /// "Flamingo cycle" is the app answering a different question from the one
    /// that was asked.
    func testTheArrivalMessageNamesTheTitleYouAlreadyHaveItUnder() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        let incoming = PolicyLibrary.entry(for: data, name: "policy.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: incoming, into: dir)
        let held = try XCTUnwrap(try? PolicyLibrary.rename(incoming, to: "Flamingo cycle",
                                                           in: dir).get())
        XCTAssertEqual(
            PolicyLibrary.arrivalMessage(added: false, incoming: incoming, held: held),
            "You already have these weights. They are in your library as Flamingo cycle.")
        XCTAssertEqual(
            PolicyLibrary.arrivalMessage(added: true, incoming: held, held: nil),
            "Added Flamingo cycle.")
    }

    // MARK: - 22-23. what leaves the phone

    func testTheExportNameKeepsTheArrivingFileNameWhenItHasOne() throws {
        let data = try policy("synthetic_valid.onnx")
        let entry = PolicyLibrary.entry(
            for: data, name: "\(identity(data)).onnx", origin: .imported,
            nameplate: PolicyNameplate(fileName: "walk_v7.onnx", title: "Waddle"),
            manifest: nil, arrivalWasRecorded: true)
        XCTAssertEqual(entry.titleSource, .typed)
        XCTAssertEqual(entry.exportFileName, "walk_v7.onnx",
                       "a nickname is a thing on this phone; the file keeps its own name")
    }

    func testTheExportNameFallsBackToTheTitleAndThenToTheDigest() throws {
        let data = try policy("synthetic_valid.onnx")
        let digestName = "\(identity(data)).onnx"

        let named = PolicyLibrary.entry(
            for: data, name: digestName, origin: .imported,
            nameplate: PolicyNameplate(fileName: digestName, title: "Waddle v3"),
            manifest: nil, arrivalWasRecorded: true)
        XCTAssertEqual(named.exportFileName, "Waddle v3.onnx")

        let unnamed = PolicyLibrary.entry(for: data, name: digestName, origin: .imported)
        XCTAssertEqual(unnamed.exportFileName,
                       "policy-\(String(unnamed.identity.value.prefix(12))).onnx")

        // A TITLE HAS NO CHARACTER RULE and this is where that stops being
        // free: a slash makes a directory that does not exist, and the write
        // fails for a reason nobody can see.
        let awkward = PolicyLibrary.entry(
            for: data, name: digestName, origin: .imported,
            nameplate: PolicyNameplate(fileName: digestName, title: "up/down: v2"),
            manifest: nil, arrivalWasRecorded: true)
        XCTAssertFalse(awkward.exportFileName.contains("/"), awkward.exportFileName)
        XCTAssertFalse(awkward.exportFileName.contains(":"), awkward.exportFileName)
    }

    // MARK: - 24-26. the small predicates

    func testKindIsMatchedOnTheFileNameIncludingTheOlderBESTSpelling() {
        XCTAssertEqual(PolicyNaming.kind(forFileName: "BEST_alpha_stand.onnx"), .stand)
        XCTAssertEqual(PolicyNaming.kind(forFileName: "alpha_walking.onnx"), .walk)
        XCTAssertNil(PolicyNaming.kind(forFileName: "Waddle v3"),
                     "a title is not a file name and must match nothing")
    }

    func testADigestIsNotAName() {
        let hash = String(repeating: "a1b2c3d4", count: 8)
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(PolicyNaming.isDigestName(hash))
        XCTAssertTrue(PolicyNaming.isDigestName("\(hash).onnx"))
        XCTAssertFalse(PolicyNaming.isDigestName("alpha_walking.onnx"))
        XCTAssertFalse(PolicyNaming.isDigestName("abc.onnx"))
        XCTAssertEqual(PolicyNaming.subject(for: "\(hash).onnx"), "This file")
        XCTAssertEqual(PolicyNaming.subject(for: "alpha_walking.onnx"), "alpha_walking.onnx")
    }

    func testANameplateRoundTrips() throws {
        let plate = PolicyNameplate(fileName: "walk_v7.onnx", title: "Waddle v3",
                                    originHost: "huggingface.co/someone/walk")
        XCTAssertEqual(try PolicyNameplate.decode(plate.encoded()), plate)
        let bare = PolicyNameplate(fileName: "walk_v7.onnx")
        XCTAssertEqual(try PolicyNameplate.decode(bare.encoded()), bare)
    }

    func testANameplateFromTheFutureIsRefusedRatherThanGuessedAt() {
        let data = Data("""
        {"schema_version":2,"file_name":"walk.onnx","title":"Waddle"}
        """.utf8)
        XCTAssertThrowsError(try PolicyNameplate.decode(data)) { error in
            XCTAssertEqual(error as? PolicyNameplate.ReadError, .unsupportedSchema(2))
        }
    }

    func testANameplateWithoutAFileNameIsRefused() {
        let data = Data("""
        {"schema_version":1,"title":"Waddle"}
        """.utf8)
        XCTAssertThrowsError(try PolicyNameplate.decode(data)) { error in
            XCTAssertEqual(error as? PolicyNameplate.ReadError, .missing("file_name"))
        }
    }

    // MARK: - the three not-yets, said in the kit rather than in a view

    /// EACH OF THESE IS A CLAIM ABOUT WHAT THIS APP KNOWS, and each one is
    /// SCOPED — from this build onward, and not retroactively. That scope is
    /// exactly the part a sentence written in a SwiftUI view loses first, which
    /// is why all three are here where a test reads them letter by letter.
    func testTheThingsThisAppCannotRecoverAreSaidExactly() {
        XCTAssertEqual(PolicyNaming.fileNameUnknown, "not kept")
        XCTAssertTrue(PolicyNaming.fileNameNotKept.contains("did not keep what the file was called"),
                      PolicyNaming.fileNameNotKept)
        XCTAssertTrue(PolicyNaming.fileNameNotKept.contains("from now on"),
                      "the promise is scoped forward, not claimed retroactively")
        XCTAssertTrue(PolicyNaming.arrivalNotRecorded.contains("not recoverable"),
                      PolicyNaming.arrivalNotRecorded)
        XCTAssertTrue(PolicyNaming.arrivalNotRecorded.contains("from now on"),
                      "the pill stops flipping for imports from this build onward, and says so")
        XCTAssertTrue(PolicyNaming.recordingsNeedAFileName.contains("not built yet"),
                      "a not-yet names itself as one and promises no version")
        // NO INVENTED CAPABILITY ANYWHERE IN THE THREE.
        for sentence in [PolicyNaming.fileNameNotKept, PolicyNaming.arrivalNotRecorded,
                         PolicyNaming.recordingsNeedAFileName] {
            for forbidden in ["will be", "coming soon", "in a future"] {
                XCTAssertFalse(sentence.lowercased().contains(forbidden),
                               "\"\(forbidden)\" is a promise nothing here can keep: \(sentence)")
            }
        }
    }

    /// A RENAME IS A LABEL AND THE EXPLAINER SAYS SO ONCE. It is the only place
    /// the sheet tells somebody what renaming does not do, and the File name row
    /// staying put is the demonstration.
    func testTheRenameExplainerSaysWhatARenameDoesNotTouch() {
        XCTAssertTrue(PolicyTitleRule.explainer.contains("stays on this phone"),
                      PolicyTitleRule.explainer)
        XCTAssertTrue(PolicyTitleRule.explainer.contains("fingerprint"),
                      PolicyTitleRule.explainer)
    }

    /// The seal's label names the POLICY. `report.headline` names the FILE, and
    /// for a digest-named entry that is "This file is a Microduck policy" — a
    /// label that identifies nothing on the one control that says which row you
    /// are on.
    func testTheRowSealNamesThePolicyAndNotTheFile() throws {
        let runnable = PolicyLibrary.entry(for: try policy("roulade.onnx"),
                                           name: "spin.onnx", origin: .imported)
        XCTAssertEqual(runnable.runnabilityLabel, "roulade, a Microduck policy")
        let unreadable = PolicyLibrary.entry(for: Data("not a network".utf8),
                                             name: "spin.onnx", origin: .imported)
        XCTAssertEqual(unreadable.runnabilityLabel, "spin, not an ONNX model")
    }

    // MARK: - 27. the release gate

    /// EVERY TESTFLIGHT TESTER IS IN EXACTLY THIS STATE. Build a container the
    /// OLD way by hand — three digest-named `.onnx` files, one manifest
    /// sidecar, no nameplates anywhere — and run the real `assembled` over it.
    ///
    /// This is the one test that fails if the ladder is wired only into the
    /// import path and not into the read-back path, which is precisely the
    /// shape the original bug had.
    func testAContainerFromBuild46ComesBackNamed() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        // One with a manifest sidecar: loadable, and not one of Pollen's nine.
        let authored = try policy("synthetic_valid.onnx")
        try write(authored, as: "\(identity(authored)).onnx", into: dir)
        try manifestBytes(named: "Flamingo cycle")
            .write(to: dir.appendingPathComponent("\(identity(authored)).manifest.json"))

        // One whose weights match a release.
        let released = try policy("alpha_walking.onnx")
        try write(released, as: "\(identity(released)).onnx", into: dir)

        // One that is neither: it will not even load.
        let orphan = Data("this was never a network".utf8)
        try write(orphan, as: "\(identity(orphan)).onnx", into: dir)

        let library = PolicyLibrary.assembled(bundled: nil, container: dir)
        XCTAssertEqual(library.entries.count, 3)

        let byId = Dictionary(uniqueKeysWithValues: library.entries.map { ($0.id, $0) })
        let a = try XCTUnwrap(byId[identity(authored)])
        let b = try XCTUnwrap(byId[identity(released)])
        let c = try XCTUnwrap(byId[identity(orphan)])

        XCTAssertEqual(a.title, "Flamingo cycle")
        XCTAssertEqual(a.titleSource, .manifest)

        XCTAssertEqual(b.title, "alpha_walking")
        XCTAssertEqual(b.titleSource, .release)
        // THE REPAIR, AND WHAT IT BUYS: the bench's action-scale match and the
        // clip link both key on this string, and both missed on every
        // re-imported release.
        XCTAssertEqual(b.fileName, "alpha_walking.onnx")

        XCTAssertTrue(c.title.hasPrefix("Unnamed policy "), c.title)
        XCTAssertEqual(c.titleSource, .digest)
        XCTAssertEqual(c.fileName, "\(identity(orphan)).onnx",
                       "an unloadable file keeps the only name there is")

        for entry in [a, b, c] {
            XCTAssertFalse(entry.arrivalWasRecorded,
                           "\(entry.title): nothing wrote down where this came from")
        }
    }

    // MARK: - the file name is the only name anything matches on

    /// A plate written for an imported COPY of a bundled policy is keyed by
    /// identity, so the bundled entry reads it back. It may supply the title;
    /// it may never replace the bundle's file name, which every clip, kind
    /// and export is keyed on.
    func testAPlateForACopyNeverRenamesTheBundledFile() throws {
        let bundle = try scratch()
        let container = try scratch()
        defer {
            try? FileManager.default.removeItem(at: bundle)
            try? FileManager.default.removeItem(at: container)
        }
        let data = try policy("alpha_stand.onnx")
        try write(data, as: "alpha_stand.onnx", into: bundle)
        let copy = PolicyLibrary.entry(for: data, name: "junk.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: copy, into: container)

        let library = PolicyLibrary.assembled(bundled: bundle, container: container)
        let bundled = try XCTUnwrap(library.entries.first { $0.origin == .bundled })
        XCTAssertEqual(bundled.fileName, "alpha_stand.onnx")
        XCTAssertEqual(PolicyNaming.kind(forFileName: bundled.fileName), .stand)
    }

    /// The name a file first arrived under is a recorded observation of that
    /// import. The same bytes arriving again under another name are refused
    /// as already held, and the name on disk must not move under that refusal.
    func testASecondArrivalUnderAnotherNameKeepsTheFirstFileName() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        try PolicyLibrary.persist(
            data, entry: PolicyLibrary.entry(for: data, name: "flamingo.onnx", origin: .imported),
            into: dir)
        try PolicyLibrary.persist(
            data, entry: PolicyLibrary.entry(for: data, name: "policy.onnx",
                                             origin: .fetched(host: "huggingface.co/a/b")),
            into: dir)
        let reread = try XCTUnwrap(
            PolicyLibrary.read(directory: dir, origin: .imported, nameplatesIn: dir).first)
        XCTAssertEqual(reread.fileName, "flamingo.onnx")
        XCTAssertEqual(reread.title, "flamingo")
    }

    /// A rename observes nothing about where the bytes came from. A build-46
    /// entry with no plate says its arrival was not recorded, and it still
    /// says so after it has been given a name.
    func testRenamingALegacyEntryDoesNotClaimAnArrival() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try policy("synthetic_valid.onnx")
        try write(data, as: identity(data) + ".onnx", into: dir)
        let before = try XCTUnwrap(
            PolicyLibrary.read(directory: dir, origin: .imported, nameplatesIn: dir).first)
        XCTAssertFalse(before.arrivalWasRecorded)
        _ = PolicyLibrary.rename(before, to: "Waddle v3", in: dir)
        let after = try XCTUnwrap(
            PolicyLibrary.read(directory: dir, origin: .imported, nameplatesIn: dir).first)
        XCTAssertEqual(after.title, "Waddle v3")
        XCTAssertFalse(after.arrivalWasRecorded, "a rename is not an arrival")
    }
}
