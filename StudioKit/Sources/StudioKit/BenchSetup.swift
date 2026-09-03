import Foundation

/// Getting a phone talking to a machine that has physics, without a support call.
///
/// THE PROBLEM IS NOT THE PROTOCOL, IT IS THE SEVEN WAYS IT FAILS. The bench is
/// one HTTP call to a host and a port. Everything hard about it is that "it
/// didn't work" covers: nothing typed, a LAN address typed while the phone is
/// on cellular, the bench not started, started on a different machine, started
/// behind a firewall, started with a token the app was not given, or something
/// else entirely answering on 8770. Each of those has a different next action,
/// and a screen that says "could not connect" makes the person guess which.
///
/// SO THE DIAGNOSIS IS THE FEATURE. `diagnose` turns what actually came back
/// into the one thing to do next. It lives here rather than in the view because
/// a sentence that tells somebody to do the wrong thing is a bug, and bugs
/// belong where `swift test` can reach them.
///
/// TAILSCALE IS THE DEFAULT ANSWER AND NOT AN ADVANCED ONE. A 192.168 address
/// only works while the phone is on the same Wi-Fi, which it silently is not
/// the moment it prefers cellular or somebody walks out of the room — and the
/// failure looks exactly like a bench that stopped. A tailnet address works
/// from anywhere and is the same string forever, so it is what the steps say.
public enum BenchSetup {

    /// One instruction, in the order somebody does them.
    public struct Step: Equatable, Sendable, Identifiable {
        public var id: Int { number }
        public let number: Int
        public let title: String
        /// What to do, in a sentence. Never a description of the screen.
        public let detail: String
        /// Something worth putting on the clipboard, if this step has one.
        public let copyable: String?

        public init(number: Int, title: String, detail: String, copyable: String? = nil) {
            self.number = number; self.title = title
            self.detail = detail; self.copyable = copyable
        }
    }

    /// What the person is being asked to do, once.
    public static let steps: [Step] = [
        .init(number: 1, title: "Install Tailscale on both",
              detail: "On this phone and on the computer that will run the bench, signed in to "
                    + "the same account. This is what lets the phone reach it from anywhere "
                    + "rather than only on the same Wi-Fi."),
        .init(number: 2, title: "Install Node.js on the computer",
              detail: "The LTS build from nodejs.org. The bench is a Node program — it needs "
                    + "nothing else installed by hand.",
              copyable: "https://nodejs.org"),
        .init(number: 3, title: "Copy the bench folder to that computer",
              detail: "The folder with start.ps1 and start.sh in it. It carries the physics "
                    + "world every measurement is made against — a 7 MB file every result is "
                    + "stamped with — so it travels as one piece rather than as a download "
                    + "list. THE BENCH IS NOT PUBLISHED YET: if you did not get this folder "
                    + "from us, there is nowhere to fetch it, and the rest of this app works "
                    + "without one."),
        .init(number: 4, title: "Start it",
              detail: "Windows: right-click start.ps1 and choose Run with PowerShell. "
                    + "Mac or Linux: run ./start.sh in a terminal. The first start installs "
                    + "MuJoCo and takes a couple of minutes; after that it is seconds. Leave "
                    + "the window open — closing it stops the bench."),
        .init(number: 5, title: "Type the address it prints",
              detail: "The start script prints the exact line to use. It is that computer's "
                    + "Tailscale address and port 8770, and it does not change, so this is the "
                    + "only time you type it.",
              copyable: nil),
    ]

    /// What the computer running the bench should be told to type, if it would
    /// rather not use the start script.
    public static let byHand = "node duckbench.mjs"

    /// Said above the list of presets, so the choice between them is informed.
    public static let preambleForAdding =
        "Every bench runs the same program on the same port — the only question is how this "
      + "phone reaches it. A Tailscale address works from anywhere; a Wi-Fi address works only "
      + "while the phone is on that network."

    /// A starting point for a new bench, so nobody has to invent the shape of
    /// an address from nothing.
    ///
    /// TWO, NOT SIX. The Models tab needs six because the SOFTWARE differs —
    /// Ollama, LM Studio, llama.cpp and a cloud service want different ports
    /// and different fields. Every bench runs the same program on the same
    /// port; the only thing that differs is HOW THE PHONE REACHES IT, and there
    /// are exactly two answers to that. Offering a longer menu would be
    /// inventing distinctions to look thorough.
    public struct Preset: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let detail: String
        public let symbol: String
        /// The address this fills in — an example, always edited before use.
        public let address: String
        public let suggestedName: String

