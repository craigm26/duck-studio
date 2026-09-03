import Foundation

/// What a policy is CALLED, as opposed to what it is.
///
/// THE WEIGHTS ARE THE IDENTITY AND A NAME IS A LABEL. `PolicyLibrary` stores a
/// policy under the digest of its parameters, which is right — and it meant the
/// name a file arrived under was never written down anywhere, so the next launch
/// renamed every imported policy to its own hash. Nothing here is ever a key:
/// the nameplate is looked up BY identity and never looked up by.
///
/// ON DISK IT IS `<identity>.nameplate.json`, beside `<identity>.manifest.json`
/// and `<identity>.onnx` — written, read and deleted with the weights, and
/// invisible to `PolicyLibrary.read(directory:)` because that filters on
/// `pathExtension == "onnx"`.
///
/// NOT THE EXISTING MANIFEST SIDECAR: that is Pollen's schema, and writing our
/// own key into it is a claim about their format. NOT ONE SHARED `names.json`
/// either: a single mutable file loses every name to one bad write and makes
/// `remove` a read-modify-write.
public struct PolicyNameplate: Equatable, Sendable {

    /// Bumped when a key changes meaning. A plate from the future is REFUSED
    /// rather than guessed at — see `ReadError.unsupportedSchema`.
    public static let schemaVersion = 1

    /// The name the bytes arrived under. The one field that is never optional:
    /// a plate that cannot say what the file was called is a plate with nothing
    /// to say.
    public let fileName: String

    /// What a person typed. `nil` means nobody has, and the title is then
    /// recomputed from the ladder every time.
    public let title: String?

    /// The host the file was fetched from, when it was fetched. `nil` means it
    /// arrived as a file, which is a different fact from "we do not know".
    public let originHost: String?

    /// Whether the plate was written BY AN ARRIVAL — an import that observed
    /// where the bytes came from. A plate a rename creates for a legacy entry
    /// observed nothing, and says so; absent in the file means false, which
    /// is every build-46 container.
    public let arrivalRecorded: Bool

    public init(fileName: String, title: String? = nil, originHost: String? = nil,
                arrivalRecorded: Bool = false) {
        self.fileName = fileName
        self.title = title
        self.originHost = originHost
        self.arrivalRecorded = arrivalRecorded
    }

    public enum ReadError: Error, Equatable {
        case notJSON
        case missing(String)
        case unsupportedSchema(Int)

        public var message: String {
            switch self {
            case .notJSON:
                return "That name file is not readable JSON, so the name it held is gone. The "
                     + "policy itself is untouched."
            case .missing(let key):
                return "That name file has no \(key), so there is nothing in it to read back."
            case .unsupportedSchema(let version):
                return "That name file is written in format \(version), which this version of "
                     + "the app has not been taught to read."
            }
        }
    }

    public static func decode(_ data: Data) throws -> PolicyNameplate {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else { throw ReadError.notJSON }
        guard let version = json["schema_version"] as? Int else {
            throw ReadError.missing("schema_version")
        }
        guard version <= schemaVersion else { throw ReadError.unsupportedSchema(version) }
        guard let fileName = json["file_name"] as? String, !fileName.isEmpty else {
            throw ReadError.missing("file_name")
        }
        return PolicyNameplate(fileName: fileName,
                               title: json["title"] as? String,
                               originHost: json["origin_host"] as? String,
                               arrivalRecorded: json["arrival_recorded"] as? Bool ?? false)
    }

    public func encoded() -> Data {
        var json: [String: Any] = [
            "schema_version": Self.schemaVersion,
            "file_name": fileName,
        ]
        // ABSENT RATHER THAN NULL. `nil` here means "nobody typed one", and a
        // key whose value is null is a key a future reader has to decide about.
        if let title { json["title"] = title }
        if let originHost { json["origin_host"] = originHost }
        if arrivalRecorded { json["arrival_recorded"] = true }
        return (try? JSONSerialization.data(withJSONObject: json,
                                            options: [.sortedKeys, .prettyPrinted]))
            ?? Data()
    }
}
