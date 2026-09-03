import SwiftUI
import UIKit
import StudioKit

/// The pieces the app is assembled from, and the only place their shapes are
/// decided.
///
/// THIS FILE DRAWS AND DOES NOT COMPUTE, which is the same rule `Theme` follows
/// one layer up. There is no hex here and no contrast arithmetic: every colour
/// is a `Theme` token, so every one of these components inherits the guarantees
/// `PaletteTests` already proves — a word on a badge clears 4.5:1 because the
/// token it is set in clears 4.5:1 on every ground the app puts words on. A
/// component that reached for `Color(red:green:blue:)` would step outside that
/// proof, and nothing on the Mac build would say so.
///
/// WHY THESE SEVEN AND NOT A SCREEN'S WORTH. Each one is a place the app was
/// about to make the same decision twice: how a robot's state looks, what a
/// button that moves fourteen servos has to be, how a number that changes is
/// set beside a word that does not. Drawn twice, they drift within a release —
/// one badge with a dot and one with a coloured word, two button heights, two
/// ideas of what "connecting" looks like. Drawn once, the whole app changes
/// when this file does.
///
/// THE NUMBERS THAT ARE HERE ARE LAYOUT, NOT FACTS. Point sizes, stroke widths
/// and the fractions that shape the lens are decisions about how big to draw
/// something. The exceptions are called out where they sit: the touch targets
/// come from Apple's Human Interface Guidelines, and would move into `Palette`
/// the moment it grows a scale for them. The focus ring's geometry is gone from
/// here: the ring it described never drew on iOS, which `PrimaryActionStyle`
/// explains, and Full Keyboard Access draws the system's own.

// MARK: - the dimensions the palette does not carry

/// Sizes that belong to a control rather than to a colour.
///
/// NOT IN `Palette` BECAUSE `Palette` HAS NO SCALE FOR THEM YET, and inventing
/// one from the app side would put the design system in two files. They are
/// gathered here rather than scattered through the components so that there is
/// exactly one 44 and one 60 in the app, and so the next person can see at a
/// glance which numbers in this file are load-bearing.
///
/// INTERNAL, NOT PRIVATE. The first cut of this file kept these two enums to
/// itself, and the app answered by writing the numbers again: `DriveView`,
/// `DuckSoccerView`, `DuckStage` and `FindDuckView` each carried a copy of the
/// 60, the 44 or the press delta with a comment saying the original could not
/// be reached — a comment that was true, and that was the defect. The private
/// keyword was protecting a number from the screens whose whole job is to draw
/// it. Every screen-local metric enum now names these by reference, and the
/// claim above — one 44 and one 60 in the app — is a fact again rather than an
/// intention.
enum DesignMetric {
    /// 44pt — the smallest thing a finger is asked to hit.
    ///
    /// Source: Apple Human Interface Guidelines, Layout — "a minimum tappable
    /// area of 44x44 points for all controls". It is a floor and not a size:
    /// most buttons here are larger because their text makes them so.
    static let minimumTarget: CGFloat = 44

    /// 60pt — anything that MOVES THE ROBOT.
    ///
    /// A CONTROL THAT MOVES A MACHINE IS NOT AN ORDINARY CONTROL. The person
    /// pressing it is looking at the robot, not at the phone; the phone is
    /// being held one-handed, possibly while walking; and a miss does not
    /// produce a wrong screen, it produces a duck walking into a table leg. The
    /// HIG floor is sized for a person who is looking at what they are
    /// pressing. This one is not.
    static let movingTarget: CGFloat = 60

    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels — the thinnest line iOS will draw crisply.
    ///
    /// Named for the stroke rather than the scale because `Palette.Spacing`
    /// already has a `hairline` and it is four points. Two things called
    /// hairline that differ by 4x is how a rule ends up drawn at the width of a
    /// gap.
    static let hairlineStroke: CGFloat = 1

    /// How far a press darkens a filled control.
    ///
    /// A DELTA RATHER THAN A SECOND TOKEN. `Palette` has no pressed variant and
    /// should not gain one: a press is a moment, not a colour, and a hard-coded
    /// darker orange is a value that drifts the first time Duck Orange is
    /// re-specified. Brightness applies to whatever the token is, so it cannot
    /// drift. One number, so a button pressed on a paired controller, a football
    /// pad held under a thumb and a capsule tapped in a list all darken by the
    /// same amount — a press has to feel like one press everywhere in the app.
    static let pressDelta: Double = -0.12
}

/// The two colours in the app that must NOT follow the colour scheme.
///
/// A COLOUR WHOSE GROUND DOES NOT CHANGE MUST NOT CHANGE EITHER, and this is
/// the only place that rule bites. Nearly every token in `Theme` is adaptive
/// because nearly every colour sits on a ground that flips with the scheme.
/// These two sit on grounds that do not: Duck Orange is the same orange in both
/// schemes, and the lens iris is yellow in both. An adaptive colour on a fixed
/// ground is not adaptive, it is wrong half the time — `Theme.textPrimary` on a
/// Duck Orange capsule is charcoal at 6.76:1 in light and Warm Cream at 2.30:1
/// in dark, and the dark half is unreadable.
///
/// So these ask `Palette` for a token in ONE NAMED SCHEME. It is the only place
/// in the app that does, and the reason is written above rather than left to be
/// worked out from the call.
enum DesignFixed {
    /// What a label on a Duck Orange fill is set in, in both schemes.
    /// Mechanical Charcoal, 6.76:1 on the orange — the same number the palette
    /// documents for charcoal grounds, because contrast is symmetric.
    static var onAction: Color { Color(Palette.color(.textPrimary, in: .light)) }

