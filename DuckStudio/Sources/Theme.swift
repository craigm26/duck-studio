import SwiftUI
import UIKit
import StudioKit

/// The app's colours, as SwiftUI sees them. Every value comes from `Palette`.
///
/// THIS FILE DECIDES NOTHING, WHICH IS THE POINT. It used to hold the palette:
/// twelve `Color(red:green:blue:)` literals, each a number that only a person
/// squinting at a phone could ever have checked. A contrast ratio is a fact
/// about two colours, and a fact that lives in a view is a fact nothing can
/// disagree with — there is no test on a `Color`, and the Mac build will never
/// tell you that the orange you set body text in is 2.30:1 against the cream
/// behind it. So the values moved to `StudioKit/Palette.swift`, where
/// `swift test` runs the WCAG formula over all of them on every build, and
/// what is left here is the mapping: token in, `Color` out.
///
/// ADAPTIVE VIA UIKit, NOT VIA TWO ASSET CATALOGUE ENTRIES. `Color` has no way
/// to be told "this value in light, that one in dark" in code; `UIColor`'s
/// dynamic provider does, and it resolves per trait collection at draw time,
/// so one `static let` is correct in both schemes, inside a sheet that
/// overrides the scheme, and in a snapshot. The alternative — a colour set per
/// token in Assets.xcassets — puts the numbers somewhere no test can reach
/// them, which is the problem this rewrite exists to solve.
///
/// THE PALETTE IS MICRODUCK'S AND THE APP IS NOT. Harmonising with a brand is
/// not wearing it: there is no Pollen logo here, no Pollen wordmark, and the
/// app says it is independent on its own store listing, its website and its
/// Policies tab. The line worth holding is that a person must never be able to
/// mistake this for something Pollen shipped — colour alone has never made
/// that claim, and nothing here goes further than colour.
enum Theme {

    // MARK: - the bridge

