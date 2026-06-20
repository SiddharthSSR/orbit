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

        let askTab = app.buttons["Ask"]
        XCTAssertTrue(askTab.exists)
        askTab.tap()
        XCTAssertTrue(app.buttons["Chat: What should I focus on today?"].waitForExistence(timeout: 3))

        let inboxTab = app.buttons["Inbox"]
        XCTAssertTrue(inboxTab.exists)
        inboxTab.tap()
        XCTAssertTrue(app.staticTexts["AI article link"].waitForExistence(timeout: 3))

        let billsTab = app.buttons["Bills"]
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

        let askTab = app.buttons["Ask"]
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
            app.buttons["Today"].isSelected,
            "Execution did not navigate to the Today tab"
        )
    }

    /// End-to-end mock-mode coverage of the save_memory suggested-action loop:
    /// ask -> Save to memory chip -> preview sheet (with extracted text) ->
    /// execute -> navigate to Inbox with the new memory. Runs entirely on seeded
    /// mock clients (no backend, no OpenAI).
    @MainActor
    func testSaveMemorySuggestedActionFlowNavigatesToInboxWithNewMemory() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let askTab = app.buttons["Ask"]
        XCTAssertTrue(askTab.waitForExistence(timeout: 5))
        askTab.tap()

        // A prompt the deterministic mock maps to a save_memory suggested action
        // whose extracted memory text is "I like quiet cafes with plants".
        let expectedMemory = "I like quiet cafes with plants"
        let input = askInput(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Ask input field not found")
        input.tap()
        input.typeText("remember that \(expectedMemory)")

        let sendButton = app.buttons["Send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3))
        sendButton.tap()

        // The reply echoes the (longer) prompt, which can leave the chip under the
        // on-screen keyboard. Scroll the transcript up so the chip is clear before
        // tapping it; otherwise the tap can land on the keyboard.
        let chip = app.buttons["Suggested action: Save to memory"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "Save to memory chip did not appear")
        app.swipeUp()
        revealAndTap(chip, in: app, label: "Save to memory suggested action chip")

        // The preview sheet shows the extracted memory text in its editable field
        // (a vertical TextField, exposed as a text field or text view by context).
        let valuePredicate = NSPredicate(format: "value == %@", expectedMemory)
        let memoryTextField = app.textFields.element(matching: valuePredicate)
        let memoryTextView = app.textViews.element(matching: valuePredicate)
        var memoryFieldShown =
            memoryTextField.waitForExistence(timeout: 5) ||
            memoryTextView.waitForExistence(timeout: 2)
        var memoryFieldRevealAttempts = 0
        while !memoryFieldShown && memoryFieldRevealAttempts < 8 {
            swipeUpInForegroundContent(in: app)
            memoryFieldShown = memoryTextField.exists || memoryTextView.exists
            memoryFieldRevealAttempts += 1
        }
        XCTAssertTrue(memoryFieldShown, "Extracted memory text not shown in the preview sheet")

        // The preview sheet's primary button confirms and executes the action.
        revealAndTap(app.buttons["Save to memory"], in: app,
                     label: "Save to memory execute button")

        // Executing navigates to Inbox, where the new memory appears.
        XCTAssertTrue(
            app.staticTexts[expectedMemory].waitForExistence(timeout: 8),
            "Created memory did not appear in Inbox"
        )
        XCTAssertTrue(
            app.buttons["Inbox"].isSelected,
            "Execution did not navigate to the Inbox tab"
        )
    }

    /// End-to-end mock-mode coverage of the review_bills suggested-action loop:
    /// ask -> Review bills chip -> preview sheet -> confirm -> navigate to Bills.
    /// The action is navigation-only and runs entirely on seeded mock clients.
    @MainActor
    func testReviewBillsSuggestedActionNavigatesToBills() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let askTab = app.buttons["Ask"]
        XCTAssertTrue(askTab.waitForExistence(timeout: 5))
        askTab.tap()

        // The deterministic mock maps any bill prompt to review_bills.
        let input = askInput(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Ask input field not found")
        input.tap()
        input.typeText("review my bills")

        let sendButton = app.buttons["Send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3))
        sendButton.tap()

        revealAndTap(app.buttons["Suggested action: Review bills"], in: app,
                     label: "Review bills suggested action chip")

        // Explicit confirmation opens Bills without mutating mock data.
        revealAndTap(app.buttons["Review bills"], in: app,
                     label: "Review bills confirm button")

        XCTAssertTrue(
            app.staticTexts["Credit card bill"].waitForExistence(timeout: 8),
            "Seeded bill did not appear after navigation"
        )
        XCTAssertTrue(
            app.buttons["Bills"].isSelected,
            "Execution did not navigate to the Bills tab"
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
        var appeared = element.waitForExistence(timeout: 8)
        var attempts = 0
        while !appeared && attempts < 8 {
            swipeUpInForegroundContent(in: app)
            appeared = element.waitForExistence(timeout: 1)
            attempts += 1
        }
        XCTAssertTrue(appeared, "\(label) did not appear", file: file, line: line)

        attempts = 0
        while !element.isHittable && attempts < 8 {
            swipeUpInForegroundContent(in: app)
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(label) was not hittable after scrolling", file: file, line: line)
        element.tap()
    }

    /// Swipe the foremost SwiftUI list when a preview sheet is presented;
    /// otherwise fall back to scrolling the app transcript.
    @MainActor
    private func swipeUpInForegroundContent(in app: XCUIApplication) {
        let collectionViews = app.collectionViews
        if collectionViews.count > 1 {
            collectionViews.element(boundBy: collectionViews.count - 1).swipeUp()
        } else {
            app.swipeUp()
        }
    }
}