    /// The lens's catchlight. The app's only pure white, and the one place
    /// white is allowed to be a mark rather than a surface.
    ///
    /// DECORATION IN SC 1.4.11'S EXACT SENSE: remove it and nothing is lost,
    /// because the lens's state is carried by the iris, by the ring's colour
    /// and — for anybody who cannot see either — by the accessibility label.
    /// It is 5.23:1 on the light scheme's yellow ink and 1.77:1 on Lens Yellow
    /// in dark, which is what a specular highlight should be: obvious on the
    /// dark eye, barely there on the bright one.
    static var catchlight: Color {
        Color(Palette.color(.surfaceElevated, in: .light))
    }
}

private extension Color {
    /// A `Palette.RGB` as a SwiftUI colour, in the colour space WCAG's formula
    /// assumes.
    ///
    /// `.sRGB` rather than `.sRGBLinear` and it is not a detail: the palette's
    /// channels are gamma-encoded — `relativeLuminance` linearises them itself
    /// before weighting — so handing them to SwiftUI as linear values would
    /// draw every one of them lighter than the number that was tested.
    init(_ rgb: Palette.RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue,
                  opacity: 1)
    }
}

// MARK: - 1. the state badge

/// What a robot can be, as far as the interface is concerned.
///
/// FOUR STATES AND A WORD FOR EACH. The colours are `Theme` tokens rather than
/// values, so the badge inherits the palette's guarantee that each of them
/// clears 4.5:1 on every ground the app sets words on — which matters because
/// each of them ends up on a word every time it ends up on a dot.
enum RobotState: String, CaseIterable, Sendable {
    /// Moving.
    case active
    /// Powered, and standing still.
    case idle
    /// Not there.
    case offline
    /// Looking for something — a sensor is working.
    case scanning

    /// The token this state is drawn in.
    var color: Color {
        switch self {
        case .active: return Theme.robotActive
        case .idle: return Theme.robotIdle
        case .offline: return Theme.robotOffline
        case .scanning: return Theme.sensorActive
        }
    }

    /// The state as a word, for anybody who is being read to rather than
    /// looking. Deliberately one word: it is a value, not a description.
    var spoken: String {
        switch self {
        case .active: return "Active"
        case .idle: return "Idle"
        case .offline: return "Offline"
        case .scanning: return "Scanning"
        }
    }
}

/// A dot AND a word, in a pill.
///
/// THE DOT IS NEVER ALLOWED OUT ALONE, and this component exists to make that
/// structurally true rather than a thing to remember. Roughly one man in twelve
/// cannot reliably separate the orange dot from the teal one, and the two
/// states they encode here are "this robot is moving" and "this robot is
/// standing still" — the single most consequential distinction the app draws.
/// SC 1.4.1 (Use of Colour) is the standard; the reason is the table leg.
///
/// THE PILL IS FURNITURE, AND ON A CARD IT IS FURNITURE NOBODY NEEDED. Its fill
/// is `surfacePrimary` and its edge is a hairline — which is exactly the fill a
/// card is drawn in, so a badge sitting on one was a capsule of the card's own
/// colour on the card, and all that was actually visible was the rim: a second
/// corner radius, at a curve nobody picked, inside a corner that was. The
/// palette's grounds are within about 1.1:1 of each other by design, so a chip
/// on this system can never announce itself with a fill and should not try.
///
/// OVER A RENDERED PICTURE IT IS LOAD-BEARING AND STAYS. On the stage panels the
/// badge sits in a column of live readings above a moving render, and the pill
/// is what says the dot and the word are one value rather than two lines that
/// happen to be adjacent — the same argument those panels make for being opaque
/// rather than `.thinMaterial`. Hence `Ground`, said by the caller: only the
/// caller knows what is behind it.
///
/// WHAT THE INFORMATION IS DID NOT CHANGE. It is the dot AND the word, in both
/// grounds. `Ground` moves furniture; it never takes away the word.
struct StateBadge: View {
    /// What is behind the badge, which decides whether it needs a pill.
    ///
    /// `card` IS THE DEFAULT BECAUSE IT IS THE SAFE ONE. A badge that should
    /// have said `render` and did not loses a rim over a picture; a badge that
    /// should have said `card` and did not draws a second corner on a card
    /// forever, because it looks deliberate. Defaulting to the plain form makes
    /// the decorated one something a caller had to ask for.
    enum Ground {
        /// On one of the palette's surfaces — a card, a form row, a list row,
        /// or one of the opaque readout panels. The pill would be the ground's
        /// own colour, so there is no pill.
        case card
        /// In a readout that reads as part of a rendered stage or venue, where
        /// the pill separates one value from the column around it.
        case render
    }

    /// The word beside the dot. The caller's, not this component's — a screen
    /// that has a better word than "Idle" for a particular robot should use it.
    let text: String
    let state: RobotState
    var ground: Ground = .card

