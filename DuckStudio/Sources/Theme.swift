import SwiftUI

/// The app's colours, read off Pollen Robotics' own Microduck page.
///
/// SO THE APP SITS BESIDE THE ROBOT IT IS FOR. Somebody arriving here has just
/// come from pollen-robotics.com/microduck, and an app in unrelated colours
/// reads as a third-party utility that happens to mention the same robot.
/// Every value below was sampled from that page rather than chosen: the near
/// blacks it grounds on, the warm cream it sets type in, and the four accents
/// it uses for emphasis.
///
/// THE PALETTE IS THEIRS AND THE APP IS NOT. Harmonising with a brand is not
/// wearing it: there is no Pollen logo here, no Pollen wordmark, and the app
/// says it is independent on its own store listing, its website and its
/// Policies tab. The line worth holding is that a person must never be able to
/// mistake this for something Pollen shipped — colour alone has never made that
/// claim, and nothing here goes further than colour.
enum Theme {

    // MARK: - grounds

    /// `#08080c` — the darkest ground their pages use. Not pure black: it is
    /// very slightly blue, and beside true black it reads as deliberate.
    static let ground = Color(red: 0x08 / 255, green: 0x08 / 255, blue: 0x0C / 255)
    /// `#101018` — the lift they put behind a subject.
    static let raised = Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x18 / 255)

    // MARK: - type

    /// `#faf8f2` — warm off-white. Their body colour, and the reason the pages
    /// do not feel like a terminal.
    static let cream = Color(red: 0xFA / 255, green: 0xF8 / 255, blue: 0xF2 / 255)
    /// `#f2ecdd` — the quieter parchment, for secondary text on dark.
    static let parchment = Color(red: 0xF2 / 255, green: 0xEC / 255, blue: 0xDD / 255)

    // MARK: - accents

    /// `#ff7a2f` — the primary. The most-used accent on their page by a clear
    /// margin, and this app's tint.
    static let orange = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x2F / 255)
    /// `#ffd23f` — the bill, and anything drawing the eye second.
    static let amber = Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x3F / 255)
    /// `#2ff0e6` — measurement, telemetry, the things that came back from a
    /// bench rather than from a person.
    static let cyan = Color(red: 0x2F / 255, green: 0xF0 / 255, blue: 0xE6 / 255)
    /// `#ff2fa8` — reserved for the loudest thing on a screen, which in this
    /// app is a refusal that matters.
    static let magenta = Color(red: 0xFF / 255, green: 0x2F / 255, blue: 0xA8 / 255)

    /// `#75c6c7` — the app icon's ground.
    ///
    /// THE ICON IS THE ONE BRIGHT THING AND THAT IS DELIBERATE. It has to work
    /// on somebody's home screen beside every other app, where a near-black
    /// tile disappears; the app itself opens onto a 3D stage that reads far
    /// better dark. Both are the same family — the icon's bill is this
    /// palette's orange, its hips are Pollen's own lavender, its feet are the
    /// amber — so the tile and the app are recognisably one thing without the
    /// app having to be as loud as its icon.
    static let iconGround = Color(red: 0x75 / 255, green: 0xC6 / 255, blue: 0xC7 / 255)
    /// `#9d87e8` — the lavender on the robot's hips, and on Pollen's own page.
    static let lavender = Color(red: 0x9D / 255, green: 0x87 / 255, blue: 0xE8 / 255)

    // MARK: - what each accent MEANS here

    /// A measured fact — something a bench or the kinematics produced.
    ///
    /// COLOUR AS A CLAIM ABOUT PROVENANCE, which is the one thing this app is
    /// consistently strict about. `cyan` is what a machine measured; `amber` is
    /// what somebody asked for; `magenta` is a refusal. Using them the other
    /// way round would make the palette say the opposite of the words.
    static let measured = cyan
    /// Something authored — a request, not a result.
    static let asked = amber
    /// A refusal, or a limit being approached.
    static let refused = magenta

    /// The Microduck page sets display type in Anton and body in DM Sans.
    ///
    /// NEITHER IS BUNDLED, AND THAT IS DELIBERATE. Shipping two font files to
    /// echo a website costs bytes on every install and breaks Dynamic Type
    /// unless every use is scaled by hand — and this app has people reading
    /// long refusals on a phone. The system face at a heavy weight carries the
    /// same intent, and respects the text size somebody actually chose.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default)
    }
}

extension View {
    /// The app's tint and preferred appearance in one place.
    ///
    /// DARK BY PREFERENCE, NOT BY FORCE. Their pages are near-black and this
    /// app's subject is a 3D stage that reads far better on dark — but somebody
    /// who has chosen light on their phone has chosen it, and an app that
    /// overrides that is an app that ignores a stated preference. `preferredColorScheme`
    /// asks; it does not insist, and every colour above is legible either way.
    func microduckTheme() -> some View {
        tint(Theme.orange)
            .preferredColorScheme(.dark)
    }
}
