import Foundation

/// The one place a finished-but-unfinished surface is switched off for a
/// release, so the code stays and the row stops being listed.
///
/// WHY THIS EXISTS AT ALL. `LabCatalogue` deliberately keeps a row for a mode
/// that is designed and not written, with a reason under its name, because a
/// silent gap is worse than an honest one for somebody reading the app to
/// understand what it does. App Review reads the same row differently: an
/// entry a person cannot open is placeholder content, and placeholder content
/// is a rejection under 2.1 no matter how truthful the sentence beside it is.
///
/// THE TABLE IS NOT EDITED AND NOTHING IS DELETED. `LabCatalogue.modes` still
/// holds every row, every blurb and every reason, and every test that reads
/// them still reads them. What the gate changes is `LabCatalogue.listed(...)`
/// — the list a screen draws — so flipping one Bool here puts the unwritten
/// rows back in front of a developer without restoring a line of copy.
public enum ReleaseGates {

    /// Whether Studio > Modes lists the rows nobody can open yet.
    ///
    /// `false` in every shipped build. Set it to `true` in a local build to see
    /// the designed-not-written rows again.
    public static let showUnfinishedModes = false
}
