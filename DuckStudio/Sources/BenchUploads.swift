import Foundation
import DuckKit
import StudioKit

/// Putting a library network on a bench, by name.
///
/// ONE PLACE, BECAUSE THREE SCREENS HAD WRITTEN IT. The weight search, the
/// tuner and the blend each carried the same branch: a desk bench loads an
/// `.onnx` through onnxruntime and wants the canonical parameter bytes beside
/// it for `/tune`; the phone bench has no ONNX reader and takes ONLY the
/// canonical bytes. `WeightSearchRun.put` documents the finding. This is that
/// branch with a name on it, so the Control tab can put a kept network on
/// whichever bench it is standing on and get back the name the bench will
/// answer to.
///
/// I/O AND NOTHING ELSE. Which bytes a bench takes is a kit fact
/// (`DuckPolicy.canonicalParameterBytes`); which name goes on the wire is a
/// kit fact (`DuckBench.uploadName`); what came back is read by the kit
/// (`DuckBench.readUploaded`). This sequences three calls.
enum BenchUploads {

    /// - Returns: the name the bench gave it, which is the name to steer by.
    static func put(_ entry: PolicyLibrary.Entry, address: DuckBench.Address,
                    token: String?, host: DuckBench.Health.Host?) async throws -> String {
        guard let file = PolicyStore.data(for: entry) else {
            throw DuckBench.ReadError.bench("\(entry.title) is not on this phone any more.")
        }
        // THE TITLE, NOT THE FILE NAME. A kept network's file is a digest-shaped
        // stem; its title is what the person sees on the shelf, and the bench's
        // name is what they see beside the sticks. The bench keeps the last
        // word on whether it is acceptable.
        let name = entry.title
        let bytes = try DuckPolicy.load(from: file).canonicalParameterBytes
        let call: DuckBench.Call
        if host?.kind == .phone {
            call = try DuckBench.uploadParameters(address, canonicalBytes: bytes, name: name)
        } else {
            call = try DuckBench.upload(address, onnx: file, parameters: bytes, name: name)
        }
        let data = try await URLSession.shared.data(
            for: DuckBench.urlRequest(for: call, token: token)).0
        return try DuckBench.readUploaded(data)
    }
}
