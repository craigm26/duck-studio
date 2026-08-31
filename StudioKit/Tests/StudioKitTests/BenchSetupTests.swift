import XCTest
@testable import StudioKit

/// Every one of these sentences is shown to somebody who has already worked out
/// that it did not connect. They are asserted because a diagnosis that names
/// the wrong action is worse than none — it sends a person to check a firewall
/// when they never started the bench.
final class BenchSetupTests: XCTestCase {

    private func diagnose(_ address: String, status: Int? = 200, body: Data? = nil,
                          failed: Bool = false) -> BenchSetup.Diagnosis {
        BenchSetup.diagnose(address: address, status: status, body: body,
                            transportFailed: failed)
    }

    // MARK: - the seven ways it fails

    func testNothingTypedAsksForTheAddressTheScriptPrints() {
        XCTAssertEqual(diagnose(""), .nothingTyped)
        XCTAssertEqual(diagnose("   "), .nothingTyped)
        XCTAssertTrue(diagnose("").message.contains("100.95.79.116:8770"),
                      "an example is worth more than a description of the format")
    }

    /// THE APP DOES NOT DIAL THE INTERNET, and the sentence says which
    /// addresses it does take rather than only refusing.
    func testAPublicAddressIsRefusedWithTheRuleSpelledOut() {
        let d = diagnose("bench.example.com:8770")
        guard case .notReachableAddress = d else { return XCTFail("\(d)") }
        XCTAssertTrue(d.message.contains("100.x"), d.message)
        XCTAssertTrue(d.message.contains("192.168"), d.message)
    }

    func testNothingListeningBlamesTheBenchBeforeTheNetwork() {
        let d = diagnose("100.95.79.116:8770", status: nil, failed: true)
        XCTAssertEqual(d, .nothingListening)
        XCTAssertTrue(d.message.contains("still open"),
                      "the commonest cause is the window being closed: \(d.message)")
    }

    func testAnUnauthorisedAnswerAsksForTheTokenAndNamesTheVariable() {
        let d = diagnose("100.95.79.116:8770", status: 401)
        XCTAssertEqual(d, .wantsAToken)
        XCTAssertTrue(d.message.contains("DUCKBENCH_TOKEN"), d.message)
    }

    func testSomethingElseOnThePortIsNotCalledAMissingBench() {
        let d = diagnose("100.95.79.116:8770", body: "<html>hello</html>".data(using: .utf8))
        XCTAssertEqual(d, .notABench)
        XCTAssertTrue(d.message.contains("8770"), d.message)
    }

