import Foundation

/// Where a person's pose comes from, and every sentence the two mimic screens
/// draw.
///
/// THREE SOURCES, ONE PIPELINE. A camera, a video on the phone and a YouTube
/// clip all end as pictures in a buffer that a body-pose model reads; what
/// differs is how the pictures get there and what is honest to say about it. A
/// camera is a person in the room. A video is a file the person chose. A
/// YouTube clip is a player on the screen and the phone reading its own screen
/// — which is the only way to see a YouTube video's frames without downloading
/// it, and is said plainly here because iOS will ask permission for exactly
/// that.
///
/// THE SENTENCES LIVE HERE SO `swift test` CAN READ THEM. This is the house rule
/// for anything a person reads on a stage, and it matters more on these two
/// screens than most: a duck that copies you LOOKS like a robot being
/// controlled, and it is a drawing being posed. `whatIsReal` is the sentence
/// that says so, once per source.
public enum MimicSource: String, CaseIterable, Identifiable, Equatable, Sendable {
    case camera, video, youtube

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .camera: return "Camera"
        case .video: return "A video"
        case .youtube: return "YouTube"
        }
    }

    public var symbol: String {
        switch self {
        case .camera: return "camera"
        case .video: return "film"
        case .youtube: return "play.rectangle"
        }
    }

    /// How to use it, under the picker.
    public var how: String {
        switch self {
        case .camera:
            return "Stand the phone where it can see your whole body — on a table, three or "
                 + "four steps back. The duck follows as you move."
        case .video:
            return "A video from your library or from Files plays here and is read frame by "
                 + "frame as it plays. Scrub to the part you want, then record."
        case .youtube:
            return "The clip plays in YouTube's own player here, and the phone reads its own "
                 + "screen to find the person in it — iOS asks once before that starts. Nothing "
                 + "is downloaded, and YouTube's terms still apply to what you watch."
        }
    }

    /// What is real about it, said once.
    public var whatIsReal: String {
        switch self {
        case .camera:
            return "Real here: where your joints are. The skeleton is a body-pose model's "
                 + "reading of the camera picture, worked out on this phone. Not real: the "
                 + "duck, which is a drawing posed to match you. Nothing is sent while you mimic."
        case .video:
            return "Real here: where the joints of the person in the video are, as a body-pose "
                 + "model on this phone reads them. Not real: the duck, which is a drawing posed "
                 + "to match. Nothing is sent while you mimic."
        case .youtube:
            return "Real here: the pixels of your own screen, read by this phone while the clip "
                 + "plays, and a body-pose model's reading of them. Not real: the duck, which is "
                 + "a drawing posed to match. Nothing is sent while you mimic."
        }
    }

    /// The word a mimicked draft's provenance names.
    public var provenanceWord: String {
        switch self {
        case .camera: return "the camera"
        case .video: return "a video"
        case .youtube: return "a YouTube clip"
        }
    }

    /// The first word of a kept motion's name.
    public var namePrefix: String {
        switch self {
        case .camera: return "Mimic"
        case .video: return "Video mimic"
        case .youtube: return "YouTube mimic"
        }
    }
}

/// A YouTube link, read for the one thing a player needs from it.
public enum YouTubeLink {

