import Foundation

/// The design system as data, so a colour can be argued with before it ships.
///
/// COLOUR VALUES ARE FACTS AND FACTS BELONG WHERE THEY CAN BE TESTED. A
/// contrast ratio is arithmetic on two hex triples. Here every value is a
/// Linux-testable Double, and `PaletteTests` fails the build when one of them
/// stops passing.
///
/// THE THEME IS "POND DAY" (docs/design/playful-theme.md). It is built from the
/// app icon and Pollen's Microduck pages: a bright pond-teal page, cream cards,
/// thick ink outlines, and orange, yellow, teal and lavender each doing one
/// job. Light is the default look; dark is a "night pond", deep teal and never
/// black.
///
/// THE RULES THE TESTS HOLD:
///
///   1. Every word clears 4.5:1 on every ground words are set on, both schemes.
///   2. Every bright fill carries an ink label (`onFill`), 6.8:1 or better.
///      White text appears on exactly one colour: Stop red.
///   3. Every pressable fill gets a 2pt ink outline (`fillEdge`). Light fills
///      like orange (2.33:1) and yellow (1.43:1) cannot carry a 3:1 boundary
///      on the light page by themselves; the outline is 15.9:1.
///   4. Stop is the only red. One value, `#D92A2A`, in both schemes, and no
///      other token sits within 20 degrees of its hue. The error colour is a
///      berry at least 30 degrees away so a refusal never looks like Stop.
///
/// NEVER RELY ON COLOUR ALONE. Every robot state has a word beside its dot,
/// and every selection carries a mark as well as a wash.
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

    // MARK: - the brand, from the icon

    /// `#75C6C7`, the icon's sky. X button, selected mode, brand moments.
    public static let microduckTeal = RGB(hex: "#75C6C7")
    /// `#FF7A1A`, the beak. THE action colour: Drive, Go, the A button. One
    /// orange per screen region, so it still means "press me".
    public static let duckOrange = RGB(hex: "#FF7A1A")
    /// `#CC4C00`, the underside of the beak. The lip under an orange fill.
    public static let beakShadow = RGB(hex: "#CC4C00")
    /// `#FFAF09`, the eye ring.
    public static let lensYellow = RGB(hex: "#FFAF09")
    /// `#FFC328`, the soles of the feet. Second-tier fills: Reset, Y, the
    /// stick knob.
    public static let feetYellow = RGB(hex: "#FFC328")
    /// `#FFFBF2`, the shell. Cards and panels in light.
    public static let shellCream = RGB(hex: "#FFFBF2")
    /// `#F9EFDE`, the shell as the 3D stage paints it (blocks and props).
    public static let shellPaint = RGB(hex: "#F9EFDE")
    /// `#B494C5`, the wing. B button, training.
    public static let microduckLavender = RGB(hex: "#B494C5")
    /// `#10191C`, every outline in the icon. Type in light, the label on every
    /// bright fill, and the 2pt outline round every pressable shape.
    public static let iconInk = RGB(hex: "#10191C")
    /// `#E6F5F4`, the icon sky lightened. The light page.
    public static let pondMist = RGB(hex: "#E6F5F4")
    /// `#10262B`, the icon sky taken to deep teal. The dark page.
    public static let nightPond = RGB(hex: "#10262B")
    /// `#D92A2A`, emergency Stop and nothing else, in both schemes.
    public static let stopRed = RGB(hex: "#D92A2A")
    /// `#A3246B`, refusals and errors in light. A berry, far enough round the
    /// hue circle from Stop that a refusal never reads as the Stop control.
    public static let berry = RGB(hex: "#A3246B")

    // MARK: - the inks

    /// `#A84B05`, orange as a word (the tab tint, links). 5.10:1 on Pond Mist.
    ///
    /// The inks are the brand hues darkened until they clear 4.5:1 on every
    /// light ground, including the selection wash, which is the darkest.
    public static let orangeInk = RGB(hex: "#A84B05")
    /// `#8A5B00`, yellow as a word. 5.24:1 on Pond Mist.
    public static let yellowInk = RGB(hex: "#8A5B00")
    /// `#2B6E70`, teal as a word. 5.25:1 on Pond Mist.
    public static let tealInk = RGB(hex: "#2B6E70")
    /// `#6E5689`, lavender as a word. 5.58:1 on Pond Mist.
    public static let lavenderInk = RGB(hex: "#6E5689")
    /// `#4A5B60`, the muted caption grey, ink lifted toward teal. 6.34:1 on
    /// Pond Mist and still 5.63:1 on the selection wash.
    public static let greyInk = RGB(hex: "#4A5B60")

    // MARK: - the bars

    /// 4.5:1, WCAG 2.1 SC 1.4.3 (Contrast Minimum) for body-size text.
    ///
    /// The 3:1 large-text allowance is deliberately not modelled. This app
    /// sets telemetry in caption sizes; a token that only passes at 24pt is a
    /// token somebody will eventually use at 13.
    public static let textContrastMinimum = 4.5

    /// 3:1, WCAG 2.1 SC 1.4.11 (Non-text Contrast), for the boundary of a
    /// control against whatever is next to it.
    public static let shapeContrastMinimum = 3.0

    // MARK: - the semantic tokens

    /// Every colour the app is allowed to name.
    ///
    /// THE ENUM IS THE POINT. A token can be iterated, which lets
    /// `PaletteTests` assert a property of ALL of them rather than a list
    /// that goes stale the first time somebody adds a colour.
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
        /// The one main action fill: Drive, Go, the A button. Orange.
        case actionPrimary
        /// Orange as a WORD: the tab tint, links, a glyph on a cream chip.
        case actionInk
        /// Second-tier fill: Reset, the Y button, chips. Yellow.
        case actionYellow
        /// The X button and the selected mode segment. Teal.
        case actionTeal
        /// The B button, training. Lavender.
        case actionLavender
        /// The label and glyph on every bright fill. Ink in both schemes.
        case onFill
        /// The 2pt outline round every pressable fill.
        case outline
        /// The thumb pad well on Play.
        case stickPad
        /// The thumb pad's 2pt rim.
        case stickPadRim
        /// Emergency Stop. The only red.
        case stop
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
        /// The 3D practice floor's playmat.
        case stageDeck
        /// The playmat's fine grid.
        case stageGridMinor
        /// The playmat's metre grid.
        case stageGridMajor
        /// Blocks and props on the stage: shell cream.
        case stageProp
        /// Walls on the stage: lavender.
        case stageWall
        /// The stage's fill light: warm by day, cool at night.
        case stageLight

        /// Whether this token sets words on the scheme's grounds, and
        /// therefore owes 4.5:1 against every ground words are set on.
        ///
        /// `onFill` sets words too, but on a FILL, not a ground; it is held
        /// to its own test (`testEveryLabelOnAFillIsInkExceptStop`).
        public var isText: Bool {
            switch self {
            case .textPrimary, .textSecondary, .textTertiary,
                 .brandPrimary, .actionInk,
                 .robotActive, .robotIdle, .robotOffline,
                 .sensorActive, .training,
                 .success, .warning, .critical:
                return true
            default:
                return false
            }
        }

        /// Whether this token draws a shape whose edge a person has to find
        /// against the ground, and therefore owes SC 1.4.11's 3:1 (from the
        /// fill itself or from `fillEdge`).
        public var isFill: Bool {
            switch self {
            case .actionPrimary, .actionYellow, .actionTeal, .actionLavender,
                 .stop, .stickPad,
                 .brandPrimary, .focus,
                 .robotActive, .robotIdle, .robotOffline,
                 .sensorActive, .training,
                 .success, .warning, .critical:
                return true
            default:
                return false
            }
        }

        /// A bright fill a person presses. Each carries an `onFill` label, a
        /// 2pt `outline` and a darker `lip` under it.
        public var isPressableFill: Bool {
            switch self {
            case .actionPrimary, .actionYellow, .actionTeal, .actionLavender:
                return true
            default:
                return false
            }
        }

        /// Whether this token is a ground that words are set directly on.
        public var isTextGround: Bool {
            switch self {
            case .backgroundPrimary, .backgroundSecondary, .surfacePrimary,
                 .surfaceElevated, .surfaceInteractive:
                return true
            default:
                return false
            }
        }

        /// Of the grounds words land on, the ones where EVERY text token
        /// clears 4.5:1. In Pond Day that is all five: the inks were darkened
        /// against the darkest light ground (the selection wash) so no ground
        /// needs an exception list.
        public var takesEveryTextToken: Bool { isTextGround }
    }

    /// The value of a token in a scheme.
    ///
    /// EXHAUSTIVE, WITH NO `default`. A new token must not compile until
    /// somebody has decided what it is in BOTH schemes.
    public static func color(_ token: Token, in scheme: Scheme) -> RGB {
        let light = scheme == .light
        switch token {

        // Grounds: the icon's sky, lightened by day and deepened at night.
        case .backgroundPrimary:
            return light ? pondMist : nightPond
        case .backgroundSecondary:
            return light ? RGB(hex: "#D8EEEC") : RGB(hex: "#0B1D21")

        // Surfaces: the shell by day. White is elevation only.
        case .surfacePrimary:
            return light ? shellCream : RGB(hex: "#183338")
        case .surfaceElevated:
            return light ? RGB(hex: "#FFFFFF") : RGB(hex: "#204048")
        // The selection wash. Always with a mark too.
        case .surfaceInteractive:
            return light ? RGB(hex: "#CDEBE9") : RGB(hex: "#1F4950")

        // Type: icon ink by day, icon cream at night.
        case .textPrimary:
            return light ? iconInk : RGB(hex: "#FFF6E6")
        case .textSecondary:
            return light ? RGB(hex: "#34454A") : RGB(hex: "#CFE0E0")
        case .textTertiary:
            return light ? greyInk : RGB(hex: "#A7C4C6")

        case .brandPrimary:
            return light ? tealInk : RGB(hex: "#7FD3D3")

        // Fills. Ink labels on all of them.
        case .actionPrimary:
            return light ? duckOrange : RGB(hex: "#FF8A2E")
        case .actionInk:
            return light ? orangeInk : RGB(hex: "#FFA04F")
        case .actionYellow:
            return light ? feetYellow : RGB(hex: "#FFC93D")
        case .actionTeal:
            return light ? microduckTeal : RGB(hex: "#7FD3D3")
        case .actionLavender:
            return light ? microduckLavender : RGB(hex: "#C4A8D8")
        case .onFill:
            return iconInk
        case .outline:
            return light ? iconInk : RGB(hex: "#0A1416")
        case .stickPad:
            return light ? RGB(hex: "#EEE6F6") : RGB(hex: "#2B2D4A")
        case .stickPadRim:
            return light ? iconInk : RGB(hex: "#9C8CC8")
        case .stop:
            return stopRed

        // Robot state: orange moving, teal still, grey absent. A word beside
        // each, always.
        case .robotActive:
            return light ? orangeInk : RGB(hex: "#FFA04F")
        case .robotIdle:
            return light ? tealInk : RGB(hex: "#7FD3D3")
        case .robotOffline:
            return light ? greyInk : RGB(hex: "#A7C4C6")

        case .sensorActive:
            return light ? yellowInk : RGB(hex: "#FFC93D")
        case .training:
            return light ? lavenderInk : RGB(hex: "#C4A8D8")

        // Status. Green is a leaf green clear of teal; the error colour is a
        // berry, never red, because red is Stop.
        case .success:
            return light ? RGB(hex: "#1D7344") : RGB(hex: "#5ED39A")
        case .warning:
            return light ? yellowInk : RGB(hex: "#FFC93D")
        case .critical:
            return light ? berry : RGB(hex: "#FF8CCB")

        case .separator:
            return light ? RGB(hex: "#C3DCDA") : RGB(hex: "#2E5258")
        // Ink by day (15.9:1), yellow at night (10.3:1).
        case .focus:
            return light ? iconInk : RGB(hex: "#FFC93D")

        // The 3D practice floor: a teal playmat that makes the cream duck,
        // its yellow head and the orange ball pop.
        case .stageDeck:
            return light ? RGB(hex: "#A8DCD9") : RGB(hex: "#1F4A50")
        case .stageGridMinor:
            return light ? RGB(hex: "#93D0CC") : RGB(hex: "#2A5C62")
        case .stageGridMajor:
            return light ? RGB(hex: "#6DB9B5") : RGB(hex: "#3D767C")
        case .stageProp:
            return shellPaint
        case .stageWall:
            return light ? microduckLavender : RGB(hex: "#7D6E9E")
        case .stageLight:
            return light ? RGB(hex: "#FFF6E6") : RGB(hex: "#CFE6FF")
        }
    }

    /// The stroke a filled shape is drawn with, or `nil` for none.
    ///
    /// EVERY PRESSABLE FILL AND THE STOP DISC GET THE 2pt INK OUTLINE, in both
    /// schemes, like the icon. In light it is what makes the control findable
    /// (orange is 2.33:1 on Pond Mist, yellow 1.43:1; the ink is 15.9:1). In
    /// dark the fills clear the ground on their own and the outline reads as
    /// a crisp shadow. The thumb pad takes its own rim, which is the pad's only
    /// boundary in dark (the well is 1.18:1 on Night Pond; the rim is 5.25:1).
    public static func fillEdge(_ token: Token, in scheme: Scheme) -> RGB? {
        if token.isPressableFill || token == .stop {
            return color(.outline, in: scheme)
        }
        if token == .stickPad {
            return color(.stickPadRim, in: scheme)
        }
        return nil
    }

    /// The 3pt "toy button" lip under a pressable fill: a darker shade of the
    /// same hue. `nil` for anything that is not a pressable fill.
    public static func lip(_ token: Token, in scheme: Scheme) -> RGB? {
        let light = scheme == .light
        switch token {
        case .actionPrimary:
            return light ? beakShadow : RGB(hex: "#B84A00")
        case .actionYellow:
            return light ? RGB(hex: "#D99A00") : RGB(hex: "#B88200")
        case .actionTeal:
            return light ? RGB(hex: "#4FA3A4") : RGB(hex: "#3F8A8B")
        case .actionLavender:
            return light ? RGB(hex: "#8F70A3") : RGB(hex: "#7A5E8E")
        default:
            return nil
        }
    }

    /// The scheme's own ground, shorthand for `backgroundPrimary`, which is
    /// what nearly every contrast question is asked against.
    public static func ground(in scheme: Scheme) -> RGB {
        color(.backgroundPrimary, in: scheme)
    }

    /// Hue in degrees, `0..<360`, and HSV saturation in `0...1`. For the
    /// "Stop is the only red" rule, which is a claim about hue, not contrast.
    public static func hueAndSaturation(_ rgb: RGB) -> (hue: Double, saturation: Double) {
        let maxC = max(rgb.red, rgb.green, rgb.blue)
        let minC = min(rgb.red, rgb.green, rgb.blue)
        let delta = maxC - minC
        let saturation = maxC == 0 ? 0 : delta / maxC
        guard delta > 0 else { return (0, saturation) }
        var hue: Double
        if maxC == rgb.red {
            hue = 60 * ((rgb.green - rgb.blue) / delta)
        } else if maxC == rgb.green {
            hue = 60 * ((rgb.blue - rgb.red) / delta + 2)
        } else {
            hue = 60 * ((rgb.red - rgb.green) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue, saturation)
    }

    /// The shortest way round the hue circle between two colours, in degrees.
    public static func hueDistance(_ a: RGB, _ b: RGB) -> Double {
        let d = abs(hueAndSaturation(a).hue - hueAndSaturation(b).hue)
        return min(d, 360 - d)
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

    /// Corner radii, smallest to largest.
    ///
    /// CONCENTRIC CORNERS ARE THE REASON THIS IS AN ENUM rather than five
    /// loose constants. A card inside a card takes the next radius down — see
    /// `inner` — and the arithmetic that produces machined-looking nesting is
    /// "one step down the scale", not "minus four". Written as raw numbers at
    /// each call site, the nesting drifts within a release and the corners
    /// stop looking cut from one piece.
    public enum Radius: Double, CaseIterable, Sendable {
        /// 10, chips and tags. Chunky and soft, Pond Day's toy look.
        case chip = 10
        /// 16, buttons, fields, anything pressable that is not a capsule.
        case control = 16
        /// 22, cards.
        case card = 22
        /// 28, a group of cards.
        case group = 28
        /// 32, sheets.
        case sheet = 32

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
