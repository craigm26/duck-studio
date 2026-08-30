import Foundation

/// The sentences printed beside the robot on a stage.
///
/// WHY THEY ARE NOT WRITTEN AT THE CALL SITE. Every one of these makes a claim,
/// and two of them were wrong for a whole build in a way nothing could catch. A
/// caption built from steps and walls alone said "bare floor" over the one
/// shipped scene that is nothing BUT things to pick up. And a clearance reading
/// written to accuse the RENDERER — "nothing should be floating" — was being run
/// against a preview whose trunk is pinned on purpose, where a positive reading
/// is the arithmetic consequence of the pinning rather than a fault in anybody's
/// motion. A claim inside a `Text(...)` is a claim nothing asserts; here
/// `swift test` reads them letter by letter on Linux.
public enum StageCaption {

    // MARK: - what is in the place

    /// The clauses naming what is standing in a place, in the order somebody
    /// would read them. Empty means there is nothing but floor.
    ///
    /// PROPS COUNT AS SOMETHING BEING THERE. They were left out of both the
    /// scene's own one-line summary and the caption over the stage, because
    /// `DuckIntentClip.Environment` — the recorded world a caption used to be
    /// built from — has no room for them. So "Broom in the corner", which ships
    /// on every phone and holds a broom, a dowel and a pencil, was captioned
    /// "Bare floor" in the list and "100 mm grid · bare floor" over a stage
    /// drawing all three.
    ///
    /// ONE FUNCTION, TWO CALLERS, so the row and the legend cannot drift. They
    /// were hand-copies of each other and both carried the same falsehood.
    public static func contents(stepCount: Int, tallestStepMetres: Double,
                                wallCount: Int, propCount: Int) -> [String] {
        var parts: [String] = []
        if stepCount > 0 {
            parts.append("\(stepCount) step\(stepCount == 1 ? "" : "s") "
                       + "to \(Int((tallestStepMetres * 1000).rounded())) mm")
        }
        if wallCount > 0 {
            parts.append("\(wallCount) wall\(wallCount == 1 ? "" : "s")")
        }
        if propCount > 0 {
            parts.append("\(propCount) thing\(propCount == 1 ? "" : "s") to pick up")
        }
        return parts
    }

    /// The line under the stage: the grid, then whatever is standing on it.
    public static func context(stepCount: Int, tallestStepMetres: Double,
                               wallCount: Int, propCount: Int) -> String {
        let parts = contents(stepCount: stepCount, tallestStepMetres: tallestStepMetres,
                             wallCount: wallCount, propCount: propCount)
        return (["100 mm grid"] + (parts.isEmpty ? ["bare floor"] : parts))
            .joined(separator: " · ")
    }

    // MARK: - a trunk that was never recorded

    /// The trunk line when the root is PINNED rather than recorded.
    ///
    /// A recorded clip's x/y/z says where physics put the body, which is the
    /// number the whole legend exists for. On an authored draft those three
    /// numbers are constants — they cannot change, whatever anybody drags — so
    /// printing them beside a camera-follow button invites the reader to look
    /// for travel that is not there. Say what the pin IS instead.
    public static func pinnedTrunk(heightMetres: Double) -> String {
        String(format: "Trunk pinned at %.0f mm — a draft carries joints, not where the body went.",
               heightMetres * 1000)
    }

    /// The ground reading under a pinned root.
    ///
    /// THE NUMBER STAYS; THE VERDICT GOES. `DuckGroundClearance.summary` is
    /// written to accuse the renderer — its own header says the point of
    /// printing the number is that a build which drew every clip floating at
    /// 116 mm could not ship again — and `isWrong` colours it orange. Against a
    /// pinned trunk that accusation is structurally guaranteed to fire on
    /// ordinary work: pin the body, fold the legs, and the feet must leave the
    /// floor. Measured on the real meshes, a slider-legal squat reads +39 mm and
    /// turns the line orange while the Checks tab, two taps away, says nothing
    /// is wrong. So the drawn distance is still reported — it is true, and it is
    /// the only thing on screen that would catch the old bug — and the sentence
    /// beside it names the pin rather than blaming the pose.
    ///
    /// NO DIRECTION IS CLAIMED. Which way a given gesture moves the feet depends
    /// on the mirrored left/right pitch convention: knees alone sink, a hip fold
    /// with the knees near straight floats. Two measured sweeps disagreed on it,
    /// so the sentence does not say.
    public static func pinnedGround(clearanceMetres: Double) -> String {
        let mm = clearanceMetres * 1000
        if mm > 5 {
            return String(format: "%.0f mm above the grid. The trunk is pinned, so this is where "
                                + "the pose puts the feet — not a fault in the motion.", mm)
        }
        if mm < -5 {
            return String(format: "%.0f mm below the grid. The trunk is pinned, so this is where "
                                + "the pose puts the feet — not a fault in the motion.", -mm)
        }
        return String(format: "%+.0f mm — the feet are on the grid, with the trunk pinned.", mm)
    }

    // MARK: - a scene that is not there any more

    /// Shown when a draft names a scene this phone no longer holds.
    ///
    /// A DELETED SCENE USED TO BE INDISTINGUISHABLE FROM NO SCENE. The lookup
    /// failed soft to `.bareFloor`, nothing walked the drafts when a scene was
    /// swiped away, and the menu carried no selection — so a stair motion
    /// reopened on an empty floor with the same caption a never-scened draft
    /// gets, and nothing on screen could tell the two apart.
    public static let sceneDeleted =
        "The scene this motion was written against has been deleted, so it is being posed on a "
      + "bare floor. Pick another one, or write it against the floor on purpose."
}
