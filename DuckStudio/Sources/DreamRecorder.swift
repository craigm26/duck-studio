import SwiftUI
import AVFoundation
import CoreGraphics
import CoreVideo
import StudioKit

/// Runs recorded for Dream-1, kept on this device until they are exported.
///
/// WHAT A RUN IS: `DreamDataset.Take`, a frame of data ten times a second (the command in force
/// before, the command in force now) and the head camera's newest picture beside each, written as
/// H.264 the moment it is taken. StudioKit writes everything else (`DreamDataset.files`), and Dream
/// Labs' own validator passes what it writes (scripts/check_dream_dataset.py).
///
/// KEPT ACROSS LAUNCHES: each finished run is a video and a line in `takes.json` under Application
/// Support, so closing the app does not lose an afternoon of driving. Nothing leaves the device until
/// Export, and then only to where the person sends it.
@MainActor
final class DreamRecorder: ObservableObject {
    struct Saved: Codable { let task: String; let rows: [[Double]]; let video: String }

    @Published private(set) var takes: [Saved] = []
    @Published private(set) var recording = false
    @Published private(set) var seconds: Double = 0
    @Published private(set) var line: String?
    @Published var exported: URL?

    private var task: Task<Void, Never>?
    private let folder: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("DreamRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: folder.appendingPathComponent("takes.json")),
           let saved = try? JSONDecoder().decode([Saved].self, from: data) {
            takes = saved
        }
    }

    var totalSeconds: Double {
        Double(takes.reduce(0) { $0 + $1.rows.count }) / Double(DreamDataset.fps)
    }

    func start(task name: String, peer: any DuckPeer, source: DreamFrameSource) {
        guard !recording else { return }
        let video = "take-\(UUID().uuidString).mp4"
        guard let writer = DreamTakeWriter(url: folder.appendingPathComponent(video)) else {
            line = DuckDream.Words.cannotRecord
            return
        }
        recording = true
        seconds = 0
        line = nil
        let period = 1.0 / Double(DreamDataset.fps)
        task = Task { [weak self] in
            var take = DreamDataset.Take(task: name)
            let began = Date()
            while !Task.isCancelled {
                let due = began.addingTimeInterval(Double(take.rows.count + 1) * period)
                if let picture = source.latestPicture {
                    take.tick(command: await peer.lastCommand())
                    writer.append(picture, frame: take.rows.count - 1)
                    self?.seconds = take.seconds
                }
                let wait = due.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            }
            await writer.finish()
            self?.finished(take, video: video)
        }
    }

    func stop() { task?.cancel() }

    private func finished(_ take: DreamDataset.Take, video: String) {
        recording = false
        guard take.longEnough else {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(video))
            line = DreamDataset.Refusal.tooShort(takes.count, take.rows.count).message
            return
        }
        takes.append(Saved(task: take.task,
                           rows: take.rows.map { [$0.state.vx, $0.state.vy, $0.state.vyaw,
                                                  $0.action.vx, $0.action.vy, $0.action.vyaw] },
                           video: video))
        save()
    }

    func discardLast() {
        guard let last = takes.popLast() else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(last.video))
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(takes) {
            try? data.write(to: folder.appendingPathComponent("takes.json"))
        }
    }

    private var episodes: [DreamDataset.Episode] {
        takes.map { t in
            DreamDataset.Episode(task: t.task, rows: t.rows.map {
                DreamDataset.Row(state: DuckDrive.Twist(vx: $0[0], vy: $0[1], vyaw: $0[2]),
                                 action: DuckDrive.Twist(vx: $0[3], vy: $0[4], vyaw: $0[5]))
            })
        }
    }

    /// The dataset as a .zip holding one LeRobot folder: what Dream Labs' Upload page takes once unzipped.
    func export() {
        line = nil
        do {
            let files = try DreamDataset.files(episodes)
            let name = DreamDataset.folderName(date: Date())
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("dream-export", isDirectory: true)
            try? FileManager.default.removeItem(at: staging)
            let root = staging.appendingPathComponent(name, isDirectory: true)
            for (path, data) in files {
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
            for (i, t) in takes.enumerated() {
                let url = root.appendingPathComponent(DreamDataset.videoPath(i))
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: folder.appendingPathComponent(t.video), to: url)
            }
            exported = try Self.zip(root, named: name, into: staging)
        } catch let refusal as DreamDataset.Refusal {
            line = refusal.message
        } catch {
            line = error.localizedDescription
        }
    }

    /// The system's own zip of a folder (the one Files makes for sharing a folder).
    private static func zip(_ folder: URL, named name: String, into dir: URL) throws -> URL {
        var made: URL?
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zip in
            let out = dir.appendingPathComponent("\(name).zip")
            do {
                try? FileManager.default.removeItem(at: out)
                try FileManager.default.copyItem(at: zip, to: out)
                made = out
            } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
        guard let made else { throw CocoaError(.fileWriteUnknown) }
        return made
    }
}

