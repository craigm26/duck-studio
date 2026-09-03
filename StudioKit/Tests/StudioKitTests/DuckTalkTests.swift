import XCTest
import DuckKit
@testable import StudioKit

/// The deterministic grammar, which runs before any model does.
///
/// EVERY GUESS IS NAMED. The interesting assertions here are not that "forward
/// for two seconds" reads — they are that a missing time, a missing speed and
/// an angle each produce a sentence saying what was assumed and why, because a
/// reader that quietly filled in a number would be a reader nobody could check.
final class DuckTalkTests: XCTestCase {

    func testForwardForTwoSecondsIsReadWithoutAModel() {
        let reading = DuckTalk.read("forward for two seconds")
        XCTAssertEqual(reading.moves.count, 1)
        XCTAssertEqual(reading.moves[0].go, "forward")
        XCTAssertEqual(reading.moves[0].seconds, 2, accuracy: 1e-9)
        XCTAssertNotEqual(reading.confidence, .notUnderstood)
    }

    func testThenChainsMovesInTheOrderTheyWereSaid() {
        let reading = DuckTalk.read("forward for two seconds then turn left")
        XCTAssertEqual(reading.moves.map(\.go), ["forward", "turn left"])
    }

    func testCommasAndAndBothChain() {
        XCTAssertEqual(DuckTalk.read("forward, turn left and stop").moves.map(\.go),
                       ["forward", "turn left", "stop"])
        XCTAssertEqual(DuckTalk.read("forward and then back").moves.map(\.go),
                       ["forward", "back"])
    }

    func testAMissingTimeIsNamedAsAnAssumptionRatherThanHidden() {
        let reading = DuckTalk.read("forward")
        XCTAssertEqual(reading.moves[0].seconds, DuckTalk.defaultSeconds)
        XCTAssertTrue(reading.assumed.contains(DuckTalk.timeAssumed("forward")),
                      "\(reading.assumed)")
        XCTAssertEqual(reading.confidence, .understoodWithGuesses)
    }

    func testAMissingSpeedIsNamedAsAnAssumption() {
        let reading = DuckTalk.read("forward for two seconds")
        XCTAssertNil(reading.moves[0].speed)
        XCTAssertTrue(reading.assumed.contains(DuckTalk.speedAssumed("forward")),
                      "\(reading.assumed)")
    }

    func testASpokenSpeedIsUnderstoodRatherThanAssumed() {
        let reading = DuckTalk.read("forward gently")
        XCTAssertEqual(reading.moves[0].speed, DuckTalk.gently)
        XCTAssertTrue(reading.understood.contains(DuckTalk.speedUnderstood(DuckTalk.gently)),
                      "\(reading.understood)")
        XCTAssertFalse(reading.assumed.contains(DuckTalk.speedAssumed("forward")))
    }

    func testGentlyHalvesAndSaysNothingElseChanged() {
        let reading = DuckTalk.read("forward gently for two seconds")
        XCTAssertEqual(reading.moves[0].speed, DuckTalk.gently)
        XCTAssertEqual(reading.moves[0].seconds, 2, accuracy: 1e-9)
        XCTAssertTrue(reading.assumed.isEmpty, "\(reading.assumed)")
        XCTAssertTrue(reading.unread.isEmpty, "\(reading.unread)")
        XCTAssertEqual(reading.confidence, .understood)
        // "a bit" and "slowly" are the same word to the reader.
        XCTAssertEqual(DuckTalk.read("forward a bit").moves[0].speed, DuckTalk.gently)
        XCTAssertEqual(DuckTalk.read("forward slowly").moves[0].speed, DuckTalk.gently)
    }

    func testDegreesBecomeSecondsAndTheAssumptionIsLoudAboutRateVersusAngle() {
        let reading = DuckTalk.read("turn left 90 degrees")
        XCTAssertEqual(reading.moves.count, 1)
        XCTAssertEqual(reading.moves[0].go, "turn left")
        XCTAssertEqual(reading.moves[0].seconds,
                       (90 * Double.pi / 180) / DuckDrive.maxTurn, accuracy: 1e-9)
        let loud = reading.assumed.first { $0.contains("degrees") }
        XCTAssertNotNil(loud, "\(reading.assumed)")
        XCTAssertTrue(loud?.contains("a rate, not an angle") ?? false, loud ?? "")
        // The degree sign is the same word.
        XCTAssertEqual(DuckTalk.read("turn right 90°").moves[0].seconds,
                       reading.moves[0].seconds, accuracy: 1e-9)
    }

