import XCTest
@testable import StudioKit

/// What this app has proved to a duck, which is nothing, and the case that says
/// so by not existing.
///
/// THE FIRST TEST IS A HEADCOUNT AND IT IS THE SERIOUS ONE. `DuckAuthority` has
/// two cases; the moment a third appears called anything like "authenticated",
/// a screen somewhere draws a tick that means "somebody wrote a word in a
/// constructor". This test is what makes adding that case a deliberate act with
/// a red build in front of it.
final class DuckAuthorityTests: XCTestCase {

    func testThereAreTwoCasesAndNeitherOfThemIsAuthenticated() {
        XCTAssertEqual(DuckAuthority.allCases.count, 2)
        for authority in DuckAuthority.allCases {
            XCTAssertFalse(authority.rawValue.lowercased().contains("authenticated"),
                           authority.rawValue)
        }
        XCTAssertEqual(Set(DuckAuthority.allCases.map(\.rawValue)),
                       ["bondedInPerson", "nothingHasBeenProved"])
    }

    /// Bluetooth is the only link with a credential, and the credential is that
    /// somebody was standing next to the duck.
    func testOnlyBluetoothHasProvedAnything() {
        XCTAssertEqual(DuckAuthority.of(.ble), .bondedInPerson)
        XCTAssertEqual(DuckAuthority.of(.webRTC), .nothingHasBeenProved)
        XCTAssertEqual(DuckAuthority.of(.bridge), .nothingHasBeenProved)
        XCTAssertEqual(DuckAuthority.of(.bench), .nothingHasBeenProved)
    }

    /// A BENCH TOKEN IS NOT AN EXCEPTION AND THE SENTENCE SAYS SO, because it
    /// is the one somebody will point at: a bench that checks a bearer token is
    /// checking that a caller may run physics on that machine.
    func testTheSentenceRefusesToCountABenchTokenAsProofAboutADuck() {
        let said = DuckAuthority.nothingHasBeenProved.says
        XCTAssertTrue(said.contains("bench token"), said)
        XCTAssertTrue(said.contains("says nothing about a duck"), said)
        XCTAssertTrue(DuckAuthority.bondedInPerson.says.contains("standing next to"),
                      DuckAuthority.bondedInPerson.says)
        XCTAssertTrue(DuckAuthority.noLinkHereHasAuthenticated.contains("mediad"),
                      DuckAuthority.noLinkHereHasAuthenticated)
    }

    /// The three methods that own somebody's way back into their robot, and the
    /// rest.
    func testOnlyTheRecoveryPathIsGatedByAuthority() {
        for method in DuckMethod.allCases {
            XCTAssertTrue(DuckAuthority.bondedInPerson.mayReach(method), method.rawValue)
            XCTAssertEqual(DuckAuthority.nothingHasBeenProved.mayReach(method),
                           !method.mutatesTheRecoveryPath, method.rawValue)
        }
    }

    // MARK: - threaded into the card

    /// THE CHECK CAN FAIL, AND HERE IS IT FAILING. `DeviceCard.Control.of`
    /// takes `reach` as a parameter so a peer that narrowed its reach is
    /// answered honestly — which means a caller can also hand it a reach set
    /// naming a recovery-path method on a link that has proved nothing. The
    /// routing table cannot see that, because it was not consulted; the
    /// authority can, and refuses with the link's own sentence.
    func testARecoveryCallOfferedOnALinkThatProvedNothingIsNotDrawn() {
        let widened = DuckMethod.reach(for: .bridge).union([.setPairingPin])
        let control = DeviceCard.Control.of(.setPairingPin, over: .bridge, reach: widened)
        XCTAssertFalse(control.isLive)
        XCTAssertEqual(control.reason, DuckAuthority.nothingHasBeenProved.says)
    }

    /// The same call on the link that has bonded is drawn. A gate that refused
    /// everywhere would be a gate nobody could tell from a missing feature.
    func testTheSameCallIsDrawnOverBluetooth() {
        let control = DeviceCard.Control.of(.setPairingPin, over: .ble,
                                            reach: DuckMethod.reach(for: .ble))
        XCTAssertTrue(control.isLive, control.reason ?? "")
    }

    /// The routing table still answers first, so an ordinary refusal still
    /// reads as one: `robot.move` over Bluetooth is out of reach, not
    /// unauthorised, and telling somebody the wrong one of those costs an hour.
    func testTheRoutingTableStillAnswersBeforeTheAuthorityDoes() {
        let control = DeviceCard.Control.of(.setPairingPin, over: .bench,
                                            reach: DuckMethod.reach(for: .bench))
        XCTAssertEqual(control.reason,
                       DuckCall.Misuse.outOfReach(.setPairingPin, .bench).message)
    }

    /// An explicitly-passed authority beats the transport's own, which is what
    /// makes this parameter worth having: a bonded BLE link that has since been
    /// unpaired is a real state a caller may know about and the enum may not.
    func testAnExplicitAuthorityOverridesTheTransportsOwn() {
        let control = DeviceCard.Control.of(.pairingPin, over: .ble,
                                            reach: DuckMethod.reach(for: .ble),
                                            authority: .nothingHasBeenProved)
        XCTAssertFalse(control.isLive)
        XCTAssertEqual(control.reason, DuckAuthority.nothingHasBeenProved.says)
    }

    /// Driving is not gated by any of this. A control that vanished because of
    /// an authority rule nobody asked for would be the inert-surface failure in
    /// a new costume.
    func testDrivingIsNotGatedByAuthorityOnAnyLink() {
        for transport in DuckTransportKind.allCases {
            let reach = DuckMethod.reach(for: transport)
            guard reach.contains(.move) else { continue }
            let control = DeviceCard.Control.of(.move, over: transport, reach: reach)
            XCTAssertTrue(control.isLive, "\(transport.label): \(control.reason ?? "")")
        }
    }
}