/// One run's video: H.264 at Dream-1's size, one frame per frame of data, at a constant 10 fps.
final class DreamTakeWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor

    init?(url: URL) {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: DreamDataset.width,
            AVVideoHeightKey: DreamDataset.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 600_000,
                                              AVVideoExpectedSourceFrameRateKey: DreamDataset.fps,
                                              AVVideoMaxKeyFrameIntervalKey: DreamDataset.fps],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: DreamDataset.width,
            kCVPixelBufferHeightKey as String: DreamDataset.height,
        ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
    }

    /// The picture for frame `frame`, scaled to Dream-1's size; its time is frame / fps exactly.
    func append(_ picture: CGImage, frame: Int) {
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: DreamDataset.width,
                                   height: DreamDataset.height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.interpolationQuality = .medium
            context.draw(picture, in: CGRect(x: 0, y: 0, width: DreamDataset.width, height: DreamDataset.height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(DreamDataset.fps)))
    }

    func finish() async {
        input.markAsFinished()
        await writer.finishWriting()
    }
}

/// The recording half of `DreamPanel`.
struct DreamRecordSection: View {
    let peer: (any DuckPeer)?
    let source: DreamFrameSource
    @ObservedObject var recorder: DreamRecorder
    var hasPicture: Bool
    @AppStorage("dream.recordTask") private var task = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Text(DreamDataset.Words.heading).font(.headline)
            Text(DreamDataset.Words.whatItIs).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(DreamDataset.Words.taskPlaceholder, text: $task, axis: .vertical)
                .font(.callout)
                .frame(minHeight: DesignMetric.minimumTarget)
            if recorder.recording {
                Button { recorder.stop() } label: {
                    Label(DreamDataset.Words.stop, systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                Text(DreamDataset.Words.recording(recorder.seconds)).font(.caption.monospacedDigit())
            } else {
                Button {
                    guard let peer else { return }
                    recorder.start(task: task.trimmingCharacters(in: .whitespacesAndNewlines), peer: peer, source: source)
                } label: {
                    Label(DreamDataset.Words.start, systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(peer == nil || !hasPicture || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !recorder.takes.isEmpty {
                Text(DreamDataset.Words.runs(recorder.takes.count, recorder.totalSeconds))
                    .font(.footnote).foregroundStyle(Theme.measured)
                HStack {
                    Button(DreamDataset.Words.discard, role: .destructive) { recorder.discardLast() }
                        .disabled(recorder.recording)
                    Spacer()
                    Button(DreamDataset.Words.export) { recorder.export() }
                        .disabled(recorder.recording)
                }
                .font(.footnote)
                .buttonStyle(.borderless)
                if let zip = recorder.exported {
                    ShareLink(item: zip) {
                        Label(zip.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                    .font(.footnote)
                    Text(DreamDataset.Words.howToUpload).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let line = recorder.line {
                Text(line).font(.caption).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
