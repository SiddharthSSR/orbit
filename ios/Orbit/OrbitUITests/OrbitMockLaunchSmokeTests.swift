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
        XCTAssertTrue(app.staticTexts["Project Digest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Orbit"].waitForExistence(timeout: 5))

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

    @MainActor
    func testProjectDetailShowsLinkedMemoriesAndTodos() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let projectsTab = app.buttons["Projects"]
        XCTAssertTrue(projectsTab.waitForExistence(timeout: 5))
        projectsTab.tap()

        XCTAssertTrue(app.staticTexts["Orbit"].waitForExistence(timeout: 5))
        let detailsButton = app.buttons["Open Orbit project"]
        XCTAssertTrue(detailsButton.waitForExistence(timeout: 5), "Orbit project details button did not appear")
        detailsButton.tap()

        // Read-only activity summary near the top.
        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Done"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Linked todos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Draft project brief"].waitForExistence(timeout: 5))
        // Linked-todo rows now show the project name for consistency with Today.
        XCTAssertTrue(app.staticTexts["Project: Orbit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Linked memories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI article link"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayProjectDigestOpensProjectDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Project Digest"].waitForExistence(timeout: 5))

        // The seeded digest has one project (Orbit) with no open todos, so the
        // header summary is deterministic.
        XCTAssertTrue(
            app.staticTexts["1 project · All caught up"].waitForExistence(timeout: 5),
            "Project Digest header summary did not appear"
        )

        let digestRow = app.buttons["today.projectDigest.Orbit"]
        XCTAssertTrue(digestRow.waitForExistence(timeout: 5), "Orbit digest row did not appear")
        // The seeded Orbit project has only a completed linked todo (plus a linked
        // memory), so its digest row shows the calm caught-up signal.
        XCTAssertTrue(
            app.staticTexts["All caught up"].waitForExistence(timeout: 5),
            "Caught-up signal did not appear for a project with no open todos"
        )
        digestRow.tap()

        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Linked todos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Draft project brief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Linked memories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI article link"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAskProjectScopeSelectAndClear() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let askTab = app.buttons["Ask"]
        XCTAssertTrue(askTab.waitForExistence(timeout: 5))
        askTab.tap()

        // Opt-in scope control defaults to unscoped ("All").
        let scopeControl = app.buttons["ask.projectScope"]
        XCTAssertTrue(scopeControl.waitForExistence(timeout: 5), "Ask project scope control did not appear")
        XCTAssertTrue(app.buttons["Project context: All"].exists, "Scope did not default to unscoped")

        // Open the sheet picker and select a project.
        scopeControl.tap()
        let orbitOption = app.buttons["Orbit"]
        XCTAssertTrue(orbitOption.waitForExistence(timeout: 5), "Project option did not appear in picker")
        orbitOption.tap()

        XCTAssertTrue(
            app.staticTexts["Using project context: Orbit"].waitForExistence(timeout: 5),
            "Selected project scope label did not appear"
        )
        XCTAssertTrue(
            app.buttons["Project: Orbit"].waitForExistence(timeout: 5),
            "Scope control did not reflect the selected project"
        )

        // Clear back to unscoped.
        app.buttons["ask.projectScope.clear"].tap()
        XCTAssertTrue(
            app.staticTexts["Using project context: Orbit"].waitForNonExistence(timeout: 5),
            "Project scope label did not clear"
        )
        XCTAssertTrue(
            app.buttons["Project context: All"].waitForExistence(timeout: 5),
            "Scope control did not return to unscoped"
        )
    }

    @MainActor
    func testAskContextPreviewReflectsProjectScope() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let askTab = app.buttons["Ask"]
        XCTAssertTrue(askTab.waitForExistence(timeout: 5))
        askTab.tap()

        // Scope Ask to the Orbit project via the sheet picker.
        let scopeControl = app.buttons["ask.projectScope"]
        XCTAssertTrue(scopeControl.waitForExistence(timeout: 5))
        scopeControl.tap()
        let orbitOption = app.buttons["Orbit"]
        XCTAssertTrue(orbitOption.waitForExistence(timeout: 5))
        orbitOption.tap()

        // Enter a question and trigger the context preview.
        let input = askInput(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Ask input field not found")
        input.tap()
        input.typeText("What is the latest?")

        let previewButton = app.buttons["Preview"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        previewButton.tap()

        // The preview output indicates it is scoped to the project.
        let previewScope = app.staticTexts["ask.preview.projectScope"]
        var attempts = 0
        while !previewScope.exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(
            previewScope.waitForExistence(timeout: 5),
            "Context preview did not indicate project scope"
        )
    }

    @MainActor
    func testTodayTodoCanLinkAndUnlinkProject() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        // Today is the default tab; the seeded open todo "Review today plan"
        // exposes a per-row project menu.
        let menu = app.buttons["Project for Review today plan"]
        revealAndTap(menu, in: app, label: "Review today plan project menu")

        let orbitOption = app.buttons["Orbit"]
        XCTAssertTrue(orbitOption.waitForExistence(timeout: 5), "Orbit project option did not appear")
        orbitOption.tap()

        XCTAssertTrue(
            app.staticTexts["Project: Orbit"].waitForExistence(timeout: 5),
            "Linked project label did not appear after assigning"
        )

        let updatedMenu = app.buttons["Project for Review today plan"]
        XCTAssertTrue(
            updatedMenu.waitUntilEnabled(timeout: 5),
            "Project menu did not re-enable after assigning"
        )
        revealAndTap(updatedMenu, in: app, label: "Review today plan project menu after linking")
        let unlinkOption = app.buttons["Unlinked"]
        XCTAssertTrue(unlinkOption.waitForExistence(timeout: 5), "Unlinked option did not appear")
        unlinkOption.tap()

        XCTAssertTrue(
            app.staticTexts["Project: Orbit"].waitForNonExistence(timeout: 5),
            "Linked project label did not disappear after unlinking"
        )
    }

    @MainActor
    func testInboxMemoryCanLinkAndUnlinkProject() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let inboxTab = app.buttons["Inbox"]
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 5))
        inboxTab.tap()
        XCTAssertTrue(app.staticTexts["AI article link"].waitForExistence(timeout: 5))

        let projectMenu = app.buttons["Project for AI article link"]
        revealAndTap(projectMenu, in: app, label: "AI article project menu")
        let orbitProject = app.buttons["Orbit"]
        XCTAssertTrue(orbitProject.waitForExistence(timeout: 3), "Orbit project option did not appear")
        orbitProject.tap()

        let linkedProject = app.staticTexts["Project: Orbit"]
        XCTAssertTrue(linkedProject.waitForExistence(timeout: 5), "Linked project label did not appear")

        revealAndTap(projectMenu, in: app, label: "AI article project menu after linking")
        let unlink = app.buttons["Unlinked"]
        XCTAssertTrue(unlink.waitForExistence(timeout: 3), "Unlinked option did not appear")
        unlink.tap()

        let removed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: linkedProject
        )
        wait(for: [removed], timeout: 5)
    }

    @MainActor
    func testInboxFilterNarrowsCapturesAndReturnsToAll() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let inboxTab = app.buttons["Inbox"]
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 5))
        inboxTab.tap()

        // All (default) shows the seeded captures; "AI article link" is the first
        // row. (Lower rows can sit below the fold on smaller CI screens, so the
        // assertions below only rely on the first row and the empty state, which
        // replaces the list in place.)
        XCTAssertTrue(app.staticTexts["AI article link"].waitForExistence(timeout: 5))

        // No seeded capture is bare (all are tagged, linked, or sourced), so the
        // Needs review filter is deterministically empty and shows the no-results
        // empty state instead of the list.
        revealAndTap(app.buttons["Needs review"], in: app, label: "Needs review filter segment")
        XCTAssertTrue(
            app.staticTexts["No matching captures"].waitForExistence(timeout: 5),
            "Needs review filter did not show the empty state"
        )

        // Returning to All restores the list, including the first row.
        revealAndTap(app.buttons["All"], in: app, label: "All filter segment")
        XCTAssertTrue(app.staticTexts["AI article link"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testInboxMemoryOpensReadOnlyDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--orbit-ui-tests"]
        app.launch()

        let inboxTab = app.buttons["Inbox"]
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 5))
        inboxTab.tap()

        // Open the first seeded capture's read-only detail.
        let openButton = app.buttons["Open memory AI article link"]
        revealAndTap(openButton, in: app, label: "Open AI article link memory")

        // The detail shows the full source URL, which the Inbox row only
        // summarizes by host — so this is unique to the detail screen and sits in
        // the top card (no below-fold dependency).
        XCTAssertTrue(
            app.staticTexts["https://example.com/ai-memory"].waitForExistence(timeout: 5),
            "Memory detail did not show the full source URL"
        )

        // Back returns to Inbox; the row open-button exists only on the Inbox list.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), "Did not return to Inbox")
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

        // The assistant reply includes the create_todo chip; the floating dock
        // and keyboard can leave it near the bottom, so scroll it clear first.
        let chip = app.buttons["Suggested action: Create a todo"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "Create a todo chip did not appear")
        app.swipeUp()
        revealAndTap(chip, in: app, label: "Create a todo suggested action chip")

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

        // Scroll the chip clear of the floating dock / keyboard before tapping.
        let chip = app.buttons["Suggested action: Review bills"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "Review bills chip did not appear")
        app.swipeUp()
        revealAndTap(chip, in: app, label: "Review bills suggested action chip")

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
        guard appeared else {
            XCTFail("\(label) did not appear", file: file, line: line)
            return
        }

        attempts = 0
        while !element.isHittable && attempts < 8 {
            swipeUpInForegroundContent(in: app)
            attempts += 1
        }
        // XCTest can report SwiftUI Menu controls as not hittable on CI even
        // when its own tap path can scroll-to-visible and activate them.
        // The following assertions in each smoke flow prove whether the tap
        // actually opened the expected menu or sheet.
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

private extension XCUIElement {
    func waitUntilEnabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
