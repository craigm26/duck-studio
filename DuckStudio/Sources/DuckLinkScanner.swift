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

    private var central: CBCentralManager?
    private var connected: CBPeripheral?
    private var pipe: CBCharacteristic?
    private var reassembler = DuckLink.Reassembler()
    /// Set once a scan has been asked for but the radio was not ready yet.
    private var wantsScan = false

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
        // ALLOW DUPLICATES OFF. The RSSI would refresh, and the cost is a
        // callback per advertisement per duck for as long as the screen is open.
        // A listing that settles is easier to read than one that flickers.
        central.scanForPeripherals(withServices: [Self.service], options: nil)
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
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "unnamed duck"
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let address = manufacturer.map(DuckLink.address(fromManufacturerData:))
            ?? .notBroadcast
        // -127 is CoreBluetooth's "no reading", not a very distant duck.
        let rssi = RSSI.intValue == 127 || RSSI.intValue == -127 ? nil : RSSI.intValue
        let id = peripheral.identifier
        Task { @MainActor in
            let sighting = DuckLink.Sighting(name: name, rssi: rssi, address: address)
            if let i = found.firstIndex(where: { $0.id == id }) {
                found[i] = Found(id: id, sighting: sighting, peripheral: peripheral)
            } else {
                found.append(Found(id: id, sighting: sighting, peripheral: peripheral))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            progress = .running(.discover)
            peripheral.discoverServices([Self.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        let why = error?.localizedDescription ?? "the duck did not accept the connection"
        Task { @MainActor in fail(.connect, why) }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        let why = error?.localizedDescription
        Task { @MainActor in
            pipe = nil
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
            if let why { return fail(.discover, why) }
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
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
            if let why { return fail(.discover, why) }
            guard let pipe = service.characteristics?.first(where: { $0.uuid == Self.rpc }) else {
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
        Task { @MainActor in
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
            if case .done = progress { return }
            fail(.hello, why)
        }
    }
}

private extension UInt32 {
    var asByte: UInt8 { UInt8(truncatingIfNeeded: self) }
}
