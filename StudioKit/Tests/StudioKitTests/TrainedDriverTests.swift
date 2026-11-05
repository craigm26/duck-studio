import XCTest
@testable import StudioKit

/// A real trained driver, downloaded from its Hugging Face repo, held to what the phone checks
/// before installing it. Skipped unless DUCK_DRIVER_DIR names a folder holding policy.json,
/// model.safetensors and golden.json: the weights are never committed here.
final class TrainedDriverTests: XCTestCase {
    func testADownloadedDriverIsOneThePhoneWouldInstall() throws {
        guard let dir = ProcessInfo.processInfo.environment["DUCK_DRIVER_DIR"] else {
            throw XCTSkip("set DUCK_DRIVER_DIR to a downloaded driver folder")
        }
        let root = URL(fileURLWithPath: dir)
        let read = { (name: String) in try Data(contentsOf: root.appendingPathComponent(name)) }
        let manifest = try DriverManifest.read(try read("policy.json"))
        let weights = try read(DriverManifest.weightsFile)
        let goldenData = try read(DriverManifest.goldenFile)
        XCTAssertTrue(manifest.matches(weights, path: DriverManifest.weightsFile))
        XCTAssertTrue(manifest.matches(goldenData, path: DriverManifest.goldenFile))
        let net = try DuckNetS1(SafeTensors(weights))
        let golden = try DriverGolden.read(goldenData)
        XCTAssertEqual(golden.seeds.count, 3)
        let problem = try DriverGolden.check(net: net, golden: golden)
        XCTAssertNil(problem, problem?.message ?? "")
        print("trained driver: task \(manifest.task), label \(manifest.label), val L1 \(manifest.valL1 ?? .nan), "
            + "zero \(manifest.baselineZeroL1 ?? .nan), repeat \(manifest.baselineRepeatL1 ?? .nan), "
            + "snap \(manifest.outputSnap.map { "\($0.forwardZeroBelow)/\($0.forwardStart)/\($0.turnZeroBelow)" } ?? "none")")
        if let snap = manifest.outputSnap { XCTAssertTrue(snap.isValid) }
    }
}
