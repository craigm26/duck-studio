import Foundation
import AVFoundation
import Vision
import ReplayKit
import CoreImage
import UIKit
import Combine
import DuckKit
import StudioKit

/// Frames in, a duck's pose out.
///
/// ONE PIPELINE FOR THREE SOURCES. A camera, a video playing on this screen and
/// a YouTube clip playing in a web view all end as a pixel buffer with a
/// timestamp; this object hands each one to Vision's 3D body-pose request,
/// turns the seventeen joints it answers with into a `HumanFigure`, and lets
/// `PoseRetarget` — in the kit, tested on a Pi — decide what the duck does.
/// Nothing here knows a hip from a knee: the app target converts a framework's
/// points into `DuckVector`s and gets out of the way, which is the same
/// division `CameraDoor` keeps with `CameraAvailability`.
///
/// WHAT THE COORDINATES ARE. `VNHumanBodyPose3DObservation` reports every joint
/// as a 4×4 transform relative to the root joint, in metres. The translation
/// column is the point; the upper-left 3×3 is the joint's orientation. Both go
/// across as they are: the kit builds the person's own frame from their hips
/// and spine, so the model's axes never have to be understood here, and the
/// head's turn is measured as the head joint's rotation relative to the
/// shoulder joint's — convention-free, as `HumanFigure` explains. THE ONE THING
/// THAT CANNOT BE DERIVED IS HANDEDNESS, and the `mirrored` switch is the
/// answer: it swaps the person's sides, which is also what a mirror does. It
/// is off by default — the duck faces the way the person faces.
///
/// FRAMES ARE DROPPED WHILE ONE IS BEING READ. The 3D request costs tens of
/// milliseconds on a recent phone and more on an older one; queueing frames
/// behind it would make the duck follow you with a growing delay. The rate it
/// actually manages is published, and drawn, because a duck answering four
/// times a second is a fact worth seeing rather than a stutter to wonder about.
@MainActor
final class PoseCaptureEngine: ObservableObject {

    /// The last person found, already mirrored if asked.
    @Published private(set) var figure: HumanFigure?
    /// The duck, retargeted from `figure`, or nil while nobody is in view.
    @Published private(set) var duckPose: [Double]?
    @Published private(set) var reading: HumanFigure.Reading?
    @Published private(set) var clamped: [Int] = []
    /// How many poses a second Vision is managing, measured over the last
    /// second of answers.
    @Published private(set) var posesPerSecond: Double = 0
    /// True when the last frame read had a person in it that the 3D model
    /// could read.
    @Published private(set) var personInView = false
    /// True when the last frame had a person the 2D stage found, whether or
    /// not the 3D stage could read them. `personInView` implies this.
    @Published private(set) var personSeen = false
    /// How many frames a second the source is delivering, read or dropped —
    /// zero means the source is not producing pictures at all, which is a
    /// different fact from pictures with nobody in them.
    @Published private(set) var framesPerSecond: Double = 0
    /// Something the source wants said — a capture that would not start.
    @Published private(set) var sourceNote: String?

    /// OFF BY DEFAULT: the duck faces the way the person faces. Craig's call
    /// on the first phone test ("to not mirror a human"); the switch stays
    /// for anybody who wants the looking-glass version.
    @Published var mirrored = false {
        didSet { if let last = lastRaw { absorb(last) } }
    }

    // MARK: recording

    @Published private(set) var isRecording = false
    @Published private(set) var track = MimicTrack()
    /// Set when the track filled up on its own.
    @Published private(set) var stoppedAtCap = false

    private var lastRaw: HumanFigure?
    private var source: (any FrameSource)?
    private var answered: [TimeInterval] = []
    private var offered: [TimeInterval] = []

    /// The Vision work, off the main actor and one frame at a time.
    private let detector = PoseDetector()

    // MARK: - sources

    /// Read frames from the camera. Replaces whatever source was running.
    func useCamera(position: AVCaptureDevice.Position) {
        replace(with: CameraFrameSource(position: position))
    }

    /// Read frames from a video playing in a player this screen draws.
    func useVideo(output: AVPlayerItemVideoOutput, player: AVPlayer, orientation: CGImagePropertyOrientation) {
        replace(with: VideoFrameSource(output: output, player: player, orientation: orientation))
    }

    /// Read frames off this phone's own screen, inside a rectangle in screen
    /// points, for a player that will not hand its frames over any other way.
    func useScreen(region: CGRect) {
        if let screen = source as? ScreenFrameSource {
            screen.region = region
            return
        }
        replace(with: ScreenFrameSource(region: region))
    }

