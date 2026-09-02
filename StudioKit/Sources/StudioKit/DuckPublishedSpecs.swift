import Foundation

/// Pollen Robotics' published figures for the Microduck, as data.
///
/// WRITTEN DOWN ONCE, WITH THEIR PROVENANCE, SO A SCREEN CANNOT TYPE THEM. The
/// Robot tab drew "25 cm", "800 g" and a sensor list as literals, asserted by
/// nothing `swift test` could read — and one of them disagreed with a number
/// the kit already computes with: `Retrieval.Drag.duckMass` is 0.7372 kg,
/// summed from every inertial in the MJCF this app's physics uses, so the app
/// could print 800 g on one tab while refusing a drag on the basis of 737 g on
/// another. Both numbers are real and they measure different things — a
/// published spec for the shipping robot, and the mass of the model that
/// stands in for it — and a screen that shows one must be able to say which.
///
/// NONE OF THIS IS A MEASUREMENT THIS APP MADE. Every figure is Pollen's, from
/// their published Microduck page, and the day it changes there it changes
/// here; nothing downstream derives from these except a sentence.
public enum DuckPublishedSpecs {
    /// Where the figures come from, for the row that prints them.
    public static let source = "Pollen Robotics' published Microduck specifications"

    public static let heightCentimetres = 25
    public static let massGrams = 800
    public static let sensors = "Camera, LiDAR, two IMUs"

    /// The mass of the physics model, in grams, from the same constant the
    /// drag refusal uses — so the two can never drift apart unnoticed.
    public static var modelledMassGrams: Int { Int((Retrieval.Drag.duckMass * 1000).rounded()) }

    /// The sentence a mass row carries, saying which number is which.
    public static var massNote: String {
        "\(massGrams) g is the published figure. The physics model this app computes with sums "
      + "to \(modelledMassGrams) g from its own inertials, and that is the number every drag "
      + "and carry refusal here is based on."
    }
}
