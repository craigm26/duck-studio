import Foundation

// Five things that must hold before any planner (hosted, on your network, or on this phone) is
// offered to people. They were found while writing the privacy page's planner and Children
// sections (microduck-com PR #38, "Gaps"). Each lives here, in the kit, so Linux tests hold it:
//
// 1. Every step a model chose carries a label saying so, with the provider and model
//    (`PlannerDisclosure.stepLabel`). DuckTalk and other fixed rules get none.
// 2. Local, network and on-phone planners carry the same "a model, not a person" line as the
//    hosted key screen (`LocalPlannerWords.aiDisclosure`).
// 3. A camera picture goes to a planner only with that provider's own switch on, off by default
//    (`PlannerSafetySettings.cameraConsent`, `PlannerFrameGate.allows`).
// 4. Faces are blurred before a picture leaves, and when they cannot be, no picture goes
//    (`PlannerFrameGate.frame`, which blurs, then encodes, in that order).
// 5. An adult's agreement is recorded (date, app version, text version; nothing personal) and is
//    required before a key is saved or a planner used. New words ask again (`ParentalAgreement`).
//
// Nothing here makes a network call. Stop is not here and does not pass through here.

// MARK: - 1. the label on each step

/// The mark a run shows beside a step a model chose: that a model, not a person, chose it, and
/// which provider and model. Built from `Decided.provider`, so it cannot drift from the step.
public struct PlannerStepLabel: Equatable, Sendable {
    /// "Chosen by an AI model, not a person"
    public let headline: String
    /// "Anthropic", "Your computer", "This phone"
    public let provider: String
    /// The model as the provider reported it: "claude-haiku-5-5", "qwen3.5:4b".
    public let model: String

    /// The whole label as one line, for a row or for VoiceOver.
    public var line: String { "\(headline): \(provider), \(model)." }
}

public enum PlannerDisclosure {
    /// Planners that are fixed rules, not models. They read words or follow a script, so a step
    /// they chose gets no AI label. Every other planner id is a model: an id nobody listed here
    /// is labelled, so a new planner is never shown unlabelled by omission.
    public static let notModels: Set<String> = [PlannerInfo.duckTalk.id]

    public static func isModel(_ info: PlannerInfo) -> Bool { !notModels.contains(info.id) }

    /// The label for one step, or nil when no model chose it.
    public static func stepLabel(for decided: Decided?, device: DeviceWords = .current) -> PlannerStepLabel? {
        stepLabel(for: decided?.provider, device: device)
    }

    public static func stepLabel(for info: PlannerInfo?, device: DeviceWords = .current) -> PlannerStepLabel? {
        guard let info, isModel(info) else { return nil }
        return PlannerStepLabel(headline: PlannerSafetyWords.chosenByModel,
                                provider: providerName(info, device: device), model: modelName(info))
    }

    /// The label a step will carry when this saved endpoint is the planner. The settings screen
    /// shows it before any planner runs.
    public static func stepLabel(for endpoint: ModelEndpoint, device: DeviceWords = .current) -> PlannerStepLabel {
        let transport = (try? ModelTransport.classify(endpoint)) ?? .thisDevice
        let typed = endpoint.model.trimmingCharacters(in: .whitespaces)
        let model = endpoint.kind == .appleOnDevice ? "Apple's on-device model" : (typed.isEmpty ? "a model" : typed)
        return PlannerStepLabel(headline: PlannerSafetyWords.chosenByModel,
                                provider: providerName(LocalPlannerWords.runsOn(transport), device: device), model: model)
    }

    /// Who ran the model, in words a person reads.
    public static func providerName(_ info: PlannerInfo, device: DeviceWords = .current) -> String {
        providerName(info.runsOn, device: device)
    }

    public static func providerName(_ runsOn: RunsOn, device: DeviceWords = .current) -> String {
        switch runsOn {
        case .hosted(let vendor): return vendor
        case .lanComputer: return "Your computer"
        case .robotComputer: return "The duck's computer"
        case .thisPhone: return device.This
        }
    }

    /// The model's name. A hosted planner's is the id the vendor said answered. A local one's is
    /// the model name in its id ("lan.qwen3.5:4b" gives "qwen3.5:4b"), which a person chose.
    public static func modelName(_ info: PlannerInfo) -> String {
        if case .hosted = info.runsOn, HostedVendor.allCases.contains(where: { $0.providerId == info.id }) {
            return info.modelVersion
        }
        if let dot = info.id.firstIndex(of: "."), info.id.index(after: dot) < info.id.endIndex {
            return String(info.id[info.id.index(after: dot)...])
        }
        return info.modelVersion
    }
}

extension Decided {
    /// The AI label for this step, or nil when a fixed rule chose it.
    public var aiLabel: PlannerStepLabel? { PlannerDisclosure.stepLabel(for: self) }
}

