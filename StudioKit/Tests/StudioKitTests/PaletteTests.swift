import XCTest
@testable import StudioKit

/// The design system, checked against the formula it claims to satisfy.
///
/// THIS IS THE REASON THE PALETTE IS IN STUDIOKIT AT ALL. A colour token in a
/// SwiftUI file is an assertion nobody can check: "orange on cream is fine"
/// looks true on a bright screen in a dark room, and the person it is not fine
/// for is not in the room. Here every claim the brief makes is arithmetic on
/// two hex triples, and `swift test` on Linux either agrees or fails the
/// build.
///
/// THREE KINDS OF TEST LIVE HERE, and the middle one is the unusual one:
///
///   1. Requirements. Every token that sets words clears 4.5:1 on every ground
///      words are set on, in both schemes. Iterated over the enum, never
///      listed by hand — a hand-written list is a list somebody adds a token
///      without. Where a pair is exempt, the exemption is a named entry with
///      its measured ratio beside it and not a token quietly left out of the
///      loop: leaving one out is how the recessed ground came to be skipped by
///      the test whose name says it checks every ground.
///   2. Pinned FAILURES. The four brand accents must stay illegible on cream,
///      and the values the brief originally specified for tertiary text and
///      the focus ring must stay below their bars. These are what say no to
///      the tempting fix: lighten the cream, or "restore" the brand teal to
///      the focus ring, and a test names the number that made it wrong.
///   3. Structure. The inks hit their documented ratios to two decimals, the
///      scales are scales, and no light-mode text token is a raw brand colour.
final class PaletteTests: XCTestCase {

    // The two brand grounds, spelled out rather than fetched, so that a test
    // about Warm Cream keeps testing Warm Cream even if a token moves.
    private let cream = Palette.RGB(hex: "#F6F0E4")
    private let charcoal = Palette.RGB(hex: "#111A1D")

    private var brandAccents: [(name: String, colour: Palette.RGB)] {
        [("Duck Orange", Palette.duckOrange),
         ("Lavender", Palette.microduckLavender),
         ("Microduck Teal", Palette.microduckTeal),
         ("Lens Yellow", Palette.lensYellow)]
    }

    /// Two decimals, the way the brief quotes a ratio.
    private func rounded(_ ratio: Double) -> Double {
        (ratio * 100).rounded() / 100
    }

    // MARK: - 1. the requirement

    /// EVERY TOKEN THAT SETS WORDS CLEARS 4.5:1, ON BOTH GROUNDS, IN BOTH
    /// SCHEMES. WCAG 2.1 SC 1.4.3.
    ///
    /// Iterated over `Token.allCases` on purpose: the value of this test is
    /// entirely in what it will say about a token that does not exist yet.
    func testEveryTextTokenIsLegibleOnTheBackgroundAndOnTheSurface() {
        for scheme in Palette.Scheme.allCases {
            for token in Palette.Token.allCases where token.isText {
                for ground in [Palette.Token.backgroundPrimary, .surfacePrimary] {
                    let ratio = Palette.contrast(token, on: ground, in: scheme)
                    XCTAssertGreaterThanOrEqual(
                        ratio, Palette.textContrastMinimum,
                        """
                        \(token.rawValue) on \(ground.rawValue) in \(scheme.rawValue) \
                        is \(rounded(ratio)):1 — body text owes 4.5:1. \
                        \(Palette.color(token, in: scheme).hexString) on \
                        \(Palette.color(ground, in: scheme).hexString).
                        """)
                }
            }
        }
    }

    /// AND ON EVERY OTHER GROUND WORDS ACTUALLY LAND ON — the elevated surface
    /// a sheet is drawn on, and the pale wash under a selected row.
    ///
    /// THIS IS THE TEST THAT CAUGHT THE DARK TERTIARY. #7E8E94 clears the dark
    /// background at 5.48:1 and the primary surface at 4.94:1, and then lands
    /// at 4.45:1 on `surfaceElevated` — which is where a tertiary label most
    /// often is, because sheets and raised cards are where the secondary
    /// information goes. A pass that only checks the background is a pass that
    /// checks the easiest case.
    ///
    /// IT USED TO SKIP THE RECESSED GROUND ENTIRELY, and it read as though it
    /// did not. `isTextGround` left `backgroundSecondary` out, so the loop
    /// covered four grounds while claiming "every ground words are set on" —
    /// and the recessed ground is precisely the one the palette already knew
    /// was short. It is in the set now, and the pairs that fall short of the
    /// bar there are named one by one in the next test rather than skipped by a
    /// classification nobody would think to question.
    func testEveryTextTokenIsLegibleOnEveryGroundWordsAreSetOn() {
        for scheme in Palette.Scheme.allCases {
            for ground in Palette.Token.allCases
            where ground.isTextGround && ground.takesEveryTextToken {
                for token in Palette.Token.allCases where token.isText {
                    let ratio = Palette.contrast(token, on: ground, in: scheme)
                    XCTAssertGreaterThanOrEqual(
                        ratio, Palette.textContrastMinimum,
                        """
                        \(token.rawValue) on \(ground.rawValue) in \(scheme.rawValue) \
                        is \(rounded(ratio)):1.
                        """)
                }
            }
        }
    }

