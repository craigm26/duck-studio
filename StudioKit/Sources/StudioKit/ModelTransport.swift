import Foundation

/// Where a planner's words go on the way to its model, and whether anyone on the way can read
/// them (brains-layer.md 6.6, and section 9 item 2: "with TLS or the plaintext caveat").
///
/// THE APP CANNOT ENCRYPT A LINK IT DOES NOT OWN, SO IT SAYS WHICH LINK IT IS. Ollama, LM Studio,
/// llama.cpp and `mlx_lm.server` all serve plain HTTP unless somebody puts TLS in front of them.
/// `ModelEndpoint.validateAddress` already refuses plain HTTP off your own network. Inside your
/// network it is allowed, and this is the sentence that tells a person what that means before
/// they type anything.
///
/// A TAILNET IS ITS OWN CASE. Tailscale encrypts traffic between your devices with WireGuard,
/// so a plain HTTP request to a 100.x address or a `.ts.net` name is not readable on the Wi-Fi
/// it crosses. Telling that person "unencrypted over your Wi-Fi" would be false, so the tailnet
/// gets its own words.
public enum ModelTransport: Equatable, Sendable {
    /// The model runs in this app (Apple's model, or downloaded MLX weights).
    case thisDevice
    /// Another app on this device, reached at localhost. It never leaves the device.
    case otherAppOnThisDevice
    /// A computer on your own network, over HTTPS.
    case ownNetworkEncrypted(host: String)
    /// A computer on your own network, over plain HTTP. Anyone on the same Wi-Fi can read it.
    case ownNetworkPlain(host: String)
    /// A computer on your tailnet, over plain HTTP. Tailscale encrypts it between devices.
    case tailnet(host: String)
    /// A host that says it forwards to a model somewhere else (`ModelEndpoint.relay`).
    case forwardsElsewhere(host: String, to: String?)
    /// A host off your own network, over HTTPS.
    case internetEncrypted(host: String)

    /// Which of these an endpoint is. Throws `ModelEndpoint.Refusal` for an address the app
    /// would refuse anyway, such as plain HTTP to the public internet.
    public static func classify(_ endpoint: ModelEndpoint) throws -> ModelTransport {
        switch endpoint.kind {
        case .appleOnDevice, .downloadedMLX:
            return .thisDevice
        case .openAICompatible:
            break
        }
        try endpoint.validateAddress()
        let trimmed = endpoint.baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let rawHost = url.host else {
            throw ModelEndpoint.Refusal.notAURL(endpoint.baseURL)
        }
        let host = rawHost.lowercased()
        let encrypted = url.scheme?.lowercased() == "https"
        if endpoint.relay {
            let note = endpoint.relayNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .forwardsElsewhere(host: host, to: (note?.isEmpty ?? true) ? nil : note)
        }
        if isLoopback(host) { return .otherAppOnThisDevice }
        if isTailnet(host) { return encrypted ? .ownNetworkEncrypted(host: host) : .tailnet(host: host) }
        if ModelEndpoint.isLocalHost(host) {
            return encrypted ? .ownNetworkEncrypted(host: host) : .ownNetworkPlain(host: host)
        }
        return .internetEncrypted(host: host)
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// A Tailscale address (100.64.0.0/10) or MagicDNS name (`.ts.net`).
    static func isTailnet(_ host: String) -> Bool {
        if host.hasSuffix(".ts.net") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return (64...127).contains(parts[1])
    }

    /// Whether anyone on the network between here and the model could read what is sent.
    public var readableOnTheWay: Bool {
        if case .ownNetworkPlain = self { return true }
        return false
    }

    /// Whether the words leave your own devices and network.
    public var leavesYourNetwork: Bool {
        switch self {
        case .forwardsElsewhere, .internetEncrypted: return true
        default: return false
        }
    }

    /// The card's lines for this transport. `bearerSet` adds the line about the access token
    /// when it travels in the clear. No key is ever in these words, only whether one is set.
    public func card(bearerSet: Bool = false, device: DeviceWords = .current) -> [String] {
        Words.card(self, bearerSet: bearerSet, device: device)
    }

    /// The sentences, in one place so a test can read every one of them.
    public enum Words {
        public static func card(_ t: ModelTransport, bearerSet: Bool, device: DeviceWords) -> [String] {
            switch t {
            case .thisDevice:
                return ["Runs on \(device.this). Nothing you type leaves it."]
            case .otherAppOnThisDevice:
                return ["Goes to another app on \(device.this). Nothing you type leaves it."]
            case .ownNetworkEncrypted(let host):
                return ["Goes to \(host) on your own network, encrypted."]
            case .ownNetworkPlain(let host):
                var lines = ["Goes to \(host) on your own network.", plainCaveat]
                if bearerSet { lines.append(plainToken) }
                return lines
            case .tailnet(let host):
                return ["Goes to \(host) on your tailnet. Tailscale encrypts it between your devices."]
            case .forwardsElsewhere(let host, let to):
                if let to {
                    return ["Goes to \(host), which forwards it to \(to). It leaves your network."]
                }
                return ["Goes to \(host), which forwards it somewhere this app cannot see. It leaves your network."]
            case .internetEncrypted(let host):
                return ["Goes to \(host) over the internet, encrypted. It is not on your own network."]
            }
        }

        /// The plain-HTTP caveat (6.6). Short, and true for an address on your own Wi-Fi.
        public static let plainCaveat =
            "What you type is sent unencrypted over your Wi-Fi. Anyone on it can read it."
        /// Said when a bearer token rides along in the clear.
        public static let plainToken =
            "The access token for it is sent unencrypted too."
        /// How to fix it, for the setup sheet.
        public static let plainRemedy =
            "To encrypt it, put the server behind HTTPS, or reach it over Tailscale."

        /// Every sentence, for the copy tests.
        public static var all: [String] {
            let cases: [ModelTransport] = [
                .thisDevice, .otherAppOnThisDevice, .ownNetworkEncrypted(host: "mac.local"),
                .ownNetworkPlain(host: "mac.local"), .tailnet(host: "mac.tail1234.ts.net"),
                .forwardsElsewhere(host: "pi.local", to: nil), .forwardsElsewhere(host: "pi.local", to: "Anthropic"),
                .internetEncrypted(host: "models.example.com"),
            ]
            return cases.flatMap { c in
                [DeviceWords.phone, .mac].flatMap { card(c, bearerSet: true, device: $0) }
            } + [plainRemedy]
        }
    }
}
