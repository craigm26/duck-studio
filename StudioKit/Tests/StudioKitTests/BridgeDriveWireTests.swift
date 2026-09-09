import XCTest
@testable import StudioKit
import DuckKit

/// The bytes this app sends a real robot, pinned to `duck-ipc-proto`.
///
/// WHY THIS FILE EXISTS AND WHY IT IS BYTES RATHER THAN BEHAVIOUR. Until now
/// every assertion about `robot.move` in this package was an assertion about a
/// bench: `BenchPeer` turns a twist into `POST /intent`, so a wrong sign or a
/// misspelled key produced a duck that walked slightly oddly in a simulator and
/// nothing anywhere said so. Over the bridge those same bytes reach `robotd`
/// unchanged — the relay does not parse the vocabulary — and a wrong sign is a
/// robot walking the wrong way in somebody's kitchen.
///
/// THE CONTRACT IS NOW READABLE, WHICH IT WAS NOT WHEN THIS CODE WAS WRITTEN.
/// `pollen-robotics/microduck` is public and `duck-ipc-proto/src/lib.rs` is the
/// source of every claim below:
///
/// ```
/// /// Velocity twist. Continuous intent — see [`method::ROBOT_MOVE`].
/// pub struct MoveParams {
///     /// Forward, m/s.
///     pub vx: f64,
///     /// Left, m/s.
///     pub vy: f64,
///     /// Yaw rate, rad/s, positive turns left.
///     pub vyaw: f64,
/// }
/// ```
///
/// with `pub const ROBOT_MOVE: &str = "robot.move";` and `Call::RobotMove` in
/// the notification family. Their own note on the frame is that the prototype
/// grew five separate sign flags "precisely because the convention was never
/// written down, so every new consumer determined it empirically and
/// disagreed". This file is this app refusing to be the sixth.
final class BridgeDriveWireTests: XCTestCase {

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - robot.move, field for field

