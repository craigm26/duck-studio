import XCTest
@testable import StudioKit

/// The links that carry a line, against the links that can carry a simulation.
///
/// WHAT IS ACTUALLY UNDER TEST IS A DISAGREEMENT. `DuckLineTransport` and
/// `SimDuck.LineTransport` answer different questions and their answers differ
/// on exactly one case — Bluetooth — so a test that only checked "both exclude
/// the bench" would pass while somebody quietly made them the same enum. The
/// second thing under test is that the bench's exclusion is ONE sentence rather
/// than two copies of one, because two copies is how a paragraph gets softened
/// in one place and not the other.
final class DuckLineTransportTests: XCTestCase {

    /// Every case maps to the transport kind of the same name, so `reach` and
    /// `vet` are answered about the link the peer is actually on.
    func testEachLineTransportNamesItsOwnKind() {
        XCTAssertEqual(DuckLineTransport.ble.kind, .ble)
        XCTAssertEqual(DuckLineTransport.webRTC.kind, .webRTC)
        XCTAssertEqual(DuckLineTransport.bridge.kind, .bridge)
        XCTAssertEqual(DuckLineTransport.allCases.count, 3)
    }

    /// THE ONE THAT CANNOT BE CONSTRUCTED. A bench answers HTTP posts; a
    /// JSON-RPC line posted at `/intent` parses as a body with no velocities in
    /// it, which is a zero twist and a duck standing perfectly still while the
    /// app reports it walking.
    func testABenchIsNotSomethingALinePeerCanBePutOn() {
        XCTAssertNil(DuckLineTransport(.bench))
        XCTAssertNotNil(DuckLineTransport(.ble))
        XCTAssertNotNil(DuckLineTransport(.webRTC))
        XCTAssertNotNil(DuckLineTransport(.bridge))
    }

    /// The refusal is by identity, not by content — a test comparing the two
    /// strings character by character would pass on a copy, and a copy is the
    /// thing this assertion exists to forbid.
    func testTheBenchRefusalIsTheSameSentenceSimDuckAlreadyWrote() {
        XCTAssertEqual(DuckLineTransport.benchIsNotALine,
                       SimDuck.LineTransport.benchIsNotALine)
        XCTAssertEqual(DuckLineTransport.whyNot(.bench), SimDuck.LineTransport.benchIsNotALine)
        for kind in [DuckTransportKind.ble, .webRTC, .bridge] {
            XCTAssertNil(DuckLineTransport.whyNot(kind), kind.label)
        }
    }

    /// THE DELIBERATE DISAGREEMENT, PINNED. Bluetooth carries a line — that is
    /// what `DuckLink` writes over a characteristic — and it cannot carry a
    /// simulation, because BLE's reach is the recovery path and a simulation has
    /// nothing to be locked out of. Two enums, two questions, one case where
    /// they differ, and this is the test that stops somebody collapsing them.
    func testBluetoothCarriesALineAndStillCannotCarryASimulation() {
        XCTAssertNotNil(DuckLineTransport(.ble))
        XCTAssertNil(SimDuck.LineTransport(.ble))
        XCTAssertEqual(SimDuck.LineTransport.whyNot(.ble),
                       SimDuck.LineTransport.bluetoothIsABondWithSomethingPhysical)
    }
}
