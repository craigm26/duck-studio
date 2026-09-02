import Foundation
import Network
import SwiftUI
import WebKit
import DuckKit
import StudioKit

/// The bench that is this phone.
///
/// WHY THIS EXISTS, AND WHAT IT OVERTURNS. Every screen in this app has been
/// built on one sentence — "an iPhone has no physics engine" — and that
/// sentence is a claim about a BUILD. MuJoCo has a WebAssembly target; the
/// `.wasm` this app now carries is byte-identical to the one the desk bench
/// imports, and the policy is four matrix multiplies over the same canonical
/// parameter bytes DuckEvidence already fingerprints. So the physics that used
/// to require a Raspberry Pi across the room runs here, and the app's own bench
/// list has a first row that is not on the network at all.
///
/// THE SHAPE, AND WHY IT IS A LOOPBACK SERVER RATHER THAN A DIRECT CALL. Every
/// caller in this app already speaks to a bench over HTTP: `BenchPeer` builds a
/// `URLRequest` from `DuckBench.Call` and hands it to an errand closure, and
/// `DriveView`, `PolicyBlendView`, `RemoteRunView` and `MyMicroduckView` all go
/// through it. A second path — "unless it is the phone, in which case call
/// JavaScript" — would be a second client, and two clients for one protocol is
/// how one of them ends up missing a field. So the phone bench is an HTTP
/// server on 127.0.0.1 with a port the kernel picks, and nothing above it
/// changes: `BenchPeer`, `DuckDrive`, `DriveView` and `DuckStage` are a
/// zero-line diff, which is the acceptance test for this whole change.
///
/// WHAT IS NOT MEASURED. Nothing here has been run on an iPhone. The core
/// owner ran the same shell in Chromium on a Raspberry Pi 5 and measured a
/// 2.7 ms control tick against a 20 ms budget; that is a desktop browser on the
/// machine that built it. `/health` measures its own tick wherever it actually
/// runs and reports it, and `PhoneBenchReport.speedIsUnmeasuredOnAPhone` is the
/// sentence that refuses to quote the Pi's number as though it were a phone's.

// MARK: - what the app serves

/// The files the page fetches, and the parameter bytes it runs.
///
/// TWO KINDS OF ASSET AND THEY ARE KEPT APART ON PURPOSE. Everything under
/// `Resources/phonebench` is a VENDORED artefact — copied byte-for-byte from
/// duck-sounds by `scripts/make_phone_bench.sh`, listed with its digest in
/// `MANIFEST.json`, and checked by `scripts/check_no_studio_math.sh` so that
/// nobody can edit physics into the app target through a `.mjs` file the Swift
/// guard cannot see. The policies are the other kind: they are DERIVED, at
/// runtime, from the `.onnx` files this app already bundles, by the one reader
/// this project has.
///
/// THE POLICIES ARE NOT SHIPPED AS BYTES, AND THAT IS THE POINT. Nine networks
/// at 791,584 bytes each would be 7 MB of duplicate — but the real reason is
/// provenance: `DuckPolicy.canonicalParameterBytes` is the layout DuckEvidence
/// fingerprints, so exporting it here means the phone runs exactly the numbers
/// the app attested to, from the same file the library screen inspected. A
/// second copy checked in beside them could drift from the `.onnx` and nothing
/// would say so.
final class PhoneBenchAssets: @unchecked Sendable {

    /// The folder reference in the app bundle. Nil is a build mistake — the
    /// folder is not in `project.yml`, or it went in as a group and its
    /// directory structure was flattened — and it surfaces as the page failing
    /// to load rather than as a crash.
    private let root: URL?
    /// Where exported parameter bytes are kept. Caches, because they are
    /// reproducible from the bundle: iOS may evict them and the next request
    /// writes them again.
    private let store: URL
    private let lock = NSLock()
    private var manifestJSON: Data?

    init() {
        root = Bundle.main.url(forResource: "phonebench", withExtension: nil)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        store = caches.appendingPathComponent("phonebench-policies", isDirectory: true)
    }

    var isPresent: Bool { root != nil }