    /// ONLY WHEN IT ADDS SOMETHING, AND "NOTHING" HAS TO MEAN NO MODIFIER.
    /// This was `.accessibilityValue(Text(spokenValue ?? ""))`, and an empty
    /// string is not the absence of a value: the element still declares one,
    /// and it declares that the value is nothing. What VoiceOver does with an
    /// empty value is not something this machine can be made to demonstrate —
    /// there is no Simulator on it — so the argument is not about the sound. It
    /// is that the accessibility tree should say what is true. A badge whose
    /// word already IS the state has no value to give, that is the common case,
    /// and the branch below is the only way SwiftUI spells "do not attach this
    /// modifier".
    var body: some View {
        if let spokenValue = spokenValue {
            pill.accessibilityValue(Text(spokenValue))
        } else {
            pill
        }
    }

    /// The dot, the word, and — over a render — the capsule that says they
    /// belong together.
    ///
    /// THE PADDING GOES WITH THE CAPSULE, because it only ever existed to inset
    /// the dot from a capsule edge. Left behind on `.card` it becomes an indent
    /// with nothing drawing it: the badge starts a `snug` further in than every
    /// `TelemetryRow` under it in the same card, and a column of labels with one
    /// item nudged right reads as a mistake rather than as a chip.
    private var pill: some View {
        let dot = HStack(spacing: Theme.spacing(.hairline)) {
            Circle()
                .fill(state.color)
                .frame(width: Theme.spacing(.tight),
                       height: Theme.spacing(.tight))
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(state.color)
        }
        return Group {
            switch ground {
            case .card:
                dot
            case .render:
                dot
                    .padding(.horizontal, Theme.spacing(.snug))
                    .padding(.vertical, Theme.spacing(.hairline))
                    .background(Capsule().fill(Theme.surfacePrimary))
                    .overlay(
                        Capsule().strokeBorder(Theme.separator,
                                               lineWidth: DesignMetric.hairlineStroke))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }

    /// The state as a word, or nothing when the caller's word already is the
    /// state — the common case, where announcing both reads as "Idle, idle",
    /// which is how a screen reader user learns to stop trusting values.
    private var spokenValue: String? {
        text.compare(state.spoken, options: .caseInsensitive) == .orderedSame
            ? nil
            : state.spoken
    }
}

// MARK: - 2. the primary action

/// The button a person presses to make something happen.
///
/// PRESSED DARKENS AND NEVER SCALES, which is the whole reason this is a style
/// and not a modifier somebody applies when they remember to. SwiftUI's own
/// pressed treatment, and every third-party one, shrinks the control under the
/// thumb. On a screen that stops a robot that is the wrong behaviour twice
/// over: the target moves out from under a finger that is already committed to
/// it, and it moves at the exact moment the person is least able to look at the
/// phone — they are watching the machine. A control that is driving hardware
/// stays exactly where it was drawn. It gets darker instead, which is a change
/// a person sees in peripheral vision without having to aim again.
///
/// DISABLED STAYS LEGIBLE. The usual half-opacity treatment takes a label to
/// roughly 2:1 and makes "why can't I press this" unanswerable. Here a disabled
/// button keeps a real surface (`surfaceInteractive`, which the palette
/// guarantees as a ground for words) and real secondary text on it at 6.89:1 in
/// light and 8.46:1 in dark. It reads as unavailable because it has lost the
/// action colour, not because it has been faded out.
///
/// IT FIRES NO HAPTIC. A press is a tap, and `Haptic` is for events in the
/// world — see the note there.
///
/// FOCUS IS THE SYSTEM'S RING, AND THIS FILE NO LONGER PRETENDS OTHERWISE.
/// There was a hand-drawn one here — three points of `Theme.focus`, two points
/// clear of the capsule, gated on `@Environment(\.isFocused)` — with a doc
/// comment citing SC 2.4.11 by number. On iOS a plain `Button` does not put
/// that value into its style's body: `isFocused` reports on a focusable
/// ancestor, and the environment a `ButtonStyle` is handed is not one. So the
/// ring almost certainly never drew, on any screen, for anybody. The wasted
/// code is the small half of that. The large half is that a design system
/// claimed an accessibility feature it did not have, in prose confident enough
/// that nobody would go looking — and a claim like that is worse than the
/// omission it hides, because it stops the omission being found.
///
/// WHAT ACTUALLY INDICATES FOCUS IS FULL KEYBOARD ACCESS, which draws its own
/// ring around whatever it has landed on, in every app on the phone, in the
/// shape and colour the person has set in Settings. That is the indicator a
/// keyboard or switch user already has here. Drawing a second one on top would
/// not add contrast; it would put a different-looking focus treatment on the
/// handful of controls that happened to use this style and leave every other
/// control in the app with the platform's — which teaches nobody anything and
/// costs somebody the one visual convention they can rely on.
///
/// `Palette.focus` STAYS, and it is not orphaned by this. It is teal ink at
/// 4.62:1 in light because brand teal is 1.74:1 on cream, and it is the colour
/// the app takes for any indicator it genuinely has to draw itself — a mark on
/// a canvas, an overlay on the AR view, somewhere iOS has nothing to say. A
/// button is not one of those places.
struct PrimaryActionStyle: ButtonStyle {

    /// How far the control has to be reachable by somebody who is not looking
    /// at it.
    enum Reach {
        /// The HIG floor. Everything that changes the app.
        case standard
        /// Everything that changes the ROBOT.
        case moves

        var minimum: CGFloat {
            switch self {
            case .standard: return DesignMetric.minimumTarget
            case .moves: return DesignMetric.movingTarget
            }
        }

        var horizontalPadding: Palette.Spacing {
            switch self {
            case .standard: return .loose
            case .moves: return .section
            }
        }

        var verticalPadding: Palette.Spacing {
            switch self {
            case .standard: return .snug
            case .moves: return .standard
            }
        }
    }

    var reach: Reach = .standard

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, reach: reach)
    }

