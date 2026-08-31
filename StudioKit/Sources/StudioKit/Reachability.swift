import Foundation

/// What one probe of a model endpoint actually saw, and which of the several
/// very different things that could mean it was.
///
/// ONE LINE OF ERROR FOR FIVE DIFFERENT PROBLEMS is the thing this file exists
/// to end. Today a wrong address, a firewalled port, an Ollama bound to its own
/// loopback, a refused Local Network permission and a model that is merely slow
/// all arrive at the screen as one `error.localizedDescription`, and the person
/// reading it has no way to tell which of the five they have. Four of those
/// five have a different remedy and one of them is not their fault at all.
///
/// IT DOES NOT DO THE NETWORKING, AND THAT IS THE POINT. StudioKit runs its
/// tests on Linux with no URLSession worth the name and no phone at all, so
/// every sentence here is asserted letter by letter by `swift test` instead of
/// being eyeballed once on a device and then trusted forever. The app target
/// makes the request, writes down what it saw in an `Observation`, and this
/// decides. Nothing in here reaches anything.
///
/// IT NEVER STATES AS FACT SOMETHING IT DID NOT MEASURE. A probe sees a code, a
/// status, a body and a clock. It does not see whether Local Network permission
/// was granted — no part of this app reads that switch — so the sentence for
/// that case says it is the *shape* of the failure and offers the setting,
/// rather than diagnosing a thing it cannot see.
public enum Reachability {

    // MARK: - the codes

    /// `URLError` raw values, as plain integers.
    ///
    /// STUDIOKIT DOES NOT IMPORT THE NETWORKING FOUNDATION, so these cannot be
    /// spelled `URLError.timedOut` here. Every value except one was read off
    /// this machine by compiling `URLError.<case>.rawValue` and printing it, so
    /// they are not remembered numbers.
    ///
    /// THE EXCEPTION IS `-1022`, AND IT IS WORTH KNOWING WHY. Swift's Linux
    /// Foundation has no `appTransportSecurityRequiresSecureConnection` case at
    /// all — ATS is a Darwin thing — so that one is the documented value of
    /// `NSURLErrorAppTransportSecurityRequiresSecureConnection` and could not be
    /// read back here the way the others were.
    public enum Code {
        public static let timedOut = -1001
        public static let cannotFindHost = -1003
        public static let cannotConnectToHost = -1004
        public static let dnsLookupFailed = -1006
        public static let notConnectedToInternet = -1009
        public static let appTransportSecurityRequiresSecureConnection = -1022
        /// The whole certificate family, -1200 through -1206.
        public static let secureConnectionFailed = -1200
        public static let clientCertificateRequired = -1206
    }

    /// How long a list of models may take before the machine serving it is the
    /// story.
    ///
    /// FIVE SECONDS FOR A LIST IT ALREADY HAS. `/v1/models` reads names off
    /// disk; it runs no model and generates no token. A machine that needs
    /// longer than this to hand over that list is a machine that will need
    /// minutes to write a motion, and saying so at the moment somebody is
    /// choosing an address is worth far more than saying it after their first
    /// ninety-second wait.
    public static let slowAfter: Double = 5

    // MARK: - what the probe saw

