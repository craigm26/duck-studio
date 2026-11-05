import XCTest
@testable import StudioKit

/// Getting a driver onto a device: nothing counts as installed until it passed everything, and
/// nothing is left behind when it does not. The files are `Fixtures/ducknet-s1`, a real driver; only
/// the network is a stand-in.
final class PhoneDriverInstallTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("driver-install-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/ducknet-s1/\(name)", withExtension: nil))
        return try Data(contentsOf: url)
    }

    /// A release pinned to the fixture's own files, or to `policy` when a test edits it.
    private func release(policy: Data? = nil) throws -> DriverRelease {
        let bytes = try (policy ?? fixture("policy.json"))
        let manifest = try DriverManifest.read(bytes)
        return DriverRelease(repo: "someone/duck-driver-test", revision: "abcdef0123456789",
                             policySHA256: DriverHash.hex(bytes),
                             weightsSHA256: try XCTUnwrap(manifest.files["model.safetensors"]).sha256,
                             bytes: bytes.count + manifest.files.values.map(\.bytes).reduce(0, +),
                             freshRuns: 20, freshReached: 20, freshParked: 14)
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var phases: [DriverInstall.Phase] = []
        private var files: [String] = []
        func heard(_ p: DriverInstall.Phase) { lock.withLock { phases.append(p) } }
        func asked(_ f: String) { lock.withLock { files.append(f) } }
        var all: [DriverInstall.Phase] { lock.withLock { phases } }
        var asked: [String] { lock.withLock { files } }
    }

    /// Serves the fixture, by file name, with any edit, half way then whole.
    private func server(_ log: Log, edit: [String: Data] = [:]) throws -> DriverInstaller.Fetch {
        var files: [String: Data] = [:]
        for name in ["policy.json", "model.safetensors", "golden.json"] { files[name] = try edit[name] ?? fixture(name) }
        let served = files
        return { url, limit, progress in
            log.asked(url.lastPathComponent)
            let data = try XCTUnwrap(served[url.lastPathComponent])
            XCTAssertGreaterThanOrEqual(limit, min(data.count, DriverInstaller.policyLimit))
            progress(data.count / 2)
            progress(data.count)
            return data
        }
    }

    private func left() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] }

    // MARK: - the pin

    func testTheShippedPinIsTheMeasuredDriverAtItsPublicAddress() {
        let r = DriverRelease.walkToBall
        XCTAssertEqual(r.repo, "craigm26/duck-driver-walk-to-ball-v6")
        XCTAssertEqual(r.revision, "5985110aefdef3da98dfcbebe939a77da631de5a")
        XCTAssertTrue(r.weightsSHA256.hasPrefix("d1a10157"))
        XCTAssertEqual(r.url("policy.json").absoluteString,
                       "https://huggingface.co/craigm26/duck-driver-walk-to-ball-v6/resolve/5985110aefdef3da98dfcbebe939a77da631de5a/policy.json")
        XCTAssertEqual(r.size, "4.4 MB")
        XCTAssertEqual(r.folder, "duck-driver-walk-to-ball-v6-5985110")
        XCTAssertEqual([r.freshRuns, r.freshReached, r.freshParked], [20, 19, 17])
    }

    // MARK: - installing

    func testADriverThatPassesIsInstalledAndWholeAndSaysSoInOrder() async throws {
        let log = Log()
        let release = try release()
        let installer = DriverInstaller(release: release, root: root)
        XCTAssertEqual(installer.status(), .absent)
        try await installer.install(fetch: try server(log), report: log.heard)

        XCTAssertEqual(log.asked, ["policy.json", "model.safetensors", "golden.json"])
        XCTAssertEqual(log.all.last, .installed)
        XCTAssertEqual(log.all.dropLast().last, .checking)
        guard case .getting(let lastDone, let total) = log.all[log.all.count - 3] else { return XCTFail("\(log.all)") }
        XCTAssertEqual(lastDone, total, "progress ends at all of it")
        XCTAssertEqual(total, release.bytes)
        XCTAssertEqual(installer.status(), .installed)
        XCTAssertEqual(left(), [release.folder], "no side folder stays")
        // And what is kept loads the way a run loads it.
        XCTAssertNoThrow(try DriverTrial.load(folder: installer.folder.path, decode: { _ in nil }))
    }

    func testChangedWeightsAreNeverInstalled() async throws {
        let log = Log()
        var weights = try fixture("model.safetensors")
        weights[weights.count - 1] ^= 1
        let installer = DriverInstaller(release: try release(), root: root)
        do {
            try await installer.install(fetch: try server(log, edit: ["model.safetensors": weights]), report: log.heard)
            XCTFail("installed")
        } catch let problem as DriverInstall.Problem {
            XCTAssertEqual(problem, .notThePinnedFile("model.safetensors"))
            XCTAssertTrue(problem.message.contains("not installed"))
        }
        XCTAssertEqual(installer.status(), .absent)
        XCTAssertEqual(left(), [])
    }

    func testAPolicyThatIsNotThePinnedOneStopsBeforeAnyWeights() async throws {
        let log = Log()
        let installer = DriverInstaller(release: try release(), root: root)
        do {
            try await installer.install(fetch: try server(log, edit: ["policy.json": Data("{}".utf8)]), report: log.heard)
            XCTFail("installed")
        } catch let problem as DriverInstall.Problem {
            XCTAssertEqual(problem, .notThePinnedFile("policy.json"))
        }
        XCTAssertEqual(log.asked, ["policy.json"])
    }

    /// Hashes that match and answers that do not: only the golden replay can catch this.
    func testAFailedGoldenReplayIsNotInstalledAndIsSaidInWords() async throws {
        var golden = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("golden.json")) as? [String: Any])
        var outputs = try XCTUnwrap(golden["outputs"] as? [[Double]])
        outputs[0][0] += 1
        golden["outputs"] = outputs
        let wrong = try JSONSerialization.data(withJSONObject: golden)
        var policy = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("policy.json")) as? [String: Any])
        var files = try XCTUnwrap(policy["files"] as? [String: Any])
        files["golden.json"] = ["sha256": DriverHash.hex(wrong), "bytes": wrong.count]
        policy["files"] = files
        let edited = try JSONSerialization.data(withJSONObject: policy)

        let log = Log()
        let installer = DriverInstaller(release: try release(policy: edited), root: root)
        do {
            try await installer.install(fetch: try server(log, edit: ["policy.json": edited, "golden.json": wrong]),
                                        report: log.heard)
            XCTFail("installed")
        } catch let problem as DriverInstall.Problem {
            guard case .golden(let why) = problem else { return XCTFail("\(problem)") }
            XCTAssertTrue(why.contains("golden replay"), why)
        }
        XCTAssertEqual(log.all.last, .checking)
        XCTAssertEqual(installer.status(), .absent)
        XCTAssertEqual(left(), [])
    }

    func testCancelLeavesNothing() async throws {
        let installer = DriverInstaller(release: try release(), root: root)
        let policy = try fixture("policy.json")
        let fetch: DriverInstaller.Fetch = { url, _, _ in
            if url.lastPathComponent == "policy.json" { return policy }
            throw CancellationError()
        }
        do {
            try await installer.install(fetch: fetch, report: { _ in })
            XCTFail("installed")
        } catch is CancellationError {}
        XCTAssertEqual(installer.status(), .absent)
        XCTAssertEqual(left(), [])
    }

    func testANetworkFailureIsSaidAsOne() async throws {
        struct Down: LocalizedError { var errorDescription: String? { "no route" } }
        let installer = DriverInstaller(release: try release(), root: root)
        do {
            try await installer.install(fetch: { _, _, _ in throw Down() }, report: { _ in })
            XCTFail("installed")
        } catch let problem as DriverInstall.Problem {
            XCTAssertEqual(problem, .download("no route"))
            XCTAssertEqual(problem.message, "The download stopped: no route")
        }
    }

    // MARK: - what is on disk

    func testADamagedDriverIsNotInstalledAndIsRemoved() async throws {
        for damage in ["model.safetensors", "golden.json", "policy.json"] {
            let installer = DriverInstaller(release: try release(), root: root)
            try await installer.install(fetch: try server(Log()), report: { _ in })
            XCTAssertEqual(installer.status(), .installed)
            let file = installer.folder.appendingPathComponent(damage)
            var bytes = try Data(contentsOf: file)
            bytes[0] ^= 1
            try bytes.write(to: file)
            XCTAssertEqual(installer.status(), .absent, damage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: installer.folder.path), damage)
        }
    }

    func testAMissingFileIsAbsent() async throws {
        let installer = DriverInstaller(release: try release(), root: root)
        try await installer.install(fetch: try server(Log()), report: { _ in })
        try FileManager.default.removeItem(at: installer.folder.appendingPathComponent("golden.json"))
        XCTAssertEqual(installer.status(), .absent)
    }

    func testASideFolderFromAKilledInstallIsCleared() throws {
        let installer = DriverInstaller(release: try release(), root: root)
        let side = root.appendingPathComponent(installer.release.folder + DriverInstaller.partialSuffix)
        try FileManager.default.createDirectory(at: side, withIntermediateDirectories: true)
        XCTAssertEqual(installer.status(), .absent)
        XCTAssertEqual(left(), [])
    }

    func testAnOlderPinIsRemovedAndTheCurrentOneAndAnythingElseStay() async throws {
        let installer = DriverInstaller(release: try release(), root: root)
        try await installer.install(fetch: try server(Log()), report: { _ in })
        for name in ["duck-driver-walk-to-ball-v5-fe94d4a", "not-a-driver"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
        XCTAssertEqual(installer.status(), .installed)
        XCTAssertEqual(left().sorted(), [installer.release.folder, "not-a-driver"].sorted())
    }

    func testDeleteTakesItOffTheDevice() async throws {
        let installer = DriverInstaller(release: try release(), root: root)
        try await installer.install(fetch: try server(Log()), report: { _ in })
        try installer.delete()
        XCTAssertEqual(installer.status(), .absent)
        XCTAssertEqual(left(), [])
        XCTAssertNoThrow(try installer.delete(), "deleting nothing is fine")
    }
}
