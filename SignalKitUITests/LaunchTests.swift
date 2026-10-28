import XCTest

final class LaunchTests: XCTestCase {
    private func app(cache:String = UUID().uuidString, offline:Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitest"]
        app.launchEnvironment["SIGNAL_TEST_CACHE"] = cache
        if offline { app.launchEnvironment["SIGNAL_TEST_MODE"] = "offline" }
        return app
    }
    private func connect(_ app:XCUIApplication) {
        let address = app.textFields["backendAddress"];XCTAssertTrue(address.waitForExistence(timeout:15))
        address.tap()
        if let text = address.value as? String, !text.isEmpty, text != "Home server URL" {
            address.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:text.count))
        }
        address.typeText("https://example.invalid")
        app.secureTextFields["backendToken"].tap();app.secureTextFields["backendToken"].typeText("synthetic-only")
        app.buttons["Connect"].tap()
        XCTAssertTrue(app.navigationBars["Offers"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["Example item"].waitForExistence(timeout:10))
    }
    func testFirstLaunchNeedsHomeConnection() {
        let app = app();app.launch()
        XCTAssertTrue(app.textFields["backendAddress"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["Connect"].exists)
    }
    func testRefreshThenOfflineRelaunchSearchAndHistory() {
        let cache = UUID().uuidString;let online = app(cache:cache);online.launch();connect(online)
        online.buttons["refreshOffers"].tap()
        XCTAssertTrue(online.staticTexts["Saved on this iPhone. Advertising coverage remains partial."].waitForExistence(timeout:15))
        online.terminate()
        let offline = app(cache:cache,offline:true);offline.launch()
        XCTAssertTrue(offline.staticTexts["Example item"].waitForExistence(timeout:15))
        offline.staticTexts["Example item"].tap()
        XCTAssertTrue(offline.navigationBars["Details"].waitForExistence(timeout:10))
        XCTAssertTrue(offline.staticTexts["Advertised goods price"].exists)
        offline.navigationBars.buttons.element(boundBy:0).tap()
        let search = offline.textFields["offerSearch"];search.tap();search.typeText("not-present\n")
        XCTAssertFalse(offline.staticTexts["Example item"].exists)
        offline.tabBars.buttons["Watchlist"].tap()
        XCTAssertTrue(offline.staticTexts["Example watch"].waitForExistence(timeout:10))
        XCTAssertFalse(offline.buttons["Add watch"].isEnabled)
    }
    func testFailedRefreshPreservesOfflineCopyAndNoEventsTab() {
        let cache = UUID().uuidString;let online = app(cache:cache);online.launch();connect(online);online.terminate()
        let offline = app(cache:cache,offline:true);offline.launch()
        XCTAssertTrue(offline.staticTexts["Example item"].waitForExistence(timeout:15))
        offline.buttons["refreshOffers"].tap()
        XCTAssertTrue(offline.alerts["Action unavailable"].waitForExistence(timeout:10));offline.alerts.buttons["OK"].tap()
        XCTAssertTrue(offline.staticTexts["Example item"].exists)
        XCTAssertFalse(offline.tabBars.buttons["Events"].exists)
    }
}
