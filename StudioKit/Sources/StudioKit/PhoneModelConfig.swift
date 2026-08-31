import Foundation

/// A `config.json` whose settings live one level down.
///
/// THE REPOSITORY THIS EXISTS FOR IS THE ODD ONE OUT, AND THE FAILURE IS
/// SILENT. `mlx-community/Gemma4-E2B-IT-Text-int4` declares a top-level
/// `"model_type": "gemma4_text"` and keeps every architecture parameter under
/// `"text_config"`. mlx-swift-lm 3.31.4 registers `gemma4_text` against a
/// configuration that decodes from the TOP LEVEL, and every one of its fields
/// is decode-if-present with a default — so nothing throws, the weight shapes
/// verify, and generation runs.
///
/// The defaults happen to equal E2B's real values for every field but one:
/// `rope_parameters` is absent at the top level, so full-attention layers take
/// `partial_rotary_factor` 1.0 instead of the 0.25 the repository specifies,
/// and one layer in five rotates 512 dimensions instead of 128. That reads as
/// "small model, mediocre quality" rather than as "we loaded it wrong", which
/// is exactly why it has to be corrected rather than warned about.
///
/// IT IS PURE JSON, SO IT LIVES HERE. The app hands the result to MLX; a test
/// on a Raspberry Pi holds the reshaping.
public enum PhoneModelConfig {

    /// The nested text configuration, lifted to the top level, when the config
    /// is one of these. Nil when the config is already flat — in which case the
    /// caller must decode the original bytes unchanged rather than a rebuilt
    /// copy, because a rebuild is a chance to lose a field.
    ///
    /// ONLY WHEN BOTH ARE TRUE: the top-level `model_type` ends in `_text`, and
    /// a `text_config` object is present. None of the five catalogue models has
    /// a `text_config` — checked against all five live — so this touches
    /// nothing already shipping.
    public static func textConfigFlattened(_ configJSON: Data) -> Data? {
        guard let top = try? JSONSerialization.jsonObject(with: configJSON) as? [String: Any],
              let modelType = top["model_type"] as? String, modelType.hasSuffix("_text"),
              var nested = top["text_config"] as? [String: Any] else { return nil }

        // The nested block is self-contained apart from the type itself, which
        // names the model and must survive to the registry lookup.
        nested["model_type"] = nested["model_type"] as? String ?? modelType
        // Quantisation is read from the top level and belongs to the file, not
        // to the text tower; losing it means the weights load unquantised and
        // fail verification.
        if nested["quantization"] == nil, let quant = top["quantization"] {
            nested["quantization"] = quant
        }
        return try? JSONSerialization.data(withJSONObject: nested)
    }

    /// Whether a config needs the correction, for a screen that wants to say so.
    public static func needsFlattening(_ configJSON: Data) -> Bool {
        textConfigFlattened(configJSON) != nil
    }
}