    /// AND THE EXCEPTIONS ARE A LIST WITH NUMBERS ON IT, NOT A GAP IN THE LOOP.
    ///
    /// EVERY TEXT TOKEN, EVERY TEXT GROUND, BOTH SCHEMES — 130 pairs — and the
    /// seven that miss 4.5:1 are written out here with the ratio that makes
    /// each one a miss. This is the same shape as the pinned failures below:
    /// stating a shortfall with its measurement is what stops it being either
    /// forgotten or quietly widened. Add a token, use an ink somewhere new, or
    /// move a ground, and a pair that was passing appears in this list with its
    /// own number attached rather than disappearing behind a `false`.
    ///
    /// ALL SEVEN ARE THE SAME FACT: an accent on the recessed ground in light,
    /// where the four inks are 4.17 to 4.27 to one. Nothing in the app draws
    /// one there — the words on that ground are section headers and footers,
    /// set in the type ramp — and `takesEveryTextToken` is the rule that says
    /// so. The list is what proves the rule is the only exception.
    func testTheOnlyWordsShortOfTheBarAreTheAccentsOnTheRecessedGround() {
        var short: [String] = []
        for scheme in Palette.Scheme.allCases {
            for ground in Palette.Token.allCases where ground.isTextGround {
                for token in Palette.Token.allCases where token.isText {
                    let ratio = Palette.contrast(token, on: ground, in: scheme)
                    guard ratio < Palette.textContrastMinimum else { continue }
                    short.append("""
                        \(token.rawValue) on \(ground.rawValue) in \
                        \(scheme.rawValue) is \(String(format: "%.2f", ratio)):1
                        """)
                }
            }
        }
        XCTAssertEqual(short, [
            "brandPrimary on backgroundSecondary in light is 4.27:1",
            "actionSecondary on backgroundSecondary in light is 4.17:1",
            "robotActive on backgroundSecondary in light is 4.17:1",
            "robotIdle on backgroundSecondary in light is 4.27:1",
            "sensorActive on backgroundSecondary in light is 4.25:1",
            "training on backgroundSecondary in light is 4.21:1",
            "warning on backgroundSecondary in light is 4.25:1",
        ])
        // And every one of them is on a ground the app knows not to set an
        // accent word on — so the exception list and the rule agree.
        for entry in short {
            XCTAssertTrue(entry.contains("on backgroundSecondary"), entry)
        }
    }

    /// EVERY FILLED SHAPE'S EDGE CLEARS 3:1 ON ITS SCHEME'S GROUND. WCAG 2.1
    /// SC 1.4.11.
    ///
    /// The shape is what has to be findable, not the paint: a fill that misses
    /// the bar is allowed if `fillEdge` gives it a rim that clears it. Exactly
    /// one token uses that allowance — Duck Orange in light, at 2.30:1 — and
    /// the next test pins it so the allowance cannot quietly spread.
    func testEveryFilledShapeHasAnEdgeAPersonCanFind() {
        for scheme in Palette.Scheme.allCases {
            let ground = Palette.ground(in: scheme)
            for token in Palette.Token.allCases where token.isFill {
                let fill = Palette.contrast(Palette.color(token, in: scheme), on: ground)
                let edge = Palette.fillEdge(token, in: scheme)
                    .map { Palette.contrast($0, on: ground) } ?? 0
                XCTAssertGreaterThanOrEqual(
                    max(fill, edge), Palette.shapeContrastMinimum,
                    """
                    \(token.rawValue) in \(scheme.rawValue): fill \(rounded(fill)):1, \
                    edge \(rounded(edge)):1 — neither reaches 3:1, so the shape has \
                    no findable boundary.
                    """)
            }
        }
    }

