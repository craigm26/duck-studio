import Foundation

/// Walk to the ball: a one-tap skill in Tell, on the practice duck and on a real one.
///
/// IT IS NOT AUTONOMY. The person starts it, watches it and ends it (the owner's call after build
/// 94), so it sits with Tell's tiles and not with Auto's goals. Its card is `DriverCard`.
///
/// THE PRACTICE DUCK KEEPS M1'S PATH (`BallRunStart`, `BallRunWatch`), and its numbers stay valid
/// because that path did not change. A real duck has none of the bench's ground truth, so what is
/// here is the real duck's own: how its picture is cut (`Framing`), when a run ends (`Watch`) and
/// the sentences that say so without claiming anything nobody measured.
public enum BallWalk {
    public static let title = "Walk to the ball"
    public static let symbol = "soccerball"
    /// Where it runs and whose it is.
    public static let provenance = "Runs on this device. Not made by Pollen."
    /// What it runs from: a driver download, no key, on either duck.
    public static let subtitle = "Runs on this device, no key needed."

    public enum Words {
        /// The driver is a download, not part of the app.
        public static func getFirst(_ size: String) -> String { "Get it first, \(size), in Play, Tell." }
        /// Studio's Drivers row: training your own. The one that ships is in Play, Tell.
        public static let ownDriversLater = "Your own drivers come in a later build. Walk to the ball is in Play, Tell."
        /// Under the simulator numbers on a real duck, so they cannot be read as its own.
        public static let simulatorNumbersOnly =
            "Those numbers are the practice duck's. Nothing has been measured on a real duck."

        // The first run on a real duck.
        public static let confirmTitle = "Walk to the ball on your duck?"
        public static let confirmStart = "Start walking"
        public static func confirmLine(_ seconds: Double) -> String {
            String(format: "This driver learned only on the drawn practice stage and has never been tried on a "
                + "real floor, so it may wander or miss the ball. Keep your duck on the floor, away from edges "
                + "and stairs, and keep Stop ready. It stops by itself or after %.0f s, and it moves only the "
                + "way the sticks can.", seconds)
        }

        // Why it will not start.
        public static let sitting = "Your duck is sitting. Tap Stand Up, then try again."
        public static let homing = "Your duck is still getting to its feet. Try again in a moment."
        public static let noPicture =
            "Walk to the ball steers by your duck's camera, and no picture is coming in. It did not start."
        public static let cameraTooSlow = "Your duck's camera is not sending pictures fast enough to steer by. "
            + "The walk did not start."

        // Why it ended. NOTHING MEASURES THE BALL ON A REAL DUCK, so no line here may say it got there.
        public static let stoppedItself =
            "Your duck stopped by itself. Nothing measured the ball, so look to see where it got to."
        public static func timeLimit(_ seconds: Double) -> String {
            String(format: "Stopped at the %.0f s limit. Nothing measured the ball, so look to see where it got to.",
                   seconds)
        }
        public static let cameraLost =
            "Stopped, because your duck's pictures stopped coming. It never steers by an old picture."

        public static let all: [String] = [
            getFirst("4.4 MB"), ownDriversLater, simulatorNumbersOnly, confirmTitle, confirmStart,
            confirmLine(30), sitting, homing, noPicture, cameraTooSlow, stoppedItself, timeLimit(30), cameraLost,
        ]
    }

    /// Whether it can start now, on this duck, with this much on the device.
    public static func availability(on duck: DuckIdentity.Kind?, driverInstalled: Bool) -> AutoGoal.Availability {
        guard duck != nil else { return .unavailable(AutoGoal.Words.noDuck) }
        if !driverInstalled { return .unavailable(Words.getFirst(DriverRelease.walkToBall.size)) }
        return .ready
    }

    /// The line under its name in Moves.
    public static func line(on duck: DuckIdentity.Kind?, driverInstalled: Bool) -> String {
        availability(on: duck, driverInstalled: driverInstalled).reason ?? subtitle
    }

    /// Why a real duck cannot start this walk yet, in what the person should do, or nil.
    ///
    /// ONLY `sitting` AND `homed` ARE READ. `robot.policies` says nothing about whether the walking
    /// policy is driving (`Readiness.read(policies:)`), so a duck that gets past this is stood up
    /// the way a Tell walk is: `robot.init` and `robot.enable`, which are always safe. A field the
    /// duck did not send is no reason to refuse.
    public static func notReady(_ ready: DuckOrder.Readiness) -> String? {
        if ready.sitting == true { return Words.sitting }
        if ready.homed == false { return Words.homing }
        return nil
    }

