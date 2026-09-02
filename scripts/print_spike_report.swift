// Print two SYNTHESISED pairing-spike reports, so the shape of the deliverable
// can be read by somebody who has never held the phone.
//
// WHY THIS EXISTS AND WHY IT IS NOT A TEST. `docs/POLLEN-ISSUE.md` asks a
// maintainer at Pollen Robotics to judge a harness they have not run, and the
// only honest way to show them what a run looks like is to render one. Nothing
// here has met a duck. Every value below is a fixture — serial
// "SYNTHETIC-0000", name "example-duck", a phone model that is not a phone —
// chosen so that no line of the output can be mistaken for a measurement, and
// the issue labels both reports SYNTHESISED three times for the same reason.
//
// It is a swiftc driver rather than an XCTest case because its product is
// TEXT somebody pastes into a public issue. A test asserts; this prints, and
// what it prints is meant to be read by a stranger. `PairingSpikeTests` still
// owns the assertions about what the readings say.
//
// It compiles the two kit files directly — no package, no build directory —
// so it runs on any machine with a Swift toolchain, including this Pi, and
// takes nothing on faith from a build product somebody else made.
//
// THE EXACT COMMAND, from the repository root:
//
//   export PATH=$HOME/swift-6.3.3/usr/bin:$PATH SWIFT_BACKTRACE=enable=no
//   swiftc -parse-as-library -O \
//       StudioKit/Sources/StudioKit/DuckLink.swift \
//       StudioKit/Sources/StudioKit/PairingSpike.swift \
//       scripts/print_spike_report.swift \
//       -o /tmp/print_spike_report \
//     && /tmp/print_spike_report
//
// `-parse-as-library` is required: neither kit file is `main.swift`, so the
// entry point is the `@main` type below rather than top-level code.

import Foundation

@main
struct PrintSpikeReport {

    // MARK: - fixtures nobody could mistake for a measurement

    /// The duck that does not exist.
    ///
    /// TEST-NET-1 FOR THE ADDRESS, `192.0.2.0/24`, WHICH RFC 5737 RESERVES FOR
    /// DOCUMENTATION and which is guaranteed never to be a real robot on a real
    /// network. The name is `example-duck` and the serial is `SYNTHETIC-0000`
    /// for the same reason: a reader who greps their fleet for either finds
    /// nothing, which is the correct answer.
    static let duck = DuckLink.Sighting(name: "example-duck",
                                        rssi: -54,
                                        address: .at("192.0.2.10"),
                                        tier: .advertisedService)

    /// Something else in the room, so the "also heard" branch of the report is
    /// shown rather than described. A name-only candidate is the weakest tier
    /// and the one most likely to be somebody's headphones.
    static let alsoHeard = DuckLink.Sighting(name: "example-duckling",
                                             rssi: -88,
                                             address: .notBroadcast,
                                             tier: .nameOnly)

    /// 2026-01-01T00:00:00Z, written as the number rather than read off a
    /// clock, so this program prints the same bytes every time it is run and a
    /// reader comparing two pastes sees only the differences that matter.
    static let firstRunStartedAt = Date(timeIntervalSince1970: 1_767_225_600)
    static let secondRunStartedAt = Date(timeIntervalSince1970: 1_767_226_200)

    static let phone = "SYNTHETIC-PHONE (no device ran this)"
    static let phoneOS = "0.0 (SYNTHETIC)"

    // MARK: - the two runs

