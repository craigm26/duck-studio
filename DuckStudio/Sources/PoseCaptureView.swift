import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import WebKit
import UniformTypeIdentifiers
import DuckKit
import StudioKit

/// Studio > Mimic a person: a camera, a video or a YouTube clip on top, the
/// duck standing the way the person stands underneath, and a record button
/// that turns what it saw into a motion.
///
/// THREE SOURCES, ONE DUCK. Which source is up top changes how the frames
/// arrive and nothing else — `PoseCaptureEngine` reads them all the same way
/// and the kit decides the pose — so the stage, the readout and the record
/// bar are drawn once and the source area is the only thing that switches.
///
/// EVERY SENTENCE HERE IS THE KIT'S. `Mimic`, `MimicSource` and `MimicTrack`
/// hold the words and `swift test` reads them; this file arranges them. That
/// is the house rule for a stage, and this screen is a stage with a camera
/// over it, which is where overclaiming is easiest: a duck that copies you
/// looks controlled and is drawn. `whatIsReal` is on screen for that reason.
///
/// THE DUCK DOES NOT LIVE INSIDE THE PICTURE VISION READS. For the YouTube
/// source the engine reads this phone's own screen, cropped to the player's
/// rectangle — measured with a `GeometryReader` in the global space — so a
/// rendered duck two hundred points below the player is never mistaken for a
/// second person.
struct PoseCaptureView: View {
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    @StateObject private var engine = PoseCaptureEngine()
    @State private var source: MimicSource = .camera
    @State private var door = CameraDoor.availability
    @State private var cameraPosition: AVCaptureDevice.Position = .front
    @State private var orbit = OrbitState()
    /// The last pose the duck was drawn in, so it stays put when the person
    /// steps out of shot rather than snapping home.
    @State private var lastShown: [Double] = StagePose.home.jointAngles

    // video
    @State private var pickedItem: PhotosPickerItem?
    @State private var player: AVPlayer?
    @State private var videoNote: String?
    @State private var pickingFile = false

    // youtube
    @State private var linkText = ""
    @State private var videoID: String?
    @State private var linkNote: String?
    @State private var playerRegion: CGRect = .zero

    // what was kept
    @State private var keptNote: String?
    @State private var kept: DraftID?
    @State private var editing: DraftID?

    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var linkFocused: Bool

    /// The pose on the stage: the person's, or the last one they left.
    private var shown: [Double] { engine.duckPose ?? lastShown }

