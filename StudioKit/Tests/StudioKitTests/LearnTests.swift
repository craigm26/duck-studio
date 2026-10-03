import XCTest
@testable import StudioKit

final class LearnTests: XCTestCase {

    /// DRIVING COMES FIRST AND "EVERYTHING" COMES LAST. The whole point of the
    /// path is the order.
    func testThePathStartsAtDrivingAndEndsAtEverything() {
        XCTAssertEqual(Learn.lessons.first?.go, .play)
        XCTAssertEqual(Learn.lessons.last?.go, .everything)
        let training = Learn.lessons.firstIndex { $0.id == "training" }!
        let make = Learn.lessons.firstIndex { $0.id == "make" }!
        XCTAssertLessThan(training, make, "how it is trained comes before making your own")
    }

    /// ONE IDEA EACH. A lesson that needs more than about fifty words is two.
    func testEveryLessonIsShort() {
        for lesson in Learn.lessons {
            XCTAssertLessThanOrEqual(lesson.body.split(separator: " ").count, 50, lesson.id)
            XCTAssertLessThanOrEqual(lesson.title.count, 30, lesson.id)
        }
    }

    /// A button always says where it goes, and a destination always has one.
    func testButtonsAndDestinationsComeTogether() {
        for lesson in Learn.lessons {
            XCTAssertEqual(lesson.button == nil, lesson.go == nil, lesson.id)
        }
        XCTAssertEqual(Set(Learn.lessons.map(\.id)).count, Learn.lessons.count)
    }

    /// THE TRAINING LESSON STATES THE FACTS THE REST OF THE APP PINS: the
    /// simulator, the shape of the network and the rate it runs at. The body
    /// stays plain; the numbers live in its "How it works" fold.
    func testTheTrainingLessonMatchesTheNetwork() throws {
        let lesson = Learn.lessons.first { $0.id == "training" }!
        XCTAssertTrue(lesson.body.contains("reinforcement learning"))
        XCTAssertFalse(lesson.body.contains("mjlab"), "jargon stays out of the body")
        let how = try XCTUnwrap(lesson.howItWorks)
        XCTAssertTrue(how.contains("mjlab"))
        XCTAssertTrue(how.contains("61"))
        XCTAssertTrue(how.contains("14 joints"))
        XCTAssertTrue(how.contains("50 times a second"))
    }

    /// Two lessons open Play, so their buttons must not read the same.
    func testButtonLabelsAreDistinct() {
        let labels = Learn.lessons.compactMap(\.button)
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    /// Nothing claims the phone trains from scratch.
    func testNothingClaimsThePhoneTrains() {
        let text = Learn.lessons.map(\.body).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("cannot train from scratch"))
    }

    func testProgressCountsAgainstTheWholePath() {
        XCTAssertEqual(Learn.progress(done: 2), "2 of \(Learn.lessons.count) done")
    }
}