// MARK: - 2. the disclosure for local planners

extension LocalPlannerWords {
    /// The local twin of `HostedPlannerWords.aiDisclosure`.
    /// "Decisions come from an AI model (qwen3.5:4b, on a computer you chose), not a person."
    public static func aiDisclosure(_ kind: ModelEndpoint.Kind, model: String,
                                    device: DeviceWords = .current) -> String {
        let name = model.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .appleOnDevice:
            return "Decisions come from an AI model (Apple's on-device model, on \(device.this)), not a person."
        case .downloadedMLX:
            return "Decisions come from an AI model (\(name.isEmpty ? "a downloaded model" : name), on \(device.this)), not a person."
        case .openAICompatible:
            return "Decisions come from an AI model (\(name.isEmpty ? "a model" : name), on a computer you chose), not a person."
        }
    }

    /// No picture goes to a local planner: neither the network nor the on-phone request has a
    /// place for one (`LANPlanner.request`, `PhoneMLXPlanner`), and `PlannerFrameGate` refuses.
    public static let noPicture = "No camera picture is sent to a model on your own computer or on this device."

    /// The local planners' lines, in order, for the settings screen.
    public static func card(_ kind: ModelEndpoint.Kind, model: String, device: DeviceWords = .current) -> [String] {
        [aiDisclosure(kind, model: model, device: device), noPicture, HostedPlannerWords.adultWatches,
         HostedPlannerWords.forChildren, HostedPlannerWords.canBeWrong]
    }

    /// Every disclosure sentence, for the word checks.
    public static func disclosures(device: DeviceWords) -> [String] {
        ModelEndpoint.Kind.allCases.flatMap { card($0, model: "qwen3.5:4b", device: device) }
            + ModelEndpoint.Kind.allCases.map { aiDisclosure($0, model: "", device: device) }
    }
}

// MARK: - 3 and 4. camera consent, face blur, and the one place a planner picture is made

/// How a picture's faces are blurred. The app gives one built on Vision (`DreamFaceBlur`, the
/// same blur Dream-1 pictures get). Where face finding does not exist, as on Linux, it is
/// `.unavailable`, and no picture is sent. `blur` returns nil when finding faces failed.
public struct PlannerFaceBlur<Picture>: Sendable {
    let blur: (@Sendable (Picture) -> Picture?)?

    public init(_ blur: @escaping @Sendable (Picture) -> Picture?) { self.blur = blur }
    private init() { self.blur = nil }

    /// No face finding on this platform. Fails closed.
    public static var unavailable: PlannerFaceBlur<Picture> { PlannerFaceBlur() }
}

/// The one place a planner picture is made and the one rule that says whether it may go.
///
/// ORDER, AND WHY. Consent first, then whether this provider takes pictures at all, then the face
/// blur, then the JPEG. Nothing is encoded before it is blurred, so an unblurred JPEG never
/// exists to be sent by mistake. Any step that fails ends with no picture: never the original.
public enum PlannerFrameGate {
    public enum Outcome: Equatable, Sendable {
        case attached(Data)
        case noConsent
        case providerTakesNoPictures
        case noPicture
        case faceBlurUnavailable
        case faceBlurFailed
        case encodeFailed

        /// The JPEG for `PlannerAsk.frame`, or nil.
        public var jpeg: Data? {
            if case .attached(let data) = self { return data }
            return nil
        }
    }

    /// Whether this provider can be sent a picture at all. Only the two hosted planners put one
    /// in their request. The network and on-phone planners have no place for one.
    public static func takesPictures(_ info: PlannerInfo) -> Bool {
        HostedVendor.allCases.contains { $0.providerId == info.id }
    }

    /// THE rule: consent given for this provider, and a provider that takes pictures. The hosted
    /// planners ask this same function before they put a picture in a request.
    public static func allows(_ info: PlannerInfo, consent: Bool) -> Bool {
        consent && takesPictures(info)
    }

    public static func frame<Picture>(_ picture: Picture?, for info: PlannerInfo, consent: Bool,
                                      blur: PlannerFaceBlur<Picture>,
                                      encode: (Picture) -> Data?) -> Outcome {
        guard consent else { return .noConsent }
        guard allows(info, consent: consent) else { return .providerTakesNoPictures }
        guard let picture else { return .noPicture }
        guard let faceBlur = blur.blur else { return .faceBlurUnavailable }
        guard let blurred = faceBlur(picture) else { return .faceBlurFailed }
        guard let jpeg = encode(blurred), !jpeg.isEmpty else { return .encodeFailed }
        return .attached(jpeg)
    }

