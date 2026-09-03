import Foundation
import StudioKit

/// Which sheet the Control tab's chrome is showing, if any.
///
/// ONE `Identifiable` ENUM AND ONE `.sheet(item:)`, WHICH IS THE POINT. The
/// alternative is four `@State private var showingX = false` and four
/// `.sheet(isPresented:)` modifiers, and SwiftUI is entitled to present all of
/// them — the bug that arrangement produces is two sheets racing over a live
/// picture with a drive loop still running underneath. One item can hold one
/// value, so the tab can be showing exactly one thing.
///
/// THE MAP CASE CARRIES A CONTROL BECAUSE THE ROW IS THE DOOR. Tapping a button
/// row in the map section opens the bind sheet already pointed at that control;
/// opening the map from the chrome opens it at the list. Same sheet, one
/// optional.
enum PadSheet: Identifiable {
    case keep
    case talk
    case map(DuckPad.Control?)
    case sequences

    var id: String {
        switch self {
        case .keep: return "keep"
        case .talk: return "talk"
        case .map(let control): return "map-\(control?.rawValue ?? "all")"
        case .sequences: return "sequences"
        }
    }
}
