import RealityKit
import UIKit
import StudioKit

/// The bridge itself: cast iron over a lake, at duck scale.
///
/// Bow Bridge is a cast-iron arch with an ornate balustrade, stone abutments at
/// each end, and the Lake under it. Everything here is scenery — the crossing
/// is decided by `BridgeCrossing`, which knows only a length, a width and an
/// arch, so the two cannot disagree about where the edge is.
enum BowBridgeScene {

    /// Segments across the arch. Twenty-four short boxes each tilted to the
    /// local gradient reads as a smooth curve at this size and costs nothing;
    /// a generated mesh would be prettier and much more code.
    static let segments = 24

    static func build(on anchor: AnchorEntity, deck: BridgeCrossing.Deck) {
        let iron = SimpleMaterial(color: UIColor(red: 0.24, green: 0.29, blue: 0.27, alpha: 1),
                                  roughness: 0.55, isMetallic: true)
        let stone = SimpleMaterial(color: UIColor(red: 0.70, green: 0.67, blue: 0.60, alpha: 1),
                                   roughness: 0.9, isMetallic: false)
        let plank = SimpleMaterial(color: UIColor(red: 0.52, green: 0.42, blue: 0.31, alpha: 1),
                                   roughness: 0.85, isMetallic: false)

        // THE LAKE, and it is what you fall into. Reflective and a little
        // green, sitting below the deck so a swim reads as going down.
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: UIColor(red: 0.10, green: 0.24, blue: 0.22, alpha: 1))
        water.roughness = 0.08
        water.metallic = 0.35
        let lake = ModelEntity(mesh: .generatePlane(width: 6, depth: 4), materials: [water])
        lake.position = SIMD3<Float>(Float(deck.length / 2), -0.08, 0)
        anchor.addChild(lake)

        // The deck, following the arch.
        let width = Float(deck.halfWidth * 2)
        for index in 0..<segments {
            let u0 = Double(index) / Double(segments)
            let u1 = Double(index + 1) / Double(segments)
            let x0 = u0 * deck.length, x1 = u1 * deck.length
            let h0 = deck.height(at: x0), h1 = deck.height(at: x1)
            let run = x1 - x0, rise = h1 - h0
            let length = (run * run + rise * rise).squareRoot()
            let piece = ModelEntity(
                mesh: .generateBox(width: Float(length) * 1.04, height: 0.012, depth: width),
                materials: [plank])
            piece.position = SIMD3<Float>(Float((x0 + x1) / 2), Float((h0 + h1) / 2), 0)
            piece.orientation = simd_quatf(angle: Float(-atan2(rise, run)),
                                           axis: SIMD3<Float>(0, 0, 1))
            anchor.addChild(piece)
        }

        // The balustrade: posts along both edges with a rail on top, following
        // the same arch so the rail is always the same height above the deck.
        for side in [Float(1), -1] {
            for index in 0...segments {
                let u = Double(index) / Double(segments)
                let x = u * deck.length
                let h = deck.height(at: x)
                let post = ModelEntity(
                    mesh: .generateBox(width: 0.012, height: 0.075, depth: 0.012),
                    materials: [iron])
                post.position = SIMD3<Float>(Float(x), Float(h) + 0.043,
                                             side * (width / 2 - 0.006))
                anchor.addChild(post)
                guard index < segments else { continue }
                let x1 = Double(index + 1) / Double(segments) * deck.length
                let h1 = deck.height(at: x1)
                let run = x1 - x, rise = h1 - h
                let rail = ModelEntity(
                    mesh: .generateBox(width: Float((run * run + rise * rise).squareRoot()) * 1.05,
                                       height: 0.008, depth: 0.010),
                    materials: [iron])
                rail.position = SIMD3<Float>(Float((x + x1) / 2), Float((h + h1) / 2) + 0.078,
                                             side * (width / 2 - 0.006))
                rail.orientation = simd_quatf(angle: Float(-atan2(rise, run)),
                                              axis: SIMD3<Float>(0, 0, 1))
                anchor.addChild(rail)
            }
        }

        // Stone abutments, so the bridge lands on something.
        for end in [Float(0), Float(deck.length)] {
            let block = ModelEntity(
                mesh: .generateBox(width: 0.16, height: 0.14, depth: width + 0.09),
                materials: [stone])
            block.position = SIMD3<Float>(end, -0.07, 0)
            anchor.addChild(block)
        }

        // A few trees on the banks. Central Park, at 1:1 with a 25 cm duck, is
        // a handful of saplings — anything taller would fill the phone.
        let bark = SimpleMaterial(color: UIColor(red: 0.30, green: 0.23, blue: 0.17, alpha: 1),
                                  roughness: 0.9, isMetallic: false)
        let leaves = SimpleMaterial(color: UIColor(red: 0.18, green: 0.36, blue: 0.20, alpha: 1),
                                    roughness: 0.85, isMetallic: false)
        for (tx, tz, scale) in [(-0.35, 0.62, 1.0), (-0.20, -0.70, 0.8),
                                (4.35, 0.68, 0.95), (4.25, -0.60, 1.1),
                                (2.0, 1.15, 0.7), (2.4, -1.20, 0.85)] {
            // A box, not a cylinder: generateCylinder is iOS 18 only and this
            // ships lower. At 12 mm across nobody can tell the difference.
            let trunk = ModelEntity(
                mesh: .generateBox(width: 0.022, height: Float(0.22 * scale), depth: 0.022),
                materials: [bark])
            trunk.position = SIMD3<Float>(Float(tx), Float(0.11 * scale) - 0.02, Float(tz))
            anchor.addChild(trunk)
            let canopy = ModelEntity(
                mesh: .generateSphere(radius: Float(0.11 * scale)), materials: [leaves])
            canopy.position = SIMD3<Float>(Float(tx), Float(0.26 * scale) - 0.02, Float(tz))
            anchor.addChild(canopy)
        }

        let key = DirectionalLight()
        key.light.intensity = 2600
        key.light.color = UIColor(red: 1.0, green: 0.95, blue: 0.86, alpha: 1)
        key.look(at: .zero, from: SIMD3<Float>(1.5, 2.0, 1.2), relativeTo: nil)
        anchor.addChild(key)
    }
}