    /// A nested `View` rather than the style itself, because `@Environment`
    /// only resolves inside a view. A `ButtonStyle` is not one, so a style that
    /// needs to know whether it is enabled, or in dark mode, has to hand its
    /// body to something that is.
    ///
    /// AND THAT IS EXACTLY AS FAR AS IT GOES. Being inside a view makes an
    /// environment value readable; it does not make one meaningful. The ring
    /// this file used to draw read `\.isFocused` here and got `false` forever,
    /// which is the difference between "the code compiles" and "the code is
    /// told anything".
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let reach: Reach

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            configuration.label
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(isEnabled ? DesignFixed.onAction : Theme.textSecondary)
                .padding(.horizontal, Theme.spacing(reach.horizontalPadding))
                .padding(.vertical, Theme.spacing(reach.verticalPadding))
                .frame(minWidth: reach.minimum, minHeight: reach.minimum)
                .background(fill)
                .overlay(edge)
                .contentShape(Capsule())
        }

        /// The capsule, darkened while held by `DesignMetric.pressDelta`, which
        /// says why it is a delta and not a second token. It is applied to the
        /// fill alone — the label keeps its own colour, because darkening the
        /// pair together would move the contrast between them.
        private var fill: some View {
            Capsule()
                .fill(isEnabled ? Theme.actionPrimary : Theme.surfaceInteractive)
                .brightness(configuration.isPressed ? DesignMetric.pressDelta : 0)
        }

        /// The rim a Duck Orange fill needs in light so its EDGE is findable.
        ///
        /// Orange is 2.30:1 on Warm Cream, below the 3:1 SC 1.4.11 asks of a
        /// control's boundary, so the shape borrows an edge rather than the
        /// fill being darkened out of the brand. `Theme.actionPrimaryEdge`
        /// returns nil in dark, where orange is 7.12:1 on the ground and needs
        /// nothing. A disabled button takes the separator instead: it is not a
        /// control that can be operated, and 1.4.11 exempts those.
        @ViewBuilder private var edge: some View {
            if !isEnabled {
                Capsule().strokeBorder(Theme.separator, lineWidth: DesignMetric.hairlineStroke)
            } else if let rim = Theme.actionPrimaryEdge(scheme) {
                Capsule().strokeBorder(rim, lineWidth: DesignMetric.hairlineStroke)
            }
        }
    }
}

extension ButtonStyle where Self == PrimaryActionStyle {
    /// The action colour, at the HIG's 44pt floor.
    static var primaryAction: PrimaryActionStyle {
        PrimaryActionStyle(reach: .standard)
    }

    /// The action colour at 60pt, for a control that moves the robot.
    static var primaryActionMoves: PrimaryActionStyle {
        PrimaryActionStyle(reach: .moves)
    }
}

// MARK: - 3. the lens

/// The eye: a ring, a yellow iris and one catchlight.
///
/// CONNECTING IS A ROBOT WAKING, NOT A SPINNER. A spinner says "the software is
/// busy" — a claim about this phone. What is actually happening is that
/// something across the room is being reached, and the honest picture of that
/// is an eye opening. The iris narrows to a slit while the link is being made
/// and OPENS on the one spring when it is, so the moment of connection is a
/// thing you see happen rather than a spinner that stops.
///
/// THE MOTION IS THE FIRST THING REDUCE MOTION TAKES. The person may be
/// watching a real robot at the same time as this screen, and somebody who has
/// turned the setting on has said so. With it on there is no pulse at all and
/// the states cross-fade in 120ms; the picture still changes, it just stops
/// moving.
///
/// THE LABEL IS NOT OPTIONAL. Everything this component says, it says in shape
/// and colour, so without a label it says nothing at all to VoiceOver. The
/// three words are fixed here rather than passed in, because they are what the
/// picture means.
struct LensIndicator: View {

    /// What the eye is doing.
    enum Connection: Equatable {
        /// Nothing is there. The eye is closed.
        case asleep
        /// Reaching for something. The iris pulses narrow.
        case connecting
        /// Reached. The iris is open.
        case connected

        /// The state in one word, for anybody being read to.
        var spoken: String {
            switch self {
            case .asleep: return "Asleep"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            }
        }

        /// The ring — the lens barrel. Teal is the connection accent; a lens
        /// with nothing behind it takes the offline grey instead.
        var ring: Color {
            switch self {
            case .asleep: return Theme.robotOffline
            case .connecting, .connected: return Theme.brandPrimary
            }
        }

