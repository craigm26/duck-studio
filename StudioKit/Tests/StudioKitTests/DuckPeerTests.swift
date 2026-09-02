import XCTest
import DuckKit
@testable import StudioKit

/// The one vocabulary, pinned.
///
/// THESE ARE TRANSCRIPTION AND ROUTING TESTS, AND THE ROUTING HALF IS THE ONE
/// THAT MATTERS. Nothing in `DuckPeer` has met a robot; what can be checked
/// from here is that the wire names are the names in `duck-ipc-proto`, that a
/// continuous intent goes out the way the contract says continuous intents go
/// out, and — the assertion this file exists for — that no network transport
/// can reach the pairing PIN or the updater. That last one is not a test of
/// code that could plausibly regress by accident; it is a test that will still
/// be here when somebody adds a fifth transport in a hurry.
final class DuckPeerTests: XCTestCase {

    // MARK: - the wire names

    /// Straight out of `duck-ipc-proto/src/lib.rs`'s method list. A name typed
    /// from memory produces a call refused by name, which on a screen is
    /// indistinguishable from a robot that does not have the feature.
    func testTheWireNamesAreTheProtosOwn() {
        XCTAssertEqual(DuckMethod.hello.rawValue, "hello")
        XCTAssertEqual(DuckMethod.move.rawValue, "robot.move")
        XCTAssertEqual(DuckMethod.head.rawValue, "robot.head")
        XCTAssertEqual(DuckMethod.look.rawValue, "robot.look")
        XCTAssertEqual(DuckMethod.stop.rawValue, "robot.stop")
        XCTAssertEqual(DuckMethod.enable.rawValue, "robot.enable")
        XCTAssertEqual(DuckMethod.initPose.rawValue, "robot.init")
        XCTAssertEqual(DuckMethod.relax.rawValue, "robot.relax")
        XCTAssertEqual(DuckMethod.pairingPin.rawValue, "system.pairingPin")
        XCTAssertEqual(DuckMethod.setPairingPin.rawValue, "system.setPairingPin")
    }

    /// The two entries that are NOT Pollen's say so in their own spelling: the
    /// state call is namespaced `studio.`, and the update family is a glob that
    /// no daemon could answer even if it were somehow sent.
    func testTheEntriesThatArePollensAreDistinguishableFromTheOnesThatAreNot() {
        XCTAssertEqual(DuckMethod.state.rawValue, "studio.state")
        XCTAssertFalse(DuckMethod.state.rawValue.hasPrefix("robot."),
                       "A method this app invented must not wear robot's prefix.")
        XCTAssertEqual(DuckMethod.update.rawValue, "update.*")
    }

    /// A duplicate raw value would silently merge two rows of the routing
    /// table, and `Set<DuckMethod>` would hide it.
    func testEveryMethodIsSpelledOnce() {
        let names = Set(DuckMethod.allCases.map(\.rawValue))
        XCTAssertEqual(names.count, DuckMethod.allCases.count)
        XCTAssertEqual(DuckMethod.allCases.count, 12,
                       "A method was added or removed. That is fine — but the routing table and "
                       + "the reach tests below are the reason this count is pinned.")
    }

    // MARK: - notifications versus requests

    /// `duck-ipc-proto`: the continuous intents are notifications, everything
    /// else is a request. The sweep is over `allShapes` rather than a list
    /// typed here, so a call added to the vocabulary is covered by this test
    /// without anybody remembering to add it.
    func testOnlyTheContinuousIntentsAreNotifications() {
        let notifying = DuckCall.allShapes.filter(\.isNotification).map(\.method)
        XCTAssertEqual(Set(notifying), [.move, .head])
        XCTAssertEqual(notifying.count, 2)
    }

