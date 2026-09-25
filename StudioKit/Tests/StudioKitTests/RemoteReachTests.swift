import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import StudioKit

/// The sign-in asks for identity and nothing more, refuses an answer it did
/// not ask for, and a 401 always reads as "sign in again".
final class RemoteReachTests: XCTestCase {

    // MARK: - PKCE and the request

    func testTheChallengeIsBase64URLOfSHA256AsAnIndependentImplementationComputesIt() {
        // Expected value from Python's hashlib + urlsafe_b64encode, unpadded — an
        // implementation that shares no code with this one.
        XCTAssertEqual(RemoteReach.challenge(for: "dBjftJeZ4CVP-mJ92K9qzYg7IN6dq5tJ1-yPo3Y4f9E"),
                       "opjRwk6U2I8uXdLwLXYPn-UEidciHPrff0gpIb-_a48")
        XCTAssertFalse(RemoteReach.challenge(for: "x").contains("="), "no padding")
    }

    func testTheSignInAsksForIdentityOnlyWithPKCEAndOurRedirect() throws {
        let url = RemoteReach.authorizeURL(state: "s1", verifier: "v")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        XCTAssertEqual(value("scope"), "openid profile")
        XCTAssertEqual(value("redirect_uri"), "duckstudio://oauth/callback")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("client_id"), RemoteReach.clientID)
        XCTAssertNil(value("client_secret"), "PKCE; no secret is in this app")
    }

    func testTheCallbackMustAnswerOurOwnRequest() throws {
        let ok = URL(string: "duckstudio://oauth/callback?code=abc&state=s1")!
        XCTAssertEqual(try RemoteReach.code(from: ok, expectedState: "s1"), "abc")
        XCTAssertThrowsError(try RemoteReach.code(from: ok, expectedState: "other")) {
            XCTAssertEqual($0 as? RemoteReach.SignInError, .stateMismatch)
        }
        let denied = URL(string: "duckstudio://oauth/callback?error=access_denied&state=s1")!
        XCTAssertThrowsError(try RemoteReach.code(from: denied, expectedState: "s1")) {
            XCTAssertEqual($0 as? RemoteReach.SignInError, .declined)
        }
    }

    func testTheTokenExchangeCarriesTheVerifierAndNoSecret() throws {
        let body = String(decoding: RemoteReach.tokenRequest(code: "c 1", verifier: "v/2").httpBody ?? Data(),
                          as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=c%201"))
        XCTAssertTrue(body.contains("code_verifier=v%2F2"))
        XCTAssertFalse(body.contains("secret"))
    }

    func testASessionPastItsTimeCountsAsNoSignIn() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let s = try RemoteReach.session(from: Data(#"{"access_token":"t","expires_in":3600}"#.utf8), at: now)
        XCTAssertTrue(s.isUsable(at: now))
        XCTAssertFalse(s.isUsable(at: now.addingTimeInterval(3590)), "a minute of margin")
    }

    // MARK: - listing

    func testOnlyMicroducksAreListedByTheRendezvousesOwnKindRule() throws {
        let answer = """
        {"robots": [
          {"peerId": "p1", "robotName": "reachy_mini", "busy": false, "meta": {"name": "reachy_mini"}},
          {"peerId": "p2", "robotName": "yoshi", "busy": true, "activeApp": "microduck console",
           "meta": {"name": "yoshi", "kind": "Micro-Duck", "release": "0.9"}, "last_seen_age_seconds": 2.4}
        ]}
        """
        let ducks = try RemoteReach.ducks(from: Data(answer.utf8), status: 200)
        XCTAssertEqual(ducks.map(\.peerID), ["p2"], "a Reachy Mini sends no kind and is left out")
        XCTAssertEqual(RemoteReach.line(ducks[0]),
                       "yoshi: reachable from anywhere · busy with microduck console · seen 2 s ago")
    }

    func testTheLiveEmptyAnswerIsNoDucksNotAnError() throws {
        // What the rendezvous returned for this account on 2026-09-24.
        XCTAssertEqual(try RemoteReach.ducks(from: Data(#"{"robots":[]}"#.utf8), status: 200), [])
    }

    func testA401IsTheSignInAndNeverTheDuck() {
        XCTAssertThrowsError(try RemoteReach.ducks(from: Data(), status: 401)) {
            XCTAssertEqual($0 as? RemoteReach.ListError, .signInAgain)
        }
        XCTAssertTrue(RemoteReach.ListError.signInAgain.message.contains("says nothing about whether your duck is there"))
    }
}
