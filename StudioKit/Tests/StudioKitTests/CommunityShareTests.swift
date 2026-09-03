import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

final class CommunityShareTests: XCTestCase {

    private func entry(named name: String) throws -> PolicyLibrary.Entry {
        let folder = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/policies",
                                                     withExtension: nil))
        let data = try Data(contentsOf: folder.appendingPathComponent(name))
        return PolicyLibrary.entry(for: data, name: name, origin: .imported)
    }

    func testEveryDestinationIsHttpsAndNamed() {
        for destination in CommunityShare.destinations {
            XCTAssertEqual(destination.url.scheme, "https", destination.name)
            XCTAssertFalse(destination.purpose.isEmpty, destination.name)
        }
        XCTAssertTrue(CommunityShare.discord.url.absoluteString
            .hasPrefix("https://discord.com/channels/519098054377340948/"))
    }

    /// The app cannot post and must not imply it can.
    func testItSaysPlainlyThatNothingIsPostedForYou() {
        XCTAssertTrue(CommunityShare.cannotPostNote.contains("Nothing is posted for you"))
        XCTAssertTrue(CommunityShare.cannotPostNote.contains("no account"))
    }

    /// An unrecognised policy is described as unrecognised. The person pasting
    /// this is about to ask strangers to run it on a robot.
    func testAnUnrecognisedPolicyIsNotSoftened() throws {
        // A perfectly loadable network that this build's manifest has never
        // seen — somebody's own training run, which is the common case.
        let entry = try entry(named: "alpha_walking.onnx")
        let message = CommunityShare.message(forPolicy: entry, standing: .unrecognised)
        XCTAssertTrue(message.contains("not one of the nine"), message)
        XCTAssertTrue(message.contains("check the fingerprint"), message)
        // Never a word this app cannot establish.
        for forbidden in ["safe", "trusted", "verified", " official"] {
            XCTAssertFalse(message.lowercased().contains(forbidden),
                           "\"\(forbidden)\" is a claim nothing here can support: \(message)")
        }
    }

    /// A file that will not parse has no fingerprint, so the message says there
    /// is nothing to check rather than inventing something.
    func testAFileThatDoesNotLoadOffersNothingCheckable() {
        let entry = PolicyLibrary.entry(for: Data("not a policy".utf8),
                                        name: "broken.onnx", origin: .imported)
        let message = CommunityShare.message(forPolicy: entry, standing: .unrecognised)
        XCTAssertTrue(message.contains("does not load"))
        // Look for an actual digest rather than for the word: the message is
        // allowed — required, in fact — to SAY there is no fingerprint.
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        let looksLikeADigest = message.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .contains { $0.count == 64 && $0.unicodeScalars.allSatisfy(hex.contains) }
        XCTAssertFalse(looksLikeADigest, "it must not offer a digest it does not have")
    }

    /// A released policy is described by what the manifest actually recorded.
    func testAReleasedPolicyQuotesTheReleaseRatherThanTheFilename() throws {
        let entry = try entry(named: "roulade.onnx")
        guard case .parameters(let fingerprint) = entry.identity else {
            return XCTFail("roulade loads")
        }
        let standing = DuckOfficialPolicies.standing(ofFingerprint: fingerprint)
        let message = CommunityShare.message(forPolicy: entry, standing: standing)
        XCTAssertTrue(message.contains(fingerprint))
        XCTAssertTrue(message.contains("match Pollen's released"), message)
        XCTAssertTrue(message.contains("forward roll"), message)
    }

    /// A negative result is worth sending, and sending it without the number
    /// is not.
    func testAMotionCarriesHowOftenItWorks() throws {
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["climb"])
        let export = IntentExport(clip: clip, policyFingerprint: "abc123")
        let outcome = try XCTUnwrap(try DuckIntentSuccess.bundled()["climb"])
        let message = CommunityShare.message(forIntent: export, outcome: outcome)
        XCTAssertTrue(message.contains("never met") || message.contains("never"), message)
        XCTAssertTrue(message.contains("on the flight"), message)
        XCTAssertTrue(message.contains("abc123"))
        XCTAssertTrue(message.contains("filename proves nothing"))
    }

    func testAMotionWithNoMeasurementSaysSoRatherThanImplyingItWorks() throws {
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["climb"])
        let message = CommunityShare.message(
            forIntent: IntentExport(clip: clip, policyFingerprint: nil), outcome: nil)
        XCTAssertTrue(message.contains("cannot tell you how often it works"), message)
        XCTAssertTrue(message.contains("hint and not a claim"), message)
    }

    /// An authored motion must not go out looking like a recording.
    func testAnAuthoredMotionIsLabelledAsOne() {
        let message = CommunityShare.message(forDraft: .blank(named: "wave"))
        XCTAssertTrue(message.contains("AUTHORED"))
        XCTAssertTrue(message.contains("no physics ran"))
    }

    // MARK: - a nickname is labelled as one the one time it leaves the phone

    /// A title somebody typed means something to them and nothing to a
    /// recipient. Leading with it as if it were the file's name would be this
    /// app exporting a private label as a public fact.
    func testAPersonsOwnNameIsMarkedAsTheirsInTheSharedMessage() throws {
        let folder = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/policies",
                                                     withExtension: nil))
        let data = try Data(contentsOf: folder.appendingPathComponent("roulade.onnx"))
        let entry = PolicyLibrary.entry(
            for: data, name: "spin.onnx", origin: .imported,
            nameplate: PolicyNameplate(fileName: "spin.onnx", title: "Waddle v3"),
            manifest: nil, arrivalWasRecorded: true)
        let message = CommunityShare.message(forPolicy: entry, standing: .unrecognised)
        XCTAssertTrue(message.hasPrefix("Waddle v3 — a Microduck policy."), message)
        XCTAssertTrue(message.contains("That is what I call it here."), message)
        XCTAssertTrue(message.contains("spin.onnx"), message)
    }

    func testAFileThatWasNeverRenamedSharesUnderItsFileName() throws {
        let entry = try entry(named: "alpha_walking.onnx")
        let message = CommunityShare.message(forPolicy: entry, standing: .unrecognised)
        XCTAssertEqual(message.components(separatedBy: "\n\n").first,
                       "alpha_walking.onnx — a Microduck policy.")
        XCTAssertFalse(message.contains("what I call it"),
                       "nobody named this one, so there is no nickname to disclose")
    }

    /// THE FINGERPRINT IS STILL THE PART ANYBODY CAN CHECK, and adding a
    /// sentence about a nickname must not push it out of the message.
    func testTheShareMessageStillLeadsWithTheFingerprint() throws {
        let folder = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/policies",
                                                     withExtension: nil))
        let data = try Data(contentsOf: folder.appendingPathComponent("roulade.onnx"))
        let entry = PolicyLibrary.entry(
            for: data, name: "spin.onnx", origin: .imported,
            nameplate: PolicyNameplate(fileName: "spin.onnx", title: "Waddle v3"),
            manifest: nil, arrivalWasRecorded: true)
        guard case .parameters(let fingerprint) = entry.identity else {
            return XCTFail("roulade loads")
        }
        let message = CommunityShare.message(forPolicy: entry, standing: .unrecognised)
        XCTAssertTrue(message.contains(fingerprint), message)
    }
}
