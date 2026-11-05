import SwiftUI
import CoreGraphics
import StudioKit

/// The phone driver on this device: whether it is here, getting it, and deleting it.
///
/// `DriverInstaller` does the work and every sentence is the kit's. What is here is what a device
/// has and the kit does not: a real folder, a real download, and one published phase for the screens.
@MainActor
final class PhoneDrivers: ObservableObject {
    static let shared = PhoneDrivers()
    /// Whether a checked driver is on this device now.
    static var installed: Bool { shared.phase.isInstalled }

    @Published private(set) var phase: DriverInstall.Phase = .absent
    private var task: Task<Void, Never>?
    private let installer: DriverInstaller

    var release: DriverRelease { installer.release }
    /// The installed driver's folder, for `DriverTrial.load`.
    var folder: String { installer.folder.path }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneDrivers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // A DOWNLOAD, NOT THE PERSON'S WORK: not worth a place in their backup.
        var folder = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let installer = DriverInstaller(release: .walkToBall, root: base)
        self.installer = installer
        Task { [weak self] in
            let found = await Task.detached { installer.status() }.value
            guard let self, self.task == nil else { return }
            self.phase = found
        }
    }

    func get() {
        guard task == nil, !phase.isInstalled else { return }
        phase = .getting(done: 0, total: release.bytes)
        let installer = installer
        task = Task { [weak self] in
            let report: @Sendable (DriverInstall.Phase) -> Void = { next in
                Task { @MainActor in self?.heard(next) }
            }
            let ended: DriverInstall.Phase
            do {
                try await Task.detached {
                    try await installer.install(fetch: DriverDownload.fetch, report: report)
                }.valueCancellingWithCaller()
                ended = .installed
            } catch is CancellationError {
                ended = .absent
            } catch let problem as DriverInstall.Problem {
                ended = .failed(problem.message)
            } catch {
                ended = .failed(error.localizedDescription)
            }
            self?.finish(ended)
        }
    }

    /// Progress arrives on its own tasks: anything late is dropped once the install has ended.
    private func heard(_ next: DriverInstall.Phase) {
        guard task != nil else { return }
        phase = next
    }

    private func finish(_ ended: DriverInstall.Phase) {
        task = nil
        phase = ended
    }

    func cancel() { task?.cancel() }

    func delete() {
        do {
            try installer.delete()
            phase = .absent
        } catch let problem as DriverInstall.Problem {
            phase = .failed(problem.message)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func act(_ action: DriverCard.Action, go: () -> Void) {
        switch action {
        case .get, .tryAgain: get()
        case .cancel: cancel()
        case .go: go()
        case .delete: delete()
        }
    }
}

private extension Task where Failure == Error {
    /// This detached task's value, cancelling it when the caller is cancelled.
    func valueCancellingWithCaller() async throws -> Success {
        try await withTaskCancellationHandler { try await value } onCancel: { cancel() }
    }
}

/// One file over plain URLSession, with progress: no Hugging Face client, no cache, no lock.
///
/// WHY NOT THE HUB CLIENT. swift-huggingface holds a `flock` for a whole download, and an app
/// suspended holding one is killed (0xdead10cc). This holds nothing: a download interrupted by
/// suspension fails, and the card offers Try again.
final class DriverDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let limit: Int
    private let progress: @Sendable (Int) -> Void
    private let lock = NSLock()
    private var done: CheckedContinuation<Data, Error>?

    private init(limit: Int, progress: @escaping @Sendable (Int) -> Void) {
        self.limit = limit; self.progress = progress
    }

    static func fetch(_ url: URL, limit: Int, progress: @escaping @Sendable (Int) -> Void) async throws -> Data {
        try Task.checkCancellation()
        let download = DriverDownload(limit: limit, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.lock.withLock { download.done = continuation }
                task.resume()
            }
        } onCancel: { task.cancel() }
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.withLock {
            let waiting = done
            done = nil
            return waiting
        }?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > Int64(limit) {
            finish(.failure(DriverInstall.Problem.notThePinnedFile(downloadTask.originalRequest?.url?.lastPathComponent ?? "")))
            downloadTask.cancel()
            return
        }
        progress(Int(totalBytesWritten))
    }

    /// The temporary file is gone when this returns, so it is read here, in one call.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let answer = downloadTask.response as? HTTPURLResponse, answer.statusCode != 200 {
            finish(.failure(DriverInstall.Problem.download("Hugging Face answered \(answer.statusCode).")))
            return
        }
        finish(Result { try Data(contentsOf: location) })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as? URLError)?.code == .cancelled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(error))
        }
    }
}

/// A head-camera JPEG as the RGB bytes a driver reads. THE ONE DECODE, for the phone and for M1.
enum DriverPicture {
    nonisolated static func rgb(_ jpeg: String) -> [UInt8]? {
        guard let data = Data(base64Encoded: jpeg), let image = DuckCameraFeed.decode(data) else { return nil }
        var rgba = [UInt8](repeating: 0, count: DriverTrial.rgbaCount)
        let drew = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: DriverPrep.pictureWidth,
                                          height: DriverPrep.pictureHeight, bitsPerComponent: 8,
                                          bytesPerRow: DriverTrial.rgbaRowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: DriverPrep.pictureWidth, height: DriverPrep.pictureHeight))
            return true
        }
        return drew ? DriverTrial.rgb(rgba: rgba) : nil
    }
}

#if os(macOS)
/// The headless check: `DuckStudio -driver-get-check`. The real download, into a temporary folder
/// that is deleted again, so URLSession, the pins, Cancel and the golden replay are proved on a Mac
/// over ssh with nothing left behind.
enum DriverGetCheck {
    static let flag = "-driver-get-check"

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func add() -> Int { lock.withLock { count += 1; return count } }
    }

    private nonisolated static func say(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    @MainActor static func run() async -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("driver-get-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = DriverInstaller(release: .walkToBall, root: root)
        say("before: \(installer.status())")

        // CANCEL: the first progress cancels the install.
        let heard = Count()
        let cancelled = Task.detached {
            try await installer.install(fetch: DriverDownload.fetch) { phase in
                if case .getting(let done, _) = phase, done > 0 { _ = heard.add() }
            }
        }
        while heard.value == 0 { try? await Task.sleep(nanoseconds: 2_000_000) }
        cancelled.cancel()
        do {
            try await cancelled.value
            say("cancel: it finished first")
        } catch is CancellationError {
            say("cancel: stopped")
        } catch {
            say("cancel: \(error)")
        }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        say("after cancel: \(installer.status()), left \(left)")
        try? installer.delete()

        let began = Date()
        let ticks = Count()
        do {
            try await installer.install(fetch: DriverDownload.fetch) { phase in
                if case .getting = phase { _ = ticks.add() } else { say("\(phase)") }
            }
        } catch {
            say("failed: \((error as? DriverInstall.Problem)?.message ?? String(describing: error))")
            return 1
        }
        say("took \(Date().timeIntervalSince(began)) s, progress heard \(ticks.add() - 1) times")
        let after = installer.status()
        say("status: \(after)")
        do {
            let loaded = try DriverTrial.load(folder: installer.folder.path, decode: { DriverPicture.rgb($0) })
            say("loaded: \(loaded.modelID), snap \(loaded.manifest.outputSnap != nil)")
            try installer.delete()
        } catch {
            say("load failed: \(error)")
            return 1
        }
        say("deleted: \(installer.status())")
        return after == .installed ? 0 : 1
    }
}
#endif
