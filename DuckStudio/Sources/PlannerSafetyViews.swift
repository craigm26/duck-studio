import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import StudioKit

// The app's side of `PlannerSafety` (StudioKit): where the adult's agreement and the camera
// switches are kept, the label a run puts beside a step a model chose, the agreement and camera
// rows on the settings screens, and the picture a planner may be sent. Every sentence is a kit
// string, so the tests read the same words the screens show.

// MARK: - storage

/// The agreement and the camera switches, in `UserDefaults`. None of it is a secret and none of it
/// is personal: a day, a version, a number, and one flag per provider.
final class UserDefaultsPlannerStorage: PlannerSettingsStorage {
    func data(forKey key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) {
        if let data { UserDefaults.standard.set(data, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

/// One settings object for the whole app, observed by the screens that change it.
@MainActor
final class PlannerSafetyStore: ObservableObject {
    static let shared = PlannerSafetyStore()

    let settings = PlannerSafetySettings(storage: UserDefaultsPlannerStorage())
    @Published private(set) var status: ParentalAgreement.Status = .none
    @Published private(set) var camera: [String: Bool] = [:]

    private init() { refresh() }

    /// "2.0 (96)": the marketing version and the build, as the record keeps them.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    func agree() {
        settings.agree(on: Date(), appVersion: Self.appVersion)
        refresh()
    }

    func withdraw() {
        settings.withdraw()
        refresh()
    }

    func cameraConsent(_ v: HostedVendor) -> Bool { camera[v.providerId] ?? false }

    func setCameraConsent(_ on: Bool, for v: HostedVendor) {
        try? settings.setCameraConsent(on, for: v.providerId)
        refresh()
    }

    private func refresh() {
        status = settings.agreementStatus()
        camera = Dictionary(uniqueKeysWithValues: HostedVendor.allCases.map {
            ($0.providerId, settings.cameraConsent($0.providerId))
        })
    }
}

// MARK: - 1. the label on a step

/// The mark beside a step a model chose: "Chosen by an AI model, not a person", then the provider
/// and model. A run shows it on every such step (`Decided.aiLabel`); a step DuckTalk read has none,
/// so this view is never built for it.
struct PlannerStepLabelView: View {
    let label: PlannerStepLabel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
            Image(systemName: "cpu")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(label.headline).font(.caption.weight(.semibold))
                Text(label.provider + ", " + label.model)
                    .font(.caption)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(Theme.spacing(.tight))
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.outline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label.line))
    }
}

/// The settings screens' example of that mark, so the adult sees what a run will show before any
/// planner is offered.
struct PlannerStepLabelExample: View {
    let label: PlannerStepLabel?

    var body: some View {
        if let label {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                Text(PlannerSafetyWords.labelExplained)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PlannerStepLabelView(label: label)
            }
        }
    }
}

// MARK: - 5. the adult's agreement

/// The agreement, its record, and the privacy page's Children section. On the hosted key screen
/// and on Models, so the same adult sees it whichever kind of planner they set up.
struct ParentalAgreementSection: View {
    @ObservedObject var store: PlannerSafetyStore

    var body: some View {
        Section {
            Text(ParentalAgreementWords.text)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            switch store.status {
            case .current(let record):
                Label(ParentalAgreementWords.recorded(record), systemImage: "checkmark.seal")
                    .font(.footnote).foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) { store.withdraw() } label: {
                    Text(ParentalAgreementWords.withdraw).foregroundStyle(Theme.critical)
                }
            case .outdated:
                Label(ParentalAgreementWords.askAgain, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                agreeButton
            case .none:
                Text(ParentalAgreementWords.needed)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                agreeButton
            }
            Link(destination: ParentalAgreementWords.privacyURL) {
                Label(ParentalAgreementWords.privacyTitle, systemImage: "hand.raised")
            }
        } header: {
            SectionHeading(text: ParentalAgreementWords.heading)
        } footer: {
            Text(ParentalAgreementWords.keptHow)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var agreeButton: some View {
        Button { store.agree() } label: {
            Label(ParentalAgreementWords.agree, systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primaryAction)
    }
}

// MARK: - 3. the camera switch

/// One provider's camera switch. Off by default; it can be turned on only after the agreement,
/// and the words under it say exactly what goes, to whom, and under whose rules.
struct PlannerCameraSwitch: View {
    let vendor: HostedVendor
    @ObservedObject var store: PlannerSafetyStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Toggle(isOn: Binding(get: { store.cameraConsent(vendor) },
                                 set: { store.setCameraConsent($0, for: vendor) })) {
                Text(PlannerSafetyWords.cameraSwitch(vendor))
            }
            .disabled(!store.status.isCurrent)
            Text(PlannerSafetyWords.cameraDetail(vendor))
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 4. the picture a planner may be sent

/// The camera picture for one planner decision, made only through `PlannerFrameGate`: the
/// provider's switch, then the same face blur Dream-1 pictures get (`DreamFaceBlur`), then the
/// JPEG. When Vision cannot look for faces, `DreamFaceBlur.scrubbed` gives nil and no picture goes.
enum PlannerFrames {
    static let faceBlur = PlannerFaceBlur<CGImage> { DreamFaceBlur.scrubbed($0) }

    /// The `PlannerAsk.frame` for this provider and this camera picture, or why there is none.
    static func frame(_ image: CGImage?, for info: PlannerInfo, settings: PlannerSafetySettings) -> PlannerFrameGate.Outcome {
        PlannerFrameGate.frame(image, for: info, settings: settings, blur: faceBlur, encode: jpeg)
    }

    /// One already-blurred picture, 320 by 176 like Dream-1's, as JPEG bytes.
    static func jpeg(_ image: CGImage) -> Data? {
        let width = 320, height = 176
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, small, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