    /// A notification is never answered, so an id on one is a caller waiting
    /// forever for a reply the robot has no obligation to send.
    func testANotificationRefusesAnID() {
        XCTAssertThrowsError(try DuckCall.move(.still).line(id: 7)) { error in
            XCTAssertEqual(error as? DuckCall.Misuse, .notificationCarriedAnID(.move))
        }
        XCTAssertThrowsError(try DuckCall.head(.level).line(id: 1)) { error in
            XCTAssertEqual(error as? DuckCall.Misuse, .notificationCarriedAnID(.head))
        }
    }

    /// And a request without an id is a notification, so the answer it exists
    /// to fetch never arrives.
    func testARequestRefusesToGoOutWithoutAnID() throws {
        for call in DuckCall.allShapes where !call.isNotification {
            XCTAssertThrowsError(try call.line(id: nil), "\(call.method.rawValue)") { error in
                XCTAssertEqual(error as? DuckCall.Misuse, .requestHadNoID(call.method))
            }
        }
    }

    /// The id that was asked for is the id that goes on the wire, and a
    /// notification carries no `id` member at all — not `null`, absent.
    func testTheIDLandsOnRequestsAndIsAbsentFromNotifications() throws {
        let request = try object(DuckCall.stop.line(id: 42))
        XCTAssertEqual(request["id"] as? Int, 42)
        XCTAssertEqual(request["method"] as? String, "robot.stop")
        XCTAssertEqual(request["jsonrpc"] as? String, "2.0")

        let notification = try object(DuckCall.move(.still).line(id: nil))
        XCTAssertNil(notification["id"])
        XCTAssertFalse(notification.keys.contains("id"),
                       "An explicit null id is still an id to a strict deserialiser.")
    }

    // MARK: - the framing