        /// The iris. Yellow is the eye; a closed one is grey.
        var iris: Color {
            switch self {
            case .asleep: return Theme.robotOffline
            case .connecting, .connected: return Theme.sensorActive
            }
        }

        /// How much of the lens the iris fills. A slit, a half, and open —
        /// proportions of the ring's inner diameter rather than point sizes, so
        /// the lens is the same eye at every size it is drawn at.
        var aperture: CGFloat {
            switch self {
            case .asleep: return 0.16
            case .connecting: return 0.38
            case .connected: return 0.72
            }
        }
    }

    let state: Connection

    /// The lens is drawn at the size it is given. The default is an inline
    /// indicator; an avatar is the same eye, larger.
    var size: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the connecting breath, and nothing else.
    ///
    /// A STORED FLAG RATHER THAN A DERIVED ONE, because SwiftUI does not
    /// animate a view's first appearance: a value that is already `true` when
    /// the view is built has never changed, so there is nothing for
    /// `.animation(_:value:)` to attach a repeating animation to. Flipping it
    /// in `onAppear` is what starts the breath.
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(state.ring, lineWidth: ringWidth)
            irisDisc
        }
        .frame(width: size, height: size)
        .animation(Theme.motion(reduced: reduceMotion), value: state)
        .onAppear { breathing = shouldBreathe }
        .onChange(of: state) { _, _ in breathing = shouldBreathe }
        .onChange(of: reduceMotion) { _, _ in breathing = shouldBreathe }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.spoken))
    }

    /// The iris, with its one catchlight.
    ///
    /// THE APERTURE AND THE BREATH ARE TWO SEPARATE ANIMATIONS ON PURPOSE. The
    /// frame carries the state — a slit, a half, an open eye — and the scale
    /// carries the breath. Folding them into one diameter would hand
    /// `repeatForever` the transition between two states as its endpoints, so
    /// an eye that had just been open would pulse all the way from open to slit
    /// forever rather than breathing around the aperture it is actually at.
    ///
    /// UNDER REDUCE MOTION IT IS REPLACED RATHER THAN RESIZED. The `.id` makes
    /// each state a different view, so SwiftUI cross-fades one out and the next
    /// in over `Theme.reducedMotion` instead of animating a diameter. Without
    /// it, "reduced motion" would still be a shape changing size — less motion
    /// is not the same as none.
    private var irisDisc: some View {
        let diameter = size * state.aperture

        return Circle()
            .fill(state.iris)
            .overlay(catchlight(on: diameter), alignment: .topLeading)
            .frame(width: diameter, height: diameter)
            .scaleEffect(breathing ? breathScale : 1)
            .animation(breath, value: breathing)
            .id(reduceMotion ? AnyHashable(state.spoken) : AnyHashable(0))
            .transition(.opacity)
    }

    /// One highlight, up and to the left, where a light source in front of and
    /// above the robot would put it. Sized and placed as fractions of the iris
    /// so it stays a catchlight when the eye opens instead of a second pupil.
    private func catchlight(on diameter: CGFloat) -> some View {
        Circle()
            .fill(DesignFixed.catchlight)
            .frame(width: diameter * 0.28, height: diameter * 0.28)
            .padding(.leading, diameter * 0.18)
            .padding(.top, diameter * 0.16)
    }

    /// Whether the eye should be breathing at all: only while it is reaching
    /// for something, and never when the person has asked for less movement.
    private var shouldBreathe: Bool { state == .connecting && !reduceMotion }

    /// How far the iris narrows on the in-breath.
    private var breathScale: CGFloat { 0.78 }

    /// The app's one spring, repeating while the eye is reaching and settling
    /// once when it stops — so the breath ends by opening rather than by being
    /// cut off mid-cycle.
    private var breath: Animation {
        breathing
            ? Theme.spring.repeatForever(autoreverses: true)
            : Theme.motion(reduced: reduceMotion)
    }

    /// The barrel's thickness, as a fraction of the lens. A fixed point width
    /// would make a large lens look like a thin ring and a small one look
    /// solid.
    private var ringWidth: CGFloat { max(DesignMetric.hairlineStroke, size * 0.08) }
}

// MARK: - 4. the bill

/// A flat orange bar: one end squared, one rounded, always horizontal.
///
/// THE BILL IS THE APP'S ONE POINTING GESTURE. It marks the selected tab and it
/// fills a slider, and both of those are the same statement — "this much, from
/// here". The squared end is where the bar is attached to something and the
/// rounded end is where it stops, which is why it never appears vertically:
/// a duck's bill has an orientation and a rotated one reads as a progress bar
/// from a different app.
///
/// IT TAKES AN EDGE IN LIGHT for the same reason the action button does. Duck
/// Orange is 2.30:1 on Warm Cream, so an unbordered orange bar on the light
/// ground is a shape whose boundary somebody with low vision cannot locate
/// (SC 1.4.11); `Theme.actionPrimaryEdge` supplies a hairline of orange ink,
/// and returns nil in dark where the orange stands on its own at 7.12:1.
///
/// HIDDEN FROM VOICEOVER UNLESS IT IS GIVEN A LABEL, which is a decision and
/// not a default. As a selection marker it sits beside a tab that already says
/// its own name, and as a slider fill it sits inside a control that already
/// reports its value; announcing it in either case adds an unnamed graphic to
/// the rotor. A caller that puts a bill somewhere it stands alone passes a
/// label and gets one.
struct BillIndicator: View {
    /// How much of the offered width the bill takes, 0...1. A selection marker
    /// leaves this at 1; a slider fill drives it.
    var fill: Double = 1

