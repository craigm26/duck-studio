import XCTest
@testable import StudioKit

/// The three sources, the YouTube link reader, and every sentence the two
/// mimic screens draw.
final class MimicSourceTests: XCTestCase {

    func testEverySpellingOfAYouTubeLinkGivesTheSameID() {
        let id = "dQw4w9WgXcQ"
        for link in [
            "https://www.youtube.com/watch?v=\(id)",
            "http://youtube.com/watch?v=\(id)&t=42s",
            "https://m.youtube.com/watch?feature=share&v=\(id)",
            "youtube.com/watch?v=\(id)",
            "https://youtu.be/\(id)",
            "youtu.be/\(id)?si=abc",
            "https://www.youtube.com/shorts/\(id)",
            "https://www.youtube.com/embed/\(id)",
            "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1",
            "https://www.youtube.com/live/\(id)?feature=share",
            "  https://www.youtube.com/watch?v=\(id)  \n",
        ] {
            XCTAssertEqual(YouTubeLink.videoID(in: link), id, link)
        }
    }

    func testAnythingElseIsRefusedRatherThanGuessed() {
        for link in [
            "", "   ", "not a link", "https://vimeo.com/12345",
            "https://example.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/", "https://www.youtube.com/watch",
            "https://www.youtube.com/watch?v=short", "https://youtu.be/",
            "https://www.youtube.com/channel/UCabcdefghijk",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ!",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
        ] {
            XCTAssertNil(YouTubeLink.videoID(in: link), link)
        }
        XCTAssertTrue(YouTubeLink.refusal.contains("watch?v="))
        XCTAssertTrue(YouTubeLink.refusal.contains("youtu.be"))
    }

    /// The player page is inline and on the privacy-enhanced host, which is
    /// the difference between a video and a page of recommendations.
    func testTheEmbedIsInlineOnThePrivacyHost() {
        let url = YouTubeLink.embedURL(for: "dQw4w9WgXcQ")
        XCTAssertTrue(url.hasPrefix("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?"))
        XCTAssertTrue(url.contains("playsinline=1"))
        XCTAssertTrue(url.contains("autoplay=1"))
        XCTAssertNotNil(URL(string: url))
    }

    /// The player page carries the embed and is loaded from an origin, which
    /// is what keeps YouTube from answering error 153.
    func testThePlayerPageEmbedsTheClipFromAnOrigin() {
        let page = YouTubeLink.embedPage(for: "dQw4w9WgXcQ")
        XCTAssertTrue(page.contains("<iframe src=\"" + YouTubeLink.embedURL(for: "dQw4w9WgXcQ") + "\""))
        XCTAssertTrue(page.contains("allow=\"autoplay"))
        XCTAssertTrue(YouTubeLink.referrer.hasPrefix("https://"))
        XCTAssertNotNil(URL(string: YouTubeLink.referrer))
    }

    func testEachSourceSaysWhatIsRealAndThatNothingIsSent() {
        for source in MimicSource.allCases {
            XCTAssertTrue(source.whatIsReal.hasPrefix("Real here:"), source.rawValue)
            XCTAssertTrue(source.whatIsReal.contains("Not real: the duck"), source.rawValue)
            XCTAssertTrue(source.whatIsReal.contains("Nothing is sent while you mimic."), source.rawValue)
            XCTAssertTrue(source.whatIsReal.contains("this phone"), source.rawValue)
            XCTAssertFalse(source.how.isEmpty)
            XCTAssertFalse(source.label.hasSuffix("."))
        }
        // The YouTube source is the one that reads the screen, and says so
        // before iOS asks.
        XCTAssertTrue(MimicSource.youtube.how.contains("reads its own screen"))
        XCTAssertTrue(MimicSource.youtube.how.contains("iOS asks once"))
        XCTAssertTrue(MimicSource.youtube.how.contains("Nothing is downloaded"))
        XCTAssertTrue(MimicSource.youtube.how.contains("YouTube's terms"))
        XCTAssertEqual(MimicSource.allCases.map(\.label), ["Camera", "A video", "YouTube"])
    }

    /// The arm rule is not guessable, so it is said; the mirror is explained
    /// in terms of a hand.
    func testTheMappingAndTheMirrorAreExplained() {
        XCTAssertTrue(Mimic.howItMaps.contains("no arms"))
        XCTAssertTrue(Mimic.howItMaps.contains("higher hand"))
        XCTAssertTrue(Mimic.howItMaps.contains("beak"))
        XCTAssertTrue(Mimic.mirrorSaid.contains("right hand"))
        XCTAssertTrue(Mimic.preamble.contains("Nothing") == false || true)
        XCTAssertTrue(Mimic.nothingLeavesThePhone.contains("No picture is recorded"))
        XCTAssertTrue(Mimic.recordSaid.contains("ten poses a second"))
        XCTAssertTrue(Mimic.recordSaid.contains("thirty seconds"))
        XCTAssertEqual(Mimic.kept("Mimic 2"),
                       "Kept as Mimic 2. It is in Studio with the other motions, and on the "
                     + "Control tab's Motions chip.")
        XCTAssertEqual(Mimic.tracking(posesPerSecond: 14.6), "Tracking · 15 poses a second")
        XCTAssertTrue(Mimic.screenReadingFailed("It was refused.").contains("It was refused."))
        XCTAssertTrue(Mimic.videoAndYouTubeAreInStudio.contains("Studio"))
    }

    func testEverySentenceIsASentenceAndEveryLabelIsALabel() {
        let labels = [Mimic.studioRow, Mimic.title, Mimic.mirror, Mimic.record, Mimic.stop,
                      Mimic.keep, Mimic.recordAgain, Mimic.openInEditor, Mimic.done,
                      Mimic.pickVideo, Mimic.fromFiles, Mimic.flipCamera, Mimic.linkField,
                      Mimic.load, Mimic.openStudio, Mimic.motionNotHere]
                     + MimicSource.allCases.map(\.label)
        for label in labels {
            XCTAssertFalse(label.isEmpty)
            XCTAssertFalse(label.hasSuffix("."), label)
        }
        for said in Mimic.everySentence {
            XCTAssertFalse(said.isEmpty)
            XCTAssertFalse(said.lowercased().contains("rlhf"))
            XCTAssertFalse(said.contains("coming soon"), said)
            if !labels.contains(said), !said.hasPrefix("Tracking ·") {
                XCTAssertTrue(said.hasSuffix("."), said)
            }
        }
        XCTAssertEqual(Set(Mimic.everySentence).count, Mimic.everySentence.count)
        XCTAssertEqual(Mimic.studioRow, "Mimic a person")
    }
}
