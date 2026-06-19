import XCTest

final class OrbitMockLaunchSmokeTests: XCTestCase {
    @MainActor
    func testMockLaunchShowsStableContentAcrossTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Daily Plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["You have 1 open todos, 1 unpaid bills, and 3 recent captures."].exists
        )

        let askTab = app.tabBars.buttons["Ask"]
        XCTAssertTrue(askTab.exists)
        askTab.tap()
        XCTAssertTrue(app.buttons["Chat: What should I focus on today?"].waitForExistence(timeout: 3))

        let inboxTab = app.tabBars.buttons["Inbox"]
        XCTAssertTrue(inboxTab.exists)
        inboxTab.tap()
        XCTAssertTrue(app.staticTexts["AI article link"].waitForExistence(timeout: 3))

        let billsTab = app.tabBars.buttons["Bills"]
        XCTAssertTrue(billsTab.exists)
        billsTab.tap()
        XCTAssertTrue(app.staticTexts["Credit card bill"].waitForExistence(timeout: 3))
    }
}