    /// The camera session being read, for a preview to draw, or nil when the
    /// source is not a camera.
    var cameraSession: AVCaptureSession? { (source as? CameraFrameSource)?.session }

    /// Stop reading frames. The last pose stays on the picture.
    func stopSource() {
        source?.stop()
        source = nil
        offered = []
        framesPerSecond = 0
    }

    private func replace(with next: any FrameSource) {
        source?.stop()
        source = next
        sourceNote = nil
        next.onFrame = { [weak self] buffer, orientation, region, clock in
            guard let self else { return }
            self.offered.append(clock)
            self.offered.removeAll { $0 < clock - 1 }
            self.framesPerSecond = Double(self.offered.count)
            self.detector.read(buffer, orientation: orientation, region: region) { sighting in
                Task { @MainActor [weak self] in
                    self?.received(sighting, at: clock)
                }
            }
        }
        next.onNote = { [weak self] note in
            Task { @MainActor [weak self] in self?.sourceNote = note }
        }
        next.start()
    }

    // MARK: - what comes back

    private func received(_ sighting: PoseDetector.Sighting, at clock: TimeInterval) {
        answered.append(clock)
        answered.removeAll { $0 < clock - 1 }
        posesPerSecond = Double(answered.count)
        let raw: HumanFigure?
        switch sighting {
        case .nobody: raw = nil; personSeen = false
        case .seen: raw = nil; personSeen = true
        case .figure(let figure): raw = figure; personSeen = true
        }
        personInView = raw != nil
        // NOBODY IN VIEW CLEARS THE READING. The first phone test printed hip
        // and knee angles under "No person found": the reading was the last
        // person's, left standing. The screens keep drawing the last pose on
        // purpose (`lastShown`, `posed`), but a readout of a person who is
        // not there is a readout of nobody.
        guard let raw else {
            duckPose = nil; reading = nil; clamped = []
            return
        }
        lastRaw = raw
        absorb(raw)
        if isRecording, let duckPose {
            track.add(duckPose, at: clock)
            if track.isFull {
                isRecording = false
                stoppedAtCap = true
            }
        }
    }

    private func absorb(_ raw: HumanFigure) {
        let oriented = mirrored ? raw.mirrored : raw
        figure = oriented
        guard let out = PoseRetarget.duckPose(from: oriented) else {
            duckPose = nil; reading = nil; clamped = []
            return
        }
        duckPose = out.pose
        reading = out.reading
        clamped = out.clamped
    }

    // MARK: - recording

    func startRecording() {
        track.clear()
        stoppedAtCap = false
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
    }

    func discardRecording() {
        isRecording = false
        stoppedAtCap = false
        track.clear()
    }
}

// MARK: - Vision

/// Vision's body-pose requests, run on their own queue one frame at a time.
///
/// TWO STAGES, BECAUSE THE 3D MODEL WANTS A BIG PERSON. The first phone test
/// played a skateboarder who filled a sixth of the screen and the 3D request
/// answered nothing, frame after frame. Vision resizes whatever it is given to
/// the model's own input size, so a person eighty pixels tall stays eighty
/// pixels tall. The 2D request is far more tolerant: it finds the person,
/// its joints give a box, and the 3D request is handed a crop of that box —
/// the same pixels, with the person now filling the frame. What comes back is
/// still a skeleton in metres relative to the root, so the crop changes
/// nothing downstream.
///
/// AND IT TELLS THE TWO FAILURES APART. "Nobody in the picture" and "somebody
/// the 3D model could not read" are different sentences with different
/// remedies, and a single nil would have collapsed them.
final class PoseDetector: @unchecked Sendable {

    enum Sighting: Sendable {
        case nobody
        /// The 2D stage found a person; the 3D stage could not read them.
        case seen
        case figure(HumanFigure)
    }

    private let queue = DispatchQueue(label: "duckstudio.pose", qos: .userInitiated)
    private var busy = false
    private let lock = NSLock()

    /// Joints below this confidence do not count toward the person's box.
    private static let confidentEnough: Float = 0.3
    /// How many confident joints make a person worth cropping to.
    private static let enoughJoints = 6
    /// Room around the joints' box, as a fraction of its size, so the head
    /// and feet — which the 2D box is measured to, not past — stay inside.
    private static let margin: CGFloat = 0.35

