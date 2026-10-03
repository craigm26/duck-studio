import XCTest
import DuckEvidence
@testable import StudioKit

/// duckkit 1.37.0: velstand leads the walk slot, alpha_walking stays behind it.
final class WalkSlotTests: XCTestCase {

    func testABenchWithVelstandWalksWithIt() {
        XCTAssertEqual(DuckQuickActions.filename(filling: .walk,
                                                 among: ["alpha_walking.onnx", "velstand.onnx"]),
                       "velstand.onnx")
    }

    /// A desk bench that never got velstand keeps walking.
    func testABenchWithOnlyAlphaWalkingStillWalks() {
        XCTAssertEqual(DuckQuickActions.filename(filling: .walk, among: ["alpha_walking.onnx"]),
                       "alpha_walking.onnx")
        XCTAssertEqual(DuckQuickActions.filename(filling: .walk, among: ["alpha_walking"]),
                       "alpha_walking")
    }

    func testNoWalkerIsNoWalker() {
        XCTAssertNil(DuckQuickActions.filename(filling: .walk, among: ["roulade.onnx"]))
    }

    func testVelstandIsAVelocityTask() {
        XCTAssertEqual(RunMetrics.Task.forPolicy("velstand.onnx"), .velocity)
    }
}
