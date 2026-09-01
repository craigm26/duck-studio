import Foundation

/// The design system as data, so a colour can be argued with before it ships.
///
/// COLOUR VALUES ARE FACTS AND FACTS BELONG WHERE THEY CAN BE TESTED. A
/// contrast ratio is arithmetic on two hex triples; it is not a matter of
/// taste, and it is not something anybody can eyeball on a phone in a lit
/// room. Putting the palette in a SwiftUI file makes every one of those
/// numbers unfalsifiable — `Color(red:green:blue:)` has no opinion about
/// whether the result is legible, and nothing on the Mac build will ever tell
/// you. Here the same numbers are Linux-testable Doubles, and
/// `PaletteTests` fails the build when one of them stops passing.
///
/// THE FINDING THAT SHAPES THE WHOLE SCHEME. Not one Microduck brand accent is
/// legible as body text on Warm Cream. Computed with WCAG 2.1's own relative
/// luminance, against the 4.5:1 that SC 1.4.3 asks of body text:
///
///     Duck Orange   #FF7A12 on #F6F0E4 → 2.30:1
///     Lavender      #A98BCD on #F6F0E4 → 2.55:1
///     Microduck Teal #69C7C8 on #F6F0E4 → 1.74:1
///     Lens Yellow   #FFB51B on #F6F0E4 → 1.56:1
///
/// On Mechanical Charcoal all four pass comfortably — 6.76, 6.11, 8.92 and
/// 9.99 — which is why the palette looks like it works until somebody turns
/// the lights on. The fix is not to abandon the hues but to darken them until
/// they pass: the four INK variants below are the same colours at the weight
/// a cream ground requires. Hence the rule the rest of the app follows: a
/// brand colour FILLS A SHAPE, an ink colour SETS A WORD.
///
/// WHERE THIS FILE DISAGREES WITH THE BRIEF IT WAS BUILT FROM, and why. The
/// brief asserted "3:1 bar, all pass" for brand fills and pinned four
/// semantic tokens whose numbers do not survive the formula. Each deviation
/// applies the brief's own method — keep the hue, darken until it passes —
/// and each is pinned by a test that fails if somebody puts the original
/// value back:
///
///   1. `focus` in light was Microduck Teal, which is 1.74:1 on cream. A
///      focus ring nobody can see is the one contrast failure that locks a
///      keyboard or switch user out of the app entirely (SC 2.4.11, 1.4.11).
///      Light focus is now `tealInk`, 4.62:1 — already a palette member, so
///      the ring is still the brand colour, just at cream's weight.
///   2. `textTertiary` and `robotOffline` in light were #6E7A80, which is
///      3.89:1 on cream and 4.23:1 on the primary surface. Both set words —
///      one of them sets the word beside an offline robot's dot — so both owe
///      4.5:1. They are now `greyInk` #5E696F, a fifth ink in the same hue.
///   3. `textTertiary` and `robotOffline` in dark were #7E8E94, which clears
///      the background at 5.48:1 but lands at 4.45:1 on `surfaceElevated` —
///      the sheets and raised cards a tertiary label most often sits on. They
///      are now #859398, which clears every dark ground.
///   4. `actionPrimary` in light stays Duck Orange, because taking the brand's
///      action colour out of the one place a person presses would be fixing
///      the measurement by deleting the thing measured. Instead the SHAPE gets
///      an edge: see `fillEdge`.
///
/// NEVER RELY ON COLOUR ALONE. Every robot state has a word beside its dot,
/// and every selection carries a mark as well as a wash — `surfaceInteractive`
/// differs from its ground by 1.02:1 in light and 1.14:1 in dark, which is a
/// hint that something is selected and is not, on its own, information.
/// `PaletteTests` asserts that smallness deliberately, so nobody later mistakes
/// the wash for a signal.
public enum Palette {

    // MARK: - the primitive