    /// AND AN EDGE EXISTS EXACTLY WHERE ONE IS NEEDED.
    ///
    /// Both directions matter. A missing edge is an unfindable control; a
    /// gratuitous one is an outline on a shape that did not need it, and the
    /// brief is explicit that this app has no thick outlines in it — the icon
    /// carries the outline and the app is quieter. So: `fillEdge` is non-nil
    /// if and only if the fill itself misses 3:1.
    func testAFillIsGivenAnEdgeIfAndOnlyIfItNeedsOne() {
        for scheme in Palette.Scheme.allCases {
            let ground = Palette.ground(in: scheme)
            for token in Palette.Token.allCases {
                let fill = Palette.contrast(Palette.color(token, in: scheme), on: ground)
                let needsOne = token.isFill && fill < Palette.shapeContrastMinimum
                let edge = Palette.fillEdge(token, in: scheme)
                XCTAssertEqual(edge != nil, needsOne,
                               """
                               \(token.rawValue) in \(scheme.rawValue) is \
                               \(rounded(fill)):1 on the ground and \
                               \(edge == nil ? "has no edge" : "has an edge").
                               """)
                if let edge {
                    XCTAssertGreaterThanOrEqual(
                        Palette.contrast(edge, on: ground), Palette.shapeContrastMinimum,
                        "\(token.rawValue)'s edge does not itself clear 3:1")
                }
            }
        }
    }

    /// The one place the allowance is used, named, so that a second one has to
    /// be argued for rather than merely added.
    func testDuckOrangeOnCreamIsTheOnlyFillThatBorrowsAnEdge() {
        var borrowers: [String] = []
        for scheme in Palette.Scheme.allCases {
            for token in Palette.Token.allCases
            where Palette.fillEdge(token, in: scheme) != nil {
                borrowers.append("\(token.rawValue)/\(scheme.rawValue)")
            }
        }
        XCTAssertEqual(borrowers, ["actionPrimary/light"])
        XCTAssertEqual(Palette.fillEdge(.actionPrimary, in: .light), Palette.orangeInk)
    }

    // MARK: - 2. the pinned failures

    /// THE FINDING THAT SHAPES EVERYTHING, AS A TEST. Not one brand accent is
    /// legible as body text on Warm Cream.
    ///
    /// THIS IS THE TEST THAT SAYS NO TO LIGHTENING THE CREAM. The tempting
    /// "fix" for a light mode that will not take the brand colours is to move
    /// the ground toward white until they pass — which trades the warm shell
    /// the robot is actually made of for a generic app, and still only barely
    /// works. If somebody tries it, this fails and names the ratio that made
    /// the ink variants necessary in the first place.
    func testNotOneBrandAccentIsLegibleAsTextOnWarmCream() {
        let expected = ["Duck Orange": 2.30, "Lavender": 2.55,
                        "Microduck Teal": 1.74, "Lens Yellow": 1.56]
        for (name, colour) in brandAccents {
            let ratio = Palette.contrast(colour, on: cream)
            XCTAssertLessThan(ratio, Palette.textContrastMinimum,
                              "\(name) has become legible on cream at \(rounded(ratio)):1 — "
                            + "if the palette changed, the ink variants need re-deriving")
            XCTAssertEqual(rounded(ratio), expected[name]!, accuracy: 0.001,
                           "\(name) on cream moved to \(rounded(ratio)):1")
        }
    }

    /// AND NOT ONE OF THEM CLEARS EVEN THE 3:1 SHAPE BAR THERE.
    ///
    /// The brief's rule reads "a brand colour FILLS A SHAPE (3:1 bar, all
    /// pass)", and on charcoal that is true. On cream it is not true of any of
    /// them: 2.30, 2.55, 1.74, 1.56 against a bar of 3. So on the light ground
    /// a raw brand colour cannot be an unbordered fill either — which is why
    /// `fillEdge` exists, and why every other light-mode token is an ink.
    func testOnCreamTheBrandAccentsDoNotEvenReachTheShapeBar() {
        for (name, colour) in brandAccents {
            XCTAssertLessThan(
                Palette.contrast(colour, on: cream), Palette.shapeContrastMinimum,
                "\(name) now clears 3:1 on cream — the fill rules can be relaxed")
        }
    }

