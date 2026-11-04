import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// A phone driver's network: anything that turns `DriverInput` into 48 rows of three numbers.
public protocol DriverNet: Sendable {
    func infer(_ input: DriverInput) throws -> [Float]
}

/// Duck Driver S1, in plain Swift: the network `duckbatch/scripts/bc_ducknet.py` trains.
///
/// THE SAME LAYERS, NAMES AND ORDER AS THE PYTORCH CLASS, which is the whole contract:
///   conv1 5x5 s2 p2 6->16, conv2 5x5 s2 p2 16->32, conv3 3x3 s2 p1 32->64,
///   conv4 3x3 s2 p1 64->64 (each then ReLU; 88x160 -> 44x80 -> 22x40 -> 11x20 -> 6x10),
///   flatten in channel, row, column order (3840), fc1 -> 256 + ReLU, fc2 -> 144.
/// Flattening, not averaging, keeps where the ball is: left of the picture and right of it are
/// different numbers, which a global average would have thrown away.
///
/// EVERY CONV IS IM2COL THEN ONE MATRIX PRODUCT: Accelerate's `cblas_sgemm` where it exists (the
/// phone, the Mac), a plain loop elsewhere (Linux, where the tests run). The tests hold both to
/// PyTorch's numbers through `DriverGolden`.
public struct DuckNetS1: DriverNet {
    struct Conv { let w: [Float]; let b: [Float]; let cin: Int; let cout: Int; let k: Int; let stride: Int; let pad: Int }
    struct Dense { let w: [Float]; let b: [Float]; let cin: Int; let cout: Int }

    let convs: [Conv]
    let fc1: Dense
    let fc2: Dense
    /// Whether to use Accelerate when it is there; the tests turn it off to compare the two paths.
    public var accelerated = true

    public enum Problem: Error, Equatable, Sendable {
        case missing(String), shape(String, [Int]), input(Int)
        public var message: String {
            switch self {
            case .missing(let n): return "This driver's weights have no tensor \(n)."
            case .shape(let n, let s): return "This driver's tensor \(n) is \(s), not the shape ducknet-s1 needs."
            case .input(let n): return "The driver was handed \(n) numbers, not two pictures."
            }
        }
    }

    static let layout: [(name: String, cin: Int, cout: Int, k: Int, stride: Int, pad: Int)] = [
        ("conv1", 6, 16, 5, 2, 2), ("conv2", 16, 32, 5, 2, 2), ("conv3", 32, 64, 3, 2, 1), ("conv4", 64, 64, 3, 2, 1),
    ]
    static let flat = 64 * 6 * 10, hidden = 256, outputs = 48 * 3

    public init(_ file: SafeTensors) throws {
        func tensor(_ name: String, _ shape: [Int]) throws -> [Float] {
            guard let t = file.tensors[name] else { throw Problem.missing(name) }
            guard t.shape == shape else { throw Problem.shape(name, t.shape) }
            return t.values
        }
        convs = try Self.layout.map { l in
            Conv(w: try tensor("\(l.name).weight", [l.cout, l.cin, l.k, l.k]), b: try tensor("\(l.name).bias", [l.cout]),
                 cin: l.cin, cout: l.cout, k: l.k, stride: l.stride, pad: l.pad)
        }
        fc1 = Dense(w: try tensor("fc1.weight", [Self.hidden, Self.flat]), b: try tensor("fc1.bias", [Self.hidden]),
                    cin: Self.flat, cout: Self.hidden)
        fc2 = Dense(w: try tensor("fc2.weight", [Self.outputs, Self.hidden]), b: try tensor("fc2.bias", [Self.outputs]),
                    cin: Self.hidden, cout: Self.outputs)
    }

    public func infer(_ input: DriverInput) throws -> [Float] {
        let size = DriverInput.channels * DriverInput.height * DriverInput.width
        guard input.values.count == size else { throw Problem.input(input.values.count) }
        var x = input.values, h = DriverInput.height, w = DriverInput.width
        for c in convs {
            let oh = (h + 2 * c.pad - c.k) / c.stride + 1, ow = (w + 2 * c.pad - c.k) / c.stride + 1
            let cols = Self.im2col(x, c: c.cin, h: h, w: w, k: c.k, stride: c.stride, pad: c.pad, oh: oh, ow: ow)
            // out[cout, oh*ow] = W[cout, cin*k*k] x cols[cin*k*k, oh*ow]
            var out = gemm(c.w, cols, m: c.cout, n: oh * ow, k: c.cin * c.k * c.k)
            for o in 0..<c.cout {
                let b = c.b[o]
                for i in 0..<(oh * ow) { out[o * oh * ow + i] = max(out[o * oh * ow + i] + b, 0) }
            }
            x = out; h = oh; w = ow
        }
        var hidden = gemm(fc1.w, x, m: fc1.cout, n: 1, k: fc1.cin)
        for i in 0..<hidden.count { hidden[i] = max(hidden[i] + fc1.b[i], 0) }
        var out = gemm(fc2.w, hidden, m: fc2.cout, n: 1, k: fc2.cin)
        for i in 0..<out.count { out[i] += fc2.b[i] }
        return out
    }

