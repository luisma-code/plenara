import XCTest

final class WorkflowUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    func launch(_ extra: [String] = []) { app.launchArguments = ["--ui-testing", "--reset", "--demo"] + extra; app.launch() }
    func attach(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func visibleTap(_ element: XCUIElement, in container: XCUIElement? = nil) {
        tapVisible(element, app: app, in: container)
    }
    func testAttendeeSearchKeepsDoneReachable() throws {
        launch(); app.buttons["tab-2"].tap(); app.buttons["log-social-event"].tap()
        app.buttons["event-people"].tap(); search("Sofia"); app.buttons["event-guest-Sofia Chen"].tap()
        let done = app.buttons["event-people-done"]
        XCTAssertTrue(done.exists && done.isHittable, "Searching must keep Done reachable")
        assertMinimumTapHeight(done)
        done.tap(); XCTAssertTrue(app.buttons["event-people"].label.contains("1 person"))
    }
    func search(_ value: String) { searchAndSubmit(value, app: app) }
    func testSharedDinnerFivePeopleEditReopenAndCancel() throws {
        launch(); app.buttons["log-social-event"].tap()
        let title = app.textFields["event-title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Friday dinner")
        let note = app.textFields["event-note"]; note.tap(); note.typeText("Made pasta and planned our summer trips")
        app.buttons["event-people"].tap()
        for name in ["Amara Okafor", "Daniel Rivera", "Leo Park", "Mum", "Sofia Chen"] {
            search(name); let row = app.buttons["event-guest-\(name)"]; XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap(); XCTAssertEqual(row.value as? String, "Selected")
        }
        app.buttons["event-people-done"].tap(); XCTAssertTrue(app.buttons["event-people-done"].waitForNonExistence(timeout: 5))
        app.buttons["save-event"].tap(); XCTAssertTrue(app.buttons["moment-follow-through"].waitForExistence(timeout: 5)); app.buttons["Dismiss next-time suggestion"].tap()
        app.buttons["tab-2"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND identifier BEGINSWITH %@", "Friday dinner", "history-moment-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "history-moment-", "Friday dinner")).count, 1, "The dinner must appear once in Moments")
        for name in ["Amara Okafor", "Daniel Rivera", "Leo Park", "Mum", "Sofia Chen"] { XCTAssertTrue(row.label.contains(name), "The saved event must retain every guest") }
        attach("Saved shared dinner"); row.tap()
        let edit = app.textFields["event-note"]; XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap(); edit.typeText(" and dessert")
        app.buttons["event-people"].tap(); search("Leo Park"); app.buttons["event-guest-Leo Park"].tap(); app.buttons["event-people-done"].tap(); app.buttons["save-event"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch(); app.buttons["tab-2"].tap()
        let reopened = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "history-moment-", "Friday dinner")).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 5)); XCTAssertTrue(reopened.label.contains("dessert")); XCTAssertFalse(reopened.label.contains("Leo Park"), "An attendee removed by editing must leave the shared event")
        app.buttons["log-social-event"].tap(); XCTAssertTrue(app.buttons["save-event"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["save-event"].isEnabled)
        app.textFields["event-title"].tap(); app.textFields["event-title"].typeText("Cancelled dinner"); app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cancelled dinner")).firstMatch.exists)
        visibleTap(app.buttons["View Sofia Chen →"])
        XCTAssertTrue(app.staticTexts["Connected today"].waitForExistence(timeout: 5), "A shared dinner must count in an attendee's connection history")
    }
    func testOptionalCustomRhythmSetupPreservesUnknownHistoryAndUndo() throws {
        launch(["--rhythm-demo"]); app.buttons["tab-1"].tap(); app.buttons["people-rhythm-setup"].tap()
        XCTAssertTrue(app.staticTexts["setup-rhythm-selection"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["setup-rhythm-selection"].label, "0 selected")
        search("Mum"); XCTAssertFalse(app.buttons["rhythm-person-Mum"].isEnabled, "Existing rhythms must start protected")
        search("Sofia"); visibleTap(app.buttons["rhythm-person-Sofia Chen"])
        // Return to the rhythm choice above the people section.
        for _ in 0..<5 { if app.buttons["setup-rhythm-cadence"].isHittable { break }; app.swipeDown() }
        app.buttons["setup-rhythm-cadence"].tap(); app.buttons["Every 2 weeks"].firstMatch.tap()
        visibleTap(app.buttons["setup-rhythm-custom-Increment"])
        let customChoice = app.buttons["setup-rhythm-cadence"]
        XCTAssertTrue("\(customChoice.label) \(customChoice.value ?? "")".contains("Every 15 days"), "The picker must name a custom rhythm")
        visibleTap(app.buttons["apply-rhythm"]); XCTAssertTrue(app.staticTexts["rhythm-saved"].waitForExistence(timeout: 5)); attach("Chosen contact rhythm")
        app.buttons["rhythm-done"].tap()
        let peopleSearch = app.textFields["people-search"]; tapVisible(peopleSearch, app: app); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); peopleSearch.typeText("Sofia\n"); visibleTap(app.buttons["person-Sofia Chen"])
        XCTAssertTrue(app.staticTexts["Every 15 days"].exists); XCTAssertTrue(app.staticTexts["Last contact not set"].exists, "Rhythm setup must not manufacture a connection")
        app.buttons["tab-1"].tap(); app.buttons["people-rhythm-setup"].tap(); visibleTap(app.buttons["undo-rhythm"])
        app.buttons["rhythm-done"].tap(); visibleTap(app.buttons["person-Sofia Chen"])
        XCTAssertTrue(app.staticTexts["No regular reminder"].exists, "Undo must work after reopening rhythm setup")
    }
    func testHomeReachOutReturnConfirmationAndNoDuplicateOnReopen() throws {
        launch(["--contact-demo", "--contact-handoff-fixture"])
        visibleTap(app.buttons["reach-out-Sofia Chen"])
        let email = app.buttons["contact-route-Email-sofia@example.invalid"]
        XCTAssertTrue(email.waitForExistence(timeout: 5)); attach("Preferred contact routes"); email.tap()
        XCTAssertTrue(app.buttons["review-contact-draft"].waitForExistence(timeout: 5), "Opening a route must preserve a draft before leaving")
        XCTAssertFalse(app.buttons["handoff-connected"].exists, "An accepted URL alone must not claim a return or create contact")
        XCUIDevice.shared.press(.home); XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5), "Confirm background departure before returning"); app.activate()
        XCTAssertTrue(app.buttons["handoff-outreach"].waitForExistence(timeout: 8), "Returning from a selected route must offer confirmation, never infer contact"); attach("Return from reaching out")
        app.buttons["handoff-outreach"].tap(); XCTAssertTrue(app.buttons["save-moment"].waitForExistence(timeout: 5)); XCTAssertTrue(app.segmentedControls.buttons["Reached out"].isSelected)
        app.buttons["save-moment"].tap(); XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertFalse(app.buttons["handoff-outreach"].exists); XCTAssertFalse(app.buttons["review-contact-draft"].exists)
        app.buttons["tab-2"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@", "history-moment-", "Sofia Chen", "Reached out")).count, 1, "Confirming and reopening must create exactly one outreach")
        app.buttons["tab-1"].tap(); let find = app.textFields["people-search"]; tapVisible(find, app: app); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); find.typeText("Sofia\n"); visibleTap(app.buttons["person-Sofia Chen"])
        XCTAssertTrue(app.staticTexts["47 days since connecting"].exists, "An unanswered reach-out cannot reset the connection")
    }
    func testUnavailableContactAndDismissedDraftCreateNoHistory() throws {
        launch(["--contact-demo", "--contact-handoff-fixture", "--contact-unavailable-fixture"])
        visibleTap(app.buttons["reach-out-Sofia Chen"]); app.buttons["contact-route-Email-sofia@example.invalid"].tap()
        XCTAssertTrue(app.alerts["Contact method unavailable"].waitForExistence(timeout: 6)); app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["review-contact-draft"].exists)
        app.terminate(); launch(["--contact-demo", "--contact-handoff-fixture"])
        visibleTap(app.buttons["reach-out-Sofia Chen"]); app.buttons["contact-route-Email-sofia@example.invalid"].tap()
        XCTAssertTrue(app.buttons["review-contact-draft"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["handoff-discard"].waitForExistence(timeout: 6), "An interrupted draft must be recoverable on cold launch")
        app.buttons["handoff-discard"].tap(); app.buttons["tab-2"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-moment-")).count, 4, "Discarding a draft must leave the four original moments unchanged")
    }
    func testOptionalNextTimeMemoryResolveAndLater() throws {
        launch(); app.buttons["quick-log"].tap(); app.buttons["log-person-Sofia Chen"].tap(); app.buttons["save-moment"].tap()
        app.buttons["moment-follow-through"].tap(); XCTAssertTrue(app.buttons["thread-add-Sofia Chen"].waitForExistence(timeout: 5))
        let resolve = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "thread-resolve-")).firstMatch
        visibleTap(resolve); app.buttons["Resolve and unpin"].tap()
        app.buttons["thread-add-Sofia Chen"].tap(); let note = app.textFields["memory-text"]; XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap(); note.typeText("Ask about the summer exhibition"); app.buttons["save-memory"].tap()
        XCTAssertTrue(app.staticTexts["Ask about the summer exhibition"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Thread resolved. The memory is still here."].exists, "A new thread action must clear the previous resolution notice")
        visibleTap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "thread-later-")).firstMatch)
        app.buttons["save-thread-date"].tap(); attach("Conversation threads for next time")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Follow up ")).firstMatch.exists)
        app.buttons["Close"].tap(); app.buttons["Dismiss next-time suggestion"].tap()
        app.buttons["tab-1"].tap(); let find = app.textFields["people-search"]; tapVisible(find, app: app); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); find.typeText("Sofia\n"); visibleTap(app.buttons["person-Sofia Chen"])
        XCTAssertTrue(app.staticTexts["Connected today"].exists)
        for _ in 0..<5 { if app.staticTexts["Her ceramics show opens in November. Ask how the pieces are coming along."].firstMatch.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Her ceramics show opens in November. Ask how the pieces are coming along."].firstMatch.exists, "Resolving a thread must preserve its original memory")
    }
    func testSocialEventDarkAndLargeText() throws {
        for (flags, name) in [(["--dark"], "Dark shared-event editor"), (["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], "Large shared-event editor")] {
            launch(flags)
            if name.hasPrefix("Large") {
                XCTAssertGreaterThan(app.buttons["log-social-event"].frame.width, app.frame.width * 0.8, "Accessibility Home actions need full width")
            }
            app.buttons["log-social-event"].tap(); XCTAssertTrue(app.buttons["event-people"].waitForExistence(timeout: 5)); attach(name)
            visibleTap(app.buttons["event-people"]); search("Mum"); app.buttons["event-guest-Mum"].tap(); app.buttons["event-people-done"].tap()
            XCTAssertTrue(app.buttons["save-event"].isEnabled); app.buttons["save-event"].tap(); XCTAssertTrue(app.buttons["moment-follow-through"].waitForExistence(timeout: 5)); attach(name + " saved")
            app.terminate()
        }
    }
}
