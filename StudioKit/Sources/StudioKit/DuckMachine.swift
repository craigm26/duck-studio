import Foundation

/// A computer on the person's network that runs Duck Studio's services — a
/// physics bench, a plan router, or both — and how the app finds it again.
///
/// BORROWED FROM OPENCASTOR, WHERE IT WAS LEARNED THE HARD WAY. "I can't find
/// the robot on the same network" turned out to be three faults at once: a
/// DHCP lease had moved, nothing had ever published the mDNS record, and the
/// fallback probed a port the robot did not serve. So, as there:
///
/// - IDENTITY BEFORE ADDRESS. A machine's record carries a stable `id`. A saved
///   bench is re-pointed only when that same id is seen at a new host; an
///   address that merely answers might have inherited the old lease.
/// - THE RECORD IS THE AUTHORITY FOR PORTS. The advertiser publishes only the
///   ports whose health routes answered, so a machine that runs no router is
///   never offered one. Defaults apply only to a bench somebody typed.
/// - A LADDER, NOT ONE PROBE. At launch every saved machine is asked for each
///   service separately; one service down says nothing about the other.
///
/// NOTHING HERE TOUCHES THE NETWORK. The app browses and probes; this reads
/// what came back and decides, so every rule is checked by `swift test`.
public enum DuckMachine {

    /// The Bonjour type the advertiser publishes (`tools/advertise_machine.py`)
    /// and the app browses. Declared in `NSBonjourServices`, because iOS
    /// refuses a browse for an undeclared type silently.
    public static let serviceType = "_duckstudio._tcp"
    public static let defaultBenchPort = 8770
    public static let defaultRouterPort = 8771

    // MARK: - what a machine says about itself

    /// One machine's record, read from its TXT keys.
    public struct Advert: Equatable, Sendable {
        public let id: String
        public let name: String
        public let benchPort: Int?
        public let routerPort: Int?

        public init(id: String, name: String, benchPort: Int?, routerPort: Int?) {
            self.id = id; self.name = name; self.benchPort = benchPort; self.routerPort = routerPort
        }

        /// Nil without an `id`: a record with no identity cannot be matched to
        /// anything saved, so it is of no use to reconnecting and is not offered.
        public static func read(txt: [String: String]) -> Advert? {
            guard let id = txt["id"]?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
            func port(_ key: String) -> Int? {
                guard let value = txt[key].flatMap(Int.init), (1..<65536).contains(value) else { return nil }
                return value
            }
            let advert = Advert(id: id, name: txt["name"].flatMap { $0.isEmpty ? nil : $0 } ?? id,
                                benchPort: port("bench_port"), routerPort: port("router_port"))
            return advert.benchPort == nil && advert.routerPort == nil ? nil : advert
        }
    }

    /// A record seen on the network, with the host it resolved to.
    public struct Found: Equatable, Sendable {
        public let advert: Advert
        public let host: String
        public init(advert: Advert, host: String) { self.advert = advert; self.host = host }

        public var benchAddress: String? { advert.benchPort.map { "\(host):\($0)" } }
    }

    // MARK: - reconciling what is saved with what was seen

    public enum Action: Equatable, Sendable {
        /// A saved bench's machine answered at a new host: same identity, so
        /// it is safe to re-point, and its token comes with it.
        case moved(bench: UUID, to: String, routerPort: Int?)
        /// A machine nobody has saved, offered for one tap.
        case offer(Found)
    }

    /// What to do about what the browse found.
    ///
    /// `answered` is the set of saved benches whose own address answered this
    /// launch: a bench that is fine where it is is never moved, even if its id
    /// is also seen somewhere else (a machine on two networks — Wi-Fi and a
    /// tailnet — is one machine with two addresses, and the saved one works).
    public static func reconcile(saved: [BenchEndpoint], answered: Set<UUID>,
                                 found: [Found]) -> [Action] {
        var actions: [Action] = []
        for machine in found {
            let owners = saved.filter { $0.machineID == machine.advert.id }
            if owners.isEmpty {
                if machine.advert.benchPort != nil { actions.append(.offer(machine)) }
                continue
            }
            for bench in owners where !answered.contains(bench.id) {
                guard let address = machine.benchAddress, address != bench.address else { continue }
                actions.append(.moved(bench: bench.id, to: address, routerPort: machine.advert.routerPort))
            }
        }
        return actions
    }

    /// A bench saved from a found machine, carrying its identity.
    public static func bench(from found: Found) -> BenchEndpoint? {
        guard let address = found.benchAddress else { return nil }
        return BenchEndpoint(name: found.advert.name, address: address,
                             machineID: found.advert.id, routerPort: found.advert.routerPort)
    }

    // MARK: - the router on the same machine

    /// Where the plan router is, for a bench: the same host, at the port its
    /// record gave, or the router's usual port for a bench somebody typed.
    /// Nil for the phone's own bench, which runs no router.
    public static func routerURL(for bench: BenchEndpoint) -> URL? {
        guard !bench.isThisPhone, let address = try? DuckBench.address(bench.address) else { return nil }
        return URL(string: "http://\(address.host):\(bench.routerPort ?? defaultRouterPort)")
    }

    // MARK: - what the launch check saw

    public enum State: Equatable, Sendable { case answering, silent, notRun }

    public struct Status: Equatable, Sendable {
        public let name: String
        public let bench: State
        public let router: State
        public init(name: String, bench: State, router: State) {
            self.name = name; self.bench = bench; self.router = router
        }
    }

    /// One line per machine, as My Microduck prints it.
    public static func line(_ status: Status) -> String {
        func say(_ service: String, _ state: State) -> String? {
            switch state {
            case .answering: return "\(service) ready"
            case .silent: return "\(service) not answering"
            case .notRun: return nil
            }
        }
        let parts = [say("bench", status.bench), say("router", status.router)].compactMap { $0 }
        return "\(status.name): " + (parts.isEmpty ? "not checked" : parts.joined(separator: " · "))
    }

    public static let heading = "Your machines"
    public static let checking = "Checking your machines…"
    public static let noneSaved =
        "No machines saved. A computer running the bench or the plan router on your network "
      + "appears here when it is found; you can also add one by address in Settings > Benches."
    public static func moved(_ name: String, to address: String) -> String {
        "\(name) moved to \(address) on your network. Same machine, so it was followed."
    }
    public static func offer(_ found: Found) -> String {
        let services = [found.advert.benchPort.map { _ in "bench" },
                        found.advert.routerPort.map { _ in "router" }].compactMap { $0 }
        return "Found \(found.advert.name) on your network (\(services.joined(separator: ", ")))."
    }
    /// THE CONSOLE'S RULE: SAY WHY, NOT JUST "NOT THERE". A browse refused by
    /// Local Network permission looks exactly like an empty network; this is
    /// the sentence for the first, so nobody goes looking for a broken Pi.
    public static let permissionOff =
        "The app could not look on your network, which is what it looks like when Local Network "
      + "access is off for Microduck Studio (Settings > Privacy & Security > Local Network). "
      + "Saved machines were still checked."
    public static let addButton = "Add"
    public static let discoveryFooter =
        "When the app opens it asks each saved machine whether it is up, and looks on your "
      + "network for machines running Duck Studio's bench or router. Nothing is added until you "
      + "tap Add, and a saved machine is only followed to a new address when it proves it is the "
      + "same machine."
    public static func usingRouter(on name: String, _ url: URL) -> String {
        "Using the router on \(name): \(url.absoluteString). Type an address to use another."
    }
}