    /// THE ASYMMETRY IS THE WHOLE ARGUMENT FOR TWO SCHEMES. The same four
    /// accents that fail on cream pass comfortably on Mechanical Charcoal:
    /// 6.76, 6.11, 8.92, 9.99. Dark mode gets the brand; light mode gets the
    /// inks. If this ever stopped being true the palette would need one set of
    /// colours, not two.
    func testAllFourBrandAccentsPassOnMechanicalCharcoal() {
        let expected = ["Duck Orange": 6.76, "Lavender": 6.11,
                        "Microduck Teal": 8.92, "Lens Yellow": 9.99]
        for (name, colour) in brandAccents {
            let ratio = Palette.contrast(colour, on: charcoal)
            XCTAssertGreaterThanOrEqual(ratio, Palette.textContrastMinimum, name)
            XCTAssertEqual(rounded(ratio), expected[name]!, accuracy: 0.001,
                           "\(name) on charcoal moved to \(rounded(ratio)):1")
        }
    }

    /// THE GREY THE BRIEF ASKED FOR WOULD HAVE SHIPPED ILLEGIBLE TERTIARY
    /// TEXT, and this is the number that says so.
    ///
    /// #6E7A80 is 3.89:1 on cream and 4.23:1 on the primary surface — under
    /// the bar on both, for the token literally named `textTertiary` and for
    /// the word beside an offline robot's dot. `greyInk` is that grey darkened
    /// along its own hue until it clears every light ground. The test is
    /// phrased as the failure rather than the fix so that restoring the
    /// original value fails here, with its reason attached.
    func testTheGreyTheBriefSpecifiedForLightTertiaryTextWasBelowTheBar() {
        let asBriefed = Palette.RGB(hex: "#6E7A80")
        XCTAssertLessThan(Palette.contrast(asBriefed, on: cream),
                          Palette.textContrastMinimum)
        XCTAssertEqual(rounded(Palette.contrast(asBriefed, on: cream)), 3.89, accuracy: 0.001)
        XCTAssertLessThan(
            Palette.contrast(asBriefed, on: Palette.color(.surfacePrimary, in: .light)),
            Palette.textContrastMinimum)

        // What shipped instead, on every light ground.
        for ground in Palette.Token.allCases where ground.isTextGround {
            XCTAssertGreaterThanOrEqual(
                Palette.contrast(Palette.greyInk, on: Palette.color(ground, in: .light)),
                Palette.textContrastMinimum, ground.rawValue)
        }
        XCTAssertEqual(Palette.color(.textTertiary, in: .light), Palette.greyInk)
        XCTAssertEqual(Palette.color(.robotOffline, in: .light), Palette.greyInk)
    }

    /// AND THE DARK GREY IT ASKED FOR FAILED ONE GROUND OUT OF FOUR.
    ///
    /// #7E8E94 is 4.45:1 on `surfaceElevated` — the only ground it misses, and
    /// the one a tertiary label on a sheet sits on. A near miss on one surface
    /// is the kind of defect that survives review precisely because three
    /// checks out of four pass.
    func testTheDarkGreyTheBriefSpecifiedMissedTheElevatedSurface() {
        let asBriefed = Palette.RGB(hex: "#7E8E94")
        let elevated = Palette.color(.surfaceElevated, in: .dark)
        XCTAssertLessThan(Palette.contrast(asBriefed, on: elevated),
                          Palette.textContrastMinimum)
        XCTAssertEqual(rounded(Palette.contrast(asBriefed, on: elevated)), 4.45, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            Palette.contrast(Palette.color(.textTertiary, in: .dark), on: elevated),
            Palette.textContrastMinimum)
    }

    /// A FOCUS RING IN THE BRAND TEAL WOULD NOT EXIST ON CREAM.
    ///
    /// 1.74:1. Of every contrast failure a design system can ship this is the
    /// worst one, because it does not degrade the experience for a keyboard,
    /// switch or Full Keyboard Access user — it removes their only way of
    /// knowing where they are. The shipped ring is the same hue at ink weight
    /// and clears the shape bar in both schemes with room to spare.
    func testTheFocusRingIsVisibleInBothSchemes() {
        XCTAssertLessThan(Palette.contrast(Palette.microduckTeal, on: cream),
                          Palette.shapeContrastMinimum,
                          "brand teal has become a usable light focus ring")
        for scheme in Palette.Scheme.allCases {
            let ratio = Palette.contrast(.focus, on: .backgroundPrimary, in: scheme)
            XCTAssertGreaterThanOrEqual(ratio, Palette.shapeContrastMinimum,
                                        "focus in \(scheme.rawValue) is \(rounded(ratio)):1")
        }
        XCTAssertEqual(Palette.color(.focus, in: .light), Palette.tealInk)
        XCTAssertEqual(Palette.color(.focus, in: .dark), Palette.microduckTeal)
    }

