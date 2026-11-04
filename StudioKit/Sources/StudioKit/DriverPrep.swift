import Foundation
import Crypto

/// The SHA-256 a driver's files are pinned by, as lowercase hex.
public enum DriverHash {
    public static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A driver's input: two head-camera pictures stacked, channels first, normalised.
public struct DriverInput: Equatable, Sendable {
    public static let channels = 6, height = 88, width = 160
    public let values: [Float]
    public init(values: [Float]) { self.values = values }
}

/// From the camera window to the network's numbers, and from its numbers to walk commands.
///
/// THE SAME STEPS AS TRAINING (`duckbatch/scripts/bc_ducknet.py`), because a driver is only as
/// good as the match between what it learned from and what it is shown:
/// - the pictures are the recorder's size, 320 by 176 RGB, averaged 2 by 2 down to 160 by 88;
/// - the frames are now and 0.4 s ago (`frame_offsets` [0, -4] at 10 fps), taken from
///   `DreamFrameWindow`, which keeps one every 0.2 s, so -4 frames is two places back;
/// - before the window holds that far back, the oldest picture stands in, as training clamps
///   to an episode's first frame;
/// - each channel is normalised by the manifest's mean and standard deviation, on 0 to 1 values.
public enum DriverPrep {
    public static let pictureWidth = 320, pictureHeight = 176
    /// Dataset frames (10 fps) per window place (one every 0.2 s).
    public static let framesPerPlace = 2

    public enum Problem: Error, Equatable, Sendable {
        case noPicture, badPicture(Int), badOutput(Int)
    }

    /// The window places the input reads, oldest last, for a window of `count` pictures.
    public static func places(offsets: [Int], count: Int) -> [Int] {
        offsets.map { max(count - 1 + $0 / framesPerPlace, 0) }
    }

    /// `pictures` are RGB bytes, 320 x 176 x 3 each, oldest first (the window, decoded).
    public static func input(pictures: [[UInt8]], manifest: DriverManifest) throws -> DriverInput {
        guard !pictures.isEmpty else { throw Problem.noPicture }
        let size = pictureWidth * pictureHeight * 3
        for (i, p) in pictures.enumerated() where p.count != size { throw Problem.badPicture(i) }
        let (h, w) = (DriverInput.height, DriverInput.width)
        var out = [Float](repeating: 0, count: DriverInput.channels * h * w)
        for (slot, place) in places(offsets: manifest.frameOffsets, count: pictures.count).enumerated() {
            let p = pictures[place]
            for c in 0..<3 {
                let mean = manifest.imgMean[c], std = manifest.imgStd[c]
                let plane = (slot * 3 + c) * h * w
                for y in 0..<h {
                    for x in 0..<w {
                        let a = ((2 * y) * pictureWidth + 2 * x) * 3 + c
                        let b = a + 3, d = a + pictureWidth * 3, e = d + 3
                        let sum = Float(p[a]) + Float(p[b]) + Float(p[d]) + Float(p[e])
                        out[plane + y * w + x] = (sum / (4 * 255) - mean) / std
                    }
                }
            }
        }
        return DriverInput(values: out)
    }

    /// The network's flat output as walk commands: `rows` x 3, un-normalised. Refused whole if any
    /// value is not finite or the count is wrong, never played in part.
    public static func rows(_ flat: [Float], rows: Int, manifest: DriverManifest) throws -> [DuckDrive.Twist] {
        guard flat.count == rows * 3 else { throw Problem.badOutput(flat.count) }
        if let bad = flat.firstIndex(where: { !$0.isFinite }) { throw Problem.badOutput(bad) }
        return (0..<rows).map { r in
            func v(_ c: Int) -> Double { Double(flat[r * 3 + c] * manifest.actStd[c] + manifest.actMean[c]) }
            return DuckDrive.Twist(vx: v(0), vy: v(1), vyaw: v(2))
        }
    }
}