    /// A colour as three linear-input sRGB channels in `0...1`.
    ///
    /// DOUBLES RATHER THAN BYTES because every consumer wants them that way:
    /// the contrast formula needs channels normalised before it linearises
    /// them, and SwiftUI's `Color(red:green:blue:)` and UIKit's
    /// `UIColor(red:green:blue:alpha:)` both take `0...1`. Storing bytes would
    /// mean dividing by 255 in three different places, which is three chances
    /// to divide by 256 instead.
    ///
    /// No alpha. A design token is a colour, and opacity is a decision the
    /// drawing code makes about a particular shape on a particular ground —
    /// baking it into the token hides the ground the contrast was computed
    /// against, which is the one thing this file exists to keep honest.
    public struct RGB: Equatable, Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Six hex digits, with or without the leading `#`, case-insensitive.
        ///
        /// TRAPS RATHER THAN RETURNING NIL, and that is the safe direction
        /// here. Every caller in this file is a literal written once by a
        /// person reading a brand sheet; a typo in one is a programmer error
        /// that should stop the first test that touches it, loudly and with
        /// the offending string in the message. The failable alternative
        /// forces a force-unwrap at every one of those literals, and the
        /// realistic outcome of a `?? .black` fallback is a token that is
        /// silently the wrong colour in shipping builds — which is precisely
        /// the class of bug the tests below exist to catch.
        ///
        /// Three-digit shorthand and eight-digit alpha are rejected on
        /// purpose: a palette in which the same colour has two spellings is a
        /// palette that will eventually hold two slightly different versions
        /// of it.
        public init(hex: String) {
            var digits = Substring(hex)
            if digits.hasPrefix("#") { digits = digits.dropFirst() }
            precondition(digits.count == 6,
                         "A palette hex is exactly six digits, got \(hex)")
            guard let value = UInt32(digits, radix: 16) else {
                preconditionFailure("Not a hex colour: \(hex)")
            }
            self.red = Double((value >> 16) & 0xFF) / 255.0
            self.green = Double((value >> 8) & 0xFF) / 255.0
            self.blue = Double(value & 0xFF) / 255.0
        }

        /// Back to `#RRGGBB`, uppercase — the spelling the brand sheet uses.
        ///
        /// This exists so the tests can round-trip every constant. A parser
        /// that is wrong in the same direction as the code reading its output
        /// produces a palette that is self-consistently the wrong colour, and
        /// nothing else in the app would notice.
        public var hexString: String {
            func byte(_ channel: Double) -> Int { Int((channel * 255.0).rounded()) }
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }

        /// WCAG 2.1 relative luminance, from the definition itself.
        ///
        /// The channels are linearised out of sRGB's transfer curve first —
        /// `c/12.92` below the 0.03928 knee, `((c+0.055)/1.055)^2.4` above it —
        /// and then weighted 0.2126 / 0.7152 / 0.0722 for red, green and blue.
        /// Source: WCAG 2.1, "relative luminance" in the glossary.
        ///
        /// THE LINEARISATION IS THE WHOLE THING, and skipping it is the
        /// standard way this gets got wrong. A weighted average of the raw
        /// 0...1 channels looks plausible and is generous by roughly a factor
        /// of two in the midtones, which is exactly the range every ink
        /// variant below lives in. A palette validated with the shortcut would
        /// have reported all four inks passing whatever value they held.
        public var relativeLuminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.03928
                    ? channel / 12.92
                    : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    /// Which of the two grounds a colour is being asked for.
    ///
    /// Not `ColorScheme`: that type lives in SwiftUI, and the point of this
    /// file is that it builds and tests on a machine with no SwiftUI on it.
    /// `Theme` maps the two across at the one place they meet.
    public enum Scheme: String, CaseIterable, Sendable {
        case light
        case dark
    }

    // MARK: - the brand, verbatim

    /// `#69C7C8` — brand moments, selected states, connection accents.
    public static let microduckTeal = RGB(hex: "#69C7C8")
    /// `#FF7A12` — THE action colour: movement, active behaviours, the thing
    /// you press. The one accent that is never replaced by its ink, because
    /// the button a person reaches for is where a brand actually lives.
    public static let duckOrange = RGB(hex: "#FF7A12")
    /// `#FFB51B` — the eye. Active sensors, discoveries, training progress,
    /// and used sparingly: it is the brightest thing in the palette and it
    /// stops meaning "look here" the moment two of them are on screen.
    public static let lensYellow = RGB(hex: "#FFB51B")
    /// `#F6F0E4` — the light ground and the robot's own shell. Pure white is
    /// never a surface in this app; it appears once, as `surfaceElevated` in
    /// light, where a sheet has to lift off the cream and nothing else will.
    public static let warmCream = RGB(hex: "#F6F0E4")
    /// `#A98BCD` — secondary categorisation and training. Used least.
    public static let microduckLavender = RGB(hex: "#A98BCD")
    /// `#111A1D` — type, icons, the dark ground. Blue-black, never true
    /// black: beside `#000000` it reads as chosen rather than defaulted, and
    /// it is the same bias the dark grounds below are derived along.
    public static let mechanicalCharcoal = RGB(hex: "#111A1D")

