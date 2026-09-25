import SwiftUI
import AuthenticationServices
import StudioKit

/// The Hugging Face sign-in that lists your ducks through Pollen's rendezvous.
///
/// ITS OWN KEYCHAIN SLOT. `TokenStore` holds the write token that publishes
/// under somebody's name; this holds an identity-only sign-in. Two credentials
/// for two doors, and `BridgeTokenStore`'s comment is why they never share one.
@MainActor
final class RemoteReachStore: ObservableObject {

    private static let service = "com.duckstudio.hf-signin"
    private static let account = "duck-studio"

    @Published private(set) var session: RemoteReach.Session?
    @Published private(set) var ducks: [RemoteReach.Duck] = []
    @Published private(set) var line: String?
    @Published private(set) var busy = false

    init() {
        if let raw = KeychainSecret.load(service: Self.service, account: Self.account),
           let saved = try? JSONDecoder().decode(RemoteReach.Session.self, from: Data(raw.utf8)),
           saved.isUsable() {
            session = saved
        }
    }

    var signedIn: Bool { session?.isUsable() == true }

    /// Sign in through the system browser sheet, then list.
    func signIn(with web: WebAuthenticationSession) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        line = nil
        var random = SystemRandomNumberGenerator()
        let verifier = RemoteReach.verifier(bytes: (0..<32).map { _ in UInt8.random(in: 0...255, using: &random) })
        let state = UUID().uuidString
        do {
            let callback = try await web.authenticate(
                using: RemoteReach.authorizeURL(state: state, verifier: verifier),
                callbackURLScheme: RemoteReach.callbackScheme,
                preferredBrowserSession: .ephemeral)
            let code = try RemoteReach.code(from: callback, expectedState: state)
            let (data, _) = try await URLSession.shared.data(
                for: RemoteReach.tokenRequest(code: code, verifier: verifier))
            let fresh = try RemoteReach.session(from: data)
            if let encoded = try? JSONEncoder().encode(fresh) {
                KeychainSecret.save(String(decoding: encoded, as: UTF8.self),
                                    service: Self.service, account: Self.account)
            }
            session = fresh
            await list()
        } catch let error as RemoteReach.SignInError {
            line = error.message
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            line = RemoteReach.SignInError.declined.message
        } catch {
            line = error.localizedDescription
        }
    }

    func signOut() {
        KeychainSecret.clear(service: Self.service, account: Self.account)
        session = nil
        ducks = []
        line = nil
    }

    /// The account's Microducks. Opens no session on the rendezvous.
    func list() async {
        guard let session, session.isUsable() else {
            if self.session != nil { line = RemoteReach.ListError.signInAgain.message; signOut() }
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(
                for: RemoteReach.statusRequest(token: session.accessToken))
            ducks = try RemoteReach.ducks(from: data,
                                          status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as RemoteReach.ListError {
            line = error.message
            if error == .signInAgain { signOut() ; line = error.message }
        } catch {
            line = error.localizedDescription
        }
    }
}
