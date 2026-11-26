import XCTest

final class CompactHomeUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { app.terminate() }
    func launch(_ flags: [String] = []) { app.launchArguments = ["--ui-testing", "--reset", "--home-demo"] + flags; app.launch(); XCTAssertTrue(app.staticTexts["Follow up"].waitForExistence(timeout: 5)) }
    func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func choose(_ identifier: String, _ choice: String) { tapVisible(app.buttons[identifier], app: app); app.buttons[choice].firstMatch.tap() }
    func testColdStartCompactFamilyAndCombinedFiltersSurviveReopen() {
        launch()
        for label in ["All", "Family", "Friends"] { assertMinimumTapHeight(app.buttons["home-type-\(label)"]) }
        let names = ["Zoe Park", "Samir Shah", "Mei Lin", "Daniel Ross", "Lena Shah"]
        let bottom = app.buttons["tab-0"].frame.minY
        for name in names {
            let row = app.buttons["home-person-\(name)"]
            XCTAssertTrue(row.exists && row.frame.maxY <= bottom, "Five compact people must fit above navigation at normal text size")
            XCTAssertLessThanOrEqual(row.frame.height, 95, "Normal person rows must stay compact")
        }
        XCTAssertLessThan(app.buttons["home-person-Zoe Park"].frame.minY, app.buttons["home-person-Mei Lin"].frame.minY)
        XCTAssertTrue(app.buttons["home-person-Zoe Park"].label.contains("No contact recorded"))
        capture("Compact Home")
        app.buttons["home-type-Family"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "3 people")
        XCTAssertFalse(app.buttons["home-person-Zoe Park"].exists)
        XCTAssertTrue(app.buttons["home-person-Samir Shah"].exists, "A Family + Friend must appear in Family")
        capture("Family Home")
        choose("home-closeness", "Close")
        app.buttons["home-filters"].tap()
        choose("home-filter-distance", "Nearby"); choose("home-filter-direction", "Grow closer")
        capture("Home filters")
        tapVisible(app.buttons["home-filter-apply"], app: app)
        XCTAssertEqual(app.staticTexts["home-count"].label, "1 person", "All selected filters must apply together")
        XCTAssertTrue(app.buttons["home-person-Lena Shah"].exists); XCTAssertFalse(app.buttons["home-person-Mei Lin"].exists)
        capture("Filtered Home")
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertEqual(app.staticTexts["home-count"].label, "1 person", "Filters must survive reopening without changing the journal")
        XCTAssertTrue(app.buttons["home-type-Family"].isSelected)
        app.buttons["home-type-Friends"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "1 person")
        XCTAssertTrue(app.buttons["home-person-Daniel Ross"].exists)
        app.buttons["home-type-Family"].tap()
        app.buttons["home-actions-Lena Shah"].tap()
        assertMinimumTapHeight(app.buttons["home-log-Lena Shah"]); assertMinimumTapHeight(app.buttons["home-later-Lena Shah"])
        capture("Home person actions")
        app.buttons["home-date-Lena Shah"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5), "Missing history must offer an explicit date choice, not record contact automatically")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["home-person-Lena Shah"].label.contains("No contact recorded"))
        app.buttons["home-log-Lena Shah"].tap(); app.buttons["save-moment"].tap()
        XCTAssertFalse(app.buttons["home-person-Lena Shah"].exists, "A saved conversation must remove the optional invitation immediately")
    }
    func testDueFilterKeepsFactualOrderAndUnknownHistoryEmptyState() {
        launch()
        choose("home-follow-up", "Due reminders")
        XCTAssertTrue(app.staticTexts["No reminders due."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home-count"].label, "0 people", "Unknown contact alone cannot create a due reminder")
        capture("Home no reminders")
        app.buttons["home-show-all"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "8 people")
        app.terminate(); launch(["--home-mixed-demo"])
        choose("home-follow-up", "Due reminders")
        XCTAssertEqual(app.staticTexts["home-count"].label, "3 people")
        let samir = app.buttons["home-person-Samir Shah"], daniel = app.buttons["home-person-Daniel Ross"], aaron = app.buttons["home-person-Aaron Miller"]
        XCTAssertLessThan(samir.frame.minY, daniel.frame.minY); XCTAssertLessThan(daniel.frame.minY, aaron.frame.minY)
        capture("Home due reminders")
        choose("home-sort", "Oldest contact first"); XCTAssertLessThan(aaron.frame.minY, samir.frame.minY, "Explicit oldest-contact sorting must reorder the filtered list")
        choose("home-sort", "Priority order")
        app.buttons["home-actions-Samir Shah"].tap(); app.buttons["home-later-Samir Shah"].tap()
        app.buttons["home-snooze-save"].tap()
        XCTAssertFalse(samir.exists, "Confirmed Later must suppress the chosen person")
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertEqual(app.staticTexts["home-count"].label, "2 people")
        XCTAssertFalse(app.buttons["home-person-Samir Shah"].exists)
    }
    func testFilterDraftSearchCancelResetAndUnansweredRelationships() {
        launch(); app.buttons["home-filters"].tap()
        let search = app.textFields["home-filter-search"]; search.tap(); search.typeText("No match\n")
        app.buttons["Cancel"].tap(); XCTAssertEqual(app.staticTexts["home-count"].label, "8 people", "Cancel must discard filter drafts")
        app.buttons["home-filters"].tap(); search.tap(); search.typeText("Nora\n"); app.buttons["home-filter-apply"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "1 person", "Applying Home filters must update the rendered list"); XCTAssertTrue(app.buttons["home-person-Nora Ellis"].exists)
        app.buttons["home-filters"].tap(); tapVisible(app.buttons["home-filter-reset"], app: app); app.buttons["home-filter-apply"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "8 people", "Reset must restore the complete eligible list")
        app.buttons["home-filters"].tap(); choose("home-filter-relationship", "Not set"); app.buttons["home-filter-apply"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "1 person", "Applying Home filters must update the rendered list"); XCTAssertTrue(app.buttons["home-person-Nora Ellis"].exists)
        app.buttons["home-type-All"].tap(); XCTAssertEqual(app.staticTexts["home-count"].label, "8 people")
    }
    func testEnablingReminderThroughEditorDoesNotReviveAnOldOffClock() {
        launch(); app.buttons["tab-1"].tap()
        let search = app.textFields["people-search"]; tapVisible(search, app: app); search.typeText("Nora\n"); tapVisible(app.buttons["person-Nora Ellis"], app: app)
        tapVisible(app.buttons["Adjust"], app: app); app.buttons["Save"].tap()
        tapVisible(app.buttons["Adjust"], app: app); choose("person-reminder-interval", "Every week"); app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["No contact recorded"].exists, "Setting reminders must not claim a conversation")
        app.buttons["tab-0"].tap(); choose("home-follow-up", "Due reminders")
        XCTAssertEqual(app.staticTexts["home-count"].label, "0 people", "Enabling a weekly reminder today must not revive the old disabled clock")
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch(); XCTAssertEqual(app.staticTexts["home-count"].label, "0 people")
    }
    func testCompactControlsAndLoggingOnSmallScreen() {
        launch()
        for id in ["quick-log", "home-type-Family", "home-filters", "home-closeness", "home-follow-up"] { assertMinimumTapHeight(app.buttons[id]) }
        let row = app.buttons["home-person-Zoe Park"]
        XCTAssertTrue(row.frame.minX >= 0 && row.frame.maxX <= app.frame.width)
        capture("Small compact Home")
        app.buttons["quick-log"].tap(); app.buttons["home-log-person"].tap()
        searchAndSubmit("Zoe", app: app); tapVisible(app.buttons["log-person-Zoe Park"], app: app)
        XCTAssertTrue(app.buttons["save-moment"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        app.buttons["home-type-Family"].tap(); tapVisible(app.buttons["home-person-Samir Shah"], app: app)
        tapVisible(app.buttons["home-log-Samir Shah"], app: app); app.buttons["save-moment"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "2 people", "A confirmed conversation must update the filtered queue")
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertEqual(app.staticTexts["home-count"].label, "2 people", "The installed app must read and write the journal across reopening")
        app.buttons["home-filters"].tap(); choose("home-filter-closeness", "Close"); app.buttons["home-filter-apply"].tap()
        XCTAssertTrue(app.buttons["home-person-Mei Lin"].exists)
        capture("Small filtered Home")
    }
    func testHomeDarkAndAccessibilityFiltersRemainUsable() {
        launch(["--dark"]); capture("Dark compact Home")
        app.terminate(); launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tapVisible(app.buttons["home-filters"], app: app)
        tapVisible(app.buttons["home-filter-feeling"], app: app); app.buttons["Needs care"].firstMatch.tap()
        assertMinimumTapHeight(app.buttons["home-filter-cancel"]); assertMinimumTapHeight(app.buttons["home-filter-apply"])
        capture("Large Home filters"); app.buttons["home-filter-apply"].tap()
        XCTAssertEqual(app.staticTexts["home-count"].label, "2 people")
        tapVisible(app.buttons["home-person-Daniel Ross"], app: app)
        let log = app.buttons["home-log-Daniel Ross"]; tapVisible(log, app: app)
        XCTAssertTrue(app.buttons["save-moment"].waitForExistence(timeout: 5)); capture("Large Home log contact")
        app.buttons["Cancel"].tap()
    }
}
