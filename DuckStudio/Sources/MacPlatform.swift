#if os(macOS)
import AppKit
import SwiftUI

/// The UIKit names this app is written against, answered by AppKit on a Mac.
///
/// WHY A LAYER AND NOT A SECOND COPY OF EVERY SCREEN. The app was written for
/// the phone, and around a hundred files say `UIColor`, `UIViewRepresentable`
/// or `.navigationBarTitleDisplayMode`. Fencing each of those would put a
/// macOS branch inside screens whose iOS behaviour is the product, and every
/// branch is a place for the two to drift. Instead the iOS source is left
/// exactly as it was and this file — compiled ONLY into the macOS slice —
/// gives those names a Mac meaning. Where AppKit has no equivalent the answer
/// is a deliberate no-op, and each one says what it is standing in for.
///
/// WHAT DOES NOT BELONG HERE. Anything that would change what a person is
/// told. A sentence that says "this phone" on a Mac is a StudioKit fix, not a
/// shim.

// MARK: - colours, fonts, views

typealias UIColor = NSColor
typealias UIFont = NSFont
typealias UIView = NSView
typealias UIGestureRecognizer = NSGestureRecognizer
typealias UIPanGestureRecognizer = NSPanGestureRecognizer

/// `UIUserInterfaceStyle`, for the adaptive-colour closure in `Theme`.
enum UIUserInterfaceStyle { case unspecified, light, dark }

/// The one trait `Theme.adaptive` reads.
struct MacTraits {
    let userInterfaceStyle: UIUserInterfaceStyle
}

extension NSColor {
    /// `UIColor { traits in … }` — a colour that answers per appearance.
    ///
    /// AppKit resolves a named dynamic colour against the drawing appearance,
    /// which is what UIKit's trait collection is to a phone: Dark Mode in
    /// System Settings, or `preferredColorScheme` on the window.
    convenience init(_ provider: @escaping (MacTraits) -> NSColor) {
        self.init(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return provider(MacTraits(userInterfaceStyle: dark ? .dark : .light))
        }
    }
}

extension Color {
    init(uiColor: NSColor) { self.init(nsColor: uiColor) }
}

extension NSFont {
    /// `UIFont.preferredFont(forTextStyle:)`. macOS has text styles too; it
    /// has no Dynamic Type slider, so this is the system's fixed size for the
    /// style.
    static func preferredFont(forTextStyle style: NSFont.TextStyle) -> NSFont {
        NSFont.preferredFont(forTextStyle: style, options: [:])
    }
}

// MARK: - gestures

/// A tap is a click. Same target/action shape; the count is spelled
/// differently.
final class UITapGestureRecognizer: NSClickGestureRecognizer {
    var numberOfTapsRequired: Int {
        get { numberOfClicksRequired }
        set { numberOfClicksRequired = newValue }
    }
}

/// A pinch is a trackpad magnify. UIKit's `scale` starts at 1 and multiplies;
/// AppKit's `magnification` starts at 0 and adds, so `scale` is `1 + it`,
/// and resetting `scale = 1` resets the gesture's baseline exactly as it does
/// on a phone.
final class UIPinchGestureRecognizer: NSMagnificationGestureRecognizer {
    var scale: CGFloat {
        get { 1 + magnification }
        set { magnification = newValue - 1 }
    }
}

// MARK: - representables

/// `UIViewRepresentable`, satisfied by AppKit's own representable.
///
/// A REFINEMENT, NOT A REIMPLEMENTATION. A screen that conforms writes
/// `makeUIView` / `updateUIView` as it does on iOS; the defaults below forward
/// AppKit's calls to them, so SwiftUI drives the NSView's lifecycle with the
/// same code that drives the UIView's on a phone.
@MainActor
protocol UIViewRepresentable: NSViewRepresentable where NSViewType == UIViewType {
    associatedtype UIViewType: NSView
    // RESTATED WITH ITS DEFAULT. Through a refining protocol Swift will not
    // infer `Coordinator` from `makeCoordinator()` or fall back to SwiftUI's
    // `Void`, and every container without a nested type of that exact name
    // failed to conform until it was said again here.
    associatedtype Coordinator = Void
    @MainActor func makeUIView(context: Context) -> UIViewType
    @MainActor func updateUIView(_ uiView: UIViewType, context: Context)
    @MainActor static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)
}