    // MARK: - the inks

    /// `#AF540C` — Duck Orange at 4.52:1 on Warm Cream.
    ///
    /// The four inks are the brand hues darkened until they clear SC 1.4.3's
    /// 4.5:1 for body text, and no further. Stopping at the bar rather than
    /// well past it is deliberate: every step darker is a step further from
    /// the colour on the robot, and the app is meant to look like it belongs
    /// beside the thing it drives.
    public static let orangeInk = RGB(hex: "#AF540C")
    /// `#8E650F` — Lens Yellow at 4.60:1 on Warm Cream.
    public static let yellowInk = RGB(hex: "#8E650F")
    /// `#3D7576` — Microduck Teal at 4.62:1 on Warm Cream.
    public static let tealInk = RGB(hex: "#3D7576")
    /// `#796493` — Lavender at 4.56:1 on Warm Cream.
    public static let lavenderInk = RGB(hex: "#796493")

    /// `#5E696F` — the fifth ink, and not one the brief specified.
    ///
    /// THE BRIEF'S OWN METHOD, APPLIED TO THE TOKEN IT DID NOT MEASURE. Light
    /// mode's tertiary text was to be #6E7A80, which is 3.89:1 on cream and
    /// 4.23:1 on the primary surface — below the body-text bar on both, and
    /// the same failure the four accents were caught by. This is that grey
    /// darkened along its own hue (a blue-grey at roughly 199°, so it stays
    /// in Mechanical Charcoal's family rather than going neutral) until it
    /// clears every light ground: 4.97:1 on the background, 5.41 on the
    /// primary surface, 5.64 on elevated, 5.06 on interactive, 4.59 on the
    /// secondary background. It is still visibly lighter than `textSecondary`
    /// at 6.76:1, so the three-step type hierarchy survives the fix.
    public static let greyInk = RGB(hex: "#5E696F")

    // MARK: - the bars

    /// 4.5:1 — WCAG 2.1 SC 1.4.3 (Contrast Minimum) for body-size text.
    ///
    /// The 3:1 large-text allowance is deliberately not modelled. This app
    /// sets telemetry in caption sizes and refusals in body copy; a token that
    /// only passes at 24pt is a token somebody will eventually use at 13.
    public static let textContrastMinimum = 4.5

    /// 3:1 — WCAG 2.1 SC 1.4.11 (Non-text Contrast), for the boundary of a
    /// control against whatever is next to it.
    public static let shapeContrastMinimum = 3.0

    // MARK: - the semantic tokens

    /// Every colour the app is allowed to name.
    ///
    /// THE ENUM IS THE POINT, not the values behind it. A token can be
    /// iterated, which is what lets `PaletteTests` assert a property of ALL of
    /// them — "every token that sets words clears 4.5:1 on both grounds in
    /// both schemes" — rather than a hand-written list that goes stale the
    /// first time somebody adds a colour and forgets the test. A raw
    /// `Color(hex:)` in a view is invisible to that.
    public enum Token: String, CaseIterable, Sendable {
        case backgroundPrimary
        case backgroundSecondary
        case surfacePrimary
        case surfaceElevated
        case surfaceInteractive
        case textPrimary
        case textSecondary
        case textTertiary
        case brandPrimary
        case actionPrimary
        case actionSecondary
        case robotActive
        case robotIdle
        case robotOffline
        case sensorActive
        case training
        case success
        case warning
        case critical
        case separator
        case focus

