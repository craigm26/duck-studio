import XCTest
@testable import StudioKit

/// THE EM-DASH PIN. No sentence a person reads may contain U+2014.
///
/// It reads every string literal in StudioKit's sources (comments are not
/// sentences and are skipped) and counts em-dashes per file.
///
/// - A file that declares a Words enum, and every file on `strict`, has none.
/// - Every other file has exactly its count in `baseline`, which is the debt
///   recorded on 2026-11-04. A file can only go down: a new em-dash fails, and
///   so does a fixed one until its count here is lowered, so the list shrinks
///   to nothing and never grows.
final class NoEmDashTests: XCTestCase {

    static let dash: Unicode.Scalar = "\u{2014}"

    /// Files that must have none, whether or not they declare a Words enum.
    static let strict: Set<String> = [
        "Onboarding.swift", "ScreenHierarchy.swift", "FirstRun.swift", "Provenance.swift",
        "Learn.swift", "DuckTalk.swift", "DuckOrder.swift", "StopPath.swift",
        "StopWords.swift", "DuckOrderMatcher.swift", "ControlArbiter.swift",
        "ControllerWords.swift",
    ]

    /// Em-dashes inside string literals, per file, on 2026-11-04.
    static let baseline: [String: Int] = [
        "BallChallenge.swift": 29,
        "BallEntrants.swift": 3,
        "BallGrid.swift": 1,
        "BallScore.swift": 4,
        "BallSubmission.swift": 5,
        "BenchPeer.swift": 8,
        "BenchSetup.swift": 12,
        "BridgeDrive.swift": 8,
        "BridgeHandshake.swift": 5,
        "CameraAvailability.swift": 3,
        "ChatDraft.swift": 6,
        "ChatWire.swift": 1,
        "Choreography.swift": 13,
        "ClipNote.swift": 3,
        "CommunityShare.swift": 9,
        "ControlShelf.swift": 6,
        "DeviceCard.swift": 12,
        "DraftGate.swift": 1,
        "DraftRouting.swift": 6,
        "DriveVenue.swift": 13,
        "DuckAuthority.swift": 3,
        "DuckBench.swift": 3,
        "DuckBenchChase.swift": 1,
        "DuckDrive.swift": 7,
        "DuckGolf.swift": 1,
        "DuckIntentPlan.swift": 1,
        "DuckLineSequence.swift": 3,
        "DuckLink.swift": 6,
        "DuckPad.swift": 14,
        "DuckPadMap.swift": 9,
        "DuckPeer.swift": 2,
        "DuckPlanFile.swift": 1,
        "DuckPolicyInstall.swift": 1,
        "DuckQuickActions.swift": 5,
        "DuckSequence.swift": 8,
        "DuckSubscription.swift": 4,
        "DuckTuner.swift": 28,
        "DuckWebRTC.swift": 3,
        "DuckWorld.swift": 11,
        "FetchRun.swift": 1,
        "FlamingoHold.swift": 1,
        "FollowMe.swift": 1,
        "HubTraining.swift": 3,
        "HuggingFacePublish.swift": 3,
        "IntentDraft.swift": 6,
        "IntentExport.swift": 1,
        "JointGroup.swift": 2,
        "JointHandles.swift": 1,
        "LabCatalogue.swift": 4,
        "LinePeer.swift": 1,
        "MimicSource.swift": 3,
        "ModelEndpoint.swift": 8,
        "MotionProposal.swift": 1,
        "MotionPublication.swift": 8,
        "MotionTweak.swift": 4,
        "MoveSearch.swift": 12,
        "MultiDuck.swift": 1,
        "ObservationPreset.swift": 1,
        "ObservationSlot.swift": 20,
        "PadPilot.swift": 3,
        "PairingSpike.swift": 54,
        "PhoneBenchReport.swift": 14,
        "PhoneModel.swift": 5,
        "PhoneModelInstall.swift": 6,
        "PhoneModelSearch.swift": 5,
        "Pipeline.swift": 6,
        "PolicyBlend.swift": 6,
        "PolicyCatalogue.swift": 7,
        "PolicyLibrary.swift": 2,
        "PolicyManifest.swift": 1,
        "PolicyNaming.swift": 1,
        "PolicyPublication.swift": 4,
        "PolicyReport.swift": 3,
        "PreferenceSearch.swift": 4,
        "Reachability.swift": 12,
        "Retrieval.swift": 12,
        "RunMetrics.swift": 9,
        "RunSeries.swift": 4,
        "SequenceProposal.swift": 5,
        "SimDuck.swift": 9,
        "Slalom.swift": 1,
        "SoundStaging.swift": 2,
        "StageCamera.swift": 1,
        "StageCaption.swift": 8,
        "StairsChallenge.swift": 14,
        "StairsMove.swift": 1,
        "StairsScore.swift": 2,
        "StairsStrategy.swift": 3,
        "StairsSubmission.swift": 6,
        "TrainingRequest.swift": 17,
        "TrickRun.swift": 1,
        "WeightSearch.swift": 6,
    ]