    /// `framing.rs`: "The newline that already separates messages is the frame
    /// delimiter, in both directions." One line, one newline, at the end —
    /// counted rather than eyeballed, because a stray newline inside a payload
    /// splits one message into two that are each invalid.
    func testEveryLineIsOneNewlineTerminatedNDJSONObject() throws {
        for call in DuckCall.allShapes {
            let line = try call.line(id: call.isNotification ? nil : 1)
            let newlines = line.filter { $0 == 0x0A }
            XCTAssertEqual(newlines.count, 1, "\(call.method.rawValue) carried \(newlines.count)")
            XCTAssertEqual(line.last, 0x0A, "\(call.method.rawValue) did not end in a newline")
            // And the bytes before it are one whole JSON object.
            let body = line.dropLast()
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(body)) as? [String: Any],
                            "\(call.method.rawValue)")
        }
    }

    // MARK: - the twist

    /// `MoveParams` is `{vx, vy, vyaw}` and nothing else, spelled exactly so.
    func testTheTwistUsesPollensFieldNames() throws {
        let twist = DuckDrive.Twist(vx: 0.3, vy: -0.1, vyaw: 1.5)
        let params = try XCTUnwrap(object(DuckCall.move(twist).line(id: nil))["params"]
                                   as? [String: Any])
        XCTAssertEqual(Set(params.keys), ["vx", "vy", "vyaw"])
        XCTAssertEqual(params["vx"] as? Double, 0.3)
        XCTAssertEqual(params["vy"] as? Double, -0.1)
        XCTAssertEqual(params["vyaw"] as? Double, 1.5)
    }

    /// THE SIGNS SURVIVE THE JOURNEY FROM THUMB TO WIRE, which is the thing
    /// five sign flags in Pollen's prototype were spent on. A stick pushed LEFT
    /// is negative in stick units and must leave here as a POSITIVE `vy`,
    /// because the protocol fixes y positive to the left; the same for a right
    /// stick pushed left and a positive `vyaw`. Get either wrong and the duck
    /// mirrors the driver — which looks like a policy fault, not a sign fault.
    func testAStickPushedLeftLeavesAsPositiveVyAndPositiveVyaw() throws {
        let sticks = DuckDrive.Sticks(left: .init(x: -1, y: 0), right: .init(x: -1, y: 0))
        let params = try XCTUnwrap(
            object(DuckCall.move(DuckDrive.twist(for: sticks)).line(id: nil))["params"]
            as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(params["vy"] as? Double), DuckDrive.maxSideways, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(params["vyaw"] as? Double), DuckDrive.maxTurn, accuracy: 1e-9)
    }

    /// There is one twist type in this package. If a second ever appears, this
    /// call site stops compiling, which is the point.
    func testTheCallTakesDuckDrivesOwnTwist() {
        let call = DuckCall.move(DuckDrive.Twist.still)
        XCTAssertEqual(call, .move(DuckDrive.Twist(vx: 0, vy: 0, vyaw: 0)))
    }

    /// JSON cannot write NaN, so a serialiser handed one throws something
    /// generic and unreadable. This throws something that names the method.
    func testANonFiniteCommandIsStoppedBeforeTheWire() {
        let broken = DuckDrive.Twist(vx: .nan, vy: 0, vyaw: 0)
        XCTAssertThrowsError(try DuckCall.move(broken).line(id: nil)) { error in
            XCTAssertEqual(error as? DuckCall.Misuse, .notANumber(.move))
        }
        let tilted = DuckHead(neckPitch: .infinity)
        XCTAssertThrowsError(try DuckCall.head(tilted).line(id: nil)) { error in
            XCTAssertEqual(error as? DuckCall.Misuse, .notANumber(.head))
        }
    }

    // MARK: - the head

    /// `HeadParams` is snake case, four angles, in radians.
    func testTheHeadUsesTheProtosFourNames() throws {
        let pose = DuckHead(neckPitch: 0.1, headPitch: 0.2, headYaw: 0.3, headRoll: 0.4)
        let params = try XCTUnwrap(object(DuckCall.head(pose).line(id: nil))["params"]
                                   as? [String: Any])
        XCTAssertEqual(Set(params.keys), ["neck_pitch", "head_pitch", "head_yaw", "head_roll"])
        XCTAssertEqual(params["neck_pitch"] as? Double, 0.1)
        XCTAssertEqual(params["head_roll"] as? Double, 0.4)
    }

    /// A method that takes nothing sends no `params` member. An empty object is
    /// a claim that it takes parameters and got none.
    func testACallWithNoParametersSendsNoParamsMember() throws {
        for call in [DuckCall.stop, .enable, .initPose, .relax, .state] {
            let top = try object(call.line(id: 3))
            XCTAssertFalse(top.keys.contains("params"), "\(call.method.rawValue)")
        }
    }

    /// One hello in the app, not two: the line this builds is byte-for-byte the
    /// line `DuckLink` has been written against a robot with.
    func testHelloIsTheSameLineDuckLinkAlreadySends() throws {
        XCTAssertEqual(try DuckCall.hello.line(id: 1), try DuckLink.helloRequest(id: 1))
        let params = try XCTUnwrap(object(DuckCall.hello.line(id: 1))["params"] as? [String: Any])
        XCTAssertEqual(params["api_version"] as? Int, 16)
    }

    // MARK: - reach, which is the whole point

    /// THE ASSERTION THIS FILE EXISTS FOR. A peer that can rewrite the pairing
    /// PIN can lock a phone out of BLE, and BLE is the recovery path — so the
    /// PIN and the updater are answered where the caller has already bonded and
    /// is standing next to the duck, and nowhere else.
    func testNoNetworkTransportCanReachThePinOrTheUpdater() {
        for transport in [DuckTransportKind.webRTC, .bridge] {
            let reach = DuckMethod.reach(for: transport)
            XCTAssertFalse(reach.contains(.pairingPin), "\(transport.label) reached the PIN")
            XCTAssertFalse(reach.contains(.setPairingPin), "\(transport.label) reached setPin")
            XCTAssertFalse(reach.contains(.update), "\(transport.label) reached the updater")
        }
    }

    /// Said once more the general way, so a method added to the recovery-path
    /// family is covered without this test being edited.
    func testEveryRecoveryPathMethodIsBluetoothOnly() {
        for method in DuckMethod.allCases where method.mutatesTheRecoveryPath {
            XCTAssertTrue(DuckMethod.reach(for: .ble).contains(method), method.rawValue)
            for transport in [DuckTransportKind.webRTC, .bench, .bridge] {
                XCTAssertFalse(DuckMethod.reach(for: transport).contains(method),
                               "\(method.rawValue) is reachable over \(transport.label)")
            }
        }
        XCTAssertEqual(Set(DuckMethod.allCases.filter(\.mutatesTheRecoveryPath)),
                       [.pairingPin, .setPairingPin, .update])
    }

    /// The recovery path is not merely denied by the routing table — it cannot
    /// be built at all. There is no `DuckCall` that names one, so there is no
    /// line for a transport to send by mistake.
    func testTheRecoveryPathIsNotEvenRepresentableAsACall() {
        let buildable = Set(DuckCall.allShapes.map(\.method))
        XCTAssertEqual(buildable.count, 9)
        for method in DuckMethod.allCases where method.mutatesTheRecoveryPath {
            XCTAssertNil(DuckCall.shape(of: method), method.rawValue)
            XCTAssertFalse(buildable.contains(method), method.rawValue)
        }
    }

    /// BLE carries "provisioning, status, update trigger/progress" and Pollen
    /// say outright that it is "too slow and too constrained for the full
    /// surface", with payloads never crossing it. So driving is not on it —
    /// including the tempting one, `robot.stop`, which is not in the subset
    /// `btd` serves. What stops an undriven duck is the robot's own age-based
    /// deadman.
    func testBluetoothCarriesNoDriving() {
        let reach = DuckMethod.reach(for: .ble)
        for method in [DuckMethod.move, .head, .look, .stop, .enable, .initPose, .relax] {
            XCTAssertFalse(reach.contains(method), "BLE claimed \(method.rawValue)")
        }
        XCTAssertTrue(reach.contains(.hello))
    }

    /// `studio.state` is this app's, so the two transports a real `robotd`
    /// answers do not carry it. A screen that asked a robot for it would get a
    /// refusal naming a method Pollen never wrote.
    func testTheStateCallIsNotOfferedOnTransportsARobotDaemonAnswers() {
        XCTAssertFalse(DuckMethod.reach(for: .ble).contains(.state))
        XCTAssertFalse(DuckMethod.reach(for: .webRTC).contains(.state))
        XCTAssertTrue(DuckMethod.reach(for: .bench).contains(.state))
        XCTAssertTrue(DuckMethod.reach(for: .bridge).contains(.state))
    }

    /// The bench is physics and the gaps are real: `DuckDrive.intent` posts
    /// `{vx, vy, vyaw, hold}` with no head in it, and a simulator has no motor
    /// bus to enable.
    func testTheBenchCarriesWhatTheBenchActuallyHas() {
        XCTAssertEqual(DuckMethod.reach(for: .bench), [.hello, .move, .stop, .state])
    }

    /// WebRTC is where the contract says the continuous intents will travel, so
    /// it carries the whole robot surface and none of the recovery path.
    func testWebRTCCarriesTheWholeRobotSurface() {
        XCTAssertEqual(DuckMethod.reach(for: .webRTC),
                       [.hello, .move, .head, .look, .stop, .enable, .initPose, .relax])
    }

    /// A method routed nowhere is almost certainly a routing slip rather than a
    /// decision — the silent denial `route.rs` refuses to allow. This catches
    /// the version of it that survives the compiler.
    func testNoMethodIsStranded() {
        for method in DuckMethod.allCases {
            let carried = DuckTransportKind.allCases.contains {
                DuckMethod.reach(for: $0).contains(method)
            }
            XCTAssertTrue(carried, "\(method.rawValue) is reachable from nothing at all")
        }
    }

    // MARK: - replies

    func testAResultIsCarriedBack() throws {
        let line = Data(#"{"jsonrpc":"2.0","id":4,"result":{"api_version":16,"ok":true}}"#.utf8)
        let reply = try DuckReply.decode(line)
        XCTAssertEqual(reply.id, 4)
        XCTAssertTrue(reply.succeeded)
        XCTAssertNil(reply.failure)
        XCTAssertEqual(reply.field("api_version"), 16)
        XCTAssertEqual(reply.field("ok"), true)
        XCTAssertNil(reply.field("missing") as String?)
    }

    /// A refusal is an ANSWER. It comes back carried, not thrown, because "the
    /// duck refused" and "the link broke" are different diagnoses and a thrown
    /// error makes every failure look like a network problem.
    func testARefusalIsCarriedRatherThanThrown() throws {
        let line = Data(#"{"jsonrpc":"2.0","id":9,"error":{"code":-32601,"message":"no such method"}}"#.utf8)
        let reply = try DuckReply.decode(line)
        XCTAssertFalse(reply.succeeded)
        XCTAssertNil(reply.result)
        XCTAssertEqual(reply.failure, DuckReply.Failure(code: -32601, message: "no such method"))
        XCTAssertEqual(reply.failure?.says, "The duck refused: no such method (-32601)")
    }

    /// `robot.stop` has no reason to answer with an object, and a decoder that
    /// demanded one would refuse a perfectly good yes.
    func testABareResultIsStillAResult() throws {
        let reply = try DuckReply.decode(Data(#"{"jsonrpc":"2.0","id":1,"result":true}"#.utf8))
        XCTAssertTrue(reply.succeeded)
        XCTAssertEqual(reply.result.map { String(decoding: $0, as: UTF8.self) }, "true")
    }

    /// Only genuinely malformed replies throw, and they reuse `DuckLink`'s
    /// wording so the app has one voice for "that was not JSON-RPC".
    func testSomethingThatIsNotAReplyThrows() {
        XCTAssertThrowsError(try DuckReply.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? DuckLink.LinkError, .notJSON)
        }
        XCTAssertThrowsError(try DuckReply.decode(Data(#"{"jsonrpc":"2.0","id":1}"#.utf8))) { error in
            guard case .unexpected = (error as? DuckLink.LinkError) else {
                return XCTFail("\(error)")
            }
        }
    }

    // MARK: - the peer itself

    /// A stub link that carries the bench's subset. It answers nothing; what is
    /// under test is what it refuses to send.
    private final class StubPeer: DuckPeer {
        let identity: DuckIdentity
        let reach: Set<DuckMethod>
        let transportKind: DuckTransportKind

        init(identity: DuckIdentity, reach: Set<DuckMethod>,
             transportKind: DuckTransportKind = .bench) {
            self.identity = identity
            self.reach = reach
            self.transportKind = transportKind
        }

        func call(_ c: DuckCall) async throws -> DuckReply {
            try vet(c, asNotification: false)
            return DuckReply(id: 1, result: Data("{}".utf8), failure: nil)
        }

        func notify(_ c: DuckCall) async throws {
            try vet(c, asNotification: true)
        }

        /// This stub is about what a peer refuses to SEND; it reports nothing,
        /// and an ended stream is how a peer says that out loud.
        nonisolated func states() -> AsyncStream<DuckState> {
            AsyncStream { $0.finish() }
        }
    }

    private func benchPeer() -> StubPeer {
        StubPeer(identity: DuckIdentity(name: "duckbench", colourway: .teal, kind: .sim),
                 reach: DuckMethod.reach(for: .bench))
    }

    /// The check exists so that three transports implementing it and a fourth
    /// forgetting is not possible — it is written once, here, and inherited.
    func testAPeerRefusesAMethodItsLinkDoesNotCarry() async {
        let peer = benchPeer()
        do {
            _ = try await peer.call(.look(.level))
            XCTFail("A bench answered robot.look")
        } catch {
            XCTAssertEqual(error as? DuckCall.Misuse, .outOfReach(.look, .bench))
        }
    }

    /// A continuous intent sent as a request would wait for an answer the
    /// contract says never comes; a stop sent as a notification would leave the
    /// caller claiming "it stopped" on no evidence.
    func testAPeerRefusesACallSentTheWrongWayRound() async {
        let peer = benchPeer()
        do {
            _ = try await peer.call(.move(.still))
            XCTFail("A continuous intent was sent as a request")
        } catch {
            XCTAssertEqual(error as? DuckCall.Misuse, .wrongDirection(.move))
        }
        do {
            try await peer.notify(.stop)
            XCTFail("An answered call was sent as a notification")
        } catch {
            XCTAssertEqual(error as? DuckCall.Misuse, .wrongDirection(.stop))
        }
    }

    func testAPeerAcceptsWhatItsLinkCarries() async throws {
        let peer = benchPeer()
        try await peer.notify(.move(.still))
        let reply = try await peer.call(.stop)
        XCTAssertTrue(reply.succeeded)
    }

    // MARK: - identity

    /// The kind travels with the name because it is the claim that matters and
    /// the transport is not evidence for it: a bridge can relay to hardware,
    /// and WebRTC can reach a simulator on a desk.
    func testAnIdentitySaysWhetherItIsRealWithoutBeingAskedAboutItsLink() {
        let sim = DuckIdentity(name: "duckbench", colourway: .teal, kind: .sim)
        XCTAssertEqual(sim.says, "duckbench — simulated, teal")
        let real = DuckIdentity(name: "microduck-01", kind: .real)
        XCTAssertEqual(real.colourway, .yellow, "The default is the colour this app draws ducks in.")
        XCTAssertEqual(real.says, "microduck-01 — robot, yellow")
        XCTAssertNotEqual(sim, DuckIdentity(name: "duckbench", colourway: .teal, kind: .real))
    }

    /// Every colourway is drawable and distinct — a duplicate swatch would put
    /// two peers in one room in the same colour, which is the one job this has.
    func testEveryColourwayHasItsOwnSwatchAndItsOwnWord() {
        let swatches = DuckColourway.allCases.map { "\($0.rgb)" }
        XCTAssertEqual(Set(swatches).count, DuckColourway.allCases.count)
        XCTAssertEqual(Set(DuckColourway.allCases.map(\.label)).count,
                       DuckColourway.allCases.count)
        for colour in DuckColourway.allCases {
            let (r, g, b) = colour.rgb
            for channel in [r, g, b] {
                XCTAssertTrue(channel >= 0 && channel <= 1, "\(colour.rawValue)")
            }
        }
    }

    // MARK: - helpers

    private func object(_ line: @autoclosure () throws -> Data) throws -> [String: Any] {
        let data = try line()
        let body = data.last == 0x0A ? data.dropLast() : data[...]
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(body)) as? [String: Any])
    }
}

extension DuckPeerTests {

    /// A REFUSAL NAMES THE LINK IT WAS ACTUALLY CHECKED AGAINST. `vet` used to
    /// take the transport as an argument, with nothing tying it to `reach` — so
    /// a peer could refuse a call in a sentence blaming a link it is not, which
    /// in a package whose product is accurate refusals is the worst kind of bug:
    /// confidently, specifically wrong.
    func testARefusalCannotNameALinkThePeerIsNot() async {
        let bluetooth = StubPeer(identity: DuckIdentity(name: "pip", kind: .real),
                                 reach: DuckMethod.reach(for: .ble),
                                 transportKind: .ble)
        do {
            try await bluetooth.notify(.move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)))
            XCTFail("Bluetooth does not carry robot.move.")
        } catch {
            guard case .outOfReach(_, let named)? = error as? DuckCall.Misuse else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(named, .ble, "the refusal must name the peer's own link")
        }
    }
}
