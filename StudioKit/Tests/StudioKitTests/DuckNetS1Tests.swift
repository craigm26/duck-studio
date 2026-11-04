import XCTest
@testable import StudioKit

/// Duck Driver S1 in Swift, held to the numbers PyTorch computed for the same weights
/// (Fixtures/ducknet-s1, written by duckbatch's bc_ducknet.py --golden-only on the Mac).
final class DuckNetS1Tests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/ducknet-s1/\(name)", withExtension: nil))
        return try Data(contentsOf: url)
    }

    func testTheGoldenInputsAreTheTrainingScriptsOwn() {
        // From bc_ducknet.py's splitmix_inputs(1, 3), run in Python.
        XCTAssertEqual(Array(DriverGolden.input(seed: 1).values.prefix(3)),
                       [0.13312314450740814, 0.4915635287761688, 0.9420055150985718])
    }

    func testTheFixtureIsWhatItsManifestSays() throws {
        let manifest = try DriverManifest.read(try fixture("policy.json"))
        XCTAssertTrue(manifest.matches(try fixture("model.safetensors"), path: "model.safetensors"))
        XCTAssertTrue(manifest.matches(try fixture("golden.json"), path: "golden.json"))
    }

    func testSwiftMatchesPyTorchOnTheGoldenInputs() throws {
        let net = try DuckNetS1(SafeTensors(try fixture("model.safetensors")))
        let golden = try DriverGolden.read(try fixture("golden.json"))
        XCTAssertNil(try DriverGolden.check(net: net, golden: golden, tolerance: 1e-4))
    }

    func testAPerturbedAnswerIsRefusedAndNamed() throws {
        let net = try DuckNetS1(SafeTensors(try fixture("model.safetensors")))
        let golden = try DriverGolden.read(try fixture("golden.json"))
        var outputs = golden.outputs
        outputs[1][7] += 0.01
        let bent = try JSONDecoder().decode(DriverGolden.File.self,
            from: JSONSerialization.data(withJSONObject: ["seeds": golden.seeds, "outputs": outputs]))
        let problem = try XCTUnwrap(try DriverGolden.check(net: net, golden: bent))
        XCTAssertEqual(problem.seed, golden.seeds[1])
        XCTAssertEqual(problem.row, 2)
        XCTAssertEqual(problem.column, 1)
        XCTAssertTrue(problem.message.contains("sideways"))
    }

    func testWrongWeightsAreRefusedByName() throws {
        let file = try SafeTensors(try fixture("model.safetensors"))
        var tensors = file.tensors
        tensors["fc2.bias"] = nil
        XCTAssertThrowsError(try DuckNetS1(SafeTensors(SafeTensors.encode(tensors)))) {
            XCTAssertEqual($0 as? DuckNetS1.Problem, .missing("fc2.bias"))
        }
        tensors = file.tensors
        tensors["conv1.weight"] = SafeTensors.Tensor(shape: [16, 3, 5, 5], values: Array(repeating: 0, count: 1200))
        XCTAssertThrowsError(try DuckNetS1(SafeTensors(SafeTensors.encode(tensors)))) {
            XCTAssertEqual($0 as? DuckNetS1.Problem, .shape("conv1.weight", [16, 3, 5, 5]))
        }
        let net = try DuckNetS1(file)
        XCTAssertThrowsError(try net.infer(DriverInput(values: [1, 2, 3]))) {
            XCTAssertEqual($0 as? DuckNetS1.Problem, .input(3))
        }
    }

    #if canImport(Accelerate)
    func testAccelerateAndThePlainLoopAgree() throws {
        var net = try DuckNetS1(SafeTensors(try fixture("model.safetensors")))
        let input = DriverGolden.input(seed: 2)
        let fast = try net.infer(input)
        net.accelerated = false
        let plain = try net.infer(input)
        for (a, b) in zip(fast, plain) { XCTAssertEqual(a, b, accuracy: 1e-5) }
    }
    #endif
}
