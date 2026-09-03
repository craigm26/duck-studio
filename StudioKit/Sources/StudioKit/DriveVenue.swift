import Foundation

/// Where the thing you are driving actually is: physics on a bench, physics
/// drawn on your own floor, or a robot.
///
/// THREE VENUES, AND ONLY TWO OF THEM EXIST. Sim and "Your floor" are the same
/// drive — the same `/intent` calls to the same bench — with the duck drawn
/// against a rendered floor or against a camera feed. Robot is not a third way
/// of doing the same thing; it is a link this app does not have, and this file
/// exists so that saying so is a tested sentence rather than a disabled button.
///
/// IT MIRRORS `LabVenue` RATHER THAN REUSING IT. The Lab's two cases are
/// `stage` and `ar`, and its whole argument is that most of its games are
/// BETTER without AR because they need floor space nobody's living room has.
/// Driving is the opposite case: it is one duck in one spot, so a carpet is
/// exactly the right size for it — and driving has a third venue the Lab will
/// never have. Sharing the enum would mean one type with a case that is
/// meaningless in half its uses, which is the shape that produces a picker
/// entry nobody can explain.
public enum DriveVenue: String, CaseIterable, Identifiable, Sendable {

    /// A rendered floor. No camera, no room needed, works on a train.
    case sim
    /// The same bench, drawn on the floor you are standing on.
    case ar
    /// A Microduck. Not offered as a drive — see `robotIsNotDrivenYet`.
    case real

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sim: return "Sim"
        case .ar: return "Your floor"
        case .real: return "Robot"
        }
    }

    /// The line under the switch, saying what this venue is.
    public var oneLine: String {
        switch self {
        case .sim:
            return "MuJoCo on your bench, drawn on a rendered floor. Nothing here needs a camera."
        case .ar:
            return "The same bench, drawn on your own floor through the camera. The physics does "
                 + "not move house: the duck is still walking in the bench's world, not in your "
                 + "room."
        case .real:
            return "A Microduck. This app can find one over Bluetooth and ask it what it is, and "
                 + "it cannot drive one."
        }
    }

    /// The explicit not-yet for a venue that cannot be entered at all, or nil
    /// when the venue works.
    ///
    /// AR IS NOT IN HERE, AND THAT IS DELIBERATE. Whether the camera can open
    /// is a question about the build, the device and the person's answer to a
    /// prompt, and `CameraAvailability.refusal(for: .venue)` is the one place
    /// that decides it. A second copy of that reasoning here would be a second
    /// answer to the same question.
    public var notYet: String? {
        switch self {
        case .sim, .ar: return nil
        case .real: return DriveVenue.robotIsNotDrivenYet
        }
    }

    /// Whether this venue may be picked at all.
    ///
    /// `.real` IS TRUE. The screen is worth opening — it is where somebody
    /// finds and pairs a duck and reads what this app knows about it — and what
    /// it must not draw is a stick.
    public func canBeEntered(camera: CameraAvailability) -> Bool {
        self == .ar ? camera.canOfferAR : true
    }

    /// Which venue a screen should actually be in, given what the camera says.
    ///
    /// THE COERCION IS THE KIT'S BECAUSE IT IS A DECISION. A view that wrote
    /// `if !door.canOfferAR { venue = .sim }` inline would be a rule nothing
    /// asserts, and the rule has a real edge: a person can be standing in AR
    /// when they walk to Settings and switch the camera off, and coming back
    /// must land them somewhere that draws.
    public static func coerce(_ venue: DriveVenue, camera: CameraAvailability) -> DriveVenue {
        venue.canBeEntered(camera: camera) ? venue : .sim
    }

    // MARK: - what is real on your floor, and what is not

    /// The two real measurements in the AR venue.
    /// The gesture instructions and the two states after them, in the kit
    /// like every other sentence on the screen: the same words the lab's AR
    /// venues use, in one place, tested once.
    public static let pointAtTheFloor = "Point the camera at the floor and tap to put the duck down."
    public static let noFloorThere = "No floor there yet — move the phone and tap again."
    public static let placedSaid = "Placed. Tap the floor again to move it."
    /// The panel's one-line head; the paragraphs sit behind a disclosure so
    /// the camera feed and the placing tap stay reachable.
    public static let arWhatIsRealTitle = "What is real here"

    public static let arIsReal =
        "Real here: where your phone is, and where your floor is. Both are ARKit's own "
      + "measurements of the room you are standing in — the camera pose that keeps the duck "
      + "stuck to one spot as you walk around it, and the horizontal plane you tapped to put it "
      + "there."

    /// Everything else, said before somebody has to work it out.
    ///
    /// THE SOFA IS THE POINT. A duck drawn on your carpet reads as a duck in
    /// your room, and it is not: the physics is a metre-and-a-half box on
    /// another machine, and nothing in it knows your furniture is there. It
    /// walks through the sofa because the sofa is not in the world it is
    /// walking in.
    public static let arIsNot =
        "Not real here: the duck, the steps, the ball and the walls. All four are the bench's "
      + "world drawn over your camera. The physics is happening in a 2.9 m box on the bench, "
      + "which knows nothing about your room — so the duck will walk through your sofa, and the "
      + "square on the floor is the edge of the world it is actually in, not of yours."

    /// Why there is no zoom on your floor, said where the person looks for one.
    ///
    /// THE CAMERA IN YOUR HAND IS THE CAMERA. There is one recogniser in the AR
    /// stage and it places the duck; a zoom button would either do nothing or
    /// would scale a duck that `arIsNot` promises is drawn at the size it really
    /// is — and that promise has a test on it. So this is a not-yet beside a
    /// control that still does something: the two moves that DO change what you
    /// see are named.
    ///
    /// IT CARRIES THE SAME 2.9 m FIGURE `arIsNot` STATES, and a test asserts
    /// both, so the two sentences about the same box cannot drift apart.
    public static let arHasNoZoom =
        "There is no zoom on your floor. The duck, the steps and the square are drawn at the "
      + "size they really are — a 250 mm robot in a 2.9 m world — so the way to see it closer "
      + "is to walk closer, or to tap the floor nearer to you to put it down again."

    /// The one thing nobody here has measured, said where it will be noticed.
    ///
    /// TWO ENGINES ON ONE PHONE IS AN UNMEASURED ARRANGEMENT. The phone bench
    /// runs MuJoCo in a WKWebView on a loopback port; AR runs ARKit's world
    /// tracking on the same device at the same time. Nobody in this project has
    /// run both together and timed it. That is not a reason to refuse — a
    /// refusal would be inventing the answer in the pessimistic direction — it
    /// is a reason to say so and to put the tick cost and the round trip on
    /// screen where a person can watch it themselves.
    ///
    /// Nil when the bench is a machine on the network, which is the arrangement
    /// that has been measured.
    public static func twoEnginesOnOnePhone(benchIsThisPhone: Bool) -> String? {
        guard benchIsThisPhone else { return nil }
        return "This phone is running both the physics and the camera. Nobody has measured that "
             + "arrangement: MuJoCo in a WebView and ARKit's world tracking have not been run "
             + "together and timed here. It is not refused — the tick cost and the round trip "
             + "are on screen, so you can watch what it costs rather than take a guess for an "
             + "answer. Point the app at a bench on your network to take one of the two off "
             + "this device."
    }

    // MARK: - the robot, and why there is no stick

    /// The headline where a Drive control would be.
    ///
    /// IT NAMES THE TRANSPORT, WHICH IS THE WHOLE DIFFERENCE between "not yet"
    /// and "broken". `DuckMethod.reach(for: .ble)` denies `move`, `stop` and
    /// `state` on Bluetooth, and that denial is Pollen's own: BLE is
    /// provisioning, status and the update trigger, and "payloads never
    /// traverse it". A stick drawn over that link would produce calls a duck
    /// refuses by name, and a refusal by name looks exactly like a feature the
    /// duck does not have.
    public static let robotIsNotDrivenYet =
        "No stick here yet, and the reason is the link. The only transport this app has working "
      + "code for is Bluetooth, and Bluetooth does not carry driving: Pollen's own split puts "
      + "provisioning, status and firmware updates on BLE and says payloads never traverse it, "
      + "so move, stop and a state read are all denied on it. What you can do from here is find "
      + "a duck, pair with it, and ask it what it is."

    /// What this app already holds toward driving a real one, named so the gap
    /// is a job rather than a mood.
    public static let whatTheKitHasTowardIt =
        "What is already written: the vocabulary and the routing. DuckPeer carries the five "
      + "things a link has to say about itself and the table of which methods each transport "
      + "carries — Bluetooth, WebRTC, the bench, and a bridge — with no wildcard in it, so a new "
      + "method has to be routed rather than silently denied. DuckLineTransport, LinePeer and "
      + "DuckLineSequence are the JSON-RPC line framing and the loss counting. DuckWebRTC holds "
      + "the shape of a signalling client, and nothing conforms to it — a test fails if anything "
      + "does — because a client written against a guessed contract is worse than none."

    /// The other route to a robot, and the four things it would need.
    ///
    /// THE PI BENCH IS ALREADY HALF OF THE TRANSPORT AND THAT IS WHY THIS IS
    /// TEMPTING. `/health` on the bench advertises `GET /state`, `POST /intent`,
    /// `/stop`, `GET /now`, `POST /policy`, `/ball` and `/reset` — the same
    /// verbs `robotd` takes over its Unix socket. A Pi sitting between the two
    /// would be a small program. It does not exist, so this says what it would
    /// take instead of offering a button that would need it.
    // MARK: - the console the robot serves, which is WebRTC without writing one

    /// WHAT WEBRTC WOULD AND WOULD NOT BUY, now that the contract is readable
    /// rather than guessed at. `pollen-robotics/microduck` is public;
    /// `duck-ipc-proto` is a crate in it and `docs/design/remote-webrtc.md`
    /// documents the transport: `mediad` runs a signalling server in its own
    /// process on port 8443, one peer connection carries video, audio, a
    /// reliable `control` channel and an unreliable `teleop` one, and `control`
    /// carries THE SAME JSON-RPC the Unix socket carries, one object per line.
    ///
    /// SO WEBRTC BUYS VIDEO, NOT CONTROL. Every driving call on that channel is
    /// a call the bridge in this repo already relays over TCP, which means a
    /// WebRTC client written here would ship a hundred megabytes of libwebrtc
    /// to reach a surface this app can already reach. What it would add is the
    /// camera, and reaching a robot that is not on this network.
    ///
    /// AND THE ROBOT ALREADY SHIPS A CLIENT FOR THAT. `mediad` serves its own
    /// console over HTTP on port 8080 — `mediad/src/web.rs`, the page embedded
    /// in the binary so the page and the daemon cannot disagree about their
    /// versions. It negotiates the session, shows the video and opens the
    /// control channel. Sending somebody to it is a door; writing a second
    /// client would be a second implementation of a protocol whose own
    /// documentation says the pipe should stay dumb.
    /// The heading over the door.
    public static let consoleHeading = "The robot's own console"

    public static let consoleIsTheRobotsOwn =
        "Your robot serves its own console: a page with the camera on it and the same control "
      + "channel this app speaks. It runs on the robot rather than here, so it is the robot's "
      + "version of that page and not this app's idea of it."

    /// What the console is, in a sentence that does not overclaim what this app
    /// did to produce it.
    public static let consoleIsNotThisApp =
        "This app is not driving that page. It opens it, and everything on it — the video, the "
      + "session, the buttons — is the robot's own software answering for itself."

    /// Where it is, when there is an address to say it about.
    public static func consoleAt(_ host: String) -> String {
        "http://\(host):8080"
    }

    /// The one thing a person should know before they open a page that can
    /// drive a robot, and it is the robot's own decision rather than ours.
    public static let consoleHasNoGate =
        "Anybody on your network who opens that page can drive the robot: the first version of "
      + "the robot's WebRTC transport has no gate on it, by its own design note. That is a "
      + "property of your network, not of this app."

        public static let whatABridgeWouldTake =
        "There is a shorter route than WebRTC and it has not been built either. The bench "
      + "already speaks half of the robot's own vocabulary over HTTP — state, intent, stop, "
      + "policy, reset — and robotd takes those same verbs as JSON-RPC on a Unix socket at "
      + "/run/robotd.sock, which has no network endpoint for a phone to open. A bridge would be "
      + "a process on a Pi translating one to the other. It would need four things: that Pi on "
      + "the robot's own network; something that authorises the relay, which is the question "
      + "nobody here has answered; a deadman, because a robot that keeps walking when the link "
      + "drops is the failure the simulator gives us for free and hardware does not; and one "
      + "person willing to be in the room the first time."
}
