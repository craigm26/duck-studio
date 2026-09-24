import XCTest
import DuckKit
@testable import StudioKit

/// The app timing its own forward pass. What these assert is the contract —
/// percentiles in order, a result that names its network and its device, and
/// comparisons only within one device — plus one physical claim with a wide
/// margin: a network with 7.5× fewer multiply-adds is faster on the same core.
final class PolicyTimingTests: XCTestCase {

    private func alpha() throws -> DuckPolicy {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "alpha_walking", withExtension: "onnx", subdirectory: "Fixtures/policies"))
        return try DuckPolicy.load(contentsOf: url)
    }

    /// A 61-128-128-14 network with small deterministic weights: the shape of
    /// craigm26/duckbatch's 26,254-parameter student. Timing depends on the
    /// shape, not on what the weights learned.
    private func student() throws -> DuckPolicy {
        var seed: UInt32 = 1
        func next() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed >> 8) % 1000) / 10_000
        }
        let layers = [(61, 128), (128, 128), (128, 14)].map { w in
            DuckPolicyWriter.Layer(weights: (0..<(w.0 * w.1)).map { _ in next() },
                                   biases: (0..<w.1).map { _ in next() }, inputs: w.0, outputs: w.1)
        }
        let data = try DuckPolicyWriter.encoded(
            mean: [Float](repeating: 0, count: DuckObservation.length),
            std: [Float](repeating: 1, count: DuckObservation.length), layers: layers)
        return try DuckPolicy.load(from: data)
    }

    private let observations: [DuckObservation] = [
        DuckObservation.zeroed,
        DuckObservation.build(gyro: [0.1, -0.2, 0.05], gravity: [0, 0, -1],
                              jointPositions: DuckModel.homePose,
                              jointVelocities: [Double](repeating: 0.3, count: DuckModel.jointCount),
                              lastAction: [Float](repeating: 0.05, count: DuckModel.policyJointCount),
                              command: DuckCommand(twist: (0.2, 0, 0.3))),
    ]

    func testATimingNamesItsNetworkAndItsDevice() throws {
        let t = PolicyTiming.measure(try student(), observations: observations, runs: 300, warmup: 30)
        XCTAssertEqual(t.runs, 300)
        XCTAssertEqual(t.widths, [61, 128, 128, 14])
        XCTAssertEqual(t.parameterCount, 26_254)
        XCTAssertFalse(t.device.isEmpty)
        XCTAssertLessThanOrEqual(t.p50Micros, t.p95Micros)
        XCTAssertLessThanOrEqual(t.p95Micros, t.p99Micros)
        XCTAssertGreaterThan(t.p50Micros, 0)
        XCTAssertTrue(t.sentence.hasSuffix("of the 20 ms tick."), t.sentence)
    }

    /// 197,774 against 26,254 learned parameters on the same core: if the
    /// student is not faster, the loop is not running the network it says.
    func testTheStudentIsFasterThanTheAlphaShapeOnTheSameCore() throws {
        let big = PolicyTiming.measure(try alpha(), observations: observations, runs: 400)
        let small = PolicyTiming.measure(try student(), observations: observations, runs: 400)
        XCTAssertLessThan(small.p50Micros, big.p50Micros,
                          "student \(small.p50Micros) µs vs alpha \(big.p50Micros) µs")
        let line = try XCTUnwrap(small.comparedWith(big))
        XCTAssertTrue(line.hasPrefix("7.5× fewer parameters"), line)
        XCTAssertTrue(line.hasSuffix("than 61-512-256-128-14"), line)
    }

    /// Two devices are never one comparison.
    func testTimingsFromTwoDevicesAreNotCompared() throws {
        let here = PolicyTiming.measure(try student(), observations: observations, runs: 50, warmup: 5)
        let elsewhere = PolicyTiming(runs: 50, p50Micros: 40, p95Micros: 50, p99Micros: 60,
                                     parameterCount: 197_774, widths: [61, 512, 256, 128, 14],
                                     device: "some other phone")
        XCTAssertNil(here.comparedWith(elsewhere))
    }
}