@MainActor
extension UIViewRepresentable {
    func makeNSView(context: Context) -> UIViewType { makeUIView(context: context) }
    func updateNSView(_ nsView: UIViewType, context: Context) {
        updateUIView(nsView, context: context)
    }
    static func dismantleNSView(_ nsView: UIViewType, coordinator: Coordinator) {
        dismantleUIView(nsView, coordinator: coordinator)
    }
    static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}
}

// MARK: - haptics

/// The taptic engine's three generators, played on a Force Touch trackpad.
///
/// A Mac has one haptic and it is subtle. These keep `Haptic`'s events firing
/// — a finished download still deserves a tap on a trackpad — and on a Mac
/// with no Force Touch trackpad they do nothing, which is the honest answer.
final class UIImpactFeedbackGenerator {
    enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    init(style: FeedbackStyle = .medium) {}
    func prepare() {}
    func impactOccurred() { Self.tap(.generic) }
    func impactOccurred(intensity: CGFloat) { Self.tap(.generic) }
    fileprivate static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

final class UINotificationFeedbackGenerator {
    enum FeedbackType { case success, warning, error }
    init() {}
    func prepare() {}
    func notificationOccurred(_ kind: FeedbackType) {
        UIImpactFeedbackGenerator.tap(kind == .success ? .levelChange : .generic)
    }
}

final class UISelectionFeedbackGenerator {
    init() {}
    func prepare() {}
    func selectionChanged() { UIImpactFeedbackGenerator.tap(.alignment) }
}

// MARK: - the device

/// `UIDevice.current`, for the two things this app asks of it.
final class UIDevice {
    enum Idiom { case phone, pad, mac }
    static let current = UIDevice()
    let userInterfaceIdiom = Idiom.mac
    var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// `UIScreen.main.bounds`: the main display, in points.
final class UIScreen {
    static let main = UIScreen()
    var bounds: CGRect { NSScreen.main?.frame ?? .zero }
}

/// `os_proc_available_memory()`, which macOS does not have.
///
/// A PHONE HAS A PER-APP BUDGET; A MAC HAS THE MACHINE. iOS kills an app
/// that passes its jetsam limit, and that limit is what the iOS call answers.
/// A Mac pages instead of killing, so the useful ceiling for "will this model
/// load without the machine grinding" is the unified memory less what macOS
/// and everything else on it need. Half is the conservative reading of that.
func os_proc_available_memory() -> Int {
    Int(ProcessInfo.processInfo.physicalMemory / 2)
}

/// `UIPasteboard.general.string`, on the Mac's general pasteboard.
final class UIPasteboard {
    static let general = UIPasteboard()
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }
}

// MARK: - SwiftUI modifiers a Mac does not have

/// `NavigationBarItem.TitleDisplayMode`. A Mac window has no large titles; the
/// title goes in the title bar whatever is asked for.
enum MacTitleDisplayMode { case automatic, inline, large }

/// `TextInputAutocapitalization`. macOS text fields do not auto-capitalise, so
/// every value is already what it asks for.
struct TextInputAutocapitalization {
    static let never = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
}

/// `UIKeyboardType`. A Mac has one keyboard, and it has every key.
enum UIKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad
    case namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: MacTitleDisplayMode) -> some View { self }
    func textInputAutocapitalization(_ value: TextInputAutocapitalization?) -> some View { self }
    func keyboardType(_ type: UIKeyboardType) -> some View { self }

    /// A full-screen cover is a sheet in a window. The phone's reason for
    /// covering everything — a small screen — is not the Mac's situation.
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>,
                                        onDismiss: (() -> Void)? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }

    func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss, content: content)
    }
}

extension ToolbarItemPlacement {
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var navigationBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var navigationBarLeading: ToolbarItemPlacement { .navigation }
    static var bottomBar: ToolbarItemPlacement { .automatic }
}

extension ListStyle where Self == InsetListStyle {
    /// The phone's grouped list. On a Mac the inset list is the nearest thing,
    /// and `Section` headers still group it.
    static var insetGrouped: InsetListStyle { InsetListStyle() }
}
#endif
