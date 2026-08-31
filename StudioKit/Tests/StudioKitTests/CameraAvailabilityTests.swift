import XCTest
@testable import StudioKit

/// The camera door, asserted letter by letter.
///
/// This is the file that stands in for a runtime that does not exist on Linux.
/// Nothing here can open a camera, and nothing here needs to: the type takes
/// three facts and answers, so every branch of the answer is reachable from a
/// test — including the two that are almost impossible to reach on a phone you
/// own, a restricted device and a build with the usage description stripped
/// back out.
final class CameraAvailabilityTests: XCTestCase {

    // The clauses, written once here so an edit to the source that changes a
    // word fails on the pair it changed rather than on all twelve at once.
    private let missingKey = "This build cannot open the camera: it ships without the camera usage description iOS requires, and iOS ends an app that asks for the camera without one."
    private let noTracking = "This device cannot do world tracking, so nothing here can find the floor you are standing on."
    private let switchedOff = "Camera access is switched off for Duck Studio."
    private let restricted = "Camera access is restricted on this device — by a configuration profile or by Screen Time, not by anything Duck Studio can change."

    private let venue = "\"Your floor\" is off, so this mode plays in its own rendered world instead — which is where it starts anyway."
    private let followMe = "Follow me is off entirely, and it is the one mode with no stage to fall back to: what it follows is your phone, and the camera's own reckoning of where the phone has moved to IS the measurement. A stage would have to replace you with a joystick, which is pretend where this is perception."
    private let roomCapture = "Room capture is off entirely. It has no stage either, and nothing to measure without a camera — what it writes out is the floor and the furniture ARKit found in the room you are standing in."

    private let itIsABug = "That is a bug in this build, not something you did."
    private let goToSettings = "You can switch it back on in Settings, under Duck Studio."

    /// Everything present and the person has said yes.
    private func working(_ permission: CameraAvailability.Permission = .authorized) -> CameraAvailability {
        CameraAvailability(usageDescriptionIsDeclared: true,
                           permission: permission,
                           deviceSupportsWorldTracking: true)
    }

    // MARK: - when the door is open

    func testACapableDeviceWithPermissionGrantedCanBeOfferedAR() {
        let door = working()
        XCTAssertNil(door.blocker)
        XCTAssertTrue(door.canOfferAR)
        for dependent in CameraAvailability.Dependent.allCases {
            XCTAssertNil(door.refusal(for: dependent), dependent.rawValue)
        }
    }

    /// THE BRANCH THAT WOULD BREAK THE APP IF IT WENT THE OTHER WAY. Nobody has
    /// been asked yet on a fresh install, and a door that refused before asking
    /// would mean the answer could never become yes.
    func testNobodyHasBeenAskedYetAndThatIsNotARefusal() {
        let door = working(.notDetermined)
        XCTAssertNil(door.blocker)
        XCTAssertTrue(door.canOfferAR)
        XCTAssertNil(door.refusal(for: .followMe))
    }

    // MARK: - the missing usage description, which is a bug in the build

    func testAMissingUsageDescriptionTakesYourFloorAndSaysItIsOurFault() {
        let door = CameraAvailability(usageDescriptionIsDeclared: false,
                                      permission: .authorized,
                                      deviceSupportsWorldTracking: true)
        XCTAssertEqual(door.blocker, .noUsageDescription)
        XCTAssertEqual(door.refusal(for: .venue), missingKey + " " + venue + " " + itIsABug)
    }

    func testAMissingUsageDescriptionTakesFollowMeEntirely() {
        let door = CameraAvailability(usageDescriptionIsDeclared: false,
                                      permission: .authorized,
                                      deviceSupportsWorldTracking: true)
        XCTAssertEqual(door.refusal(for: .followMe), missingKey + " " + followMe + " " + itIsABug)
    }

    func testAMissingUsageDescriptionTakesRoomCaptureEntirely() {
        let door = CameraAvailability(usageDescriptionIsDeclared: false,
                                      permission: .authorized,
                                      deviceSupportsWorldTracking: true)
        XCTAssertEqual(door.refusal(for: .roomCapture), missingKey + " " + roomCapture + " " + itIsABug)
    }