        /// Whether this token sets words, and therefore owes 4.5:1 against
        /// every ground words are set on.
        ///
        /// THE ROBOT STATES ARE TEXT TOKENS, which is the non-obvious entry.
        /// The app never signals a robot's state with a dot alone — a person
        /// who cannot separate the teal dot from the orange one has to be able
        /// to read "idle" and "driving" — so the state colour ends up on a
        /// word every time it ends up on a dot, and it owes the text bar
        /// rather than the shape bar.
        ///
        /// `actionPrimary` is the deliberate exception: it is Duck Orange, it
        /// fills the capsule a person presses, and the label inside that
        /// capsule is drawn in `textPrimary` against the orange rather than in
        /// orange against the ground.
        public var isText: Bool {
            switch self {
            case .textPrimary, .textSecondary, .textTertiary,
                 .brandPrimary, .actionSecondary,
                 .robotActive, .robotIdle, .robotOffline,
                 .sensorActive, .training,
                 .success, .warning, .critical:
                return true
            case .backgroundPrimary, .backgroundSecondary,
                 .surfacePrimary, .surfaceElevated, .surfaceInteractive,
                 .actionPrimary, .separator, .focus:
                return false
            }
        }

        /// Whether this token draws a shape whose edge a person has to be able
        /// to find against the ground — a filled capsule, a status dot, a
        /// progress bar, a focus ring — and therefore owes SC 1.4.11's 3:1.
        ///
        /// `separator` is not one. A hairline between rows is decoration in
        /// the specific sense 1.4.11 means: remove it and every row is still
        /// identifiable, because the rows are separated by space and set in
        /// type. Holding a 3:1 separator against cream would mean a rule dark
        /// enough to read as a table border, which is a different and much
        /// louder app than this one.
        public var isFill: Bool {
            switch self {
            case .actionPrimary, .brandPrimary, .focus,
                 .robotActive, .robotIdle, .robotOffline,
                 .sensorActive, .training,
                 .success, .warning, .critical:
                return true
            case .backgroundPrimary, .backgroundSecondary,
                 .surfacePrimary, .surfaceElevated, .surfaceInteractive,
                 .textPrimary, .textSecondary, .textTertiary,
                 .actionSecondary, .separator:
                return false
            }
        }

        /// Whether this token is a ground that words are set directly on, and
        /// therefore one every text token has to be checked against.
        ///
        /// `backgroundSecondary` is pointedly NOT one, and the number is the
        /// reason: the four inks land between 4.17:1 and 4.27:1 on #EFE7D8,
        /// short of the body-text bar. That is not a defect to fix by
        /// re-tuning four inks whose ratios on the primary ground are pinned
        /// to two decimals — it is what a recessed ground is for. It sits
        /// BEHIND grouped content the way `systemGroupedBackground` does on
        /// iOS; the words go on the `surfacePrimary` cards that sit on it. A
        /// test asserts the shortfall so the distinction is enforced rather
        /// than remembered.
        public var isTextGround: Bool {
            switch self {
            case .backgroundPrimary, .surfacePrimary,
                 .surfaceElevated, .surfaceInteractive:
                return true
            case .backgroundSecondary,
                 .textPrimary, .textSecondary, .textTertiary,
                 .brandPrimary, .actionPrimary, .actionSecondary,
                 .robotActive, .robotIdle, .robotOffline,
                 .sensorActive, .training,
                 .success, .warning, .critical,
                 .separator, .focus:
                return false
            }
        }
    }

