import Foundation

/// A bench, saved and named, so there can be more than one of them.
///
/// WHY THIS EXISTS. Everything that talks to a bench read one
/// `@AppStorage("duckbench.address")` string, so the app could hold exactly one
/// bench and could not tell you which. That is wrong for the way these are
/// actually used: there is a Pi that is always on and slow, a desktop that is
/// fast and sometimes off, and a machine at somebody else's house — and moving
/// between them meant retyping an address and losing the last one. The Models
/// tab solved this shape a while ago with `ModelEndpoint`, so this is
/// deliberately the same shape rather than a second design: a named list, one
/// selected, each entry checkable on its own.
///
/// THE TOKEN IS NOT IN HERE WHEN IT IS STORED. `Codable` carries `hasToken` and
/// not the token itself, exactly as `ModelEndpoint` keeps API keys out of the
/// plist that device backups copy. `BenchStore` puts it in the Keychain against
/// this id and hands back an armed copy at the moment of use.
///
/// AN ADDRESS IS VALIDATED BY `DuckBench.address` AND NOWHERE ELSE. Two parsers
/// for one address is how a screen accepts something the client then refuses,
/// and the refusals it throws already say what is wrong in a sentence.
public struct BenchEndpoint: Equatable, Sendable, Codable, Identifiable {

    public var id: UUID
    public var name: String
    /// Host and port, as the start script prints it — `100.122.199.6:8770`.
    public var address: String
    /// Set when a token lives in the Keychain for this id. The token itself is
    /// never encoded.
    public var hasToken: Bool

    /// Present only on an ARMED copy, on its way to a request. Never encoded.
    public var token: String?

    public init(id: UUID = UUID(), name: String, address: String,
                hasToken: Bool = false, token: String? = nil) {
        self.id = id; self.name = name; self.address = address
        self.hasToken = hasToken; self.token = token
    }

    private enum CodingKeys: String, CodingKey { case id, name, address, hasToken }

    // MARK: - refusing a bad one

    public enum Refusal: Error, Equatable, Sendable {
        case emptyName
        case address(DuckBench.Refusal)

        public var message: String {
            switch self {
            case .emptyName:
                return "Give this bench a name. With more than one saved, \"the bench\" stops "
                     + "being enough to tell them apart."
            case .address(let refusal):
                return refusal.message
            }
        }
    }

    /// THE NAME IS CHECKED FIRST, and that order is pinned by test. A new entry
    /// has neither, and being told to name it is the step somebody can act on
    /// without knowing anything about addresses.
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Refusal.emptyName }
        try validateAddress()
    }

    /// Everything the ADDRESS has to satisfy, with nothing in it about the name.
    ///
    /// SPLIT OUT FOR THE SAME REASON `ModelEndpoint` SPLITS ITS OWN: "Check this
    /// address" has to work on an entry that is not finished yet, which is the
    /// only moment anybody wants it. A check that first demanded a name would
    /// refuse the exact case it exists for.
    public func validateAddress() throws {
        do {
            _ = try DuckBench.address(address)
        } catch let refusal as DuckBench.Refusal {
            throw Refusal.address(refusal)
        }
    }

    /// The parsed address, for a caller that is about to build a request.
    public func resolved() throws -> DuckBench.Address {
        do {
            return try DuckBench.address(address)
        } catch let refusal as DuckBench.Refusal {
            throw Refusal.address(refusal)
        }
    }

    /// Whether this one keeps working when the phone leaves the house.
    public var isTailnet: Bool { BenchSetup.isTailnet(address) }

    // MARK: - reading the saved list back

    /// What came back out of storage: the benches that could be read, and how
    /// many could not.
    ///
    /// ONE UNREADABLE ENTRY MUST NOT COST THE OTHERS. Decoding the array whole
    /// throws on the first bad element and takes every good one with it, which
    /// turns a single corrupt record into "all your benches are gone".
    public struct Salvage: Equatable, Sendable {
        public var benches: [BenchEndpoint]
        /// How many were unreadable, or nil if the whole blob was.
        public var unreadable: Int?

        public init(benches: [BenchEndpoint], unreadable: Int?) {
            self.benches = benches; self.unreadable = unreadable
        }
    }

    /// THE SAME READER `ModelEndpoint.decodeList` USES, not a second design.
    ///
    /// My first attempt re-encoded each element through a `[String: String?]`
    /// box and retried it — which silently dropped `hasToken`, because it is a
    /// Bool and decoding it as a String gives nil. A salvage that loses a field
    /// while claiming to have recovered the record is worse than one that
    /// admits the record is gone. Stepping an unkeyed container touches nothing
    /// it keeps.
    public static func decodeList(from data: Data) -> Salvage {
        struct Reader: Decodable {
            var salvage: Salvage

            /// Decodes from anything at all, so the cursor can be stepped over
            /// an element `BenchEndpoint` refused.
            struct Skipped: Decodable {
                init(from decoder: Decoder) throws {}
            }

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                var kept: [BenchEndpoint] = []
                var lost = 0
                while !container.isAtEnd {
                    if let one = try? container.decode(BenchEndpoint.self) {
                        kept.append(one)
                        continue
                    }
                    lost += 1
                    // A null steps the cursor only through decodeNil, which
                    // returns false without moving for anything that is not one.
                    if (try? container.decodeNil()) == true { continue }
                    if (try? container.decode(Skipped.self)) != nil { continue }
                    break
                }
                salvage = Salvage(benches: kept, unreadable: lost)
            }
        }
        guard let reader = try? JSONDecoder().decode(Reader.self, from: data) else {
            return Salvage(benches: [], unreadable: nil)
        }
        return reader.salvage
    }
}