    /// One probe, written down. Every field is something a caller can actually
    /// observe; there is no field here for anything the app would have to guess.
    public struct Observation: Equatable, Sendable {
        /// The host as it was typed — a name, a `.local`, or an address.
        public var host: String
        /// nil when the URL carried none.
        public var port: Int?
        public var scheme: String
        /// The path that was asked for, so a 404 can name the route it missed.
        public var path: String
        /// Wall clock for the request.
        public var seconds: Double
        /// What the probe was willing to wait, which is what a timeout means.
        public var allowance: Double
        /// The HTTP status, when a response arrived at all.
        public var status: Int?
        /// The first of the body, for quoting back. nil when there was none.
        public var body: String?
        /// How many models the body listed BY NAME, or nil when the body was
        /// not a model list. THE TWO ARE NOT THE SAME: zero means a real API
        /// that named no models, nil means whatever came back was not a list.
        public var modelsFound: Int?
        /// How many entries that list held, whatever shape they were in — nil
        /// when the body was not a model list.
        ///
        /// IT IS NOT THE SAME NUMBER AS `modelsFound` AND THE GAP IS A REAL
        /// FAILURE. A server that answers 200 with three entries that carry no
        /// readable id has models on it; counting only the names it could read
        /// made that three-entry list indistinguishable from an empty one, and
        /// the person was told "the shelf is empty — load a model on that
        /// machine" about a machine with models already loaded. Both counts are
        /// observed, so the verdict can tell an empty shelf from a shelf it
        /// cannot read.
        public var listedEntries: Int?
        /// `(error as NSError).code`, when the request threw.
        public var urlErrorCode: Int?
        /// `error.localizedDescription`, for the case nothing else explains.
        public var systemText: String?

        public init(host: String, port: Int? = nil, scheme: String = "http",
                    path: String = "/v1/models",
                    seconds: Double = 0, allowance: Double = 15,
                    status: Int? = nil, body: String? = nil, modelsFound: Int? = nil,
                    listedEntries: Int? = nil,
                    urlErrorCode: Int? = nil, systemText: String? = nil) {
            self.host = host
            self.port = port
            self.scheme = scheme
            self.path = path
            self.seconds = seconds
            self.allowance = allowance
            self.status = status
            self.body = body
            self.modelsFound = modelsFound
            self.listedEntries = listedEntries
            self.urlErrorCode = urlErrorCode
            self.systemText = systemText
        }
    }

    // MARK: - what it means

    /// The distinguishable things a probe can have found.
    ///
    /// DISTINGUISHABLE IS THE BAR, not exhaustive. Two failures share a case
    /// only when they share a remedy; the moment the person would do something
    /// different, they get their own case and their own sentence.
    public enum Cause: String, Equatable, Sendable, CaseIterable {
        /// It is an OpenAI-compatible API, it has models, and it was quick.
        case answered
        /// The same, slowly — which is a fact about the machine, not a fault.
        case answeredSlowly
        /// A real API with an empty shelf.
        case noModelsLoaded
        /// A real API whose list has things in it and no names on any of them.
        case modelNamesUnreadable
        /// It answered, and would not let the request in.
        case notAuthorised
        /// Something is listening; nothing serves that route.
        case noAPIAtThatPath
        /// Something is listening; it is not an API at all.
        case notAnAPI
        /// It answered with a status nothing above explains.
        case serverRefused
        /// The connection was refused outright: nothing is bound there.
        case nothingListening
        /// The name did not resolve.
        case hostNotFound
        /// The connection never left the phone, against an address on the
        /// person's own network. See the note on the sentence: this is a shape,
        /// not a reading of the setting.
        case localNetworkBlocked
        /// Nothing came back inside the allowance.
        case timedOut
        /// ATS refused plain http. A fault in the build, not in the address.
        case plaintextBlocked
        /// The certificate could not be checked.
        case tlsFailed
        /// The phone itself has no network.
        case offline
        /// Something else, quoted rather than interpreted.
        case unknown
    }

    /// The cause and the sentence that goes on the screen.
    public struct Verdict: Equatable, Sendable {
        public let cause: Cause
        /// What a person reads. Never empty, for any cause.
        public let sentence: String

        /// The endpoint spoke the API. Drafting can be tried.
        public var foundAnAPI: Bool {
            switch cause {
            case .answered, .answeredSlowly, .noModelsLoaded, .modelNamesUnreadable: return true
            default: return false
            }
        }

        /// Nothing stands in the way at all. `foundAnAPI` minus the empty shelf.
        public var isReady: Bool {
            cause == .answered || cause == .answeredSlowly
        }
    }