    /// The value of a token in a scheme.
    ///
    /// EXHAUSTIVE, WITH NO `default`. A new token must not compile until
    /// somebody has decided what it is in BOTH schemes — the default clause is
    /// how a palette acquires a token that is correct in dark and arbitrary in
    /// light, which is the exact bug this rewrite exists to undo.
    public static func color(_ token: Token, in scheme: Scheme) -> RGB {
        let light = scheme == .light
        switch token {

        // Grounds. The dark pair is Mechanical Charcoal taken down rather than
        // toward neutral, so the blue-black bias survives into the deepest
        // well; the light pair is Warm Cream and Warm Cream slightly sunk.
        case .backgroundPrimary:
            return light ? warmCream : RGB(hex: "#0D1417")
        case .backgroundSecondary:
            return light ? RGB(hex: "#EFE7D8") : RGB(hex: "#080E10")

        // Surfaces. Light's elevated is the app's only pure white, and it is
        // an elevation rather than a ground: it exists so a sheet can lift off
        // cream, which nothing dimmer than white manages at 1.14:1.
        case .surfacePrimary:
            return light ? RGB(hex: "#FDFAF3") : RGB(hex: "#151F23")
        case .surfaceElevated:
            return light ? RGB(hex: "#FFFFFF") : RGB(hex: "#1C282D")
        // Pale teal, so a selected row reads as this app's brand rather than
        // as the system blue every other app selects with.
        case .surfaceInteractive:
            return light ? RGB(hex: "#EAF5F4") : RGB(hex: "#132226")

        // Type. The two primaries are each other's ground, which is the
        // cleanest evidence that the pair is right: 15.56:1 either way up.
        case .textPrimary:
            return light ? mechanicalCharcoal : warmCream
        case .textSecondary:
            return light ? RGB(hex: "#4A555A") : RGB(hex: "#AFBDC1")
        // Warm-biased rather than neutral, and darkened past the brief's
        // #6E7A80 / #7E8E94 in both directions — see `greyInk`.
        case .textTertiary:
            return light ? greyInk : RGB(hex: "#859398")

        // Brand and action. Light takes the ink of every hue except the one a
        // person presses.
        case .brandPrimary:
            return light ? tealInk : microduckTeal
        case .actionPrimary:
            return duckOrange
        case .actionSecondary:
            return light ? orangeInk : duckOrange

        // Robot state. Orange for a robot that is moving, teal for one that is
        // powered and still, grey for one that is not there — and a word
        // beside each, always.
        case .robotActive:
            return light ? orangeInk : duckOrange
        case .robotIdle:
            return light ? tealInk : microduckTeal
        case .robotOffline:
            return light ? greyInk : RGB(hex: "#859398")

        // Sensing and training. Yellow is the eye; lavender is the least-used
        // hue in the palette and training is the least-frequent thing the app
        // reports, which is why they are paired.
        case .sensorActive:
            return light ? yellowInk : lensYellow
        case .training:
            return light ? lavenderInk : microduckLavender

        // Status. Green and red are not in the brand palette because the brand
        // has no opinion about failure; these are chosen to sit in the same
        // desaturated register as the inks rather than to look like system
        // colours dropped in.
        case .success:
            return light ? RGB(hex: "#2E6B4F") : RGB(hex: "#5FC38F")
        case .warning:
            return light ? yellowInk : lensYellow
        case .critical:
            return light ? RGB(hex: "#A32020") : RGB(hex: "#FF6B6B")

        // Furniture.
        case .separator:
            return light ? RGB(hex: "#DED3BE") : RGB(hex: "#2A383D")
        // Microduck Teal in dark at 9.39:1. In light the same hue at ink
        // weight, 4.62:1 — the brand teal itself is 1.74:1 on cream, which is
        // a focus ring that does not exist for the people who most need one.
        case .focus:
            return light ? tealInk : microduckTeal
        }
    }

    /// The stroke a filled shape needs so its EDGE clears 3:1, or `nil` when
    /// the fill already clears the ground on its own.
    ///
    /// THE ONE CASE IS DUCK ORANGE ON CREAM, and it is worth the API. Orange
    /// is 2.30:1 on Warm Cream — below SC 1.4.11 — so an unbordered orange
    /// capsule on the light ground is a control whose boundary a person with
    /// low vision cannot locate. The three ways out are to darken the button
    /// (which removes the brand's action colour from the only place it truly
    /// matters), to accept the failure (which is a real accessibility defect
    /// in the most-pressed control in the app), or to give the shape an edge.
    /// 1.4.11 is a requirement about the boundary of a component, so an edge
    /// satisfies it exactly: `orangeInk` is the same hue at 4.52:1, a hairline
    /// of it reads as a rim rather than an outline, and the fill stays Duck
    /// Orange. The brief's "NO thick outlines" survives — this is one point,
    /// not a frame.
    ///
    /// Dark needs none of this: orange is 7.12:1 on #0D1417.
    public static func fillEdge(_ token: Token, in scheme: Scheme) -> RGB? {
        switch (token, scheme) {
        case (.actionPrimary, .light):
            return orangeInk
        default:
            return nil
        }
    }

    /// The scheme's own ground — shorthand for `backgroundPrimary`, which is
    /// what nearly every contrast question is asked against.
    public static func ground(in scheme: Scheme) -> RGB {
        color(.backgroundPrimary, in: scheme)
    }

    // MARK: - the maths

