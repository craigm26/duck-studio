import XCTest
@testable import StudioKit

/// The app's idea of a local host and iOS's must agree, or a bench the app accepts is refused by
/// the system before a byte is sent ("requires the use of a secure connection", build 83).
/// NSAllowsLocalNetworking covers IP addresses, `.local` and unqualified names; any other suffix
/// `isLocalHost` accepts needs its own NSExceptionDomains entry in DuckStudio/project.yml.
final class AppTransportSecurityTests: XCTestCase {
    func testEveryNamedLocalSuffixHasAnATSException() throws {
        let yml = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("DuckStudio/project.yml")
        let text = try String(contentsOf: yml, encoding: .utf8)
        let block = try XCTUnwrap(text.range(of: "NSExceptionDomains:").map { String(text[$0.upperBound...].prefix(600)) })
        for (host, domain) in [("robot.tail881eb7.ts.net", "ts.net"), ("bench.internal", "internal")] {
            XCTAssertTrue(ModelEndpoint.isLocalHost(host), host)
            XCTAssertTrue(block.contains("\n            \(domain):"), "\(domain) has no ATS exception")
        }
    }
}