    /// There is no address yet, so there is nothing to check.
    ///
    /// A DISABLED BUTTON WITH NOTHING BESIDE IT IS THE SILENT FAILURE THIS APP
    /// IS BUILT AGAINST, and "Check this address" with the field empty is
    /// exactly that control. This is the reason that sits next to it.
    public static let nothingToCheck =
        "There is no address to check yet. Paste the one that machine prints when its server "
        + "starts, with /v1 on the end."

    // MARK: - the verdict

    public static func explain(_ seen: Observation) -> Verdict {
        let cause = decide(seen)
        return Verdict(cause: cause, sentence: sentence(cause, seen))
    }

    /// Which of the causes this was.
    ///
    /// A STATUS OUTRANKS EVERY TRANSPORT CODE, and the order below is that
    /// rule written down: if an HTTP response arrived at all then the address
    /// resolved, the route existed, the port was open and something answered —
    /// so nothing about names, firewalls or permissions can still be the story.
    ///
    /// AUTHORISATION OUTRANKS THE BODY. A proxy that refuses an unkeyed request
    /// often answers with an HTML login page, and reading that as "not an API"
    /// would send somebody off to check an address that was right all along.
    private static func decide(_ seen: Observation) -> Cause {
        if let status = seen.status {
            if status == 401 || status == 403 { return .notAuthorised }
            // 404 OUTRANKS THE HTML HEURISTIC, and the order used to be the
            // other way round. A status code is what the server SAID; the
            // shape of the body is a guess about what the server IS. A real
            // OpenAI-compatible server behind a reverse proxy answers an
            // unknown route with the proxy's own HTML error page, and reading
            // that as "a router, a printer, a web server" sent somebody off to
            // check an address that was right except for the path. The 404
            // sentence names both readings, so neither is asserted.
            if status == 404 { return .noAPIAtThatPath }
            if let body = seen.body, looksLikeAWebPage(body) { return .notAnAPI }
            guard (200...299).contains(status) else { return .serverRefused }
            // A 200 whose body is not a model list is a server that speaks
            // something else on that route.
            guard let found = seen.modelsFound else { return .notAnAPI }
            if found == 0 {
                // AN EMPTY SHELF AND AN UNREADABLE ONE ARE DIFFERENT ROOMS. A
                // list holding entries with no readable id is a machine with
                // models on it that this app cannot name; telling that person
                // to "load a model on that machine" sends them to solve a
                // problem they do not have.
                return (seen.listedEntries ?? 0) > 0 ? .modelNamesUnreadable : .noModelsLoaded
            }
            return seen.seconds > slowAfter ? .answeredSlowly : .answered
        }
        guard let code = seen.urlErrorCode else { return .unknown }
        switch code {
        case Code.timedOut:
            return .timedOut
        case Code.cannotConnectToHost:
            return .nothingListening
        case Code.cannotFindHost, Code.dnsLookupFailed:
            // A NAME LOOKUP THAT FAILED FOR SOMETHING THAT IS NOT A NAME is the
            // one fingerprint here that cannot be what it says it is. There was
            // nothing to look up, so the lookup is not what failed.
            return looksLikeAnAddress(seen.host) ? .localNetworkBlocked : .hostNotFound
        case Code.notConnectedToInternet:
            // AND THE OTHER IMPOSSIBLE ANSWER: an address on your own network
            // needs no internet, so "the internet appears to be offline" cannot
            // be the reason this one failed — unless the phone is off every
            // network, which the sentence keeps as the second reading.
            return ModelEndpoint.isLocalHost(seen.host) ? .localNetworkBlocked : .offline
        case Code.appTransportSecurityRequiresSecureConnection:
            return .plaintextBlocked
        default:
            if code <= Code.secureConnectionFailed, code >= Code.clientCertificateRequired {
                return .tlsFailed
            }
            return .unknown
        }
    }

    // MARK: - the sentences

