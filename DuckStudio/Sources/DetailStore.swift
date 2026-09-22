import Foundation
import StudioKit

/// How much of the app to show, and whether the first run has happened.
///
/// TWO SETTINGS IN ONE STORE because they are one decision: the first run is
/// where the level gets chosen, and a person who has answered once must not be
/// asked again. Both live in `UserDefaults` — neither is a credential and
/// neither is worth a Keychain round trip.
@MainActor
final class DetailStore: ObservableObject {

    @Published var level: DetailLevel {
        didSet { UserDefaults.standard.set(level.rawValue, forKey: Self.levelKey) }
    }

    /// Which first run this person has seen, or nil for none.
    @Published private(set) var seenFirstRun: Int? {
        didSet {
            if let seenFirstRun {
                UserDefaults.standard.set(seenFirstRun, forKey: Self.seenKey)
            }
        }
    }

    private static let levelKey = "duckstudio.detailLevel"
    private static let seenKey = "duckstudio.firstRunSeen"

    init() {
        // AN UPDATE MUST NOT TAKE ANYTHING AWAY. Somebody already holding this
        // app has no stored level, and `installedDefault` is Everything, so the
        // screens they installed it for are exactly where they left them.
        let stored = UserDefaults.standard.string(forKey: Self.levelKey)
        level = stored.flatMap(DetailLevel.init(rawValue:)) ?? .installedDefault
        let seen = UserDefaults.standard.object(forKey: Self.seenKey) as? Int
        seenFirstRun = seen
        // A PERSON WHO ALREADY HAS THE APP HAS ALREADY HAD THEIR FIRST RUN.
        // Showing the welcome to somebody on their fortieth launch, just
        // because the flag is new, is the update announcing itself as a
        // stranger. Only a genuinely empty container gets the cards.
        if seen == nil, stored != nil {
            seenFirstRun = FirstRun.currentVersion
        }
    }

    var shouldShowFirstRun: Bool { FirstRun.shouldShow(seenVersion: seenFirstRun) }

    func finishFirstRun(choosing level: DetailLevel?) {
        if let level { self.level = level }
        seenFirstRun = FirstRun.currentVersion
    }

    func shows(_ surface: DetailLevel.Surface) -> Bool { level.shows(surface) }
}
