import XCTest

final class LaunchTests: XCTestCase {
    func testFirstLaunchNeedsPrivateConnection() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["backendAddress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Connect"].exists)
    }
}
