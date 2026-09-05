import XCTest
@testable import StudioKit

/// L20: a log this app displays is a log their own reader would open.
///
/// WHY REFUSING IS THE FEATURE. `EvalLog.from_dict` builds frozen dataclasses
/// by keyword, so an unknown key is a `TypeError` there, measured against
/// 0.58.0 this session. A reader here that shrugged one off would let a person
/// look at a file on a phone, believe it, hand it to somebody with the real
/// library and watch it fail to open. Every refusal below is that failure
/// arriving early, with the key and the object it sat in named.
final class EvalLogReaderTests: XCTestCase {

    private func log(_ text: String) throws -> EvalLog {
        try EvalLogReader.read(Data(text.utf8))
    }

    /// A minimal log that IS valid, so every test below can change exactly one
    /// thing about it.
    private static let valid = """
    {"version": 1, "status": "success", "error": null,
     "eval": {"task": "t", "policy": "p", "embodiment": "e", "created": "c",
              "inspect_robots_version": "v", "git_commit": null,
              "policy_config": {}, "embodiment_info": {},
              "seed": null, "max_steps": 10, "max_seconds": 0.2},
     "results": {"total_scenes": 1, "total_trials": 1, "metrics": {}, "errored_trials": 0},
     "stats": {"started_at": "a", "completed_at": "b", "duration_s": 1.0,
               "total_steps": 0, "mean_inference_latency_s": null, "frames_dir": null},
     "samples": []}
    """

    func testTheValidOneIsValid() throws {
        let read = try log(Self.valid)
        XCTAssertEqual(read.version, 1)
        XCTAssertEqual(read.status, .success)
        XCTAssertEqual(read.eval.task, "t")
        XCTAssertEqual(read.stats.durationSeconds, 1.0)
    }

    // MARK: - the version

    func testAnyVersionButOneIsRefused() {
        for version in ["2", "0", "-1"] {
            let text = Self.valid.replacingOccurrences(of: "\"version\": 1",
                                                       with: "\"version\": \(version)")
            XCTAssertThrowsError(try log(text)) { error in
                guard case EvalLogRefusal.unsupportedVersion(let found) = error else {
                    return XCTFail("\(error)")
                }
                XCTAssertEqual(found, version)
            }
        }
    }

    // MARK: - unknown keys, by name AND by object

    /// The same key name in two objects is two different faults, so the message
    /// names both.
    func testAnUnknownKeyIsRefusedByNameAndByTheObjectItSatIn() throws {
        let cases: [(String, String, String)] = [
            ("\"version\": 1", "\"version\": 1, \"extra\": 3", "the log"),
            ("\"task\": \"t\"", "\"task\": \"t\", \"extra\": 3", "eval"),
            ("\"total_scenes\": 1", "\"total_scenes\": 1, \"extra\": 3", "results"),
            ("\"started_at\": \"a\"", "\"started_at\": \"a\", \"extra\": 3", "stats"),
        ]
        for (from, to, object) in cases {
            let text = Self.valid.replacingOccurrences(of: from, with: to)
            XCTAssertThrowsError(try log(text)) { error in
                guard case EvalLogRefusal.unknownKey(let key, let inside) = error else {
                    return XCTFail("\(object): \(error)")
                }
                XCTAssertEqual(key, "extra")
                XCTAssertEqual(inside, object)
                XCTAssertTrue(EvalLogRefusal.unknownKey(key, in: inside).message.contains("extra"))
                XCTAssertTrue(EvalLogRefusal.unknownKey(key, in: inside).message.contains(object))
            }
        }
    }

    func testAnUnknownKeyInASampleIsRefusedToo() {
        let text = Self.valid.replacingOccurrences(
            of: "\"samples\": []",
            with: "\"samples\": [{\"scene_id\": \"s\", \"status\": \"success\", \"extra\": 1}]")
        XCTAssertThrowsError(try log(text)) { error in
            guard case EvalLogRefusal.unknownKey(let key, let inside) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(key, "extra")
            XCTAssertEqual(inside, "a sample")
        }
    }

    // MARK: - missing and wrong

