import Foundation
import CoreGraphics
import ImageIO
import StudioKit

#if os(macOS)
/// The headless M1 job: `DuckStudio -driver-trial DRIVER_FOLDER` (or `-driver-trial zero`).
///
/// WHAT IT IS FOR. A phone driver is judged closed loop on the simulated duck (M1). The physics runs
/// on the bench machine, which speaks to this over stdin and stdout (`scripts/m1_trial.py`); this
/// draws the head camera with the app's own `SimHeadCameraRenderer` and `dreamJPEG`, and StudioKit's
/// `DriverTrial` runs the shipped `DreamPilot` with the driver loaded as the phone loads one. This
/// only draws pictures and decodes them back to the bytes a driver reads.
@MainActor
enum DriverTrialRun {
    private static var renderer: AnyObject?

    static func run(_ job: DriverTrial.Job) async -> Int32 {
        guard #available(macOS 15.0, *), let made = SimHeadCameraRenderer() else {
            FileHandle.standardError.write(Data((BallTakes.Words.noRenderer + "\n").utf8))
            return 1
        }
        renderer = made
        return await DriverTrial.main(job, wire: DriverTrial.stdioWire(), decode: { decode($0) },
                                      render: { live in await picture(live) })
    }

    /// The picture a driver is sent at run time: drawn, then `dreamJPEG` (base64 JPEG).
    private static func picture(_ live: DuckDrive.Live) async -> String? {
        guard #available(macOS 15.0, *), let renderer = renderer as? SimHeadCameraRenderer,
              let drawn = await renderer.render(live) else { return nil }
        return DuckCameraFeed.dreamJPEG(drawn)
    }

    /// A base64 JPEG back to RGB bytes at the driver's picture size, as a phone driver's `decode` does.
    nonisolated static func decode(_ jpeg: String) -> [UInt8]? {
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
#endif
