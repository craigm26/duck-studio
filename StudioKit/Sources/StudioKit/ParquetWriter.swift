import Foundation

/// A Parquet file, written by hand: one row group, every column uncompressed and PLAIN.
///
/// WHY BY HAND. LeRobot's episode tables are Parquet, and Dream Labs reads them with pyarrow. There
/// is no Parquet library for Swift that runs on a phone without a C++ toolchain, and the tables
/// this app writes are small and fixed: integers, floats, and lists of floats of one width. That
/// subset of the format (Apache Parquet, `parquet.thrift`) is a few hundred lines, so it is here,
/// held by a test to what pyarrow and Dream Labs' own dataset checks read back.
///
/// WHAT IT WRITES: a `required` column per scalar, and per vector the standard three-level LIST
/// (`required group <name> (LIST) { repeated group list { required float element } }`), which pyarrow
/// reads as `list<element: float>`.
public struct ParquetWriter {
    public enum Column {
        case int64(String, [Int64])
        case float(String, [Float])
        case floatList(String, [[Float]])

        var name: String {
            switch self { case .int64(let n, _), .float(let n, _), .floatList(let n, _): return n }
        }
        var rows: Int {
            switch self {
            case .int64(_, let v): return v.count
            case .float(_, let v): return v.count
            case .floatList(_, let v): return v.count
            }
        }
    }

    public enum Misuse: Error, Equatable { case rowsDiffer, emptyTable, ragged(String) }

    // parquet.thrift's numbers
    private enum PType: Int32 { case int64 = 2, float = 4 }
    private static let required: Int32 = 0, repeated: Int32 = 2, listConverted: Int32 = 3

    public static func write(_ columns: [Column], createdBy: String = "microduck-studio") throws -> Data {
        guard let rows = columns.first?.rows, rows > 0 else { throw Misuse.emptyTable }
        guard columns.allSatisfy({ $0.rows == rows }) else { throw Misuse.rowsDiffer }
        var file = Data("PAR1".utf8)
        var chunks: [Data] = []
        var total: Int64 = 0
        for column in columns {
            let offset = Int64(file.count)
            let (page, values, type, path) = try Self.page(column)
            file.append(page)
            total += Int64(page.count)
            var meta = Thrift()
            meta.i32(1, type.rawValue)
            meta.list(2, Thrift.i32Type, [Int32(0), 3].map { Thrift.zigzag32($0) })   // PLAIN, RLE
            meta.stringList(3, path)
            meta.i32(4, 0)                                   // UNCOMPRESSED
            meta.i64(5, Int64(values))
            meta.i64(6, Int64(page.count))
            meta.i64(7, Int64(page.count))
            meta.i64(9, offset)
            meta.stop()
            var chunk = Thrift()
            chunk.i64(2, offset)
            chunk.structField(3, meta.bytes)
            chunk.stop()
            chunks.append(chunk.bytes)
        }
        var group = Thrift()
        group.structList(1, chunks)
        group.i64(2, total)
        group.i64(3, Int64(rows))
        group.stop()

        var schema: [Data] = []
        var root = Thrift()
        root.string(4, "schema")
        root.i32(5, Int32(columns.count))
        root.stop()
        schema.append(root.bytes)
        for column in columns {
            switch column {
            case .int64(let n, _): schema.append(Self.leaf(n, .int64))
            case .float(let n, _): schema.append(Self.leaf(n, .float))
            case .floatList(let n, _):
                var outer = Thrift()
                outer.i32(3, required); outer.string(4, n); outer.i32(5, 1); outer.i32(6, listConverted); outer.stop()
                var middle = Thrift()
                middle.i32(3, repeated); middle.string(4, "list"); middle.i32(5, 1); middle.stop()
                schema += [outer.bytes, middle.bytes, Self.leaf("element", .float)]
            }
        }
        var footer = Thrift()
        footer.i32(1, 1)
        footer.structList(2, schema)
        footer.i64(3, Int64(rows))
        footer.structList(4, [group.bytes])
        footer.string(6, createdBy)
        footer.stop()
        file.append(footer.bytes)
        var length = UInt32(footer.bytes.count).littleEndian
        file.append(Data(bytes: &length, count: 4))
        file.append(Data("PAR1".utf8))
        return file
    }

    private static func leaf(_ name: String, _ type: PType) -> Data {
        var t = Thrift()
        t.i32(1, type.rawValue); t.i32(3, required); t.string(4, name); t.stop()
        return t.bytes
    }

