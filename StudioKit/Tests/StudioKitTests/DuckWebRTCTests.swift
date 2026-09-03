import XCTest
@testable import StudioKit

/// A protocol nobody implements, and the test that keeps it that way.
///
/// WHY A TEST ASSERTS AN ABSENCE. `DuckWebRTC.Signalling` is a shape held still
/// while five specific unknowns get answered by somebody reading Pollen's
/// source. A conformance written before those answers is a client built on
/// guesses, and the failure mode is the one `DuckLink` already paid for: "a name
/// copied from a web mirror produces a call the robot refuses by name, and a
/// refusal by name looks exactly like a feature the robot does not have." So the
/// day a conformance appears, this file fails and whoever wrote it has to delete
/// the corresponding unknown from the list in the same commit.
final class DuckWebRTCTests: XCTestCase {

    /// Five unknowns, numbered, each naming what would answer it.
    /// The list of unknowns is now a list of what was READ, and what is
    /// genuinely still open. Four of the original five were answered from
    /// `pollen-robotics/microduck`, which is public.
    func testWhatIsKnownIsTheContractAndWhatIsOpenIsSaidSeparately() {
        let known = DuckWebRTC.whatIsKnownNow
        XCTAssertTrue(known.contains("8443"))
        XCTAssertTrue(known.contains("ANSWERS the offer"))
        XCTAssertTrue(known.contains("`control`"))
        XCTAssertTrue(known.contains("no gate"))
        let open = DuckWebRTC.twoThingsStillOpen
        XCTAssertTrue(open.contains("TURN"))
        XCTAssertTrue(open.contains("studio-to-studio"))
        XCTAssertFalse(open.contains("datachannel"),
                       "the channel's label and shape are known now")
    }

    /// The screen still says not-yet, and the REASON has changed: it was a
    /// contract nobody had read, and it is now a dependency this app has not
    /// linked. A sentence that did not move when the reason moved would be the
    /// worse of the two failures.
    func testTheScreenSentenceSaysNotYetAndSaysWhichThingIsMissing() {
        let said = DuckWebRTC.whyThereIsNoClient
        XCTAssertTrue(said.contains("No WebRTC client here yet"), said)
        XCTAssertTrue(said.contains("a peer connection rather than a contract"), said)
        XCTAssertTrue(said.contains("transcribed from the client the robot itself serves"), said)
        XCTAssertFalse(said.contains("five specific things"),
                       "four of the five were read; the sentence cannot still claim them")
    }

    /// The peers this package actually has, asked directly. Cheap, total over
    /// the types that exist today, and it runs everywhere — including on a
    /// phone, where the source scan below cannot.
    func testNoPeerInThisPackageIsAWebRTCClient() async throws {
        let bench: any DuckPeer = try BenchPeer(address: DuckBench.Address(host: "h", port: 1),
                                                errand: { _ in Data() })
        let sim: any DuckPeer = SimDuck(config: .stock(), over: .bridge, wire: { _ in nil })
        var carry: AsyncStream<Data>.Continuation!
        let inbound = AsyncStream<Data> { carry = $0 }
        carry.finish()
        let line: any DuckPeer = LinePeer(identity: DuckIdentity(name: "d", kind: .sim),
                                          over: .webRTC, inbound: inbound, wire: { _ in })
        for peer in [bench, sim, line] {
            XCTAssertFalse(peer is DuckWebRTCSignalling,
                           "\(type(of: peer)) has grown a WebRTC conformance")
        }
    }

    /// THE ONE THAT COVERS TYPES THIS TEST HAS NEVER HEARD OF. A runtime check
    /// can only ask about types somebody remembered to list, and the conformance
    /// this file is guarding against would be written by somebody who did not
    /// read this file. So the sources are read instead: every `.swift` in the
    /// package, checked for a conformance to the protocol under any of its two
    /// names.
    ///
    /// IT SKIPS RATHER THAN FAILS WHEN THE SOURCES ARE NOT THERE. `#filePath`
    /// points at a checkout, and this suite is also built into a test bundle
    /// that can be run where no checkout exists; a scan that failed in that
    /// situation would be reporting the absence of a directory as the presence
    /// of a conformance.
    func testNoTypeInTheKitConformsToTheSignallingProtocol() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // StudioKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // StudioKit
            .appendingPathComponent("Sources/StudioKit")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sources.path,
                                             isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw XCTSkip("no source checkout beside this test bundle to scan")
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 40, "the scan found almost no sources; check the path")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                // The declaration itself names its own inherited protocols and
                // is not a conformance to itself.
                if line.hasPrefix("public protocol DuckWebRTCSignalling") { continue }
                // A doc comment or a comment mentioning the name is not a
                // conformance either; only code that inherits from it is.
                let code = line.split(separator: "/", maxSplits: 1,
                                      omittingEmptySubsequences: false)[0]
                for spelling in [": DuckWebRTCSignalling", ", DuckWebRTCSignalling",
                                 ": DuckWebRTC.Signalling", ", DuckWebRTC.Signalling"] {
                    if code.contains(spelling) {
                        offenders.append("\(file.lastPathComponent):\(number + 1) \(line)")
                    }
                }
            }
        }
        XCTAssertEqual(offenders, [],
                       "Something now conforms to DuckWebRTC.Signalling. Before that is allowed "
                     + "to stand, the five unknowns it was written against have to be answered "
                     + "and struck off DuckWebRTC.twoThingsStillOpen.")
    }

    /// The scan can find something, which is the half of it a green result does
    /// not prove — a checker whose failure path has never run is a checker
    /// nobody should trust. The same matching logic, pointed at a line that
    /// really does declare a conformance.
    func testTheScanWouldNoticeAConformanceIfThereWereOne() {
        let pretend = "final class Naive: DuckWebRTC.Signalling {"
        let code = pretend.split(separator: "/", maxSplits: 1,
                                 omittingEmptySubsequences: false)[0]
        XCTAssertTrue(code.contains(": DuckWebRTC.Signalling"))
        let commented = "/// A note about : DuckWebRTC.Signalling in prose"
        let commentedCode = commented.split(separator: "/", maxSplits: 1,
                                            omittingEmptySubsequences: false)[0]
        XCTAssertFalse(commentedCode.contains(": DuckWebRTC.Signalling"))
    }
}