    /// A token as a `Color` that answers correctly in both schemes.
    private static func adaptive(_ token: Palette.Token) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Palette.color(token,
                                  in: traits.userInterfaceStyle == .dark ? .dark : .light))
        })
    }

    // MARK: - grounds and surfaces

    /// The page. Warm Cream in light, charcoal taken down in dark.
    static let backgroundPrimary = adaptive(.backgroundPrimary)
    /// The recessed ground under grouped content.
    ///
    /// PUT SURFACES ON THIS, AND ONLY THE TYPE RAMP DIRECTLY ON IT. The four
    /// ink variants land between 4.17:1 and 4.27:1 against it — short of the
    /// 4.5:1 body text owes — so an accent word goes on a `surfacePrimary` card
    /// and the card goes on this.
    ///
    /// IT IS STILL A GROUND WORDS LAND ON, WHICH THE PALETTE USED TO DENY. A
    /// `List` row here keeps its card, but a section's HEADER and FOOTER do
    /// not: they are drawn straight on the list's own background, and this
    /// token is that background in thirty-two places across twenty-seven
    /// files. Those headers and footers are set in the
    /// three-step type ramp, which clears it — 14.37:1, 6.24:1 and 4.59:1 — so
    /// the arrangement was right all along and only the claim was wrong.
    /// `Palette.Token.takesEveryTextToken` is now the narrower thing that is
    /// true of it, and `PaletteTests` names every pair that falls short with
    /// its measured ratio.
    static let backgroundSecondary = adaptive(.backgroundSecondary)
    /// A card.
    static let surfacePrimary = adaptive(.surfacePrimary)
    /// A sheet, or a card that has to lift off the one behind it. The app's
    /// only pure white, and only in light, because nothing dimmer separates
    /// from cream.
    static let surfaceElevated = adaptive(.surfaceElevated)
    /// The wash behind a selected row — pale teal, so selection reads as this
    /// app's brand rather than as the system blue.
    ///
    /// A WASH IS NOT A SIGNAL. It differs from its ground by 1.02:1 in light
    /// and 1.14:1 in dark, which is a hint and not information. Anything
    /// selected must also carry a mark, a label or a checkmark.
    static let surfaceInteractive = adaptive(.surfaceInteractive)

    // MARK: - type

    static let textPrimary = adaptive(.textPrimary)
    static let textSecondary = adaptive(.textSecondary)
    /// Captions and disclosure. Warm-biased rather than neutral grey, and
    /// darker in light mode than the brand sheet suggested — see `greyInk`.
    static let textTertiary = adaptive(.textTertiary)

    // MARK: - brand and action

    /// Microduck Teal in dark, teal ink in light.
    static let brandPrimary = adaptive(.brandPrimary)
    /// Duck Orange, in both schemes. The thing you press.
    ///
    /// THE ONE ACCENT THAT IS NEVER REPLACED BY ITS INK. Every other hue takes
    /// a darkened variant on cream so it can set a word; this one keeps its
    /// brand value because the button a person reaches for is where a brand
    /// actually lives. On cream it is 2.30:1, which is below even the 3:1 a
    /// control's boundary owes — so a filled orange shape on the light ground
    /// takes `actionPrimaryEdge` as a hairline rim, and the fill stays orange.
    static let actionPrimary = adaptive(.actionPrimary)
    /// The rim a Duck Orange fill needs so its EDGE is findable, or `nil` in
    /// dark, where orange is 7.12:1 on the ground and needs nothing.
    ///
    /// Not adaptive, because it is absent rather than different in dark:
    /// asking for it in the wrong scheme should give you nothing to draw, not
    /// a colour you then have to remember to skip.
    static func actionPrimaryEdge(_ scheme: ColorScheme) -> Color? {
        Palette.fillEdge(.actionPrimary, in: scheme == .dark ? .dark : .light)
            .map { Color(uiColor: UIColor($0)) }
    }
    /// The quieter action — orange ink in light, orange in dark. This is the
    /// one that sets words.
    static let actionSecondary = adaptive(.actionSecondary)

    // MARK: - robot state

    /// A robot that is moving.
    ///
    /// NEVER THE DOT ALONE. Every robot state has a word beside it. Somebody
    /// who cannot separate the orange dot from the teal one still has to be
    /// able to tell a driving duck from an idle one, and these colours are
    /// specified at text contrast rather than dot contrast precisely because
    /// they always end up on that word.
    static let robotActive = adaptive(.robotActive)
    /// Powered, and standing still.
    static let robotIdle = adaptive(.robotIdle)
    /// Not there.
    static let robotOffline = adaptive(.robotOffline)

    // MARK: - sensing, training, status

    /// The eye. Active sensors, discoveries, training progress — sparingly.
    static let sensorActive = adaptive(.sensorActive)
    /// Training. The least-used hue in the palette, on the least-frequent
    /// thing the app reports.
    static let training = adaptive(.training)
    static let success = adaptive(.success)
    static let warning = adaptive(.warning)
    static let critical = adaptive(.critical)

    // MARK: - furniture

    static let separator = adaptive(.separator)
    /// The focus ring, 3pt at a 2pt offset in both schemes.
    ///
    /// TEAL INK IN LIGHT, NOT BRAND TEAL. Microduck Teal is 1.74:1 on cream —
    /// a focus indicator that is not there. Of every contrast failure a design
    /// system can ship this is the worst, because it does not make the app
    /// harder for a keyboard, switch or Full Keyboard Access user; it removes
    /// their only way of knowing where they are. The ink is the same hue at
    /// 4.62:1, so the ring is still recognisably the brand.
    static let focus = adaptive(.focus)

    // MARK: - what each colour MEANS here

    /// A measured fact — something a bench or the kinematics produced.
    ///
    /// COLOUR AS A CLAIM ABOUT PROVENANCE, which is the one thing this app is
    /// consistently strict about. Teal is what a machine measured; yellow is
    /// what somebody asked for; the critical colour is a refusal. Using them
    /// the other way round would make the palette say the opposite of the
    /// words beside it.
    ///
    /// These are aliases onto tokens rather than colours of their own, so that
    /// a provenance claim is drawn in a value the contrast tests already cover.
    static let measured = brandPrimary
    /// Something authored — a request, not a result.
    static let asked = sensorActive
    /// A refusal, or a limit being approached.
    static let refused = critical

    /// The old raw-colour name for `asked`, kept because `DriveView`'s HUD
    /// still prints the last action in it. The meaning is what matters — this
    /// is "what somebody asked for" — and the name is the one thing about it
    /// that is left over from a palette of sampled hex values.
    static let amber = asked
    /// Duck Orange, under the name the brand sheet uses. `actionPrimary` is
    /// the token; this is the colour.
    static let orange = actionPrimary

    // MARK: - the scales

    static func radius(_ radius: Palette.Radius) -> CGFloat { CGFloat(radius.rawValue) }
    static func spacing(_ spacing: Palette.Spacing) -> CGFloat { CGFloat(spacing.rawValue) }

    // MARK: - motion

    /// One spring, everywhere.
    static let spring = Animation.spring(response: Palette.Motion.springResponse,
                                         dampingFraction: Palette.Motion.springDamping,
                                         blendDuration: 0)
    /// The same spring, critically damped — for sheets, which land with no
    /// bounce. A sheet that overshoots reads as the app being surprised by its
    /// own navigation.
    static let settle = Animation.spring(response: Palette.Motion.springResponse,
                                         dampingFraction: 1,
                                         blendDuration: 0)
    /// What Reduce Motion gets instead: a cross-fade, and no parallax ever.
    ///
    /// THE PERSON MAY BE WATCHING A REAL ROBOT. Movement in the interface that
    /// does not correspond to movement in the world is the one thing a robot
    /// controller must never do, and somebody who has asked the system for
    /// less of it has asked for a reason.
    static let reducedMotion = Animation.easeInOut(
        duration: Palette.Motion.reducedMotionSeconds)

    /// The animation to use, given the accessibility setting.
    static func motion(reduced: Bool) -> Animation { reduced ? reducedMotion : spring }

    // MARK: - type, and why there is no font token
    //
    // SF EVERYWHERE A PERSON READS, AND NO BUNDLED FACE. The Microduck page
    // sets display type in Anton and body in DM Sans; shipping two font files
    // to echo a website costs bytes on every install and breaks Dynamic Type
    // unless every use is scaled by hand — and this app has people reading long
    // refusals on a phone. Dynamic Type matters more than a matched face, so
    // every screen takes a system text style and none of them asks here.
    //
    // THERE WAS A `display(_:)` HELPER AND NOTHING EVER CALLED IT. It returned
    // `.system(size:weight:.heavy)` for large titles, and no screen used it:
    // the app sets titles with `.navigationTitle` forty-six times and
    // `.largeTitle` twice, and there is not one `weight: .heavy` in the target.
    // That is the correct answer and it is why the helper never found a caller.
    // A design token nothing draws is not a spare part, it is a second opinion:
    // the next person reads it as the app's way of setting a title and starts
    // hand-sizing type that Dynamic Type was already handling. The reasoning is
    // worth keeping and the function was not.
}

