import XCTest
@testable import StudioKit

/// The key-pattern grep, extended to local planners (brains-layer.md 6.2 logs and 6.6).
///
/// A LOCAL TOKEN CAN BE ANY STRING, so `KeyScrub`'s vendor patterns cannot be the only check:
/// "letmein-mac-studio" matches none of them. Every case here also greps for the exact token.
/// In a separate file so it does not collide with PR #73's additions to the same test class.
extension GateKeyExportTests {

    static let localTokens = fakeKeys + ["letmein-mac-studio-2026", "0123456789abcdef-own-token"]

    func testNoLocalTokenLeavesInDescriptionsErrorsOrDecisions() async throws {
        for token in Self.localTokens {
            let echo = "token " + token + " was rejected"
            let quoted = String(decoding: try JSONSerialization.data(withJSONObject: [echo]), as: UTF8.self).dropFirst().dropLast()
            // A planner's own description, reflection and dump.
            let quiet = try LocalFixtures.planner(StubLocalHTTP(json: "{}"), key: token)
            var dumped = ""
            dump(quiet, to: &dumped)
            var texts = [String(describing: quiet), String(reflecting: quiet), dumped, quiet.info.id, quiet.info.modelVersion,
                         quiet.info.label, String(describing: quiet.endpoint)]

            // A server that echoes the token in a refusal, in an auth failure, in its reason and
            // in the model name it reports.
            let refuses = StubLocalHTTP(status: 400, json: #"{"error":\#(quoted)}"#)
            do {
                _ = try await LocalFixtures.planner(refuses, key: token, mode: .promptOnly).decide(LocalFixtures.ask())
                XCTFail("did not throw")
            } catch { texts += [String(describing: error), (error as? LocalPlannerError)?.says ?? ""] }
            let auth = StubLocalHTTP(status: 401, json: #"{"error":\#(quoted)}"#)
            do {
                _ = try await LocalFixtures.planner(auth, key: token).decide(LocalFixtures.ask())
            } catch { texts.append(String(describing: error)) }
            let reason = #"{"kind":"turn","degrees":10,"why":"\#(token)"}"#
            let chatty = StubLocalHTTP(json: LocalFixtures.ollama(content: reason, model: "m-" + token))
            let d = try await LocalFixtures.planner(chatty, key: token).decide(LocalFixtures.ask())
            texts += [d.why, d.provider.modelVersion, d.provider.id, String(describing: d)]
            XCTAssertEqual(chatty.sent.first?.headers["Authorization"], "Bearer " + token, "the token is sent, only to the server")

            for text in texts {
                XCTAssertFalse(text.contains(token), "the raw token is in:\n\(text)")
                XCTAssertFalse(KeyScrub.containsKey(text), "a key pattern is in:\n\(text)")
            }
        }
    }

    func testTheCardSaysWhetherATokenIsSetNeverWhichOne() throws {
        for token in Self.localTokens {
            let e = LocalFixtures.endpoint("http://192.168.1.20:11434/v1", key: token)
            let lines = try ModelTransport.classify(e).card(bearerSet: e.apiKey != nil)
            XCTAssertTrue(lines.contains(ModelTransport.Words.plainToken))
            for line in lines { XCTAssertFalse(line.contains(token)) }
        }
    }
}
