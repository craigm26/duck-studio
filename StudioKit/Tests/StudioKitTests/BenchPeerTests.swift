import XCTest
import DuckKit
@testable import StudioKit

/// The bench, answering the robot's vocabulary.
///
/// WHAT THESE TESTS ARE ACTUALLY FOR. A few of them check that a `DuckCall`
/// arrives at the right duckbench endpoint with the right body, which is
/// translation and could hardly be otherwise. The rest are about the gaps: the
/// five calls a bench cannot do, and whether it says so in words that name what
/// is missing rather than in the routing table's shrug. A peer that silently
/// no-opped `robot.enable` would leave somebody believing a motor bus had been
/// powered on a machine that has no motors, and that belief is exactly what
/// this app exists not to produce.
///
/// NOTHING HERE TOUCHES A NETWORK. The peer takes an errand closure — for the
/// reason `BenchSetup.diagnose` takes pieces rather than a `URLSession` — so a
/// bench that is not there can answer whatever a test needs it to, including
/// refusing.
final class BenchPeerTests: XCTestCase {

    // MARK: - a bench that is not there

    /// Stands in for duckbench: remembers every call it was handed, and answers
    /// with whatever the test told it to.
    private actor FakeBench {
        private(set) var seen: [DuckBench.Call] = []
        private let answer: @Sendable (DuckBench.Call) throws -> Data

        init(_ answer: @escaping @Sendable (DuckBench.Call) throws -> Data) {
            self.answer = answer
        }

        func take(_ call: DuckBench.Call) throws -> Data {
            seen.append(call)
            return try answer(call)
        }

        var count: Int { seen.count }

        var paths: [String] { seen.map(\.url.path) }

        /// The body of the nth call, as JSON.
        func body(_ index: Int) throws -> [String: Any] {
            let data = try XCTUnwrap(seen[index].body)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }

    private static let there = DuckBench.Address(host: "192.168.1.20", port: 8770)

    /// A state block of the shape `/intent`, `/stop`, `/policy` and `/reset`
    /// all answer with — the same fixture `DuckDriveTests` reads, because a
    /// second shape written here would be testing this peer against a bench
    /// nobody has.
    private static func liveBody(t: Double = 1.5, height: Double = 0.116,
                                 upright: Bool = true, policy: String? = "alpha_walking",
                                 vx: Double = 0.3) -> Data {
        var body: [String: Any] = [
            "t": t,
            "joints": [Double](repeating: 0.25, count: DuckModel.policyJointCount),
            "height": height, "upright": upright,
            "position": [0.2, -0.1, height], "quaternion": [1, 0, 0, 0],
            "command": ["vx": vx, "vy": 0.0, "vyaw": 0.0],
        ]
        if let policy { body["policy"] = policy }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private static func healthBody() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "bench": "duck-bench", "plant": "a bare floor and a duck",
            "plantName": "duck.xml", "plantDigest": String(repeating: "a", count: 64),
            "tickHz": DuckModel.tickHz, "cores": 4,
            "policies": ["alpha_walking", "alpha_stand"], "trains": false,
        ])
    }

    /// IT THROWS BECAUSE THE INITIALISER DOES, and the initialiser does
    /// because a NaN hold is a crash later rather than an error now. Every
    /// test below hands it a real number, so the `try` here never fires; the
    /// one that hands it a NaN builds its peer by hand, where the throw is the
    /// assertion.
    private func peer(_ fake: FakeBench, hold: Double = DuckDrive.holdSeconds,
                      name: String? = nil) throws -> BenchPeer {
        try BenchPeer(address: Self.there, name: name, hold: hold) { call in
            try await fake.take(call)
        }
    }

    /// A bench with a policy loaded that answers everything.
    private func walkingBench() -> FakeBench {
        FakeBench { call in
            call.url.path == "/health" ? Self.healthBody() : Self.liveBody()
        }
    }

    // MARK: - reach

    /// ASSERTED AGAINST THE TABLE RATHER THAN AGAINST A LITERAL. A set written
    /// out here would agree with `DuckMethod.reach(for: .bench)` on the day it
    /// was typed and drift from it the first time the bench column changed —
    /// and a peer whose reach is wider than the routing table's is a peer
    /// claiming a route the table has denied.
    func testItsReachIsTheRoutingTablesAnswerAndNotASecondCopyOfIt() throws {
        XCTAssertEqual(try peer(walkingBench()).reach, DuckMethod.reach(for: .bench))
    }

    // MARK: - the four it carries

    /// `DuckDrive.intent` posts Pollen's three names and a hold, and this is the
    /// call that has to arrive unchanged: the signs in it are the ones five
    /// separate flags were spent on in Pollen's prototype.
    func testAMoveBecomesAnIntentPostCarryingPollensThreeNumbers() async throws {
        let fake = walkingBench()
        try await peer(fake).notify(.move(DuckDrive.Twist(vx: 0.3, vy: -0.1, vyaw: 1.5)))

        let paths = await fake.paths
        XCTAssertEqual(paths, ["/intent"])
        let body = try await fake.body(0)
        XCTAssertEqual(body["vx"] as? Double, 0.3)
        XCTAssertEqual(body["vy"] as? Double, -0.1)
        XCTAssertEqual(body["vyaw"] as? Double, 1.5)
        XCTAssertEqual(body["hold"] as? Double, DuckDrive.holdSeconds)
    }

    /// The hold is the driving loop's business — how much sim time one intent
    /// buys — so the peer posts what it was built with rather than a constant.
    func testTheHoldTheDriverChoseIsTheHoldThatIsPosted() async throws {
        let fake = walkingBench()
        try await peer(fake, hold: 0.05).notify(.move(.still))
        let body = try await fake.body(0)
        XCTAssertEqual(body["hold"] as? Double, 0.05)
    }

    /// `robot.stop` is discrete because the caller needs to know it landed, so
    /// this one comes back answered rather than fired and forgotten.
    func testAStopBecomesAStopPostAndComesBackAnswered() async throws {
        let fake = walkingBench()
        let reply = try await peer(fake).call(.stop)

        let paths = await fake.paths
        XCTAssertEqual(paths, ["/stop"])
        let body = try await fake.body(0)
        XCTAssertNotNil(body["settle"] as? Double)
        XCTAssertTrue(reply.succeeded)
        XCTAssertEqual(reply.field("upright") as Bool?, true)
        XCTAssertEqual(reply.field("t") as Double?, 1.5)
        XCTAssertEqual(reply.field("policy") as String?, "alpha_walking")
        XCTAssertEqual(reply.field("vx") as Double?, 0.3)
    }

    /// `t` IS SIM SECONDS AND THE REPLY SAYS SO BESIDE IT. A screen printing
    /// them as elapsed real time would be wrong by a factor nobody controls.
    func testTheStateReplySaysWhichClockItsSecondsAreOn() async throws {
        let reply = try await peer(walkingBench()).call(.stop)
        XCTAssertEqual(reply.field("clock") as String?, "sim")
    }

    /// `hello` and `/health` ask the same question — who is on the other end —
    /// and a bench's honest answer is which software, which world, at what
    /// rate, holding how many policies.
    func testHelloAsksHealthAndAnswersWithWhatABenchCanHonestlySayAboutItself() async throws {
        let fake = walkingBench()
        let reply = try await peer(fake).call(.hello)

        let paths = await fake.paths
        XCTAssertEqual(paths, ["/health"])
        XCTAssertTrue(reply.succeeded)
        XCTAssertEqual(reply.field("bench") as String?, "duck-bench")
        XCTAssertEqual(reply.field("policies") as Int?, 2)
        XCTAssertEqual(reply.field("plantName") as String?, "duck.xml")
        XCTAssertEqual(reply.field("tickHz") as Double?, DuckModel.tickHz)
    }

    /// THE ABSENCE IS THE ASSERTION. `api_version` is `duck-ipc-proto`'s, and a
    /// bench has never heard of it; a fabricated 16 here would make
    /// `DuckLink.verdict(for:)` say "the same one this app was written against"
    /// about a program that implements none of the protocol.
    func testTheHelloAnswerInventsNoAPIVersion() async throws {
        let reply = try await peer(walkingBench()).call(.hello)
        XCTAssertNil(reply.field("api_version") as Int?)
        XCTAssertNil(reply.field("api_version") as String?)
    }

    /// The bench has no state endpoint, and the reason it has none is the
    /// reason this cannot invent one: every endpoint it does have advances
    /// physics in order to answer. So state is read from the last answer and
    /// posts nothing at all.
    func testStateIsReadFromTheLastAnswerAndPostsNothing() async throws {
        let fake = walkingBench()
        let peer = try peer(fake)
        try await peer.notify(.move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)))
        let afterTheMove = await fake.count
        XCTAssertEqual(afterTheMove, 1)

        let reply = try await peer.call(.state)
        let afterTheRead = await fake.count
        XCTAssertEqual(afterTheRead, 1, "A state read advanced the world it was reporting on.")
        XCTAssertTrue(reply.succeeded)
        XCTAssertEqual(reply.field("vx") as Double?, 0.3)
        XCTAssertEqual(reply.field("height") as Double?, 0.116)
    }

    /// And before anything has been commanded there is nothing to report — said
    /// in a sentence rather than answered with zeroes, which would be a duck
    /// standing at the origin that nobody has ever seen.
    func testStateBeforeAnyCommandRefusesRatherThanAdvancingTheWorld() async {
        let fake = walkingBench()
        do {
            _ = try await peer(fake).call(.state)
            XCTFail("A bench reported state it had never been given")
        } catch {
            XCTAssertEqual(error as? BenchPeer.Refusal, .nothingHasHappenedYet)
            XCTAssertTrue(BenchPeer.Refusal.nothingHasHappenedYet.message
                            .contains("only advances inside a request"))
        }
        let posted = await fake.count
        XCTAssertEqual(posted, 0)
    }

    /// The whole state block is kept, not only the scalars the reply carries —
    /// a view drawing the duck needs every joint angle, and the mouth among
    /// them is one no network drives.
    func testItKeepsTheWholeStanceAndNotJustTheNumbersInTheReply() async throws {
        let peer = try peer(walkingBench())
        try await peer.notify(.move(.still))
        // Pulled out of the actor before the assertion, because `XCTUnwrap`
        // takes an autoclosure and an autoclosure cannot carry an `await`.
        let kept = await peer.live
        let live = try XCTUnwrap(kept)
        XCTAssertEqual(live.stance.jointAngles.count, DuckModel.jointNames.count)
        XCTAssertEqual(live.stance.jointAngles[DuckModel.mouthIndex],
                       DuckModel.homePose[DuckModel.mouthIndex])
        XCTAssertEqual(live.policy, "alpha_walking")
        XCTAssertTrue(live.upright)
    }

    // MARK: - the five it cannot

    /// THE REFUSAL THIS FILE EXISTS FOR. `/intent` takes a velocity twist and
    /// nothing else, so a head pose has no door to go in by — and the message
    /// has to say that rather than repeat the routing table's "the link does not
    /// carry it", which tells a person nothing about what is missing.
    func testAHeadPoseIsRefusedWithTheReasonRatherThanTheGenericDenial() async throws {
        let fake = walkingBench()
        let peer = try peer(fake)
        for call in [DuckCall.head(.level), .look(.level)] {
            do {
                if call.isNotification { try await peer.notify(call) }
                else { _ = try await peer.call(call) }
                XCTFail("A bench posed a head: \(call.method.rawValue)")
            } catch {
                XCTAssertEqual(error as? BenchPeer.Refusal,
                               .noPlaceToPutAHeadPose(call.method))
                let said = BenchPeer.Refusal.noPlaceToPutAHeadPose(call.method).message
                XCTAssertTrue(said.contains("vx, vy, vyaw"), said)
                XCTAssertNotEqual(said, DuckCall.Misuse.outOfReach(call.method, .bench).message,
                                  "The whole point is that this says more than the table does.")
            }
        }
        let posted = await fake.count
        XCTAssertEqual(posted, 0)
    }

    /// A simulator has no motors, so there is nothing to power and nothing with
    /// power to cut. Answering "enabled" would teach a habit that means
    /// something on hardware and nothing here.
    func testEnableAndRelaxAreRefusedBecauseThereIsNoMotorBus() async throws {
        let fake = walkingBench()
        let peer = try peer(fake)
        for call in [DuckCall.enable, .relax] {
            do {
                _ = try await peer.call(call)
                XCTFail("A bench answered \(call.method.rawValue)")
            } catch {
                XCTAssertEqual(error as? BenchPeer.Refusal, .noMotorBus(call.method))
                XCTAssertTrue(BenchPeer.Refusal.noMotorBus(call.method).message
                                .contains("motor bus"))
            }
        }
        let posted = await fake.count
        XCTAssertEqual(posted, 0)
    }

    /// `/reset` teleports the duck upright and starts the world again, which is
    /// not what `robot.init` does. Mapping one onto the other would report a
    /// pose where there had been a fall — the bench's own objection to reset as
    /// a way of stopping.
    func testInitIsRefusedRatherThanQuietlyBecomingAReset() async {
        let fake = walkingBench()
        do {
            _ = try await peer(fake).call(.initPose)
            XCTFail("robot.init became something else")
        } catch {
            XCTAssertEqual(error as? BenchPeer.Refusal, .resetIsNotTheInitialPose)
            let said = BenchPeer.Refusal.resetIsNotTheInitialPose.message
            XCTAssertTrue(said.contains("/reset"), said)
            XCTAssertTrue(said.contains("hiding the fall"), said)
        }
        // The point is not only that it threw: nothing was posted at all, least
        // of all to `/reset`.
        let posted = await fake.count
        XCTAssertEqual(posted, 0)
    }

    /// Said once in general, so that the day a method joins the bench column —
    /// or leaves it — the two halves cannot disagree: everything the table
    /// denies owes a sentence of its own, and everything it carries owes none.
    func testEveryCallTheBenchDoesNotCarryHasItsOwnSentenceAndEveryOneItDoesHasNone() throws {
        let carried = DuckMethod.reach(for: .bench)
        var sentences: [String] = []
        for call in DuckCall.allShapes {
            let refusal = BenchPeer.refusal(for: call)
            guard !carried.contains(call.method) else {
                XCTAssertNil(refusal, "\(call.method.rawValue) is carried and was refused anyway")
                continue
            }
            let said = try XCTUnwrap(refusal?.message,
                                     "\(call.method.rawValue) was denied with no reason given")
            XCTAssertTrue(said.contains(call.method.rawValue),
                          "\(call.method.rawValue) is not named in its own refusal")
            XCTAssertNotEqual(said, DuckCall.Misuse.outOfReach(call.method, .bench).message)
            sentences.append(said)
        }
        XCTAssertEqual(sentences.count, 5,
                       "The bench carries four of the nine calls; the other five each owe an "
                       + "explanation.")
    }

    // MARK: - the checks it inherits

    /// The direction half of the contract is `DuckPeer.vet`'s single copy,
    /// inherited rather than re-implemented here — which is the arrangement
    /// that stops the fourth transport from forgetting it.
    func testTheDirectionCheckIsStillTheProtocolsAndStillRuns() async throws {
        let fake = walkingBench()
        let peer = try peer(fake)
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
        let posted = await fake.count
        XCTAssertEqual(posted, 0)
    }

    /// A NaN is stopped before it reaches `JSONSerialization`, which on Darwin
    /// RAISES rather than throwing — so an unchecked twist is a crash in
    /// somebody's hand, not an error they can read. The check is the one in
    /// `DuckCall.line`, run by building a line this transport then discards.
    func testANonFiniteTwistIsStoppedBeforeItReachesTheSerialiser() async {
        let fake = walkingBench()
        do {
            try await peer(fake).notify(.move(DuckDrive.Twist(vx: .nan, vy: 0, vyaw: 0)))
            XCTFail("A NaN was posted to a bench")
        } catch {
            XCTAssertEqual(error as? DuckCall.Misuse, .notANumber(.move))
        }
        let posted = await fake.count
        XCTAssertEqual(posted, 0)
    }

    // MARK: - the check that is this peer's own

    /// THE HOLD IS THE OTHER NUMBER THAT REACHES THE SERIALISER, AND THE LINE
    /// CHECK DOES NOT SEE IT. `DuckCall.line` validates the twist, because
    /// `robot.move` is vx, vy and vyaw; the hold is duckbench's own field on
    /// `POST /intent` and appears in no line at all. So it is checked at the
    /// only door it comes in by — the initialiser — and a peer that cannot be
    /// driven is never built.
    func testAHoldThatIsNotANumberIsRefusedWhenThePeerIsBuilt() async {
        let fake = walkingBench()
        do {
            _ = try BenchPeer(address: Self.there, hold: .nan) { call in
                try await fake.take(call)
            }
            XCTFail("A peer was built with a hold that would crash the first time it moved")
        } catch {
            XCTAssertEqual(error as? BenchPeer.Misuse, .holdIsNotANumber)
        }
        let posted = await fake.count
        XCTAssertEqual(posted, 0, "Building a peer talked to a bench.")
    }

    /// The refusal has to name what actually happens, because "invalid hold" is
    /// the sentence that sends somebody looking for a range check that would
    /// have caught it.
    func testTheHoldRefusalNamesTheClampThatDoesNotCatchItAndTheCrashThatFollows() {
        let said = BenchPeer.Misuse.holdIsNotANumber.message
        XCTAssertTrue(said.contains("min(max(hold, 0.02), 2)"), said)
        XCTAssertTrue(said.contains("raises rather than throws"), said)
    }

    /// WHY THE GUARD EXISTS, PINNED AS ARITHMETIC. `DuckDrive.intent` clamps
    /// with `min(max(hold, 0.02), 2)` and the peer's own documentation used to
    /// say that clamp handled whatever arrived. It does not: both halves are
    /// NaN-transparent in Swift, because every comparison against a NaN is
    /// false, so a NaN goes in and a NaN comes out. Everything else really is
    /// handled, infinities included, which is why the guard refuses a NaN and
    /// nothing else.
    ///
    /// ASSERTED AGAINST `DuckDrive.intent` ITSELF, WHICH IT COULD NOT BE.
    ///
    /// This test used to define `min(max(hold, 0.02), 2)` in its own body and
    /// assert on that copy — so it could not observe the real function and
    /// would have passed unchanged if `DuckDrive.intent` were deleted. The
    /// reason was real: handing a NaN to the real thing reached
    /// `JSONSerialization`, which raises on Darwin, and a test that takes the
    /// process down does not fail, it disappears. The fix was to make the
    /// function refuse rather than to keep testing a replica of it.
    func testDuckDriveIntentRefusesANaNHoldAndClampsEverythingElse() throws {
        let address = DuckBench.Address(host: "127.0.0.1", port: 8770)
        XCTAssertThrowsError(try DuckDrive.intent(address, .still, hold: .nan)) {
            // NOT XCTAssertEqual: the payload IS a NaN, and NaN != NaN, so an
            // equality check on the case fails while looking correct.
            guard case .holdIsNotASecond(let held)? = $0 as? DuckDrive.Refusal else {
                return XCTFail("wrong refusal: \($0)")
            }
            XCTAssertTrue(held.isNaN)
        }

        // Everything else is bounded rather than refused — the bench is happy
        // to be told 1000 and clamp it, and a peer that threw at everything out
        // of range would be refusing what the bench itself accepts.
        func heldBy(_ hold: Double) throws -> Double {
            let call = try DuckDrive.intent(address, .still, hold: hold)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body!) as? [String: Any])
            return try XCTUnwrap(body["hold"] as? Double)
        }
        XCTAssertEqual(try heldBy(.infinity), 2)
        XCTAssertEqual(try heldBy(-.infinity), 0.02)
        XCTAssertEqual(try heldBy(1000), 2)
        XCTAssertEqual(try heldBy(-1000), 0.02)
        XCTAssertEqual(try heldBy(DuckDrive.holdSeconds), DuckDrive.holdSeconds)
    }

    /// And a hold that is only unreasonable is not refused: the clamp handles
    /// it, and a peer that threw at everything out of range would be refusing
    /// what the bench itself is happy to bound.
    func testAnOutOfRangeHoldIsBuiltAndClampedRatherThanRefused() async throws {
        let fake = walkingBench()
        try await peer(fake, hold: .infinity).notify(.move(.still))
        let body = try await fake.body(0)
        XCTAssertEqual(body["hold"] as? Double, 2)
    }

    // MARK: - when the bench says no

    /// A BENCH THAT REFUSES HAS ANSWERED. Carrying it back as a failure rather
    /// than throwing is what keeps "unknown policy" from looking like a network
    /// fault, which is the distinction `DuckReply` exists for.
    func testABenchRefusalOnAStopIsCarriedBackAsAnAnswer() async throws {
        let fake = FakeBench { _ in
            try JSONSerialization.data(withJSONObject: ["error": "unknown policy: nope"])
        }
        let reply = try await peer(fake).call(.stop)
        XCTAssertFalse(reply.succeeded)
        XCTAssertNil(reply.result)
        XCTAssertEqual(reply.failure?.message, "unknown policy: nope")
        XCTAssertEqual(reply.failure?.code, 0,
                       "The bench sends no code, and 0 is already what DuckReply.decode records "
                       + "for a refusal that omitted one.")
        XCTAssertEqual(reply.failure?.says, "The duck refused: unknown policy: nope (0)")
    }

    /// A notification has nowhere to put an answer, so this is the one place a
    /// refusal becomes a thrown error — in `DuckBench.ReadError`'s own words,
    /// which are the words the drive screen already prints.
    func testABenchRefusalOnAnIntentIsThrownBecauseANotificationCannotCarryIt() async {
        let fake = FakeBench { _ in
            try JSONSerialization.data(withJSONObject: ["error": "no policy loaded"])
        }
        do {
            try await peer(fake).notify(.move(.still))
            XCTFail("A refused intent was dropped on the floor")
        } catch {
            XCTAssertEqual(error as? DuckBench.ReadError, .bench("no policy loaded"))
        }
    }

    /// Something that is not a bench answering gets the reader's own sentence
    /// rather than a second wording of it invented here.
    func testSomethingThatIsNotABenchGetsTheReadersOwnSentence() async throws {
        let peer = try peer(FakeBench { _ in Data("<html>404</html>".utf8) })
        do {
            _ = try await peer.call(.hello)
            XCTFail("A web page said hello")
        } catch {
            XCTAssertEqual(error as? DuckBench.ReadError, .notJSON)
        }
        do {
            try await peer.notify(.move(.still))
            XCTFail("A web page ran physics")
        } catch {
            XCTAssertEqual(error as? DuckBench.ReadError, .notJSON)
        }
    }

    // MARK: - who it says it is

    /// THE KIND IS NOT A PARAMETER. Every other peer could be pointed at either
    /// a robot or a simulator; this one cannot, and a constructor that took
    /// `.real` would let one line of app code tell somebody they were driving a
    /// robot when they were driving MuJoCo.
    func testItsKindIsSimulatedAndNobodyGetsToSayOtherwise() throws {
        let peer = try peer(walkingBench())
        XCTAssertEqual(peer.identity.kind, .sim)
        XCTAssertTrue(peer.identity.says.contains("simulated"))
        XCTAssertEqual(peer.identity.name, "192.168.1.20",
                       "/health answers what software is running — the same word for every bench "
                       + "on the desk — so the host is the name until somebody types a better one.")
        XCTAssertEqual(peer.address, Self.there)
    }

    func testANameSomebodyTypedWinsOverTheHost() throws {
        let peer = try peer(walkingBench(), name: "the Pi under the telly")
        XCTAssertEqual(peer.identity.name, "the Pi under the telly")
        XCTAssertEqual(peer.identity.kind, .sim)
    }

    /// The ids are this peer's own — HTTP pairs a request with its answer by the
    /// socket and carries no JSON-RPC id at all — so what is asserted here is
    /// that a caller logging them sees a sequence rather than a column of nils,
    /// and that a notification, which is never answered, consumes none.
    func testTheIdsAreOursAndTheyCountUp() async throws {
        let peer = try peer(walkingBench())
        let first = try await peer.call(.stop)
        try await peer.notify(.move(.still))
        let second = try await peer.call(.stop)
        XCTAssertEqual(first.id, 1)
        XCTAssertEqual(second.id, 2)
    }

    // MARK: - the sentence that has to be said out loud

    /// THE ONE SAFETY PROPERTY THAT DOES NOT SURVIVE THE MOVE TO HARDWARE, and
    /// it is written down in the package rather than in a view because it is a
    /// claim about what a robot does. The bench freezes between requests; a real
    /// `robot.move` expires on an age-based deadman instead. Somebody who learns
    /// "letting go stops it" here has learned a fact about a simulator.
    func testTheFrozenWorldIsSaidOutLoudAndNamesWhatHardwareDoesInstead() {
        let said = BenchPeer.theWorldOnlyMovesWhenAsked
        XCTAssertTrue(said.contains("frozen mid-stride"), said)
        XCTAssertTrue(said.contains("deadman"), said)
        XCTAssertTrue(said.contains("expires"), said)
    }

    /// IT IS SAID TWICE TODAY, AND THIS IS THE THING THAT STOPS THE TWO COPIES
    /// FROM DRIFTING. The third paragraph of `DuckDrive.thisIsNotARobot` makes
    /// the same claim in its own words, `DriveView` prints that string, and
    /// either can be edited without the other — so an edit that softened one
    /// copy would leave a screen telling somebody the freeze is what stops a
    /// robot while the other copy still said it is not.
    ///
    /// A RED HERE IS A HANDOFF, NOT A NUISANCE. `BenchPeer` records what is
    /// owed in `DuckDrive.swift`: lift that paragraph into a constant of its
    /// own, in this file's stronger wording, and compose it back into
    /// `thisIsNotARobot` so the screen keeps printing it. Done that way this
    /// test stays green. If instead the paragraph is simply deleted, this test
    /// fails — and that failure is the reminder that `DriveView` now has to
    /// print `BenchPeer.theWorldOnlyMovesWhenAsked` itself, after which this
    /// test can go.
    func testBothPlacesThatMakeTheDeadmanClaimStillMakeTheSameOne() {
        for said in [BenchPeer.theWorldOnlyMovesWhenAsked, DuckDrive.thisIsNotARobot] {
            XCTAssertTrue(said.contains("mid-stride"),
                          "This copy no longer says what letting go does here: \(said)")
            XCTAssertTrue(said.contains("expires"),
                          "This copy no longer says a real move expires: \(said)")
            XCTAssertTrue(said.contains("deadman"),
                          "This copy no longer names the deadman: \(said)")
        }
    }
}