    private static func sentence(_ cause: Cause, _ seen: Observation) -> String {
        let place = place(seen)
        // Only ever read under a cause that decide() produces from a status.
        let status = seen.status ?? 0
        switch cause {

        case .answered:
            return "\(place) answered as an OpenAI-compatible API and listed \(models(seen)), "
                 + "in \(secondsText(seen.seconds)). The address is right."

        case .answeredSlowly:
            return "\(place) answered as an OpenAI-compatible API and listed \(models(seen)) — "
                 + "but it took \(secondsText(seen.seconds)) to hand over a list it holds on "
                 + "disk, with no model run at all. Drafting asks it to run the model, which is "
                 + "far more work than reading a list: a 7.5B model on a Raspberry Pi 5 took "
                 + "766 s to write one motion here. A smaller model is the remedy, not a "
                 + "shorter timeout."

        case .noModelsLoaded:
            return "\(place) answered as an OpenAI-compatible API and listed no models at all. "
                 + "The address is right and the shelf is empty — load a model on that machine, "
                 + "then ask for the list again."

        case .modelNamesUnreadable:
            // WHAT WAS MEASURED IS THE ARRAY, NOT THE SHELF. This used to end
            // "That is not an empty shelf — something is on it", and what was
            // actually observed is that the `data` array held N JSON objects,
            // none carrying a String `id`. That N entries means N models is an
            // inference about a server this app could not parse — a small one,
            // and still the kind of step from observation to conclusion that
            // put six other untrue sentences into this app.
            return "\(place) answered as an OpenAI-compatible API and its list held "
                 + "\(entries(seen)) with no readable name between them. So the list is not "
                 + "empty, but this app cannot tell you what is on it. Type the model name that "
                 + "machine uses into Model, and Try a draft will say whether it took it."

        case .notAuthorised:
            return "\(place) answered \(status), which is a refusal to let the request in rather "
                 + "than anything wrong with the address. Put the bearer token that server "
                 + "expects under Advanced — or clear it, if it wants none."

        case .noAPIAtThatPath:
            return "Something is listening on \(place), and it answered 404 for \(seen.path). "
                 + "Either the route is wrong — Ollama, LM Studio and llama.cpp all serve theirs "
                 + "under /v1, so the address wants /v1 on the end and nothing after it — or "
                 + "what is on that port is not a model server at all. A 404 does not say "
                 + "which."

        case .notAnAPI:
            return "Something is listening on \(place), and it answered with a page rather than "
                 + "a list of models. That is a different service on that port — a router, a "
                 + "printer, a web server — and not an OpenAI-compatible API."

        case .serverRefused:
            guard let preview = preview(seen.body) else {
                return "\(place) answered \(status), with nothing in the body to explain it. It "
                     + "is listening and it understood enough to say no, so the address is close."
            }
            return "\(place) answered \(status). It is listening and it understood enough to say "
                 + "no, so the address is close. It said: \(preview)"

        case .nothingListening:
            let opening = "Nothing answered on \(place). Something has to be listening there, "
                        + "and on an address other machines can reach rather than only on its "
                        + "own localhost."
            guard seen.port == 11434 else { return opening }
            // THE SINGLE MOST COMMON SETUP FAILURE IN THIS APP, and Ollama
            // documents the fix itself, so it is quoted rather than paraphrased.
            return opening + " Ollama's own FAQ says it: “Ollama binds 127.0.0.1 port 11434 by "
                 + "default. Change the bind address with the OLLAMA_HOST environment variable.”"

        case .hostNotFound:
            return "Nothing on this network answers to the name \(seen.host). A .local name is "
                 + "found over Bonjour, and iOS asks for Local Network permission the first time "
                 + "an app looks; if that was declined, nothing here can reach it until Duck "
                 + "Studio is turned back on under Settings, Privacy & Security, Local Network. "
                 + "An address like 192.168.1.10 does not need the name to resolve, and is the "
                 + "quicker thing to try."

        case .localNetworkBlocked:
            let opening = looksLikeAnAddress(seen.host)
                ? "\(seen.host) is an address rather than a name, so there was nothing to look "
                  + "up — and iOS would not make the connection anyway."
                : "iOS said this phone has no connection at all, and yet \(place) is on your own "
                  + "network and needs none."
            return opening + " " + localNetworkRemedy

        case .timedOut:
            return "Nothing came back from \(place) inside \(secondsText(seen.allowance)). Two "
                 + "different things look like this. A machine slow enough that even a list took "
                 + "longer than that — slow is real here, a 7.5B model on a Raspberry Pi 5 took "
                 + "766 s to write one motion. Or a firewall on that machine swallowing the "
                 + "connection instead of refusing it: a refused connection comes back at once, "
                 + "a dropped one leaves you waiting."

        case .plaintextBlocked:
            guard ModelEndpoint.isLocalHost(seen.host) else {
                return "iOS refused this connection because it is plain http to \(seen.host), "
                     + "which is not on your own network. Use https for anything off your LAN."
            }
            return "iOS refused this connection as plain http even though \(seen.host) is on "
                 + "your own network. That is a fault in this build rather than anything you "
                 + "did — the app is meant to declare an exception for addresses like that one."

        case .tlsFailed:
            guard ModelEndpoint.isLocalHost(seen.host) else {
                return "The https handshake with \(seen.host) failed. That is a certificate this "
                     + "phone could not check, not a wrong address."
            }
            return "The https handshake with \(seen.host) failed. A machine on your own desk "
                 + "usually has no certificate anything trusts, which is why plain http is "
                 + "allowed here for addresses on your own network — try http for this one."

        case .offline:
            return "This phone has no network connection, so nothing could be tried. Nothing "
                 + "was learned about \(place) either way."

        case .unknown:
            guard let code = seen.urlErrorCode else {
                return "The connection to \(place) failed, and nothing came back to say why."
            }
            guard let text = trimmed(seen.systemText) else {
                return "The connection to \(place) failed, and the system gave no reason beyond "
                     + "the code \(code)."
            }
            return "The connection to \(place) failed: \(text) (\(code))."
        }
    }