    /// THE SECONDARY BACKGROUND TAKES THE TYPE RAMP AND NOT THE INKS, which is
    /// a sharper claim than the one this test used to make and is the reason
    /// the ground had to be admitted into the set rather than argued out of it.
    ///
    /// The four inks land between 4.17:1 and 4.27:1 on #EFE7D8 — near misses,
    /// the kind that survive review because they look fine. The right response
    /// is not to re-tune four inks whose ratios on the primary ground are
    /// pinned to two decimals; it is to put a card on the recessed ground and
    /// the accent words on the card. What DOES land on it directly is a
    /// section header and a section footer, in the three-step type ramp, and
    /// all three of those clear the bar with the tertiary the closest at
    /// 4.59:1. Both halves are pinned: lose the first and the rule about cards
    /// stops being enforced, lose the second and every list header in the app
    /// is illegible with nothing to say so.
    func testTheRecessedGroundTakesTheTypeRampAndNotTheInks() {
        XCTAssertTrue(Palette.Token.backgroundSecondary.isTextGround,
                      "words land on the recessed ground — a list's section "
                    + "headers and footers are drawn straight on it")
        XCTAssertFalse(Palette.Token.backgroundSecondary.takesEveryTextToken)

        let recessed = Palette.color(.backgroundSecondary, in: .light)
        for (name, ink, documented) in [("orangeInk", Palette.orangeInk, 4.17),
                                        ("yellowInk", Palette.yellowInk, 4.25),
                                        ("tealInk", Palette.tealInk, 4.27),
                                        ("lavenderInk", Palette.lavenderInk, 4.21)] {
            let ratio = Palette.contrast(ink, on: recessed)
            XCTAssertLessThan(ratio, Palette.textContrastMinimum,
                              "\(name) now clears 4.5:1 on the recessed ground — "
                            + "backgroundSecondary could take every text token")
            XCTAssertEqual(rounded(ratio), documented, accuracy: 0.001,
                           "\(name) on the recessed ground moved to \(rounded(ratio)):1")
        }

        // The words that are actually set on it, and by how much they clear.
        for (token, documented) in [(Palette.Token.textPrimary, 14.37),
                                    (.textSecondary, 6.24),
                                    (.textTertiary, 4.59)] {
            let ratio = Palette.contrast(token, on: .backgroundSecondary, in: .light)
            XCTAssertGreaterThanOrEqual(ratio, Palette.textContrastMinimum,
                                        "\(token.rawValue) on the recessed ground")
            XCTAssertEqual(rounded(ratio), documented, accuracy: 0.001,
                           "\(token.rawValue) on the recessed ground is \(rounded(ratio)):1")
        }
    }

    // MARK: - the words drawn ON a fill

    /// A LABEL ON DUCK ORANGE IS 6.76:1 AND IS FIXED IN BOTH SCHEMES, which is
    /// the one contrast fact the app was making in a view file with nothing
    /// checking it.
    ///
    /// `DesignFixed.onAction` in `DesignComponents.swift` is
    /// `Palette.color(.textPrimary, in: .light)` — Mechanical Charcoal, asked
    /// for in ONE named scheme rather than adaptively, and used for the label
    /// inside every `PrimaryActionStyle` capsule and for the word on Duck
    /// soccer's command pads. Every other ratio in this app is arithmetic a
    /// test can run; this one was a sentence in a doc comment, on the most
    /// pressed control in the app.
    ///
    /// THE SECOND ASSERTION IS THE REASON FOR THE FIRST. Duck Orange is the
    /// same orange in both schemes, so a label on it that follows the scheme is
    /// wrong half the time: the adaptive `textPrimary` becomes Warm Cream in
    /// dark and lands at 2.30:1 on the fill — unreadable, on a button that
    /// moves a robot. A colour whose GROUND does not change must not change
    /// either, and 2.30 is the number that says so.
    func testTheLabelOnADuckOrangeFillClearsTheBarInBothSchemes() {
        let ink = Palette.color(.textPrimary, in: .light)
        for scheme in Palette.Scheme.allCases {
            let fill = Palette.color(.actionPrimary, in: scheme)
            let ratio = Palette.contrast(ink, on: fill)
            XCTAssertGreaterThanOrEqual(ratio, Palette.textContrastMinimum,
                                        "the action label in \(scheme.rawValue)")
            XCTAssertEqual(rounded(ratio), 6.76, accuracy: 0.001,
                           "the label on Duck Orange moved to \(rounded(ratio)):1")
        }
        // What the adaptive token would have given in dark, and why the app
        // pins the scheme instead of following it.
        let followingTheScheme = Palette.contrast(Palette.color(.textPrimary, in: .dark),
                                                  on: Palette.color(.actionPrimary, in: .dark))
        XCTAssertLessThan(followingTheScheme, Palette.textContrastMinimum)
        XCTAssertEqual(rounded(followingTheScheme), 2.30, accuracy: 0.001)
    }

