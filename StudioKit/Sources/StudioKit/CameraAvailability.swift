import Foundation

/// Whether this build, this device and this person's answer to the permission
/// prompt add up to a camera the Lab can actually open — and, when they do not,
/// the sentence that says so.
///
/// WHY THIS TYPE EXISTS. Build 27 shipped with nine files calling
/// `ARSession.run` against an Info.plist that had no `NSCameraUsageDescription`
/// in it. iOS terminates a process that touches a privacy-sensitive API with no
/// usage description, so every Lab mode killed the app the instant it was
/// opened. The key is in `DuckStudio/project.yml` now and that crash is fixed —
/// but a fix that is one line of a generated manifest is a fix somebody tidying
/// the manifest can delete, and NOTHING IN THE BINARY WOULD NOTICE. This is the
/// thing that notices. It also answers the two questions the plist never could:
/// whether the person said no to the prompt, and whether the device can do
/// world tracking at all.
///
/// IT IMPORTS NEITHER AVFoundation NOR ARKit, AND THAT IS THE POINT. Both are
/// iOS-only frameworks, and StudioKit exists so that every sentence a person
/// reads is asserted by `swift test` on Linux rather than eyeballed on a phone.
/// So the three facts arrive as parameters — the app target reads them in
/// `CameraDoor`, in `DuckLabStage.swift` — and this type does the deciding and
/// all of the talking.
///
/// THERE IS NO "ASK AGAIN" HERE AND NO SIDE EFFECT ANYWHERE IN IT. It is a
/// value: three facts in, a verdict and a sentence out.
public struct CameraAvailability: Equatable, Sendable {

    /// The person's standing answer, named case for case after AVFoundation's
    /// `AVAuthorizationStatus` so the app-side mapping is a one-to-one switch
    /// with nothing to get subtly backwards. (Verified: `AVAuthorizationStatus`
    /// is iOS 7.0 and its four cases are `notDetermined`, `restricted`,
    /// `denied`, `authorized`.)
    public enum Permission: String, Equatable, Sendable, CaseIterable {
        /// Nobody has been asked yet. THIS IS NOT A BLOCKER — see `blocker`.
        case notDetermined
        /// A configuration profile or Screen Time forbids it. The person cannot
        /// clear this from Settings themselves, which is why it says something
        /// different from `denied`.
        case restricted
        /// Asked, and the answer was no.
        case denied
        /// Asked, and the answer was yes.
        case authorized
    }

    /// The one thing standing in the way, when something is.
    ///
    /// It is deliberately not a set. A person reading a caption under a control
    /// wants the reason they can act on, not an audit; and the ordering in
    /// `blocker` is chosen so the one they get is the one that matters.
    public enum Blocker: String, Equatable, Sendable, CaseIterable {
        /// The build ships without `NSCameraUsageDescription`. Asking for the
        /// camera in this state does not fail — it ends the process.
        case noUsageDescription
        /// `ARWorldTrackingConfiguration.isSupported` is false.
        case deviceCannotWorldTrack
        /// `AVAuthorizationStatus.denied`.
        case permissionDenied
        /// `AVAuthorizationStatus.restricted`.
        case permissionRestricted
    }

    /// What is being asked for, because the same blocker costs three different
    /// things and a person deserves to be told which one they just lost.
    ///
    /// THE THREE ARE NOT INTERCHANGEABLE AND THAT IS THE WHOLE REASON THIS
    /// ENUM EXISTS. A game losing "Your floor" loses a backdrop it did not
    /// start in anyway. Follow me and Room capture lose everything, for two
    /// different reasons.
    public enum Dependent: String, Equatable, Sendable, CaseIterable {
        /// A mode with a rendered venue to fall back to: the five stage games
        /// and soccer's stadium.
        case venue
        /// Follow me, which has no stage and cannot be given one.
        case followMe
        /// Room capture, which has no stage and nothing to measure without a
        /// camera.
        case roomCapture

        /// The headline over a full-screen refusal.
        ///
        /// Total over the enum on purpose: a fourth dependent must be given a
        /// title before it compiles. `.venue`'s is not drawn by any screen
        /// today — a blocked venue shows its refusal as a caption under the
        /// venue picker, whose own label is already the headline — and it is
        /// written out rather than left as an empty string so that the day one
        /// is needed, nobody invents one at a call site.
        public var title: String {
            switch self {
            case .venue: return "\"Your floor\" cannot start"
            case .followMe: return "Follow me cannot start"
            case .roomCapture: return "Room capture cannot start"
            }
        }
    }

    /// Is `NSCameraUsageDescription` present in the running bundle, and not
    /// empty? An empty string is as fatal as a missing key, so the app target
    /// checks for text rather than for presence.
    public let usageDescriptionIsDeclared: Bool
    public let permission: Permission
    /// `ARWorldTrackingConfiguration.isSupported`, read on the app side.
    public let deviceSupportsWorldTracking: Bool

    public init(usageDescriptionIsDeclared: Bool,
                permission: Permission,
                deviceSupportsWorldTracking: Bool) {
        self.usageDescriptionIsDeclared = usageDescriptionIsDeclared
        self.permission = permission
        self.deviceSupportsWorldTracking = deviceSupportsWorldTracking
    }

