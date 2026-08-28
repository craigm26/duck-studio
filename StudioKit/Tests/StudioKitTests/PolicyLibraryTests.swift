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
            XCTAssertTrue(entry.isRunnable, "\(entry.displayName): \(entry.report.reason)")
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
        let third = try fixture("Fixtures/policies", "BEST_roller.onnx")
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

        let reread = PolicyLibrary.read(directory: container, origin: .imported)
        XCTAssertEqual(reread.count, 2, "both survive a relaunch")
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
}