    /// The first run on a real duck asks first, and a new driver asks again: `confirmed` is the
    /// folder of the last one the person said yes to.
    public static func needsConfirming(confirmed: String, release: DriverRelease = .walkToBall) -> Bool {
        confirmed != release.folder
    }

    /// Whether a typed or spoken Tell sentence asks for this walk.
    ///
    /// AS NARROW AS `DuckOrderMatcher`: after its fillers the words must be exactly one of these
    /// phrases. A stop word anywhere makes it not a walk, so "no, walk to the ball" stays a stop
    /// and "don't walk to the ball" is not read as an order to go.
    public static func heard(_ text: String) -> Bool {
        let all = StopWords.tokens(text)
        guard !all.contains(where: StopWords.words.contains), !all.contains("halt") else { return false }
        let words = all.filter { !DuckOrderMatcher.fillers.contains($0) }
        return phrases.contains(words)
    }

    /// "Go" and "the" are fillers: "go to the ball" reads as `to ball`, "go get the ball" as `get ball`.
    static let phrases: Set<[String]> = [["walk", "to", "ball"], ["to", "ball"], ["get", "ball"], ["find", "ball"]]

    /// The line after a run on a real duck. The pilot's last word is kept, unless the time limit
    /// ended it: then this says so, in words that claim nothing about the ball.
    public static func line(pilotSaid: String?, capped: Bool, capSeconds: Double, p50: Int?) -> String {
        let ran = capped || pilotSaid == DuckDream.Words.timeUp
        return [ran ? Words.timeLimit(capSeconds) : pilotSaid, p50.map(BallRunWatch.Words.answered)]
            .compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - when a real run ends

    /// Ends a run on a real duck, from what the pilot is about to do and how old the picture is.
    ///
    /// NO GROUND TRUTH, SO THE DRIVER ITSELF IS THE ONLY SIGNAL. It stands when it believes it is
    /// done (`DriverSnap.chunk` makes every row still from its first stand), so `standSeconds` of
    /// still rows in a row ends the run. That says the driver stopped asking to move, and nothing
    /// about where the ball is: a driver lost on a real floor can stand too.
    ///
    /// A PICTURE OLDER THAN `stalePicture` ENDS IT TOO, between asks as well as at them. The pilot
    /// plays 2 s of rows from each answer, so a check only at the ask could walk 2 s on a dead link.
    public struct Watch: Equatable, Sendable {
        /// About one chunk's horizon of rows.
        public static let standSeconds = 2.0
        public static let standRows = Int((standSeconds * DreamPilot.rowsPerSecond).rounded())
        /// Five pictures missed in a row at the driver's period. Wi-Fi hiccups are shorter.
        public static let stalePicture: TimeInterval = 1.0

        private var stillRows = 0

        public init() {}

        /// One look. `row` is the row about to play, or nil just before an ask; `pictureAge` is
        /// seconds since the newest picture, or nil when there is none. A sentence ends the run.
        public mutating func see(row: DuckDrive.Twist?, pictureAge: TimeInterval?) -> String? {
            guard let pictureAge, pictureAge <= Self.stalePicture else { return Words.cameraLost }
            guard let row else { return nil }
            stillRows = Self.isStill(row) ? stillRows + 1 : 0
            return stillRows >= Self.standRows ? Words.stoppedItself : nil
        }

        static func isStill(_ t: DuckDrive.Twist) -> Bool {
            abs(t.vx) < 1e-6 && abs(t.vy) < 1e-6 && abs(t.vyaw) < 1e-6
        }
    }

    /// One `Watch` as the closure `DreamPilot.run` takes. `pictureAge` is asked at every look.
    public static func pilotWatch(pictureAge: @escaping @Sendable () async -> TimeInterval?)
        -> @Sendable (DuckDrive.Twist?) async -> String? {
        let keeper = WatchKeeper()
        return { row in await keeper.see(row: row, pictureAge: await pictureAge()) }
    }

    private actor WatchKeeper {
        private var watch = Watch()
        func see(row: DuckDrive.Twist?, pictureAge: TimeInterval?) -> String? {
            watch.see(row: row, pictureAge: pictureAge)
        }
    }

    // MARK: - a real picture on the drawn stage's terms

    /// How `DreamPilot` sees a real camera: pictures at the driver's own rate, and no blind start.
    public enum Pictures {
        /// In the window before the first ask, as on the practice duck.
        public static let first = BallRunStart.picturesFirst
        /// `first` pictures must arrive within this. About 2.3 a second: the slowest camera that
        /// still keeps the driver's two pictures under a second apart.
        public static let within: TimeInterval = 3
    }

    /// Cuts a real duck's upright picture so the driver sees it at the angles it learned.
    ///
    /// THE TWO CAMERAS ARE NOT THE SAME SHAPE. The drawn head camera the driver learned on is
    /// landscape, 320 by 176, 45 degrees tall and about 74 wide (`SimHeadCamera`). An alpha duck's
    /// camera is an IMX219 mounted a quarter turn off, so `mediad`'s upright `/frame` is PORTRAIT,
    /// 720 by 1280: about 37 degrees wide and 62 tall, and its optical axis is well off centre
    /// (robotd-params' family solve). `DuckCameraFeed.dreamJPEG` squashes any picture to 320 by 176,
    /// which on this one makes a round ball about three times wider than it is tall.
    ///
    /// SO THE SCALE IS KEPT AND THE MISSING SIDES ARE FILLED. The picture is scaled so a degree
    /// covers the same pixels as on the drawn stage, centred on its real optical axis, and cropped
    /// at the top and bottom to 45 degrees. That keeps what the driver steers and stops by: where
    /// the ball sits left to right, how far up the picture it is, and how big it looks. The cost is
    /// width. The real view is about 144 of the 320 pixels, and the rest is `fill`, the driver's
    /// mean colour, which normalises to 0.
    ///
    /// A LANDSCAPE PICTURE IS FITTED WHOLE. That is a beta duck's upright GC2093, whose field of
    /// view nobody has published, so there is no angle to match; `mediad` publishes no geometry for
    /// it either.
    public struct Framing: Equatable, Sendable {
        public struct Box: Equatable, Sendable {
            public let x, y, width, height: Double
        }

        /// What to take from the picture, in its pixels, from its top left.
        public let source: Box
        /// Where to draw that in the 320 by 176 picture, from its BOTTOM left, as Core Graphics does.
        public let target: Box

        /// The alpha's family calibration on the 1280 by 720 frame as `mediad` sends it, unrotated
        /// (robotd-params `[media.intrinsics]`, 0.79 px RMS on real frames).
        static let sensorWidth = 720.0
        static let focal = (1061.806 + 1062.194) / 2
        static let sensorCx = 596.778, sensorCy = 474.523

        /// Pixels per radian-ish of the drawn camera at 320 by 176: `f = (h / 2) / tan(fovy / 2)`.
        static let drawnFocal = Double(DriverPrep.pictureHeight) / 2
            / tan(SimHeadCamera.fovyDegrees / 2 * .pi / 180)

        /// The real optical axis in the upright picture. `mediad` turns a quarter turn clockwise,
        /// which takes source (x, y) to upright (h - 1 - y, x).
        static let axisX = sensorWidth - 1 - sensorCy, axisY = sensorCx

        /// The cut for an upright picture this size.
        public static func real(width: Int, height: Int) -> Framing {
            let w = Double(width), h = Double(height)
            let (outW, outH) = (Double(DriverPrep.pictureWidth), Double(DriverPrep.pictureHeight))
            guard height > width else {
                return Framing(source: Box(x: 0, y: 0, width: w, height: h),
                               target: Box(x: 0, y: 0, width: outW, height: outH))
            }
            // Picture pixels to drawn pixels. Any other `mediad` quality is the same frame scaled.
            let unit = w / sensorWidth
            let scale = drawnFocal / (focal * unit)
            let (cx, cy) = (axisX * unit, axisY * unit)
            // The whole drawn view around the axis, kept to the picture that is really there.
            let left = max(cx - outW / 2 / scale, 0), right = min(cx + outW / 2 / scale, w)
            let top = max(cy - outH / 2 / scale, 0), bottom = min(cy + outH / 2 / scale, h)
            let toX = outW / 2 + (left - cx) * scale
            let toBottom = outH / 2 - (bottom - cy) * scale
            return Framing(source: Box(x: left, y: top, width: right - left, height: bottom - top),
                           target: Box(x: toX, y: toBottom, width: (right - left) * scale,
                                       height: (bottom - top) * scale))
        }
    }

    /// The colour around a real picture: the driver's own mean, 0 to 1, so those pixels normalise to 0.
    public static func fill(_ manifest: DriverManifest) -> (red: Double, green: Double, blue: Double) {
        (Double(manifest.imgMean[0]), Double(manifest.imgMean[1]), Double(manifest.imgMean[2]))
    }
}