    /// One data page (v1) holding the whole column: its header and its bytes.
    private static func page(_ column: Column) throws -> (Data, Int, PType, [String]) {
        var body = Data()
        let values: Int, type: PType, path: [String]
        switch column {
        case .int64(let n, let v):
            for x in v { var le = x.littleEndian; body.append(Data(bytes: &le, count: 8)) }
            values = v.count; type = .int64; path = [n]
        case .float(let n, let v):
            for x in v { var le = x.bitPattern.littleEndian; body.append(Data(bytes: &le, count: 4)) }
            values = v.count; type = .float; path = [n]
        case .floatList(let n, let v):
            guard let width = v.first?.count, width > 0, v.allSatisfy({ $0.count == width }) else {
                throw Misuse.ragged(n)
            }
            // REPETITION LEVELS: 0 starts a row, 1 continues it. DEFINITION LEVELS: all 1, every element present.
            var rep = Data()
            for _ in v {
                rep.append(Self.rleRun(0, count: 1))
                if width > 1 { rep.append(Self.rleRun(1, count: width - 1)) }
            }
            let def = Self.rleRun(1, count: v.count * width)
            for levels in [rep, def] {
                var length = UInt32(levels.count).littleEndian
                body.append(Data(bytes: &length, count: 4))
                body.append(levels)
            }
            for row in v { for x in row { var le = x.bitPattern.littleEndian; body.append(Data(bytes: &le, count: 4)) } }
            values = v.count * width; type = .float; path = [n, "list", "element"]
        }
        var dataHeader = Thrift()
        dataHeader.i32(1, Int32(values))
        dataHeader.i32(2, 0)       // PLAIN
        dataHeader.i32(3, 3)       // RLE
        dataHeader.i32(4, 3)       // RLE
        dataHeader.stop()
        var header = Thrift()
        header.i32(1, 0)           // DATA_PAGE
        header.i32(2, Int32(body.count))
        header.i32(3, Int32(body.count))
        header.structField(5, dataHeader.bytes)
        header.stop()
        return (header.bytes + body, values, type, path)
    }

    /// One RLE run of the RLE/bit-packing hybrid, at bit width 1.
    static func rleRun(_ value: UInt8, count: Int) -> Data {
        var d = Thrift.varint(UInt64(count) << 1)
        d.append(value)
        return d
    }
}

/// Thrift's compact protocol, as much of it as a Parquet footer needs.
struct Thrift {
    private(set) var bytes = Data()
    private var last: [Int16] = [0]

    static let i32Type: UInt8 = 5, i64Type: UInt8 = 6, binaryType: UInt8 = 8, listType: UInt8 = 9, structType: UInt8 = 12

    static func varint(_ value: UInt64) -> Data {
        var v = value, out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }
    static func zigzag32(_ n: Int32) -> UInt64 { UInt64(UInt32(bitPattern: (n << 1) ^ (n >> 31))) }
    static func zigzag64(_ n: Int64) -> UInt64 { UInt64(bitPattern: (n << 1) ^ (n >> 63)) }

    private mutating func field(_ id: Int16, _ type: UInt8) {
        let delta = id - last[last.count - 1]
        if delta > 0 && delta <= 15 {
            bytes.append(UInt8(delta) << 4 | type)
        } else {
            bytes.append(type)
            bytes.append(Thrift.varint(Thrift.zigzag32(Int32(id))))
        }
        last[last.count - 1] = id
    }
    mutating func i32(_ id: Int16, _ v: Int32) { field(id, Thrift.i32Type); bytes.append(Thrift.varint(Thrift.zigzag32(v))) }
    mutating func i64(_ id: Int16, _ v: Int64) { field(id, Thrift.i64Type); bytes.append(Thrift.varint(Thrift.zigzag64(v))) }
    mutating func string(_ id: Int16, _ s: String) {
        field(id, Thrift.binaryType)
        let utf8 = Data(s.utf8)
        bytes.append(Thrift.varint(UInt64(utf8.count)))
        bytes.append(utf8)
    }
    private mutating func listHeader(_ count: Int, _ type: UInt8) {
        if count < 15 { bytes.append(UInt8(count) << 4 | type) } else {
            bytes.append(0xF0 | type)
            bytes.append(Thrift.varint(UInt64(count)))
        }
    }
    /// A list of i32, each already zigzagged.
    mutating func list(_ id: Int16, _ type: UInt8, _ zigzagged: [UInt64]) {
        field(id, Thrift.listType)
        listHeader(zigzagged.count, type)
        for v in zigzagged { bytes.append(Thrift.varint(v)) }
    }
    mutating func stringList(_ id: Int16, _ strings: [String]) {
        field(id, Thrift.listType)
        listHeader(strings.count, Thrift.binaryType)
        for s in strings {
            let utf8 = Data(s.utf8)
            bytes.append(Thrift.varint(UInt64(utf8.count)))
            bytes.append(utf8)
        }
    }
    /// A nested struct, given its own complete bytes (field ids restart inside it, ending in stop).
    mutating func structField(_ id: Int16, _ encoded: Data) {
        field(id, Thrift.structType)
        bytes.append(encoded)
    }
    mutating func structList(_ id: Int16, _ encoded: [Data]) {
        field(id, Thrift.listType)
        listHeader(encoded.count, Thrift.structType)
        for e in encoded { bytes.append(e) }
    }
    mutating func stop() { bytes.append(0) }
}
