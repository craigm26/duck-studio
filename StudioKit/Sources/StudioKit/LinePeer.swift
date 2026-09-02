import Foundation
import DuckKit

/// A duck at the other end of a stream of NDJSON lines.
///
/// WHAT THIS IS AND WHAT IT IS NOT. It is the app's vocabulary — `DuckPeer` —
/// spoken over the framing `robotd` actually uses: one JSON-RPC 2.0 object per
/// line, newline-terminated, in both directions. It is NOT a transport. There is
/// no socket, no peripheral and no datachannel in this file, and there cannot be
/// one, because this package is built and tested on a Pi with nothing listening;
/// what a caller hands in is a closure that writes a frame and a stream that
/// yields whatever bytes arrived. That split is what lets the hard parts —
/// correlation, framing, fan-out, a send queue that drops the right frame — be
/// driven by `swift test` against a fake daemon rather than eyeballed on a phone
/// beside a robot nobody has yet.
///
/// IT DIFFERS FROM `SimDuck` IN ONE STRUCTURAL WAY AND THAT WAY IS THE POINT.
/// `SimDuck.Wire` is `(Data) -> Data?`: one line out, the answer back, which
/// is a request/response shape and can carry nothing the duck says on its own.
/// A real `robotd` does not work like that. `robot.state` arrives unbidden at
/// the loop rate, and `DuckState`'s whole design is built on that — "a robot's
/// state arrives as telemetry rather than by being asked". So this peer takes
/// the inbound bytes as a stream that exists whether or not anybody asked
/// anything, and every line off it goes through one `DuckRPC.StreamDecoder`:
/// answers get correlated, `robot.state` notifications go to `states()`, and
/// nothing has to guess which it is holding.
///
/// ONE DECODER, ONE DOOR. The write closure returns nothing on purpose. A
/// closure that also handed bytes back — the shape `SimDuck` uses — would give
/// the decoder two entrances, and two entrances into a stateful line assembler
/// is a partial line from one door being completed by bytes from the other.
/// That failure produces a message that never existed out of two that did, and
/// it would appear only under load.
///
/// THE FRAME CARRIES A NUMBER AND THE PARAMS DO NOT. Every line handed to the
/// transport is stamped by `DuckLineSequence` — beside the bytes, never inside
/// them. `robot.move`'s params stay exactly `{vx, vy, vyaw}`; a test asserts
/// that the bytes of a stamped move frame contain no fourth key. What a
/// transport does with the number is its business, and today every transport
/// this app has would drop it, which `DuckLineSequence.thisCounterStopsNothing`
/// says out loud.
///
/// AN ACTOR, AND STILL NOT A SINGLE WRITER. Isolation protects this peer's own
/// bookkeeping — the id table, the decoder, the send slot. It does nothing about
/// `intents.rs`, which is last-writer-wins on one command slot, so two of these
/// pointed at one duck still "interleave into one slot, producing a robot that
/// obeys neither". The fix their contract names is a token the duck hands out,
/// and `duck-ipc-proto` has no method to claim one.
public actor LinePeer: DuckPeer {

    /// One frame out. Nothing comes back through here: replies arrive on the
    /// inbound stream like everything else.
    ///
    /// IT TAKES THE STAMPED FRAME RATHER THAN THE BYTES so the counter reaches
    /// the transport at all. A transport with somewhere to put frame metadata
    /// puts it there; one without — which is all of them today — ignores the
    /// number and writes `frame.line`. Handing over only the bytes would have
    /// meant the counter existed solely inside this file, which is a
    /// measurement of nothing.
    public typealias Wire = @Sendable (DuckLineSequence.Stamped) async throws -> Void

    // MARK: - who and what

    public nonisolated let identity: DuckIdentity

    /// Which of the line-carrying links this is. `DuckLineTransport` has no
    /// bench case, so the type is the enforcement: a bench answers HTTP posts
    /// and a JSON-RPC line posted at it reads as a zero twist with no error
    /// anywhere. See `DuckLineTransport.benchIsNotALine`.
    public nonisolated let transport: DuckLineTransport

    public nonisolated var transportKind: DuckTransportKind { transport.kind }

    /// Exactly `DuckMethod.reach(for:)` for this link, or narrower if the
    /// caller knows this particular duck answers less. `DuckPeer` permits
    /// narrowing and forbids widening; the initialiser enforces it rather than
    /// asking.
    public nonisolated let reach: Set<DuckMethod>

    /// What this link has proved about who is calling. Never `.authenticated`,
    /// because no link in this app has ever authenticated anything — see
    /// `DuckAuthority`.
    public nonisolated var authority: DuckAuthority { DuckAuthority.of(transportKind) }

    private nonisolated let fan = DuckStateFanOut()
    private let wire: Wire
    private let inbound: AsyncStream<Data>

    // MARK: - bookkeeping

    private var decoder = DuckRPC.StreamDecoder()
    private var correlator = DuckRPC.Correlator()
    private var sequence = DuckLineSequence()

    /// Callers parked on an answer, and answers that arrived before their
    /// caller got round to waiting.
    ///
    /// THE SECOND TABLE IS NOT PARANOIA. `call` has to write before it can
    /// wait, and the write is an `await`, which releases this actor — so the
    /// read loop can decode the answer while the asker is still suspended
    /// inside the transport. Without somewhere to put that answer it would be
    /// dropped and the caller would wait forever, and it would happen only
    /// against a fast far end, which is to say only on the desk of whoever is
    /// demonstrating this.
    private var waiting: [DuckRPC.ID: CheckedContinuation<DuckReply, Error>] = [:]
    private var arrived: [DuckRPC.ID: Result<DuckReply, Error>] = [:]

    /// The depth-1 send slot. See `notify`.
    private var sending = false
    private var queued: DuckLineSequence.Stamped?

    private var closed = false
    private var readingAlready = false

    /// What has actually happened on this link, in counts.
    public private(set) var traffic = Traffic()

    /// The numbers a link is worth knowing about, none of which are inferred.
    ///
    /// COUNTED RATHER THAN AVERAGED, for `DuckState`'s stated reason: a line
    /// this decoder could not read is evidence that the schema moved, and the
    /// only useless thing to do with it is fold it into a rate.
    public struct Traffic: Equatable, Sendable {
        /// `robot.state` notifications that decoded and were published.
        public var statesPublished = 0
        /// Notifications that were not `robot.state` — update progress, or
        /// something this build has never heard of. Kept apart from the states
        /// because a rise here is a daemon that grew a feature.
        public var otherNotifications = 0
        /// Responses carrying an id nobody on this end minted. A late answer
        /// from a previous connection looks like this, which is exactly why
        /// `DuckRPC.Correlator` never reuses an id.
        public var unmatchedResponses = 0
        /// Requests from the far end. `duck-ipc-proto` has the daemon
        /// answering, not asking; one of these is news.
        public var requestsFromTheFarEnd = 0
        /// Notifications this peer's own send slot threw away — see `notify`.
        /// A gap in the sequence numbers that this end already knows about.
        public var supersededNotifications = 0
        /// Whole lines that arrived and were not JSON-RPC — the decoder's own
        /// count, carried out so a screen does not have to reach into it.
        public var malformedLines = 0
        /// Lines discarded unread for breaching `StreamDecoder.maxLineBytes`.
        public var refusedLines = 0
    }

    // MARK: - building one

    /// - Parameter inbound: every byte that arrives, in whatever chunks it
    ///   arrives in. Chunking is the transport's business and this peer's
    ///   problem — `DuckRPC.StreamDecoder` is written against the five things
    ///   that actually happen to a stream, including a message split across two
    ///   reads and four whole messages in one.
    /// - Parameter reach: what this duck answers, if it is known to be less
    ///   than the link carries. Anything wider is intersected down rather than
    ///   trusted: a peer that widened its reach would be claiming a route the
    ///   routing table has denied, and `DuckPeer` says so.
    public init(identity: DuckIdentity,
                over transport: DuckLineTransport,
                inbound: AsyncStream<Data>,
                reach: Set<DuckMethod>? = nil,
                wire: @escaping Wire) {
        self.identity = identity
        self.transport = transport
        let carried = DuckMethod.reach(for: transport.kind)
        self.reach = reach.map { $0.intersection(carried) } ?? carried
        self.inbound = inbound
        self.wire = wire
    }

    // MARK: - what the duck says

    /// Every state this duck reports, to every reader that asks.
    ///
    /// NOTHING IS PUBLISHED UNTIL `read()` IS RUNNING, and the ordering is a
    /// caller's to get right: take the stream, then start reading. That is why
    /// this member is not `async` — see `DuckPeer.states()`.
    public nonisolated func states() -> AsyncStream<DuckState> { fan.states() }

    /// Read the inbound stream until it ends.
    ///
    /// IT DOES NOT RETURN, WHICH IS THE HONEST SHAPE. A link is a thing that
    /// keeps arriving; the loop ends when the far end stops, and then every
    /// reader's stream ends too rather than going quiet — a `for await` that
    /// simply stops producing looks exactly like a duck standing still.
    ///
    /// CALLED ONCE. An `AsyncStream` has one consumer, so a second reader would
    /// take half the bytes and hand the decoder a stream with holes in it; the
    /// second call returns immediately rather than doing that.
    public func read() async {
        guard !readingAlready else { return }
        readingAlready = true
        for await chunk in inbound {
            for message in decoder.append(chunk) { take(message) }
            traffic.malformedLines = decoder.malformedLines
            traffic.refusedLines = decoder.refusedLines
        }
        close(because: LinkEnded.theFarEndStopped)
    }

    /// One decoded line, sorted into the three things it can be.
    ///
    /// THE TEST IS STRUCTURAL AND IT IS JSON-RPC'S OWN. A method with no id is
    /// a notification: the sender owes no reply and expects none. That is the
    /// same rule `DuckLink.notificationMethod(fromLine:)` applies to a BLE line,
    /// and `LinePeerTests` pins the two against the same bytes so they cannot
    /// come to disagree — the failure that rule was written for is a
    /// notification being reported as "the duck answered and this app could not
    /// read the answer", which fabricates a refusal out of the robot doing
    /// exactly what the protocol allows.
    private func take(_ message: DuckRPC.Message) {
        if message.isNotification {
            guard message.method == DuckState.method else {
                traffic.otherNotifications += 1
                return
            }
            // A `robot.state` whose params are an object always decodes, even
            // when nothing in it is recognised — `DuckState.isEmpty` is that
            // case, and it is a fact worth publishing rather than a line worth
            // dropping, because it is the loudest signal the schema moved.
            guard let state = DuckState(message, receivedAt: Date()) else {
                traffic.otherNotifications += 1
                return
            }
            traffic.statesPublished += 1
            fan.publish(state)
            return
        }
        if message.isRequest {
            traffic.requestsFromTheFarEnd += 1
            return
        }
        guard let id = message.id else {
            // No method, no id: `StreamDecoder` only builds a message when one
            // of method, id or error is present, so this is an error object
            // with no id — a refusal of something unparseable. Nobody can be
            // told which call it answers.
            traffic.unmatchedResponses += 1
            return
        }
        // The Correlator is what turns an integer back into "the kick was
        // refused" rather than "something was refused". Consuming the row here
        // is also what makes a duplicated answer unmatched rather than a second
        // delivery to a caller who has already been resumed.
        let wasWaitingFor = correlator.method(answering: message)
        if wasWaitingFor == nil {
            traffic.unmatchedResponses += 1
            return
        }
        deliver(Result { try DuckReply.decode(message.line) }, for: id)
    }

    private func deliver(_ outcome: Result<DuckReply, Error>, for id: DuckRPC.ID) {
        if let continuation = waiting.removeValue(forKey: id) {
            continuation.resume(with: outcome)
        } else {
            arrived[id] = outcome
        }
    }

    // MARK: - saying the vocabulary

    /// Ask, and wait for the answer.
    public func call(_ c: DuckCall) async throws -> DuckReply {
        try vet(c, asNotification: false)
        if closed { throw LinkEnded.theFarEndStopped }
        let id = try mint(c.method)
        // THE CORRELATOR MINTS THE ID AND THIS BUILDS THE LINE, WHICH IS TWO
        // JOBS ON PURPOSE. `Correlator.request` can produce bytes as well, and
        // its bytes are not the ones this app sends: `DuckCall.line(id:)` is
        // the single line builder in the package — it routes `hello` through
        // `DuckLink.helloRequest`, which is the one line a real robot has been
        // written against, and it runs the finiteness check that keeps a NaN
        // out of `JSONSerialization`. Two line builders would be two spellings
        // of every call.
        guard case .number(let raw) = id, let numbered = Int(exactly: raw) else {
            throw LinkEnded.idWasNotANumber
        }
        let frame = sequence.stamp(try c.line(id: numbered))
        do {
            try await wire(frame)
        } catch {
            // The id stays in the Correlator's table. It cannot mis-correlate
            // anything — ids are never reused, so no future answer can claim it
            // — and `close` reports it as abandoned, which is the truth: a call
            // that was never written is a call nothing will ever answer.
            throw error
        }
        return try await answer(to: id)
    }

    /// Park until the answer for this id arrives, or take one that beat us here.
    ///
    /// NO AWAIT BETWEEN THE TWO HALVES, which is what makes the arrived-early
    /// table safe: this runs on the actor, and `withCheckedThrowingContinuation`
    /// runs its body synchronously, so nothing can deliver an answer between the
    /// lookup and the registration.
    private func answer(to id: DuckRPC.ID) async throws -> DuckReply {
        if let already = arrived.removeValue(forKey: id) { return try already.get() }
        // THE LINK CAN DIE DURING THE WRITE, which is a window one `await` wide
        // and exactly the one a dropped connection lands in. Parking here after
        // `close` has already resumed everybody would be a caller waiting on a
        // link that has finished admitting it is gone — the hang this whole
        // arrangement exists to prevent.
        if closed { throw LinkEnded.theFarEndStopped }
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
        }
    }

    private func mint(_ method: DuckMethod) throws -> DuckRPC.ID {
        try correlator.request(method.rawValue).id
    }

    /// Say, and do not wait — with a send slot exactly one frame deep.
    ///
    /// WHY A QUEUE OF ONE AND NOT A QUEUE. A continuous intent is
    /// last-writer-wins and it EXPIRES: `duck-ipc-proto` sends `robot.move` at
    /// 20–50 Hz precisely so that the newest twist is the only one that matters.
    /// A transport that is slower than the loop — Bluetooth renegotiating an
    /// MTU, a relay across a phone — therefore must not build a backlog, because
    /// every frame in that backlog is a command the driver has already changed
    /// their mind about. A queue of ten is a duck that keeps walking for a fifth
    /// of a second after the stick is centred. A queue of one is a duck that
    /// does the last thing it was told, late.
    ///
    /// THE DROP IS COUNTED AND IT IS THE APP'S OWN. Superseding a queued frame
    /// puts a hole in the sequence numbers this end sent, and
    /// `traffic.supersededNotifications` is what distinguishes that hole from a
    /// frame the link lost — which is the entire reason `DuckLineSequence`
    /// exists, so a hole this peer made itself must not be counted as loss.
    ///
    /// IT RETURNS AS SOON AS THE FRAME IS ACCEPTED, not when it is written.
    /// "Do not wait" is the contract's word: a caller that waited for each
    /// twist to reach the wire would be pacing the driving loop on the transport
    /// rather than on the clock, which is the shape `BenchPeer` is stuck with
    /// and this one is not.
    public func notify(_ c: DuckCall) async throws {
        try vet(c, asNotification: true)
        if closed { throw LinkEnded.theFarEndStopped }
        let frame = sequence.stamp(try c.line(id: nil))
        guard !sending else {
            if queued != nil { traffic.supersededNotifications += 1 }
            queued = frame
            return
        }
        sending = true
        defer {
            sending = false
            queued = nil
        }
        var next: DuckLineSequence.Stamped? = frame
        while let out = next {
            try await wire(out)
            next = queued
            queued = nil
        }
    }

    // MARK: - the end of a link

    /// Why a call could not be made or an answer will never come.
    public enum LinkEnded: Error, Equatable {
        /// The inbound stream ended, or somebody closed this peer.
        case theFarEndStopped
        /// A minted id was not a number. `DuckRPC.Correlator` only mints
        /// numbers, so this is unreachable and is a thrown error rather than a
        /// `fatalError` for `BenchPeer`'s reason: an impossible branch in
        /// somebody's hand should be a message, not a crash.
        case idWasNotANumber

        public var message: String {
            switch self {
            case .theFarEndStopped:
                return "This link has ended. Anything that was still waiting for an answer will "
                     + "not get one — those answers are not coming, and a screen with four "
                     + "buttons stuck on \"sent…\" is worse than four that admit the link died."
            case .idWasNotANumber:
                return "A request id came back as something other than a number, which nothing in "
                     + "this app can mint. Nothing was sent."
            }
        }
    }

    /// Stop, and tell everybody.
    ///
    /// EVERY PARKED CALLER IS RESUMED AND EVERY READER'S STREAM ENDS. A
    /// connection that drops silently leaves both halves of the app waiting on
    /// something that will not arrive; `Correlator.abandonAll` exists for
    /// exactly this and says what was abandoned.
    public func close() {
        close(because: LinkEnded.theFarEndStopped)
    }

    private func close(because reason: LinkEnded) {
        guard !closed else { return }
        closed = true
        // The table of what was still expected, emptied. Its contents are the
        // methods nobody will ever get an answer to; each one's caller is
        // resumed below with the same refusal, which is where that fact is
        // actually delivered.
        correlator.abandonAll()
        let parked = waiting
        waiting.removeAll()
        arrived.removeAll()
        for continuation in parked.values { continuation.resume(throwing: reason) }
        fan.finish()
    }

    /// How many answers this link is still waiting for.
    public var inFlight: Int { correlator.inFlightCount }

    /// The last frame number stamped on this link. Zero before anything has
    /// been sent.
    public var lastFrameNumber: UInt64 { sequence.last }

    /// Bytes held by the decoder right now, waiting for a newline — the
    /// difference between "the duck is quiet" and "the duck is mid-sentence".
    public var pendingBytes: Int { decoder.pendingBytes }
}
