import XCTest
@testable import StudioKit

/// The bench that is this phone: what it is called, what survives storage, and
/// every sentence said about it.
///
/// THIS FILE IS WHERE THE OLD PREMISE IS REVERSED UNDER TEST. The app has said
/// "an iPhone has no physics engine" in eleven places, and the replacement
/// claim — that the same MuJoCo build runs here — comes with a caveat that
/// matters more than the claim: same physics, different trajectory. A sentence
/// that made the first half without the second would be believed and then
/// contradicted by two recordings that do not line up.
final class PhoneBenchReportTests: XCTestCase {

    // MARK: - the endpoint that is not on the network

    /// THE ID IS A CONSTANT AND THE TEST SAYS THE CONSTANT OUT LOUD. Every
    /// screen that remembers a bench remembers a UUID, so a phone bench built
    /// with a fresh `UUID()` each launch would be selected once and be a
    /// different bench in the morning.
    func testThePhoneBenchHasTheOneFixedIdentity() {
        let phone = BenchEndpoint.thisPhone
        XCTAssertEqual(phone.id.uuidString.lowercased(),
                       "00000000-0000-0000-0000-00000000dc0c")
        XCTAssertEqual(phone.name, "This iPhone")
        XCTAssertEqual(phone.address, "127.0.0.1:0")
        XCTAssertEqual(phone.kind, .thisPhone)
        XCTAssertFalse(phone.hasToken)
        XCTAssertNil(phone.token)
    }

    /// It is not a thing to edit and not a thing to hand a token.
    func testThePhoneBenchIsNotEditable() {
        XCTAssertFalse(BenchEndpoint.thisPhone.isEditable)
        XCTAssertTrue(BenchEndpoint.thisPhone.isThisPhone)
        XCTAssertTrue(BenchEndpoint(name: "Pi", address: "100.122.199.6:8770").isEditable)
        XCTAssertFalse(BenchEndpoint(name: "Pi", address: "100.122.199.6:8770").isThisPhone)
    }

    /// BEFORE THE LISTENER HAS A PORT, THE REFUSAL IS ITS OWN SENTENCE. Run
    /// through the address parser, `127.0.0.1:0` comes back as
    /// `notLocal("127.0.0.1:0")` — telling somebody their own phone is not on
    /// their network, about an address they never typed.
    func testAPhoneBenchWithNoPortYetRefusesInItsOwnWords() {
        XCTAssertNil(BenchEndpoint.thisPhone.phoneBenchPort)
        XCTAssertThrowsError(try BenchEndpoint.thisPhone.resolved()) { error in
            XCTAssertEqual(error as? BenchEndpoint.Refusal, .phoneBenchNotListening)
            XCTAssertEqual((error as? BenchEndpoint.Refusal)?.message,
                           PhoneBenchReport.notListening)
        }
        // And the same refusal comes out of the check the editor would run.
        XCTAssertThrowsError(try BenchEndpoint.thisPhone.validateAddress())
    }

    /// The port the kernel handed the listener is the port a request goes to.
    func testThePortTheAppWasGivenIsTheOneItDials() throws {
        let live = BenchEndpoint.thisPhone.servedOn(port: 51993)
        XCTAssertEqual(live.address, "127.0.0.1:51993")
        XCTAssertEqual(live.phoneBenchPort, 51993)
        let address = try live.resolved()
        XCTAssertEqual(address.host, "127.0.0.1")
        XCTAssertEqual(address.port, 51993)
        XCTAssertEqual(address.base, "http://127.0.0.1:51993")
        // The identity does not move when the port does.
        XCTAssertEqual(live.id, BenchEndpoint.thisPhone.id)
    }

    /// A NETWORK BENCH'S ADDRESS IS SOMEBODY'S TYPING AND NOTHING MAY REWRITE
    /// IT. `servedOn` is a no-op on anything that is not the phone.
    func testServedOnDoesNothingToABenchOnYourNetwork() {
        let pi = BenchEndpoint(name: "Pi", address: "100.122.199.6:8770")
        XCTAssertEqual(pi.servedOn(port: 51993).address, "100.122.199.6:8770")
        XCTAssertNil(pi.phoneBenchPort)
    }

    // MARK: - what survives storage

