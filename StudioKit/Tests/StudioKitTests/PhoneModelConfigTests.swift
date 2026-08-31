import XCTest
@testable import StudioKit

/// The Gemma 4 text repository hides its architecture one level down, and the
/// loader that reads it decodes from the top with defaults for everything — so
/// it loads, runs, and is wrong.
final class PhoneModelConfigTests: XCTestCase {

    /// The shape of the real repository, reduced to the fields that matter.
    private let gemma4 = """
    {"model_type":"gemma4_text","quantization":{"group_size":64,"bits":4},
     "text_config":{"num_hidden_layers":35,"hidden_size":1536,"vocab_size":262144,
       "tie_word_embeddings":true,"layer_types":["sliding","full"],
       "rope_parameters":{"full_attention":{"partial_rotary_factor":0.25}}}}
    """.data(using: .utf8)!

    /// THE FIELD THE WHOLE THING EXISTS FOR. Absent at the top level, the
    /// loader defaults partial_rotary_factor to 1.0 and one layer in five
    /// rotates 512 dimensions instead of 128.
    func testTheNestedRopeParametersReachTheTopLevel() throws {
        let flattened = try XCTUnwrap(PhoneModelConfig.textConfigFlattened(gemma4))
        let out = try XCTUnwrap(
            JSONSerialization.jsonObject(with: flattened) as? [String: Any])
        let rope = try XCTUnwrap(out["rope_parameters"] as? [String: Any])
        let full = try XCTUnwrap(rope["full_attention"] as? [String: Any])
        XCTAssertEqual(full["partial_rotary_factor"] as? Double, 0.25)
    }

    /// The type has to survive, or the registry cannot find the model at all.
    func testTheModelTypeSurvives() throws {
        let flattened = try XCTUnwrap(PhoneModelConfig.textConfigFlattened(gemma4))
        let out = try XCTUnwrap(
            JSONSerialization.jsonObject(with: flattened) as? [String: Any])
        XCTAssertEqual(out["model_type"] as? String, "gemma4_text")
        XCTAssertEqual(out["num_hidden_layers"] as? Int, 35)
        XCTAssertEqual(out["tie_word_embeddings"] as? Bool, true)
    }

    /// QUANTISATION IS READ FROM THE TOP LEVEL and belongs to the file rather
    /// than the text tower. Dropping it means the weights load unquantised and
    /// fail verification — a much louder failure, but still one this would have
    /// caused.
    func testQuantisationIsCarriedDownWithIt() throws {
        let flattened = try XCTUnwrap(PhoneModelConfig.textConfigFlattened(gemma4))
        let out = try XCTUnwrap(
            JSONSerialization.jsonObject(with: flattened) as? [String: Any])
        let quant = try XCTUnwrap(out["quantization"] as? [String: Any])
        XCTAssertEqual(quant["bits"] as? Int, 4)
    }

    /// A FLAT CONFIG MUST COME BACK NIL, so its original bytes are decoded
    /// unchanged. Every catalogue model is flat; rebuilding one is a chance to
    /// lose a field for no gain.
    func testAFlatConfigIsLeftAlone() {
        let qwen = """
        {"model_type":"qwen3","num_hidden_layers":28,
         "quantization":{"group_size":64,"bits":4}}
        """.data(using: .utf8)!
        XCTAssertNil(PhoneModelConfig.textConfigFlattened(qwen))
        XCTAssertFalse(PhoneModelConfig.needsFlattening(qwen))
        XCTAssertTrue(PhoneModelConfig.needsFlattening(gemma4))
    }

    /// A `_text` type with no nested block is flat too, whatever it is called.
    func testATextTypeWithoutANestedBlockIsFlat() {
        let gemma3 = """
        {"model_type":"gemma3_text","num_hidden_layers":26}
        """.data(using: .utf8)!
        XCTAssertNil(PhoneModelConfig.textConfigFlattened(gemma3))
    }

    func testNonsenseIsNotFlattened() {
        XCTAssertNil(PhoneModelConfig.textConfigFlattened(Data("{".utf8)))
        XCTAssertNil(PhoneModelConfig.textConfigFlattened(Data()))
    }
}
