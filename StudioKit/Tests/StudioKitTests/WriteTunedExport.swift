import XCTest
import DuckKit
@testable import StudioKit

/// Not a test — a generator, in `PrintFingerprints`' shape and for the same
/// reason.
///
/// WHY A FILE ON DISK IS THE ONLY HONEST CHECK OF THE METADATA WRITER.
/// `DuckTunerTests` round-trips `withMetadata` through `metadata(of:)`, and a
/// writer checked only by its own reader proves that the two agree, not that
/// either is right. The append is hand-written protobuf into a `ModelProto`
/// somebody else's runtime has to open — and the last time this project
/// hand-wrote a ModelProto it produced a file that round-tripped perfectly here
/// and that onnxruntime refused outright for a missing opset, found by
/// uploading one to a real bench.
///
/// So this writes the artefact out where a DIFFERENT parser, in a different
/// language, in another repository, can be pointed at it:
///
///     swift test --filter WriteTunedExport
///     node duck-sounds/sim/onnx_meta.mjs <the path it prints>
///
/// It writes to a directory named by `TUNED_EXPORT_DIR` and does nothing at all
/// when that is unset, so a normal `swift test` run neither writes files nor
/// fails for want of somewhere to write them.
final class WriteTunedExport: XCTestCase {

    func testWriteATunedPolicyForAnOutsideReader() throws {
        guard let directory = ProcessInfo.processInfo.environment["TUNED_EXPORT_DIR"] else {
            print("WriteTunedExport: TUNED_EXPORT_DIR unset — nothing written.")
            return
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "alpha_walking",
                                                  withExtension: "onnx",
                                                  subdirectory: "Fixtures/policies"))
        let baseBytes = try Data(contentsOf: url)

        var gain = DuckTuner.TuningVector.identity.gain
        var trim = DuckTuner.TuningVector.identity.offset
        for slot in DuckTuner.Schedule.legSlots { gain[slot] = 1.08; trim[slot] = 0.01 }
        let vector = try DuckTuner.TuningVector.checked(gain: gain, offset: trim)

        let export = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: 1.0,
            vector: vector, schedule: .onAPhone, seed: 7, bench: "This iPhone",
            measuredTerms: Dictionary(uniqueKeysWithValues:
                DuckTuner.terms.map { ($0.key, 0.5) }),
            travelled: 1.207, elapsed: 900)

        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let onnx = folder.appendingPathComponent(export.filename)
        try export.onnx.write(to: onnx)
        try export.manifest.write(to: folder.appendingPathComponent("manifest.json"))
        try Data(export.robotdExcerpt.utf8)
            .write(to: folder.appendingPathComponent("robotd.toml"))
        print("TUNED ONNX \(onnx.path) \(export.onnx.count) bytes")
        print("TUNED FINGERPRINT \(export.fingerprint)")
        print("BASE FINGERPRINT \(export.baseFingerprint)")
    }
}