    func testTheUnreadPartsAreNamedInTheSentence() {
        let reading = DuckTalk.read("forward for two seconds xyzzy")
        XCTAssertEqual(reading.unread, ["xyzzy"])
        XCTAssertEqual(reading.confidence, .understoodWithGuesses)
        let named = DuckTalk.notRead(reading.unread)
        XCTAssertNotNil(named)
        XCTAssertTrue(named!.contains("xyzzy"), named!)
        XCTAssertNil(DuckTalk.notRead([]), "and nothing is said when nothing was missed")
    }

    func testASentenceItCannotReadOffersTheVocabularyAndTheThreeModelRoutes() {
        let reading = DuckTalk.read("please do a barrel roll")
        XCTAssertEqual(reading.confidence, .notUnderstood)
        XCTAssertTrue(reading.moves.isEmpty)
        let sentence = reading.sentence
        XCTAssertTrue(sentence.contains("Apple"), sentence)
        XCTAssertTrue(sentence.contains("downloaded"), sentence)
        XCTAssertTrue(sentence.contains("OpenAI"), sentence)
        XCTAssertTrue(sentence.contains(DuckTalk.vocabulary), sentence)
    }

    /// BOTH DIRECTIONS. The words a person is offered and the words that
    /// resolve are built from one table, so they cannot drift apart.
    func testTheVocabularySentenceIsBuiltFromTheTableItMatches() {
        for word in DuckTalk.vocabulary.components(separatedBy: ", ") {
            XCTAssertNotEqual(DuckTalk.read(word).confidence, .notUnderstood,
                              "\"\(word)\" is offered and does not resolve")
        }
        for word in SequenceProposal.offeredWords {
            XCTAssertTrue(DuckTalk.vocabulary.contains(word),
                          "\"\(word)\" resolves and is not offered")
        }
    }

    /// ANCHORED, AND THE ONE STRING ALLOWED TO CONTAIN "understand" IS THE ONE
    /// DENYING IT. Nothing on this surface may claim the duck read anything.
    func testNothingHereClaimsTheDuckUnderstood() {
        let claiming = DuckTalk.allSentences.filter { $0.contains("understand") }
        XCTAssertEqual(claiming.count, 1, "\(claiming)")
        XCTAssertTrue(claiming[0].contains("could not read that as driving"), claiming[0])
        XCTAssertTrue(DuckTalk.notAModel.contains("No model was asked"))
    }

    func testEveryBranchOfTheReadingSentenceIsReachable() {
        XCTAssertEqual(DuckTalk.read("forward gently for two seconds").confidence, .understood)
        XCTAssertEqual(DuckTalk.read("forward").confidence, .understoodWithGuesses)
        XCTAssertEqual(DuckTalk.read("please do a barrel roll").confidence, .notUnderstood)
        var seen = Set<String>()
        for sentence in ["forward gently for two seconds", "forward", "barrel roll"] {
            seen.insert(DuckTalk.read(sentence).sentence)
        }
        XCTAssertEqual(seen.count, 3, "three branches, three different sentences")
    }

    func testTheTimesAPersonActuallyTypesAllRead() {
        for (typed, seconds) in [("forward for 2s", 2.0), ("forward 2 seconds", 2.0),
                                 ("forward for half a second", 0.5),
                                 ("forward for a second", 1.0),
                                 ("forward for 1.5 seconds", 1.5)] {
            XCTAssertEqual(DuckTalk.read(typed).moves.first?.seconds, seconds,
                           "\"\(typed)\"")
        }
    }

    func testATurnIsAYawAndABareLeftIsAStrafe() {
        XCTAssertEqual(DuckTalk.read("left").moves[0].go, "left")
        XCTAssertEqual(DuckTalk.read("turn left").moves[0].go, "turn left")
        XCTAssertEqual(DuckTalk.read("spin right").moves[0].go, "turn right")
        XCTAssertEqual(DuckTalk.read("rotate left").moves[0].go, "turn left")
    }

    func testWithoutAModelOffersTheWordsItDoesRead() {
        XCTAssertTrue(DuckTalk.withoutAModel.contains(DuckTalk.vocabulary))
        XCTAssertTrue(DuckTalk.withoutAModel.contains("add a model in Settings"))
    }

    func testTheSecondsAreSaidToBeTheBenchsClock() {
        XCTAssertTrue(DuckTalk.simSecondsNote.contains("the bench's clock"))
    }
}
