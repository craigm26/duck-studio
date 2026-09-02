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