    /// It outranks everything, because it is the only state where OFFERING the
    /// control is what kills the app, and because a person should not be sent
    /// to Settings to fix a mistake in the build they were handed.
    func testTheMissingUsageDescriptionOutranksTheDeviceAndThePermission() {
        let door = CameraAvailability(usageDescriptionIsDeclared: false,
                                      permission: .denied,
                                      deviceSupportsWorldTracking: false)
        XCTAssertEqual(door.blocker, .noUsageDescription)
        XCTAssertEqual(door.refusal(for: .venue), missingKey + " " + venue + " " + itIsABug)
    }

    // MARK: - a device that cannot do it

    func testADeviceThatCannotWorldTrackSaysSoAndOffersNoRemedy() {
        let door = CameraAvailability(usageDescriptionIsDeclared: true,
                                      permission: .authorized,
                                      deviceSupportsWorldTracking: false)
        XCTAssertEqual(door.blocker, .deviceCannotWorldTrack)
        XCTAssertEqual(door.refusal(for: .venue), noTracking + " " + venue)
        XCTAssertEqual(door.refusal(for: .followMe), noTracking + " " + followMe)
        XCTAssertEqual(door.refusal(for: .roomCapture), noTracking + " " + roomCapture)
    }

    /// Walking somebody to Settings on a phone that still cannot do it when
    /// they come back is a true sentence used to make a false promise.
    func testADeviceThatCannotWorldTrackOutranksADeniedPermission() {
        let door = CameraAvailability(usageDescriptionIsDeclared: true,
                                      permission: .denied,
                                      deviceSupportsWorldTracking: false)
        XCTAssertEqual(door.blocker, .deviceCannotWorldTrack)
        XCTAssertFalse(door.refusal(for: .venue)!.contains("Settings"))
    }

    // MARK: - the person said no, and the person was not asked

    func testADeniedCameraNamesSettingsBecauseThatOneActuallyWorks() {
        let door = working(.denied)
        XCTAssertEqual(door.blocker, .permissionDenied)
        XCTAssertEqual(door.refusal(for: .venue), switchedOff + " " + venue + " " + goToSettings)
        XCTAssertEqual(door.refusal(for: .followMe), switchedOff + " " + followMe + " " + goToSettings)
        XCTAssertEqual(door.refusal(for: .roomCapture), switchedOff + " " + roomCapture + " " + goToSettings)
    }

    /// A restriction is not a denial: the person cannot clear it from Duck
    /// Studio's own page in Settings, so they are not sent there.
    func testARestrictedCameraSaysWhoSetItAndDoesNotSendAnybodyToSettings() {
        let door = working(.restricted)
        XCTAssertEqual(door.blocker, .permissionRestricted)
        XCTAssertEqual(door.refusal(for: .venue), restricted + " " + venue)
        XCTAssertEqual(door.refusal(for: .followMe), restricted + " " + followMe)
        XCTAssertEqual(door.refusal(for: .roomCapture), restricted + " " + roomCapture)
        XCTAssertFalse(door.refusal(for: .venue)!.contains("Settings, under Duck Studio"))
    }

    // MARK: - the invariants, over every state there is

    /// Sixteen states crossed with three dependents. A control that cannot work
    /// is disabled WITH THE REASON BESIDE IT, so a nil where a string belongs
    /// is a control that goes dead in silence, and a string where a nil belongs
    /// is a working control refused for no reason.
    func testARefusalExistsExactlyWhenTheDoorIsShut() {
        for declared in [true, false] {
            for permission in CameraAvailability.Permission.allCases {
                for supported in [true, false] {
                    let door = CameraAvailability(usageDescriptionIsDeclared: declared,
                                                  permission: permission,
                                                  deviceSupportsWorldTracking: supported)
                    let label = "\(declared)/\(permission.rawValue)/\(supported)"
                    for dependent in CameraAvailability.Dependent.allCases {
                        let refusal = door.refusal(for: dependent)
                        if door.canOfferAR {
                            XCTAssertNil(refusal, "\(label) \(dependent.rawValue)")
                        } else {
                            XCTAssertNotNil(refusal, "\(label) \(dependent.rawValue)")
                            XCTAssertFalse(refusal!.isEmpty, "\(label) \(dependent.rawValue)")
                            XCTAssertTrue(refusal!.hasSuffix("."), "\(label) \(dependent.rawValue): \(refusal!)")
                        }
                    }
                }
            }
        }
    }