    /// A RECORD WRITTEN BEFORE `kind` EXISTED IS A NETWORK BENCH. Every bench
    /// already saved on somebody's phone has no `kind` key, and a decoder that
    /// threw on the missing one would take the whole list down through
    /// `decodeList`'s salvage — which reads, from the other side, as the app
    /// having forgotten their benches.
    func testABenchSavedBeforeKindExistedIsANetworkBench() throws {
        let old = Data("""
        [{"id":"7B4E6D9C-0000-4000-8000-000000000001","name":"Pi",
          "address":"100.122.199.6:8770","hasToken":true}]
        """.utf8)
        let salvage = BenchEndpoint.decodeList(from: old)
        XCTAssertEqual(salvage.unreadable, 0)
        XCTAssertEqual(salvage.benches.count, 1)
        XCTAssertEqual(salvage.benches.first?.kind, .network)
        XCTAssertEqual(salvage.benches.first?.hasToken, true)
    }

    /// And a word this app does not know is a network bench too, rather than an
    /// unreadable record that costs the whole list.
    func testAKindThisAppDoesNotKnowIsStillReadable() {
        let strange = Data("""
        [{"id":"7B4E6D9C-0000-4000-8000-000000000002","name":"Pi",
          "address":"10.0.0.5:8770","hasToken":false,"kind":"orbital"}]
        """.utf8)
        let salvage = BenchEndpoint.decodeList(from: strange)
        XCTAssertEqual(salvage.benches.count, 1)
        XCTAssertEqual(salvage.benches.first?.kind, .network)
    }

    /// The kind makes the round trip for the benches that are written down.
    func testKindSurvivesEncodingForASavedBench() throws {
        let pi = BenchEndpoint(name: "Pi", address: "10.0.0.5:8770", hasToken: true)
        let back = BenchEndpoint.decodeList(from: try JSONEncoder().encode([pi]))
        XCTAssertEqual(back.benches.first?.kind, .network)
        XCTAssertNil(back.benches.first?.token, "the token is never encoded")
    }

    // MARK: - the host block on /health

    /// `duck-bench/5` says where the physics ran. Nothing older does, and the
    /// difference between "did not say" and "said nothing useful" is the whole
    /// reason the field is Optional.
    func testHealthReadsTheHostBlockWhenTheBenchSendsOne() throws {
        let body = Data("""
        {"bench":"duck-bench/5","plant":"scene.mjb — Pollen","tickHz":50,"cores":4,
         "policies":["alpha_stand.onnx"],"trains":false,
         "host":{"kind":"phone","device":"iPhone15,2","engine":"JavaScriptCore/WebKit",
                 "tickMillis":2.7}}
        """.utf8)
        let health = try DuckBench.readHealth(body)
        let host = try XCTUnwrap(health.host)
        XCTAssertEqual(host.kind, .phone)
        XCTAssertEqual(host.kindSaid, "phone")
        XCTAssertEqual(host.device, "iPhone15,2")
        XCTAssertEqual(host.engine, "JavaScriptCore/WebKit")
        XCTAssertEqual(host.tickMillis ?? 0, 2.7, accuracy: 1e-9)
    }

    func testAnOlderBenchSaysNothingAboutItsHostRatherThanGuessing() throws {
        let body = Data("""
        {"bench":"duck-bench/4","plant":"scene.mjb","tickHz":50,"cores":4,
         "policies":[],"trains":false}
        """.utf8)
        XCTAssertNil(try DuckBench.readHealth(body).host)
        XCTAssertEqual(PhoneBenchReport.ranOn(nil), PhoneBenchReport.unstatedHost)
    }

    /// A NULL TICK IS A BENCH THAT DID NOT MEASURE, not a bench that measured
    /// zero. `tickMillis` is documented as number-or-null and JSON null arrives
    /// as `NSNull`, which must not cast to 0.
    func testATickTheBenchDidNotMeasureStaysUnmeasured() throws {
        let body = Data("""
        {"bench":"duck-bench/5","plant":"scene.mjb","tickHz":50,"cores":4,
         "policies":[],"trains":false,
         "host":{"kind":"desk","device":"Raspberry Pi 5","engine":"V8","tickMillis":null}}
        """.utf8)
        let host = try XCTUnwrap(try DuckBench.readHealth(body).host)
        XCTAssertNil(host.tickMillis)
        XCTAssertTrue(PhoneBenchReport.ranOn(host).contains("did not measure what a tick costs"),
                      PhoneBenchReport.ranOn(host))
    }