    /// The bar's thickness. Four points — the smallest step on the spacing
    /// scale — because the bill is a mark and not a bar chart.
    var thickness: CGFloat = Theme.spacing(.hairline)

    /// A label, when the bill is the only thing saying what it says.
    var label: String? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            shape
                .fill(Theme.actionPrimary)
                .overlay(edge)
                .frame(width: proxy.size.width * clamped,
                       height: thickness)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: thickness)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(Text(label ?? ""))
    }

    /// Squared at the leading end, rounded at the trailing one. The radius is
    /// half the thickness, which is what makes the rounded end a half-circle
    /// rather than a soft corner.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0,
                               bottomLeadingRadius: 0,
                               bottomTrailingRadius: thickness / 2,
                               topTrailingRadius: thickness / 2,
                               style: .continuous)
    }

    @ViewBuilder private var edge: some View {
        if let rim = Theme.actionPrimaryEdge(scheme) {
            shape.strokeBorder(rim, lineWidth: DesignMetric.hairlineStroke)
        }
    }

    private var clamped: CGFloat { CGFloat(min(max(fill, 0), 1)) }
}

// MARK: - 5. the joint

/// The servo horn: a dark disc inside a quieter collar, sized by load.
///
/// SIZE ENCODES LOAD BECAUSE COLOUR CANNOT. A row of joints is exactly the
/// situation where a colour ramp fails — six or fourteen small marks, no legend
/// beside any of them, and the reader is being asked to compare them to each
/// other rather than to a key. Size is comparable at a glance and survives
/// every form of colour blindness, and the load is in the accessibility value
/// in words for anybody not looking at all.
///
/// "LIGHTER COLLAR" MEANS QUIETER, NOT PALER, and the distinction is what
/// survives dark mode. In light the hub is charcoal inside a grey collar,
/// exactly as the motif describes. In dark the hub is cream and the collar is
/// still the tertiary grey — so the hub is the *lighter* of the two. What is
/// constant, and what the motif is actually about, is that the hub is the
/// strongest mark against the ground and the collar is a step back from it.
struct JointNode: View {
    /// 0 is free, 1 is against the stop. Values outside are clamped rather than
    /// trusted: a joint reporting 1.4 is a bug somewhere else, and a node four
    /// times the size of its neighbours would read as a finding.
    let load: Double

    /// Which joint this is. VoiceOver needs a name to attach the value to, and
    /// a screen with fourteen nodes on it needs fourteen different ones.
    var label: String = "Joint"

    var body: some View {
        Circle()
            .fill(Theme.textTertiary)
            .overlay(
                Circle()
                    .fill(Theme.textPrimary)
                    .padding(collar)
            )
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(spoken))
    }

    /// Sixteen points free, twenty-four against the stop — two steps of the
    /// spacing scale, so a joint at load never lands on a size the rest of the
    /// layout does not use.
    private var diameter: CGFloat {
        let free = Theme.spacing(.standard)
        let loaded = Theme.spacing(.loose)
        return free + (loaded - free) * CGFloat(clamped)
    }

    /// The collar's thickness. A fraction rather than a fixed width, so the
    /// hub grows with the node instead of the ring getting proportionally
    /// thinner as load rises.
    private var collar: CGFloat { diameter * 0.22 }

    /// THREE BANDS AND A STOP. The thirds are a presentation scale in the same
    /// sense as a battery icon's bars — they are how many words are useful
    /// while glancing, not a claim about the servo. The stop is the exception
    /// and is the top of the range exactly, because "at its stop" is the one
    /// thing here that is a fact rather than a band.
    private var spoken: String {
        if clamped >= 1 { return "At its stop" }
        if clamped <= 0 { return "No load" }
        if clamped < 1.0 / 3.0 { return "Light load" }
        if clamped < 2.0 / 3.0 { return "Moderate load" }
        return "Heavy load"
    }

    private var clamped: Double { min(max(load, 0), 1) }
}

// MARK: - 6. the telemetry row

/// A label that does not change, beside a number that does.
///
/// MONOSPACE IS A CLAIM, AND THE CLAIM IS "THIS WILL CHANGE". If it never
/// changes, it is not telemetry — a name, a status word or a serial set in
/// tabular figures tells the reader to watch a thing that is never going to
/// move. So the label is SF and only the value is mono, which is also what
/// stops the digits from jittering: tabular figures are the same width, so
/// 0.09 replaced by 0.11 does not shift the row.
///
/// AT ACCESSIBILITY SIZES IT REFLOWS RATHER THAN TRUNCATING. Two columns of
/// text at AX5 is a fight for the width that one of them has to lose, and the
/// one that loses is always the value, because it is on the right — which is to
/// say that the app hides the number from the people who most enlarged it in
/// order to read it. Stacked, the label and the value each get the whole width
/// and nothing is dropped.
struct TelemetryRow: View {
    /// What the number is. Never mono.
    let label: String

