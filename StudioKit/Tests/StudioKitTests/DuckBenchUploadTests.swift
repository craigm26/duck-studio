import XCTest
@testable import StudioKit

/// The two calls that let a policy made on this phone be run by something with
/// physics, and the reader that stops a success rate flattering a collapse.
final class DuckBenchUploadTests: XCTestCase {

    private func address() throws -> DuckBench.Address {
        try DuckBench.address("192.168.1.50:8770")
    }

    // MARK: - putting a policy on the bench

    func testAnUploadCarriesTheFileAsBase64() throws {
        let onnx = Data([0x08, 0x08, 0x3A, 0x00, 0xFF, 0x00])
        let call = try DuckBench.upload(address(), onnx: onnx)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.absoluteString, "http://192.168.1.50:8770/upload")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(call.body))
                                    as? [String: Any])
        let text = try XCTUnwrap(body["onnx"] as? String)
        XCTAssertEqual(Data(base64Encoded: text), onnx, "the bytes must survive the trip")
    }

    func testTheNameTheBenchGaveItComesBack() throws {
        let answer = #"{"policy":"uploaded-16b2bc2380f1","bytes":792076}"#.data(using: .utf8)!
        XCTAssertEqual(try DuckBench.readUploaded(answer), "uploaded-16b2bc2380f1")
    }

    /// A REFUSAL IS NOT A NAME. The bench answers 200 with an `error` key when
    /// a file will not load as a policy, and reading past that would name a
    /// policy that does not exist there.
    func testARefusedUploadIsAnErrorAndNotAName() throws {
        let answer = #"{"error":"that file did not load as a policy: Missing opset"}"#
            .data(using: .utf8)!
        XCTAssertThrowsError(try DuckBench.readUploaded(answer)) { error in
            XCTAssertEqual(error as? DuckBench.ReadError,
                           .bench("that file did not load as a policy: Missing opset"))
        }
    }

    // MARK: - how far it actually got

    /// Straight forward: travel and path agree.
    func testAStraightWalkTravelsAsFarAsItStepped() throws {
        let roots = (0...10).map { "[\(Double($0) * 0.1),0,0.115,1,0,0,0]" }.joined(separator: ",")
        let answer = "{\"roots\":[\(roots)],\"endsUpright\":true,\"plantName\":\"scene.mjb\"}"
            .data(using: .utf8)!
        let t = try DuckBench.readTravel(answer)
        XCTAssertEqual(t.travelled, 1.0, accuracy: 1e-9)
        XCTAssertEqual(t.path, 1.0, accuracy: 1e-9)
        XCTAssertEqual(t.endHeight, 0.115, accuracy: 1e-9)
        XCTAssertTrue(t.endsUpright)
        XCTAssertEqual(t.plantName, "scene.mjb")
    }

    /// THE PAIR IS WHAT TELLS THEM APART. A duck marching on the spot covers
    /// ground every step and arrives where it started; travel alone would call
    /// that identical to a duck that never moved, and path alone would call it
    /// a walk.
    func testThrashingInPlaceHasAPathAndNoTravel() throws {
        var xs: [Double] = []
        for i in 0..<20 { xs.append(i % 2 == 0 ? 0 : 0.05) }
        let roots = xs.map { "[\($0),0,0.115,1,0,0,0]" }.joined(separator: ",")
        let t = try DuckBench.readTravel("{\"roots\":[\(roots)]}".data(using: .utf8)!)
        XCTAssertEqual(t.travelled, 0.05, accuracy: 1e-9)
        XCTAssertGreaterThan(t.path, 0.9, "every step counted")
    }

    func testARecordingWithNoRootsIsEmptyRatherThanZero() {
        XCTAssertThrowsError(try DuckBench.readTravel(#"{"roots":[]}"#.data(using: .utf8)!)) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .empty)
        }
    }

    func testABenchRefusalIsNotReadAsADistance() {
        XCTAssertThrowsError(try DuckBench.readTravel(
            #"{"error":"no such policy"}"#.data(using: .utf8)!)) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("no such policy"))
        }
    }

    // MARK: - the command

    /// A COMPARISON BY DISTANCE NEEDS A COMMAND PAST THE GAIT THRESHOLD.
    /// `alpha_walking` travels 7 mm in six seconds at vx = 0.15 on this bench
    /// and 1.207 m at vx = 0.5. A schedule that never commands a walk compares
    /// two ducks standing still and finds them alike.
    func testTheWalkingCommandActuallyCommandsAWalk() throws {
        let steps = DuckBench.walkingCommand
        XCTAssertEqual(steps.first?.vx, 0, "the settle is commanded neutral")
        let top = try XCTUnwrap(steps.last)
        XCTAssertGreaterThanOrEqual(top.vx, 0.3,
            "below about 0.3 the walking policy stands, which looks like a broken policy")
        XCTAssertGreaterThan(top.at, 0, "the drop bounce has to die before a command means anything")
    }

    // MARK: - against what the bench actually said

    private func benchFixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/bench/\(name)",
                                                  withExtension: "json"),
                                "fixture \(name).json is missing")
        return try Data(contentsOf: url)
    }

    /// THE FIXTURES ABOVE ARE ONES I WROTE, WHICH PROVES ONLY SELF-CONSISTENCY.
    /// These two are the duckbench's own answers, saved byte for byte: six
    /// seconds of `alpha_walking` commanded forward at vx = 0.5 on plant
    /// `scene.mjb`, and the same command given to `alpha_walking` averaged
    /// 75/25 with `alpha_stand`.
    ///
    /// This is the pair that made the case for `readTravel` existing. Both end
    /// upright — both score perfectly against the bench's own criterion — and
    /// one of them travels a millimetre and a half.
    func testTheRealRecordingsSeparateAWalkFromADuckStandingStill() throws {
        let walking = try DuckBench.readTravel(benchFixture("record-walking-vx05"))
        XCTAssertEqual(walking.travelled, 1.207, accuracy: 0.002)
        XCTAssertTrue(walking.endsUpright)
        XCTAssertEqual(walking.plantName, "scene.mjb")
        XCTAssertNotNil(walking.plantDigest, "a distance without its world is not a fact")

        let blend = try DuckBench.readTravel(benchFixture("record-blend75-vx05"))
        XCTAssertLessThan(blend.travelled, 0.01, "the blend lost the walk")
        XCTAssertTrue(blend.endsUpright, "and still passes an uprightness criterion perfectly")

        // Which is the whole point: identical on the criterion, three orders of
        // magnitude apart on the thing anybody cares about.
        XCTAssertEqual(walking.endsUpright, blend.endsUpright)
        XCTAssertGreaterThan(walking.travelled / max(blend.travelled, 1e-6), 100)
    }

    /// And the sentence built from those two recordings refuses to call the
    /// blend a success — the end of the chain, on real numbers.
    func testTheRealBlendIsReportedAsHavingStoppedRatherThanWorking() throws {
        let walking = try DuckBench.readTravel(benchFixture("record-walking-vx05"))
        let blend = try DuckBench.readTravel(benchFixture("record-blend75-vx05"))
        let said = PolicyBlend.measured(.init(
            achieves: 16, rollouts: 16, criterion: "ends standing, trunk at least 100 mm up",
            travelled: blend.travelled, liveliestIngredientTravelled: walking.travelled,
            plant: "On \(blend.plantName ?? "?")."))
        XCTAssertTrue(said.contains("stopped doing the thing"), said)
        XCTAssertFalse(said.contains("genuinely surprising"), said)
    }
}