    /// THE LENS'S CATCHLIGHT IS DECORATION, AND THE NUMBERS SAY WHICH KIND.
    ///
    /// `DesignFixed.catchlight` is `Palette.color(.surfaceElevated, in: .light)`
    /// — the app's one pure white — drawn on the iris, which is `sensorActive`.
    /// It is 5.23:1 on the light scheme's yellow ink and 1.77:1 on Lens Yellow
    /// in dark, and that asymmetry is exactly right for a specular highlight:
    /// obvious on the dark eye, barely there on the bright one. It is also why
    /// the 4.5:1 bar does not apply to it — SC 1.4.11 exempts decoration, and
    /// this is decoration in the standard's own sense, because the lens's state
    /// is carried by the iris colour, the ring colour and the accessibility
    /// label. The two ratios are pinned so that "it is decoration" stays a
    /// description of what is drawn rather than a licence.
    func testTheCatchlightIsBrightOnTheDarkEyeAndFaintOnTheBrightOne() {
        let white = Palette.color(.surfaceElevated, in: .light)
        XCTAssertEqual(white, Palette.RGB(hex: "#FFFFFF"))
        XCTAssertEqual(rounded(Palette.contrast(white, on: Palette.color(.sensorActive, in: .light))),
                       5.23, accuracy: 0.001)
        XCTAssertEqual(rounded(Palette.contrast(white, on: Palette.color(.sensorActive, in: .dark))),
                       1.77, accuracy: 0.001)
    }

    /// SELECTION IS A WASH, NOT A SIGNAL — 1.02:1 in light, 1.14:1 in dark.
    ///
    /// `surfaceInteractive` is pale teal so that a selected row reads as this
    /// app's brand rather than the system blue, and it is nowhere near a
    /// contrast that carries information on its own. That is fine and
    /// intended, and it is exactly why the brief's rule is absolute: never
    /// rely on colour alone. This test pins the smallness so that nobody
    /// later points at the tint and calls it the selected state.
    func testTheSelectionWashCannotCarryInformationOnItsOwn() {
        for scheme in Palette.Scheme.allCases {
            let ratio = Palette.contrast(.surfaceInteractive, on: .backgroundPrimary,
                                         in: scheme)
            XCTAssertLessThan(ratio, Palette.shapeContrastMinimum,
                              """
                              surfaceInteractive in \(scheme.rawValue) is \
                              \(rounded(ratio)):1 — if it now carries 3:1 the rule that \
                              selection needs a mark as well should be revisited \
                              deliberately, not by accident.
                              """)
        }
    }

    // MARK: - 3. structure

    /// The four inks hit the ratios the brief documents, to two decimals.
    ///
    /// These are the numbers the whole light scheme was derived from, so they
    /// are asserted as exact rounded values rather than as "at least 4.5". An
    /// ink that drifted to 5.2 would still pass a bar test while being a
    /// visibly different colour from the one the design was signed off on.
    func testTheInkVariantsMatchTheirDocumentedRatios() {
        let inks: [(String, Palette.RGB, Double)] = [
            ("orangeInk", Palette.orangeInk, 4.52),
            ("yellowInk", Palette.yellowInk, 4.60),
            ("tealInk", Palette.tealInk, 4.62),
            ("lavenderInk", Palette.lavenderInk, 4.56),
        ]
        for (name, ink, documented) in inks {
            let ratio = Palette.contrast(ink, on: cream)
            XCTAssertEqual(rounded(ratio), documented, accuracy: 0.001,
                           "\(name) is \(rounded(ratio)):1 on cream, documented as \(documented)")
            XCTAssertGreaterThanOrEqual(ratio, Palette.textContrastMinimum, name)
        }
    }

