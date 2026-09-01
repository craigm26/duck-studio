import Foundation
import CoreBluetooth
import StudioKit

/// The CoreBluetooth half of talking to a real Microduck.
///
/// EVERYTHING IT KNOWS ABOUT THE PROTOCOL LIVES IN `DuckLink`. This class owns
/// the radio and the state machine; it owns no constant, no byte layout and no
/// sentence. That split is what let the whole contract be pinned by test
/// without a robot in the room.
///
/// THE ORDER OF OPERATIONS IS THE ONLY SUBTLE THING HERE, and it is not this
/// file's invention: `btd`'s `gatt.rs` says the version READ must happen before
/// any write, because the read is what forces the bond. Skip it and a central
/// subscribes happily, writes, and gets nothing back — "on macOS, sees neither
/// a prompt nor an error." So `didDiscoverCharacteristics` reads, and only the
/// read's completion moves on to subscribing and saying hello.
@MainActor
final class DuckLinkScanner: NSObject, ObservableObject {

    /// A duck seen in a scan, with the peripheral needed to connect to it.
    struct Found: Identifiable {
        let id: UUID
        let sighting: DuckLink.Sighting
        let peripheral: CBPeripheral
    }

    /// Where the handshake has got to, so the screen can show the steps rather
    /// than a spinner. A failed step keeps its reason.
    enum Progress: Equatable {
        case idle
        case running(DuckLink.Step)
        case failed(DuckLink.Step, String)
        case done(DuckLink.Hello, apiByte: UInt8)
    }

    @Published private(set) var found: [Found] = []
    @Published private(set) var scanning = false
    @Published private(set) var progress = Progress.idle
    /// What CoreBluetooth says about the radio and our permission to use it.
    @Published private(set) var radio: String?
    /// The byte the version READ returned, kept beside the version the JSON-RPC
    /// answer reports.
    ///
    /// TWO LAYERS ANSWER THE SAME QUESTION AND THEY CAN DISAGREE. The GATT read
    /// is `API_VERSION as u8` straight out of the daemon binary; `hello`'s
    /// `api_version` comes back through the RPC router. If those two ever
    /// differ, something is proxying or stale, and a tester holding the robot
    /// is the only person who can find that out.
    @Published private(set) var apiByte: UInt8?

    // MARK: - the pairing spike's state
    //
    // A SECOND STATE MACHINE OVER THE SAME RADIO, DELIBERATELY NOT THE SAME ONE.
    // `progress` above is the everyday path: it stops at the first failure,
    // because somebody looking for their duck wants the first thing that went
    // wrong and nothing else. The spike cannot work that way — the whole
    // question it exists to answer is what happens to the steps AFTER the read,
    // when the read never answered — so it records every step and keeps going.
    // Mixing the two into one enum would have made one of them lie.

    /// What each step did, keyed by step — the shape `PairingSpike.Run` takes,
    /// so the screen and the report are reading the same thing rather than two
    /// things that could drift.
    ///
    /// A STEP'S FIRST OUTCOME IS FINAL AND NOTHING OVERWRITES IT. An answer that
    /// arrives after its own deadline expired is dropped rather than replacing
    /// the timeout, and that is the safest of the available wrongs: the run
    /// genuinely did wait out its budget with nothing in hand, which is what
    /// `.timedOut` says, while overwriting it would report a clean success for a
    /// step a client would have given up on. The report may not turn a hang into
    /// a green tick on the strength of a straggler.
    @Published private(set) var spikeOutcomes: [PairingSpike.Step: PairingSpike.Outcome] = [:]

    /// The step in flight. Nil between steps, before the run and after it.
    @Published private(set) var spikeStep: PairingSpike.Step?

    /// True once the run has stopped, however it stopped. The report is offered
    /// on this and not on success, because a run that timed out at every step
    /// is the result Pollen most needs to see.
    @Published private(set) var spikeFinished = false

    /// WHETHER iOS RAISED A PAIRING PROMPT — ANSWERED BY A PERSON, NOT MEASURED.
    ///
    /// There is no CoreBluetooth API that reports this. The pairing sheet is
    /// raised by the system, outside the app, and an app is not told that it
    /// appeared, that it was accepted, or that it was dismissed. So this is
    /// asked out loud after the read step and nowhere derived: `true` and
    /// `false` are what somebody watching the screen said, and `nil` means
    /// nobody said. The report has to be able to tell those three apart,
    /// because a fabricated "no prompt" would send Pollen's investigation in
    /// exactly the wrong direction.
    @Published private(set) var pairingPrompt: Bool?

    /// Raised once, when the read step resolves, so the screen can ask the one
    /// question this harness cannot answer for itself.
    @Published var askingAboutPairingPrompt = false