    /// The whole point of the Follow me carve-out: its refusal must never
    /// imply the mode has somewhere else to run, because it does not.
    func testTheFollowMeRefusalNeverImpliesAStageIsWaitingForIt() {
        for permission in CameraAvailability.Permission.allCases {
            for door in [CameraAvailability(usageDescriptionIsDeclared: false,
                                            permission: permission,
                                            deviceSupportsWorldTracking: true),
                         CameraAvailability(usageDescriptionIsDeclared: true,
                                            permission: permission,
                                            deviceSupportsWorldTracking: false),
                         CameraAvailability(usageDescriptionIsDeclared: true,
                                            permission: permission,
                                            deviceSupportsWorldTracking: true)] {
                guard let refusal = door.refusal(for: .followMe) else { continue }
                XCTAssertFalse(refusal.contains("its own rendered world"), refusal)
                XCTAssertTrue(refusal.contains("no stage to fall back to"), refusal)
            }
        }
    }

    /// It has to say what it is that it cannot do without — not "the camera",
    /// which is a permission, but the measurement the camera is standing in for.
    func testTheFollowMeRefusalNamesTheMeasurementItLoses() {
        let refusal = working(.denied).refusal(for: .followMe)!
        XCTAssertTrue(refusal.contains("what it follows is your phone"), refusal)
        XCTAssertTrue(refusal.contains("IS the measurement"), refusal)
        XCTAssertTrue(refusal.contains("pretend where this is perception"), refusal)
    }

    /// Only the one remedy that works is ever offered. `restricted` and an
    /// incapable device both mention no route out, because they have none.
    func testSettingsIsNamedOnlyWhereGoingToSettingsWouldHelp() {
        for declared in [true, false] {
            for permission in CameraAvailability.Permission.allCases {
                for supported in [true, false] {
                    let door = CameraAvailability(usageDescriptionIsDeclared: declared,
                                                  permission: permission,
                                                  deviceSupportsWorldTracking: supported)
                    guard let refusal = door.refusal(for: .venue) else { continue }
                    if refusal.contains("Settings") {
                        XCTAssertEqual(door.blocker, .permissionDenied, refusal)
                    }
                }
            }
        }
    }

    /// NO REFUSAL SAYS "TRY AGAIN". Nothing here retries anything, and three of
    /// the four states will answer exactly the same way for as long as the app
    /// is installed.
    func testNoRefusalTellsAnybodyToTryAgain() {
        let banned = ["try again", "please retry", "coming soon", "temporarily", "for now"]
        for declared in [true, false] {
            for permission in CameraAvailability.Permission.allCases {
                for supported in [true, false] {
                    let door = CameraAvailability(usageDescriptionIsDeclared: declared,
                                                  permission: permission,
                                                  deviceSupportsWorldTracking: supported)
                    for dependent in CameraAvailability.Dependent.allCases {
                        guard let refusal = door.refusal(for: dependent)?.lowercased() else { continue }
                        for phrase in banned {
                            XCTAssertFalse(refusal.contains(phrase), "\(phrase): \(refusal)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - the headlines

    func testEveryDependentHasAHeadlineAndNoneOfThemIsAShrug() {
        XCTAssertEqual(CameraAvailability.Dependent.venue.title, "\"Your floor\" cannot start")
        XCTAssertEqual(CameraAvailability.Dependent.followMe.title, "Follow me cannot start")
        XCTAssertEqual(CameraAvailability.Dependent.roomCapture.title, "Room capture cannot start")
        for dependent in CameraAvailability.Dependent.allCases {
            XCTAssertFalse(dependent.title.isEmpty, dependent.rawValue)
            // A headline that says "error" or "sorry" tells nobody what is off.
            XCTAssertFalse(dependent.title.lowercased().contains("error"), dependent.title)
            XCTAssertFalse(dependent.title.lowercased().contains("sorry"), dependent.title)
        }
    }
}
