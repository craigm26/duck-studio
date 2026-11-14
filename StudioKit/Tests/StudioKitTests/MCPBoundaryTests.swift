import XCTest

/// Where MCP code may be, checked by reading the source (brains-layer.md 5.4 and 6.1), the way
/// `StopPathTests.testTheFileImportsFoundationAndNamesNoModel` checks StopPath.
///
/// Stop, per-tick control, limits and keys never go over MCP. The strongest form of that is
/// structural: StudioKit, which holds StopPath, LinePeer, DuckPeer, ControlArbiter and the gate,
/// does not import the SDK or the client at all, so nothing on the stop path can call it. The
/// app's Stop entry points (Play's Stop and the stop pill in `StopPill.swift`, Siri and the Live
/// Activity in `DuckShortcuts.swift`) do not import it either, and one screen does.
final class MCPBoundaryTests: XCTestCase {

    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let kit = root.appendingPathComponent("Sources/StudioKit")
    static let client = root.appendingPathComponent("Sources/StudioMCP")
    static let app = root.deletingLastPathComponent().appendingPathComponent("DuckStudio/Sources")

    static func swiftFiles(_ dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func imports(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") || $0.hasPrefix("@_exported import ") }
            .map { $0.split(separator: " ").last.map(String.init) ?? "" }
    }

    static let mcpModules: Set<String> = ["MCP", "StudioMCP", "Logging"]

    /// The source with comment lines taken out, so a doc comment that says "never MCP" is not a hit.
    static func code(_ text: String) -> String {
        text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The check can fail: an import line is found when there is one.
    func testTheImportReaderFindsAnImport() {
        XCTAssertEqual(Self.imports("import Foundation\n#if canImport(MCP)\nimport MCP\n#endif"), ["Foundation", "MCP"])
        XCTAssertEqual(Self.imports("  @_exported import StudioMCP"), ["StudioMCP"])
    }

    func testStudioKitImportsNoMCPCode() throws {
        let files = try Self.swiftFiles(Self.kit)
        XCTAssertGreaterThan(files.count, 100, "read the kit's sources")
        for file in files {
            let found = Set(Self.imports(try String(contentsOf: file, encoding: .utf8))).intersection(Self.mcpModules)
            XCTAssertEqual(found, [], "\(file.lastPathComponent) imports \(found)")
        }
    }

    /// The kit files a stop runs through name no MCP type at all.
    func testTheStopPathNamesNoMCP() throws {
        for name in ["StopPath", "StopWords", "LinePeer", "DuckPeer", "ControlArbiter", "DuckEnvelopeGate", "PadPilot"] {
            let text = Self.code(try String(contentsOf: Self.kit.appendingPathComponent(name + ".swift"), encoding: .utf8))
            XCTAssertFalse(text.isEmpty)
            for word in ["MCP", "PlannerContextNote", "readTool", "listTools"] {
                XCTAssertFalse(text.contains(word), "\(name).swift names \(word)")
            }
        }
    }

    func testTheAppsStopEntryPointsImportNoMCP() throws {
        for name in ["StopPill", "DuckShortcuts"] {
            let text = try String(contentsOf: Self.app.appendingPathComponent(name + ".swift"), encoding: .utf8)
            XCTAssertTrue(text.contains("StopPath") || text.contains("StopDuckIntent"), "\(name).swift is a stop entry point")
            XCTAssertEqual(Set(Self.imports(text)).intersection(Self.mcpModules), [], "\(name).swift imports MCP")
            XCTAssertFalse(Self.code(text).contains("MCP"), "\(name).swift names MCP")
        }
    }

    func testOneAppScreenImportsTheClient() throws {
        let importers = try Self.swiftFiles(Self.app).filter {
            Self.imports(try String(contentsOf: $0, encoding: .utf8)).contains { Self.mcpModules.contains($0) }
        }.map(\.lastPathComponent)
        XCTAssertEqual(importers, ["MCPServerView.swift"])
    }

    /// The client calls a tool in one place, with no arguments, answers no server request, and
    /// writes no log line.
    func testTheClientCallsNoToolWithArgumentsAndLogsNothing() throws {
        let files = try Self.swiftFiles(Self.client)
        XCTAssertEqual(files.map(\.lastPathComponent), ["MCPHTTPToolSource.swift"])
        let text = try String(contentsOf: files[0], encoding: .utf8)
        let code = Self.code(text)
        XCTAssertEqual(code.components(separatedBy: "callTool(").count - 1, 1, "one tool call site")
        XCTAssertTrue(code.contains("callTool(name: name, arguments: nil)"), "and it sends no arguments")
        for banned in ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(subsystem", "withMethodHandler",
                       "Sampling", "Elicitation", "Roots", "robot.stop", "robot.move", "DuckPeer", "LinePeer", "StopPath"] {
            XCTAssertFalse(code.contains(banned), "the client names \(banned)")
        }
    }
}
