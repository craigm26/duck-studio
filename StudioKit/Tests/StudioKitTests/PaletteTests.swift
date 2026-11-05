import XCTest
@testable import StudioKit

/// The Pond Day palette, checked against the formula it claims to satisfy.
///
/// Every claim in docs/design/playful-theme.md is arithmetic on two hex
/// triples, and `swift test` on Linux either agrees or fails the build.
///
/// THREE KINDS OF TEST LIVE HERE:
///
///   1. Requirements, iterated over the token enum so they hold for tokens
///      nobody has written yet: words clear 4.5:1 on every ground, fills have
///      a findable edge, labels on fills are ink, Stop is the only red.
///   2. The spec's numbers, pinned to two decimals, so a value cannot drift
///      away from the table the design was signed off on.
///   3. Structure: the scales are scales and the maths is the maths.
final class PaletteTests: XCTestCase {

    /// Two decimals, the way the spec quotes a ratio.
    private func rounded(_ ratio: Double) -> Double {
        (ratio * 100).rounded() / 100
    }

    private func ratio(_ a: Palette.Token, _ b: Palette.Token,
                       _ scheme: Palette.Scheme) -> Double {
        Palette.contrast(a, on: b, in: scheme)
    }

    // MARK: - 1. the requirements

    /// EVERY TOKEN THAT SETS WORDS CLEARS 4.5:1 ON EVERY GROUND WORDS ARE SET
    /// ON, IN BOTH SCHEMES. WCAG 2.1 SC 1.4.3. This is the contrast-ratio test
    /// for every text/background pair.
    func testEveryTextTokenIsLegibleOnEveryGroundWordsAreSetOn() {
        var pairs = 0
        for scheme in Palette.Scheme.allCases {
            for ground in Palette.Token.allCases where ground.isTextGround {
                for token in Palette.Token.allCases where token.isText {
                    pairs += 1
                    let value = ratio(token, ground, scheme)
                    XCTAssertGreaterThanOrEqual(
                        value, Palette.textContrastMinimum,
                        """
                        \(token.rawValue) on \(ground.rawValue) in \(scheme.rawValue) \
                        is \(rounded(value)):1. \
                        \(Palette.color(token, in: scheme).hexString) on \
                        \(Palette.color(ground, in: scheme).hexString).
                        """)
                }
            }
        }
        // 13 text tokens, 5 grounds, 2 schemes.
        XCTAssertEqual(pairs, 130)
    }

    /// THE PLAY SCREEN'S OWN GROUNDS: the pad labels sit on the stick pad, and
    /// "Move" / "Turn" can land on the 3D floor's playmat.
    func testTheTypeRampIsLegibleOnTheStickPadAndTheFloor() {
        for scheme in Palette.Scheme.allCases {
            for ground in [Palette.Token.stickPad, .stageDeck] {
                for token in [Palette.Token.textPrimary, .textSecondary, .textTertiary] {
                    let value = ratio(token, ground, scheme)
                    XCTAssertGreaterThanOrEqual(value, Palette.textContrastMinimum,
                                                "\(token) on \(ground) in \(scheme)")
                }
            }
        }
        XCTAssertEqual(rounded(ratio(.textTertiary, .stageDeck, .light)), 4.70, accuracy: 0.001)
        XCTAssertEqual(rounded(ratio(.textPrimary, .stageDeck, .light)), 11.80, accuracy: 0.001)
    }

