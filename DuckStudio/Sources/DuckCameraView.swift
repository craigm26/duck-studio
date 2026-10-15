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
    /// Read Duck Cards in each picture. Off by default: the finder costs a pass over every frame.
    @Published var readCards = false {
        didSet { if !readCards { cards = nil; reading = nil; watcher = DuckCards.Watcher() } }
    }
    /// What the camera sees, in `DuckCards.Words`.
    @Published private(set) var cards: String?
    /// The reading behind `cards`, so a row on the table can be held still and used.
    @Published private(set) var reading: DuckCards.Reading?
    /// The last card or row held still long enough to act on (`DuckCards.Watcher`).
    @Published private(set) var cardEvent: DuckCards.Watcher.Event?

    private var task: Task<Void, Never>?
    private var finder: DuckCards.Finder?
    private var watcher = DuckCards.Watcher()
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
                    if self.readCards { self.read(image) }
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

    /// The cards in one picture. StudioKit reads; this only hands it the picture and keeps the
    /// answer (`DuckCards`: the same rules as the duck's own reader, held to one set of vectors).
    ///
    /// WITH THE CLASS'S DECK, NOT THE STARTER: a Your card means what the class saved for it, in
    /// the deck file `DuckCardsStore` keeps.
    private func read(_ image: CGImage) {
        guard let deck = DuckCardsStore.shared.deck, let grey = DuckCards.grey(image) else { return }
        let finder = self.finder ?? DuckCards.Finder()
        self.finder = finder
        let found = finder.find(grey: grey.bytes, width: grey.width, height: grey.height)
        let reading = DuckCards.reading(found, deck: deck)
        self.reading = reading
        cards = DuckCards.Words.sees(reading)
        if let event = watcher.feed(reading.program, at: Date().timeIntervalSinceReferenceDate) {
            cardEvent = event
        }
    }

    nonisolated static func decode(_ png: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// A camera card: the address, the picture, and the robot's own live-video page one tap away.
///
/// AND THE CARDS IN THE PICTURE, WHEN IT IS READING THEM. A row or a card the camera reads can be
/// held still and opened in the plan editor, a row can be saved as a Your card, and the class deck
/// the cards are read with is one tap away (`DuckCardsSheet`).
struct DuckCameraCard: View {
    /// Typed or remembered address; seeded from the bridge's host when there is one.
    @Binding var address: String
    /// The link to a real duck, handed to the plan editor so a row read here can run on it.
    var robot: BridgeLink? = nil
    /// The models chosen in Settings, handed to the plan editor.
    var models: EndpointStore? = nil
    /// Hands the duck over from the sticks before a plan drives it.
    var stopDriving: (() async -> Void)? = nil
    @StateObject private var feed = DuckCameraFeed()
    /// What the card has opened: cards held still, or the class deck.
    @State private var opened: DuckCardsOpening?

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
                    .accessibilityLabel(Text(DuckCamera.Words.pictureLabel))
            }
            if feed.running {
                Toggle(DuckCards.Words.toggle, isOn: $feed.readCards)
                    .font(.footnote)
                    .tint(Theme.actionSecondary)
                if feed.readCards, let line = feed.cards {
                    Text(line)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if feed.readCards { cardButtons }
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
            // THE CLASS DECK DOES NOT NEED A CAMERA. Sharing it or forgetting a card is something a
            // teacher does at a desk, so the door is here whether or not a duck is in view.
            Button {
                opened = DuckCardsOpening(kind: .deck, held: nil)
            } label: {
                Label(DuckCards.Words.classDeck, systemImage: "rectangle.stack")
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .tint(Theme.actionSecondary)
            .frame(minHeight: DesignMetric.minimumTarget)
        }
        .onDisappear { feed.stop() }
        .sheet(item: $opened) { opening in
            DuckCardsSheet(opening: opening, robot: robot, models: models, stopDriving: stopDriving)
        }
    }

    /// What can be done with what the camera reads: hold it still for the plan editor, or to save
    /// a row as a Your card. Offered only for a reading the kit says can be used
    /// (`DuckCards.usable`, `DuckCards.savable`); a row with no End is not finished yet.
    @ViewBuilder private var cardButtons: some View {
        if let reading = feed.reading, DuckCards.usable(reading) {
            Button {
                opened = DuckCardsOpening(kind: .plan, held: reading)
            } label: {
                Label(DuckCards.Words.openInPlanEditor, systemImage: PlanEditorWords.studioRowSymbol)
            }
            .buttonStyle(.primaryAction)
        }
        if let reading = feed.reading, DuckCards.savable(reading) {
            Button {
                opened = DuckCardsOpening(kind: .save, held: reading)
            } label: {
                Label(DuckCards.Words.saveAsCard, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .tint(Theme.actionSecondary)
            .frame(minHeight: DesignMetric.minimumTarget)
        }
    }
}
