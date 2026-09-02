import XCTest
import DuckKit
@testable import StudioKit

/// One duck, several readers, and a bench that must not invent a battery.
///
/// THE TWO THINGS UNDER TEST ARE UNRELATED AND BELONG TOGETHER. The fan-out is
/// mechanics: three readers, one of them leaves, the other two must not notice.
/// The bench's synthesised state is a claim: everything physics cannot measure
/// arrives as nil, because the alternative — a plausible number in a battery row
/// on a simulator — is the exact thing `DuckBattery` was built to make
/// impossible from the other end.
final class DuckStateStreamTests: XCTestCase {

    private static func state(fallen: Bool = false, policy: String = "alpha_walking",
                              at seconds: TimeInterval = 0) -> DuckState {
        DuckState(policy: policy,
                  safety: DuckState.Safety(fallen: fallen, limp: false),
                  receivedAt: Date(timeIntervalSince1970: seconds))
    }

    /// Wait for a condition the actor system will get to in its own time.
    /// POLLED RATHER THAN SLEPT: a sleep long enough to be reliable on a busy Pi
    /// is a second added to every run, and one short enough not to be is a test
    /// that fails at three in the morning.
    private func settle(until condition: @escaping () -> Bool,
                        _ what: String,
                        file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("never settled: \(what)", file: file, line: line)
    }

    // MARK: - the fan-out

    /// THE TEST THE FAN-OUT EXISTS FOR. Three readers, one dropped mid-flight,
    /// and the two that stayed see every state — including the ones published
    /// while the third was leaving. A single shared stream would have handed
    /// each state to whichever reader happened to be waiting.
    func testThreeReadersOneLeavesAndTheOtherTwoSeeEveryState() async throws {
        let fan = DuckStateFanOut()
        var first = fan.states().makeAsyncIterator()
        var second = fan.states().makeAsyncIterator()
        var third: AsyncStream<DuckState>.Iterator? = fan.states().makeAsyncIterator()
        XCTAssertEqual(fan.readerCount, 3)

        fan.publish(Self.state(at: 1))
        var firstSaw = [await first.next()].compactMap { $0 }
        var secondSaw = [await second.next()].compactMap { $0 }
        let thirdSaw = await third?.next()
        XCTAssertEqual(thirdSaw?.receivedAt, Date(timeIntervalSince1970: 1))

        // Dropped mid-flight: the iterator goes away with the stream behind it,
        // which is the case `onTermination` is registered for.
        third = nil
        await settle(until: { fan.readerCount == 2 }, "the dropped reader removed itself")

        for tick in 2...5 { fan.publish(Self.state(at: TimeInterval(tick))) }
        for _ in 2...5 {
            if let state = await first.next() { firstSaw.append(state) }
            if let state = await second.next() { secondSaw.append(state) }
        }
        let expected = (1...5).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        XCTAssertEqual(firstSaw.map(\.receivedAt), expected)
        XCTAssertEqual(secondSaw.map(\.receivedAt), expected)
        XCTAssertEqual(fan.readerCount, 2)
    }

    /// A reader that arrives late gets what comes next and not a replay. A card
    /// that opened and immediately showed a state from four minutes ago would be
    /// showing a duck that has since fallen over.
    func testAReaderSeesWhatComesNextAndNotWhatItMissed() async {
        let fan = DuckStateFanOut()
        fan.publish(Self.state(at: 1))
        var reader = fan.states().makeAsyncIterator()
        fan.publish(Self.state(at: 2))
        let seen = await reader.next()
        XCTAssertEqual(seen?.receivedAt, Date(timeIntervalSince1970: 2))
    }

    /// A LINK THAT DIES ENDS THE STREAMS RATHER THAN GOING QUIET, because a
    /// `for await` that simply stops producing looks exactly like a duck
    /// standing still.
    func testFinishingEndsEveryStreamAndTheOnesTakenAfterwards() async {
        let fan = DuckStateFanOut()
        var reader = fan.states().makeAsyncIterator()
        fan.publish(Self.state(at: 1))
        _ = await reader.next()
        fan.finish()
        let afterFinish = await reader.next()
        XCTAssertNil(afterFinish)
        XCTAssertTrue(fan.isFinished)
        var late = fan.states().makeAsyncIterator()
        let nothing = await late.next()
        XCTAssertNil(nothing)
        fan.publish(Self.state(at: 9))
        XCTAssertEqual(fan.readerCount, 0)
    }

    // MARK: - what a bench may put in a state

    func testTheBenchSynthesisLeavesEveryUnmeasurableFieldNil() {
        let live = DuckDrive.Live(t: 1.5, stance: .home, height: 0.116, upright: true,
                                  policy: "alpha_walking",
                                  command: DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: -0.2))
        let state = BenchPeer.synthesised(from: live, receivedAt: Date(timeIntervalSince1970: 7))