    /// The number, already formatted. Formatting belongs to whoever knows what
    /// the quantity is; this component knows only that it changes.
    let value: String

    /// Degrees, volts, milliseconds. Empty for a unitless value.
    var unit: String = ""

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The body text style's point size at the person's current setting.
    ///
    /// SEVENTEEN IS THE DEFAULT AND `@ScaledMetric` IS WHY IT IS SAFE TO WRITE.
    /// `UIFont.preferredFont(forTextStyle: .body).pointSize` is 17 at the
    /// default content size; the wrapper scales it from there with whatever the
    /// person has set, and — unlike reading `UIFont` directly — it honours a
    /// `dynamicTypeSize` override placed in the environment by a parent view,
    /// which is how the reflow below can be exercised at all.
    @ScaledMetric(relativeTo: .body) private var valuePointSize: CGFloat = 17

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    labelText
                    valueText
                }
            } else {
                HStack(alignment: .firstTextBaseline,
                       spacing: Theme.spacing(.tight)) {
                    labelText
                    Spacer(minLength: Theme.spacing(.tight))
                    valueText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken))
    }

    private var labelText: some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The number, with its unit at half the number's size.
    ///
    /// THE UNIT IS SUBORDINATE ON PURPOSE. It is the part of the pair that
    /// never changes, and at the same size it competes with the digits for the
    /// glance. Half is small enough to recede and large enough to stay legible
    /// at every Dynamic Type size, because it is derived from the value's size
    /// rather than pinned to a caption style that stops growing.
    private var valueText: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.hairline) / 2) {
            Text(value)
                .font(.system(size: valuePointSize, design: .monospaced)
                    .monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: valuePointSize / 2, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var spoken: String {
        unit.isEmpty ? value : "\(value) \(unit)"
    }
}

// MARK: - 7. haptics

/// The feedback the phone gives for things that happen in the WORLD.
///
/// NOTHING HERE FIRES ON A TAP. That is the entire design of this namespace,
/// and it is why every function is named after an event rather than after a
/// gesture: there is no `Haptic.tap()`, no `Haptic.selection()` and nothing for
/// a tab change, because a phone that buzzes when you touch it is telling you
/// what you already know — your own finger did that. The taptic engine is the
/// only channel this app has to something that is happening across the room
/// while the person is looking at the robot and not at the glass, and spending
/// it on scroll and selection is how it stops being noticed.
///
/// THE MAPPING IS THE BRIEF'S. Success on connect and on finish; a medium
/// impact when a behaviour starts, because something began to move; a rigid
/// impact at a stick's limit or a joint's stop, because a rigid tap is what
/// hitting a wall feels like; warning when the link is lost; error when the
/// robot falls. Nothing else is added: a vocabulary of five feelings is one a
/// person can learn, and a vocabulary of twelve is noise.
///
/// MAIN-ACTOR BECAUSE UIKit IS. Every generator here touches the taptic engine
/// through UIKit, which is main-thread-only, and a haptic fired from a network
/// callback is exactly where that goes wrong.
@MainActor
enum Haptic {

    /// A robot answered.
    static func connected() { notify(.success) }

    /// Something the person asked for ran to the end.
    static func finished() { notify(.success) }

    /// A behaviour started — something is now moving.
    static func behaviourStarted() { impact(medium) }

    /// The stick is against its limit; pushing further will not do more.
    static func stickAtLimit() { impact(rigid) }

    /// A joint reached its stop.
    static func jointAtStop() { impact(rigid) }

    /// The link went away on its own.
    static func linkLost() { notify(.warning) }

    /// The robot fell.
    static func fell() { notify(.error) }

    /// Warms the taptic engine, for a screen that is about to be able to
    /// produce these events.
    ///
    /// WITHOUT IT THE FIRST HAPTIC OF A SESSION IS LATE. The engine spins up on
    /// demand, and the delay is long enough that the first tap of a run arrives
    /// after the thing it is about — which teaches the person that the buzz and
    /// the event are unrelated, and that is not a lesson a later `prepare()`
    /// can undo.
    static func prepare() {
        notifier.prepare()
        medium.prepare()
        rigid.prepare()
    }

    // MARK: the generators

    /// Retained rather than made per call, because a generator created at the
    /// moment of use has not had time to prepare and produces a weaker, later
    /// tap than the same call a second time.
    private static let notifier = UINotificationFeedbackGenerator()
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    private static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        notifier.notificationOccurred(kind)
        // Re-prepared straight away: a run that connects, finishes and
        // reconnects should feel the same every time, not weaker after the
        // first.
        notifier.prepare()
    }

    private static func impact(_ generator: UIImpactFeedbackGenerator) {
        generator.impactOccurred()
        generator.prepare()
    }
}

// MARK: - the heading over a section

