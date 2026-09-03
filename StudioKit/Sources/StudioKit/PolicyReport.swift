import Foundation
import DuckKit

/// What Microduck Studio says about a file somebody handed it.
///
/// THIS TYPE IS THE APP'S VALUE PROPOSITION, WRITTEN DOWN. Someone exports a
/// policy from their own PPO run, it does not load, and the useful product is
/// not "invalid file" — it is *your exporter emitted Relu where the training
/// used Elu*. That sentence is the whole reason to open this app rather than
/// Netron, so it lives in a package where `swift test` can assert it letter by
/// letter, instead of in a SwiftUI view where the only way to check it is to
/// look at a phone.
///
/// A REFUSAL AND A DESCRIPTION ARE ONE ANSWER, NOT TWO. `DuckPolicy` is built
/// as describe-then-validate over a single walk of the bytes, so a report can
/// always show what was in the file beside the reason it was rejected — and the
/// two can never tell different stories. A refusal screen that cannot show the
/// op sequence it objected to is asking to be believed on faith.
///
/// Every string here is final. The app target interpolates nothing.
public struct PolicyReport: Equatable, Sendable {

    /// Whether THIS APP can read the file. **Not a verdict about the robot**,
    /// and it used to be written as one.
    ///
    /// DUCK STUDIO'S READER IS MUCH STRICTER THAN THE ROBOT'S, so the two
    /// answers genuinely differ. `DuckPolicy.load` refuses anything that is not
    /// exactly the one architecture it supports — nine operations in a fixed
    /// order at fixed widths, 61 to 512 to 256 to 128 to 14, ELU throughout —
    /// which is the property the App Review note in `PLAN.md` rests on.
    /// robotd asks for far less: `duck-control/src/policy.rs`'s `check_width`
    /// (read at main on 2026-08-30) asserts only the TRAILING dimension of the
    /// first outlet, saying in its own comment that "the leading dimension is
    /// the batch and is usually dynamic (-1), so only the last one is checked.
    /// That is the one that encodes the contract." Loading then warms up with
    /// one zeroed observation (`open_warm`). Nothing checks a layer type, an
    /// activation, or a hidden width.
    ///
    /// So a network with Relu where this reader wants Elu, or 512-512-128
    /// where it wants 512-256-128, is refused HERE and would very likely load
    /// THERE. Saying "will not drive the robot" about such a file was a claim
    /// this app is in no position to make.
    public enum Outcome: Equatable, Sendable {
        /// It loaded. The policy is attached.
        case runnable
        /// It did not load, for the reason given.
        case refused
        /// The bytes could not even be walked, so there is no structure to
        /// show — the one case where a report has facts about nothing.
        case unreadable
    }

    /// One row of the structure table.
    public struct Fact: Equatable, Sendable {
        public let label: String
        public let value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public let outcome: Outcome
    /// One short line, suitable for a row in a list.
    public let headline: String
    /// What is wrong, specifically. Empty when the policy is runnable.
    public let reason: String
    /// What to do about it. `nil` when there is nothing useful to suggest —
    /// which is honest, and better than inventing advice for a file that is
    /// simply not an ONNX model.
    public let remedy: String?
    /// The structure, for the table under the sentence.
    public let facts: [Fact]

    /// What a refusal here does and does not settle about the robot.
    ///
    /// Shown under a refusal, because the refusal is the moment somebody
    /// concludes their file is broken — and this app only knows that its own
    /// reader would not take it.
    public static let refusalIsAboutThisApp =
        "This is Microduck Studio's answer, not the robot's. This app reads one exact architecture "
      + "— 61 to 512 to 256 to 128 to 14, ELU throughout — so it refuses networks the robot's "
      + "runtime would load: robotd checks the observation is 61 wide, the actions are 14 wide, "
      + "and that one zeroed step runs. It does not look at layers or activations."

    /// The two widths a robot's runtime does check, which this app can check
    /// too — so a file that fails THESE is one both would turn away.
    public static let widthsTheRobotChecks =
        "61 floats in, 14 out. A file that gets those wrong is refused everywhere."

    // MARK: - building one