    /// Read one frame. Dropped, silently, when the previous one is still
    /// being read.
    func read(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
              region: CGRect?, then: @escaping @Sendable (Sighting) -> Void) {
        lock.lock()
        if busy { lock.unlock(); return }
        busy = true
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); busy = false; lock.unlock() }
            then(sight(buffer, orientation: orientation, region: region))
        }
    }

    private func sight(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                       region: CGRect?) -> Sighting {
        var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        if let region { image = Self.crop(image, to: region) }
        // Stage one: is there a person, and where.
        let flat = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(ciImage: image, orientation: .up).perform([flat])
        } catch {
            return .nobody
        }
        guard let body = flat.results?.first,
              let joints = try? body.recognizedPoints(.all) else { return .nobody }
        let confident = joints.values.filter { $0.confidence >= Self.confidentEnough }
        guard confident.count >= Self.enoughJoints else { return .nobody }
        let xs = confident.map(\.location.x), ys = confident.map(\.location.y)
        var box = CGRect(x: xs.min()!, y: ys.min()!,
                         width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        box = box.insetBy(dx: -box.width * Self.margin, dy: -box.height * Self.margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard box.width > 0.02, box.height > 0.02 else { return .seen }
        // Stage two: the 3D reading, on the person alone.
        let deep = VNDetectHumanBodyPose3DRequest()
        do {
            try VNImageRequestHandler(ciImage: Self.crop(image, to: box), orientation: .up)
                .perform([deep])
        } catch {
            return .seen
        }
        guard let observation = deep.results?.first,
              let figure = Self.figure(from: observation) else { return .seen }
        return .figure(figure)
    }

    /// A normalised rectangle of an image (origin bottom-left, as Vision has
    /// it), as a new image whose extent starts at zero — Vision's normalised
    /// answers are relative to the extent, so the extent has to be the crop.
    private static func crop(_ image: CIImage, to normalised: CGRect) -> CIImage {
        let e = image.extent
        let rect = CGRect(x: e.minX + normalised.minX * e.width,
                          y: e.minY + normalised.minY * e.height,
                          width: normalised.width * e.width,
                          height: normalised.height * e.height)
        let cropped = image.cropped(to: rect)
        return cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.minX,
                                                         y: -cropped.extent.minY))
    }

    /// The observation as the kit's figure: seventeen points and two rotations.
    static func figure(from observation: VNHumanBodyPose3DObservation) -> HumanFigure? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        var out: [HumanFigure.Joint: DuckVector] = [:]
        var head: HumanFigure.Rotation?
        var torso: HumanFigure.Rotation?
        for (name, point) in points {
            guard let joint = joint(for: name) else { continue }
            let m = point.position
            out[joint] = DuckVector(Double(m.columns.3.x), Double(m.columns.3.y), Double(m.columns.3.z))
            if joint == .centerHead { head = rotation(of: m) }
            if joint == .centerShoulder { torso = rotation(of: m) }
        }
        guard !out.isEmpty else { return nil }
        let both = head != nil && torso != nil
        return HumanFigure(points: out, headRotation: both ? head : nil,
                           torsoRotation: both ? torso : nil)
    }

    /// The upper-left 3×3, row-major. simd stores columns, so the row-major
    /// walk reads across the columns.
    private static func rotation(of m: simd_float4x4) -> HumanFigure.Rotation {
        HumanFigure.Rotation(rowMajor: [
            Double(m.columns.0.x), Double(m.columns.1.x), Double(m.columns.2.x),
            Double(m.columns.0.y), Double(m.columns.1.y), Double(m.columns.2.y),
            Double(m.columns.0.z), Double(m.columns.1.z), Double(m.columns.2.z),
        ])
    }

    /// Vision's names to the kit's, one to one. Anything Vision adds later is
    /// dropped rather than guessed at.
    private static func joint(for name: VNHumanBodyPose3DObservation.JointName) -> HumanFigure.Joint? {
        switch name {
        case .root: return .root
        case .spine: return .spine
        case .centerShoulder: return .centerShoulder
        case .centerHead: return .centerHead
        case .topHead: return .topHead
        case .leftShoulder: return .leftShoulder
        case .leftElbow: return .leftElbow
        case .leftWrist: return .leftWrist
        case .rightShoulder: return .rightShoulder
        case .rightElbow: return .rightElbow
        case .rightWrist: return .rightWrist
        case .leftHip: return .leftHip
        case .leftKnee: return .leftKnee
        case .leftAnkle: return .leftAnkle
        case .rightHip: return .rightHip
        case .rightKnee: return .rightKnee
        case .rightAnkle: return .rightAnkle
        default: return nil
        }
    }
}

// MARK: - frame sources