    func testARequiredFieldMissingIsNamed() {
        let text = Self.valid.replacingOccurrences(of: "\"task\": \"t\",", with: "")
        XCTAssertThrowsError(try log(text)) { error in
            guard case EvalLogRefusal.missing(let key, let inside) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(key, EvalLog.Key.task)
            XCTAssertEqual(inside, "eval")
        }
    }

    func testAStatusWordTheirVocabularyDoesNotHaveIsRefused() {
        let text = Self.valid.replacingOccurrences(of: "\"status\": \"success\"",
                                                   with: "\"status\": \"finished\"")
        XCTAssertThrowsError(try log(text)) { error in
            guard case EvalLogRefusal.wrongType(let key, _, let wanted) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(key, EvalLog.Key.status)
            XCTAssertTrue(wanted.contains("cancelled"), wanted)
        }
    }

    func testAFileThatIsNotJSONIsRefusedWithTheParsersOwnWords() {
        XCTAssertThrowsError(try log("not json at all")) { error in
            guard case EvalLogRefusal.notJSON(let why) = error else { return XCTFail("\(error)") }
            XCTAssertFalse(why.isEmpty)
        }
    }

    func testAJSONArrayIsNotALog() {
        XCTAssertThrowsError(try log("[1, 2, 3]")) { error in
            guard case EvalLogRefusal.notAnObject(let what) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(what, "the log")
        }
    }

    // MARK: - what it does read