    /// WCAG 2.1 contrast ratio, `(L_lighter + 0.05) / (L_darker + 0.05)`.
    ///
    /// Symmetric by construction — it sorts the two luminances rather than
    /// trusting the argument order — because the commonest way to get a
    /// contrast helper wrong is to assume the foreground is always the lighter
    /// one, which silently returns a number below 1 for dark text and passes
    /// nothing. Range is 1...21.
    public static func contrast(_ a: RGB, on b: RGB) -> Double {
        let first = a.relativeLuminance
        let second = b.relativeLuminance
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// The same question asked in tokens, which is how the app asks it.
    public static func contrast(_ token: Token, on ground: Token,
                                in scheme: Scheme) -> Double {
        contrast(color(token, in: scheme), on: color(ground, in: scheme))
    }

    // MARK: - the scales

    /// Corner radii on a 4pt base, smallest to largest.
    ///
    /// CONCENTRIC CORNERS ARE THE REASON THIS IS AN ENUM rather than five
    /// loose constants. A card inside a card takes the next radius down — see
    /// `inner` — and the arithmetic that produces machined-looking nesting is
    /// "one step down the scale", not "minus four". Written as raw numbers at
    /// each call site, the nesting drifts within a release and the corners
    /// stop looking cut from one piece.
    public enum Radius: Double, CaseIterable, Sendable {
        /// 6 — chips and tags.
        case chip = 6
        /// 10 — buttons, fields, anything pressable that is not a capsule.
        case control = 10
        /// 14 — cards.
        case card = 14
        /// 20 — a group of cards.
        case group = 20
        /// 28 — sheets.
        case sheet = 28

        /// The radius a shape nested inside this one takes.
        ///
        /// `chip` returns itself: below six points the corner stops reading as
        /// a corner, and a chip inside a chip is a layout that has gone wrong
        /// somewhere further up anyway.
        public var inner: Radius {
            switch self {
            case .chip: return .chip
            case .control: return .chip
            case .card: return .control
            case .group: return .card
            case .sheet: return .group
            }
        }
    }

    /// A fully rounded end, for anything pressable that reads as a capsule.
    ///
    /// NOT A NUMBER, AND THAT IS WHY IT IS NOT IN `Radius`. A pill's radius is
    /// half its height, so it has no place on a scale of points; SwiftUI
    /// spells it `Capsule()` and the drawing code should too. It is here so
    /// that "pill" appears in the design system rather than only in the views,
    /// and the value is infinite so that clamping it against a real radius
    /// picks the pill.
    public static let pill = Double.infinity

    /// The spacing scale, 4pt base.
    ///
    /// SEVEN STEPS AND NO OTHERS. The value of a scale is entirely in what it
    /// forbids: 18 and 20 both look fine in isolation and, mixed across a
    /// screen, produce gutters that are visibly not aligned to anything. Every
    /// gap in the app is one of these.
    public enum Spacing: Double, CaseIterable, Sendable {
        /// 4 — inside a chip; between a glyph and its label.
        case hairline = 4
        /// 8 — between a label and the value it names.
        case tight = 8
        /// 12 — between rows within a group.
        case snug = 12
        /// 16 — the default gutter and screen margin.
        case standard = 16
        /// 24 — between groups.
        case loose = 24
        /// 32 — between sections of a screen.
        case section = 32
        /// 48 — above a screen's title.
        case chapter = 48
    }

    /// The base every spacing step is a multiple of.
    public static let spacingBase = 4.0

    // MARK: - motion

    /// One spring, everywhere.
    ///
    /// THESE ARE FACTS AND SO THEY LIVE HERE. A spring response is a number
    /// that has to be identical in every animation in the app or the app feels
    /// assembled from parts; born inside a view it is a number nothing can
    /// check. `Theme` turns them into a SwiftUI `Animation` at the single
    /// point where this package meets that framework.
    public enum Motion {
        /// 0.35 s — the response of the one spring.
        public static let springResponse = 0.35
        /// 0.82 — damping. Below 1, so it settles without ringing; sheets are
        /// given no bounce at all, because a sheet that overshoots reads as
        /// the app being surprised by its own navigation.
        public static let springDamping = 0.82
        /// 0.12 s — what Reduce Motion gets instead: a cross-fade.
        ///
        /// AND NO PARALLAX, EVER. The person may be watching a real robot at
        /// the same time as this screen; motion in the interface that does not
        /// correspond to motion in the world is the one thing a robot
        /// controller must never do.
        public static let reducedMotionSeconds = 0.12
    }
}