    /// THE THREE KEYS, THEIR SPELLINGS, AND NOTHING ELSE IN THE PARAMS.
    ///
    /// `MoveParams` derives `#[serde(deny_unknown_fields)]`'s sibling default on
    /// several neighbouring types, and a fourth key is exactly the kind of thing
    /// a frame counter or a hold would slip in — `DuckLineSequence` stamps its
    /// number BESIDE the bytes for this reason. So the assertion is not "vx is
    /// there", it is "vx, vy, vyaw are there and they are the whole of it".
    func testMoveParamsAreExactlyVxVyVyaw() throws {
        let twist = DuckDrive.Twist(vx: 0.2, vy: -0.1, vyaw: 0.4)
        let line = try DuckCall.move(twist).line(id: nil)
        let top = try object(line)

        XCTAssertEqual(top["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(top["method"] as? String, "robot.move")
        // A NOTIFICATION CARRIES NO ID. The contract's continuous intents are
        // never answered, so an id would be a reply somebody waits for forever.
        XCTAssertNil(top["id"])

        let params = try XCTUnwrap(top["params"] as? [String: Any])
        XCTAssertEqual(Set(params.keys), ["vx", "vy", "vyaw"])
        XCTAssertEqual(params["vx"] as? Double, 0.2)
        XCTAssertEqual(params["vy"] as? Double, -0.1)
        XCTAssertEqual(params["vyaw"] as? Double, 0.4)

        // THE SAME THREE VALUES THE PROTO'S OWN ROUND-TRIP TEST USES
        // (`Call::RobotMove(MoveParams { vx: 0.2, vy: -0.1, vyaw: 0.4 })`), so
        // this test and their test are looking at the same numbers.
        XCTAssertEqual(String(decoding: line, as: UTF8.self),
                       "{\"jsonrpc\":\"2.0\",\"method\":\"robot.move\","
                     + "\"params\":{\"vx\":0.2,\"vy\":-0.1,\"vyaw\":0.4}}\n")
    }

    /// ONE NEWLINE, AT THE END, AND THAT IS THE FRAME.
    ///
    /// `framing.rs`: the newline that separates messages IS the delimiter, in
    /// both directions, and it is safe rather than lucky because serde escapes
    /// a newline inside a string. Nothing in a twist is a string at all.
    func testAMoveFrameIsOneLine() throws {
        let line = try DuckCall.move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: -1.5)).line(id: nil)
        XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1)
        XCTAssertEqual(line.last, 0x0A)
    }

    /// THE FRAME, IN WORDS, AND THE SIGNS THAT GO WITH IT.
    ///
    /// Trunk frame: **x forward, y LEFT, z up, positive vyaw turns LEFT**. This
    /// is asserted through `DuckDrive.twist(for:)` rather than by restating the
    /// numbers, because the mapping from a stick to a twist is where a sign
    /// error would actually live: the params builder above only copies.
    ///
    /// `padd`'s layout, which this transcribes: left stick translates
    /// (`vx: left_y`, `vy: -left_x`), right stick x steers (`vyaw: -right_x`).
    /// So pushing the left stick UP is forward, pushing it LEFT is +vy, and
    /// pushing the right stick LEFT is +vyaw.
    func testTheSignsAreTrunkFrameXForwardYLeftYawLeft() {
        // Stick up (positive y on the left stick) is forward: +vx, nothing else.
        let up = DuckDrive.twist(for: DuckDrive.Sticks(left: .init(x: 0, y: 1),
                                                       right: .init(x: 0, y: 0)))
        XCTAssertGreaterThan(up.vx, 0, "left stick up must be forward")
        XCTAssertEqual(up.vy, 0, accuracy: 1e-12)
        XCTAssertEqual(up.vyaw, 0, accuracy: 1e-12)

        // Stick down is backward.
        let down = DuckDrive.twist(for: DuckDrive.Sticks(left: .init(x: 0, y: -1),
                                                         right: .init(x: 0, y: 0)))
        XCTAssertLessThan(down.vx, 0, "left stick down must be backward")

        // Stick left is +vy, because y is LEFT. This is the sign that had five
        // flags in Pollen's prototype.
        let left = DuckDrive.twist(for: DuckDrive.Sticks(left: .init(x: -1, y: 0),
                                                         right: .init(x: 0, y: 0)))
        XCTAssertGreaterThan(left.vy, 0, "left stick left must be +vy (y is left)")
        XCTAssertEqual(left.vx, 0, accuracy: 1e-12)

        // Right stick left is +vyaw, because positive yaw turns LEFT.
        let turnLeft = DuckDrive.twist(for: DuckDrive.Sticks(left: .init(x: 0, y: 0),
                                                             right: .init(x: -1, y: 0)))
        XCTAssertGreaterThan(turnLeft.vyaw, 0, "right stick left must be +vyaw (yaw turns left)")

        let turnRight = DuckDrive.twist(for: DuckDrive.Sticks(left: .init(x: 0, y: 0),
                                                              right: .init(x: 1, y: 0)))
        XCTAssertLessThan(turnRight.vyaw, 0, "right stick right must be −vyaw")
    }

    /// THE SPEEDS ARE `padd`'S CLAP DEFAULTS AND NOT A GUESS: `--max-linear`
    /// 0.3 m/s, `--max-linear-backward` 0.3, `--max-angular` 1.5 rad/s — which
    /// is deliberately NOT the same range as the linear axes.
    func testTheEnvelopeIsPaddsOwnLimits() {
        let full = DuckDrive.twist(for: DuckDrive.Sticks(left: .init(x: -1, y: 1),
                                                         right: .init(x: -1, y: 0)))
        XCTAssertLessThanOrEqual(abs(full.vx), 0.3 + 1e-12)
        XCTAssertLessThanOrEqual(abs(full.vy), 0.3 + 1e-12)
        XCTAssertLessThanOrEqual(abs(full.vyaw), 1.5 + 1e-12)
        // And the angular range really is wider than the linear one, so a
        // future edit that "tidied" them into one limit fails here.
        XCTAssertGreaterThan(1.5, 0.3)
    }

    /// A NaN NEVER REACHES THE WIRE. JSON cannot write one, so a robot would
    /// get a line it cannot parse — and over the bridge that line has already
    /// left the phone by the time anybody notices.
    func testANaNTwistIsRefusedRatherThanSerialised() {
        let bad = DuckDrive.Twist(vx: .nan, vy: 0, vyaw: 0)
        XCTAssertThrowsError(try DuckCall.move(bad).line(id: nil)) { error in
            XCTAssertEqual(error as? DuckCall.Misuse, .notANumber(.move))
        }
    }

    // MARK: - robot.stop and robot.head

    /// STOP IS A REQUEST, WITH AN ID, AND NO PARAMS AT ALL.
    ///
    /// `Call::RobotStop` is a unit variant — it takes no parameter struct — so
    /// `params` is omitted rather than sent as `{}`: an empty object is a claim
    /// that the method takes parameters and got none, which is a different
    /// thing to say to a strict deserialiser.
    func testStopIsARequestWithNoParams() throws {
        let line = try DuckCall.stop.line(id: 7)
        XCTAssertEqual(String(decoding: line, as: UTF8.self),
                       "{\"id\":7,\"jsonrpc\":\"2.0\",\"method\":\"robot.stop\"}\n")
        let top = try object(line)
        XCTAssertNil(top["params"])
        XCTAssertFalse(DuckCall.stop.isNotification)
        // Sent the wrong way round it refuses rather than becoming a
        // notification nobody answers.
        XCTAssertThrowsError(try DuckCall.stop.line(id: nil))
    }

    /// THE HEAD IS FOUR ANGLES IN SNAKE CASE, in `HeadParams`' own order, and
    /// it is a NOTIFICATION like the twist.
    func testHeadParamsAreTheProtosFourSnakeCaseAngles() throws {
        let pose = DuckHead(neckPitch: 0.35, headPitch: -0.1, headYaw: 0.2, headRoll: 0)
        let line = try DuckCall.head(pose).line(id: nil)
        let params = try XCTUnwrap(try object(line)["params"] as? [String: Any])
        XCTAssertEqual(Set(params.keys), ["neck_pitch", "head_pitch", "head_yaw", "head_roll"])
        XCTAssertEqual(params["neck_pitch"] as? Double, 0.35)
        XCTAssertEqual(params["head_pitch"] as? Double, -0.1)
        XCTAssertEqual(params["head_yaw"] as? Double, 0.2)
        XCTAssertEqual(params["head_roll"] as? Double, 0)
        XCTAssertTrue(DuckCall.head(pose).isNotification)
    }

    /// THE HEAD IS A MODE AND THE BODY IS ZEROED IN THE SAME FRAME. Both halves
    /// are `padd`'s, and the second one is the safety half.
    func testTheHeadModeIsPaddsMappingIncludingItsTwoInversions() {
        let sticks = DuckDrive.Sticks(left: .init(x: 1, y: 1), right: .init(x: 1, y: 1))
        let head = DuckDrive.head(for: sticks)
        XCTAssertEqual(head.neckPitch, DuckDrive.maxHead, accuracy: 1e-12)   //  right_y
        XCTAssertEqual(head.headPitch, -DuckDrive.maxHead, accuracy: 1e-12)  // -left_y
        XCTAssertEqual(head.headYaw, -DuckDrive.maxHead, accuracy: 1e-12)    // -left_x
        XCTAssertEqual(head.headRoll, DuckDrive.maxHead, accuracy: 1e-12)    //  right_x
        XCTAssertEqual(DuckDrive.maxHead, 2.5)
        // The travel is generous rather than a servo limit — it feeds the
        // policy's observation, and the network decides how far the head goes.
        XCTAssertGreaterThan(DuckDrive.maxHead, DuckDrive.maxTurn)
        XCTAssertTrue(DuckDrive.stillWhilePosingTheHead.contains("zero"))
        // A centred pair is a level head, not a nudge.
        XCTAssertEqual(DuckDrive.head(for: .centred), .level)
    }

    /// A head pose is REFUSED ON A BENCH by name, and carried on the bridge —
    /// which is why the control that sends one is drawn on one venue only.
    func testAHeadPoseIsCarriedToARobotAndRefusedByABench() throws {
        XCTAssertTrue(DuckMethod.reach(for: .bridge).contains(.head))
        XCTAssertFalse(DuckMethod.reach(for: .bench).contains(.head))
        let refusal = try XCTUnwrap(BenchPeer.refusal(for: .head(.level)))
        XCTAssertEqual(refusal, .noPlaceToPutAHeadPose(.head))
    }

    // MARK: - robot.subscribe

    func testSubscribeIsARequestAndItsRateIsOptional() throws {
        let asked = try DuckCall.subscribe(hz: 10).line(id: 2)
        XCTAssertEqual(String(decoding: asked, as: UTF8.self),
                       "{\"id\":2,\"jsonrpc\":\"2.0\",\"method\":\"robot.subscribe\","
                     + "\"params\":{\"hz\":10}}\n")

        // ABSENT MEANS EVERY TICK — the proto's own words — so nil omits the
        // member rather than sending a null.
        let everyTick = try DuckCall.subscribe(hz: nil).line(id: 3)
        XCTAssertNil(try object(everyTick)["params"])
        XCTAssertNil(DuckSubscription.everyTick)
        XCTAssertFalse(DuckCall.subscribe(hz: nil).isNotification)
    }

    /// The routing table's answer for the new method, on all four transports.
    func testSubscribeIsCarriedWhereARealDaemonAnswersAndNowhereElse() {
        XCTAssertTrue(DuckMethod.reach(for: .bridge).contains(.subscribe))
        XCTAssertTrue(DuckMethod.reach(for: .webRTC).contains(.subscribe))
        // A bench pushes nothing, so there is no stream to turn on.
        XCTAssertFalse(DuckMethod.reach(for: .bench).contains(.subscribe))
        // BLE carries provisioning and status, and payloads never traverse it.
        XCTAssertFalse(DuckMethod.reach(for: .ble).contains(.subscribe))
        XCTAssertFalse(DuckMethod.subscribe.mutatesTheRecoveryPath)
        XCTAssertTrue(DuckCall.allShapes.contains { $0.method == .subscribe })
        XCTAssertEqual(DuckMethod.subscribe.rawValue, "robot.subscribe")
    }

    /// The bench refuses it by name rather than accepting and pushing nothing.
    func testABenchRefusesSubscribeAndSaysWhy() throws {
        let refusal = try XCTUnwrap(BenchPeer.refusal(for: .subscribe(hz: 10)))
        XCTAssertEqual(refusal, .nothingToSubscribeTo)
        XCTAssertTrue(refusal.message.contains("pushes nothing"))
    }

    /// `SubscribeResult`, read back with the wire's own snake_case.
    func testASubscriptionIsReadWithTheProtosOwnKeys() throws {
        let result = try JSONSerialization.data(withJSONObject: [
            "accepted": true,
            "walk": "alpha_walking.onnx",
            "stand": "alpha_stand.onnx",
            "ground_pick": "alpha_ground_pick.onnx",
            "skills": ["ball_kick_left", "roulade"],
        ])
        let read = try DuckSubscription.read(DuckReply(id: 1, result: result, failure: nil))
        XCTAssertTrue(read.accepted)
        XCTAssertEqual(read.walk, "alpha_walking.onnx")
        XCTAssertEqual(read.stand, "alpha_stand.onnx")
        // ground_pick, NOT groundPick: a Swift-cased key on the wire is a key
        // nothing would ever fill in.
        XCTAssertEqual(read.groundPick, "alpha_ground_pick.onnx")
        XCTAssertEqual(read.skills, ["ball_kick_left", "roulade"])
        XCTAssertNil(read.unavailable)
        XCTAssertTrue(read.says.contains("alpha_walking.onnx"))
    }

    /// AN ABSENT `stand` IS A CONFIGURATION AND THE SENTENCE SAYS SO, rather
    /// than reading as a missing file.
    func testNoStandingNetworkIsSaidAsAConfiguration() throws {
        let result = try JSONSerialization.data(withJSONObject: [
            "accepted": true, "walk": "alpha_walking.onnx",
        ])
        let read = try DuckSubscription.read(DuckReply(id: 1, result: result, failure: nil))
        XCTAssertNil(read.stand)
        XCTAssertTrue(read.says.contains("runs at every velocity"))
    }

    /// `unavailable` OUTRANKS THE NETWORK LIST, because a robot that is not
    /// driving is the fact, and a list of files under it would bury it.
    func testUnavailableIsWhatGetsSaid() throws {
        let result = try JSONSerialization.data(withJSONObject: [
            "accepted": true, "unavailable": "policy disabled in params",
        ])
        let read = try DuckSubscription.read(DuckReply(id: 1, result: result, failure: nil))
        XCTAssertTrue(read.says.contains("policy disabled in params"))
        XCTAssertTrue(read.says.contains("Nothing is driving"))
    }

    // MARK: - the cadence

    /// THE PREFERRED RATE WINS AGAINST A NORMAL BRIDGE, and it is comfortably
    /// inside the contract's 20–50 Hz band.
    func testTheCadenceIsTwentyHertzAgainstAnOrdinaryBridge() {
        XCTAssertEqual(BridgeDrive.interval(bridgeDeadmanMilliseconds: 700), 0.05, accuracy: 1e-12)
        XCTAssertEqual(BridgeDrive.hz(bridgeDeadmanMilliseconds: 700), 20, accuracy: 1e-9)
        // Three frames fit inside robotd's own 500 ms deadman more than twice
        // over, which is the margin this is chosen for.
        XCTAssertLessThan(BridgeDrive.interval(bridgeDeadmanMilliseconds: 700)
                            * BridgeDrive.framesPerDeadman,
                          BridgeDrive.robotdDeadmanSeconds)
    }

    /// A BRIDGE WITH A SHORT DEADMAN SPEEDS THIS APP UP rather than being
    /// ignored until it stops the duck under a hand that is still driving.
    func testAShortDeadmanTightensTheCadence() {
        let tight = BridgeDrive.interval(bridgeDeadmanMilliseconds: 90)
        XCTAssertEqual(tight, 0.03, accuracy: 1e-12)
        XCTAssertLessThan(tight * BridgeDrive.framesPerDeadman, 0.09 + 1e-12)
    }

    /// SILENCE IS READ AS THE SHIPPED DEFAULT, NOT AS "no deadman". The
    /// optimistic reading of silence is what gets a duck stopped mid-stride by
    /// a bridge this app decided to ignore.
    func testABridgeThatDidNotSayIsTreatedAsTheShippedDefault() {
        XCTAssertEqual(BridgeDrive.interval(bridgeDeadmanMilliseconds: nil),
                       BridgeDrive.interval(bridgeDeadmanMilliseconds: 700),
                       accuracy: 1e-12)
        XCTAssertTrue(BridgeDrive.deadmanChainSaid(bridgeDeadmanMilliseconds: nil)
                        .contains("did not say"))
        XCTAssertTrue(BridgeDrive.deadmanChainSaid(bridgeDeadmanMilliseconds: 700)
                        .contains("700 ms"))
    }

    /// ROBOTD'S OWN NUMBER IS NAMED AS A DEFAULT, never as a reading from this
    /// robot — nothing in this app asks a duck what its deadman is set to.
    func testTheChainNamesAllThreeTimersAndCallsFiveHundredADefault() {
        let said = BridgeDrive.deadmanChainSaid(bridgeDeadmanMilliseconds: 700)
        XCTAssertTrue(said.contains("500 ms as shipped"))
        XCTAssertTrue(said.contains("robotd"))
        XCTAssertTrue(said.contains("20 times a second"))
        XCTAssertEqual(BridgeDrive.robotdDeadmanSeconds, 0.5)
        XCTAssertEqual(BridgeDrive.bridgeDeadmanSecondsDefault, 0.7)
    }

    /// THE HEADINGS ARE TESTED BECAUSE THEY ARE PROMISES. "What is not here"
    /// is a claim about the section under it, and the guard that sent them into
    /// the kit exists because a promise nothing can read goes on being made
    /// after it stops being true.
    func testTheVenuesHeadingsAreTheKitsAndAreDistinct() {
        let headings = [BridgeDrive.drivingHeading, BridgeDrive.runningHeading,
                        BridgeDrive.sticksHeading, BridgeDrive.absencesHeading]
        XCTAssertEqual(Set(headings).count, headings.count)
        for heading in headings {
            XCTAssertFalse(heading.isEmpty)
            XCTAssertFalse(heading.hasSuffix("."), heading)
        }
        XCTAssertEqual(BridgeDrive.drivingHeading, "Driving a robot")
        XCTAssertEqual(BridgeDrive.absencesHeading, "What is not here")
    }

    /// The two doors between the screen that opens the link and the one that
    /// uses it, both of which name the consequence rather than just the place.
    func testTheTwoLinkDoorsNameWhatTheyCost() {
        XCTAssertTrue(BridgeDrive.driveOnControl.contains("Control tab"))
        XCTAssertTrue(BridgeDrive.driveOnControl.contains("robot.move"))
        XCTAssertTrue(BridgeDrive.disconnectEndsDriving.contains("one link"))
        XCTAssertTrue(BridgeDrive.disconnectEndsDriving.contains("robot.stop"))
        XCTAssertTrue(BridgeDrive.connectFirst.contains("Bridge"))
    }

    /// The three absences this venue has to explain rather than leave blank.
    func testTheVenueSaysWhatItIsNotDrawing() {
        XCTAssertTrue(BridgeDrive.noPictureHere.contains("joint angles"))
        XCTAssertTrue(BridgeDrive.noWorldNoScene.contains("Reset"))
        XCTAssertTrue(BridgeDrive.noPolicySwapHere.contains("robotd owns its slots"))
        XCTAssertTrue(BridgeDrive.oneWriterOnly.contains("single command slot"))
        XCTAssertTrue(BridgeDrive.theseCommandsAreReal.contains("robot.move"))
    }
}