/// A section's heading, in the design system rather than in the platform's.
///
/// THE DEFAULT WAS A CONTRAST FAILURE AND NO TEST COULD SEE IT. A bare `Text`
/// in a grouped list header takes the system's secondary label — about 3.18:1
/// on the light ground a list sits on, short of the 4.5:1 SC 1.4.3 asks of
/// body text — and because the colour comes from UIKit rather than from a
/// token, `PaletteTests` never had a chance to run the formula over it.
/// `textTertiary` is a token, and it is the one the palette measures at 4.59:1
/// on `backgroundSecondary`: it clears the bar on the recessed ground these
/// headings sit on, which the four inks as a family do not.
///
/// THIRTEEN POINTS, BOLD, SIX PER CENT OF TRACKING — the brand sheet's heading,
/// with the size as a `@ScaledMetric` so a heading is not the smallest thing on
/// the screen once somebody has enlarged type, and the tracking derived from
/// whatever size that lands on, because six per cent of 13 is not six per cent
/// of 30. `.textCase(nil)` because SwiftUI upper-cases grouped headers by
/// default and "STOP AND RESET" is a louder app than this one.
///
/// ONE COPY. Three screens carried a private, byte-identical one each while
/// this file was not theirs to edit; it lives here now, beside the other
/// pieces, for the reason this file gives everywhere — drawn twice, they drift
/// within a release.
///
/// AND NOW EVERY HEADING IN THE APP IS THIS ONE. `scripts/check_section_headings.sh`
/// counts the two spellings that ask for the platform's header instead —
/// `Section("Name")` and a bare `Text` in a `header:` closure — and it counted
/// 87 before the migration and 0 after. There is exactly one exception and it is
/// listed by the guard rather than hidden from it: `CommunityPoliciesView`'s
/// repository header is an `HStack` of a monospaced address and an origin pill,
/// which is a header carrying two things a plain heading cannot hold.
///
/// `.headerProminence(.increased)` IS STILL SET AT THE ROOT AND IS NOW A NO-OP.
/// It exists in `Theme.swift` — another owner's file, deliberately not touched
/// here — to lift the bare headers out of a 3.18:1 contrast failure, and there
/// are no bare headers left to lift: a header that sets its own font and colour
/// keeps them. Its own comment says "some sixty of them are still plain `Text`",
/// which is no longer true. Removing the modifier and correcting that comment is
/// the owner of `Theme.swift`'s call, not this file's.
struct SectionHeading: View {
    let text: String

    /// The `.footnote` point size at the person's current setting; 13 is what
    /// that style measures at the default content size.
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .tracking(size * 0.06)
            .textCase(nil)
            .foregroundStyle(Theme.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - the caption over a picture

/// A sentence set ON a stage, over whatever the stage is drawing.
///
/// LIFTED OUT OF `DriveView.floorCaption`, WHICH HAD THE ONLY ONE. That screen
/// is the one that already got this right — it draws the readback and captions
/// the picture when there is no readback to draw — and the second screen that
/// needed the same box was about to be a hand-copy of it, which is the drift
/// this file exists to stop. Same font, same two-line ceiling, same backing,
/// same card radius, same untappable.
///
/// TWO LINES, AND THE CEILING IS LOAD-BEARING. Build 41 shipped a legend that
/// covered the duck: a caption over a 340-point viewport is a caption that can
/// hide the thing it is captioning. Two lines of `.caption2` is what fits over
/// a picture without becoming the picture.
///
/// NOT `.accessibilityHidden`, BECAUSE IT MAKES A CLAIM. Every sentence this
/// box carries says which world is being drawn, which is exactly the fact a
/// person who cannot see the picture most needs. It is not hit-testable, so
/// the caller mirrors it as a row as well.
///
/// IT DOES NOT PLACE ITSELF. Where a caption goes depends on what else is on
/// the picture — the drive stage keeps its bottom corner, the player's bottom
/// 76 points belong to `StageLegend` — so the caller frames and pads it.
struct StageCaptionBox: View {
    let text: String

    /// How opaque the card under the words is.
    ///
    /// 0.85 AND NOT 1: the picture goes on behind it, so the caption reads as
    /// something laid on the stage rather than a panel bolted beside it, and
    /// the words still clear their contrast because the backing is a surface
    /// token rather than a tint.
    static let backing = 0.85

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(2)
            .padding(Theme.spacing(.hairline))
            .background(Theme.surfacePrimary.opacity(Self.backing),
                        in: RoundedRectangle(cornerRadius: Theme.radius(Palette.Radius.card),
                                             style: .continuous))
            // A CAPTION IS NOT A CONTROL. The pictures this sits on are all
            // draggable — the camera orbits under a finger — and a caption
            // that swallowed the drag would make the stage feel broken in the
            // one corner a person is most likely to touch first.
            .allowsHitTesting(false)
    }
}

// MARK: - a value that may not exist

extension View {
    /// An accessibility value, attached only when there is one.
    ///
    /// AN EMPTY STRING IS NOT THE ABSENCE OF A VALUE. `.accessibilityValue(
    /// Text(x ?? ""))` still declares that the element HAS a value and that the
    /// value is nothing — VoiceOver pauses on it, Switch Control lists it, and
    /// a screen-reader user learns that this app's values are noise. `StateBadge`
    /// was rewritten to branch on `if let` for exactly this; then the same
    /// pattern was written again one file over. This is the branch, as a
    /// modifier, so the rule is one call rather than a shape to remember.
    @ViewBuilder
    func accessibilityValue(ifPresent value: String?) -> some View {
        if let value, !value.isEmpty {
            accessibilityValue(Text(value))
        } else {
            self
        }
    }
}