    static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // StudioKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StudioKit
            .appendingPathComponent("Sources/StudioKit")
    }

    static func sources() throws -> [(name: String, text: String)] {
        let dir = sourceDirectory
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        return try names.map { ($0, try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8)) }
    }

    func testTheScannerReadsLiteralsAndSkipsComments() {
        let sample = """
        // a comment \u{2014} skipped
        /* block \u{2014} /* nested \u{2014} */ still \u{2014} */
        let a = "one \u{2014} two"
        let b = "no dash \\(x ? "in \u{2014} interpolation" : "") here"
        let c = #"raw \u{2014} "quoted" \\#(y)"#
        let d = \"\"\"
            multi \u{2014} line
            \"\"\"
        let e = "escaped \\" quote \u{2014}"
        """
        let found = Self.literals(in: sample)
        XCTAssertEqual(found.map { $0.unicodeScalars.filter { $0 == Self.dash }.count }.reduce(0, +), 4, "\(found)")
        XCTAssertTrue(found.contains("one \u{2014} two"), "\(found)")
    }

    func testWordsEnumsAndStrictFilesHaveNoEmDash() throws {
        let declaresWords = try NSRegularExpression(pattern: #"\benum\s+\w*Words\b"#)
        var checked = 0
        for (name, text) in try Self.sources() {
            let range = NSRange(text.startIndex..., in: text)
            guard Self.strict.contains(name) || declaresWords.firstMatch(in: text, range: range) != nil
            else { continue }
            checked += 1
            for literal in Self.literals(in: text) where literal.unicodeScalars.contains(Self.dash) {
                XCTFail("\(name): \(literal)")
            }
        }
        XCTAssertGreaterThan(checked, Self.strict.count, "the Words enums were not found")
    }

    func testNoFileGainsAnEmDashAndFixedOnesLowerTheBaseline() throws {
        var seen = Set<String>()
        for (name, text) in try Self.sources() {
            seen.insert(name)
            let count = Self.literals(in: text)
                .map { $0.unicodeScalars.filter { $0 == Self.dash }.count }.reduce(0, +)
            let allowed = Self.baseline[name] ?? 0
            if count > allowed {
                XCTFail("\(name) has \(count) em-dashes in its strings, \(allowed) allowed. "
                        + "Use a colon, a comma, parentheses or a full stop.")
            } else if count < allowed {
                XCTFail("\(name) is down to \(count) em-dashes: lower its baseline from \(allowed).")
            }
        }
        for name in Self.baseline.keys where !seen.contains(name) {
            XCTFail("\(name) is in the baseline but no longer exists: remove it.")
        }
        XCTAssertTrue(Self.baseline.keys.allSatisfy { !Self.strict.contains($0) })
    }

    // MARK: A small Swift string-literal reader

    /// The contents of every string literal in `source`, comments skipped.
    /// Interpolations are skipped too, including string literals inside them.
    static func literals(in source: String) -> [String] {
        let s = Array(source.unicodeScalars)
        let n = s.count
        var out: [String] = []
        var i = 0

        func at(_ k: Int, _ text: String) -> Bool {
            let t = Array(text.unicodeScalars)
            guard k + t.count <= n else { return false }
            for (j, c) in t.enumerated() where s[k + j] != c { return false }
            return true
        }

        while i < n {
            if at(i, "//") {
                while i < n && s[i] != "\n" { i += 1 }
                continue
            }
            if at(i, "/*") {
                var depth = 1; i += 2
                while i < n && depth > 0 {
                    if at(i, "/*") { depth += 1; i += 2 }
                    else if at(i, "*/") { depth -= 1; i += 2 }
                    else { i += 1 }
                }
                continue
            }
            var hashes = 0
            if s[i] == "#" {
                var k = i
                while k < n && s[k] == "#" { k += 1 }
                guard k < n && s[k] == "\"" else { i += 1; continue }
                hashes = k - i; i = k
            }
            guard s[i] == "\"" else { i += 1; continue }
            let quote = at(i, "\"\"\"") ? "\"\"\"" : "\""
            let close = quote + String(repeating: "#", count: hashes)
            let pounds = String(repeating: "#", count: hashes)
            i += quote.unicodeScalars.count
            var text = String.UnicodeScalarView()
            while i < n && !at(i, close) {
                if s[i] == "\\" && at(i + 1, pounds) {
                    var j = i + 1 + hashes
                    if j < n && s[j] == "(" {
                        var depth = 1; j += 1
                        while j < n && depth > 0 {
                            if s[j] == "(" { depth += 1 }
                            else if s[j] == ")" { depth -= 1 }
                            else if s[j] == "\"" {
                                j += 1
                                while j < n && s[j] != "\"" {
                                    if s[j] == "\\" { j += 1 }
                                    j += 1
                                }
                            }
                            j += 1
                        }
                        i = j
                        continue
                    }
                    if j < n { text.append(s[i]); text.append(contentsOf: s[(i + 1)...j]) }
                    i = j + 1
                    continue
                }
                text.append(s[i]); i += 1
            }
            out.append(String(text))
            i += close.unicodeScalars.count
        }
        return out
    }
}
