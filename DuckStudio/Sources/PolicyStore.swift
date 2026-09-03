import Foundation
import StudioKit

/// Where a policy's bytes are, when a view needs them again.
///
/// `PolicyLibrary.Entry` deliberately carries the REPORT and not the file: a
/// library of a dozen policies would otherwise hold ten megabytes of weights in
/// memory for a list that only draws names. So a screen that actually needs to
/// run one comes back here for the bytes.
enum PolicyStore {

    static func data(for entry: PolicyLibrary.Entry) -> Data? {
        // Imported files are stored under their identity, so that is the first
        // place to look and the only one that cannot collide.
        let container = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Policies", isDirectory: true)
            .appendingPathComponent("\(entry.identity.value).onnx")
        if let data = try? Data(contentsOf: container) { return data }

        // Otherwise it is one of the bundled seeds, which keep their own names.
        //
        // THE FILE NAME, NEVER THE TITLE. A bundled policy is renamable — the
        // nameplate is keyed by identity and lives in the container — so the
        // string a person reads on the row is not the string this lookup needs.
        // Handing `Bundle.main` a nickname finds nothing, and finding nothing
        // here is a Probe button that does not work.
        if let url = Bundle.main.url(forResource: entry.fileName
                                        .replacingOccurrences(of: ".onnx", with: ""),
                                     withExtension: "onnx") {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}