    /// What is in the way, or nil if nothing is.
    ///
    /// THE ORDER IS DELIBERATE AND IT IS NOT SEVERITY. It is "would telling
    /// them this get them anywhere".
    ///
    /// The missing usage description comes first because it is the only one
    /// where *offering* the control is itself the harm: the control would be
    /// tapped, the prompt would be raised, and iOS would end the app before
    /// anything on screen could explain what happened. It also outranks the
    /// other two because it is a fault in the build rather than a fact about
    /// the phone or a choice the person made, and a person should not be sent
    /// to Settings to fix our mistake.
    ///
    /// The device check comes before the permission check because there is no
    /// point walking somebody to Settings > Microduck Studio > Camera on a phone
    /// that still cannot do world tracking when they come back. That would be
    /// a true sentence used to make a false promise.
    ///
    /// `.notDetermined` IS NOT A BLOCKER, and treating it as one would be the
    /// bug this whole file is against: nobody has been asked yet, ARKit's own
    /// prompt is what asks, and refusing before asking means the answer can
    /// never become yes.
    public var blocker: Blocker? {
        if !usageDescriptionIsDeclared { return .noUsageDescription }
        if !deviceSupportsWorldTracking { return .deviceCannotWorldTrack }
        switch permission {
        case .denied: return .permissionDenied
        case .restricted: return .permissionRestricted
        case .notDetermined, .authorized: return nil
        }
    }

    /// True when an AR control may be enabled. Exactly `blocker == nil`.
    public var canOfferAR: Bool { blocker == nil }

    /// The sentence to put beside the control that just went dark, or nil when
    /// the control can be enabled.
    ///
    /// nil EXACTLY WHEN `canOfferAR`, and a test asserts that over all sixteen
    /// states crossed with all three dependents. A screen that draws this and
    /// finds nil has a control it may enable; a screen that finds a string has
    /// a control it must disable AND a sentence it must show. Returning an
    /// empty string in either direction would give it a disabled control with
    /// nothing next to it, which is the silent failure this app is built
    /// against.
    ///
    /// Three clauses: what is wrong, what it costs, and what the person can do
    /// about it — in that order, and the third is absent when there is nothing
    /// they can do, because inventing a remedy is worse than admitting there
    /// is none.
    public func refusal(for dependent: Dependent) -> String? {
        guard let blocker else { return nil }
        let parts = [Self.cause(blocker), Self.consequence(dependent), Self.remedy(blocker)]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - the clauses

    /// What is wrong. NOTE WHAT NONE OF THESE SAY: none of them claims the
    /// camera was tried and failed. Nothing here opens a camera; these are
    /// three facts read off the bundle, the device and the permission store,
    /// and the sentences are written to describe exactly that and no more.
    private static func cause(_ blocker: Blocker) -> String {
        switch blocker {
        case .noUsageDescription:
            return "This build cannot open the camera: it ships without the camera usage description iOS requires, and iOS ends an app that asks for the camera without one."
        case .deviceCannotWorldTrack:
            return "This device cannot do world tracking, so nothing here can find the floor you are standing on."
        case .permissionDenied:
            return "Camera access is switched off for Microduck Studio."
        case .permissionRestricted:
            return "Camera access is restricted on this device — by a configuration profile or by Screen Time, not by anything Microduck Studio can change."
        }
    }

    /// What it costs.
    ///
    /// THE `followMe` CLAUSE IS THE ONE THAT MATTERS AND IT IS ARGUED, NOT
    /// ASSERTED. Every other AR mode in the Lab is a duck drawn on your carpet
    /// instead of on a rendered floor, and loses a backdrop when the camera
    /// goes. Follow me loses the measurement itself: the thing it follows is
    /// the phone, and ARKit's camera pose is a real reading of where a person
    /// is standing in a room. A stage version would have to feed the steering
    /// law a position off a joystick, which is the app inventing the very
    /// number the mode exists to measure. `DuckLabStage.swift`'s own header
    /// says the same thing about why that mode has no stage; this is that
    /// argument said to the person who just found the door shut.
    private static func consequence(_ dependent: Dependent) -> String {
        switch dependent {
        case .venue:
            return "\"Your floor\" is off, so this mode plays in its own rendered world instead — which is where it starts anyway."
        case .followMe:
            return "Follow me is off entirely, and it is the one mode with no stage to fall back to: what it follows is your phone, and the camera's own reckoning of where the phone has moved to IS the measurement. A stage would have to replace you with a joystick, which is pretend where this is perception."
        case .roomCapture:
            return "Room capture is off entirely. It has no stage either, and nothing to measure without a camera — what it writes out is the floor and the furniture ARKit found in the room you are standing in."
        }
    }

    /// What the person can do, when there is anything.
    ///
    /// TWO OF THE FOUR RETURN NIL AND THAT IS NOT AN OVERSIGHT. A phone that
    /// cannot do world tracking will not learn to, and a restriction set by a
    /// profile or by Screen Time is not clearable from Microduck Studio's own
    /// Settings page. Offering a step that does not work is how a refusal turns
    /// into a runaround.
    private static func remedy(_ blocker: Blocker) -> String? {
        switch blocker {
        case .noUsageDescription:
            return "That is a bug in this build, not something you did."
        case .permissionDenied:
            return "You can switch it back on in Settings, under Microduck Studio."
        case .deviceCannotWorldTrack, .permissionRestricted:
            return nil
        }
    }
}