// MARK: - the appearance the person chose

extension Theme {

    /// What the person has asked the app to look like.
    ///
    /// TWO OPTIONS, AND `system` IS ONE OF THEM. There is no `light` case
    /// because "light" is not a thing to choose here — a phone set to light
    /// already produces light under `system`, and offering it separately would
    /// only let somebody pin the app against a phone that later switches to
    /// dark at sunset.
    enum Appearance: String, CaseIterable, Identifiable {
        /// Follow the phone. The default.
        case system
        /// Dark regardless.
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return "Match my phone"
            case .dark: return "Always dark"
            }
        }

        var detail: String {
            switch self {
            case .system:
                return "The app follows the appearance you set in Settings."
            case .dark:
                return "The 3D stage reads better on a dark ground. This keeps it dark even "
                     + "when your phone is light."
            }
        }

        /// `nil` means no preference — the system decides, which is what
        /// `preferredColorScheme` does with a nil argument.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .dark: return .dark
            }
        }
    }

    /// Where the choice is stored. Public so a settings screen can bind
    /// `@AppStorage` to the same key rather than to a second copy of it.
    static let appearanceKey = "theme.appearance"

    /// The default, and the reason it is `system`.
    ///
    /// THE OLD COMMENT WAS WRONG ABOUT ITS OWN CODE, and the code was the
    /// thing to fix. It said `preferredColorScheme` "asks; it does not
    /// insist" — it does insist. `.preferredColorScheme(.dark)` on the root
    /// view overrides the person's phone for the entire app; there is no
    /// asking in it, and the sentence directly above it ("an app that
    /// overrides that is an app that ignores a stated preference") described
    /// exactly what the line below was doing.
    ///
    /// Two things had to be true before it could be deleted, and now both are.
    /// The first is that light mode has to actually work: every token is
    /// defined in both schemes and every text token is asserted at 4.5:1
    /// against every ground it can land on, in light as well as dark. The
    /// second is that somebody who wants dark can still have it, which is what
    /// this setting is for. Dark remains the app's own preference — the 3D
    /// stage genuinely reads better on a dark ground — but a preference the
    /// app holds is an option it offers, not a setting it overwrites.
    ///
    /// DARK BY DEFAULT, AND THE REASON IS A COUNT, NOT A TASTE. The design
    /// system has reached four of this app's sixty-one screens. The other
    /// fifty-seven were built when dark was forced, on materials and literal
    /// colours never once drawn on cream — so a default of `.system` put a
    /// light-mode phone straight onto fifty-seven screens nobody had designed
    /// for light. Un-forcing dark was right; defaulting AWAY from it was not,
    /// yet. `.system` stays one tap away as a real choice, and the default
    /// moves back to it the day the count reaches sixty-one.
    static let defaultAppearance = Appearance.dark
}

