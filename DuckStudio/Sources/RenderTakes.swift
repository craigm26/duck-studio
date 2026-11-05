import Foundation
import SwiftUI
import CoreGraphics
import ImageIO
import StudioKit

#if os(macOS)
/// The headless render job: `DuckStudio -render-takes IN.jsonl OUTDIR [-render-png 0:0,5:40]`.
///
/// WHAT IT IS FOR. The phone driver trains on the scripted expert's takes, which hold physics and no
/// pictures. This draws each row's picture with the app's own `SimHeadCameraRenderer`, sends it
/// through the very path a picture takes to a driver at run time (`DuckCameraFeed.dreamJPEG`: faces
/// blurred, 320 by 176, JPEG at 0.85), and writes it into the take's video with `DreamTakeWriter`, the
/// recorder's own H.264 writer, one frame per row. StudioKit (`BallTakes`) reads the takes, writes
/// every other file, and decides which state draws which frame; this only draws and encodes.
///
/// NO WINDOW. It runs before SwiftUI starts (see `DuckStudioLaunch`), so it works over ssh on a Mac
/// with no GUI session, and the app quits when it is done: status 0 when every frame was written.
@MainActor
enum RenderTakes {
    static func run(_ job: BallTakes.Job) async -> Int32 {
        guard #available(macOS 15.0, *) else { return fail(BallTakes.Words.noRenderer) }
        do {
            let takes = try BallTakes.read(jsonl: try Data(contentsOf: URL(fileURLWithPath: job.input)))
            let plan = try BallTakes.plan(takes, pictures: job.pictures)
            say(BallTakes.Words.read(takes.count, plan.frames))
            guard let renderer = SimHeadCameraRenderer() else { return fail(BallTakes.Words.noRenderer) }
            let root = URL(fileURLWithPath: job.output, isDirectory: true)
            for (path, data) in plan.files { try write(data, to: root.appendingPathComponent(path)) }
            for (i, video) in plan.videos.enumerated() {
                let url = root.appendingPathComponent(video.path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let writer = DreamTakeWriter(url: url) else { return fail(BallTakes.Words.frameFailed(i, 0)) }
                for (f, live) in video.states.enumerated() {
                    guard let frame = await picture(renderer, live), await append(frame, f, to: writer) else {
                        return fail(BallTakes.Words.frameFailed(i, f))
                    }
                }
                await writer.finish()
                say(BallTakes.Words.video(i, of: plan.videos.count, frames: video.states.count))
            }
            let shots = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-pictures")
            for (p, live) in plan.pictures {
                guard let frame = await picture(renderer, live), let png = pngData(frame) else {
                    return fail(BallTakes.Words.frameFailed(p.episode, p.frame))
                }
                try write(png, to: shots.appendingPathComponent(p.fileName))
            }
            say(BallTakes.Words.done(plan.videos.count, plan.frames, root.path))
            return 0
        } catch let refusal as BallTakes.Refusal {
            return fail(refusal.message)
        } catch let refusal as BallTakes.PlanRefusal {
            return fail(refusal.message)
        } catch let refusal as DreamDataset.Refusal {
            return fail(refusal.message)
        } catch {
            return fail(error.localizedDescription)
        }
    }

    /// The picture exactly as a driver is handed it at run time: drawn, then `dreamJPEG`, then decoded.
    @available(macOS 15.0, *)
    private static func picture(_ renderer: SimHeadCameraRenderer, _ live: DuckDrive.Live) async -> CGImage? {
        guard let drawn = await renderer.render(live), let jpeg = DuckCameraFeed.dreamJPEG(drawn),
              let bytes = Data(base64Encoded: jpeg) else { return nil }
        return DuckCameraFeed.decode(bytes)
    }

    /// The recorder's writer takes a frame only when it is ready for one; offline that is a wait,
    /// not a dropped frame. Five seconds of not ready is a failure.
    private static func append(_ frame: CGImage, _ index: Int, to writer: DreamTakeWriter) async -> Bool {
        for _ in 0..<500 {
            if writer.append(frame, frame: index) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func fail(_ why: String) -> Int32 {
        FileHandle.standardError.write(Data((BallTakes.Words.failed(why) + "\n").utf8))
        return 1
    }
}
#endif

/// The app's entry point: the headless render job (`-render-takes`) or the M1 driver trial
/// (`-driver-trial`) when launched so on a Mac, otherwise the app itself.
@main
@MainActor
enum DuckStudioLaunch {
    static func main() {
        #if os(macOS)
        if let job = BallTakes.job(arguments: CommandLine.arguments) {
            Task { @MainActor in exit(await RenderTakes.run(job)) }
            dispatchMain()
        }
        if let job = DriverTrial.job(arguments: CommandLine.arguments) {
            Task { @MainActor in exit(await DriverTrialRun.run(job)) }
            dispatchMain()
        }
        if CommandLine.arguments.contains(DriverGetCheck.flag) {
            Task { @MainActor in exit(await DriverGetCheck.run()) }
            dispatchMain()
        }
        #endif
        DuckStudioApp.main()
    }
}
