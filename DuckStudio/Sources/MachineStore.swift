import Foundation
import StudioKit

/// What the app found when it opened: each saved machine's bench and router,
/// and any machine on the network nobody has saved yet.
///
/// A LADDER PER MACHINE, IN PARALLEL. Every saved network bench is asked for
/// its bench health and, separately, its router health — one being down says
/// nothing about the other (OpenCastor's Rover had no console and was reported
/// dead on every launch until its probe became a ladder). All of it runs at
/// once with a short timeout, because this is in front of somebody who just
/// opened the app.
///
/// THEN THE BROWSE, THEN THE RECONCILE. Only a bench whose own address did not
/// answer can be followed to a new one, and only by identity — the rule lives
/// in `DuckMachine.reconcile`, where it is tested; this applies the answer.
@MainActor
final class MachineStore: ObservableObject {

    @Published private(set) var statuses: [DuckMachine.Status] = []
    @Published private(set) var offers: [DuckMachine.Found] = []
    /// Microduck bridges seen on the network.
    @Published private(set) var ducks: [DuckMachine.FoundDuck] = []
    @Published private(set) var notes: [String] = []
    @Published private(set) var checking = false

    private let discovery = MachineDiscovery()
    private let duckDiscovery = MachineDiscovery()
    private static let timeout: TimeInterval = 3

    /// Run once as the app opens, and again whenever somebody asks.
    func check(_ benches: BenchStore) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        notes = []
        let saved = benches.benches.filter { !$0.isThisPhone }.map { benches.armed($0) }

        async let browse = discovery.discover(type: DuckMachine.serviceType, timeout: Self.timeout)
        async let duckBrowse = duckDiscovery.discover(type: DuckMachine.duckServiceType,
                                                      timeout: Self.timeout)
        var answered = Set<UUID>()
        var fresh: [DuckMachine.Status] = []
        await withTaskGroup(of: (BenchEndpoint, Bool, Bool).self) { group in
            for bench in saved {
                group.addTask {
                    async let benchUp = Self.benchAnswers(bench)
                    async let routerUp = Self.routerAnswers(bench)
                    return (bench, await benchUp, await routerUp)
                }
            }
            for await (bench, benchUp, routerUp) in group {
                if benchUp { answered.insert(bench.id) }
                fresh.append(DuckMachine.Status(name: bench.name,
                                                bench: benchUp ? .answering : .silent,
                                                router: routerUp ? .answering : .silent))
            }
        }
        let (records, ending) = await browse
        if ending == .permissionLikelyOff { notes.append(DuckMachine.permissionOff) }
        let found = records.compactMap { record in
            DuckMachine.Advert.read(txt: record.txt).map { DuckMachine.Found(advert: $0, host: record.host) }
        }
        ducks = await duckBrowse.found.compactMap {
            DuckMachine.FoundDuck.read(txt: $0.txt, name: $0.name, host: $0.host, port: $0.port)
        }

        var newOffers: [DuckMachine.Found] = []
        for action in DuckMachine.reconcile(saved: saved, answered: answered, found: found) {
            switch action {
            case .moved(let id, let address, let routerPort):
                guard let bench = saved.first(where: { $0.id == id }) else { continue }
                benches.follow(id, to: address, routerPort: routerPort)
                notes.append(DuckMachine.moved(bench.name, to: address))
                if let i = fresh.firstIndex(where: { $0.name == bench.name }) {
                    fresh[i] = DuckMachine.Status(name: bench.name, bench: .answering,
                                                  router: routerPort == nil ? .notRun : .answering)
                }
            case .offer(let machine):
                newOffers.append(machine)
            }
        }
        statuses = fresh.sorted { $0.name < $1.name }
        offers = newOffers
    }

    /// Save a found machine as a bench, with its identity, and select it.
    func add(_ machine: DuckMachine.Found, to benches: BenchStore) {
        guard let bench = DuckMachine.bench(from: machine) else { return }
        benches.save(bench)
        benches.selectedID = bench.id
        offers.removeAll { $0.advert.id == machine.advert.id }
        statuses.append(DuckMachine.Status(name: bench.name, bench: .answering,
                                           router: machine.advert.routerPort == nil ? .notRun : .answering))
    }

    /// Point Robot > Bridge at a found duck. The token stays the person's to enter.
    func use(_ duck: DuckMachine.FoundDuck) {
        UserDefaults.standard.set(duck.host, forKey: "bridge.host")
        UserDefaults.standard.set(duck.port, forKey: "bridge.port")
        notes.append(DuckMachine.duckFilledIn(duck))
    }

    // MARK: - the probes

    nonisolated private static func benchAnswers(_ bench: BenchEndpoint) async -> Bool {
        guard let address = try? bench.resolved() else { return false }
        var request = DuckBench.urlRequest(for: DuckBench.health(address), token: bench.token)
        request.timeoutInterval = timeout
        return await ok(request)
    }

    nonisolated private static func routerAnswers(_ bench: BenchEndpoint) async -> Bool {
        guard let base = DuckMachine.routerURL(for: bench) else { return false }
        var request = URLRequest(url: base.appendingPathComponent("health"))
        request.timeoutInterval = timeout
        return await ok(request)
    }

    nonisolated private static func ok(_ request: URLRequest) async -> Bool {
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