/// Something that produces pixel buffers with a clock.
///
/// `region` is Vision's region of interest in its own normalised coordinates
/// (origin bottom-left), or nil for the whole frame. `clock` is seconds on a
/// monotonic clock, which is what the recording track keys on.
@MainActor
protocol FrameSource: AnyObject {
    var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation, CGRect?, TimeInterval) -> Void)? { get set }
    var onNote: ((String) -> Void)? { get set }
    func start()
    func stop()
}

/// The camera, delivered upright and, on the front camera, mirrored — so the
/// buffer is the picture the preview shows and `mirrored` means one thing.
@MainActor
final class CameraFrameSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation, CGRect?, TimeInterval) -> Void)?
    var onNote: ((String) -> Void)?

    let session = AVCaptureSession()
    private let position: AVCaptureDevice.Position
    private let queue = DispatchQueue(label: "duckstudio.camera")

    init(position: AVCaptureDevice.Position) {
        self.position = position
        super.init()
    }

    func start() {
        let session = self.session
        let position = self.position
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if let self, session.canAddOutput(output) {
                output.setSampleBufferDelegate(self, queue: self.queue)
                session.addOutput(output)
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if position == .front, connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    }
                }
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let clock = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in self?.onFrame?(buffer, .up, nil, clock) }
    }
}

/// A video playing in an `AVPlayer` this screen owns, read through a video
/// output on a display link — so the frame the model reads is the frame the
/// player is showing.
@MainActor
final class VideoFrameSource: NSObject, FrameSource {
    var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation, CGRect?, TimeInterval) -> Void)?
    var onNote: ((String) -> Void)?

    private let output: AVPlayerItemVideoOutput
    private let player: AVPlayer
    private let orientation: CGImagePropertyOrientation
    private var link: CADisplayLink?

    // NSObject because a display link's target needs an `@objc` selector.
    init(output: AVPlayerItemVideoOutput, player: AVPlayer, orientation: CGImagePropertyOrientation) {
        self.output = output
        self.player = player
        self.orientation = orientation
        super.init()
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 15)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        guard player.rate != 0 || player.currentItem?.status == .readyToPlay else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        else { return }
        onFrame?(buffer, orientation, nil, ProcessInfo.processInfo.systemUptime)
    }
}

/// The phone's own screen, through ReplayKit's in-app capture, cropped to the
/// rectangle a player is drawn in.
///
/// THIS IS THE ONLY WAY TO SEE A YOUTUBE CLIP'S FRAMES WITHOUT DOWNLOADING IT.
/// A web view does not hand its video frames to the app, and pulling a stream
/// URL out of YouTube is a terms-of-service problem this app declines to have.
/// ReplayKit asks the person once — a system sheet — and captures only while
/// the app is in front. `MimicSource.youtube.how` says all of this before the
/// sheet appears.
@MainActor
final class ScreenFrameSource: FrameSource {
    var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation, CGRect?, TimeInterval) -> Void)?
    var onNote: ((String) -> Void)?

    /// Where the player is, in screen points. Updated as layout moves it.
    var region: CGRect

    init(region: CGRect) {
        self.region = region
    }

    func start() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            onNote?(Mimic.screenReadingFailed("Screen reading is not available on this device."))
            return
        }
        recorder.isMicrophoneEnabled = false
        recorder.startCapture(handler: { [weak self] sample, kind, error in
            guard kind == .video, error == nil,
                  let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
            let clock = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                // NEVER THE WHOLE SCREEN. Until the player's rectangle is
                // known the frame is dropped, not read: on the first phone
                // test the whole screen was read and the rendered duck under
                // the player was found as a person, hips and knees and all.
                guard let self, let region = self.visionRegion else { return }
                self.onFrame?(buffer, .up, region, clock)
            }
        }, completionHandler: { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.onNote?(Mimic.screenReadingFailed(error.localizedDescription))
            }
        })
    }

    func stop() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isRecording else { return }
        recorder.stopCapture { _ in }
    }

    /// The player's rectangle as Vision wants it: normalised to the screen,
    /// origin at the bottom-left. Nil when the rectangle is empty, and a nil
    /// region means the frame is dropped — see `start`.
    private var visionRegion: CGRect? {
        let screen = UIScreen.main.bounds
        guard screen.width > 0, screen.height > 0, region.width > 0, region.height > 0 else { return nil }
        let clipped = region.intersection(screen)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return CGRect(x: clipped.minX / screen.width,
                      y: 1 - clipped.maxY / screen.height,
                      width: clipped.width / screen.width,
                      height: clipped.height / screen.height)
    }
}