/// Holds the stored choice. A `ViewModifier` rather than a plain `View`
/// extension because `@AppStorage` has to live on a `View` type to observe
/// changes — read straight out of `UserDefaults` in a function, the appearance
/// would only follow the setting after a relaunch.
private struct MicroduckTheme: ViewModifier {
    @AppStorage(Theme.appearanceKey) private var stored = Theme.defaultAppearance.rawValue

    func body(content: Content) -> some View {
        content
            // AN INK, BECAUSE A TINT SETS WORDS. Tab-bar labels, links and
            // `.borderless` buttons all inherit the tint as TEXT, and Duck
            // Orange is 2.30:1 on cream — the brief's own rule is that a brand
            // colour fills a shape and an ink sets a word. `actionSecondary` is
            // orange-ink in light (4.52:1) and full Duck Orange in dark, so the
            // tab bar reads in both and the capsule buttons, which fill their
            // own shape from `actionPrimary`, are untouched.
            .tint(Theme.actionSecondary)
            // EVERY BARE SECTION HEADER, LIFTED OUT OF A CONTRAST FAILURE AT
            // ONCE. A grouped list's default header is the system's secondary
            // label, about 3.18:1 on the light ground, and some sixty of them
            // are still plain `Text`. Increased prominence sets them in the
            // primary label colour, which is legible everywhere; the screens
            // that have moved to `SectionHeading` are unaffected, because a
            // header that sets its own font and colour keeps them.
            .headerProminence(.increased)
            .preferredColorScheme(
                (Theme.Appearance(rawValue: stored) ?? Theme.defaultAppearance).colorScheme)
    }
}

extension View {
    /// The app's tint and the appearance the person chose, in one place.
    ///
    /// DARK BY PREFERENCE, NOT BY FORCE — and this time the code says so. The
    /// tint is Duck Orange because the action colour is the one thing every
    /// system control in the app should inherit; the scheme is whatever
    /// `Theme.Appearance` holds, which is `nil` by default and therefore no
    /// override at all.
    func microduckTheme() -> some View {
        modifier(MicroduckTheme())
    }
}

private extension UIColor {
    /// The one place a `Palette.RGB` becomes a UIKit colour. Opaque: opacity
    /// is a decision about a particular shape on a particular ground, and
    /// baking it into a token would hide the ground its contrast was computed
    /// against.
    convenience init(_ rgb: Palette.RGB) {
        self.init(red: CGFloat(rgb.red), green: CGFloat(rgb.green),
                  blue: CGFloat(rgb.blue), alpha: 1)
    }
}