        public init(name: String, detail: String, symbol: String,
                    address: String, suggestedName: String) {
            self.name = name; self.detail = detail; self.symbol = symbol
            self.address = address; self.suggestedName = suggestedName
        }
    }

    /// TAILSCALE FIRST, AND THAT ORDER IS THE RECOMMENDATION. A Wi-Fi address
    /// works right up until the phone prefers cellular or somebody leaves the
    /// room, and it fails looking exactly like a bench that has gone down.
    public static let presets: [Preset] = [
        .init(name: "A machine on my tailnet",
              detail: "Reaches it from anywhere, including on cellular. The address the start "
                    + "script prints.",
              symbol: "point.3.connected.trianglepath.dotted",
              address: "100.64.0.1:8770", suggestedName: "My bench"),
        .init(name: "A machine on my Wi-Fi",
              detail: "Only while this phone is on the same network as it. Simpler to set up, "
                    + "and it stops working when you walk out.",
              symbol: "wifi",
              address: "192.168.1.10:8770", suggestedName: "Bench on the LAN"),
    ]

    // MARK: - what went wrong

    /// The state of a connection attempt, and the one thing to do about it.
    public enum Diagnosis: Equatable, Sendable {
        case connected(policies: Int, plant: String?)
        case nothingTyped
        case notReachableAddress(String)
        case malformed(String)
        case nothingListening
        case wantsAToken
        case notABench
        case benchRefused(String)

        /// The sentence shown. EVERY ONE OF THESE NAMES AN ACTION, because a
        /// person looking at this screen has already worked out that it did not
        /// connect and needs the next move, not the news.
        public var message: String {
            switch self {
            case .connected(let policies, let plant):
                let world = plant.map { " Its world is \($0)." } ?? ""
                return "Connected. \(policies) \(policies == 1 ? "policy" : "policies") "
                     + "available to run.\(world)"
            case .nothingTyped:
                return "Start the bench on the other computer and type the address it prints — "
                     + "something like 100.95.79.116:8770."
            case .notReachableAddress(let host):
                return "\(host) is not an address this app will dial. It talks to your own "
                     + "network and your own tailnet only — a Tailscale address (100.x) or a "
                     + "LAN one (192.168.x, 10.x) — and never out to the internet."
            case .malformed(let text):
                return "\"\(text)\" is not a host and port. It should look like "
                     + "100.95.79.116:8770 — no https://, no trailing slash."
            case .nothingListening:
                return "Nothing answered there. Either the bench is not running — check the "
                     + "window on that computer is still open — or that is not its address. "
                     + "The start script prints the right one every time it runs."
            case .wantsAToken:
                return "The bench is running and wants its token. Put the same string in the "
                     + "token field that DUCKBENCH_TOKEN was set to when it started."
            case .notABench:
                return "Something answered on that port, but it is not a duck bench. Check the "
                     + "port is 8770 and that nothing else on that computer is using it."
            case .benchRefused(let said):
                return "The bench answered and refused: \(said)"
            }
        }

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    /// Work out what happened, from what the attempt produced.
    ///
    /// TAKES THE PIECES RATHER THAN A URLSession, so it is testable without a
    /// network: the status code, whatever body came back, and the error if the
    /// request never completed.
    public static func diagnose(address: String, status: Int?, body: Data?,
                                transportFailed: Bool) -> Diagnosis {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return .nothingTyped }
        do {
            _ = try DuckBench.address(typed)
        } catch let refusal as DuckBench.Refusal {
            switch refusal {
            case .empty: return .nothingTyped
            case .notLocal(let host): return .notReachableAddress(host)
            case .malformed(let text): return .malformed(text)
            // UNREACHABLE, AND NAMED RATHER THAN SWEPT INTO A `default`.
            // `DuckBench.address` parses an address and cannot refuse a
            // blend; this arm exists because the two refusals share one enum,
            // and it answers exactly what the generic `catch` below answers so
            // the shape of this function does not depend on an impossibility.
            case .blendWouldBeClamped: return .malformed(typed)
            }
        } catch {
            return .malformed(typed)
        }

        if transportFailed { return .nothingListening }
        if status == 401 { return .wantsAToken }
        guard let body else { return .notABench }
        if let health = try? DuckBench.readHealth(body) {
            return .connected(policies: health.policies.count, plant: health.plantName)
        }
        // A bench that answered with a refusal is a bench, and saying so is
        // different from saying nothing is there.
        if let top = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let said = top["error"] as? String {
            return .benchRefused(said)
        }
        return .notABench
    }

    // MARK: - what they typed

    /// Tidy up an address somebody pasted, without deciding it is wrong.
    ///
    /// PEOPLE PASTE URLS. The start script prints `100.95.79.116:8770`, and what
    /// arrives here is as often `http://100.95.79.116:8770/` off a browser bar,
    /// with a space on the end from the paste. `DuckBench.address` already
    /// strips a scheme and a path, but the field shows what was typed — so
    /// tidying it where the person can see keeps the screen and the parser
    /// telling the same story.
    public static func tidy(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = out.range(of: "://") { out = String(out[range.upperBound...]) }
        if let slash = out.firstIndex(of: "/") { out = String(out[..<slash]) }
        return out
    }

    /// Whether this looks like a tailnet address, which is the one worth
    /// preferring — a LAN address stops working the moment the phone is not on
    /// that Wi-Fi, and the failure looks like a broken bench.
    public static func isTailnet(_ text: String) -> Bool {
        let host = tidy(text).split(separator: ":").first.map(String.init) ?? ""
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return parts[1] >= 64 && parts[1] <= 127          // 100.64.0.0/10
    }

    /// Said next to a LAN address that will work now and stop working later.
    public static let lanWarning =
        "That is a Wi-Fi address. It works while this phone is on the same Wi-Fi as the bench "
      + "and stops the moment it is not — which looks exactly like the bench going down. The "
      + "start script prints a Tailscale address (100.x) that works from anywhere."
}
