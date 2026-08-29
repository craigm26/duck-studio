import Foundation

/// Where a policy can be fetched from, and what this app will refuse to do.
///
/// THERE IS NO TOKEN FIELD, AND THAT IS THE DESIGN. A box that accepts a
/// Hugging Face access token would make private repositories work and would
/// also make this app a place people paste credentials. An inspector has no
/// business holding one: it reads networks, it has no account, it stores
/// nothing that needs authorising. So only public files can be fetched, private
/// repositories fail with a plain 401, and the remedy is to download the file
/// in a browser and open it — which keeps the credential in the browser, where
/// it already lives.
///
/// THE FULL URL IS SHOWN BEFORE ANYTHING IS FETCHED. Typing `owner/repo` and
/// having a request leave the device is the shape of an accident. `Request`
/// carries `displayURL` precisely so a screen can print the exact address and
/// wait — a person who mistypes a repository name should find out by reading,
/// not by watching a download fail.
///
/// The construction is pure, so every rule below is asserted on Linux rather
/// than by pointing a phone at the network.
public enum PolicySource {

    /// A fetch that has been checked but not yet performed.
    public struct Request: Equatable, Sendable {
        public let url: URL
        /// Exactly what the person should read before agreeing. Identical to
        /// `url.absoluteString`; named separately because its job is to be
        /// displayed, and a field with that job should be hard to drop.
        public let displayURL: String
        public let host: String
        /// The filename to store it under.
        public let suggestedName: String
    }

    public enum Refusal: Error, Equatable {
        /// Not `owner/repo`.
        case malformedRepository(String)
        case emptyFilename
        /// Anything but https. A policy fetched over http can be swapped in
        /// flight for one that walks the robot into a wall, and the whole
        /// point of this app is knowing what you are about to run.
        case insecureScheme(String)
        case notAURL(String)
        /// Bigger than `byteCap`.
        case tooLarge(bytes: Int)
        /// Not an .onnx file.
        case notAPolicyFile(String)
    }

    /// Eight megabytes. Every alpha policy is about 793 KB, so this is ten
    /// times the real thing — loose enough that a larger network is not
    /// arbitrarily blocked, tight enough that a mistyped URL pointing at a
    /// dataset does not spend somebody's cellular allowance before failing.
    public static let byteCap = 8 * 1024 * 1024

    /// Build the resolve URL for a public Hugging Face file.
    ///
    /// `resolve/<revision>/<path>` is the raw-file endpoint; `blob/` is the
    /// HTML page around it, and fetching that returns a web page that fails to
    /// parse as ONNX with a confusing message. Getting this wrong is the single
    /// most likely way a fetch feature misbehaves, so it is spelled out here
    /// once rather than assembled at a call site.
    public static func huggingFace(repository: String, file: String,
                                   revision: String = "main") throws -> Request {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else {
            throw Refusal.malformedRepository(repository)
        }
        let name = file.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Refusal.emptyFilename }
        guard name.lowercased().hasSuffix(".onnx") else { throw Refusal.notAPolicyFile(name) }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(parts[0])/\(parts[1])/resolve/\(revision)/\(name)"
        guard let url = components.url else { throw Refusal.notAURL(repository) }
        return Request(url: url, displayURL: url.absoluteString,
                       host: "huggingface.co", suggestedName: lastComponent(of: name))
    }

    /// The same resolve endpoint, for a repository's `manifest.json`.
    ///
    /// A SEPARATE DOOR ON PURPOSE. `huggingFace(repository:file:)` refuses
    /// anything that is not a `.onnx`, and that guard is worth keeping: it is
    /// what stops a policy fetch quietly downloading a web page. A manifest is
    /// the one other file this app asks for, so it gets its own function
    /// rather than a loosened check.
    public static func huggingFaceManifest(repository: String,
                                           revision: String = "main") throws -> Request {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else {
            throw Refusal.malformedRepository(repository)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(parts[0])/\(parts[1])/resolve/\(revision)/manifest.json"
        guard let url = components.url else { throw Refusal.notAURL(repository) }
        return Request(url: url, displayURL: url.absoluteString,
                       host: "huggingface.co", suggestedName: "manifest.json")
    }

    /// Accept an address someone pasted, after checking it.
    public static func direct(_ text: String) throws -> Request {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            throw Refusal.notAURL(trimmed)
        }
        guard url.scheme?.lowercased() == "https" else {
            throw Refusal.insecureScheme(url.scheme ?? "none")
        }
        guard url.lastPathComponent.lowercased().hasSuffix(".onnx") else {
            throw Refusal.notAPolicyFile(url.lastPathComponent)
        }
        return Request(url: url, displayURL: url.absoluteString,
                       host: host, suggestedName: url.lastPathComponent)
    }

    /// Check a response before it becomes a policy.
    public static func accept(_ data: Data) throws -> Data {
        guard data.count <= byteCap else { throw Refusal.tooLarge(bytes: data.count) }
        return data
    }

    /// The sentence for a refusal. Lives here for the same reason
    /// `PolicyReport`'s do — so a test can read it.
    public static func message(for refusal: Refusal) -> String {
        switch refusal {
        case .malformedRepository(let text):
            return "\"\(text)\" is not a repository. Hugging Face repositories are written owner/name, like pollen-robotics/microduck."
        case .emptyFilename:
            return "Give the name of a file inside the repository."
        case .insecureScheme(let scheme):
            return "\(scheme) is not secure enough to fetch a policy over. A network someone can modify in flight is a network that can hand you a different robot."
        case .notAURL(let text):
            return "\"\(text)\" is not an address this app can fetch."
        case .tooLarge(let bytes):
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "That file is %.1f MB. Policies are under a megabyte, so this is almost certainly not one.", mb)
        case .notAPolicyFile(let name):
            return "\(name) is not an .onnx file."
        }
    }

    private static func lastComponent(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
