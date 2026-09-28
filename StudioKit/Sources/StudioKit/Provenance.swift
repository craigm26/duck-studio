import Foundation

/// Who made this app, and who did not.
///
/// A CLAIM ABOUT SOMEBODY ELSE'S NAME IS THE ONE SENTENCE A COMMENT MAY NOT
/// OWN. `Theme.swift` carried this for months as prose: "the app says it is
/// independent on its own store listing, its website and its Policies tab." A
/// grep for `not affiliated`, `unofficial` or `independent` across this
/// repository found that comment and nothing else — no store-listing copy, no
/// website, no tab. The comment was the only place the claim existed, and a
/// comment is not a surface anybody reads. That is the exact failure mode this
/// project has already paid for elsewhere: a capability asserted in a file
/// nobody renders, believed because it was written down.
///
/// So the sentence lives here, where `swift test` pins its wording, and the
/// app draws it. A tested string can be shown; a comment cannot.
///
/// WHY IT NEEDS SAYING AT ALL. This app harmonises with Microduck's palette,
/// speaks `btd`'s own GATT dialect, transcribes Pollen Robotics' UUIDs, quotes
/// their design documents, and is about to file a report in their issue
/// tracker. Every one of those is a good reason for a stranger to assume it is
/// theirs. None of them is true. Pollen have not asked for this, have not seen
/// it, and are not answerable for it — and a person who believed otherwise
/// would take a bug here to the wrong maintainers and a promise here as
/// theirs to keep.
///
/// TWO LENGTHS, ONE CLAIM. The long form is what goes in a document, a store
/// listing or an issue comment, where there is room to say which part is
/// theirs. The short form is what fits under a screen. Neither hedges: there
/// is no "not officially affiliated", which invites the reader to wonder about
/// the unofficial kind.
public enum Provenance {

    /// The full claim, in the shape `duckkit`'s README already uses.
    ///
    /// THREE SENTENCES BECAUSE THREE THINGS NEED SAYING, and the third is the
    /// one a bare disclaimer leaves out. "Not affiliated" tells a reader what
    /// this is not; it does not tell them that Microduck is a real robot made
    /// by real people, which is the fact that makes the disclaimer necessary
    /// and the fact that credits them. An app that names somebody else's
    /// product owes them the naming.
    public static let independence =
        "Microduck Studio is an independent project. It is not made by, endorsed by, or "
      + "affiliated with Pollen Robotics. Microduck is their robot; this is an independent "
      + "owner's app for it."

    /// The same claim, short enough for a footer.
    ///
    /// IT KEEPS THE THREE VERBS. Shortening this to "an unofficial app" would
    /// save a line and lose the whole point: "unofficial" is a word a reader
    /// can take as "not yet official", and the three things being denied —
    /// made by, endorsed by, affiliated with — are three different
    /// relationships somebody might otherwise assume. What is dropped is the
    /// sentence that credits Pollen, because a footer sits under a screen that
    /// is already full of their robot's name.
    public static let independenceShort =
        "An independent project. Not made by, endorsed by, or affiliated with Pollen Robotics."

    /// The headline over the claim, where the claim gets a screen of its own.
    ///
    /// "OFFICIAL" IS POLLEN'S WORD, AND THE REASON IT IS HERE. Pollen Robotics
    /// asked (pollen-robotics/microduck#329, 2026-09-28) that this app make
    /// clear it is not the "official" one: they are building their own. The
    /// three denials above say so to a careful reader; a person who opens the
    /// app wondering "is this Pollen's app?" deserves the answer in the words
    /// they asked it in. It is a plain negation of "official", never the
    /// adjective "unofficial", for the reason `independence` gives.
    public static let notOfficialTitle = "This is not the official Microduck app"

    /// Where Pollen's own robot and company are, for a reader who came
    /// looking for them.
    ///
    /// A DISCLAIMER THAT NAMES A COMPANY AND GIVES NO WAY TO REACH IT sends the
    /// reader to a search engine, which is where they find this app again. The
    /// links are the two pages Pollen publish for exactly this reader: the
    /// company, and the robot.
    public struct Link: Equatable, Sendable, Identifiable {
        public let title: String
        public let url: URL
        public var id: String { url.absoluteString }
    }

    /// Pollen Robotics' own site.
    public static let pollenSite = Link(
        title: "Pollen Robotics",
        url: URL(string: "https://pollen-robotics.com/")!)

    /// Pollen's page for the Microduck robot itself.
    public static let microduckPage = Link(
        title: "Microduck, by Pollen Robotics",
        url: URL(string: "https://pollen-robotics.com/microduck/")!)

    /// Both, in the order a reader wants them: the robot, then who makes it.
    public static let links = [microduckPage, pollenSite]
}