    /// THE MARKS ON THE FLOOR ARE FINDABLE (build 93). The pitch lines, goal frame and net, the
    /// walked path and the step's leading edge each clear SC 1.4.11's 3:1 against what they are
    /// drawn on, in both schemes. White lines were 1.51:1 on the light playmat; the yellow step
    /// edge was 1.35:1 on the cream step.
    func testTheMarksOnTheFloorAreFindableInBothSchemes() {
        for scheme in Palette.Scheme.allCases {
            for mark in [Palette.Token.stageLine, .stageTrail] {
                XCTAssertGreaterThanOrEqual(ratio(mark, .stageDeck, scheme), Palette.shapeContrastMinimum,
                                            "\(mark) on the playmat in \(scheme)")
            }
            XCTAssertGreaterThanOrEqual(ratio(.stageStepEdge, .stageProp, scheme), Palette.shapeContrastMinimum,
                                        "the step edge on the step in \(scheme)")
            // A walked path is not a painted line.
            XCTAssertNotEqual(Palette.color(.stageTrail, in: scheme), Palette.color(.stageLine, in: scheme))
        }
        let white = Palette.RGB(hex: "#FFFFFF")
        XCTAssertLessThan(Palette.contrast(white, on: Palette.color(.stageDeck, in: .light)),
                          Palette.shapeContrastMinimum, "why the lines are not white by day")
        XCTAssertLessThan(Palette.contrast(Palette.color(.actionYellow, in: .light),
                                           on: Palette.color(.stageProp, in: .light)),
                          Palette.shapeContrastMinimum, "why the step edge is not yellow")
        XCTAssertEqual(rounded(ratio(.stageLine, .stageDeck, .light)), 3.90, accuracy: 0.001)
        XCTAssertEqual(rounded(ratio(.stageStepEdge, .stageProp, .light)), 5.02, accuracy: 0.001)
    }

    /// A SYSTEM PROMINENT BUTTON SETS A WHITE LABEL ON THE TINT, and the tint is orange ink. By
    /// day that is 5.72:1; at night the ink is a light orange and white on it is 2.02:1. So the
    /// app's own button style (ink on Beak Orange) is used instead, and
    /// scripts/check_no_bordered_prominent.sh keeps `.borderedProminent` out of the app.
    func testWhiteOnTheTintFailsAtNightSoProminentButtonsWearInk() {
        let white = Palette.RGB(hex: "#FFFFFF")
        XCTAssertLessThan(Palette.contrast(white, on: Palette.color(.actionInk, in: .dark)),
                          Palette.textContrastMinimum)
        XCTAssertEqual(rounded(Palette.contrast(white, on: Palette.color(.actionInk, in: .dark))), 2.02,
                       accuracy: 0.001)
        for scheme in Palette.Scheme.allCases {
            XCTAssertGreaterThanOrEqual(ratio(.onFill, .actionPrimary, scheme), Palette.textContrastMinimum)
        }
    }

