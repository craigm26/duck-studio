import XCTest
import DuckKit
@testable import StudioKit

/// A peer over a stream of lines, driven first by a hand-written far end and
/// then by a real process.
///
/// TWO HALVES ON PURPOSE. The hand-written half can produce the situations that
/// matter and never happen on demand — an answer arriving before its caller is
/// waiting, a send slot superseded mid-write, a response to an id nobody minted.
/// The `fake_mediad` half cannot produce any of those deliberately, and is the
/// only part of this file where the bytes travel through a pipe, get chunked by
/// an OS, and arrive interleaved with telemetry nobody asked for. Neither half
/// is worth much without the other: the first proves the logic, the second
/// proves the logic was about the right problem.
final class LinePeerTests: XCTestCase {

    // MARK: - a far end made of closures

    /// Everything written to the link, in order.
    private actor Written {
        private(set) var frames: [DuckLineSequence.Stamped] = []
        func add(_ frame: DuckLineSequence.Stamped) { frames.append(frame) }
        var count: Int { frames.count }
        var lines: [String] { frames.map { String(decoding: $0.line, as: UTF8.self) } }
        var numbers: [UInt64] { frames.map(\.number) }
    }

    /// Holds every write until it is opened. A slow transport, on demand.
    private actor Gate {
        private var open = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if open { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func release() {
            open = true
            let parked = waiting
            waiting.removeAll()
            for continuation in parked { continuation.resume() }
        }
    }

    private struct FarEnd {
        let peer: LinePeer
        let written: Written
        let send: @Sendable (String) -> Void
        let stop: @Sendable () -> Void
    }

    private func makeLink(_ transport: DuckLineTransport = .bridge,
                      wire: (@Sendable (DuckLineSequence.Stamped) async throws -> Void)? = nil)
        -> FarEnd {
        let written = Written()
        var carry: AsyncStream<Data>.Continuation!
        let inbound = AsyncStream<Data> { carry = $0 }
        let continuation = carry!
        let peer = LinePeer(identity: DuckIdentity(name: "fake", kind: .sim),
                            over: transport,
                            inbound: inbound) { frame in
            await written.add(frame)
            try await wire?(frame)
        }
        return FarEnd(peer: peer, written: written,
                      send: { continuation.yield(Data($0.utf8)) },
                      stop: { continuation.finish() })
    }

    private func settle(until condition: @escaping () async -> Bool,
                        _ what: String,
                        file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<4000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("never settled: \(what)", file: file, line: line)
    }


    // MARK: - assertions that can be awaited
    //
    // `XCTAssertEqual` and its family take autoclosures, and an autoclosure
    // cannot contain an `await` — so every assertion about an actor's own
    // bookkeeping has to be made through a plain function whose arguments are
    // evaluated at the call site. These are those functions and nothing more.

    private func same<T: Equatable>(_ value: T, _ expected: T, _ what: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, expected, what, file: file, line: line)
    }

    private func greater<T: Comparable>(_ value: T, _ floor: T, _ what: String = "",
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(value, floor, what, file: file, line: line)
    }

    private func isNil<T>(_ value: T?, _ what: String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(value, what, file: file, line: line)
    }

    // MARK: - correlation