    /// True while a spike run owns the radio. Every delegate callback below
    /// branches on it, and the everyday path is left exactly as it was.
    private var spiking = false

    /// The hard clock on the step in flight.
    ///
    /// THE ENTIRE HARNESS EXISTS FOR THIS ONE OBJECT. Pollen's symptom is a read
    /// that never returns: "no prompt, no error, no retry. The client waits out
    /// its timeout against a working robot." CoreBluetooth will not call back at
    /// all in that case, so nothing else here would ever run again. This task is
    /// what turns silence into a recorded outcome.
    private var deadline: Task<Void, Never>?

    /// When each step started, so a late answer can still be timed from the
    /// right moment rather than from now.
    private var startedAt: [PairingSpike.Step: Double] = [:]

    /// Set when the version read times out.
    ///
    /// It exists so a belated answer to the read is RECOGNISED rather than fed
    /// to the line reassembler as if it were the start of a JSON line — one
    /// stray byte in that buffer would corrupt the next real answer and turn a
    /// clean finding into an unexplainable one.
    private var readTimedOut = false

    /// The PIN the person typed, held from the moment the run starts.
    private var pin = PairingSpike.factoryPIN

    private var central: CBCentralManager?
    private var connected: CBPeripheral?
    private var pipe: CBCharacteristic?
    private var reassembler = DuckLink.Reassembler()
    /// Set once a scan has been asked for but the radio was not ready yet.
    private var wantsScan = false
    /// The step whose write is in flight, so a late failure is blamed on the
    /// step that caused it rather than on whichever one happens to be running.
    /// A stored property, so it lives on the class rather than in an extension.
    private var wroteFor: PairingSpike.Step?
    /// Peripherals this app has connected to before.
    ///
    /// STORED AFTER A SUCCESSFUL HANDSHAKE, NOT AFTER A SIGHTING. An identifier
    /// is only worth keeping once "serves our characteristic" has been proven —
    /// that is the one authoritative identity test, and it is knowable solely
    /// after connecting.
    private var remembered: Set<UUID> {
        get { Set((UserDefaults.standard.array(forKey: Self.rememberedKey) as? [String] ?? [])
                    .compactMap(UUID.init(uuidString:))) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: Self.rememberedKey) }
    }
    private static let rememberedKey = "duck.link.known"

    private static let service = CBUUID(string: DuckLink.serviceUUID)
    private static let rpc = CBUUID(string: DuckLink.rpcUUID)

    override init() {
        super.init()
    }

    /// Start the radio. Called when the screen appears, NOT in `init` — a
    /// `CBCentralManager` raises the system permission prompt the moment it is
    /// created, and an app that asks for Bluetooth on launch, for a screen most
    /// people never open, deserves the refusal it gets.
    func begin() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        wantsScan = true
        startIfReady()
    }

    func stop() {
        central?.stopScan()
        scanning = false
        if let connected { central?.cancelPeripheralConnection(connected) }
        connected = nil
        pipe = nil
    }

    private func startIfReady() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        found.removeAll()
        scanning = true

        // ALREADY-BONDED DUCKS FIRST, WITHOUT WAITING FOR A SIGHTING. iOS can
        // hand back a peripheral by identifier and let us connect with no fresh
        // advertisement at all, which turns reconnection from "wait for the
        // radio to be heard" into latency. It does nothing for a FIRST
        // connection — that still needs the scan below.
        for known in central.retrievePeripherals(withIdentifiers: Array(remembered)) {
            note(known, name: known.name ?? "Microduck", manufacturer: nil, rssi: nil)
        }

        // 🔴 UNFILTERED, AND THIS IS NOT A PREFERENCE. Pollen measured it and
        // wrote it down in `app-path-design.md` §3.3: "CoreBluetooth honours the
        // filter strictly, and a bonded peripheral frequently advertises with an
        // empty service list. Filtered, it is then never reported at all — not
        // 'reported without services', absent." Their own tool reported
        // `no robot found` on roughly half its runs from exactly this, and a
        // first fix survived because a name fallback could only match
        // peripherals the filtered scan had already returned.
        //
        // So the filter moves here, into `note`, where a candidate is judged on
        // the strongest evidence it actually carries.
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    /// Connect to one and run the whole handshake.
    func handshake(with duck: Found) {
        guard let central else { return }
        central.stopScan()
        scanning = false
        reassembler = DuckLink.Reassembler()
        progress = .running(.connect)
        connected = duck.peripheral
        duck.peripheral.delegate = self
        central.connect(duck.peripheral, options: nil)
    }

    private func fail(_ step: DuckLink.Step, _ why: String) {
        progress = .failed(step, why)
    }
}