    /// Their own log, which is the only file in this repository nobody here
    /// wrote, read through the app's door.
    func testUpstreamsOwnLogReadsThroughTheAppsDoor() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reference-cubepick",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures/evallog"))
        let read = try EvalLogReader.read(try Data(contentsOf: url))
        XCTAssertEqual(read.version, 1)
        XCTAssertEqual(read.samples.count, 4)
        XCTAssertEqual(read.eval.seed, 7, "a log written elsewhere keeps the seed it had")
        XCTAssertFalse(read.eval.inspectRobotsVersion.isEmpty)
    }

    /// Every fixture this app writes opens through the same door, so the reader
    /// and the writer cannot drift apart without a test going red.
    func testEveryFixtureThisAppWritesOpensHere() throws {
        for entry in try EvalFixtures.corpus() {
            let read = try EvalLogReader.read(entry.file.bytes)
            XCTAssertEqual(read.eval.task, entry.file.log.eval.task, entry.name)
            XCTAssertEqual(read.samples.count, entry.file.log.samples.count, entry.name)
        }
    }

    /// THE ONE PLACE THE TYPED READER IS LOSSY, stated so nobody discovers it
    /// from a missing row. A score that was not a number is null in the file,
    /// the way `_sanitize` writes it, and `[String: Double]` cannot hold a
    /// null, so the key is absent from the log that comes back. The file is
    /// unchanged either way, an imported log's bytes are never rewritten, and
    /// the writing side names the scorer through `EvalRun.nonFiniteScores`.
    func testANullMetricComesBackAsAnAbsentKeyRatherThanAsAnInventedNumber() throws {
        let file = try EvalFixtures.hostileStrings()
        let read = try EvalLogReader.read(file.bytes)
        XCTAssertNil(read.results.metrics[EvalScorer.endHeight.name])
        XCTAssertNotNil(file.log.results.metrics[EvalScorer.endHeight.name])
        XCTAssertEqual(file.log.results.metrics[EvalScorer.endHeight.name]?.isFinite, false)
        // And the file itself still says null, which is what their tools read.
        let text = try XCTUnwrap(String(data: file.bytes, encoding: .utf8))
        XCTAssertTrue(text.contains("\"end_height_m\": null"))
    }

    // MARK: - importing

    func testAnImportedFileKeepsItsOwnBytesAndCannotBePublished() throws {
        let file = try EvalFixtures.importedForeign()
        XCTAssertEqual(file.origin, .imported)
        XCTAssertFalse(file.canPublish)
        XCTAssertNil(file.wroteIt)
        XCTAssertEqual(file.importedName, "cubepick-reach_1f2e3d4c.json")
        XCTAssertEqual(file.log.eval.seed, 7)
        XCTAssertThrowsError(try file.publishCalls(namespace: "craigm26", isPrivate: false)) {
            XCTAssertEqual($0 as? EvalLogFile.Refusal, .imported)
        }
    }

    /// C6: the name a file arrived under is somebody else's string and is
    /// capped and cleaned before it can become a row title.
    func testAnImportedFilenameIsForeignText() throws {
        let hostile = String(repeating: "n", count: 400) + "\t.json"
        let file = try EvalLogFile.imported(try EvalFixtures.workedExample().bytes,
                                            named: hostile)
        let name = try XCTUnwrap(file.importedName)
        XCTAssertEqual(name.count, EvalText.cap)
        XCTAssertFalse(name.contains("\t"))
    }

    func testImportingSomethingThatIsNotALogRefusesRatherThanShowingIt() {
        XCTAssertThrowsError(try EvalLogFile.imported(Data("{}".utf8), named: "x.json")) {
            guard case EvalLogRefusal.missing = $0 else { return XCTFail("\($0)") }
        }
    }

    // MARK: - reading this phone's own log back

    /// The third constructor, and the reason it is not `imported`: a log this
    /// app wrote and then read off its own disk is still this app's, so the
    /// Imported badge stays off and publishing stays on.
    func testALogReadBackOffTheDiskIsStillOursAndCanStillBePublished() throws {
        let written = try EvalFixtures.workedExample()
        let back = try EvalLogFile.onDisk(written.bytes, named: written.name)
        XCTAssertEqual(back.origin, .written)
        XCTAssertTrue(back.canPublish)
        XCTAssertNil(back.importedName)
        XCTAssertEqual(back.name, written.name)
        XCTAssertEqual(back.log, written.log)
    }

    /// THE BYTES ARE THE FILE'S. A log read back and re encoded on the way out
    /// would be a different file from the one on disk, which is what write once
    /// exists to prevent.
    func testReadingALogBackDoesNotReEncodeIt() throws {
        let written = try EvalFixtures.workedExample()
        let back = try EvalLogFile.onDisk(written.bytes, named: written.name)
        XCTAssertEqual(back.bytes, written.bytes)
    }

    /// `wroteIt` comes out of the log rather than off the running build, so an
    /// archived file goes on naming the build that made it.
    func testWhatWroteItComesOutOfTheFileAndNotOffThisBuild() throws {
        let written = try EvalFixtures.workedExample()
        let back = try EvalLogFile.onDisk(written.bytes, named: written.name)
        XCTAssertEqual(back.wroteIt, written.wroteIt)
        XCTAssertEqual(back.wroteIt, "Microduck Studio 1.1 (58)")
        // And a log an older build wrote goes on naming that build, which is
        // the whole reason this is read rather than stamped.
        XCTAssertEqual(
            EvalRun.wroteItSaid(from: EvalRun.producerSaid(version: "0.9", build: "12")),
            "Microduck Studio 0.9 (12)")
    }

    /// A producer sentence this app did not write has no clause to lift out of
    /// it, and nil is what the share paragraph turns into `passedOnSaid`.
    func testAForeignProducerSentenceNamesNobody() throws {
        XCTAssertNil(EvalRun.wroteItSaid(from: "0.58.0"))
        XCTAssertNil(EvalRun.wroteItSaid(from: ""))
        let imported = try EvalFixtures.importedForeign()
        let back = try EvalLogFile.onDisk(imported.bytes, named: imported.name)
        XCTAssertNil(back.wroteIt)
    }

    /// The reader and the writer are the same two clauses, so a change to the
    /// sentence cannot leave the parser looking for words nothing says.
    func testTheProducerSentenceRoundTripsThroughItsOwnReader() {
        let said = EvalRun.producerSaid(version: "1.1", build: "58")
        XCTAssertEqual(EvalRun.wroteItSaid(from: said), "Microduck Studio 1.1 (58)")
        XCTAssertEqual(said, "none; written by Microduck Studio 1.1 (58). "
                           + "No inspect-robots ran: an iPhone cannot run Python.")
    }
}
