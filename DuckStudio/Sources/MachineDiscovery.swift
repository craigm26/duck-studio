import Foundation
import Network
import StudioKit

/// Browses for `_duckstudio._tcp` and reports what answered, with the host each
/// record resolved to.
///
/// OPENCASTOR'S `RobotDiscovery.discover`, ADAPTED, because it already carries
/// the lessons: the TXT record is read in the browse result (so only the host
/// needs resolving), the host is resolved by opening a throwaway connection and
/// reading the path it would take, and a browser that goes to `.waiting` —
/// which is how a refused Local Network permission shows up — finishes at once
/// rather than hanging the launch.
///
/// NOT MAIN-ACTOR ISOLATED: `NWBrowser` and `NWConnection` call back on their
/// own queue, so everything mutable is confined to `queue` and the async entry
/// point resumes the caller when it is done.
final class MachineDiscovery: @unchecked Sendable {

    /// How a browse ended, so the screen can say which of two very different
    /// things "nothing found" means.
    enum Ending: Sendable { case finished, permissionLikelyOff }

    private let queue = DispatchQueue(label: "duckstudio.machine-discovery")
    private var browser: NWBrowser?
    private var pending: [NWEndpoint: NWConnection] = [:]
    /// One record as the browse saw it.
    struct Record: Sendable {
        let txt: [String: String]
        let name: String
        let host: String
        let port: Int
    }

    private var found: [String: Record] = [:]
    private var finished = false

    /// Browse briefly. Short, because it runs as the app opens.
    func discover(type: String, timeout: TimeInterval = 3.0) async -> (found: [Record], ending: Ending) {
        await withCheckedContinuation { continuation in
            queue.async {
                self.found = [:]
                self.finished = false
                let complete = { [weak self] (ending: Ending) in
                    guard let self, !self.finished else { return }
                    self.finished = true
                    let results = Array(self.found.values)
                    self.browser?.cancel()
                    self.browser = nil
                    self.pending.values.forEach { $0.cancel() }
                    self.pending = [:]
                    continuation.resume(returning: (results, ending))
                }
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil),
                                        using: NWParameters())
                self.browser = browser
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    guard let self else { return }
                    for result in results {
                        guard case .bonjour(let record) = result.metadata else { continue }
                        var name = ""
                        if case .service(let service, _, _, _) = result.endpoint { name = service }
                        let txt = record.dictionary
                        self.resolveHost(for: result.endpoint) { host, port in
                            guard let host, let port else { return }
                            self.found["\(name)|\(host)"] = Record(txt: txt, name: name, host: host, port: port)
                        }
                    }
                }
                browser.stateUpdateHandler = { state in
                    switch state {
                    case .waiting: complete(.permissionLikelyOff)
                    case .failed, .cancelled: complete(.finished)
                    default: break
                    }
                }
                browser.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) { complete(.finished) }
            }
        }
    }

    /// Resolve a Bonjour endpoint to an IPv4 literal. Runs on `queue`.
    private func resolveHost(for endpoint: NWEndpoint, completion: @escaping (String?, Int?) -> Void) {
        guard pending[endpoint] == nil else { return }
        let connection = NWConnection(to: endpoint, using: .tcp)
        pending[endpoint] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                var host: String?
                var port: Int?
                if case .hostPort(let h, let p)? = connection.currentPath?.remoteEndpoint {
                    port = Int(p.rawValue)
                    switch h {
                    case .ipv4(let address): host = "\(address)".components(separatedBy: "%").first
                    // IPv4 ONLY. The advertiser publishes v4, and a v6 literal
                    // would need brackets `DuckBench.address` does not parse —
                    // it splits the port off at the last colon.
                    case .ipv6: host = nil
                    case .name(let name, _): host = name
                    @unknown default: host = nil
                    }
                }
                completion(host, port)
                connection.cancel()
                self.pending[endpoint] = nil
            case .failed, .cancelled:
                completion(nil, nil)
                self.pending[endpoint] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}
