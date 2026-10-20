#if canImport(RealityKit)
import RealityKit
import Metal
import CoreGraphics
import DuckKit
import DuckRender
import StudioKit

/// The simulated duck's head camera, drawn off screen with RealityKit.
///
/// WHAT IT DRAWS: `DreamPracticeWorld` (the taped mat and three things to walk to) and the duck
/// itself, posed from the bench's state, seen from `SimHeadCamera.pose`, at Dream-1's picture size.
/// It is a drawing for practice, not a camera: StudioKit's comment on `SimHeadCamera` says what a
/// model trained on it does and does not learn.
///
/// NO ARITHMETIC HERE. The pose comes from StudioKit, the conversion to RealityKit's frame from
/// `DuckGhostEntity.rk`, the same one every AR screen uses.
@available(iOS 18.0, macOS 15.0, *)
@MainActor
final class SimHeadCameraRenderer {
    private let renderer: RealityRenderer
    private let duck = DuckGhostEntity()
    private let camera = PerspectiveCamera()
    private let texture: MTLTexture
    private let width = DreamDataset.width, height = DreamDataset.height

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let made = try? RealityRenderer() else { return nil }
        renderer = made
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        self.texture = texture
        camera.camera.fieldOfViewInDegrees = Float(SimHeadCamera.fovyDegrees)  // camera-ok: StudioKit decides it (Pollen's head camera); this only hands it to RealityKit
        camera.camera.near = 0.01
        renderer.entities.append(Self.world())
        renderer.entities.append(duck)
        renderer.entities.append(camera)
        let sun = DirectionalLight()
        sun.light.intensity = 3000
        sun.look(at: .zero, from: SIMD3<Float>(0.6, 2.0, 0.8), relativeTo: nil)
        renderer.entities.append(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 1200
        fill.look(at: .zero, from: SIMD3<Float>(-1.0, 1.5, -0.6), relativeTo: nil)
        renderer.entities.append(fill)
        renderer.activeCamera = camera
    }

    /// One picture of what the duck in `live` sees.
    func render(_ live: DuckDrive.Live) async -> CGImage? {
        duck.place(root: live.stance.root, jointAngles: live.stance.jointAngles)
        let pose = SimHeadCamera.pose(live)
        let eye = DuckGhostEntity.rk(pose.position)
        camera.look(at: eye + DuckGhostEntity.rk(pose.forward), from: eye,
                    upVector: DuckGhostEntity.rk(pose.up), relativeTo: nil)
        do {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 0,
                                                 cameraOutput: .init(.singleProjection(colorTexture: texture)),
                                                 onComplete: { _ in done.resume() })
                } catch { done.resume(throwing: error) }
            }
        } catch { return nil }
        return Self.image(texture, width: width, height: height)
    }

    private static func image(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        let row = width * 4
        var bytes = [UInt8](repeating: 0, count: row * height)
        texture.getBytes(&bytes, bytesPerRow: row, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let drawn = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: row, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let flat = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: space, bitmapInfo: info) else { return nil }
        // OVER THE SKY: the off-screen picture is transparent where nothing was drawn.
        let sky = DreamPracticeWorld.skyRGB
        flat.setFillColor(CGColor(srgbRed: CGFloat(sky.0), green: CGFloat(sky.1), blue: CGFloat(sky.2), alpha: 1))
        flat.fill(CGRect(x: 0, y: 0, width: width, height: height))
        flat.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
        return flat.makeImage()
    }

    /// The practice world, in RealityKit's frame. Unlit, so its colours are its colours under any light.
    private static func world() -> Entity {
        let root = Entity()
        func material(_ rgb: (Double, Double, Double)) -> UnlitMaterial {
            UnlitMaterial(color: .init(red: CGFloat(rgb.0), green: CGFloat(rgb.1), blue: CGFloat(rgb.2), alpha: 1))
        }
        func tile(_ x: Double, _ y: Double, _ along: Double, _ across: Double, _ lift: Double,
                  _ rgb: (Double, Double, Double)) -> ModelEntity {
            let e = ModelEntity(mesh: .generatePlane(width: Float(along), depth: Float(across)),
                                materials: [material(rgb)])
            e.position = DuckGhostEntity.rk(DuckVector(x, y, lift))
            return e
        }
        root.addChild(tile(0.6, 0, 12, 12, 0, DreamPracticeWorld.floorRGB))
        for (x, y, along, across) in DreamPracticeWorld.tape {
            root.addChild(tile(x, y, along, across, 0.0008, DreamPracticeWorld.tapeRGB))
        }
        for thing in DreamPracticeWorld.things {
            switch thing.shape {
            case .tile(let w, let d):
                root.addChild(tile(thing.x, thing.y, w, d, 0.0015, thing.rgb))
            case .ball(let r):
                let e = ModelEntity(mesh: .generateSphere(radius: Float(r)), materials: [material(thing.rgb)])
                e.position = DuckGhostEntity.rk(DuckVector(thing.x, thing.y, r))
                root.addChild(e)
            }
        }
        return root
    }
}
#endif
