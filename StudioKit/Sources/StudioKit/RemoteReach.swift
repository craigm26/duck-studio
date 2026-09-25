import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLRequest lives here on Linux, where these tests run
#endif
import Crypto

/// Stage 1 of `docs/REMOTE-REACH.md`: sign in with Hugging Face, and list the
/// Microducks that account owns on Pollen's rendezvous.
///
/// IDENTITY ONLY. The sign-in asks for `openid profile` and nothing else —
/// Pollen's remote-access design names over-broad scopes as the one thing to
/// fix before shipping, and their console asks for exactly these two. It is a
/// separate credential from the write token Settings holds for publishing, and
/// it is never a robot's token: peers are keyed by token, so borrowing one
/// would take the robot off the listing.
///
/// LISTING OPENS NOTHING. `GET /api/robot-status` answers the account's robots
/// without consuming a session slot (the rendezvous's own docstring), which is
/// why it is used rather than the SSE `list`. Sending calls to a duck is stage
/// 2 and waits for Pollen's answer to pollen-robotics/microduck#329.
///
/// A 401 IS THE SIGN-IN AND NOTHING ELSE. The console's rule, learned the hard
/// way on their side: an expired or refused token must read as "sign in
/// again", never as "your duck is not there".
public enum RemoteReach {

    // MARK: - the sign-in

    /// Duck Studio's OAuth app on huggingface.co (created 2026-09-24). A
    /// client id is public; PKCE needs no secret, and none is in this app.
    public static let clientID = "fa895e94-2e3c-464c-9c98-73f250e16c98"
    public static let callbackScheme = "duckstudio"
    public static let redirectURI = "duckstudio://oauth/callback"
    public static let scopes = "openid profile"
    public static let authorizeEndpoint = URL(string: "https://huggingface.co/oauth/authorize")!
    public static let tokenEndpoint = URL(string: "https://huggingface.co/oauth/token")!

    /// A PKCE verifier: 32 random bytes, base64url. Passed in so a test can pin it.
    public static func verifier(bytes: [UInt8]) -> String { base64URL(Data(bytes)) }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func authorizeURL(state: String, verifier: String) -> URL {
        var parts = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return parts.url!
    }

    public enum SignInError: Error, Equatable {
        case declined
        case stateMismatch
        case noCode
        case noToken

        public var message: String {
            switch self {
            case .declined: return "Hugging Face sign-in was cancelled. Nothing was changed."
            case .stateMismatch:
                return "That sign-in answer was not the one this app asked for, so it was ignored."
            case .noCode, .noToken: return "Hugging Face did not complete the sign-in. Try again."
            }
        }
    }

    /// The code from the redirect, after checking it answers our own request.
    public static func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if value("error") != nil { throw SignInError.declined }
        guard value("state") == expectedState else { throw SignInError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw SignInError.noCode }
        return code
    }

    public static func tokenRequest(code: String, verifier: String) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [(String, String)] = [
            ("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
            ("client_id", clientID), ("code_verifier", verifier),
        ]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").utf8)
        return request
    }

    /// What the sign-in yields: a bearer token and when it stops working.
    public struct Session: Equatable, Sendable, Codable {
        public let accessToken: String
        public let expires: Date
        public init(accessToken: String, expires: Date) {
            self.accessToken = accessToken; self.expires = expires
        }
        /// Checked BEFORE the token is offered, with a minute of margin — the
        /// console's rule: a token past its time counts as no sign-in.
        public func isUsable(at now: Date = Date()) -> Bool { now.addingTimeInterval(60) < expires }
    }

    public static func session(from data: Data, at now: Date = Date()) throws -> Session {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = top["access_token"] as? String, !token.isEmpty else {
            throw SignInError.noToken
        }
        let lifetime = (top["expires_in"] as? Double) ?? (top["expires_in"] as? Int).map(Double.init) ?? 3600
        return Session(accessToken: token, expires: now.addingTimeInterval(lifetime))
    }

    // MARK: - your ducks

    public static let rendezvous = URL(string: "https://pollen-robotics-reachy-mini-central.hf.space")!

    public static func statusRequest(token: String) -> URLRequest {
        var request = URLRequest(url: rendezvous.appendingPathComponent("api/robot-status"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        return request
    }

    /// One Microduck on the account, as the rendezvous lists it.
    public struct Duck: Equatable, Sendable {
        public let peerID: String
        public let name: String
        public let busy: Bool
        public let activeApp: String?
        public let secondsSinceSeen: Double?
        public let release: String?
    }

    /// The rendezvous's own kind rule: case-insensitive, ignoring everything
    /// outside a-z0-9, so "Micro Duck" and "micro-duck" are both a Microduck.
    /// Reachy Minis send no kind at all, and are left out.
    public static func isMicroduck(_ meta: [String: Any]) -> Bool {
        let raw = (meta["kind"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? meta["robot_type"] as? String
        guard let raw, raw.count <= 64 else { return false }
        return raw.lowercased().filter { $0.isLetter && $0.isASCII || $0.isNumber } == "microduck"
    }

    public enum ListError: Error, Equatable {
        case signInAgain
        case answered(Int)

        public var message: String {
            switch self {
            case .signInAgain:
                return "Your Hugging Face sign-in has expired or was refused. Sign in again; this "
                     + "says nothing about whether your duck is there."
            case .answered(let status):
                return "Pollen's rendezvous answered \(status), so your ducks could not be listed."
            }
        }
    }

    public static func ducks(from data: Data, status: Int) throws -> [Duck] {
        if status == 401 { throw ListError.signInAgain }
        guard status == 200 else { throw ListError.answered(status) }
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let robots = top["robots"] as? [[String: Any]] else { throw ListError.answered(status) }
        return robots.compactMap { robot in
            let meta = robot["meta"] as? [String: Any] ?? [:]
            guard isMicroduck(meta), let peer = robot["peerId"] as? String else { return nil }
            return Duck(peerID: peer,
                        name: (meta["name"] as? String) ?? (robot["robotName"] as? String) ?? "Microduck",
                        busy: robot["busy"] as? Bool ?? false,
                        activeApp: robot["activeApp"] as? String,
                        secondsSinceSeen: robot["last_seen_age_seconds"] as? Double,
                        release: meta["release"] as? String)
        }
    }

    // MARK: - the words

    public static let heading = "Reach your ducks from anywhere"
    public static let signIn = "Sign in with Hugging Face"
    public static let signOut = "Sign out"
    public static func signedIn(until expires: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Signed in with Hugging Face until \(formatter.string(from: expires))."
    }
    public static let explain =
        "Signing in lists the Microducks your Hugging Face account owns, through Pollen's "
      + "rendezvous, even when they are not on your network. It asks Hugging Face who you are and "
      + "nothing else, and it is separate from any token you use to publish."
    public static let noDucks =
        "No Microduck on this account yet. A duck appears here once it has signed in with "
      + "`account login` on the robot."
    public static func line(_ duck: Duck) -> String {
        let seen = duck.secondsSinceSeen.map { String(format: " · seen %.0f s ago", $0) } ?? ""
        let state = duck.busy ? "busy\(duck.activeApp.map { " with \($0)" } ?? "")" : "free"
        return "\(duck.name): reachable from anywhere · \(state)\(seen)"
    }
    public static let controlWaits =
        "Sending plans and walkers to a duck this way comes next, once Pollen has confirmed a "
      + "third-party app is welcome on their rendezvous."
}