    /// The half of the Local Network sentence that is the same either way.
    ///
    /// IT OFFERS THE CAUSE AND REFUSES TO DIAGNOSE IT. Nothing in this app
    /// reads the Local Network switch, so a sentence claiming the permission
    /// *is* off would be stating as fact a thing nobody measured. It says what
    /// the failure looks like, where the switch is, and what to think if the
    /// switch turns out to be on already.
    static let localNetworkRemedy =
        "That is what a refused Local Network permission looks like from in here, and this app "
        + "does not read that switch — so it is the shape of the failure and not a reading of "
        + "the setting. Open Settings, then Privacy & Security, then Local Network, and turn "
        + "Duck Studio on. If it is already on, then the address itself is the thing to check."

    // MARK: - small parts

    /// "192.168.1.10 port 11434", or just the host when no port was given.
    static func place(_ seen: Observation) -> String {
        guard let port = seen.port else { return seen.host }
        return "\(seen.host) port \(port)"
    }

    static func models(_ seen: Observation) -> String {
        let found = seen.modelsFound ?? 0
        return found == 1 ? "1 model" : "\(found) models"
    }

    /// The other count: what was in the list, rather than what could be named.
    static func entries(_ seen: Observation) -> String {
        let listed = seen.listedEntries ?? 0
        return listed == 1 ? "1 entry" : "\(listed) entries"
    }

    /// One decimal place. A probe that took 0.3 s should say so rather than
    /// rounding itself to "0 s" and looking like it never ran.
    static func secondsText(_ seconds: Double) -> String {
        String(format: "%.1f s", seconds)
    }

    /// Whatever the server said, short enough to sit in a footnote.
    static func preview(_ body: String?) -> String? {
        guard let text = trimmed(body) else { return nil }
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }

    static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// A body that begins with a tag is markup, whatever the status said.
    static func looksLikeAWebPage(_ body: String) -> Bool {
        trimmed(body)?.hasPrefix("<") ?? false
    }

    /// A literal address rather than a name. IPv6 is caught by its colons,
    /// which cannot appear in the host of a URL any other way.
    static func looksLikeAnAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }
}
