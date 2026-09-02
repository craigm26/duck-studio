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
///
/// AND ONE OF THEM IS NOT ON THE NETWORK AT ALL. `kind` exists because this
/// phone now has a bench of its own — MuJoCo compiled to WebAssembly, running
/// in a WebView the app keeps alive, answering the same endpoints on a loopback
/// port. Everything the saved list does to a network bench is wrong for that
/// one: it has no address to type, no token to hold, nothing to delete, and
/// persisting it would write down a port number that is different on the next
/// launch. So it is a case rather than a flag, the switch is exhaustive, and a
/// third kind is a compile error rather than a row that quietly behaves like a
/// Pi on a desk.
public struct BenchEndpoint: Equatable, Sendable, Codable, Identifiable {

    /// Which machine is running the physics.
    ///
    /// DECODED WITH A DEFAULT OF `.network`, and that default is the whole
    /// reason this is a `String` enum and not a `Bool`. Every bench already
    /// saved on somebody's phone was written before this field existed; a
    /// record without it is a machine on their network, which is what they
    /// typed in, and the alternative — a decode that throws on the missing key
    /// — would empty the whole list through `decodeList`'s salvage and read
    /// from the other side as the app having forgotten their benches.
    public enum Kind: String, Codable, Sendable {
        case network
        case thisPhone
    }

    public var id: UUID
    public var name: String
    /// Host and port, as the start script prints it — `100.122.199.6:8770`.
    public var address: String
    /// Set when a token lives in the Keychain for this id. The token itself is
    /// never encoded.
    public var hasToken: Bool
    public var kind: Kind

    /// Present only on an ARMED copy, on its way to a request. Never encoded.
    public var token: String?

    public init(id: UUID = UUID(), name: String, address: String,
                hasToken: Bool = false, token: String? = nil,
                kind: Kind = .network) {
        self.id = id; self.name = name; self.address = address
        self.hasToken = hasToken; self.token = token; self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case id, name, address, hasToken, kind }

    /// HAND-WRITTEN FOR ONE KEY. The synthesized decoder throws when `kind` is
    /// absent, and absent is what every record written before this field looks
    /// like. `decodeIfPresent` is the difference between "an older bench is a
    /// network bench" and "an older bench is gone".
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        hasToken = try container.decode(Bool.self, forKey: .hasToken)
        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .network
        token = nil
    }

    // MARK: - the bench that is this phone

    /// The one bench that is not somewhere else.
    ///
    /// THE ID IS A CONSTANT AND THAT IS LOAD-BEARING. `BenchStore.selectedID`
    /// is persisted, and every screen that remembers "the bench I was using"
    /// remembers a UUID — so a phone bench built with a fresh `UUID()` on each
    /// launch would be selected once and then be a different bench in the
    /// morning, with the selection pointing at nothing. `DC0C` is `duck` in the
    /// only hexadecimal that spells it.
    ///
    /// THE PORT IS A LIE UNTIL THE APP FILLS IT IN. A loopback listener is
    /// given its port by the kernel at bind time, so `0` here means "not
    /// listening yet" and `servedOn(port:)` is how the app says otherwise.
    /// `resolved()` refuses the zero with its own sentence rather than letting
    /// `127.0.0.1:0` fall through the address parser and come back as
    /// "not on your network", which would be true of nothing and confusing to
    /// everyone.
    public static let thisPhone = BenchEndpoint(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000DC0C")!,
        name: PhoneBenchReport.name,
        address: "127.0.0.1:0",
        hasToken: false,
        kind: .thisPhone)

    /// Whether this is the bench inside the app.
    public var isThisPhone: Bool { kind == .thisPhone }

    /// Whether a person may open this one in the editor.
    ///
    /// FALSE FOR THE PHONE, AND THE SCREEN OBEYS IT RATHER THAN CHECKING THE
    /// KIND ITSELF. There is nothing on the phone bench to edit — no address
    /// somebody transcribed, no token, no name worth changing — and a form that
    /// opens on it would be four fields that cannot do anything, which is the
    /// enabled-and-inert control this app is built not to ship.
    public var isEditable: Bool { kind == .network }

    /// The loopback port the app is actually listening on, or nil before it is.
    public var phoneBenchPort: Int? {
        guard kind == .thisPhone,
              let colon = address.lastIndex(of: ":"),
              let port = Int(address[address.index(after: colon)...]),
              port > 0 else { return nil }
        return port
    }

    /// The same bench, with the port the app's listener actually got.
    ///
    /// A NO-OP ON ANYTHING ELSE, on purpose: a network bench's address is
    /// somebody's typing and nothing here may rewrite it.
    public func servedOn(port: Int) -> BenchEndpoint {
        guard kind == .thisPhone else { return self }
        var out = self
        out.address = "127.0.0.1:\(port)"
        return out
    }

    // MARK: - refusing a bad one

    public enum Refusal: Error, Equatable, Sendable {
        case emptyName
        case address(DuckBench.Refusal)
        /// The phone's own bench, asked for before its listener came up.
        case phoneBenchNotListening

        public var message: String {
            switch self {
            case .emptyName:
                return "Give this bench a name. With more than one saved, \"the bench\" stops "
                     + "being enough to tell them apart."
            case .address(let refusal):
                return refusal.message
            case .phoneBenchNotListening:
                return PhoneBenchReport.notListening
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
        _ = try resolved()
    }

    /// The parsed address, for a caller that is about to build a request.
    ///
    /// THE PHONE TAKES THE SHORT WAY OUT, and it is not laziness. Its address
    /// is written by the app from a port the kernel handed it, so there is no
    /// typing to validate — and the one thing that CAN be wrong with it, that
    /// the listener is not up, has nothing to do with what `DuckBench.address`
    /// knows how to say. Run through that parser, `127.0.0.1:0` comes back as
    /// `notLocal("127.0.0.1:0")` — a sentence telling somebody their own phone
    /// is not on their network, about an address they never typed.
    public func resolved() throws -> DuckBench.Address {
        if kind == .thisPhone {
            guard let port = phoneBenchPort else { throw Refusal.phoneBenchNotListening }
            return DuckBench.Address(host: "127.0.0.1", port: port)
        }
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
