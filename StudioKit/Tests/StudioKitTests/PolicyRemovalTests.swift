import XCTest
import DuckKit
@testable import StudioKit

/// What a person may take back out of their own app.
///
/// THE RULE IS ABOUT THE FILESYSTEM, NOT ABOUT PROVENANCE. A policy Pollen
/// released is not protected for being Pollen's — one somebody DOWNLOADED from
/// Pollen lives in the container and is theirs to delete. The only thing that
/// cannot go is a file inside the read-only app bundle.
final class PolicyRemovalTests: XCTestCase {

    private func entry(_ name: String, _ origin: PolicyLibrary.Origin) -> PolicyLibrary.Entry {
        PolicyLibrary.entry(for: Data("not a real policy".utf8), name: name, origin: origin)
    }

    func testBundledPoliciesCannotBeRemoved() {
        XCTAssertFalse(entry("alpha_walking.onnx", .bundled).isRemovable)
        XCTAssertTrue(entry("alpha_walking.onnx", .bundled)
            .removalWarning.contains("came with the app"))
    }

    func testAnythingBroughtInCanBeRemoved() {
        XCTAssertTrue(entry("someones.onnx", .imported).isRemovable)
        XCTAssertTrue(entry("someones.onnx", .fetched(host: "huggingface.co")).isRemovable)
    }

    /// A POLLEN POLICY THE PERSON FETCHED IS STILL THEIRS. Being recognised by
    /// fingerprint puts a policy in the "Released by Pollen Robotics" section;
    /// it does not put the file in the app bundle.
    func testAFetchedPollenPolicyIsRemovable() {
        XCTAssertTrue(entry("alpha_walking.onnx", .fetched(host: "huggingface.co")).isRemovable)
    }

    /// The two risks wear the same button and must not read the same.
    func testTheWarningDistinguishesRefetchableFromGoneForever() {
        let fetched = entry("x.onnx", .fetched(host: "huggingface.co")).removalWarning
        XCTAssertTrue(fetched.contains("huggingface.co"))
        XCTAssertTrue(fetched.contains("downloaded again"))
        let imported = entry("x.onnx", .imported).removalWarning
        XCTAssertTrue(imported.contains("only copy"))
        XCTAssertFalse(imported.contains("downloaded again"),
                       "an AirDropped file cannot be re-fetched and must not say it can")
    }

    // MARK: - actually removing it

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("removal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRemovingTakesTheFileTheIdentityNamesRatherThanTheDisplayName() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("weights".utf8)
        // TWO FILES, ONE DISPLAY NAME. `persist` stores by identity precisely
        // so two people sending you `policy.onnx` do not collide, and a removal
        // that matched on the display name would delete the wrong one.
        let mine = PolicyLibrary.entry(for: data, name: "policy.onnx", origin: .imported)
        let theirs = PolicyLibrary.entry(for: Data("other weights".utf8),
                                         name: "policy.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: mine, into: dir)
        try PolicyLibrary.persist(Data("other weights".utf8), entry: theirs, into: dir)
        // TWO FILES EACH NOW: the weights and the nameplate that remembers what
        // they were called, which is the whole of this build's root fix.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 4)

        XCTAssertTrue(PolicyLibrary.remove(mine, from: dir))
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(left, ["\(theirs.identity.value).nameplate.json",
                              "\(theirs.identity.value).onnx"].sorted(),
                       "the other person's policy must survive, name and all")
    }

    func testRemovingABundledPolicyDoesNothingAndSaysSo() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = entry("alpha_walking.onnx", .bundled)
        // Even with a file sitting there under its identity, a bundled entry
        // must refuse: the real one is in the app bundle and this is not it.
        try PolicyLibrary.persist(Data("weights".utf8), entry: bundled, into: dir)
        XCTAssertFalse(PolicyLibrary.remove(bundled, from: dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2,
                       "the weights and their nameplate both stay put")
    }

    func testRemovingSomethingAlreadyGoneReportsFalseRatherThanThrowing() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(PolicyLibrary.remove(entry("x.onnx", .imported), from: dir))
    }
}

extension PolicyRemovalTests {

    /// A manifest belongs to the WEIGHTS, and goes when they go.
    func testAPolicysManifestIsStoredWithItAndRemovedWithIt() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("weights".utf8)
        let one = PolicyLibrary.entry(for: data, name: "happy-hop.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: one, into: dir)
        let manifest = Data("""
        {"schema_version":2,"model_api":1,"name":"happy-hop","obs_len":61,
         "action_len":14,"action_scale":1.0}
        """.utf8)
        XCTAssertTrue(PolicyLibrary.persistManifest(manifest, for: one, into: dir))

        // THE NUMBER THE APP WOULD OTHERWISE GUESS.
        XCTAssertEqual(PolicyLibrary.declaredScale(for: one, in: dir), 1.0)
        XCTAssertNotEqual(PolicyLibrary.declaredScale(for: one, in: dir), DuckModel.actionScale)

        XCTAssertTrue(PolicyLibrary.remove(one, from: dir))
        XCTAssertNil(PolicyLibrary.declaredScale(for: one, in: dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [],
                       "the manifest must not outlive the weights it describes")
    }

    func testAPolicyWithNoManifestDeclaresNothingRatherThanGuessing() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let one = PolicyLibrary.entry(for: Data("w".utf8), name: "x.onnx", origin: .imported)
        try PolicyLibrary.persist(Data("w".utf8), entry: one, into: dir)
        XCTAssertNil(PolicyLibrary.declaredScale(for: one, in: dir),
                     "nil is what tells the caller to fall back, and it must not be a number")
    }
}
