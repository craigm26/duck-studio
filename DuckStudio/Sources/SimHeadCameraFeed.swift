import SwiftUI
import CoreGraphics
import ImageIO
import StudioKit

/// The simulated duck's head camera, as a feed: five pictures a second of what the bench's duck sees.
///
/// iOS 18 AND macOS 15 OR LATER, because RealityKit's off-screen renderer is; on an older system
/// `unavailable` says so and nothing else changes. See `SimHeadCameraRenderer` for what is drawn.
@MainActor
final class SimHeadCameraFeed: ObservableObject, DreamFrameSource {
    @Published private(set) var picture: CGImage?
    @Published private(set) var running = false
    let unavailable: String?

    var keepsDreamFrames = false { didSet { if !keepsDreamFrames { window = [] } } }
    private var window: [String] = []
    private var task: Task<Void, Never>?
    private var renderer: AnyObject?

    var latestPicture: CGImage? { picture }
    func dreamWindow() -> [String] { window }

    init() {
        if #available(iOS 18.0, macOS 15.0, *) {
            unavailable = nil
        } else {
            unavailable = DuckDream.Words.simCameraNeedsNewerSystem
        }
    }

    func start(_ peer: BenchPeer) {
        guard task == nil, unavailable == nil else { return }
        running = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let live = await peer.live { await self.draw(live) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        running = false
    }

    private func draw(_ live: DuckDrive.Live) async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        if renderer == nil { renderer = SimHeadCameraRenderer() }
        guard let renderer = renderer as? SimHeadCameraRenderer, let image = await renderer.render(live) else { return }
        picture = image
        if keepsDreamFrames, let jpeg = DuckCameraFeed.dreamJPEG(image) {
            window = Array((window + [jpeg]).suffix(DreamPilot.window))
        }
    }
}

/// Dream-1 on the duck in this device's physics: its camera, running, and recording.
struct DreamSimSheet: View {
    let peer: BenchPeer?
    @ObservedObject var feed: SimHeadCameraFeed
    @ObservedObject var model: DreamRunModel
    @ObservedObject var recorder: DreamRecorder
    var stopDriving: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing(.standard)) {
                    if let note = feed.unavailable {
                        Text(note).font(.footnote).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let picture = feed.picture {
                        Image(decorative: picture, scale: 1)
                            .resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel(Text(DuckDream.Words.simCameraLabel))
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    Text(DuckDream.Words.simCameraNote).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DreamPanel(peer: peer, source: feed, stopDriving: stopDriving, model: model,
                               recorder: recorder, hasPicture: feed.picture != nil)
                }
                .padding()
            }
            .navigationTitle(DuckDream.Words.simSheetTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { if let peer { feed.start(peer) } }
        .onChange(of: recorder.recording) { _, now in if now { dismiss() } }
        .onChange(of: model.running) { _, now in if now { dismiss() } }
    }
}

/// While Dream-1 drives or a run records on the simulated duck: one line over the picture, and Stop.
struct DreamSimStatus: View {
    @ObservedObject var model: DreamRunModel
    @ObservedObject var recorder: DreamRecorder

    var body: some View {
        if recorder.recording || model.running {
            HStack(spacing: Theme.spacing(.tight)) {
                Image(systemName: recorder.recording ? "record.circle.fill" : "sparkles")
                    .foregroundStyle(recorder.recording ? Theme.critical : Theme.actionSecondary)
                Text(recorder.recording ? DreamDataset.Words.recording(recorder.seconds)
                                        : (model.line ?? DuckDream.Words.heading))
                    .font(.footnote.monospacedDigit()).lineLimit(1)
                Button(recorder.recording ? DreamDataset.Words.stop : DuckDream.Words.stop) {
                    if recorder.recording { recorder.stop() } else { model.stop() }
                }
                .buttonStyle(.borderedProminent)
                .font(.footnote)
            }
            .padding(.horizontal, Theme.spacing(.snug)).padding(.vertical, Theme.spacing(.tight))
            .background(.thinMaterial, in: Capsule())
            .frame(maxHeight: 60)
        }
    }
}
