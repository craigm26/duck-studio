import Foundation

/// What a scene may be called, and the one thing it may not.
public enum SceneName {

    /// Nil when the typed name can be used. A sentence when it cannot.
    ///
    /// EMPTY IS THE ONLY REFUSAL. A nameless scene is a blank row in the Scenes
    /// list, in the bench's "Stand it in" picker, in the author's scene picker
    /// and in the player's "Play somewhere else" menu — four places where the
    /// only thing telling one row from another IS the name, and one of them is
    /// a menu whose buttons are nothing else. Length is not refused and
    /// duplicates are not refused, because nothing in the app or the kit
    /// resolves a scene by name: every cross-object reference is the id.
    ///
    /// `current` is what the store still holds, so the sentence can say what
    /// the name IS rather than only what it may not become. No scene is ever
    /// born nameless, so `current` is never itself blank.
    public static func refusal(_ typed: String, keeping current: String) -> String? {
        guard typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "A scene with no name is a blank row in every menu that offers it. "
             + "The name is still \u{201C}\(current)\u{201D}."
    }
}
