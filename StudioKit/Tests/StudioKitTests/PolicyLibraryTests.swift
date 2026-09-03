import XCTest
import DuckKit
@testable import StudioKit

/// Identity is what this type is for, so most of these are about identity.
final class PolicyLibraryTests: XCTestCase {

    private func fixture(_ subdirectory: String, _ file: String) throws -> Data {
        let base = file.replacingOccurrences(of: ".onnx", with: "")
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: base, withExtension: "onnx", subdirectory: subdirectory),
            "missing fixture \(file)")
        return try Data(contentsOf: url)
    }

    private func policies() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/policies", withExtension: nil))
    }

    /// The nine real networks all load. This is the floor: an inspector that
    /// cannot open the policies it ships with is not shippable.
    func testEveryVendoredPolicyLoads() throws {
        let entries = PolicyLibrary.read(directory: try policies(), origin: .bundled)
        XCTAssertEqual(entries.count, 9, "nine vendored networks")
        for entry in entries {
            XCTAssertTrue(entry.isRunnable, "\(entry.fileName): \(entry.report.reason)")
            XCTAssertTrue(entry.identity.isNetworkIdentity,
                          "a loadable policy is identified by its parameters")
        }
    }

    /// The whole reason identity is a digest and not a filename.
    func testTheSameNetworkUnderTwoNamesIsOneEntry() throws {
        let data = try fixture("Fixtures/policies", "alpha_walking.onnx")
        var library = PolicyLibrary()
        XCTAssertTrue(library.add(PolicyLibrary.entry(for: data, name: "alpha_walking.onnx", origin: .bundled)))
        XCTAssertFalse(library.add(PolicyLibrary.entry(for: data, name: "my_copy.onnx", origin: .imported)),
                       "a second copy under a new name is not a second policy")
        XCTAssertEqual(library.entries.count, 1)
        XCTAssertEqual(library.entries[0].origin, .bundled,
                       "first one wins, so a familiar entry does not silently change origin")
    }

    /// Two genuinely different networks are two entries even though every
    /// vendored file is within twenty bytes of the same size.
    func testDifferentNetworksAreDifferentEntries() throws {
        var library = PolicyLibrary()
        library.add(PolicyLibrary.entry(
            for: try fixture("Fixtures/policies", "alpha_walking.onnx"),
            name: "a.onnx", origin: .bundled))
        library.add(PolicyLibrary.entry(
            for: try fixture("Fixtures/policies", "roulade.onnx"),
            name: "b.onnx", origin: .bundled))
        XCTAssertEqual(library.entries.count, 2)
        XCTAssertNotEqual(library.entries[0].identity, library.entries[1].identity)
    }

    /// A file that will not load still gets kept, and gets the other kind of
    /// identity — because the refusal is the thing worth looking at.
    func testABrokenFileIsKeptAndIdentifiedByItsBytes() throws {
        let data = try fixture("Fixtures/refusals", "relu_instead_of_elu.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "mine.onnx", origin: .imported)
        XCTAssertFalse(entry.isRunnable)
        XCTAssertFalse(entry.identity.isNetworkIdentity,
                       "there are no parameters to digest, so it falls back to the file")
        XCTAssertEqual(entry.identity.value.count, 64)
        var library = PolicyLibrary()
        XCTAssertTrue(library.add(entry), "a refused policy still belongs in the library")
    }

    /// Ordering has to be total. Two different networks exported under one
    /// filename happens constantly during a training run, and without the
    /// identity tiebreak the list would reshuffle between launches.
    func testOrderingIsTotalEvenWhenNamesCollide() throws {
        let a = PolicyLibrary.entry(for: try fixture("Fixtures/policies", "alpha_walking.onnx"),
                                    name: "policy.onnx", origin: .imported)
        let b = PolicyLibrary.entry(for: try fixture("Fixtures/policies", "roulade.onnx"),
                                    name: "policy.onnx", origin: .imported)
        XCTAssertNotEqual(PolicyLibrary.ordering(a, b), PolicyLibrary.ordering(b, a),
                          "exactly one of the two orders must hold")

        var one = PolicyLibrary(); one.add(a); one.add(b)
        var other = PolicyLibrary(); other.add(b); other.add(a)
        XCTAssertEqual(one.entries.map(\.id), other.entries.map(\.id),
                       "insertion order must not change the result")
    }

    /// Bundled before imported before fetched, so the seed does not scatter.
    func testOriginDecidesTheSectionOrder() throws {
        let data = try fixture("Fixtures/policies", "alpha_walking.onnx")
        let other = try fixture("Fixtures/policies", "roulade.onnx")
        let third = try fixture("Fixtures/policies", "roller.onnx")
        var library = PolicyLibrary()
        library.add(PolicyLibrary.entry(for: third, name: "z.onnx", origin: .fetched(host: "huggingface.co")))
        library.add(PolicyLibrary.entry(for: other, name: "m.onnx", origin: .imported))
        library.add(PolicyLibrary.entry(for: data, name: "a.onnx", origin: .bundled))
        XCTAssertEqual(library.entries.map(\.origin),
                       [.bundled, .imported, .fetched(host: "huggingface.co")])
    }

    /// Stored under the identity, not the name someone else chose.
    func testPersistenceNamesFilesByIdentityNotByFilename() throws {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duck-studio-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }

        let first = try fixture("Fixtures/policies", "alpha_walking.onnx")
        let second = try fixture("Fixtures/policies", "roulade.onnx")
        let e1 = PolicyLibrary.entry(for: first, name: "policy.onnx", origin: .imported)
        let e2 = PolicyLibrary.entry(for: second, name: "policy.onnx", origin: .imported)
        let u1 = try PolicyLibrary.persist(first, entry: e1, into: container)
        let u2 = try PolicyLibrary.persist(second, entry: e2, into: container)
        XCTAssertNotEqual(u1, u2, "two files called policy.onnx must not collide")

        let reread = PolicyLibrary.read(directory: container, origin: .imported,
                                        nameplatesIn: container)
        XCTAssertEqual(reread.count, 2, "both survive a relaunch")
        // THE ASSERTION THIS TEST HAS ALWAYS BEEN MISSING. Storing by identity
        // was proved; keeping the name was not, and it was not kept — both came
        // back called after their own digests, which is the bug this whole
        // track exists to close.
        XCTAssertEqual(reread.map(\.fileName), ["policy.onnx", "policy.onnx"])
    }

    /// The root fix: bytes and a nameplate in ONE call, so the name cannot be
    /// lost between two of them.
    func testPersistWritesTheNameplateBesideTheWeights() throws {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duck-studio-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }
        let data = try fixture("Fixtures/policies", "roulade.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "spin.onnx", origin: .imported)
        try PolicyLibrary.persist(data, entry: entry, into: container)
        let plate = try XCTUnwrap(PolicyLibrary.nameplate(forIdentity: entry.id, in: container))
        XCTAssertEqual(plate.fileName, "spin.onnx")
        XCTAssertNil(plate.title, "nobody typed one, so nothing is written down as typed")
    }

    /// The manifest goes in the SAME call, which is what kills the silent drop:
    /// the old second hop looked the entry back up by display name and returned
    /// quietly when the name it was handed did not match the one on disk.
    func testPersistWritesTheManifestWhenOneIsHandedOver() throws {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duck-studio-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }
        let data = try fixture("Fixtures/policies", "roulade.onnx")
        let entry = PolicyLibrary.entry(for: data, name: "spin.onnx", origin: .imported)
        let manifest = Data("""
        {"schema_version":2,"model_api":1,"name":"happy-hop","obs_len":61,
         "action_len":14,"action_scale":1.0}
        """.utf8)
        try PolicyLibrary.persist(data, entry: entry, into: container, manifest: manifest)
        XCTAssertEqual(PolicyLibrary.declaredScale(for: entry, in: container), 1.0,
                       "the number the bench would otherwise guess")
    }

    /// A library of twelve files where four load is not a library of twelve
    /// policies, and the UI needs the honest number.
    func testRunnableCountIgnoresRefusedEntries() throws {
        var library = PolicyLibrary()
        library.add(PolicyLibrary.entry(for: try fixture("Fixtures/policies", "alpha_walking.onnx"),
                                        name: "good.onnx", origin: .bundled))
        library.add(PolicyLibrary.entry(for: try fixture("Fixtures/refusals", "output_13_actions.onnx"),
                                        name: "bad.onnx", origin: .imported))
        XCTAssertEqual(library.entries.count, 2)
        XCTAssertEqual(library.runnableCount, 1)
    }

    // MARK: - a policy this phone made

    /// A FOURTH ORIGIN, BECAUSE IT ANSWERS A QUESTION THE OTHER THREE CANNOT.
    /// Everything else in the library arrived from somewhere and its weights
    /// were somebody's before they were here. A tuned policy was made on this
    /// phone: nobody else has its digest, and only the residual is the person's
    /// own — which is what the caveat has to say.
    func testATunedOriginSaysWhoMadeItAndWhatIsStillSomebodyElses() {
        let origin = PolicyLibrary.Origin.tuned(base: "alpha_walking.onnx")
        XCTAssertEqual(origin.label, "Tuned here from alpha_walking.onnx")
        XCTAssertEqual(origin.author, "you")
        let caveat = XCTUnwrapOrEmpty(origin.caveat)
        XCTAssertTrue(caveat.contains("Nothing was trained"))
        XCTAssertTrue(caveat.contains("the walk is still the base policy's"))
        XCTAssertTrue(caveat.contains("never run on hardware"))
        // AND ONLY THIS ORIGIN CARRIES ONE. A caveat on every row is a caveat
        // nobody reads.
        for other in [PolicyLibrary.Origin.bundled, .imported, .fetched(host: "huggingface.co")] {
            XCTAssertNil(other.caveat)
            XCTAssertNotEqual(other.author, "you")
        }
    }

    /// IT SORTS LAST, WHICH IS ALSO NEWEST — the one kind of entry that did not
    /// exist at the previous launch belongs where somebody will look for a
    /// thing they just made.
    func testATunedPolicySortsAfterEverythingThatArrived() {
        XCTAssertTrue(PolicyLibrary.Origin.bundled < .tuned(base: "a"))
        XCTAssertTrue(PolicyLibrary.Origin.imported < .tuned(base: "a"))
        XCTAssertTrue(PolicyLibrary.Origin.fetched(host: "zzz.example") < .tuned(base: "a"))
        XCTAssertTrue(PolicyLibrary.Origin.tuned(base: "a") < .tuned(base: "b"))
    }

    /// THE ONE ENTRY THAT EXISTS NOWHERE ELSE. A bundled file comes back with
    /// the app and a fetched one comes back off a server; this was produced by
    /// a search on this phone and deleting it is deleting the only copy.
    func testRemovingATunedPolicyWarnsThatItIsTheOnlyCopy() {
        let entry = PolicyLibrary.Entry(
            fileName: "tuned-abc123.onnx",
            title: "tuned-abc123",
            titleSource: .fileName,
            origin: .tuned(base: "alpha_walking.onnx"),
            identity: .parameters("abc123"), byteCount: 791_584,
            report: PolicyReport.of(Data(), name: "tuned-abc123.onnx"))
        XCTAssertTrue(entry.isRemovable)
        XCTAssertTrue(entry.removalWarning.contains("only copy there has ever been"))
        XCTAssertTrue(entry.removalWarning.contains("alpha_walking.onnx"),
                      "and it names what it was made from, which is the reproducible half")
    }

    private func XCTUnwrapOrEmpty(_ text: String?) -> String { text ?? "" }
}
