import Foundation

/// A `.safetensors` file, read without trusting it: the format a phone driver's weights come in.
///
/// THE FORMAT (huggingface/safetensors): 8 bytes, a little-endian UInt64 N; then N bytes of
/// JSON mapping each tensor name to `{dtype, shape, data_offsets: [begin, end]}` (offsets into
/// the bytes after the header), plus an optional `__metadata__` of strings; then the data.
///
/// ONLY F32, AND EVERY RANGE CHECKED. A driver is downloaded from a repo anyone can push to, so a
/// header that claims a range past the end, ranges that overlap, a shape whose element count
/// disagrees with its byte range, or a header too large to be honest is refused by name, before
/// any number is read. `DuckNetS1` then checks the names and shapes it needs.
public struct SafeTensors: Sendable {
    public struct Tensor: Equatable, Sendable {
        public let shape: [Int]
        public let values: [Float]
    }

    public enum Problem: Error, Equatable, Sendable {
        case tooShort
        case headerLength(UInt64)
        case headerNotJSON
        case badEntry(String)
        case dtype(String, String)
        case outOfRange(String)
        case overlap(String, String)
        case shapeMismatch(String)

        public var message: String {
            switch self {
            case .tooShort: return "The weights file is shorter than its own header says."
            case .headerLength(let n): return "The weights file claims a header of \(n) bytes, more than a driver needs."
            case .headerNotJSON: return "The weights file's header is not the JSON a safetensors file starts with."
            case .badEntry(let name): return "The weights file describes tensor \(name) in a way this app cannot read."
            case .dtype(let name, let dtype): return "Tensor \(name) is \(dtype); a phone driver's weights are F32."
            case .outOfRange(let name): return "Tensor \(name) points past the end of the weights file."
            case .overlap(let a, let b): return "Tensors \(a) and \(b) claim the same bytes."
            case .shapeMismatch(let name): return "Tensor \(name)'s shape does not match its size in the file."
            }
        }
    }

    /// The largest header a driver's file may have: a few dozen tensors need a few kilobytes.
    public static let maxHeader: UInt64 = 1 << 20

    public let tensors: [String: Tensor]
    public let metadata: [String: String]

    public init(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { throw Problem.tooShort }
        var n: UInt64 = 0
        for i in 0..<8 { n |= UInt64(bytes[i]) << (8 * UInt64(i)) }
        guard n <= Self.maxHeader else { throw Problem.headerLength(n) }
        guard UInt64(bytes.count) >= 8 + n else { throw Problem.tooShort }
        let headerEnd = 8 + Int(n)
        guard let header = try? JSONSerialization.jsonObject(with: Data(bytes[8..<headerEnd])) as? [String: Any] else {
            throw Problem.headerNotJSON
        }
        let dataCount = bytes.count - headerEnd
        var metadata: [String: String] = [:]
        var ranges: [(name: String, lo: Int, hi: Int)] = []
        var described: [(name: String, shape: [Int], lo: Int, hi: Int)] = []
        for (name, raw) in header {
            if name == "__metadata__" {
                for (k, v) in raw as? [String: Any] ?? [:] { if let s = v as? String { metadata[k] = s } }
                continue
            }
            guard let entry = raw as? [String: Any],
                  let dtype = entry["dtype"] as? String,
                  let shapeRaw = entry["shape"] as? [NSNumber],
                  let offsets = entry["data_offsets"] as? [NSNumber], offsets.count == 2 else {
                throw Problem.badEntry(name)
            }
            guard dtype == "F32" else { throw Problem.dtype(name, dtype) }
            let shape = shapeRaw.map(\.intValue)
            let lo = offsets[0].intValue, hi = offsets[1].intValue
            guard shape.allSatisfy({ $0 >= 0 }), lo >= 0, hi >= lo else { throw Problem.badEntry(name) }
            guard hi <= dataCount else { throw Problem.outOfRange(name) }
            let elements = shape.reduce(1) { $0.multipliedReportingOverflow(by: $1).overflow ? Int.max : $0 * $1 }
            guard elements != Int.max, elements * 4 == hi - lo else { throw Problem.shapeMismatch(name) }
            ranges.append((name, lo, hi))
            described.append((name, shape, lo, hi))
        }
        let sorted = ranges.filter { $0.hi > $0.lo }.sorted { $0.lo < $1.lo }
        for (a, b) in zip(sorted, sorted.dropFirst()) where b.lo < a.hi { throw Problem.overlap(a.name, b.name) }
        var tensors: [String: Tensor] = [:]
        for t in described {
            var values = [Float](repeating: 0, count: (t.hi - t.lo) / 4)
            for i in 0..<values.count {
                let at = headerEnd + t.lo + 4 * i
                let bits = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
                values[i] = Float(bitPattern: bits)
            }
            tensors[t.name] = Tensor(shape: t.shape, values: values)
        }
        self.tensors = tensors
        self.metadata = metadata
    }

    /// A file holding `tensors` (F32, little-endian), in name order: what the tests and the
    /// training script's golden-only mode write.
    public static func encode(_ tensors: [String: Tensor], metadata: [String: String] = [:]) -> Data {
        var header: [String: Any] = [:]
        if !metadata.isEmpty { header["__metadata__"] = metadata }
        var body = Data()
        for name in tensors.keys.sorted() {
            let t = tensors[name]!
            let lo = body.count
            for v in t.values {
                let bits = v.bitPattern
                body.append(contentsOf: [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)])
            }
            header[name] = ["dtype": "F32", "shape": t.shape, "data_offsets": [lo, body.count]]
        }
        let json = (try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])) ?? Data("{}".utf8)
        var out = Data()
        let n = UInt64(json.count)
        for i in 0..<8 { out.append(UInt8(n >> (8 * UInt64(i)) & 0xFF)) }
        out.append(json)
        out.append(body)
        return out
    }
}