    /// Rows are (channel, ky, kx), columns are output pixels, zero outside the picture.
    static func im2col(_ x: [Float], c: Int, h: Int, w: Int, k: Int, stride: Int, pad: Int, oh: Int, ow: Int) -> [Float] {
        var cols = [Float](repeating: 0, count: c * k * k * oh * ow)
        x.withUnsafeBufferPointer { src in
            cols.withUnsafeMutableBufferPointer { dst in
                for ch in 0..<c {
                    for ky in 0..<k {
                        for kx in 0..<k {
                            let row = ((ch * k + ky) * k + kx) * oh * ow
                            for oy in 0..<oh {
                                let iy = oy * stride + ky - pad
                                if iy < 0 || iy >= h { continue }
                                let base = (ch * h + iy) * w
                                for ox in 0..<ow {
                                    let ix = ox * stride + kx - pad
                                    if ix >= 0 && ix < w { dst[row + oy * ow + ox] = src[base + ix] }
                                }
                            }
                        }
                    }
                }
            }
        }
        return cols
    }

    /// C[m, n] = A[m, k] x B[k, n], all row-major.
    func gemm(_ a: [Float], _ b: [Float], m: Int, n: Int, k: Int) -> [Float] {
        var c = [Float](repeating: 0, count: m * n)
        #if canImport(Accelerate)
        if accelerated {
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(m), Int32(n), Int32(k),
                        1, a, Int32(k), b, Int32(n), 0, &c, Int32(n))
            return c
        }
        #endif
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                c.withUnsafeMutableBufferPointer { pc in
                    for i in 0..<m {
                        for p in 0..<k {
                            let av = pa[i * k + p]
                            if av == 0 { continue }
                            let bRow = p * n, cRow = i * n
                            for j in 0..<n { pc[cRow + j] += av * pb[bRow + j] }
                        }
                    }
                }
            }
        }
        return c
    }
}

/// The check a driver passes before it is installed: regenerate the golden inputs, run this
/// device's own forward pass, compare with what PyTorch computed when the driver was written.
public enum DriverGolden {
    public struct File: Decodable, Sendable {
        public let seeds: [UInt64]
        public let outputs: [[Float]]
        public let tolerance: Float?
    }

    public struct Problem: Error, Equatable, Sendable {
        public let seed: UInt64, row: Int, column: Int, error: Float
        public var message: String {
            String(format: "This driver's numbers on this device differ from its own test answers "
                + "(test %llu, step %d, %@, off by %.4g), so it was not installed.",
                   seed, row + 1, ["forward", "sideways", "turn"][column], error)
        }
    }

    /// The input for a seed: SplitMix64(seed:).next() mapped to [-1, 1), as bc_ducknet.py makes it.
    public static func input(seed: UInt64) -> DriverInput {
        var rng = SplitMix64(seed: seed)
        let n = DriverInput.channels * DriverInput.height * DriverInput.width
        return DriverInput(values: (0..<n).map { _ in Float(rng.next() * 2 - 1) })
    }

    public static func read(_ data: Data) throws -> File { try JSONDecoder().decode(File.self, from: data) }

    /// Nil when every output is within tolerance; else the worst miss, named.
    public static func check(net: any DriverNet, golden: File, tolerance: Float = 1e-3) throws -> Problem? {
        var worst: Problem?
        for (seed, want) in zip(golden.seeds, golden.outputs) {
            let got = try net.infer(input(seed: seed))
            for (i, (g, w)) in zip(got, want).enumerated() {
                let e = abs(g - w)
                if !(e <= tolerance), e > (worst?.error ?? -1) || !e.isFinite {
                    worst = Problem(seed: seed, row: i / 3, column: i % 3, error: e.isFinite ? e : .infinity)
                }
            }
            if got.count != want.count { return Problem(seed: seed, row: 0, column: 0, error: .infinity) }
        }
        return worst
    }
}
