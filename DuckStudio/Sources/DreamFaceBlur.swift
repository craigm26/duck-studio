import CoreGraphics
import CoreImage
import Vision

/// Faces blurred out of a picture before it goes to Dream Labs, as a run or in a recording.
///
/// WHY HERE. Dream Labs' own station blurs faces on the robot before frames leave it; their
/// gateway does not, so a client that talks to it directly has to (their docs: "a third-party
/// client that wants faces scrubbed must do it before sending"). Every picture this app sends or
/// records for Dream-1 passes through `scrubbed(_:)` first.
///
/// FOUND ON THE FULL PICTURE, before it is shrunk to 320 by 176, where a face across the room is
/// still big enough to find. Each face box is grown by a quarter on every side, then pixellated
/// past recognising. If Vision fails, the picture is NOT sent as it was: `scrubbed` returns nil
/// and the caller drops that frame.
enum DreamFaceBlur {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func scrubbed(_ image: CGImage) -> CGImage? {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        let faces = request.results ?? []
        if faces.isEmpty { return image }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let source = CIImage(cgImage: image)
        var out = source
        for face in faces {
            // Vision's boxes are normalised with the origin at the bottom left, as Core Image's are.
            let box = VNImageRectForNormalizedRect(face.boundingBox, Int(width), Int(height))
            let grown = box.insetBy(dx: -box.width / 4, dy: -box.height / 4).intersection(source.extent)
            // Six blocks across the face whatever its size: a shape, not a person.
            let block = max(max(grown.width, grown.height) / 6, 4)
            let pixellated = source.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: block,
                                                            kCIInputCenterKey: CIVector(x: grown.minX, y: grown.minY)])
            out = pixellated.cropped(to: grown).composited(over: out)
        }
        return context.createCGImage(out, from: source.extent)
    }
}