    /// A bench that answered with a refusal IS a bench, and saying so points at
    /// a different fix than "nothing is there".
    func testABenchThatRefusedIsStillReportedAsABench() {
        let d = diagnose("100.95.79.116:8770",
                         body: #"{"error":"this bench wants its token"}"#.data(using: .utf8))
        XCTAssertEqual(d, .benchRefused("this bench wants its token"))
    }

    // MARK: - when it works

    /// Against the duckbench's OWN /health, saved byte for byte — the reader
    /// and the sentence proven on the thing they will actually meet.
    func testARealHealthAnswerConnects() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/bench/health",
                                                  withExtension: "json"))
        let d = diagnose("100.95.79.116:8770", body: try Data(contentsOf: url))
        guard case .connected(let policies, let plant) = d else { return XCTFail("\(d)") }
        XCTAssertGreaterThan(policies, 0)
        XCTAssertNotNil(plant, "a bench without a named world is not one worth quoting")
        XCTAssertTrue(d.isConnected)
    }

    // MARK: - what they pasted

    func testAPastedURLIsTidiedIntoAHostAndPort() {
        XCTAssertEqual(BenchSetup.tidy(" http://100.95.79.116:8770/ "), "100.95.79.116:8770")
        XCTAssertEqual(BenchSetup.tidy("100.95.79.116:8770"), "100.95.79.116:8770")
    }

    /// 100.64.0.0/10 IS THE TAILNET RANGE, not "anything starting 100". 100.5
    /// and 100.200 are ordinary public addresses and calling them a tailnet
    /// would recommend the wrong thing.
    func testOnlyTheRealTailnetRangeCountsAsATailnetAddress() {
        XCTAssertTrue(BenchSetup.isTailnet("100.95.79.116:8770"))
        XCTAssertTrue(BenchSetup.isTailnet("100.64.76.122"))
        XCTAssertTrue(BenchSetup.isTailnet("100.127.0.1"))
        XCTAssertFalse(BenchSetup.isTailnet("100.5.0.1"), "below the range")
        XCTAssertFalse(BenchSetup.isTailnet("100.200.0.1"), "above the range")
        XCTAssertFalse(BenchSetup.isTailnet("192.168.1.20:8770"))
    }

    /// A LAN address works right up until the phone prefers cellular, and then
    /// fails in a way that looks like a dead bench. The warning says that.
    func testTheLanWarningExplainsWhyItWillStopWorking() {
        let s = BenchSetup.lanWarning
        XCTAssertTrue(s.contains("same Wi-Fi"), s)
        XCTAssertTrue(s.contains("looks exactly like the bench going down"), s)
    }

    // MARK: - the steps

    func testTheStepsAreNumberedInOrderAndEachSaysWhatToDo() {
        let steps = BenchSetup.steps
        XCTAssertEqual(steps.map(\.number), Array(1...steps.count))
        for step in steps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertGreaterThan(step.detail.count, 40, "step \(step.number) says too little")
        }
    }

    /// THE ONE THING PEOPLE GET WRONG IS CLOSING THE WINDOW, so the step that
    /// starts the bench has to say the window stays open.
    func testTheStartStepSaysToLeaveItRunning() throws {
        let start = try XCTUnwrap(BenchSetup.steps.first { $0.title.contains("Start") })
        XCTAssertTrue(start.detail.contains("Leave the window open"), start.detail)
    }

    /// And the steps must not send somebody to a Wi-Fi address, which is the
    /// setup that works today and breaks tomorrow.
    func testTheStepsRecommendTailscaleRatherThanWiFi() {
        let all = BenchSetup.steps.map(\.detail).joined(separator: " ")
        XCTAssertTrue(all.contains("Tailscale"), all)
        XCTAssertTrue(all.contains("rather than only on the same Wi-Fi"), all)
    }

    /// THE BENCH IS IN A PRIVATE REPO. Somebody who installed this from
    /// TestFlight cannot get the folder step 3 asks for, and a setup screen
    /// that walks them to an impossible step is the app telling them their
    /// phone is the problem. Until there is a download, the step says so.
    ///
    /// DELETE THIS TEST WHEN THE BENCH IS PUBLISHED, and say where it is
    /// instead — an assertion that outlives the fact it guards becomes the
    /// reason a true sentence cannot be written.
    func testTheStepsAdmitTheBenchCannotYetBeDownloaded() throws {
        let copy = try XCTUnwrap(BenchSetup.steps.first { $0.title.contains("Copy") })
        XCTAssertTrue(copy.detail.contains("NOT PUBLISHED YET"), copy.detail)
        XCTAssertTrue(copy.detail.contains("works without one"),
                      "and the app is not useless without a bench: \(copy.detail)")
    }

    // MARK: - the presets

    /// EVERY BENCH RUNS THE SAME PROGRAM ON THE SAME PORT. The only thing that
    /// differs is how the phone reaches it, and there are two answers — so a
    /// longer menu here would be inventing distinctions to look thorough.
    func testThereAreExactlyTwoPresetsAndBothUsePortEightSevenSevenZero() {
        XCTAssertEqual(BenchSetup.presets.count, 2)
        for preset in BenchSetup.presets {
            XCTAssertTrue(preset.address.hasSuffix(":8770"), preset.address)
            XCTAssertFalse(preset.suggestedName.isEmpty)
            XCTAssertGreaterThan(preset.detail.count, 30, preset.name)
        }
    }

    /// The tailnet one comes first because it is the recommendation, and its
    /// address really is in the tailnet range — a preset that filled in
    /// something `isTailnet` rejects would teach the wrong shape.
    func testTheTailnetPresetIsFirstAndIsActuallyATailnetAddress() throws {
        let first = try XCTUnwrap(BenchSetup.presets.first)
        XCTAssertTrue(BenchSetup.isTailnet(first.address), first.address)
        XCTAssertFalse(BenchSetup.isTailnet(BenchSetup.presets[1].address))
        XCTAssertTrue(BenchSetup.presets[1].detail.contains("stops working"),
                      "the Wi-Fi preset says what it costs")
    }

    /// Both fill in something the app will actually dial. A preset that seeded
    /// an address the parser refuses would open a new entry already broken.
    func testEveryPresetAddressIsOneTheClientAccepts() {
        for preset in BenchSetup.presets {
            XCTAssertNoThrow(try DuckBench.address(preset.address), preset.name)
        }
    }
}