    /// AN INK SETS A WORD; A BRAND COLOUR FILLS A SHAPE. Structurally, in
    /// light mode, which is where the distinction bites.
    ///
    /// No token that sets words in light mode may be one of the four raw brand
    /// accents — that is the rule, and stated as a property it holds for
    /// tokens nobody has written yet. Dark mode is deliberately exempt: there
    /// the accents are the legible ones.
    func testNoLightModeTextTokenIsARawBrandAccent() {
        let raw = Set(brandAccents.map(\.colour.hexString))
        for token in Palette.Token.allCases where token.isText {
            let value = Palette.color(token, in: .light)
            XCTAssertFalse(raw.contains(value.hexString),
                           "\(token.rawValue) sets words in \(value.hexString), which is a raw "
                         + "brand accent — words take the ink")
        }
    }

    /// Duck Orange survives as the action colour in both schemes, which is the
    /// one thing the accessibility work was not allowed to cost.
    func testTheActionColourIsDuckOrangeInBothSchemes() {
        for scheme in Palette.Scheme.allCases {
            XCTAssertEqual(Palette.color(.actionPrimary, in: scheme), Palette.duckOrange)
        }
    }

    /// The two schemes are actually two: the light ground is light, the dark
    /// ground is dark, and primary type inverts between them.
    func testTheSchemesAreTheWayRoundTheyClaimToBe() {
        XCTAssertGreaterThan(Palette.ground(in: .light).relativeLuminance,
                             Palette.ground(in: .dark).relativeLuminance)
        XCTAssertEqual(Palette.color(.textPrimary, in: .light), Palette.mechanicalCharcoal)
        XCTAssertEqual(Palette.color(.textPrimary, in: .dark), Palette.warmCream)
        // Each is legible on the other, which is the cleanest evidence the
        // pair was chosen together: 15.56:1 either way up.
        XCTAssertEqual(rounded(Palette.contrast(Palette.mechanicalCharcoal, on: cream)),
                       15.56, accuracy: 0.001)
    }

    /// Type hierarchy is a hierarchy: primary reads more strongly than
    /// secondary, which reads more strongly than tertiary, on both grounds.
    /// Three text colours that all clear 4.5:1 but sit within a hair of each
    /// other are three colours doing one colour's job.
    func testTheThreeTextWeightsAreActuallyThreeWeights() {
        for scheme in Palette.Scheme.allCases {
            let primary = Palette.contrast(.textPrimary, on: .backgroundPrimary, in: scheme)
            let secondary = Palette.contrast(.textSecondary, on: .backgroundPrimary, in: scheme)
            let tertiary = Palette.contrast(.textTertiary, on: .backgroundPrimary, in: scheme)
            XCTAssertGreaterThan(primary, secondary, scheme.rawValue)
            XCTAssertGreaterThan(secondary, tertiary, scheme.rawValue)
        }
    }

    /// Every token is classified, and the classification is coherent: a ground
    /// never sets words, a token that sets words is not also a ground, and
    /// nothing takes every text token without being a text ground in the first
    /// place.
    func testTheClassificationOfEveryTokenIsCoherent() {
        for token in Palette.Token.allCases {
            XCTAssertFalse(token.isText && token.isTextGround,
                           "\(token.rawValue) cannot be both the word and the paper")
            if token.takesEveryTextToken {
                XCTAssertTrue(token.isTextGround,
                              "\(token.rawValue) takes every text token without being "
                            + "a ground words are set on, which is not a thing")
            }
        }
        // Nothing has been left out of the roster the app draws from. Five
        // grounds, because `backgroundSecondary` is one — four of them take any
        // text token and the recessed one takes the type ramp.
        XCTAssertEqual(Palette.Token.allCases.count, 21)
        XCTAssertEqual(Palette.Token.allCases.filter(\.isText).count, 13)
        XCTAssertEqual(Palette.Token.allCases.filter(\.isTextGround).count, 5)
        XCTAssertEqual(Palette.Token.allCases.filter(\.takesEveryTextToken).count, 4)
    }

    // MARK: - the maths itself

    /// A contrast helper that is wrong is worse than none, because every
    /// number above would agree with it. These are the three values the
    /// formula is defined by.
    func testTheContrastFormulaHitsItsKnownValues() {
        let white = Palette.RGB(hex: "#FFFFFF")
        let black = Palette.RGB(hex: "#000000")
        XCTAssertEqual(Palette.contrast(white, on: black), 21.0, accuracy: 0.0001)
        XCTAssertEqual(Palette.contrast(white, on: white), 1.0, accuracy: 0.0001)
        XCTAssertEqual(white.relativeLuminance, 1.0, accuracy: 0.0001)
        XCTAssertEqual(black.relativeLuminance, 0.0, accuracy: 0.0001)
        // Mid grey, from the WCAG definition rather than from this
        // implementation: #808080 linearises to 0.2158.
        XCTAssertEqual(Palette.RGB(hex: "#808080").relativeLuminance, 0.2158, accuracy: 0.0001)
    }

