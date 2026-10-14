import Foundation
import CAprilTag
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DuckCards {

    /// Finds Duck Card codes in a grey picture, with the AprilTag library.
    ///
    /// SETTINGS ARE THE DUCK'S READER'S, AND FOR THE DUCK'S FRAMES. Full
    /// resolution (`quad_decimate` 1): the head camera's upright picture is 720
    /// wide and a card at half a metre has a code about 26 px across, so
    /// halving the picture loses the far cards first. Edges refined, because the
    /// rows are built from the corners. One bit of correction, matching
    /// `maxHamming`: anything the library would fix beyond that is refused
    /// anyway, and the table for one bit is the small one, which matters on a
    /// phone.
    ///
    /// NOT THREAD-SAFE. The library's detector is one object with scratch
    /// space; give each queue its own finder.
    public final class Finder {
        private let detector: UnsafeMutablePointer<apriltag_detector_t>
        private let family: UnsafeMutablePointer<apriltag_family_t>

        public init(threads: Int = 2) {
            family = tag36h11_create()
            detector = apriltag_detector_create()
            apriltag_detector_add_family_bits(detector, family, 1)
            detector.pointee.quad_decimate = 1.0
            detector.pointee.quad_sigma = 0.0
            detector.pointee.refine_edges = true
            detector.pointee.decode_sharpening = 0.25
            detector.pointee.nthreads = Int32(max(1, threads))
        }

        deinit {
            apriltag_detector_destroy(detector)
            tag36h11_destroy(family)
        }

        /// Every tag36h11 code in a grey picture, one byte a pixel, row by row.
        public func find(grey: [UInt8], width: Int, height: Int) -> [Detection] {
            precondition(grey.count >= width * height, "a picture smaller than its size")
            var out: [Detection] = []
            grey.withUnsafeBufferPointer { buffer in
                var image = image_u8_t(width: Int32(width), height: Int32(height), stride: Int32(width),
                                       buf: UnsafeMutablePointer(mutating: buffer.baseAddress))
                guard let found = apriltag_detector_detect(detector, &image) else { return }
                defer { apriltag_detections_destroy(found) }
                for i in 0..<zarray_size(found) {
                    var det: UnsafeMutablePointer<apriltag_detection_t>?
                    zarray_get(found, i, &det)
                    guard let d = det?.pointee else { continue }
                    let p = d.p
                    out.append(Detection(
                        id: Int(d.id), hamming: Int(d.hamming), margin: Double(d.decision_margin),
                        corners: [Point(p.0.0, p.0.1), Point(p.1.0, p.1.1), Point(p.2.0, p.2.1), Point(p.3.0, p.3.1)]))
                }
            }
            return out
        }
    }

    /// One picture, read: what was seen, the rows, and the program.
    public struct Reading: Sendable {
        public let look: Look
        public let layout: Layout
        public let program: Program
    }

    /// `counts` answers the Repeat numbers a reading asked about (`Program.asks`), by position.
    public static func reading(_ detections: [Detection], deck: Deck, counts: [Int: Int] = [:]) -> Reading {
        let look = self.look(detections, deck: deck)
        let layout = arrange(look.seen)
        return Reading(look: look, layout: layout, program: read(layout, deck: deck, counts: counts))
    }

    /// The same reading with Repeat numbers answered: what the person told Studio when it asked.
    public static func answered(_ reading: Reading, deck: Deck, counts: [Int: Int]) -> Reading {
        Reading(look: reading.look, layout: reading.layout, program: read(reading.layout, deck: deck, counts: counts))
    }

    #if canImport(CoreGraphics)
    /// The grey bytes of a picture — what `DuckCamera` hands back from the robot's `/frame` — for
    /// `Finder.find`. Drawn into an 8-bit grey context, which is the luminance the library wants.
    public static func grey(_ image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? (bytes, w, h) : nil
    }
    #endif
}
