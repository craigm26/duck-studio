import SwiftUI
import ImageIO
import StudioKit

/// The duck's head camera, read a few times a second from the robot's own `/frame`.
///
/// See `DuckCamera` for why stills and not WebRTC. Works the same against a robot on the floor
/// and a duck in Pollen's simulator: only the address differs. Decoded with ImageIO so the same
/// file draws on iOS and macOS.
@MainActor
final class DuckCameraFeed: ObservableObject {
    @Published private(set) var picture: CGImage?
    @Published private(set) var problem: String?
    @Published private(set) var fps: Double = 0
    @Published private(set) var running = false

    private var task: Task<Void, Never>?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = DuckCamera.timeout
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func start(_ address: DuckCamera.Address) {
        stop()
        guard let url = address.frameURL else { problem = DuckCamera.Words.notAnAddress; return }
        running = true
        problem = nil
        task = Task { [weak self] in
            var stamps: [Date] = []
            while !Task.isCancelled {
                let began = Date()
                let next: (CGImage?, String?)
                guard let session = self?.session else { return }
                do {
                    let (data, response) = try await session.data(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    switch DuckCamera.read(status: status, body: data) {
                    case .picture(let png):
                        next = (Self.decode(png), nil)
                    case .notCapturing(let said):
                        next = (nil, said)
                    case .notACamera(let code):
                        next = (nil, DuckCamera.Words.notACamera(code))
                    }
                } catch {
                    if Task.isCancelled { return }
                    next = (nil, DuckCamera.Words.unreachable(address.said))
                }
                guard let self else { return }
                if let image = next.0 {
                    self.picture = image
                    self.problem = nil
                    stamps.append(Date())
                    stamps = stamps.filter { Date().timeIntervalSince($0) < 3 }
                    self.fps = Double(stamps.count) / 3
                } else {
                    self.problem = next.1
                    self.fps = 0
                }
                let spent = Date().timeIntervalSince(began)
                // A camera that is not there is asked again every two seconds, not four times one.
                let wait = next.0 == nil ? 2.0 : max(DuckCamera.interval - spent, 0.02)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        running = false
        fps = 0
    }

    nonisolated static func decode(_ png: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// A camera card: the address, the picture, and the robot's own live-video page one tap away.
struct DuckCameraCard: View {
    /// Typed or remembered address; seeded from the bridge's host when there is one.
    @Binding var address: String
    @StateObject private var feed = DuckCameraFeed()

    private var parsed: DuckCamera.Address? { DuckCamera.Address(address) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            if let picture = feed.picture, feed.running {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text(DuckCamera.Words.rate(feed.fps))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                            .padding(6)
                    }
                    .accessibilityLabel(Text("The duck's camera"))
            }
            TextField(DuckCamera.Words.addressPlaceholder, text: $address)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
#endif
                .autocorrectionDisabled()
                .frame(minHeight: DesignMetric.minimumTarget)
                .onSubmit { if feed.running, let parsed { feed.start(parsed) } }
            HStack {
                Button(feed.running ? DuckCamera.Words.stop : DuckCamera.Words.start) {
                    if feed.running { feed.stop() } else if let parsed { feed.start(parsed) }
                }
                .buttonStyle(.primaryAction)
                .disabled(!feed.running && parsed == nil)
                Spacer()
                if let console = parsed?.consoleURL {
                    Link(destination: console) {
                        Label(DuckCamera.Words.liveVideo, systemImage: "safari")
                            .font(.footnote)
                    }
                    .tint(Theme.actionSecondary)
                }
            }
            if !address.isEmpty, parsed == nil {
                Text(DuckCamera.Words.notAnAddress)
                    .font(.caption).foregroundStyle(Theme.warning)
            } else if let problem = feed.problem {
                Text(problem)
                    .font(.caption).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { feed.stop() }
    }
}