    /// §5.5's hang, reproduced on iOS. The finding this whole exercise exists
    /// to be able to report.
    ///
    /// EVERY STEP AFTER THE READ TIMES OUT TOO, AND THAT IS THE POINT OF
    /// PRINTING IT. The harness carries on past a hung read on purpose, so a
    /// robot that answers late or answers only some calls is still described —
    /// and in this outcome each of those later steps earns
    /// `downstreamOfAnUnfinishedRead` rather than a sentence presupposing a
    /// bond that was never proven. A reader can check that here instead of
    /// taking it from a paragraph.
    ///
    /// `authenticateWritten: false` because the subscribe never completed, so
    /// the PIN was never put on any wire — and the report says exactly that
    /// rather than "PIN tried: 000000" under a write nobody made.
    static var hungRead: PairingSpike.Run {
        PairingSpike.Run(
            outcomes: [.scan: .ok(seconds: 2.41),
                       .connect: .ok(seconds: 0.88),
                       .discover: .ok(seconds: 0.31),
                       .readVersion: .timedOut(afterSeconds: 60.00),
                       .subscribe: .timedOut(afterSeconds: 10.00),
                       .hello: .timedOut(afterSeconds: 15.00),
                       .authenticate: .timedOut(afterSeconds: 15.00),
                       .systemInfo: .timedOut(afterSeconds: 15.00)],
            pairingPromptShown: true,
            requirePairing: true,
            deviceModel: phone,
            iOSVersion: phoneOS,
            robotAPIVersion: nil,
            pin: PairingSpike.factoryPIN,
            startedAt: firstRunStartedAt,
            runNumber: 1,
            sightings: [duck, alsoHeard],
            tested: duck,
            hello: nil,
            info: nil,
            lateAnswers: [:],
            notifications: [],
            authenticateWritten: false)
    }

    /// The other answer: the encrypted read completes and the whole sequence
    /// runs. This is the run that would let Pollen flip `--require-pairing` on
    /// by default and close §8.1.
    ///
    /// PRINTED BESIDE THE HANG BECAUSE A HARNESS THAT CAN ONLY REPORT BAD NEWS
    /// IS NOT A HARNESS. The two readings are produced by the same code from
    /// the same fixtures, and a maintainer deciding whether to trust the first
    /// one is entitled to see what the second looks like.
    static var cleanPass: PairingSpike.Run {
        PairingSpike.Run(
            outcomes: [.scan: .ok(seconds: 1.92),
                       .connect: .ok(seconds: 0.74),
                       .discover: .ok(seconds: 0.28),
                       .readVersion: .ok(seconds: 7.63),
                       .subscribe: .ok(seconds: 0.19),
                       .hello: .ok(seconds: 0.42),
                       .authenticate: .ok(seconds: 0.37),
                       .systemInfo: .ok(seconds: 0.44)],
            pairingPromptShown: true,
            requirePairing: true,
            deviceModel: phone,
            iOSVersion: phoneOS,
            robotAPIVersion: 16,
            pin: PairingSpike.factoryPIN,
            startedAt: secondRunStartedAt,
            runNumber: 2,
            sightings: [duck, alsoHeard],
            tested: duck,
            hello: DuckLink.Hello(apiVersion: 16,
                                  daemonVersion: "0.0.0-SYNTHETIC",
                                  revision: "0000000synthetic"),
            info: DuckLink.SystemInfo(name: "example-duck",
                                      serial: "SYNTHETIC-0000",
                                      uptimeSeconds: 3725),
            lateAnswers: [:],
            notifications: [],
            authenticateWritten: true)
    }

    // MARK: - printing

    /// The banner every report here is wrapped in.
    ///
    /// THE LABEL IS NOT DECORATION AND IT IS NOT OPTIONAL. These reports are
    /// written to be pasted into somebody else's issue tracker, where a block
    /// of plausible-looking measurements is exactly the thing a maintainer may
    /// act on. This project has already shipped one fabricated bulletin by
    /// letting a fixture look like a reading; the banner, the fixture values
    /// and the issue's own labelling are three independent chances to notice.
    static func banner(_ what: String) -> String {
        let rule = String(repeating: "#", count: 78)
        return rule + "\n"
             + "# SYNTHESISED — NOTHING HERE HAS MET A DUCK.\n"
             + "# \(what)\n"
             + "# Fixture values throughout: serial SYNTHETIC-0000, name example-duck,\n"
             + "# a phone model that is not a phone. Not a measurement of anything.\n"
             + rule + "\n"
    }

    static func main() {
        print(banner("Report 1 of 2 — what §5.5's hang would look like, reproduced on iOS."))
        print(hungRead.report())
        print(banner("Report 2 of 2 — what a clean pass would look like."))
        print(cleanPass.report())
        print(banner("End. Both reports above are SYNTHESISED. No robot was involved."))
    }
}