    /// The same, reading consent from the stored switch for this provider.
    public static func frame<Picture>(_ picture: Picture?, for info: PlannerInfo, settings: PlannerSafetySettings,
                                      blur: PlannerFaceBlur<Picture>,
                                      encode: (Picture) -> Data?) -> Outcome {
        frame(picture, for: info, consent: settings.cameraConsent(info.id), blur: blur, encode: encode)
    }
}

// MARK: - 5. the adult's agreement

/// A record that an adult agreed to the planner terms on this device. Nothing personal: the day,
/// the app's version and which words were agreed to. Kept so the agreement survives a relaunch,
/// and so new words ask again.
public struct ParentalAgreement: Equatable, Sendable, Codable {
    /// The day, "2026-11-14", in the device's calendar. No time, no place.
    public let agreedOn: String
    /// The app's version, "2.0 (96)".
    public let appVersion: String
    /// `ParentalAgreementWords.textVersion` at the moment of agreeing.
    public let textVersion: Int

    public init(agreedOn: String, appVersion: String, textVersion: Int) {
        self.agreedOn = agreedOn
        self.appVersion = appVersion
        self.textVersion = textVersion
    }

    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(c.year ?? 0)-\(two(c.month ?? 0))-\(two(c.day ?? 0))"
    }

    public enum Status: Equatable, Sendable {
        case none
        /// Agreed to older words. Ask again.
        case outdated(ParentalAgreement)
        case current(ParentalAgreement)

        public var isCurrent: Bool { if case .current = self { return true }; return false }
    }

    public static func status(_ stored: ParentalAgreement?,
                              textVersion: Int = ParentalAgreementWords.textVersion) -> Status {
        guard let stored else { return .none }
        return stored.textVersion == textVersion ? .current(stored) : .outdated(stored)
    }
}

/// The words an adult agrees to. CHANGE `textVersion` WHENEVER `text` CHANGES: that is what asks
/// everyone who agreed before to read the new words and agree again. A test pins the pair.
public enum ParentalAgreementWords {
    public static let textVersion = 1
    public static let text =
        "I am an adult. If a child uses these planners, I am their parent or guardian and I agree to it. "
        + "I hold any key, I decide whether the camera is used, and I watch the duck while a model chooses its steps."

    public static let heading = "An adult's agreement"
    public static let agree = "I agree"
    public static let withdraw = "Withdraw my agreement"
    public static let needed = "An adult must agree before a key is saved or a planner is used."
    public static let askAgain = "The words changed since you agreed. Read them and agree again."
    public static let keptHow = "Only the day, the app version and which words you agreed to are kept, on this device."
    public static func recorded(_ a: ParentalAgreement) -> String {
        "Agreed on \(a.agreedOn), in version \(a.appVersion)."
    }

    /// The privacy page's Children section.
    public static let privacyTitle = "Children and privacy"
    public static let privacyURL = URL(string: "https://microduckstudio.com/privacy/#children")!

    public static var all: [String] {
        [text, heading, agree, withdraw, needed, askAgain, keptHow, privacyTitle,
         recorded(ParentalAgreement(agreedOn: "2026-11-14", appVersion: "2.0 (96)", textVersion: textVersion))]
    }
}

// MARK: - the stored settings

/// Where the agreement and the camera switches are kept. The app gives `UserDefaults`; the tests
/// give a dictionary. None of it is secret, and none of it is personal.
public protocol PlannerSettingsStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// Why a planner step was refused before anything was asked of a model.
public enum PlannerSafetyRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case noAgreement
    case agreementOutdated

    public var says: String {
        switch self {
        case .noAgreement: return ParentalAgreementWords.needed
        case .agreementOutdated: return ParentalAgreementWords.askAgain
        }
    }
    public var description: String { says }
}

/// The agreement and the per-provider camera switches, and the two gates that read them.
public final class PlannerSafetySettings: @unchecked Sendable {
    public static let agreementKey = "planner.parentalAgreement"
    public static func cameraKey(_ providerId: String) -> String { "planner.cameraConsent." + providerId }

    private let storage: PlannerSettingsStorage
    private let lock = NSLock()

    public init(storage: PlannerSettingsStorage) { self.storage = storage }

    // MARK: agreement

    public var agreement: ParentalAgreement? {
        lock.lock(); defer { lock.unlock() }
        return storage.data(forKey: Self.agreementKey).flatMap { try? JSONDecoder().decode(ParentalAgreement.self, from: $0) }
    }

    public func agreementStatus(textVersion: Int = ParentalAgreementWords.textVersion) -> ParentalAgreement.Status {
        ParentalAgreement.status(agreement, textVersion: textVersion)
    }

    @discardableResult
    public func agree(on date: Date, appVersion: String,
                      textVersion: Int = ParentalAgreementWords.textVersion) -> ParentalAgreement {
        let record = ParentalAgreement(agreedOn: ParentalAgreement.day(date), appVersion: appVersion, textVersion: textVersion)
        lock.lock(); defer { lock.unlock() }
        storage.set(try? JSONEncoder().encode(record), forKey: Self.agreementKey)
        return record
    }

