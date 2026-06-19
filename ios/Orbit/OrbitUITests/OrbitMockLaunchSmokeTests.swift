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

    /// End-to-end mock-mode coverage of the create_todo suggested-action loop:
    /// ask -> suggested action chip -> preview sheet -> execute -> navigate to
    /// Today with the new todo highlighted. Runs entirely on seeded mock
    /// clients (no backend, no OpenAI).
    @MainActor
    func testCreateTodoSuggestedActionFlowNavigatesToTodayWithNewTodo() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let askTab = app.tabBars.buttons["Ask"]
        XCTAssertTrue(askTab.waitForExistence(timeout: 5))
        askTab.tap()

        // A prompt the deterministic mock maps to a create_todo suggested action
        // titled "Call the dentist tomorrow".
        let input = askInput(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Ask input field not found")
        input.tap()
        input.typeText("add a todo to call the dentist tomorrow")

        let sendButton = app.buttons["Send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3))
        sendButton.tap()

        // The assistant reply includes the create_todo chip; open its sheet.
        revealAndTap(app.buttons["Suggested action: Create a todo"], in: app,
                     label: "Create a todo suggested action chip")

        // The preview sheet's primary button confirms and executes the action.
        revealAndTap(app.buttons["Create todo"], in: app,
                     label: "Create todo execute button")

        // Executing navigates to Today, where the new todo appears in Open Todos.
        // (The "New" highlight badge is intentionally transient, so the stable
        // signal is the todo row plus the Today tab being selected.)
        XCTAssertTrue(
            app.staticTexts["Call the dentist tomorrow"].waitForExistence(timeout: 8),
            "Created todo did not appear on Today"
        )
        XCTAssertTrue(
            app.tabBars.buttons["Today"].isSelected,
            "Execution did not navigate to the Today tab"
        )
    }

    /// The Ask composer uses a vertical `TextField` (backed by a text view), so
    /// resolve whichever element kind exposes the `ask.input` identifier.
    @MainActor
    private func askInput(in app: XCUIApplication) -> XCUIElement {
        let textView = app.textViews["ask.input"]
        if textView.waitForExistence(timeout: 5) {
            return textView
        }
        return app.textFields["ask.input"]
    }

    /// Wait for an element, scroll it into view if needed, then tap it.
    @MainActor
    private func revealAndTap(
        _ element: XCUIElement,
        in app: XCUIApplication,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "\(label) did not appear", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(label) was not hittable after scrolling", file: file, line: line)
        element.tap()
    }
}