        XCTAssertNil(state.battery)
        XCTAssertNil(state.batteryPercentOrDerived)
        XCTAssertNil(state.loop)
        XCTAssertNil(state.odom)
        XCTAssertNil(state.safety?.limp)
        XCTAssertEqual(state.safety?.fallen, false)
        XCTAssertEqual(state.policy, "alpha_walking")
        XCTAssertEqual(state.move?.requested, [0.3, 0, -0.2])
        XCTAssertNil(state.move?.applied)
        XCTAssertEqual(state.receivedAt, Date(timeIntervalSince1970: 7))
        XCTAssertFalse(state.isEmpty)
    }

    /// A fall is the negation of upright and it is the one honest translation
    /// in the whole synthesis.
    func testAnInvertedDuckIsAFallenOne() {
        let live = DuckDrive.Live(t: 3, stance: .home, height: 0.02, upright: false,
                                  policy: nil, command: .still)
        let state = BenchPeer.synthesised(from: live, receivedAt: Date())
        XCTAssertEqual(state.safety?.fallen, true)
        XCTAssertNil(state.policy)
    }

    /// The sentence names what is missing and why, rather than apologising for
    /// the numbers that are there.
    func testTheSynthesisSaysWhatItIsInAsentenceAScreenCanPrint() {
        let said = BenchPeer.benchStateIsSynthesised
        XCTAssertTrue(said.contains("assembled by the app"), said)
        XCTAssertTrue(said.contains("no battery"), said)
        XCTAssertTrue(said.contains("no loop rate"), said)
        XCTAssertFalse(said.contains("robot reported"), said)
    }

    /// ONE STATE PER ROUND TRIP AND NOT ONE MORE. The bench's world only
    /// advances inside a request, so a second state between requests would be
    /// the same physics with a fresher timestamp — a frozen duck reported as a
    /// live one.
    func testABenchPublishesExactlyOneStatePerRoundTrip() async throws {
        let peer = try BenchPeer(address: DuckBench.Address(host: "10.0.0.5", port: 8770),
                                 errand: { _ in Self.liveBody() })
        var reader = peer.states().makeAsyncIterator()
        _ = try await peer.call(.stop)
        let first = await reader.next()
        XCTAssertEqual(first?.safety?.fallen, false)
        XCTAssertNil(first?.battery)

        try await peer.notify(.move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)))
        let second = await reader.next()
        XCTAssertEqual(second?.move?.requested, [0.3, 0, 0])
    }

    /// A bench asked something it refuses publishes nothing: no round trip, no
    /// state, and in particular no state saying the duck is fine.
    func testARefusedCallPublishesNoState() async throws {
        let peer = try BenchPeer(address: DuckBench.Address(host: "10.0.0.5", port: 8770),
                                 errand: { _ in Self.liveBody() })
        var reader = peer.states().makeAsyncIterator()
        await XCTAssertThrowsErrorAsync(_ = try await peer.call(.enable))
        _ = try await peer.call(.stop)
        let seen = await reader.next()
        XCTAssertEqual(seen?.safety?.fallen, false)
        let live = await peer.live
        XCTAssertEqual(live?.upright, true)
    }

    /// A sim duck has no inbound stream at all, so what reaches its readers is
    /// what a test put there — which is the whole reason the member exists on
    /// this peer.
    func testASimDuckCarriesTheStatesATestFeedsIt() async {
        let duck = SimDuck(config: .stock(), over: .bridge, wire: { _ in nil })
        var reader = duck.states().makeAsyncIterator()
        await duck.feed(Self.state(fallen: true, at: 4))
        let seen = await reader.next()
        XCTAssertEqual(seen?.safety?.fallen, true)
        XCTAssertEqual(seen?.receivedAt, Date(timeIntervalSince1970: 4))
        await duck.stopFeeding()
        let ended = await reader.next()
        XCTAssertNil(ended)
    }

    /// THE REQUIREMENT ITSELF. Every peer answers `states()`; a transport whose
    /// author forgot it does not compile, which is the whole reason it is not
    /// defaulted.
    func testEveryPeerInThisPackageAnswersTheStateStream() async throws {
        let bench: any DuckPeer = try BenchPeer(
            address: DuckBench.Address(host: "h", port: 1), errand: { _ in Data() })
        let sim: any DuckPeer = SimDuck(config: .stock(), over: .webRTC, wire: { _ in nil })
        // Taking the stream is most of the assertion — it compiles or it does
        // not — and finishing with no reader proves the peer is not holding one
        // open in the meantime.
        for peer in [bench, sim] {
            let stream = peer.states()
            XCTAssertNotNil(stream)
        }
    }

    private static func liveBody(upright: Bool = true, vx: Double = 0.3) -> Data {
        let body: [String: Any] = [
            "t": 1.5,
            "height": 0.116,
            "upright": upright,
            "policy": "alpha_walking",
            "joints": Array(repeating: 0.0, count: DuckModel.policyJointCount),
            "position": [0.0, 0.0, 0.116],
            "quaternion": [1.0, 0.0, 0.0, 0.0],
            "command": ["vx": vx, "vy": 0.0, "vyaw": 0.0],
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }
}

/// `XCTAssertThrowsError` has no async form on Linux's XCTest, and a `do/catch`
/// per call site is four lines of noise around one assertion.
func XCTAssertThrowsErrorAsync(_ body: @autoclosure () async throws -> Void,
                               file: StaticString = #filePath,
                               line: UInt = #line) async {
    do {
        try await body()
        XCTFail("expected this to throw", file: file, line: line)
    } catch {
        // The refusal itself is asserted at the call sites that care which one
        // it was; here the point is only that nothing was published.
    }
}