    /// A THIRD WORD READS AS A THIRD WORD. Rounding an unknown `kind` to
    /// whichever case is nearer would show somebody a machine the bench never
    /// claimed.
    func testAHostKindThisAppHasNoWordForIsQuotedRatherThanRounded() throws {
        let body = Data("""
        {"bench":"duck-bench/5","plant":"scene.mjb","tickHz":50,"cores":4,
         "policies":[],"trains":false,
         "host":{"kind":"orbital","device":"a satellite","engine":"V8","tickMillis":1.5}}
        """.utf8)
        let host = try XCTUnwrap(try DuckBench.readHealth(body).host)
        XCTAssertNil(host.kind)
        XCTAssertEqual(host.kindSaid, "orbital")
        let said = PhoneBenchReport.ranOn(host)
        XCTAssertTrue(said.contains("\"orbital\""), said)
        XCTAssertTrue(said.contains("has no word for"), said)
        XCTAssertFalse(said.contains("on this phone"), said)
        XCTAssertFalse(said.contains("across the network"), said)
    }

    /// The two sentences a reader actually gets, with the numbers in them.
    func testTheHostSentenceQuotesTheMachineAndTheTick() throws {
        let phone = DuckBench.Health.Host(kind: .phone, kindSaid: "phone",
                                          device: "iPhone15,2",
                                          engine: "JavaScriptCore/WebKit, MuJoCo 3.1.16 (WASM)",
                                          tickMillis: 2.7)
        let said = PhoneBenchReport.ranOn(phone)
        XCTAssertTrue(said.hasPrefix("Ran on this phone: iPhone15,2, "), said)
        XCTAssertTrue(said.contains("2.70 ms"), "two decimals separate 2.70 from 27.0: \(said)")

        let desk = DuckBench.Health.Host(kind: .desk, kindSaid: "desk", device: "", engine: "",
                                         tickMillis: nil)
        let deskSaid = PhoneBenchReport.ranOn(desk)
        XCTAssertTrue(deskSaid.contains("across the network"), deskSaid)
        XCTAssertTrue(deskSaid.contains("an unnamed device"), deskSaid)
        XCTAssertTrue(deskSaid.contains("an unnamed engine"), deskSaid)
    }

    // MARK: - the claim, and the caveat that must travel with it

    /// SAME PHYSICS IS NOT SAME TRAJECTORY, and the pair is asserted together
    /// so neither can be shipped alone.
    func testTheSamePhysicsClaimIsAboutTheIntegratorAndThePlant() {
        let s = PhoneBenchReport.samePhysics
        XCTAssertTrue(s.hasPrefix("The same physics the bench runs."), s)
        XCTAssertTrue(s.contains("MuJoCo 3.1.16"), s)
        XCTAssertTrue(s.contains("byte for byte"), s)
        XCTAssertTrue(s.contains("scene.mjb"), s)
    }

    func testTheDriftIsStatedWhereverTheClaimIs() {
        let s = PhoneBenchReport.notTheSameTrajectory
        XCTAssertTrue(s.contains("3.5e-6"), s)
        XCTAssertTrue(s.contains("\(PhoneBenchReport.driftMillimetres) mm"), s)
        XCTAssertTrue(s.contains("\(PhoneBenchReport.driftTicks) ticks"), s)
        XCTAssertEqual(PhoneBenchReport.actionAgreement, 3.5e-6, accuracy: 1e-12)
        // The two halves of the verdict, in the order a reader needs them.
        XCTAssertNotNil(s.range(of: "Counting outcomes carries"), s)
        XCTAssertNotNil(s.range(of: "Comparing recorded frames does not"), s)
    }

    func testMeasureTransfersAndRecordDoesNot() {
        XCTAssertTrue(PhoneBenchReport.measureTransfers.contains("can be read against one"),
                      PhoneBenchReport.measureTransfers)
        XCTAssertTrue(PhoneBenchReport.recordDoesNotTransfer.contains("not the desk bench's"),
                      PhoneBenchReport.recordDoesNotTransfer)
        XCTAssertTrue(PhoneBenchReport.recordDoesNotTransfer.contains("32 mm"),
                      PhoneBenchReport.recordDoesNotTransfer)
    }

    /// NO NUMBER MEASURED ON A DESK MAY BE QUOTED AS A NUMBER ABOUT A PHONE.
    /// The speed sentence names the machine that produced its figure and then
    /// says it is not this one.
    func testTheSpeedSentenceRefusesToClaimAPhoneNumber() {
        let s = PhoneBenchReport.speedIsUnmeasuredOnAPhone
        XCTAssertTrue(s.hasPrefix("How fast this is on this phone has not been measured."), s)
        XCTAssertTrue(s.contains("Chromium on a Raspberry Pi"), s)
        XCTAssertTrue(s.contains("not Safari on an iPhone"), s)
        // A RANGE, BECAUSE TWO RUNS ON ONE MACHINE DISAGREED BY A THIRD —
        // 2.7 ms headed, 3.50 ms headless. A single figure here would be the
        // more confident and less true sentence.
        XCTAssertTrue(s.contains("2.7 to 3.5 ms"), s)
        XCTAssertTrue(s.contains("20 ms"), s)
        XCTAssertFalse(s.contains("on this phone it takes"), s)
    }