    var body: some View {
        VStack(spacing: 0) {
            sourcePicker
            sourceArea
                .frame(height: CaptureMetric.sourceHeight)
                .clipped()
            stage
            bottom
        }
        .background(Theme.backgroundPrimary)
        // THE KEYBOARD DOES NOT MOVE THE PICTURE. Left to itself SwiftUI
        // shrinks this stack to fit above the keyboard, which on the first
        // phone test pushed the source picker up under the title bar. The
        // link field is at the top and is never under the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationTitle(Mimic.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshingCameraDoor($door)
        .onAppear { enter(source) }
        .onChange(of: source) { _, now in enter(now) }
        .onChange(of: engine.duckPose) { _, pose in if let pose { lastShown = pose } }
        .onChange(of: playerRegion) { _, region in
            if source == .youtube, videoID != nil { engine.useScreen(region: region) }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onDisappear {
            engine.stopSource()
            player?.pause()
            if let endOfVideo { NotificationCenter.default.removeObserver(endOfVideo) }
            endOfVideo = nil
        }
        .fileImporter(isPresented: $pickingFile,
                      allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) { result in
            switch result {
            case .success(let url): Task { await open(url, scoped: true) }
            case .failure(let error):
                videoNote = Mimic.videoCouldNotBeOpened(error.localizedDescription)
            }
        }
        .sheet(item: $editing) { wrapper in
            NavigationStack {
                if let current = drafts.drafts.first(where: { $0.id == wrapper.id }) {
                    IntentAuthorView(draft: current, scenes: scenes, models: models,
                                     isNew: false,
                                     onSave: { drafts.save($0) },
                                     onDiscard: { doomed in
                                         editing = nil
                                         kept = nil
                                         keptNote = nil
                                         drafts.delete(doomed)
                                     })
                        .onDisappear { drafts.flush() }
                } else {
                    // THE ELSE BRANCH EXISTS SO THE SHEET IS NEVER AN EMPTY
                    // NavigationStack — the toolbar-less blank card this app
                    // has been bitten by before.
                    ContentUnavailableView(Mimic.motionNotHere, systemImage: "questionmark.square.dashed",
                                           description: Text(Mimic.motionNotHereSaid))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(Mimic.done) { editing = nil }
                            }
                        }
                }
            }
        }
    }

    // MARK: - which source

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Picker(Mimic.title, selection: $source) {
                ForEach(MimicSource.allCases) { one in
                    Text(one.label).tag(one)
                }
            }
            .pickerStyle(.segmented)
            Text(source.how)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.vertical, Theme.spacing(.tight))
    }

    @ViewBuilder private var sourceArea: some View {
        switch source {
        case .camera:
            if let refusal = door.refusal(for: .mimic) {
                ContentUnavailableView(CameraAvailability.Dependent.mimic.title,
                                       systemImage: "video.slash",
                                       description: Text(refusal))
            } else {
                ZStack(alignment: .topTrailing) {
                    CameraPreview(session: engine.cameraSession)
                    Button {
                        cameraPosition = cameraPosition == .front ? .back : .front
                        engine.useCamera(position: cameraPosition)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3)
                            .padding(Theme.spacing(.tight))
                            .background(Theme.surfacePrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(Theme.spacing(.snug))
                    .accessibilityLabel(Text(Mimic.flipCamera))
                }
            }
        case .video:
            if let player {
                VideoSurface(player: player)
            } else {
                VStack(spacing: Theme.spacing(.snug)) {
                    PhotosPicker(selection: $pickedItem, matching: .videos) {
                        Label(Mimic.pickVideo, systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.primaryAction)
                    Button(Mimic.fromFiles) { pickingFile = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.actionSecondary)
                        .frame(minHeight: DesignMetric.minimumTarget)
                    if let videoNote {
                        Text(videoNote)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.spacing(.standard))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.backgroundSecondary)
            }
        case .youtube:
            VStack(spacing: Theme.spacing(.tight)) {
                HStack(spacing: Theme.spacing(.tight)) {
                    TextField(Mimic.linkField, text: $linkText)
                        .focused($linkFocused)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { loadLink() }
                    Button(Mimic.load) { loadLink() }
                        .buttonStyle(.primaryAction)
                }
                .padding(.horizontal, Theme.spacing(.snug))
                if let videoID {
                    YouTubePlayer(videoID: videoID)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: PlayerRegionKey.self,
                                                   value: proxy.frame(in: .global))
                        })
                        .onPreferenceChange(PlayerRegionKey.self) { playerRegion = $0 }
                } else {
                    Text(linkNote ?? source.how)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Theme.spacing(.standard))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, Theme.spacing(.tight))
            .background(Theme.backgroundSecondary)
        }
    }

    // MARK: - the duck

    private var stage: some View {
        DuckStage(pose: StagePose(jointAngles: shown, root: restingRoot(for: shown)),
                  environment: .bareFloor,
                  orbit: $orbit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: CaptureMetric.stageMinHeight)
    }

    /// The trunk let down onto the floor for the pose, as the editor does it.
    private func restingRoot(for angles: [Double]) -> DuckIntentClip.Root {
        let pinned = StagePose.home.root
        guard let probe = StageLegend.clearance else { return pinned }
        return StageFloor.resting(pinned,
                                  clearanceMetres: probe.clearance(jointAngles: angles, root: pinned))
    }

    // MARK: - readout and the record bar

    private var bottom: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                statusLine
                if let reading = engine.reading {
                    Text(PoseRetarget.readingLine(reading))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let held = PoseRetarget.clampedLine(engine.clamped) {
                    Text(held)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = engine.sourceNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                recordRow
                Toggle(isOn: $engine.mirrored) {
                    Text(Mimic.mirror)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .tint(Theme.actionSecondary)
                Text(Mimic.mirrorSaid)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Mimic.howItMaps)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(source.whatIsReal)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Mimic.nothingLeavesThePhone)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.spacing(.snug))
        }
        .frame(maxHeight: CaptureMetric.bottomMaxHeight)
        .background(Theme.surfacePrimary)
    }

    /// One line about what the engine is seeing or what was just kept.
    private var statusLine: some View {
        HStack(spacing: Theme.spacing(.tight)) {
            Circle()
                .fill(engine.personInView ? Theme.robotActive : Theme.robotOffline)
                .frame(width: Theme.spacing(.tight), height: Theme.spacing(.tight))
                .accessibilityHidden(true)
            Text(status)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Whether a source is running at all — the camera, a loaded video, or a
    /// loaded clip. Without one, "no frames" would be a complaint about a
    /// source nobody has started.
    private var sourceIsUp: Bool {
        switch source {
        case .camera: return door.canOffer(.mimic)
        case .video: return player != nil
        case .youtube: return videoID != nil
        }
    }

    private var status: String {
        if let keptNote { return keptNote }
        if engine.isRecording {
            return MimicTrack.recordingSaid(seconds: engine.track.seconds, keys: engine.track.keyCount)
        }
        if engine.stoppedAtCap { return MimicTrack.stoppedAtTheCap }
        if engine.personInView { return Mimic.tracking(posesPerSecond: engine.posesPerSecond) }
        if sourceIsUp, engine.framesPerSecond == 0 { return Mimic.noFramesYet(source) }
        if engine.personSeen { return Mimic.personSeenNotRead }
        return source == .camera ? Mimic.noPersonYet : Mimic.noPersonInTheClip
    }

    private var recordRow: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack(spacing: Theme.spacing(.tight)) {
                if engine.isRecording {
                    Button(Mimic.stop) { engine.stopRecording() }
                        .buttonStyle(.primaryAction)
                } else {
                    Button(engine.track.isEmpty ? Mimic.record : Mimic.recordAgain) {
                        keptNote = nil
                        kept = nil
                        engine.startRecording()
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(engine.duckPose == nil)
                }
                if !engine.isRecording, !engine.track.isEmpty, kept == nil {
                    Button(Mimic.keep) { keep() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.actionSecondary)
                        .frame(minHeight: DesignMetric.minimumTarget)
                }
                if let kept {
                    Button(Mimic.openInEditor) { editing = kept }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.actionSecondary)
                        .frame(minHeight: DesignMetric.minimumTarget)
                }
            }
            Text(Mimic.recordSaid)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - doing things

    private func enter(_ source: MimicSource) {
        keptNote = nil
        switch source {
        case .camera:
            player?.pause()
            guard door.canOffer(.mimic) else { engine.stopSource(); return }
            engine.useCamera(position: cameraPosition)
        case .video:
            if let player {
                attach(player)
                player.play()
            } else {
                engine.stopSource()
            }
        case .youtube:
            player?.pause()
            if videoID != nil, playerRegion.width > 0 {
                engine.useScreen(region: playerRegion)
            } else {
                engine.stopSource()
            }
        }
    }

    private func loadLink() {
        linkFocused = false
        guard let id = YouTubeLink.videoID(in: linkText) else {
            linkNote = YouTubeLink.refusal
            videoID = nil
            engine.stopSource()
            return
        }
        linkNote = nil
        videoID = id
        keptNote = nil
        if playerRegion.width > 0 { engine.useScreen(region: playerRegion) }
    }

    private func keep() {
        let name = MimicTrack.name(source, ordinal: drafts.drafts.count + 1)
        guard let draft = engine.track.draft(named: name,
                                             provenance: MimicTrack.provenance(source)) else { return }
        drafts.save(draft)
        kept = DraftID(id: draft.id)
        keptNote = Mimic.kept(name)
        Haptic.behaviourStarted()
    }

    /// A picked library video, copied out of the picker's sandbox.
    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: MovieFile.self) else { return }
            await open(movie.url, scoped: false)
        } catch {
            videoNote = Mimic.videoCouldNotBeOpened(error.localizedDescription)
        }
    }

    /// Open a video file: a player, a frame output on its item, and the
    /// engine reading that output while it plays.
    private func open(_ url: URL, scoped: Bool) async {
        var local = url
        if scoped {
            guard url.startAccessingSecurityScopedResource() else {
                videoNote = Mimic.videoCouldNotBeOpened("It is not readable from here.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
            do {
                try FileManager.default.copyItem(at: url, to: copy)
                local = copy
            } catch {
                videoNote = Mimic.videoCouldNotBeOpened(error.localizedDescription)
                return
            }
        }
        let asset = AVURLAsset(url: local)
        let orientation: CGImagePropertyOrientation
        do {
            let track = try await asset.loadTracks(withMediaType: .video).first
            let transform = try await track?.load(.preferredTransform) ?? .identity
            orientation = Self.orientation(of: transform)
        } catch {
            videoNote = Mimic.videoCouldNotBeOpened(error.localizedDescription)
            return
        }
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        if let endOfVideo { NotificationCenter.default.removeObserver(endOfVideo) }
        endOfVideo = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        self.player?.pause()
        self.player = player
        self.videoNote = nil
        self.videoOutput = output
        self.videoOrientation = orientation
        attach(player)
        player.play()
    }

    @State private var videoOutput: AVPlayerItemVideoOutput?
    @State private var videoOrientation: CGImagePropertyOrientation = .up
    @State private var endOfVideo: NSObjectProtocol?

    private func attach(_ player: AVPlayer) {
        guard let videoOutput else { return }
        engine.useVideo(output: videoOutput, player: player, orientation: videoOrientation)
    }

    /// A track's preferred transform as the orientation Vision should read
    /// its raw frames in. Phones record portrait video as landscape frames
    /// with a quarter-turn transform, and a person read sideways is nobody.
    static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
        if t.a == 0, t.b == 1, t.c == -1, t.d == 0 { return .right }
        if t.a == 0, t.b == -1, t.c == 1, t.d == 0 { return .left }
        if t.a == -1, t.b == 0, t.c == 0, t.d == -1 { return .down }
        return .up
    }
}