    /// Withdrawing also turns every camera switch off: the adult who allowed them took it back.
    public func withdraw() {
        lock.lock(); defer { lock.unlock() }
        storage.set(nil, forKey: Self.agreementKey)
        for v in HostedVendor.allCases { storage.set(nil, forKey: Self.cameraKey(v.providerId)) }
    }

    /// Throws unless the agreement is on record for the current words.
    public func requireAgreement(textVersion: Int = ParentalAgreementWords.textVersion) throws {
        switch agreementStatus(textVersion: textVersion) {
        case .current: return
        case .none: throw PlannerSafetyRefusal.noAgreement
        case .outdated: throw PlannerSafetyRefusal.agreementOutdated
        }
    }

    // MARK: camera

    /// Off unless an adult turned it on for exactly this provider.
    public func cameraConsent(_ providerId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storage.data(forKey: Self.cameraKey(providerId)) == Data([1])
    }

    /// Turning a switch on needs the agreement. Off always works.
    public func setCameraConsent(_ on: Bool, for providerId: String) throws {
        if on { try requireAgreement() }
        lock.lock(); defer { lock.unlock() }
        storage.set(on ? Data([1]) : nil, forKey: Self.cameraKey(providerId))
    }

    // MARK: the gates

    /// The one way a hosted key is saved. Without a current agreement nothing is written, and
    /// `write` is never called. The paste is checked for shape (`HostedVendor.cleaned`) after the
    /// agreement, so a refused save says the agreement first.
    public func saveKey(_ typed: String, for vendor: HostedVendor,
                        write: (String) -> Void) -> Result<String, KeySaveRefusal> {
        do { try requireAgreement() } catch let r as PlannerSafetyRefusal { return .failure(.agreement(r)) } catch {
            return .failure(.agreement(.noAgreement))
        }
        switch vendor.cleaned(typed) {
        case .failure(let p): return .failure(.key(p))
        case .success(let key):
            write(key)
            return .success(key)
        }
    }

    public enum KeySaveRefusal: Error, Equatable, Sendable {
        case agreement(PlannerSafetyRefusal)
        case key(HostedKeyProblem)

        public var says: String {
            switch self {
            case .agreement(let r): return r.says
            case .key(let p): return p.says
            }
        }
    }

    /// Whether this planner may be asked for a step. A fixed rule (DuckTalk) always may; any model
    /// needs the agreement.
    public func mayUse(_ info: PlannerInfo) -> Bool {
        !PlannerDisclosure.isModel(info) || agreementStatus().isCurrent
    }
}

/// A planner that refuses before it asks, unless the adult's agreement is current. The run builds
/// every model planner through this, so the check sits in one place.
public struct AgreedPlanner: Planner {
    public let inner: any Planner
    let settings: PlannerSafetySettings

    public init(_ inner: any Planner, settings: PlannerSafetySettings) {
        self.inner = inner
        self.settings = settings
    }

    public var info: PlannerInfo { inner.info }

    public func decide(_ ask: PlannerAsk) async throws -> Decided {
        if PlannerDisclosure.isModel(inner.info) { try settings.requireAgreement() }
        return try await inner.decide(ask)
    }
}

/// An in-memory store, for previews and tests.
public final class MemoryPlannerSettingsStorage: PlannerSettingsStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func data(forKey key: String) -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    public func set(_ data: Data?, forKey key: String) { lock.lock(); defer { lock.unlock() }; values[key] = data }
}

// MARK: - the words

/// The shared sentences for the label and the camera switch. Plain text, never "safe".
public enum PlannerSafetyWords {
    public static let chosenByModel = "Chosen by an AI model, not a person"
    /// The heading over the local planners' lines on Models.
    public static let localHeading = "When a model picks the steps"
    /// Above the example label on the settings screens.
    public static let labelExplained = "During a run, every step a model chooses carries this mark:"

    public static func cameraSwitch(_ v: HostedVendor) -> String { "Send camera pictures to \(v.name)" }

    /// Exactly what the switch sends, to whom, and under whose rules.
    public static func cameraDetail(_ v: HostedVendor) -> String {
        "Off unless you turn it on. When on, each decision sends \(v.name) one picture from the duck's camera, "
            + "with faces blurred on this device first. If faces cannot be blurred, no picture is sent. "
            + "\(v.name) keeps it under its own terms: "
            + (v.terms.imageRetention ?? "how long is not known.")
    }

    public static var all: [String] {
        [chosenByModel, localHeading, labelExplained]
            + HostedVendor.allCases.flatMap { [cameraSwitch($0), cameraDetail($0)] }
    }
}