    // MARK: - the refusals and the losses

    /// A BLOCKED SURFACE SHIPS AS AN EXPLICIT NOT-YET, AND THIS ONE WAS BLOCKED
    /// WIDER THAN THE TRUTH.
    ///
    /// The sentence used to say the bench "cannot be handed a network". What it
    /// cannot be handed is a FILE: `duckbench-web.mjs` checks the body's length
    /// against `FLOAT_COUNT * 4` and runs anything that passes through
    /// `policyforward.mjs`, which reads exactly `canonicalParameterBytes`.
    /// Measured against the shipped `site/phonebench` build: canonical bytes
    /// accepted and run, an ONNX body refused. The distinction is the whole
    /// difference between a phone that replays what shipped with it and one
    /// that can run something it just made, so the assertion below pins the new
    /// claim AND forbids the old one coming back.
    func testUploadRefusesAFileAndNotANetwork() {
        let s = PhoneBenchReport.uploadNotWired
        XCTAssertTrue(s.contains("will not take a policy FILE"), s)
        XCTAssertTrue(s.contains("no ONNX reader of its own"), s)
        XCTAssertTrue(s.contains("bench on your network"), s)
        XCTAssertTrue(s.contains("those it accepts"),
                      "the door that IS open has to be named in the same sentence: \(s)")
        XCTAssertFalse(s.contains("cannot be handed a network"),
                       "the over-broad claim must not come back: \(s)")
        XCTAssertTrue(PhoneBenchReport.parametersAreWhatItTakes.contains("parameter bytes"))
        XCTAssertTrue(PhoneBenchReport.parametersAreWhatItTakes.contains("fingerprint"),
                      "and it says why that is the same network the library inspected")
    }

    /// THE LOSS SENTENCE MUST NOT BE OPTIMISTIC. The rebuild comes last, after
    /// the plain statement that whatever was running is not a result.
    func testTheWorldLostSentenceCallsTheUnfinishedWorkNotAResult() {
        let s = PhoneBenchReport.worldLost
        XCTAssertTrue(s.contains("lost its world"), s)
        XCTAssertTrue(s.contains("is not a result"), s)
        guard let notAResult = s.range(of: "is not a result"),
              let rebuilding = s.range(of: "being rebuilt") else { return XCTFail(s) }
        XCTAssertLessThan(notAResult.lowerBound, rebuilding.lowerBound,
                          "the loss is stated before the recovery: \(s)")
    }

    /// NOT AN ERROR, A MOMENT. The listener gets its port at launch.
    func testTheNotListeningSentenceIsAStateAndNotAFailure() {
        let s = PhoneBenchReport.notListening
        XCTAssertTrue(s.contains("still coming up"), s)
        XCTAssertTrue(s.contains("arrives on its own"), s)
        XCTAssertFalse(s.lowercased().contains("error"), s)
    }

    // MARK: - the sentence the old empty state used to say

    /// THE PREMISE IS REVERSED IN WRITING, and the list's own copy no longer
    /// tells anybody their phone cannot run a policy.
    func testTheListNoLongerSaysAPhoneCannotRunAnything() {
        for sentence in [PhoneBenchReport.alwaysOneBench,
                         PhoneBenchReport.phoneRowNote,
                         PhoneBenchReport.premiseWasAboutABuild] {
            XCTAssertFalse(sentence.contains("no physics engine")
                           && !sentence.contains("was a claim"),
                           "still repeating the old premise: \(sentence)")
        }
        XCTAssertTrue(PhoneBenchReport.alwaysOneBench.hasPrefix("There is always one bench"),
                      PhoneBenchReport.alwaysOneBench)
        XCTAssertTrue(PhoneBenchReport.alwaysOneBench.contains("cannot be edited or deleted"),
                      PhoneBenchReport.alwaysOneBench)
        XCTAssertTrue(PhoneBenchReport.alwaysOneBench.contains("wants no token"),
                      PhoneBenchReport.alwaysOneBench)
        XCTAssertTrue(PhoneBenchReport.premiseWasAboutABuild.contains("about a build"),
                      PhoneBenchReport.premiseWasAboutABuild)
    }

    /// The name is one string and not two.
    func testTheNameIsTheOneTheEndpointCarries() {
        XCTAssertEqual(PhoneBenchReport.name, BenchEndpoint.thisPhone.name)
    }
}