    /// Read a file and say everything there is to say about it.
    ///
    /// THE SUBJECT OF EVERY SENTENCE IS THE FILE, and when the file's name is a
    /// bare digest there is no file name worth saying. `PolicyLibrary.persist`
    /// stores every imported policy as `<identity>.onnx`, so before nameplates
    /// existed this sentence read "4f2a…3.onnx is a Microduck policy" — a
    /// verdict about a hash. `PolicyNaming.subject` substitutes "This file",
    /// which is what a person reading the row is looking at.
    ///
    /// STILL BUILT FROM THE FILE NAME AND NEVER FROM THE TITLE. A verdict that
    /// took the display title would go stale the moment somebody renamed the
    /// policy, and there is no second headline field anywhere for it to go
    /// stale in.
    public static func of(_ data: Data, name: String) -> PolicyReport {
        let subject = PolicyNaming.subject(for: name)
        // `describe` first: it is the non-judgmental read, and its failure is
        // the only case where nothing can be shown at all.
        let structure: DuckPolicy.Description
        do {
            structure = try DuckPolicy.describe(from: data)
        } catch {
            return PolicyReport(
                outcome: .unreadable,
                headline: "\(subject) is not an ONNX model",
                reason: unreadableReason(error, byteCount: data.count),
                remedy: data.isEmpty
                    ? nil
                    : "Check the export finished. A file that stops mid-field is usually a run that was interrupted or a download that was cut off.",
                facts: [Fact(label: "Size", value: byteCount(data.count))])
        }

        let facts = describeFacts(structure)

        do {
            _ = try DuckPolicy.load(from: data)
            return PolicyReport(
                outcome: .runnable,
                headline: "\(subject) is a Microduck policy",
                reason: "",
                remedy: nil,
                facts: facts)
        } catch let error as DuckPolicy.LoadError {
            let (reason, remedy) = explain(error, structure: structure)
            return PolicyReport(
                outcome: .refused,
                headline: "\(subject) will not load in Microduck Studio",
                reason: reason,
                remedy: remedy,
                facts: facts)
        } catch {
            return PolicyReport(
                outcome: .refused,
                headline: "\(subject) will not load in Microduck Studio",
                reason: "\(error)",
                remedy: nil,
                facts: facts)
        }
    }

    // MARK: - the sentences

    /// Turn a `LoadError` into a sentence about THIS file.
    ///
    /// The error's own payload already carries what was found; the job here is
    /// to put it next to what was expected, because "op sequence [Sub, Div,
    /// Gemm, Relu…]" only means something to a reader who knows what should
    /// have been there.
    static func explain(_ error: DuckPolicy.LoadError,
                        structure: DuckPolicy.Description) -> (String, String?) {
        switch error {
        case .malformed(let detail):
            return ("The file could not be read: \(detail).", nil)

        case .unsupportedArchitecture(let detail):
            if detail.contains("transB") {
                return ("A Gemm in this network multiplies its weight matrix untransposed. Every alpha policy stores weights as [outputs, inputs] and sets transB=1.",
                        "Re-export with the standard torch.onnx path rather than a hand-built graph. A cleared transB usually means the weights were transposed on the way out, which changes what the layer computes.")
            }
            if let found = opSequence(in: detail) {
                if found.contains("Relu") {
                    return ("This network uses Relu where the trained policy uses Elu. Found \(found.joined(separator: ", ")).",
                            "Elu is what PPO trained with, and swapping the activation changes every output. Check the activation in your policy definition rather than the export settings.")
                }
                let extra = found.count - expectedOps.count
                if extra > 0, found.starts(with: expectedOps) {
                    let tail = found.suffix(extra).joined(separator: ", ")
                    return ("This network is the right shape with \(extra) extra operation\(extra == 1 ? "" : "s") on the end: \(tail).",
                            "Something was appended after the final layer — often a squashing or scaling op added at export time. DuckGait applies the action scale and the travel limits itself, so that step has to come out of the graph.")
                }
                return ("This is not the alpha policy architecture. Expected \(expectedOps.joined(separator: ", )")); found \(found.joined(separator: ", ")).",
                        "Every shipped Microduck policy is the same nine-operation graph. A different sequence means a different network, not a different build of the same one.")
            }
            return ("This is not the alpha policy architecture: \(detail).", nil)

        case .shape(let detail):
            if let (observed, expected) = firstLayerWidth(structure), observed != expected {
                return ("The first layer takes \(observed) inputs. The robot's observation is \(expected).",
                        observed == 48
                            ? "48 inputs is the observation without the 13-value command block. This policy was trained on a robot that could not be commanded, and there is nothing to feed the missing slots."
                            : "The observation layout is fixed: 3 angular velocity, 3 projected gravity, 14 joint positions, 14 velocities, 14 last actions, 13 command. A different width means a different observation was assembled during training.")
            }
            if let outputs = lastLayerWidth(structure), outputs != 14 {
                return ("This network produces \(outputs) actions. The robot has 14 actuated joints.",
                        "There is no safe way to spread \(outputs) numbers across 14 joints, so the kit refuses rather than guessing which joint goes unmoved.")
            }
            return ("A layer width disagrees with the robot: \(detail).",
                    "The architecture is fixed at 61 → 512 → 256 → 128 → 14. Every intermediate width is part of the contract, because the weights are read positionally.")
        }
    }