    /// SYMMETRIC, DELIBERATELY. The commonest way to write this helper wrong
    /// is to assume the first argument is the lighter one, which returns a
    /// number below 1 for dark text and quietly passes nothing.
    func testContrastDoesNotCareWhichArgumentIsLighter() {
        for token in Palette.Token.allCases {
            for scheme in Palette.Scheme.allCases {
                let colour = Palette.color(token, in: scheme)
                let ground = Palette.ground(in: scheme)
                XCTAssertEqual(Palette.contrast(colour, on: ground),
                               Palette.contrast(ground, on: colour), accuracy: 1e-12)
                XCTAssertGreaterThanOrEqual(Palette.contrast(colour, on: colour), 1.0)
            }
        }
    }

    /// Every hex in the palette round-trips. A parser that is wrong in the
    /// same direction as everything reading its output produces a design
    /// system that is self-consistently the wrong colour.
    func testEveryTokenRoundTripsThroughHex() {
        for token in Palette.Token.allCases {
            for scheme in Palette.Scheme.allCases {
                let colour = Palette.color(token, in: scheme)
                XCTAssertEqual(Palette.RGB(hex: colour.hexString), colour,
                               "\(token.rawValue)/\(scheme.rawValue)")
            }
        }
        XCTAssertEqual(Palette.duckOrange.hexString, "#FF7A12")
        XCTAssertEqual(Palette.RGB(hex: "ff7a12"), Palette.duckOrange,
                       "the parser must not care about the # or the case")
    }

    // MARK: - the scales

    /// Radii are a scale: strictly increasing, on the 4pt base, and every one
    /// of them a value somebody chose.
    func testTheRadiusScaleIsStrictlyIncreasing() {
        let values = Palette.Radius.allCases.map(\.rawValue)
        XCTAssertEqual(values, [6, 10, 14, 20, 28])
        for (smaller, larger) in zip(values, values.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
        XCTAssertGreaterThan(Palette.pill, values.last!)
    }

    /// A CARD INSIDE A CARD TAKES THE NEXT RADIUS DOWN, which is what makes
    /// nesting look machined rather than stacked. Every step goes down exactly
    /// one, and `chip` is the floor rather than an error.
    func testANestedShapeTakesExactlyTheNextRadiusDown() {
        let ordered = Palette.Radius.allCases
        for (index, radius) in ordered.enumerated() {
            let expected = index == 0 ? ordered[0] : ordered[index - 1]
            XCTAssertEqual(radius.inner, expected, "\(radius) nests wrongly")
            XCTAssertLessThanOrEqual(radius.inner.rawValue, radius.rawValue)
        }
        XCTAssertEqual(Palette.Radius.chip.inner, .chip)
        XCTAssertEqual(Palette.Radius.sheet.inner.inner.inner, .control)
    }

    /// Spacing is strictly increasing and every step is a multiple of four.
    /// The scale's value is in what it forbids: 18 and 20 both look fine
    /// alone, and together they produce gutters aligned to nothing.
    func testTheSpacingScaleIsOnAFourPointBase() {
        let values = Palette.Spacing.allCases.map(\.rawValue)
        XCTAssertEqual(values, [4, 8, 12, 16, 24, 32, 48])
        for step in values {
            XCTAssertEqual(step.truncatingRemainder(dividingBy: Palette.spacingBase), 0,
                           "\(step) is not on the 4pt base")
        }
        for (smaller, larger) in zip(values, values.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
    }

    /// One spring, and a Reduce Motion cross-fade short enough to read as an
    /// instant change rather than as an animation somebody asked not to see.
    func testThereIsOneSpringAndItSettlesWithoutRinging() {
        XCTAssertEqual(Palette.Motion.springResponse, 0.35, accuracy: 1e-9)
        XCTAssertGreaterThan(Palette.Motion.springDamping, 0)
        XCTAssertLessThan(Palette.Motion.springDamping, 1.0,
                          "damping at or above 1 no longer settles like a spring")
        XCTAssertLessThan(Palette.Motion.reducedMotionSeconds, Palette.Motion.springResponse)
    }
}