    /// The eleven-character video id in a link, or nil.
    ///
    /// Takes every spelling a person is likely to paste: `watch?v=`, `youtu.be/`,
    /// a Shorts link, a live link, an embed link, with or without a scheme,
    /// on any of YouTube's hosts. Refuses anything else rather than guessing —
    /// an id pulled out of the wrong site is a player showing the wrong video.
    public static func videoID(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let host = url.host?.lowercased() else { return nil }
        let hosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
                     "youtu.be", "www.youtu.be", "youtube-nocookie.com", "www.youtube-nocookie.com"]
        guard hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("youtu.be") {
            return parts.first.flatMap(valid)
        }
        if parts.first == "watch" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return query.first { $0.name == "v" }?.value.flatMap(valid)
        }
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
            return valid(parts[1])
        }
        return nil
    }

    /// Exactly eleven of the characters an id is made of.
    private static func valid(_ candidate: String) -> String? {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard candidate.count == 11, candidate.allSatisfy({ allowed.contains($0) }) else { return nil }
        return candidate
    }

    /// The player page for an id: YouTube's privacy-enhanced host, inline so
    /// iOS does not take it full screen, playing on load.
    public static func embedURL(for id: String) -> String {
        "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&autoplay=1&rel=0&modestbranding=1"
    }

    /// The origin the player page is loaded from.
    ///
    /// ERROR 153 IS WHAT HAPPENS WITHOUT THIS. YouTube's embed refuses to play
    /// when the request carries no HTTP referrer — "Video player configuration
    /// error" — and a web view handed the embed URL directly sends none. So
    /// the embed is put inside a page of our own, loaded with this as its
    /// base URL, and the iframe's request carries it. It is the app's own
    /// site, which is true of the embed and says who is embedding.
    public static let referrer = "https://microduckstudio.com/"

    /// The page the player sits in: the embed, full-bleed, on a black ground.
    public static func embedPage(for id: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="\(embedURL(for: id))" allow="autoplay; encrypted-media; picture-in-picture"
        referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></body></html>
        """
    }

    public static let refusal =
        "That is not a YouTube link this screen can play. It takes youtube.com/watch?v=…, "
      + "youtu.be/…, a Shorts link, a live link or an embed link."
}

/// Every sentence the mimic screens draw that is not a source's own.
public enum Mimic {

    // MARK: - doors

    /// The Studio row, and the screen's title.
    public static let studioRow = "Mimic a person"
    public static let studioRowSymbol = "figure.arms.open"
    public static let title = "Mimic"

    /// Under the title, once.
    public static let preamble =
        "A person in front of the camera, in a video, or in a YouTube clip is read as a "
      + "skeleton on this phone, and the duck on the picture stands the way they stand. Record "
      + "what you like and keep it as a motion, which runs on a bench like any other."

    /// How a person becomes a duck. Said, because the arm rule is not guessable.
    public static let howItMaps =
        "Legs go to legs and the head to the head. The duck has no arms, so the higher hand "
      + "opens the beak — hand at your shoulder is closed, straight up is wide open."

    public static let nothingLeavesThePhone =
        "The skeleton is worked out on this phone. No picture is recorded, stored or sent "
      + "anywhere by this screen."

    // MARK: - the readout

    public static let noPersonYet =
        "No person in view yet. Stand back so your whole body is in the picture."
    public static let noPersonInTheClip =
        "No person found in this frame. Play a part of the clip where a whole body is in shot."

    public static func tracking(posesPerSecond: Double) -> String {
        String(format: "Tracking · %.0f poses a second", posesPerSecond)
    }

    public static let mirror = "Mirror"
    public static let mirrorSaid =
        "Mirrored, like looking in one: raise your right hand and the duck raises the side on "
      + "your right. Off, the duck faces the way you face."

    // MARK: - recording

    public static let record = "Record"
    public static let stop = "Stop"
    public static let keep = "Keep as a motion"
    public static let recordAgain = "Record again"
    public static let openInEditor = "Open it in the editor"
    public static let done = "Done"

    public static let recordSaid =
        "Recording keeps ten poses a second, smoothed, for up to thirty seconds. Nothing is sent "
      + "while it records."

    public static func kept(_ name: String) -> String {
        "Kept as \(name). It is in Studio with the other motions, and on the Control tab's "
      + "Motions chip."
    }

    public static let nothingRecordedYet = "Nothing recorded yet. Press Record while a person is in view."

    /// The editor was asked for a motion that has left Studio in the meantime.
    public static let motionNotHere = "That motion is not here"
    public static let motionNotHereSaid =
        "It was kept and is no longer in Studio's drafts. Nothing already written into is lost; "
      + "record again to make another."

    // MARK: - sources

    public static let pickVideo = "Choose a video"
    public static let fromFiles = "From Files"
    public static let flipCamera = "Flip camera"
    public static let linkField = "Paste a YouTube link"
    public static let load = "Load"

    /// On the Control tab, where only the camera is offered.
    public static let videoAndYouTubeAreInStudio =
        "A video or a YouTube clip is read in Studio, where there is room for a player."
    public static let openStudio = "Open Mimic in Studio"

    /// The screen-reading permission was refused, or the capture could not start.
    public static func screenReadingFailed(_ reason: String) -> String {
        "The phone could not read its own screen, so the clip cannot be followed. \(reason) "
      + "Playing still works; mimicking does not until it can."
    }

    public static let screenReadingStopped =
        "Screen reading stopped. Press Load again to start it."

    public static func videoCouldNotBeOpened(_ reason: String) -> String {
        "That video could not be opened. \(reason)"
    }

    /// Everything here, for a test to sweep.
    public static let everySentence: [String] = [
        studioRow, title, preamble, howItMaps, nothingLeavesThePhone, noPersonYet,
        noPersonInTheClip, tracking(posesPerSecond: 12), mirror, mirrorSaid, record, stop, keep,
        recordAgain, openInEditor, done, recordSaid, kept("x"), nothingRecordedYet, pickVideo,
        fromFiles, flipCamera, linkField, load, videoAndYouTubeAreInStudio, openStudio,
        screenReadingFailed("x."), screenReadingStopped, videoCouldNotBeOpened("x."),
        YouTubeLink.refusal, MimicTrack.stoppedAtTheCap, motionNotHere, motionNotHereSaid,
    ] + MimicSource.allCases.flatMap { [$0.label, $0.how, $0.whatIsReal] }
}