    /// The message for bytes that could not be walked at all.
    static func unreadableReason(_ error: Error, byteCount: Int) -> String {
        guard byteCount > 0 else { return "The file is empty." }
        if case DuckPolicy.LoadError.malformed(let detail) = error {
            if detail.contains("no graph") {
                return "The file is a readable protobuf but carries no graph, so there is no network in it at all."
            }
            return "The bytes are not a walkable ONNX protobuf: \(detail)."
        }
        return "The bytes are not a walkable ONNX protobuf."
    }

    // MARK: - the table

    static func describeFacts(_ s: DuckPolicy.Description) -> [Fact] {
        var facts = [
            Fact(label: "Operations", value: s.ops.isEmpty ? "none" : s.ops.joined(separator: " → ")),
            Fact(label: "Parameters", value: grouped(s.parameterCount)),
            Fact(label: "Inputs", value: s.inputs.isEmpty ? "unnamed" : s.inputs.joined(separator: ", ")),
            Fact(label: "Outputs", value: s.outputs.isEmpty ? "unnamed" : s.outputs.joined(separator: ", ")),
        ]
        // Widths are the fact people actually scan for, so they get their own
        // row rather than being buried in the initializer list.
        let widths = s.initializers.filter { $0.dims.count == 2 }
            .map { "\($0.dims[1])×\($0.dims[0])" }
        if !widths.isEmpty {
            facts.append(Fact(label: "Layers", value: widths.joined(separator: ", ")))
        }
        return facts
    }

    // MARK: - small helpers

    static let expectedOps = ["Sub", "Div", "Gemm", "Elu", "Gemm", "Elu", "Gemm", "Elu", "Gemm"]

    /// Pull the op list back out of the error's payload. The error is built as
    /// `"op sequence [A, B, C]"`, and reparsing it here keeps DuckKit free of
    /// presentation concerns.
    static func opSequence(in detail: String) -> [String]? {
        guard let open = detail.firstIndex(of: "["), let close = detail.lastIndex(of: "]"),
              open < close else { return nil }
        let inside = detail[detail.index(after: open)..<close]
        let parts = inside.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        }
        return parts.isEmpty ? nil : parts
    }

    /// The first Gemm's input width, as stored: dims are [outputs, inputs].
    static func firstLayerWidth(_ s: DuckPolicy.Description) -> (observed: Int, expected: Int)? {
        guard let first = s.initializers.first(where: { $0.dims.count == 2 }) else { return nil }
        return (first.dims[1], 61)
    }

    static func lastLayerWidth(_ s: DuckPolicy.Description) -> Int? {
        s.initializers.last(where: { $0.dims.count == 2 })?.dims.first
    }

    static func grouped(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func byteCount(_ n: Int) -> String {
        n < 1024 ? "\(n) bytes" : String(format: "%.0f KB", Double(n) / 1024)
    }
}