    /// The ordinary case: ask, and the answer with the matching id comes back.
    func testACallIsAnsweredByTheLineCarryingItsID() async throws {
        let link = makeLink()
        let reading = Task { await link.peer.read() }
        async let answer = link.peer.call(.hello)
        await settle(until: { await link.written.count == 1 }, "the hello reached the wire")
        link.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"api_version\":16}}\n")
        let reply = try await answer
        XCTAssertTrue(reply.succeeded)
        XCTAssertEqual(reply.field("api_version"), 16)
        same(await link.peer.inFlight, 0)
        link.stop()
        await reading.value
    }

    /// A REFUSAL IS AN ANSWER. The duck said no, which is a different fact from
    /// the link breaking, and `DuckReply` carries it rather than throwing it.
    func testARefusalComesBackAsAnAnswerRatherThanAThrow() async throws {
        let link = makeLink()
        let reading = Task { await link.peer.read() }
        async let answer = link.peer.call(.stop)
        await settle(until: { await link.written.count == 1 }, "the stop reached the wire")
        link.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,"
                + "\"message\":\"no such method\"}}\n")
        let reply = try await answer
        XCTAssertFalse(reply.succeeded)
        XCTAssertEqual(reply.failure?.code, -32601)
        XCTAssertTrue(reply.failure?.says.contains("The duck refused") ?? false)
        link.stop()
        await reading.value
    }

    /// A response nobody asked for is counted, not delivered. A late answer
    /// from a previous connection looks exactly like this, which is why
    /// `DuckRPC.Correlator` never reuses an id.
    func testAnAnswerToAnIDNobodyMintedIsCountedAndDropped() async throws {
        let link = makeLink()
        let reading = Task { await link.peer.read() }
        link.send("{\"jsonrpc\":\"2.0\",\"id\":99,\"result\":{}}\n")
        await settle(until: { await link.peer.traffic.unmatchedResponses == 1 },
                     "the stray answer was counted")
        link.stop()
        await reading.value
    }

    // MARK: - telemetry

    /// A `robot.state` notification reaches every reader, and reaches them as a
    /// state rather than as an unreadable answer.
    func testAStateNotificationReachesEveryReader() async throws {
        let link = makeLink()
        var first = link.peer.states().makeAsyncIterator()
        var second = link.peer.states().makeAsyncIterator()
        let reading = Task { await link.peer.read() }
        link.send("{\"jsonrpc\":\"2.0\",\"method\":\"robot.state\",\"params\":"
                + "{\"safety\":{\"fallen\":true},\"policy\":\"alpha_walking\"}}\n")
        let a = await first.next()
        let b = await second.next()
        XCTAssertEqual(a?.safety?.fallen, true)
        XCTAssertEqual(b?.policy, "alpha_walking")
        XCTAssertNil(a?.battery)
        same(await link.peer.traffic.statesPublished, 1)
        link.stop()
        await reading.value
    }

    /// A NOTIFICATION THAT IS NOT A STATE IS NOT A FAILURE. Update progress
    /// arrives this way on Bluetooth, and a peer that reported it as an
    /// unreadable answer would fabricate a refusal out of the robot doing
    /// exactly what the protocol allows.
    func testANotificationThatIsNotAStateIsCountedSeparately() async throws {
        let link = makeLink()
        let reading = Task { await link.peer.read() }
        link.send("{\"jsonrpc\":\"2.0\",\"method\":\"update.progress\","
                + "\"params\":{\"percent\":40}}\n")
        await settle(until: { await link.peer.traffic.otherNotifications == 1 },
                     "the progress notification was counted")
        same(await link.peer.traffic.statesPublished, 0)
        same(await link.peer.traffic.unmatchedResponses, 0)
        link.stop()
        await reading.value
    }

    /// THE RULE IS ONE RULE, HELD IN TWO PLACES, AND THIS PINS THEM TOGETHER.
    /// `DuckRPC.Message.isNotification` and `DuckLink.notificationMethod(fromLine:)`
    /// both say "a method with no id"; they are used on different transports and
    /// could drift apart, so the same bytes are put through both.
    func testTheNotificationRuleIsTheSameOneDuckLinkApplies() {
        let lines = [
            "{\"jsonrpc\":\"2.0\",\"method\":\"robot.state\",\"params\":{}}",
            "{\"jsonrpc\":\"2.0\",\"method\":\"update.progress\"}",
            "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"hello\"}",
            "{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{}}",
        ]
        for line in lines {
            var decoder = DuckRPC.StreamDecoder()
            let messages = decoder.append(Data((line + "\n").utf8))
            XCTAssertEqual(messages.count, 1, line)
            let byRPC = messages[0].isNotification
            let byLink = DuckLink.notificationMethod(fromLine: Data(line.utf8)) != nil
            XCTAssertEqual(byRPC, byLink, line)
            if byRPC {
                XCTAssertEqual(messages[0].method,
                               DuckLink.notificationMethod(fromLine: Data(line.utf8)))
            }
        }
    }

    /// The framing is the decoder's, and this is the case that breaks a client
    /// that assumes one read is one message: two states in one chunk, and a
    /// third split across two.
    func testLinesAreReassembledAcrossChunks() async throws {
        let link = makeLink()
        var reader = link.peer.states().makeAsyncIterator()
        let reading = Task { await link.peer.read() }
        let state = "{\"jsonrpc\":\"2.0\",\"method\":\"robot.state\",\"params\":"
                  + "{\"safety\":{\"fallen\":false}}}\n"
        link.send(state + state + String(state.prefix(20)))
        _ = await reader.next()
        _ = await reader.next()
        same(await link.peer.traffic.statesPublished, 2)
        greater(await link.peer.pendingBytes, 0)
        link.send(String(state.dropFirst(20)))
        _ = await reader.next()
        same(await link.peer.traffic.statesPublished, 3)
        same(await link.peer.pendingBytes, 0)
        link.stop()
        await reading.value
    }

    // MARK: - the send slot

    /// THE DEPTH-1 QUEUE, WATCHED SUPERSEDING SOMETHING. Three twists into a
    /// transport that is slower than the caller: the first goes out, the second
    /// is replaced by the third, and only the newest survives — which is what
    /// last-writer-wins means when the loop is faster than the link.
    func testASecondTwistIsSupersededByAThirdRatherThanQueuedBehindIt() async throws {
        let gate = Gate()
        let link = makeLink(wire: { _ in await gate.wait() })
        let first = Task { try await link.peer.notify(.move(DuckDrive.Twist(vx: 0.1, vy: 0, vyaw: 0))) }
        await settle(until: { await link.written.count == 1 }, "the first twist is in the wire")

        try await link.peer.notify(.move(DuckDrive.Twist(vx: 0.2, vy: 0, vyaw: 0)))
        try await link.peer.notify(.move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)))
        same(await link.peer.traffic.supersededNotifications, 1)

        await gate.release()
        try await first.value
        await settle(until: { await link.written.count == 2 }, "the queued twist went out")

        let lines = await link.written.lines
        XCTAssertTrue(lines[0].contains("\"vx\":0.1"), lines[0])
        XCTAssertTrue(lines[1].contains("\"vx\":0.3"), lines[1])
        // The superseded frame took a number with it, so the numbers this end
        // sent have a hole in them — a hole this peer knows it made, which is
        // exactly what `supersededNotifications` is for.
        same(await link.written.numbers, [1, 3])
        link.stop()
    }

    /// Every frame is stamped, requests included, and the numbers only count up.
    func testEveryFrameIsStampedAndTheNumbersOnlyCountUp() async throws {
        let link = makeLink()
        let reading = Task { await link.peer.read() }
        try await link.peer.notify(.move(.still))
        async let answer = link.peer.call(.stop)
        await settle(until: { await link.written.count == 2 }, "both frames are out")
        link.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n")
        _ = try await answer
        same(await link.written.numbers, [1, 2])
        same(await link.peer.lastFrameNumber, 2)
        link.stop()
        await reading.value
    }

    // MARK: - reach, direction, and the end of a link

    /// The reach check is `DuckPeer.vet`'s single copy, inherited rather than
    /// re-implemented — so a bridge peer refuses the pairing PIN in the routing
    /// table's own words.
    func testAMethodThisLinkDoesNotCarryIsRefusedByName() async throws {
        let link = makeLink(.webRTC)
        do {
            _ = try await link.peer.call(.state)
            XCTFail("studio.state is not carried over WebRTC")
        } catch let misuse as DuckCall.Misuse {
            XCTAssertEqual(misuse, .outOfReach(.state, .webRTC))
        }
        same(await link.written.count, 0)
    }

    /// A caller may narrow what a peer claims to carry; it may not widen it.
    func testAWiderReachThanTheLinkCarriesIsIntersectedDownRatherThanTrusted() {
        var carry: AsyncStream<Data>.Continuation!
        let inbound = AsyncStream<Data> { carry = $0 }
        carry.finish()
        let peer = LinePeer(identity: DuckIdentity(name: "d", kind: .real),
                            over: .webRTC, inbound: inbound,
                            reach: Set(DuckMethod.allCases), wire: { _ in })
        XCTAssertEqual(peer.reach, DuckMethod.reach(for: .webRTC))
        XCTAssertFalse(peer.reach.contains(.setPairingPin))
    }

    /// EVERY PARKED CALLER FINDS OUT. A link that dies silently leaves a screen
    /// with buttons stuck on "sent…", which is worse than one that admits the
    /// socket died.
    func testTheEndOfTheInboundStreamResumesEverybodyAndEndsEveryReader() async throws {
        let gate = Gate()
        let link = makeLink(wire: { _ in await gate.wait() })
        var reader = link.peer.states().makeAsyncIterator()
        let reading = Task { await link.peer.read() }
        let asking = Task { try await link.peer.call(.hello) }
        await settle(until: { await link.written.count == 1 }, "the hello reached the wire")
        await gate.release()
        link.stop()
        await reading.value
        do {
            _ = try await asking.value
            XCTFail("a call parked on a dead link must not succeed")
        } catch let ended as LinePeer.LinkEnded {
            XCTAssertEqual(ended, .theFarEndStopped)
            XCTAssertTrue(ended.message.contains("sent…"), ended.message)
        }
        isNil(await reader.next())
    }

    // MARK: - SPIKE A: a real process on the other end

    /// `node`, wherever this machine keeps it, or nil.
    ///
    /// SEARCHED ON `PATH` RATHER THAN HARD-CODED, because node lives under nvm
    /// on the machine this package is developed on and in `/usr/bin` almost
    /// everywhere else, and a test that skipped on one of those would be a test
    /// that never ran.
    private static func node() -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("node")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// `duck-sounds/sim/fake_mediad.mjs`, beside this repository.
    private static func fakeDaemon() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // StudioKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StudioKit
            .deletingLastPathComponent()   // duck-studio
            .deletingLastPathComponent()   // projects
            .appendingPathComponent("duck-sounds/sim/fake_mediad.mjs")
            .path
    }

    /// THE SPIKE. A real process, a real pipe, real chunking, and telemetry
    /// arriving in the middle of a request — the three things a closure-shaped
    /// far end cannot honestly produce.
    ///
    /// WHAT IT DOES NOT PROVE. `fake_mediad` is not a robot and not a
    /// simulation of one: it runs no physics and its state is canned. If the
    /// real daemon's state block has different field names, this test passes and
    /// the app is still wrong — which is the one thing a fake can never tell
    /// you, and the reason the script's own preamble says so first.
    func testAProcessOnTheOtherEndAnswersWhileTelemetryIsArriving() async throws {
        guard let node = Self.node() else {
            throw XCTSkip("node is not on PATH, so the fake daemon cannot be run")
        }
        let script = Self.fakeDaemon()
        guard FileManager.default.fileExists(atPath: script) else {
            throw XCTSkip("duck-sounds is not checked out beside duck-studio: \(script)")
        }

        let child = Process()
        child.executableURL = node
        // A HUNDRED STATES A SECOND AND A HARD LIMIT OF FIVE, so the count is a
        // number this test can assert rather than a race with a wall clock. One
        // of the five is emitted immediately before the reply to the hello,
        // which is the case under test.
        child.arguments = [script, "--rate", "100", "--limit", "5", "--state-before-reply"]
        let toChild = Pipe()
        let fromChild = Pipe()
        child.standardInput = toChild
        child.standardOutput = fromChild

        var carry: AsyncStream<Data>.Continuation!
        let inbound = AsyncStream<Data> { carry = $0 }
        let continuation = carry!
        fromChild.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { continuation.finish() } else { continuation.yield(data) }
        }

        try child.run()
        let writing = toChild.fileHandleForWriting
        // THE TRANSPORT LABEL IS THE CLOSEST TRUE THING AND IT IS NOT TRUE. This
        // is a pipe, not WebRTC; what the label actually decides here is which
        // methods this peer will agree to send, and `mediad` is the thing that
        // would speak WebRTC if anybody knew how.
        let peer = LinePeer(identity: DuckIdentity(name: "fake-mediad", kind: .sim),
                            over: .webRTC, inbound: inbound) { frame in
            try writing.write(contentsOf: frame.line)
        }

        // Three readers, taken BEFORE anything is read off the pipe, which is
        // the ordering `DuckPeer.states()` is not `async` in order to allow.
        var first = peer.states().makeAsyncIterator()
        var second = peer.states().makeAsyncIterator()
        var third = peer.states().makeAsyncIterator()
        let reading = Task { await peer.read() }

        let reply = try await peer.call(.hello)
        XCTAssertTrue(reply.succeeded, "\(reply)")
        let version: Int? = reply.field("api_version")
        XCTAssertEqual(version, Int(DuckLink.apiVersion))
        XCTAssertEqual(reply.id, 1)
        // THE CORRELATOR WAS NOT CONFUSED. States arrived on the same stream
        // before the answer did; none of them was mistaken for one, and nothing
        // was left in flight.
        same(await peer.inFlight, 0)
        same(await peer.traffic.unmatchedResponses, 0)
        greater(await peer.traffic.statesPublished, 0)

        var seen: [[DuckState]] = [[], [], []]
        for _ in 0..<5 {
            if let state = await first.next() { seen[0].append(state) }
            if let state = await second.next() { seen[1].append(state) }
            if let state = await third.next() { seen[2].append(state) }
        }
        for (index, states) in seen.enumerated() {
            XCTAssertEqual(states.count, 5, "reader \(index) missed a state")
            for state in states {
                // The canned state: fallen, and carrying no battery block at
                // all. A nil here is the whole assertion — a client that filled
                // a missing battery with a zero would read as a flat duck.
                XCTAssertEqual(state.safety?.fallen, true)
                XCTAssertNil(state.battery)
                XCTAssertNil(state.batteryPercentOrDerived)
                XCTAssertEqual(state.policy, "alpha_walking")
                XCTAssertFalse(state.isEmpty)
            }
        }

        try writing.close()
        await reading.value
        child.waitUntilExit()
        fromChild.fileHandleForReading.readabilityHandler = nil
        XCTAssertEqual(child.terminationStatus, 0)
    }
}
