import XCTest
@testable import StudioKit

/// OpenCastor's discovery rules, held here: identity before address, the
/// record as the authority for ports, and a saved machine that answers where
/// it is never moved.
final class DuckMachineTests: XCTestCase {

    private let advert = DuckMachine.Advert(id: "m-robot", name: "robot", benchPort: 8770, routerPort: 8771)

    // MARK: - the record

    func testARecordReadsItsIdentityNameAndOnlyThePortsItPublished() {
        let a = DuckMachine.Advert.read(txt: ["id": "m1", "name": "robot", "bench_port": "8770"])
        XCTAssertEqual(a, DuckMachine.Advert(id: "m1", name: "robot", benchPort: 8770, routerPort: nil))
    }

    func testARecordWithoutAnIdentityIsIgnoredBecauseItCannotBeMatched() {
        XCTAssertNil(DuckMachine.Advert.read(txt: ["name": "robot", "bench_port": "8770"]))
    }

    func testARecordWithNoServiceOrABadPortOffersNothing() {
        XCTAssertNil(DuckMachine.Advert.read(txt: ["id": "m1"]))
        XCTAssertNil(DuckMachine.Advert.read(txt: ["id": "m1", "bench_port": "99999"]))
    }

    // MARK: - reconciling

    func testAnUnsavedMachineWithABenchIsOfferedAndNotAdded() {
        let found = DuckMachine.Found(advert: advert, host: "192.168.68.90")
        XCTAssertEqual(DuckMachine.reconcile(saved: [], answered: [], found: [found]), [.offer(found)])
    }

    func testARouterOnlyMachineIsNotOfferedAsABench() {
        let routerOnly = DuckMachine.Advert(id: "gpu", name: "gpu", benchPort: nil, routerPort: 8771)
        let found = DuckMachine.Found(advert: routerOnly, host: "192.168.68.83")
        XCTAssertEqual(DuckMachine.reconcile(saved: [], answered: [], found: [found]), [])
    }

    func testASilentSavedMachineSeenAtANewHostIsFollowedByIdentity() {
        let bench = BenchEndpoint(name: "robot", address: "192.168.68.93:8770", machineID: "m-robot")
        let found = DuckMachine.Found(advert: advert, host: "192.168.68.90")
        XCTAssertEqual(DuckMachine.reconcile(saved: [bench], answered: [], found: [found]),
                       [.moved(bench: bench.id, to: "192.168.68.90:8770", routerPort: 8771)])
    }

    func testASavedMachineThatAnswersWhereItIsIsNeverMoved() {
        let bench = BenchEndpoint(name: "robot", address: "100.122.199.6:8770", machineID: "m-robot")
        let found = DuckMachine.Found(advert: advert, host: "192.168.68.90")
        XCTAssertEqual(DuckMachine.reconcile(saved: [bench], answered: [bench.id], found: [found]), [],
                       "one machine on Wi-Fi and a tailnet has two addresses, and the saved one works")
    }

    func testABenchTypedWithoutAnIdentityIsNeverRePointedByAnAddress() {
        let typed = BenchEndpoint(name: "robot", address: "192.168.68.93:8770")
        let found = DuckMachine.Found(advert: advert, host: "192.168.68.93")
        XCTAssertEqual(DuckMachine.reconcile(saved: [typed], answered: [], found: [found]), [.offer(found)],
                       "no identity to match, so it is offered rather than silently merged")
    }

    func testAFoundMachineIsSavedWithItsIdentityAndRouter() throws {
        let bench = try XCTUnwrap(DuckMachine.bench(from: .init(advert: advert, host: "192.168.68.90")))
        XCTAssertEqual(bench.address, "192.168.68.90:8770")
        XCTAssertEqual(bench.machineID, "m-robot")
        XCTAssertEqual(bench.routerPort, 8771)
    }

    // MARK: - the router

    func testTheRouterIsOnTheBenchesHostAtItsPublishedPortOrTheUsualOne() {
        let found = BenchEndpoint(name: "r", address: "100.122.199.6:8770", routerPort: 9000)
        XCTAssertEqual(DuckMachine.routerURL(for: found)?.absoluteString, "http://100.122.199.6:9000")
        let typed = BenchEndpoint(name: "r", address: "100.122.199.6:8770")
        XCTAssertEqual(DuckMachine.routerURL(for: typed)?.absoluteString, "http://100.122.199.6:8771")
        XCTAssertNil(DuckMachine.routerURL(for: .thisPhone), "the phone's bench runs no router")
    }

    // MARK: - saved benches keep working

    func testABenchSavedBeforeMachinesWereRememberedStillDecodes() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"My bench","address":"10.0.0.2:8770","hasToken":false}"#
        let bench = try JSONDecoder().decode(BenchEndpoint.self, from: Data(old.utf8))
        XCTAssertNil(bench.machineID)
        XCTAssertEqual(bench.kind, .network)
        let round = try JSONDecoder().decode(BenchEndpoint.self, from: JSONEncoder().encode(
            BenchEndpoint(name: "r", address: "10.0.0.2:8770", machineID: "m", routerPort: 8771)))
        XCTAssertEqual(round.machineID, "m")
        XCTAssertEqual(round.routerPort, 8771)
    }

    // MARK: - the words

    func testTheLaunchLineSaysEachServiceItChecked() {
        XCTAssertEqual(DuckMachine.line(.init(name: "robot", bench: .answering, router: .silent)),
                       "robot: bench ready · router not answering")
        XCTAssertEqual(DuckMachine.line(.init(name: "gpu", bench: .notRun, router: .answering)),
                       "gpu: router ready")
    }

    func testTheOfferNamesTheServicesTheMachinePublished() {
        XCTAssertEqual(DuckMachine.offer(.init(advert: advert, host: "h")),
                       "Found robot on your network (bench, router).")
        XCTAssertTrue(DuckMachine.discoveryFooter.contains("Nothing is added until you tap Add"))
    }
}
