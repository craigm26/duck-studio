import Foundation
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
        return await DriverTrial.main(job, wire: DriverTrial.stdioWire(), decode: { DriverPicture.rgb($0) },
                                      render: { live in await picture(live) })
    }

    /// The picture a driver is sent at run time: drawn, then `dreamJPEG` (base64 JPEG).
    private static func picture(_ live: DuckDrive.Live) async -> String? {
        guard #available(macOS 15.0, *), let renderer = renderer as? SimHeadCameraRenderer,
              let drawn = await renderer.render(live) else { return nil }
        return DuckCameraFeed.dreamJPEG(drawn)
    }
}
#endif