/// Where the YouTube player is on screen, reported upward.
private struct PlayerRegionKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// A video from the library, copied to a file this process can open.
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov"
                                                                            : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieFile(url: copy)
        }
    }
}

/// The numbers this screen writes down for itself.
private enum CaptureMetric {
    /// The source area — a camera preview or a player — is a fixed band so the
    /// duck under it gets the rest, whatever the source. TALL ENOUGH FOR A
    /// PORTRAIT CLIP: a vertical video sits inside YouTube's player at the
    /// player's height, and at 250 points the person in it was a sixth of the
    /// screen and unreadable. The stage keeps its minimum; the readout under
    /// it is what gives.
    static let sourceHeight: CGFloat = 330
    static let stageMinHeight: CGFloat = 200
    static let bottomMaxHeight: CGFloat = 260
}

// MARK: - the three surfaces

/// The camera preview, drawn from the session the engine is reading.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
    }
}

/// An `AVPlayer` with its controls, so the person can scrub to the part they
/// want.
struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

/// YouTube's own inline player, in a web view.
///
/// INLINE, OR THE FRAMES ARE NOT ON THIS SCREEN. Without
/// `allowsInlineMediaPlayback` iOS plays a web video in its own full-screen
/// player, over the app, and the region this screen measures is a rectangle
/// of nothing.
struct YouTubePlayer: UIViewRepresentable {
    let videoID: String

    final class Coordinator { var loaded: String? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        load(videoID, into: view, context.coordinator)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.loaded != videoID { load(videoID, into: view, context.coordinator) }
    }

    /// THE EMBED IS INSIDE A PAGE WITH AN ORIGIN, NOT LOADED BARE. Loaded bare
    /// the iframe request carries no referrer and YouTube answers error 153,
    /// "Video player configuration error" — seen on the first phone test.
    /// `YouTubeLink.referrer` is the base URL, so the request says who is
    /// embedding.
    private func load(_ id: String, into view: WKWebView, _ coordinator: Coordinator) {
        coordinator.loaded = id
        view.loadHTMLString(YouTubeLink.embedPage(for: id), baseURL: URL(string: YouTubeLink.referrer))
    }
}