extension DuckLinkScanner: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                radio = nil
                startIfReady()
            case .poweredOff:
                radio = "Bluetooth is switched off."
            case .unauthorized:
                // THE ONE A PERSON CAN FIX, AND THE ONE WITH THE LEAST HELPFUL
                // DEFAULT MESSAGE. Naming the row in Settings is the difference
                // between a dead screen and a two-tap fix.
                radio = "Microduck Studio is not allowed to use Bluetooth. Settings, Privacy & "
                      + "Security, Bluetooth."
            case .unsupported:
                radio = "This device has no Bluetooth LE."
            case .resetting:
                radio = "The Bluetooth stack is restarting."
            default:
                radio = "Bluetooth is not ready yet."
            }
            if central.state != .poweredOn { scanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        // COPIED OUT ON THIS THREAD, because `advertisementData` is not Sendable
        // and must not cross the hop.
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        // -127 is CoreBluetooth's "no reading", not a very distant duck.
        let rssi = RSSI.intValue == 127 || RSSI.intValue == -127 ? nil : RSSI.intValue
        let servesUs = advertised.contains(Self.service)
        Task { @MainActor in
            guard servesUs || self.remembered.contains(peripheral.identifier)
                    || (name.map(DuckLink.looksLikeADuck) ?? false) else { return }
            self.note(peripheral, name: name ?? "Microduck",
                      manufacturer: manufacturer, rssi: rssi)
        }
    }

    /// Add or refresh a candidate.
    ///
    /// THREE TIERS OF EVIDENCE, STRONGEST FIRST, and none of them is proof.
    /// Pollen's own note is precise about this: the advertised UUID is the best
    /// hint, a known name or a stored identifier is the next, and "serves our
    /// characteristic" is "the only authoritative identity test — it is knowable
    /// solely after connecting". So a listing is a list of CANDIDATES, and the
    /// handshake is what settles it.
    @MainActor private func note(_ peripheral: CBPeripheral, name: String,
                                 manufacturer: Data?, rssi: Int?) {
        let address = manufacturer.map(DuckLink.address(fromManufacturerData:)) ?? .notBroadcast
        let sighting = DuckLink.Sighting(name: name, rssi: rssi, address: address)
        let id = peripheral.identifier
        if let i = found.firstIndex(where: { $0.id == id }) {
            found[i] = Found(id: id, sighting: sighting, peripheral: peripheral)
        } else {
            found.append(Found(id: id, sighting: sighting, peripheral: peripheral))
        }
        // THE SPIKE'S SCAN STEP ENDS AT THE FIRST SIGHTING, NOT AT THE PICK.
        // What is worth timing here is the radio: Pollen measured advertising
        // silences of 9, 14, 17 and once 31 seconds on the old default. How long
        // a person then takes to read the list and tap a row is not a fact about
        // the robot, so it is kept out of the number.
        if spiking, spikeStep == .scan { complete(.scan) { .ok(seconds: $0) } }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            if spiking { return complete(.connect) { .ok(seconds: $0) } }
            progress = .running(.discover)
            peripheral.discoverServices([Self.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        let why = error?.localizedDescription ?? "the duck did not accept the connection"
        Task { @MainActor in
            if spiking { return complete(.connect) { .refused(seconds: $0, why) } }
            fail(.connect, why)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        let why = error?.localizedDescription
        Task { @MainActor in
            pipe = nil
            if spiking {
                // A LINK THAT DROPS ENDS THE RUN RATHER THAN ADVANCING IT.
                // Every step after this one would write into nothing and time
                // out, and eight identical timeouts caused by one disconnect
                // would read like eight findings. The step in flight keeps the
                // disconnect as its reason and the report stops there.
                guard !spikeFinished else { return }
                let reason = why ?? "the duck disconnected"
                if let step = spikeStep { finish(step) { .refused(seconds: $0, reason) } }
                return endSpike()
            }
            // A DISCONNECT AFTER A COMPLETED HELLO IS NOT A FAILURE. The
            // handshake is the whole job; the link closing afterwards is what
            // is supposed to happen.
            if case .done = progress { return }
            if case .running(let step) = progress {
                fail(step, why ?? "the duck disconnected")
            }
        }
    }
}

extension DuckLinkScanner: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let why = error?.localizedDescription
        Task { @MainActor in
            let missing = peripheral.services?.first(where: { $0.uuid == Self.service })
            if spiking {
                if let why { return complete(.discover) { .refused(seconds: $0, why) } }
                guard let service = missing else {
                    return complete(.discover) {
                        .refused(seconds: $0, "That device is not serving the robot's service.")
                    }
                }
                // STILL THE SAME STEP AND THE SAME CLOCK. Services and
                // characteristics are two round trips to the robot but one
                // question — "is the RPC pipe there" — so they share a step.
                return peripheral.discoverCharacteristics([Self.rpc], for: service)
            }
            if let why { return fail(.discover, why) }
            guard let service = missing else {
                return fail(.discover, "That device is not serving the robot's service.")
            }
            peripheral.discoverCharacteristics([Self.rpc], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        let why = error?.localizedDescription
        Task { @MainActor in
            let rpcPipe = service.characteristics?.first(where: { $0.uuid == Self.rpc })
            if spiking {
                if let why { return complete(.discover) { .refused(seconds: $0, why) } }
                guard let rpcPipe else {
                    return complete(.discover) {
                        .refused(seconds: $0, "The service is there but the RPC characteristic is not.")
                    }
                }
                self.pipe = rpcPipe
                return complete(.discover) { .ok(seconds: $0) }
            }
            if let why { return fail(.discover, why) }
            guard let pipe = rpcPipe else {
                return fail(.discover, "The service is there but the RPC characteristic is not.")
            }
            self.pipe = pipe
            // THE READ, BEFORE ANYTHING ELSE. This is what raises the pairing
            // prompt; a subscribe first would succeed and then swallow the
            // first write with no error anywhere. See `DuckLink.Step`.
            progress = .running(.readVersion)
            peripheral.readValue(for: pipe)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let why = error?.localizedDescription
        let value = characteristic.value
        let subscribed = characteristic.isNotifying
        Task { @MainActor in
            if spiking { return spikeValue(value, why: why, subscribed: subscribed) }
            // ONE CALLBACK, TWO MEANINGS, and only the state tells them apart:
            // CoreBluetooth delivers both a read's answer and every notification
            // through this method. Before we subscribe it can only be the read.
            if case .running(.readVersion) = progress {
                if let why { return fail(.readVersion, why) }
                guard let value, let version = DuckLink.apiVersion(fromRead: value) else {
                    return fail(.readVersion,
                                "The version read answered \(value?.count ?? 0) bytes; the robot "
                                + "answers exactly one.")
                }
                apiByte = version
                progress = .running(.subscribe)
                peripheral.setNotifyValue(true, for: characteristic)
                return
            }
            guard subscribed, let value else { return }
            if let why { return fail(.hello, why) }
            do {
                for line in try reassembler.feed(value) {
                    let hello = try DuckLink.hello(fromLine: line)
                    progress = .done(hello, apiByte: apiByte ?? hello.apiVersion.asByte)
                    // PROVEN, SO WORTH REMEMBERING. Now — and only now — is it
                    // established that this peripheral is a Microduck, so its
                    // identifier can be stored and `retrievePeripherals` can
                    // skip the scan entirely next time.
                    remembered.insert(peripheral.identifier)
                    // THE JOB IS DONE, SO LET GO OF THE RADIO. A phone that
                    // stays bonded and connected to a robot it has finished
                    // asking about is a phone holding a slot somebody else
                    // wants.
                    central?.cancelPeripheralConnection(peripheral)
                }
            } catch let failure as DuckLink.Reassembler.Failure {
                fail(.hello, failure.message)
            } catch let failure as DuckLink.LinkError {
                fail(.hello, failure.message)
            } catch {
                fail(.hello, error.localizedDescription)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        let why = error?.localizedDescription
        let notifying = characteristic.isNotifying
        Task { @MainActor in
            if spiking {
                if let why { return complete(.subscribe) { .refused(seconds: $0, why) } }
                guard notifying else { return }
                return complete(.subscribe) { .ok(seconds: $0) }
            }
            if let why { return fail(.subscribe, why) }
            guard characteristic.isNotifying else { return }
            progress = .running(.hello)
            do {
                let line = try DuckLink.helloRequest()
                // THE MTU IS ASKED FOR, NOT ASSUMED. CoreBluetooth already
                // reports the usable payload for each write type, so this is
                // where a good link earns its bigger writes and a phone that
                // never renegotiates falls back to twenty bytes on its own.
                let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
                for chunk in DuckLink.chunks(line, mtu: mtu) {
                    peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
                }
            } catch {
                fail(.hello, error.localizedDescription)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let error else { return }
        let why = error.localizedDescription
        Task { @MainActor in
            if spiking {
                // A REFUSED WRITE IS THE OTHER HALF OF POLLEN'S QUESTION. If the
                // read never bonded the link, this is where the robot says so —
                // and an error here, with a reason in it, is a completely
                // different finding from the silence a timeout records.
                //
                // BLAMED ON THE STEP THAT WROTE, NOT THE ONE IN FLIGHT. A write
                // is chunked at the MTU, so several callbacks land per step and
                // a late one can arrive after the step that issued it has timed
                // out and the next has begun — filing hello's refusal against
                // authenticate. `route` already refuses to dispatch by "whatever
                // is running" for the same reason and says so; this is the same
                // rule on the write side.
                guard let step = wroteFor, step == spikeStep else { return }
                return complete(step) { .refused(seconds: $0, why) }
            }
            if case .done = progress { return }
            fail(.hello, why)
        }
    }
}

private extension UInt32 {
    var asByte: UInt8 { UInt8(truncatingIfNeeded: self) }
}

// MARK: - the pairing spike

/// The phone spike Pollen's own roadmap says their app is blocked on.
///
/// WHY THIS IS A SECOND PATH AND NOT A FLAG ON THE FIRST. `docs/project/roadmap.md`
/// M6 names the missing thing exactly: "a phone spike — scan, connect, `hello`,
/// authenticate, `system.info` with `--require-pairing` on, on a real iPhone and
/// a real Android — because §5.5 is currently a fact about CoreBluetooth on a
/// laptop." And §5.5's fact is a HANG, not an error: "CoreBluetooth issues the
/// Read Request, BlueZ refuses it for insufficient encryption, and nothing
/// resolves it — no prompt, no error, no retry."
///
/// THAT ONE SENTENCE DECIDES THE SHAPE OF EVERYTHING BELOW. A harness that
/// reported "failed" would be worthless here, because the finding they need is
/// the difference between three things that all look the same on a stuck screen:
/// a step that SUCCEEDED, a step that was REFUSED with a reason somebody can be
/// shown, and a step that produced NOTHING AT ALL until its clock ran out. Only
/// the third is the bug being chased. So every step runs under its own hard
/// deadline from `PairingSpike.Step.timeoutSeconds`, an expired deadline is
/// recorded as `.timedOut` rather than as a failure, and — the part the everyday
/// path could not do — the run CARRIES ON afterwards. A read that times out
/// followed by a subscribe that succeeds and a write that is answered by silence
/// is the exact signature §5.5 predicts, and only a harness that refuses to stop
/// at the first silence can see it.
///
/// `PairingSpike` owns the order, the budgets, what an outcome means and every
/// sentence in the report. This half owns the radio and a stopwatch.
extension DuckLinkScanner {

    /// A monotonic reading, in seconds.
    ///
    /// UPTIME RATHER THAN A WALL CLOCK, because a clock that steps while a step
    /// is in flight — an NTP correction, a timezone change, a person setting the
    /// date — would turn a measurement into fiction. A negative or absurdly long
    /// duration in this report is exactly the kind of number a reader would
    /// believe.
    static func clock() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: running one

    /// Start a spike run: power the radio, scan unfiltered, and put a hard clock
    /// on the scan itself.
    ///
    /// THE SCAN IS A TIMED STEP LIKE ANY OTHER, because "no duck ever appeared"
    /// is the outcome a listening screen is worst at reporting — it shows a
    /// spinner, forever, and a duck that is switched off looks exactly like a
    /// duck that is two seconds away.
    func beginSpike() {
        spiking = true
        spikeFinished = false
        spikeOutcomes.removeAll()
        startedAt.removeAll()
        readTimedOut = false
        pairingPrompt = nil
        askingAboutPairingPrompt = false
        apiByte = nil
        reassembler = DuckLink.Reassembler()
        begin()
        start(.scan)
    }

    /// Connect to the duck the person picked and run the rest of the spike.
    ///
    /// - Parameter pin: What `system.authenticate` will be given. Editable
    ///   because a robot that has been provisioned no longer answers to the
    ///   factory one, and a spike that could only ever try `000000` would bring
    ///   back a refusal that says nothing about pairing.
    func runSpike(with duck: Found, pin: String) {
        guard spiking, !spikeFinished, let central else { return }
        self.pin = pin
        central.stopScan()
        scanning = false
        reassembler = DuckLink.Reassembler()
        connected = duck.peripheral
        duck.peripheral.delegate = self
        start(.connect)
        central.connect(duck.peripheral, options: nil)
    }

    /// Put the radio down. A run that is abandoned keeps whatever it recorded.
    func stopSpike() {
        guard spiking else { return }
        endSpike()
        spiking = false
    }

    /// Record what a person said about the pairing prompt.
    ///
    /// `nil` IS A REAL ANSWER HERE and it means nobody watched — see
    /// `pairingPrompt`, and see `Run.pairingPromptShown`, which refuses to treat
    /// "not observed" as "no prompt appeared".
    func answerPairingPrompt(_ answer: Bool?) {
        pairingPrompt = answer
        askingAboutPairingPrompt = false
    }

    /// The finished run, assembled from what was measured and what was said.
    ///
    /// - Parameters:
    ///   - requirePairing: Whether `btd` was started with the flag on. NOT
    ///     KNOWABLE FROM HERE — nothing in the advertisement, the GATT table or
    ///     the RPC surface says which way the daemon was launched — so it is
    ///     asked of the person who launched it. It is also the easiest way to
    ///     produce a false green, which is why the kit's reading refuses to be
    ///     encouraging about a read that succeeded with the flag off.
    ///   - deviceModel: The hardware identifier this ran on. §5.5 is "a fact
    ///     about CoreBluetooth on a laptop" and a report that cannot name the
    ///     phone that turned it into a fact about a phone is not evidence.
    func spikeRun(requirePairing: Bool,
                  deviceModel: String,
                  iOSVersion: String) -> PairingSpike.Run {
        PairingSpike.Run(outcomes: spikeOutcomes,
                         pairingPromptShown: pairingPrompt,
                         requirePairing: requirePairing,
                         deviceModel: deviceModel,
                         iOSVersion: iOSVersion,
                         robotAPIVersion: apiByte)
    }

    // MARK: the clock

    /// Begin a step and arm its deadline.
    private func start(_ step: PairingSpike.Step) {
        deadline?.cancel()
        spikeStep = step
        startedAt[step] = Self.clock()
        let seconds = step.timeoutSeconds
        deadline = Task { @MainActor [weak self] in
            // `try?` SWALLOWS THE CANCELLATION AND THEN THE FLAG IS CHECKED. A
            // cancelled sleep throws, and treating that throw as "the step timed
            // out" would file a timeout against every step that finished
            // normally — the report would be all timeouts and not one of them
            // real, which is the same worthlessness as reporting them all as
            // failures.
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.timedOut(step)
        }
    }

    /// Record a step's ending without moving on. Used where the run is about to
    /// stop anyway and advancing would only write into a dead link.
    ///
    /// - Parameter ending: Given the elapsed seconds, the outcome. The duration
    ///   lives inside `PairingSpike.Outcome` — a refusal and a hang are both
    ///   only meaningful with a number beside them — so the caller says what
    ///   happened and this says when.
    private func finish(_ step: PairingSpike.Step,
                        _ ending: (Double) -> PairingSpike.Outcome) {
        guard spiking, spikeStep == step else { return }
        deadline?.cancel()
        deadline = nil
        spikeStep = nil
        let started = startedAt[step] ?? Self.clock()
        // FIRST OUTCOME WINS. See `spikeOutcomes`.
        if spikeOutcomes[step] == nil {
            spikeOutcomes[step] = ending(Self.clock() - started)
        }
    }

    /// Record a step's ending and move the run on.
    private func complete(_ step: PairingSpike.Step,
                          _ ending: (Double) -> PairingSpike.Outcome) {
        guard spiking, spikeStep == step else { return }
        finish(step, ending)
        advance(after: step)
    }

    /// A deadline expired: nothing came back at all.
    private func timedOut(_ step: PairingSpike.Step) {
        guard spiking, spikeStep == step else { return }
        if step == .readVersion { readTimedOut = true }
        finish(step) { .timedOut(afterSeconds: $0) }
        advance(after: step)
    }

    /// Stop the run and let go of the radio.
    private func endSpike() {
        deadline?.cancel()
        deadline = nil
        spikeStep = nil
        spikeFinished = true
        central?.stopScan()
        scanning = false
        if let connected { central?.cancelPeripheralConnection(connected) }
        connected = nil
        pipe = nil
    }

    // MARK: what happens next

    /// The one place that decides whether the run continues — and it continues
    /// through a timeout on purpose.
    ///
    /// THE READ IS THE HINGE. Everything before it is plumbing: with no link
    /// there is nothing to write to and with no characteristic there is nothing
    /// to write on, so those endings stop the run. But a read that answered
    /// nothing is the START of the experiment rather than the end of it. The
    /// next questions are whether a subscribe still succeeds and whether the
    /// first write is then swallowed in silence, which is precisely what
    /// `gatt.rs` predicts — "a client subscribes, has its first write silently
    /// refused, and (on macOS) sees neither a prompt nor an error" — and what
    /// nobody has yet watched a phone do.
    private func advance(after step: PairingSpike.Step) {
        let moved = spikeOutcomes[step]?.isOK ?? false

        switch step {
        case .scan:
            // A sighting hands the choice to the person; nothing is auto-picked,
            // because "serves our characteristic" is the only authoritative
            // identity test and connecting to a stranger's headphones is not a
            // finding.
            if !moved { endSpike() }

        case .connect:
            guard moved, let peripheral = connected else { return endSpike() }
            start(.discover)
            peripheral.discoverServices([Self.service])

        case .discover:
            guard moved, let peripheral = connected, let pipe else { return endSpike() }
            start(.readVersion)
            peripheral.readValue(for: pipe)

        case .readVersion:
            // ASKED HERE, AND THE RUN DOES NOT WAIT FOR THE ANSWER. iOS raises
            // the pairing sheet outside the app and tells the app nothing about
            // it — not that it appeared, not that it was accepted — so a person
            // has to say. Stalling the radio on a human would corrupt every
            // timing after this one, and the report is built to carry `nil`.
            askingAboutPairingPrompt = true
            guard let peripheral = connected, let pipe else { return endSpike() }
            start(.subscribe)
            peripheral.setNotifyValue(true, for: pipe)

        case .subscribe:
            // Written even when the subscription failed. A write with no way of
            // hearing the answer will time out, and that timeout is still
            // evidence about the link rather than about this app.
            start(.hello)
            send(failing: .hello) { try DuckLink.helloRequest(id: SpikeWire.id(for: .hello)) }

        case .hello:
            start(.authenticate)
            send(failing: .authenticate) { try SpikeWire.authenticate(pin: self.pin) }

        case .authenticate:
            start(.systemInfo)
            send(failing: .systemInfo) { try SpikeWire.systemInfo() }

        case .systemInfo:
            endSpike()
        }
    }

    /// Build a line and put it on the wire in MTU-sized pieces.
    private func send(failing step: PairingSpike.Step, request: () throws -> Data) {
        wroteFor = step
        guard let peripheral = connected, let pipe else {
            return complete(step) { .refused(seconds: $0, "The link was gone before the write.") }
        }
        do {
            let line = try request()
            // THE MTU IS ASKED FOR, NOT ASSUMED — the same reason as the everyday
            // path: CoreBluetooth already reports the usable payload for each
            // write type, so a good link earns its bigger writes and a phone
            // that never renegotiates falls back to twenty bytes on its own,
            // without this file inventing a number.
            let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
            for chunk in DuckLink.chunks(line, mtu: mtu) {
                peripheral.writeValue(chunk, for: pipe, type: .withResponse)
            }
        } catch {
            let why = error.localizedDescription
            complete(step) { .refused(seconds: $0, why) }
        }
    }

    // MARK: what came back

    /// Everything `didUpdateValueFor` means while a spike is running.
    private func spikeValue(_ value: Data?, why: String?, subscribed: Bool) {
        if spikeStep == .readVersion {
            if let why { return complete(.readVersion) { .refused(seconds: $0, why) } }
            guard let value, let version = DuckLink.apiVersion(fromRead: value) else {
                let count = value?.count ?? 0
                return complete(.readVersion) {
                    .refused(seconds: $0, "The version read answered \(count) bytes; the robot "
                                        + "answers exactly one.")
                }
            }
            apiByte = version
            return complete(.readVersion) { .ok(seconds: $0) }
        }

        // A READ THAT ANSWERS AFTER ITS OWN CLOCK RAN OUT. The byte is kept —
        // knowing which version the robot runs is worth having however late it
        // arrived — but the step keeps its `.timedOut`, because a client that
        // had given up is what the report is describing. Recognising it here
        // also keeps a stray unframed byte out of the reassembler, where it
        // would have corrupted the next real answer. Only trusted before the
        // subscription exists: once notifications flow, CoreBluetooth delivers
        // both through this same callback with nothing to tell them apart.
        if readTimedOut, !subscribed, let value,
           let version = DuckLink.apiVersion(fromRead: value) {
            apiByte = version
            return
        }

        guard subscribed else { return }
        // THE ERROR IS READ BEFORE THE VALUE, because a failed notification
        // usually arrives with no value at all — and a step whose refusal was
        // dropped for want of bytes would be reported as a timeout, which is
        // the one substitution this harness must never make.
        if let why, let step = spikeStep {
            return complete(step) { .refused(seconds: $0, why) }
        }
        guard let value else { return }
        do {
            for line in try reassembler.feed(value) { route(line) }
        } catch let failure as DuckLink.Reassembler.Failure {
            let message = failure.message
            if let step = spikeStep { complete(step) { .refused(seconds: $0, message) } }
        } catch {
            let why = error.localizedDescription
            if let step = spikeStep { complete(step) { .refused(seconds: $0, why) } }
        }
    }

    /// File one NDJSON line against the request that asked for it.
    ///
    /// BY ID, NOT BY "WHATEVER STEP IS RUNNING". They are the same thing right
    /// up until a step times out, and then they are the difference between a
    /// true report and a fabricated one: a `hello` answer that arrives while
    /// `system.authenticate` is in flight would, under step-dispatch, be
    /// recorded as an authenticate that succeeded and was never answered. The
    /// id is what stops this harness from inventing the one thing it exists to
    /// measure honestly.
    private func route(_ line: Data) {
        guard let reply = SpikeWire.reply(fromLine: line) else {
            // A LINE THAT ARRIVED IS NOT SILENCE, AND THIS IS THE ONE
            // SUBSTITUTION THE SPIKE EXISTS TO PREVENT. Discarding a reply this
            // harness cannot parse let the step run out its budget and be
            // written as "no answer and no error" — which is §5.5's exact
            // symptom, reported about a robot that answered. If the duck said
            // something we could not read, that is a finding about this app and
            // it belongs in the report as one.
            if let step = spikeStep {
                let text = String(data: line.prefix(200), encoding: .utf8) ?? "not UTF-8"
                complete(step) { .refused(seconds: $0,
                    "the duck answered and this app could not read the answer: \(text)") }
            }
            return
        }
        guard let step = SpikeWire.step(forID: reply.id) else {
            // An id we did not issue. Same rule: something answered.
            if let waiting = spikeStep {
                complete(waiting) { .refused(seconds: $0,
                    "the duck answered with id \(reply.id), which this app did not send") }
            }
            return
        }
        // A reply to a step that already ended is dropped — see `spikeOutcomes`.
        guard spikeStep == step else { return }
        switch reply.trouble {
        case .some(let why): complete(step) { .refused(seconds: $0, why) }
        case .none: complete(step) { .ok(seconds: $0) }
        }
    }
}

/// The two JSON-RPC calls this spike makes that `DuckLink` does not yet build,
/// and the id-and-error read that files their answers.
///
/// 🔴 THIS BELONGS IN `PairingSpike`, IN StudioKit, AND IS HERE ONLY BECAUSE IT
/// IS NOT THERE YET. Every rule this project has says so: StudioKit computes and
/// holds every sentence, the app target draws, and a claim about the protocol
/// written here is a claim no `swift test` can pin. `DuckLink` already owns
/// `helloRequest` and the NDJSON framing for exactly that reason, and
/// `PairingSpike` owns the step order and the report — but neither ships a
/// builder for `system.authenticate` or `system.info`, and neither reads a
/// JSON-RPC id off a line. Without those two the roadmap's sequence stops at
/// `hello` and the spike does not answer the question it was written for.
///
/// So this is the smallest thing that closes the gap, kept in one type, doing
/// nothing but the three calls the kit is missing. MOVE IT: when `PairingSpike`
/// grows `authenticateRequest(pin:id:)`, `systemInfoRequest(id:)` and a reply
/// reader, delete this and point the three call sites at them. Nothing else in
/// this file knows the protocol.
///
/// The method names are `system.authenticate` and `system.info` — the ones the
/// roadmap's M6 sentence names, with `system.authenticate` the PIN method added
/// in API_VERSION v4. The framing is `DuckLink`'s: one JSON object per line,
/// newline-terminated, chunked at the MTU by `DuckLink.chunks`.
private enum SpikeWire {

    /// Which id each request goes out under.
    ///
    /// CLIENT-SIDE BOOKKEEPING RATHER THAN A CLAIM ABOUT THE ROBOT — JSON-RPC
    /// lets the caller choose its own ids. These exist so an answer can be
    /// matched to the request that asked for it; see `route`.
    static func id(for step: PairingSpike.Step) -> Int {
        switch step {
        case .hello: return 1
        case .authenticate: return 2
        case .systemInfo: return 3
        default: return 0
        }
    }

    static func step(forID id: Int) -> PairingSpike.Step? {
        switch id {
        case 1: return .hello
        case 2: return .authenticate
        case 3: return .systemInfo
        default: return nil
        }
    }

    /// `system.authenticate`, framed and ready to write.
    static func authenticate(pin: String) throws -> Data {
        try line(["jsonrpc": "2.0", "id": id(for: .authenticate),
                  "method": "system.authenticate", "params": ["pin": pin]])
    }

    /// `system.info`, framed and ready to write.
    static func systemInfo() throws -> Data {
        try line(["jsonrpc": "2.0", "id": id(for: .systemInfo),
                  "method": "system.info", "params": [String: String]()])
    }

    private static func line(_ body: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    /// What a robot's answer was for, and whether it was a refusal.
    ///
    /// DELIBERATELY DOES NOT READ THE RESULT. What `system.info` returns is not
    /// what this spike is measuring — the question is whether an authenticated
    /// call crosses a bonded link at all — and parsing fields nothing here
    /// displays would be inventing protocol knowledge in the wrong target twice
    /// over.
    static func reply(fromLine line: Data) -> (id: Int, trouble: String?)? {
        guard let top = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = top["id"] as? Int else { return nil }
        guard let error = top["error"] as? [String: Any] else { return (id, nil) }
        let message = error["message"] as? String ?? "no reason given"
        let code = error["code"] as? Int ?? 0
        return (id, "The duck refused: \(message) (\(code))")
    }
}
