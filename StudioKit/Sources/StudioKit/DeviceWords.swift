/// What this app calls the machine it is running on.
///
/// ONE APP, TWO KINDS OF MACHINE, SINCE 2026-09-30. The same target builds a
/// native macOS slice, and a sentence that says "this phone" on a Mac is
/// wrong in the one way a person notices straight away. The words live here so
/// every sentence in the kit says the same thing about the same machine.
///
/// DECIDED AT COMPILE TIME, NOT ASKED AT RUN TIME. StudioKit is compiled into
/// the macOS slice for macOS and into the iOS slice for iOS, so `#if os` is
/// already the right answer and needs no state: no global to set at launch, no
/// window in which a sentence is built before somebody set it. Linux — where
/// the tests run — reads as the phone, so every existing sentence test keeps
/// testing the wording that ships to phones. The Mac wording is tested by
/// passing `.mac` to the functions that take a `device:`.
///
/// iPhone OR iPad IS NOT DECIDED HERE. The kit cannot ask (no UIKit), and the
/// one place that names the model of phone — `PhoneBenchReport.name(onPad:)` —
/// is already told by the app.
public enum DeviceWords: Sendable, Equatable {
    case phone
    case mac

    /// The machine this build of the kit is running on.
    public static let current: DeviceWords = {
#if os(macOS)
        return .mac
#else
        return .phone
#endif
    }()

    /// "this phone" / "this Mac" — mid-sentence.
    public var this: String { self == .mac ? "this Mac" : "this phone" }
    /// "This phone" / "This Mac" — to start a sentence.
    public var This: String { self == .mac ? "This Mac" : "This phone" }
    /// "the phone" / "the Mac".
    public var the: String { self == .mac ? "the Mac" : "the phone" }
    /// "a phone" / "a Mac".
    public var a: String { self == .mac ? "a Mac" : "a phone" }
    /// "iOS" / "macOS" — for a rule the operating system enforces on both,
    /// such as App Transport Security or Local Network permission.
    public var system: String { self == .mac ? "macOS" : "iOS" }
}
