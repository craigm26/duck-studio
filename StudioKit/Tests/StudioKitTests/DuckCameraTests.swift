import XCTest
@testable import StudioKit

final class DuckCameraTests: XCTestCase {
    func testAddressesARealPersonTypes() {
        XCTAssertEqual(DuckCamera.Address("duck.local"), .init(host: "duck.local", port: 8080))
        XCTAssertEqual(DuckCamera.Address(" 192.168.1.40:8081 "), .init(host: "192.168.1.40", port: 8081))
        XCTAssertEqual(DuckCamera.Address("http://duck.local:8080/"), .init(host: "duck.local", port: 8080))
        XCTAssertEqual(DuckCamera.Address("duck.local")?.frameURL?.absoluteString, "http://duck.local:8080/frame")
        XCTAssertEqual(DuckCamera.Address("10.0.0.2:8081")?.consoleURL?.absoluteString, "http://10.0.0.2:8081/")
    }

    func testWhatIsNotAnAddressIsRefused() {
        for bad in ["", "duck local", "duck.local/frame", "duck.local:", "duck.local:99999", "a:b:c", "duck.local:x"] {
            XCTAssertNil(DuckCamera.Address(bad), bad)
        }
    }

    func testAFrameIsAPNGAndA503IsTheRobotsOwnSentence() {
        let png = Data(DuckCamera.png + [0, 1, 2])
        XCTAssertEqual(DuckCamera.read(status: 200, body: png), .picture(png))
        let said = "Camera snapshot unavailable; retry when capture is running.\n"
        XCTAssertEqual(DuckCamera.read(status: 503, body: Data(said.utf8)),
                       .notCapturing("Camera snapshot unavailable; retry when capture is running."))
        XCTAssertEqual(DuckCamera.read(status: 200, body: Data("<html>".utf8)), .notACamera(200))
        XCTAssertEqual(DuckCamera.read(status: 404, body: Data()), .notACamera(404))
    }
}