    /// One vendored file, by its path under the folder.
    ///
    /// THE PATH IS CHECKED AGAINST THE FOLDER IT CAME FROM, not against a list
    /// of allowed names. `..` in a request would otherwise walk out of the
    /// bundle, and the listener is on loopback but a loopback port on iOS is
    /// reachable by anything else running on the phone.
    func file(_ relative: String) -> Data? {
        guard let root, !relative.isEmpty, !relative.contains("..") else { return nil }
        let url = root.appendingPathComponent(relative)
        let inside = url.standardizedFileURL.path
        guard inside.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// What this bench can run, as the manifest `duckbench-web.mjs` reads at
    /// boot to learn the name-to-file mapping.
    ///
    /// BUILT ONCE, BY EXPORTING EVERY BUNDLED NETWORK. It would be cheaper to
    /// list the filenames and export lazily, and that cheapness would be a lie:
    /// `/health` publishes this list, `ensureStanding` resolves the settling
    /// policy out of it, and a name in the list that cannot actually be
    /// exported would fail later as `asset alpha_x.bin: 404` — a sentence about
    /// a missing file, for a network that is right there and simply is not one
    /// this reader accepts. So the export is attempted here and the manifest
    /// names only what came back.
    ///
    /// A POLICY IMPORTED INTO THIS APP IS NOT IN HERE, and that is the honest
    /// limit rather than an oversight. This walks the BUNDLE; anything somebody
    /// AirDropped in lives in the container, and putting it on the phone bench
    /// means `/upload`, which the shell refuses for a reason
    /// (`PhoneBenchReport.uploadNotWired`).
    func policyManifest() -> Data {
        lock.lock(); defer { lock.unlock() }
        if let manifestJSON { return manifestJSON }
        var rows: [[String: String]] = []
        for url in bundledNetworks() {
            let base = url.deletingPathExtension().lastPathComponent
            guard exported(base, from: url) else { continue }
            rows.append(["name": "\(base).onnx", "file": "\(base).bin"])
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["policies": rows],
                                                options: [.sortedKeys]))
            ?? Data(#"{"policies":[]}"#.utf8)
        manifestJSON = data
        return data
    }

    /// The parameter bytes for one entry in that manifest.
    func policyBytes(_ file: String) -> Data? {
        guard !file.contains("/"), !file.contains(".."), file.hasSuffix(".bin") else { return nil }
        _ = policyManifest()          // the first export happens there
        let url = store.appendingPathComponent(file)
        if let data = try? Data(contentsOf: url) { return data }
        // EVICTED, SO EXPORTED AGAIN. The manifest is memoised, so the loop that
        // wrote these files runs once per process — and iOS may empty Caches
        // between two requests. A miss here is a file that was there and is
        // not, and the bundled network it came from still is.
        let base = String(file.dropLast(4))
        guard let source = bundledNetworks().first(where: { $0.deletingPathExtension().lastPathComponent == base }),
              exported(base, from: source) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func bundledNetworks() -> [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "onnx", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Write the canonical bytes out once, and say whether they are there.
    ///
    /// WRITTEN ATOMICALLY SO "IT EXISTS" IS ENOUGH TO TRUST IT. The alternative
    /// — checking the length against the one this architecture has — would put
    /// a number that belongs to DuckKit into the app target, which is the rule
    /// this project is built on. A half-written file cannot happen, so its
    /// presence is the whole check.
    private func exported(_ base: String, from url: URL) -> Bool {
        let out = store.appendingPathComponent("\(base).bin")
        if FileManager.default.fileExists(atPath: out.path) { return true }
        guard let policy = try? DuckPolicy.load(contentsOf: url) else { return false }
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        do {
            try policy.canonicalParameterBytes.write(to: out, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - the listener

/// An HTTP server on loopback, in front of a bench that lives in a WebView.
///
/// THE HEADERS ARE THE REASON THIS IS A SERVER AND NOT A `file://` LOAD. A page
/// loaded from `file://` on iOS cannot fetch its own siblings, gets no origin
/// worth the name, and can never be cross-origin isolated. The three headers
/// below are what let WebKit instantiate the WebAssembly module and — if a
/// threaded MuJoCo build is ever wanted — hand it shared memory. They go on
/// every response, including the JSON ones, because a page that is isolated for
/// its assets and not for its fetches is isolated for nothing.
final class PhoneBenchServer: @unchecked Sendable {

    /// Ask the page. `pathAndQuery` and a JSON body in, a JSON string out.
    typealias Bridge = @Sendable (String, String) async -> String

    /// THE ENDPOINTS, AND THEY ARE THE KIT'S LIST. Anything else is a 404 from
    /// here rather than a question put to the page: the set is the contract
    /// this app's client speaks, and a server that forwarded every unknown
    /// path would let a typo in a future call look like a bench that answered.
    /// It used to be written out here as ten paths, and `/tune` shipped as the
    /// eleventh factory in the kit with no entry in it — so the phone bench
    /// 404'd the probe and the Start button never appeared on the one bench
    /// the app carries. `DuckBench.routes` is pinned by a kit test to every
    /// call the kit can make, which this file cannot be.
    static let benchRoutes: Set<String> = DuckBench.routes

    /// A request bigger than this is refused rather than buffered. `/perform`
    /// sends keyframes and `/upload` is refused by the page anyway, so nothing
    /// legitimate comes close.
    private static let requestCeiling = 4 << 20

    private let assets: PhoneBenchAssets
    private let bridge: Bridge
    private let announce: @Sendable (Int) -> Void
    private let queue = DispatchQueue(label: "com.duckstudio.phonebench.http")
    private var listener: NWListener?

    init(assets: PhoneBenchAssets,
         bridge: @escaping Bridge,
         announce: @escaping @Sendable (Int) -> Void) {
        self.assets = assets
        self.bridge = bridge
        self.announce = announce
    }

    /// Bind, and say what port we got.
    ///
    /// LOOPBACK IS REQUIRED TWICE, AND ONE OF THEM IS BELT AND BRACES.
    /// `requiredLocalEndpoint` is what asks the system to bind 127.0.0.1 only;
    /// the check on every accepted connection is what makes a mistake there
    /// harmless rather than a physics bench answering the coffee shop. The port
    /// is `.any`, so the kernel picks — a fixed port is a fixed collision with
    /// whatever else on the phone wanted it.
    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        guard let listener = try? NWListener(using: parameters) else { return }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = listener.port?.rawValue else { return }
            self?.announce(Int(port))
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback
        default: return false
        }
    }

    private func accept(_ connection: NWConnection) {
        guard Self.isLoopback(connection.currentPath?.remoteEndpoint ?? connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
            [weak self] chunk, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var data = buffer
            if let chunk { data.append(chunk) }
            if error != nil { return connection.cancel() }
            if let request = Request(data) {
                self.route(request, on: connection)
                return
            }
            if data.count > Self.requestCeiling || isComplete { return connection.cancel() }
            self.receive(connection, buffer: data)
        }
    }

    /// One request, whole: what was asked for and the body that came with it.
    struct Request {
        let target: String
        let path: String
        let body: Data

        /// Nil while the bytes so far are not yet a complete request. THAT
        /// NIL IS NOT AN ERROR — it is how the read loop knows to wait for more,
        /// which is the difference between handling a POST whose body arrived
        /// in a second packet and dropping it.
        init?(_ data: Data) {
            guard let split = data.range(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[data.startIndex..<split.lowerBound],
                                    encoding: .utf8) else { return nil }
            let lines = head.components(separatedBy: "\r\n")
            let words = (lines.first ?? "").split(separator: " ")
            guard words.count >= 2 else { return nil }
            target = String(words[1])
            path = (target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/")
                .removingPercentEncoding ?? "/"
            var declared = 0
            for line in lines.dropFirst() {
                let halves = line.split(separator: ":", maxSplits: 1)
                guard halves.count == 2,
                      halves[0].trimmingCharacters(in: .whitespaces).lowercased()
                        == "content-length" else { continue }
                declared = Int(halves[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
            let start = split.upperBound
            guard data.endIndex - start >= declared else { return nil }
            body = Data(data[start..<(start + declared)])
        }
    }

    private func route(_ request: Request, on connection: NWConnection) {
        if Self.benchRoutes.contains(request.path) {
            let target = request.target
            let body = String(data: request.body, encoding: .utf8) ?? ""
            Task { [bridge] in
                let answer = await bridge(target, body)
                self.send(connection, status: "200 OK",
                          type: "application/json; charset=utf-8", body: Data(answer.utf8))
            }
            return
        }

        if request.path == "/" || request.path == "/index.html" {
            return sendFile("index.html", on: connection)
        }
        guard request.path.hasPrefix("/assets/") else {
            return send(connection, status: "404 Not Found", type: "text/plain; charset=utf-8",
                        body: Data("no \(request.path) here\n".utf8))
        }
        // THE LEADING SLASH COMES OFF AND THE `assets/` DOES NOT. Written the
        // other way — stripping `/assets/` and resolving the remainder against
        // the folder — every asset 404s, because the folder reference in the
        // bundle IS `phonebench/` and the files are inside its own `assets/`
        // subdirectory. The page then loads, finds no `mujoco.js`, and the
        // bench simply never appears: no crash, no error, a first row in the
        // bench list that answers nothing. Found by serving this exact folder
        // to Chromium and reading the request log, which is the only place it
        // is visible.
        let relative = String(request.path.dropFirst())
        if relative == "assets/policies/manifest.json" {
            return send(connection, status: "200 OK", type: "application/json; charset=utf-8",
                        body: assets.policyManifest())
        }
        if relative.hasPrefix("assets/policies/") {
            let file = String(relative.dropFirst("assets/policies/".count))
            guard let bytes = assets.policyBytes(file) else {
                return send(connection, status: "404 Not Found",
                            type: "text/plain; charset=utf-8",
                            body: Data(PhoneBenchReport.uploadNotWired.utf8))
            }
            return send(connection, status: "200 OK", type: Self.octet, body: bytes)
        }
        sendFile(relative, on: connection)
    }

    private func sendFile(_ relative: String, on connection: NWConnection) {
        guard let bytes = assets.file(relative) else {
            return send(connection, status: "404 Not Found", type: "text/plain; charset=utf-8",
                        body: Data("no \(relative) here\n".utf8))
        }
        send(connection, status: "200 OK", type: Self.contentType(relative), body: bytes)
    }

    private static let octet = "application/octet-stream"

    /// WHAT EACH EXTENSION IS, AND `application/wasm` IS THE LOAD-BEARING ONE.
    /// `WebAssembly.instantiateStreaming` refuses anything else outright, and
    /// the refusal names the MIME type rather than the file — which reads like
    /// a corrupt build.
    private static func contentType(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "html":                 return "text/html; charset=utf-8"
        case "js", "mjs":            return "text/javascript; charset=utf-8"
        case "json":                 return "application/json; charset=utf-8"
        case "wasm":                 return "application/wasm"
        case "mjb", "bin", "onnx":   return octet
        default:                     return octet
        }
    }

    /// THE THREE ISOLATION HEADERS GO ON EVERYTHING. `no-store` too: every byte
    /// here comes off the local disk in under a millisecond, and a cached page
    /// pointing at last launch's port is a bench that answers nothing.
    private func send(_ connection: NWConnection, status: String, type: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cross-Origin-Opener-Policy: same-origin\r\n"
        head += "Cross-Origin-Embedder-Policy: require-corp\r\n"
        head += "Cross-Origin-Resource-Policy: same-origin\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - the world

/// The WebView the physics lives in, and the app's handle on it.
///
/// IT IS IN THE VIEW HIERARCHY AND THAT IS NOT COSMETIC. A `WKWebView` that is
/// never added to a window has its content process suspended by iOS, and a
/// suspended process runs no JavaScript — the bench would answer `/health` once
/// and then hang. One point by one point, alpha zero, no hit testing: present
/// enough for WebKit to keep it alive, invisible enough that nobody has to be
/// told it is there.
///
/// AND THE PROCESS CAN STILL BE KILLED. `webViewWebContentProcessDidTerminate`
/// is not an edge case on a phone under memory pressure; it is the normal way
/// this ends. What matters is that the loss is not silent: the world is marked
/// lost, the sentence naming the loss is a tested kit string, anything in
/// flight comes back as an error rather than as a half-finished measurement,
/// and only then is the page reloaded.
@MainActor
final class PhoneBenchHost: NSObject, ObservableObject {

    /// The port the listener came up on, or 0 before it has.
    @Published private(set) var port: Int = 0
    /// Set when the content process died and the rebuilt world is not up yet.
    @Published private(set) var lost = false

    /// The 1×1 the representable hands to SwiftUI. Held here rather than made
    /// in `makeUIView` so the WebView's life belongs to this object and not to
    /// a view that SwiftUI may rebuild.
    let container: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        view.alpha = 0
        return view
    }()

    private let assets = PhoneBenchAssets()
    private var server: PhoneBenchServer?
    private var webView: WKWebView?
    private var ready = false
    private var readiness: Task<Void, Never>?
    /// The tail of the request chain. ONE CALL AT A TIME, because the thing on
    /// the other end is a world with a pose in it: two `/intent`s in flight
    /// would step the same duck twice from the same state and neither answer
    /// would describe what happened.
    private var tail: Task<String, Never>?

    private weak var benches: BenchStore?

    /// Bring the bench up, once.
    func start(benches: BenchStore) {
        guard server == nil else { return }
        self.benches = benches
        guard assets.isPresent else {
            // The folder reference is missing from the build. Nothing to serve,
            // so nothing is claimed: the list keeps its first row, and its
            // address stays unreachable with the sentence that says so.
            print(PhoneBenchReport.notListening)
            return
        }
        let server = PhoneBenchServer(
            assets: assets,
            bridge: { [weak self] target, body in
                guard let self else { return PhoneBenchHost.errorJSON(PhoneBenchReport.notListening) }
                return await self.ask(target, body)
            },
            announce: { [weak self] port in
                Task { @MainActor in self?.listening(on: port) }
            })
        self.server = server
        server.start()
    }

    private func listening(on port: Int) {
        guard self.port != port else { return }
        self.port = port
        benches?.notePhoneBench(port: port)
        buildWebView()
    }

    private func buildWebView() {
        let configuration = WKWebViewConfiguration()
        // NOTHING FROM THIS PAGE OUTLIVES THE LAUNCH. The port changes every
        // time, so a persistent data store would only ever accumulate caches
        // keyed to an origin that no longer exists.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0
        webView.isOpaque = false
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
        self.webView = webView
        load()
    }

    private func load() {
        guard let webView, let url = URL(string: "http://127.0.0.1:\(port)/index.html") else { return }
        ready = false
        webView.load(URLRequest(url: url))
    }

    // MARK: - asking the page

    /// One request, queued behind every request before it.
    ///
    /// THE CHAIN IS THE LOCK. `MainActor` is not one: an `await` inside an
    /// actor-isolated method lets the next call in, which for a stateful world
    /// means two `/intent`s stepping the same duck from the same pose. Each
    /// call waits on the previous task's value, so the order requests arrive in
    /// is the order the world sees.
    func ask(_ target: String, _ body: String) async -> String {
        let previous = tail
        let task = Task<String, Never> { @MainActor in
            _ = await previous?.value
            return await self.perform(target, body)
        }
        tail = task
        return await task.value
    }

    private func perform(_ target: String, _ body: String) async -> String {
        guard let webView, ready, !lost else {
            return Self.errorJSON(lost ? PhoneBenchReport.worldLost
                                       : PhoneBenchReport.notListening)
        }
        do {
            // `callAsyncJavaScript` AND NOT `evaluateJavaScript`, and the
            // difference is the whole bridge. `duckbench` returns a Promise;
            // `evaluateJavaScript` hands back the Promise object itself, which
            // bridges to an empty dictionary — so every answer would be `{}`
            // and every measurement would read as a bench that ran and found
            // nothing. This one awaits it.
            //
            // AND A DEADLINE, BECAUSE A WEDGED CONTENT PROCESS NEVER TERMINATES.
            // The termination callback covers a process that dies; a process
            // that stops making progress — a WebAssembly trap that never
            // resolves the promise — would leave this call waiting forever and
            // every later request queued behind it. The race returns the
            // world-lost sentence after `deadline` seconds and marks the world
            // lost, so the next request reloads rather than joining the queue.
            let answer = try await Self.race(seconds: Self.deadline(for: target, body: body)) { @MainActor in
                try await webView.callAsyncJavaScript(
                    "return await duckbench(target, body);",
                    arguments: ["target": target, "body": body],
                    contentWorld: .page)
            }
            guard let text = answer as? String else {
                return Self.errorJSON(PhoneBenchReport.worldLost)
            }
            return text
        } catch {
            // The commonest way to get here is the content process dying
            // mid-call, which is exactly the case that must not come back as a
            // partial result; the other is the deadline above.
            lost = true
            return Self.errorJSON(PhoneBenchReport.worldLost)
        }
    }

    /// How long one bench request may take before the world is declared lost.
    /// A measure is the longest honest request — a few seconds of physics at
    /// several times real time — so fifteen seconds is a wedged process, not a
    /// slow one.
    static let deadline: Double = 15

    /// The deadline for THIS request. `/tune` runs every drop it is sent for
    /// as many seconds as it is sent, in one request — the tuner's batch is
    /// three drops of six seconds, eighteen seconds of physics — and on a
    /// phone that has never been timed. A fixed fifteen seconds there would
    /// report a slow bench as a lost world and reload it mid-search. So the
    /// request's own numbers set the ceiling: the base, plus three seconds of
    /// wall per second of physics per drop, which is slower than any bench
    /// this project has measured (the Pi does a second of physics in 0.09 s)
    /// and still a wedge, not a wait, past it.
    /// `/climb` GETS THE SAME KIND OF CEILING FOR THE SAME KIND OF REASON. One
    /// cell is one whole episode: the move played from its first keyframe to
    /// its last, then a fifty-tick tail with the standing policy on the legs —
    /// and before any of that, the stair bank is laid out and, afterwards,
    /// cleared again. That is more physics than a `/state` and less than a
    /// `/tune` batch, and how much more depends entirely on the move in the
    /// body: the corpus runs from under a second to several. A fixed fifteen
    /// seconds would be generous for the record and tight for the longest move
    /// on the slowest phone, and being tight here does not read as slow — it
    /// reloads the world mid-grid and turns thirteen good cells into a partial
    /// run. So the request's own keyframes set it, on the same three-seconds-of
    /// -wall-per-second-of-physics allowance `/tune` uses.
    static func deadline(for target: String, body: String) -> Double {
        guard let data = body.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return deadline
        }
        if target.hasPrefix("/tune") {
            let seconds = min(max((top["seconds"] as? Double) ?? 6, 0.2), 30)
            let drops = max((top["drops"] as? [Any])?.count ?? 1, 1)
            return deadline + 3 * seconds * Double(drops)
        }
        // `/chase` IS THE SAME KIND OF REQUEST WITH ITS LENGTH ALREADY IN THE
        // BODY, and simpler for it: an entrant declares its own driven span, so
        // there are no keyframes to read a duration out of. The episode the
        // bench runs is 25 settle ticks under the standing policy, then the
        // entrant driven for `seconds`, then the 50-tick tail — and, either
        // side of all that, the ball is placed for the cell and the world is
        // put back. Same three-seconds-of-wall-per-second-of-physics allowance.
        //
        // `/chase/grid` IS A GET WITH NO BODY and falls out on the guard above,
        // which is right: answering the cell list runs no physics.
        if target.hasPrefix("/chase") {
            // CLAMPED THE WAY THE BENCH CLAMPS IT: `chase_score.mjs` refuses a
            // span outside 0 < seconds <= 30, so a body claiming a thousand
            // seconds buys no extra ceiling here either.
            let seconds = min(max((top["seconds"] as? Double) ?? 5, 0.2), 30)
            let episode = 0.5 + seconds + tailSeconds
            return deadline + 3 * episode
        }
        // `/climb/grid` IS A GET WITH NO BODY and falls out here on the guard
        // above, which is right: answering the cell list runs no physics.
        if target.hasPrefix("/climb") {
            let intent = top["intent"] as? [String: Any]
            let keyframes = (intent?["keyframes"] as? [[String: Any]]) ?? []
            let last = keyframes.compactMap { $0["t"] as? Double }.max() ?? 0
            // THE EPISODE THE BENCH ACTUALLY RUNS: 25 settle ticks (0.5 s)
            // before the track, the track to its last keyframe, 0.8 s of
            // track tail, then the 50-tick policy tail.
            let episode = 0.5 + min(max(last, 0), 30) + 0.8 + tailSeconds
            return deadline + 3 * episode
        }
        return deadline
    }

    /// The tail every climb AND every chase episode runs after the entrant
    /// ends: fifty ticks at the bench's control rate. It is the window
    /// `uprightTailTicks` is counted over — 45 of 50 is what "stable" means in
    /// both challenges — so it is physics that happens on every cell whatever
    /// the entrant's length.
    private static let tailSeconds: Double = 1

    private struct TimedOut: Error {}

    /// Run `work` against a clock; whichever finishes first wins.
    private static func race<T: Sendable>(seconds: Double,
                                          _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOut()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    /// The bench's own error shape, so a client written against the HTTP bench
    /// reads this one without a special case: `DuckBench.readHealth` and
    /// friends already turn `{"error": …}` into `ReadError.bench(…)`.
    nonisolated static func errorJSON(_ sentence: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ["error": sentence]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"error":"the bench on this phone could not say what went wrong"}"#
        }
        return text
    }

    // MARK: - knowing when it is up

    /// WHY READINESS IS TWO QUESTIONS AND NOT ONE. `duckbench` being installed
    /// means the shell is built. It does NOT mean the page is finished with it:
    /// the shipped page is the probe, and after installing the bench it runs
    /// its own physics-parity script — a `/reset`, a policy swap and 250 ticks.
    /// App traffic interleaved with that would step the same world from both
    /// sides, and both answers would be wrong in a way nobody could see.
    ///
    /// THE SECOND QUESTION READS THE PAGE'S DOM, WHICH IS THE ONE PLACE THIS
    /// APP DOES. The probe leaves an ellipsis in its `#health` block until it
    /// has finished and then fills it in, so that is the signal. It is coupling
    /// and it is written down as coupling; a shell with no such element is
    /// treated as ready immediately, and the wait is capped so a probe that
    /// throws half way cannot hold the bench closed forever.
    private static let readinessScript = #"""
    if (typeof duckbench !== 'function') return 'building';
    const pre = document.getElementById('health');
    if (pre && (pre.textContent || '').trim() === '…') return 'settling';
    return 'ready';
    """#

    private func waitUntilReady() {
        readiness?.cancel()
        readiness = Task { @MainActor in
            let deadline = Date().addingTimeInterval(120)
            while !Task.isCancelled {
                guard let webView else { return }
                let raw = try? await webView.callAsyncJavaScript(
                    Self.readinessScript, arguments: [:], contentWorld: .page)
                let state = (raw ?? nil) as? String
                if state == "ready" {
                    ready = true
                    lost = false
                    return
                }
                if Date() > deadline {
                    // THE CAP IS NOT A TIMEOUT ON THE PHYSICS, it is a timeout
                    // on politeness. "settling" means the shell is built and
                    // the page's own self-test has not finished; taking the
                    // bench anyway risks interleaving with it, which is worse
                    // than waiting and better than a bench that never opens.
                    // "building" means the page never got that far, and there
                    // is nothing to open — so the loop stops rather than
                    // asking the same dead page every quarter second forever.
                    if state == "settling" { ready = true; lost = false }
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
}

extension PhoneBenchHost: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitUntilReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        ready = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        ready = false
    }

    /// iOS TOOK THE MEMORY BACK. Everything in that process is gone: the duck's
    /// pose, the loaded policy, and whatever rollouts were part way through.
    ///
    /// THE ORDER HERE IS THE POINT. `ready` goes false and `lost` goes true
    /// FIRST, so any call that arrives from now on — and any call already
    /// suspended in `perform`, whose `callAsyncJavaScript` is about to throw —
    /// comes back as `PhoneBenchReport.worldLost` rather than as a number. Only
    /// then is the page reloaded. An app that reloaded first would have a
    /// window in which a fresh, settled world answered a question about the
    /// world that died.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        lost = true
        readiness?.cancel()
        // Printed rather than only published, because this is the one failure
        // whose whole cost is being invisible: a measurement that quietly
        // restarted is a measurement somebody keeps.
        print(PhoneBenchReport.worldLost)
        load()
    }
}

/// The 1×1 that keeps the world alive, put into the tab view's own hierarchy.
///
/// A CONTAINER RATHER THAN THE WEB VIEW ITSELF. SwiftUI asks for the view
/// before the listener has a port, and the WebView cannot be made until there
/// is a URL to load — so this hands over a box the host fills in later.
struct PhoneBenchHostView: UIViewRepresentable {
    @ObservedObject var host: PhoneBenchHost

    func makeUIView(context: Context) -> UIView { host.container }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