    /// EVERY FILLED SHAPE'S EDGE CLEARS 3:1 ON ITS SCHEME'S GROUND. WCAG 2.1
    /// SC 1.4.11. The fill may miss if `fillEdge` gives it an outline that
    /// clears the bar.
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
                    edge \(rounded(edge)):1. Neither reaches 3:1.
                    """)
            }
        }
    }

    /// EVERY LIGHT FILL HAS AN INK OUTLINE, like the icon. The light fills
    /// cannot carry their own boundary on Pond Mist; the outline can.
    func testEveryLightFillHasAnInkOutline() {
        for token in Palette.Token.allCases where token.isPressableFill || token == .stop {
            XCTAssertEqual(Palette.fillEdge(token, in: .light), Palette.iconInk,
                           "\(token.rawValue) has no ink outline in light")
            XCTAssertGreaterThanOrEqual(
                Palette.contrast(Palette.iconInk, on: Palette.ground(in: .light)), 15.0)
        }
        // And the four pressable fills are exactly the four face-button colours.
        XCTAssertEqual(Palette.Token.allCases.filter(\.isPressableFill),
                       [.actionPrimary, .actionYellow, .actionTeal, .actionLavender])
        // The pad's rim is its boundary in dark, where the well alone is 1.18:1.
        let padDark = Palette.contrast(.stickPad, on: .backgroundPrimary, in: .dark)
        XCTAssertLessThan(padDark, Palette.shapeContrastMinimum)
        let rim = Palette.fillEdge(.stickPad, in: .dark)!
        XCTAssertEqual(rounded(Palette.contrast(rim, on: Palette.ground(in: .dark))),
                       5.25, accuracy: 0.001)
    }

    /// EVERY LABEL ON A FILL IS INK, EXCEPT STOP. Ink on orange, yellow, teal
    /// and lavender clears 4.5:1 in both schemes; white appears on exactly one
    /// colour, Stop red.
    func testEveryLabelOnAFillIsInkExceptStop() {
        XCTAssertEqual(Palette.color(.onFill, in: .light), Palette.iconInk)
        XCTAssertEqual(Palette.color(.onFill, in: .dark), Palette.iconInk)
        for scheme in Palette.Scheme.allCases {
            for fill in Palette.Token.allCases where fill.isPressableFill {
                let value = ratio(.onFill, fill, scheme)
                XCTAssertGreaterThanOrEqual(value, Palette.textContrastMinimum,
                                            "ink on \(fill.rawValue) in \(scheme.rawValue)")
                // White would fail on every one of them, which is the reason
                // the label is ink.
                let white = Palette.contrast(Palette.RGB(hex: "#FFFFFF"),
                                             on: Palette.color(fill, in: scheme))
                XCTAssertLessThan(white, Palette.textContrastMinimum,
                                  "white on \(fill.rawValue) now passes; revisit the label rule")
            }
            // Stop: white on red, and ink on red would be the weaker choice.
            let whiteOnStop = Palette.contrast(Palette.RGB(hex: "#FFFFFF"),
                                               on: Palette.color(.stop, in: scheme))
            XCTAssertGreaterThanOrEqual(whiteOnStop, Palette.textContrastMinimum)
            XCTAssertEqual(rounded(whiteOnStop), 4.87, accuracy: 0.001)
        }
        // The spec's table, light then dark.
        let expected: [(Palette.Token, Double, Double)] = [
            (.actionPrimary, 6.84, 7.58),
            (.actionYellow, 11.11, 11.61),
            (.actionTeal, 9.05, 10.32),
            (.actionLavender, 6.78, 8.44),
        ]
        for (fill, light, dark) in expected {
            XCTAssertEqual(rounded(ratio(.onFill, fill, .light)), light, accuracy: 0.001,
                           fill.rawValue)
            XCTAssertEqual(rounded(ratio(.onFill, fill, .dark)), dark, accuracy: 0.001,
                           fill.rawValue)
        }
    }

    /// STOP IS THE ONLY RED. One value in both schemes, and no other token
    /// (in either scheme) is a saturated colour within 20 degrees of its hue.
    func testStopRedIsUsedByNoOtherToken() {
        XCTAssertEqual(Palette.color(.stop, in: .light), Palette.RGB(hex: "#D92A2A"))
        XCTAssertEqual(Palette.color(.stop, in: .dark), Palette.RGB(hex: "#D92A2A"))
        let stop = Palette.stopRed
        for scheme in Palette.Scheme.allCases {
            for token in Palette.Token.allCases where token != .stop {
                let colour = Palette.color(token, in: scheme)
                XCTAssertNotEqual(colour, stop, "\(token.rawValue) is Stop red")
                let saturation = Palette.hueAndSaturation(colour).saturation
                guard saturation >= 0.35 else { continue }
                XCTAssertGreaterThanOrEqual(
                    Palette.hueDistance(colour, stop), 20,
                    "\(token.rawValue) in \(scheme.rawValue) (\(colour.hexString)) reads as red")
            }
            for token in Palette.Token.allCases where token.isPressableFill {
                if let lip = Palette.lip(token, in: scheme) {
                    XCTAssertGreaterThanOrEqual(Palette.hueDistance(lip, stop), 20,
                                                "\(token.rawValue)'s lip reads as red")
                }
            }
        }
    }

    /// THE ERROR COLOUR IS AT LEAST 30 DEGREES FROM STOP, so a refusal is
    /// never mistaken for the Stop control.
    func testCriticalHueIsAtLeast30DegreesFromStop() {
        for scheme in Palette.Scheme.allCases {
            let distance = Palette.hueDistance(Palette.color(.critical, in: scheme),
                                               Palette.stopRed)
            XCTAssertGreaterThanOrEqual(distance, 30,
                                        "critical in \(scheme.rawValue) is \(distance) degrees")
        }
    }

    /// Stop's own boundary. On the page it clears 3:1 by itself; on the dark
    /// floor it does not (2.00:1), which is why the disc wears a white ring
    /// and an ink outline as well.
    func testTheStopDiscIsFindableOnThePageAndNeedsItsRingOnTheDarkFloor() {
        XCTAssertEqual(rounded(ratio(.stop, .backgroundPrimary, .light)), 4.34, accuracy: 0.001)
        XCTAssertEqual(rounded(ratio(.stop, .backgroundPrimary, .dark)), 3.23, accuracy: 0.001)
        let onDarkFloor = ratio(.stop, .stageDeck, .dark)
        XCTAssertLessThan(onDarkFloor, Palette.shapeContrastMinimum)
        XCTAssertGreaterThanOrEqual(
            Palette.contrast(Palette.RGB(hex: "#FFFFFF"),
                             on: Palette.color(.stageDeck, in: .dark)),
            Palette.shapeContrastMinimum)
    }

    /// Orange and Stop red are close for people with protanopia, so colour
    /// alone must not separate them. Pinned so nobody leans on it.
    func testOrangeAndStopAreNotSeparatedByLuminanceAlone() {
        XCTAssertLessThan(ratio(.actionPrimary, .stop, .light), Palette.shapeContrastMinimum)
        XCTAssertEqual(rounded(ratio(.actionPrimary, .stop, .light)), 1.87, accuracy: 0.001)
    }

    // MARK: - 2. the spec's numbers

    func testTheTextRatiosMatchTheSpecTable() {
        let light: [(Palette.Token, Palette.Token, Double)] = [
            (.textPrimary, .backgroundPrimary, 15.90),
            (.textPrimary, .surfacePrimary, 17.26),
            (.textPrimary, .surfaceElevated, 17.83),
            (.textPrimary, .stickPad, 14.67),
            (.textPrimary, .surfaceInteractive, 14.14),
            (.textTertiary, .backgroundPrimary, 6.34),
            (.textTertiary, .surfacePrimary, 6.88),
            (.textTertiary, .surfaceInteractive, 5.63),
            (.brandPrimary, .backgroundPrimary, 5.25),
            (.actionInk, .backgroundPrimary, 5.10),
            (.actionInk, .surfacePrimary, 5.53),
            (.success, .backgroundPrimary, 5.22),
            (.warning, .backgroundPrimary, 5.24),
        ]
        for (token, ground, documented) in light {
            XCTAssertEqual(rounded(ratio(token, ground, .light)), documented, accuracy: 0.001,
                           "\(token) on \(ground) in light")
        }
        let dark: [(Palette.Token, Palette.Token, Double)] = [
            (.textPrimary, .backgroundPrimary, 14.67),
            (.textPrimary, .surfacePrimary, 12.47),
            (.textPrimary, .surfaceElevated, 10.37),
            (.textTertiary, .backgroundPrimary, 8.51),
            (.textTertiary, .surfaceElevated, 6.01),
            (.brandPrimary, .backgroundPrimary, 9.11),
            (.warning, .backgroundPrimary, 10.25),
        ]
        for (token, ground, documented) in dark {
            XCTAssertEqual(rounded(ratio(token, ground, .dark)), documented, accuracy: 0.001,
                           "\(token) on \(ground) in dark")
        }
    }

    /// The light fills miss 3:1 on Pond Mist by themselves. That is not a bug;
    /// it is the reason every one of them wears the ink outline.
    func testTheLightFillsNeedTheirOutline() {
        let expected: [(Palette.Token, Double)] = [
            (.actionPrimary, 2.33), (.actionYellow, 1.43),
            (.actionTeal, 1.76), (.actionLavender, 2.35),
        ]
        for (fill, documented) in expected {
            let value = ratio(fill, .backgroundPrimary, .light)
            XCTAssertLessThan(value, Palette.shapeContrastMinimum, fill.rawValue)
            XCTAssertEqual(rounded(value), documented, accuracy: 0.001, fill.rawValue)
        }
    }

    /// The brand values come from the icon and Pollen's page, verbatim.
    func testTheBrandColoursAreTheIconsColours() {
        XCTAssertEqual(Palette.color(.actionPrimary, in: .light).hexString, "#FF7A1A")
        XCTAssertEqual(Palette.color(.actionYellow, in: .light).hexString, "#FFC328")
        XCTAssertEqual(Palette.color(.actionTeal, in: .light).hexString, "#75C6C7")
        XCTAssertEqual(Palette.color(.actionLavender, in: .light).hexString, "#B494C5")
        XCTAssertEqual(Palette.color(.backgroundPrimary, in: .light).hexString, "#E6F5F4")
        XCTAssertEqual(Palette.color(.backgroundPrimary, in: .dark).hexString, "#10262B")
        XCTAssertEqual(Palette.color(.surfacePrimary, in: .light).hexString, "#FFFBF2")
        XCTAssertEqual(Palette.color(.stickPad, in: .light).hexString, "#EEE6F6")
        XCTAssertEqual(Palette.color(.stageDeck, in: .light).hexString, "#A8DCD9")
        XCTAssertEqual(Palette.lip(.actionPrimary, in: .light), Palette.beakShadow)
    }

    /// The dark page is a night pond, never black: the ground keeps a visible
    /// teal bias.
    func testTheDarkGroundIsNightPondNotBlack() {
        let ground = Palette.ground(in: .dark)
        XCTAssertGreaterThan(ground.blue, ground.red)
        XCTAssertGreaterThan(ground.green, ground.red)
        XCTAssertGreaterThan(ground.relativeLuminance, 0.01)
    }

    /// No light-mode text token is a raw bright fill colour. A fill fills a
    /// shape; an ink sets a word.
    func testNoLightModeTextTokenIsARawFillColour() {
        let fills = Set(Palette.Token.allCases.filter(\.isPressableFill)
            .map { Palette.color($0, in: .light).hexString })
        for token in Palette.Token.allCases where token.isText {
            let value = Palette.color(token, in: .light).hexString
            XCTAssertFalse(fills.contains(value), "\(token.rawValue) sets words in a fill colour")
        }
    }

    /// Selection is a wash, not a signal: under 3:1 on its ground in both
    /// schemes, so anything selected must also carry a mark.
    func testTheSelectionWashCannotCarryInformationOnItsOwn() {
        for scheme in Palette.Scheme.allCases {
            XCTAssertLessThan(ratio(.surfaceInteractive, .backgroundPrimary, scheme),
                              Palette.shapeContrastMinimum)
        }
    }

    /// Every lip is darker than its fill, so the button reads as standing up.
    func testEveryLipIsDarkerThanItsFill() {
        for scheme in Palette.Scheme.allCases {
            for token in Palette.Token.allCases {
                let lip = Palette.lip(token, in: scheme)
                XCTAssertEqual(lip != nil, token.isPressableFill, token.rawValue)
                if let lip {
                    XCTAssertLessThan(lip.relativeLuminance,
                                      Palette.color(token, in: scheme).relativeLuminance,
                                      "\(token.rawValue) lip in \(scheme.rawValue)")
                }
            }
        }
    }

    /// The focus ring is visible in both schemes, on the page and on a card.
    func testTheFocusRingIsVisibleInBothSchemes() {
        for scheme in Palette.Scheme.allCases {
            for ground in [Palette.Token.backgroundPrimary, .surfacePrimary] {
                XCTAssertGreaterThanOrEqual(ratio(.focus, ground, scheme),
                                            Palette.shapeContrastMinimum)
            }
        }
    }

    // MARK: - 3. structure

    func testTheSchemesAreTheWayRoundTheyClaimToBe() {
        XCTAssertGreaterThan(Palette.ground(in: .light).relativeLuminance,
                             Palette.ground(in: .dark).relativeLuminance)
        XCTAssertEqual(Palette.color(.textPrimary, in: .light), Palette.iconInk)
    }

    func testTheThreeTextWeightsAreActuallyThreeWeights() {
        for scheme in Palette.Scheme.allCases {
            let primary = ratio(.textPrimary, .backgroundPrimary, scheme)
            let secondary = ratio(.textSecondary, .backgroundPrimary, scheme)
            let tertiary = ratio(.textTertiary, .backgroundPrimary, scheme)
            XCTAssertGreaterThan(primary, secondary, scheme.rawValue)
            XCTAssertGreaterThan(secondary, tertiary, scheme.rawValue)
        }
    }

    func testTheClassificationOfEveryTokenIsCoherent() {
        for token in Palette.Token.allCases {
            XCTAssertFalse(token.isText && token.isTextGround,
                           "\(token.rawValue) cannot be both the word and the paper")
            if token.takesEveryTextToken {
                XCTAssertTrue(token.isTextGround)
            }
            if token.isPressableFill {
                XCTAssertTrue(token.isFill)
            }
        }
        XCTAssertEqual(Palette.Token.allCases.count, 38)
        XCTAssertEqual(Palette.Token.allCases.filter(\.isText).count, 13)
        XCTAssertEqual(Palette.Token.allCases.filter(\.isTextGround).count, 5)
        XCTAssertEqual(Palette.Token.allCases.filter(\.takesEveryTextToken).count, 5)
    }

    // MARK: - the maths itself

    func testTheContrastFormulaHitsItsKnownValues() {
        let white = Palette.RGB(hex: "#FFFFFF")
        let black = Palette.RGB(hex: "#000000")
        XCTAssertEqual(Palette.contrast(white, on: black), 21.0, accuracy: 0.0001)
        XCTAssertEqual(Palette.contrast(white, on: white), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Palette.RGB(hex: "#808080").relativeLuminance, 0.2158, accuracy: 0.0001)
    }

    func testContrastDoesNotCareWhichArgumentIsLighter() {
        for token in Palette.Token.allCases {
            for scheme in Palette.Scheme.allCases {
                let colour = Palette.color(token, in: scheme)
                let ground = Palette.ground(in: scheme)
                XCTAssertEqual(Palette.contrast(colour, on: ground),
                               Palette.contrast(ground, on: colour), accuracy: 1e-12)
            }
        }
    }

    func testHueMathsHitsItsKnownValues() {
        XCTAssertEqual(Palette.hueAndSaturation(Palette.RGB(hex: "#FF0000")).hue, 0, accuracy: 0.01)
        XCTAssertEqual(Palette.hueAndSaturation(Palette.RGB(hex: "#00FF00")).hue, 120, accuracy: 0.01)
        XCTAssertEqual(Palette.hueAndSaturation(Palette.RGB(hex: "#0000FF")).hue, 240, accuracy: 0.01)
        XCTAssertEqual(Palette.hueDistance(Palette.RGB(hex: "#FF0000"),
                                           Palette.RGB(hex: "#FF00FF")), 60, accuracy: 0.01)
        XCTAssertEqual(Palette.hueAndSaturation(Palette.RGB(hex: "#808080")).saturation, 0)
    }

    func testEveryTokenRoundTripsThroughHex() {
        for token in Palette.Token.allCases {
            for scheme in Palette.Scheme.allCases {
                let colour = Palette.color(token, in: scheme)
                XCTAssertEqual(Palette.RGB(hex: colour.hexString), colour,
                               "\(token.rawValue)/\(scheme.rawValue)")
            }
        }
        XCTAssertEqual(Palette.RGB(hex: "ff7a1a"), Palette.duckOrange,
                       "the parser must not care about the # or the case")
    }

    // MARK: - the scales

    /// Chunky, round, soft: the Pond Day radii.
    func testTheRadiusScaleIsStrictlyIncreasing() {
        let values = Palette.Radius.allCases.map(\.rawValue)
        XCTAssertEqual(values, [10, 16, 22, 28, 32])
        for (smaller, larger) in zip(values, values.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
        XCTAssertGreaterThan(Palette.pill, values.last!)
    }

    func testANestedShapeTakesExactlyTheNextRadiusDown() {
        let ordered = Palette.Radius.allCases
        for (index, radius) in ordered.enumerated() {
            let expected = index == 0 ? ordered[0] : ordered[index - 1]
            XCTAssertEqual(radius.inner, expected, "\(radius) nests wrongly")
        }
        XCTAssertEqual(Palette.Radius.sheet.inner.inner.inner, .control)
    }

    func testTheSpacingScaleIsOnAFourPointBase() {
        let values = Palette.Spacing.allCases.map(\.rawValue)
        XCTAssertEqual(values, [4, 8, 12, 16, 24, 32, 48])
        for step in values {
            XCTAssertEqual(step.truncatingRemainder(dividingBy: Palette.spacingBase), 0)
        }
    }

    func testThereIsOneSpringAndItSettlesWithoutRinging() {
        XCTAssertEqual(Palette.Motion.springResponse, 0.35, accuracy: 1e-9)
        XCTAssertGreaterThan(Palette.Motion.springDamping, 0)
        XCTAssertLessThan(Palette.Motion.springDamping, 1.0)
        XCTAssertLessThan(Palette.Motion.reducedMotionSeconds, Palette.Motion.springResponse)
    }
}
