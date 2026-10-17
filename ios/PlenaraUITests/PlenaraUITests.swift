import XCTest
import UIKit

final class PlenaraUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset"]; app.launch() }
    func testManualPersonMemoryMomentAndReopen() throws {
        app.buttons["Bring your people in"].tap(); app.buttons["Add someone yourself"].tap()
        let name = app.textFields["person-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Julia Test")
        app.buttons["save-person"].tap()
        let setupFinished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["tab-1"])
        XCTAssertEqual(XCTWaiter.wait(for: [setupFinished], timeout: 5), .completed, "Finishing setup must return to the app")
        app.buttons["tab-1"].tap(); app.buttons["person-Julia Test"].tap()
        app.buttons["Add a note"].tap(); let memory = app.textFields["memory-text"]; memory.tap(); memory.typeText("Ask about the exhibition")
        app.buttons["save-memory"].tap()
        app.swipeUp(); XCTAssertTrue(app.buttons["memory-row"].firstMatch.waitForExistence(timeout: 5)); app.swipeDown()
        app.buttons["Log a moment"].tap(); app.buttons["save-moment"].tap()
        XCTAssertTrue(app.staticTexts["Connected today"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch(); app.buttons["tab-1"].tap(); app.buttons["person-Julia Test"].tap()
        XCTAssertTrue(app.staticTexts["Connected today"].waitForExistence(timeout: 5)); app.swipeUp(); XCTAssertTrue(app.staticTexts["Ask about the exhibition"].firstMatch.exists)
    }
    func testDemoNavigationAndScreenshots() throws {
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["A little closer."].waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(app.buttons["tab-1"].frame.height, 44); XCTAssertGreaterThanOrEqual(app.buttons["Log a moment"].frame.height, 44); XCTAssertGreaterThanOrEqual(app.buttons["Another week"].frame.height, 44); attach("Stay close")
        app.buttons["tab-1"].tap(); attach("People"); app.buttons["Far away"].tap(); XCTAssertTrue(app.buttons["person-Sofia Chen"].exists); XCTAssertFalse(app.buttons["person-Daniel Rivera"].exists)
        app.buttons["Everyone"].tap(); app.swipeUp(); app.buttons["person-Sofia Chen"].tap(); XCTAssertTrue(app.staticTexts["Sofia Chen"].firstMatch.waitForExistence(timeout: 5)); attach("Person")
        app.swipeUp(); attach("Person notes"); app.buttons["tab-2"].tap(); XCTAssertTrue(app.staticTexts["Time well spent."].exists); attach("Moments")
        app.buttons["tab-0"].tap(); app.buttons["Settings and reminders"].tap(); XCTAssertTrue(app.buttons["Export a restorable backup"].exists); attach("Settings"); app.buttons["Export a restorable backup"].tap()
        let export = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Save"]
        XCTAssertTrue(export.waitForExistence(timeout: 8), "The native Files export destination must open")
        attach("Backup export"); let exportedName = app.textFields["DOCPicker.filenameTextField"].value as? String ?? ""; export.tap()
        XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForNonExistence(timeout: 5))
        let status = app.staticTexts["settings-status"]
        for _ in 0..<3 { if status.exists { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Your export was saved.", "The backup must actually be saved through Files")
        app.collectionViews.firstMatch.swipeDown(); app.buttons["Restore from a backup"].tap()
        let file = app.collectionViews.cells.matching(NSPredicate(format: "label CONTAINS %@", exportedName)).firstMatch
        XCTAssertFalse(exportedName.isEmpty); XCTAssertTrue(file.waitForExistence(timeout: 8), "The saved backup must be available in the native Files picker")
        file.tap()
        let replace = app.buttons["Replace with backup"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5)); replace.tap()
        let restored = app.staticTexts["settings-status"]
        for _ in 0..<3 { if restored.exists && restored.label.hasPrefix("Restored ") { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(restored.label.hasPrefix("Restored 5 people and 4 moments"), "Restoring the exported journal must complete")

    }
    func testNativeContactPickerImportAndRepeat() throws {
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--contact-fixture"]; app.launch()
        app.buttons["tab-1"].tap(); app.buttons["Import from Contacts"].tap(); app.buttons["Choose from Contacts"].tap()
        let maya = app.collectionViews.staticTexts["Maya Plenara Test"].firstMatch
        XCTAssertTrue(maya.waitForExistence(timeout: 8), "The native picker must display the real seeded system contact")
        app.navigationBars["Contacts"].buttons["Done"].tap(); XCTAssertTrue(app.navigationBars["Contacts"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose from Contacts"].waitForExistence(timeout: 5), "Finishing without a selection must keep the import screen available")
        app.buttons["Choose from Contacts"].tap(); XCTAssertTrue(maya.waitForExistence(timeout: 5))
        maya.tap(); app.navigationBars["Contacts"].buttons["Done"].tap(); XCTAssertTrue(app.navigationBars["Contacts"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import selected people"].waitForExistence(timeout: 5)); app.buttons["Import selected people"].tap(); app.alerts.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["person-Maya Plenara Test"].waitForExistence(timeout: 5)); app.buttons["person-Maya Plenara Test"].tap()
        XCTAssertTrue(app.staticTexts["No regular reminder"].exists); XCTAssertTrue(app.staticTexts["Last contact not set"].exists)
        app.buttons["tab-1"].tap(); app.buttons["Import from Contacts"].tap(); app.buttons["Choose from Contacts"].tap()
        XCTAssertTrue(maya.waitForExistence(timeout: 5)); maya.tap(); app.navigationBars["Contacts"].buttons["Done"].tap(); XCTAssertTrue(app.navigationBars["Contacts"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import selected people"].waitForExistence(timeout: 5)); attach("Repeat import review"); XCTAssertTrue(app.staticTexts["0 selected"].exists, "A previously imported contact must start unselected")
        app.switches.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); app.buttons["Import selected people"].tap(); app.alerts.buttons["Done"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "person-Maya Plenara Test").count, 1)

    }
    func testDatedReminderContext() throws {
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo", "--dated-demo"]; app.launch()
        XCTAssertTrue(app.buttons["dated-Mum"].waitForExistence(timeout: 5), "A due reminder must show its person context")
        attach("Dated reminders"); app.buttons["dated-Mum"].tap()
        XCTAssertTrue(app.staticTexts["birthday-info"].waitForExistence(timeout: 5))
        app.buttons["tab-0"].tap(); app.swipeUp(); app.buttons["Picked up this thread"].tap()
        XCTAssertFalse(app.buttons["dated-Sofia Chen"].exists, "Clearing the date keeps the memory but removes its reminder")
        XCTAssertTrue(app.staticTexts["Her ceramics show opens in November. Ask how the pieces are coming along."].firstMatch.exists, "Completing a dated reminder must keep the memory")
    }
    func testNotificationPermissionAndNativeSchedule() throws {
        app.buttons["Settings and reminders"].tap()
        app.switches["notifications-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        else if app.alerts.buttons["Allow"].exists { app.alerts.buttons["Allow"].tap() }
        XCTAssertTrue(app.staticTexts["Your weekly reminder is ready."].waitForExistence(timeout: 8), "A system-accepted local weekly reminder must exist after opt-in")
        attach("Reminder settings")
        app.switches["notifications-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertFalse(app.staticTexts["Your weekly reminder is ready."].exists)
    }
    func testDarkAndLargeTextNavigation() throws {
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo", "--dark"]; app.launch()
        XCTAssertTrue(app.staticTexts["A little closer."].waitForExistence(timeout: 5)); assertDarkBackground(); attach("Dark Stay close")
        app.buttons["tab-1"].tap(); app.swipeUp(); app.buttons["person-Sofia Chen"].tap(); attach("Dark person")
        app.buttons["relationship-intention"].tap(); waitForRelationshipEditor(); attach("Dark relationship choices"); app.buttons["Cancel"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["tab-1"].waitForExistence(timeout: 5)); app.buttons["tab-1"].tap(); attach("Large text People")
        let search = app.textFields["people-search"]; search.tap(); search.typeText("Sofia\n")
        app.swipeUp(); app.buttons["person-Sofia Chen"].tap(); XCTAssertTrue(app.buttons["relationship-intention"].waitForExistence(timeout: 5)); attach("Large text person")
        let relationship = app.buttons["relationship-intention"]
        for _ in 0..<4 { if relationship.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(relationship.isHittable); relationship.tap(); waitForRelationshipEditor()
        XCTAssertTrue(app.buttons["feeling-choice"].waitForExistence(timeout: 5)); attach("Large text relationship choices")
        app.buttons["Cancel"].tap()
        app.buttons["tab-0"].tap(); XCTAssertTrue(app.staticTexts["A little closer."].exists)
    }
    func testExistingImportSurvivesUpgradeAndIndependentChoices() throws {
        let fixture = try XCTUnwrap(Bundle(for: PlenaraUITests.self).url(forResource: "journal-build-1001", withExtension: "json"))
        let bytes = try Data(contentsOf: fixture)
        app.terminate(); app.launchArguments = ["--ui-testing", "--legacy-fixture"]
        app.launchEnvironment["PLENARA_LEGACY_JOURNAL"] = bytes.base64EncodedString(); app.launch()
        app.buttons["tab-1"].tap()
        XCTAssertTrue(app.buttons["person-Maya Imported"].waitForExistence(timeout: 5), "The previous-version import must open without reimporting")
        XCTAssertTrue(app.buttons["person-Alex Imported"].exists)
        app.buttons["person-Maya Imported"].tap()
        let intention = app.buttons["relationship-intention"]
        XCTAssertTrue(intention.waitForExistence(timeout: 5)); XCTAssertTrue(intention.label.contains("Grow closer"))
        XCTAssertFalse(intention.label.contains("Feels good")); XCTAssertFalse(intention.label.contains("Needs care"))
        attach("Migrated imported person")
        intention.tap(); waitForRelationshipEditor()
        choose("direction-choice", "Keep it steady")
        choose("feeling-choice", "Needs care")
        XCTAssertEqual(app.textFields["relationship-context"].value as? String, "Lunch together", "Existing intention text must survive the new choices")
        attach("Independent relationship choices")
        app.buttons["save-relationship"].tap()
        XCTAssertTrue(intention.waitForExistence(timeout: 5)); XCTAssertTrue(intention.label.contains("Keep it steady")); XCTAssertTrue(intention.label.contains("Needs care"))
        app.buttons["Edit"].tap()
        let friend = app.switches["connection-Friend"]
        for _ in 0..<4 { if friend.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(friend.isHittable); friend.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        choose("closeness-choice", "Casual")
        choose("distance-choice", "Far away")
        attach("About your relationship")
        app.buttons["save-person"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launchEnvironment = [:]; app.launch()
        app.buttons["tab-1"].tap(); app.buttons["person-Maya Imported"].tap()
        XCTAssertTrue(app.staticTexts["Family"].exists); XCTAssertTrue(app.staticTexts["Friend"].exists); XCTAssertTrue(app.staticTexts["Casual"].exists); XCTAssertTrue(app.staticTexts["Far away"].exists)
        XCTAssertTrue(intention.label.contains("Keep it steady")); XCTAssertTrue(intention.label.contains("Needs care"))
        attach("Updated relationship profile")
        let memory = app.staticTexts["Ask about the exhibition"]
        for _ in 0..<4 { if memory.exists { break }; app.swipeUp() }
        XCTAssertTrue(memory.exists, "The existing imported person's notes must survive upgrade and editing")
        app.buttons["tab-1"].tap()
        shortcut("Family"); shortcut("Far away"); shortcut("Needs care")
        XCTAssertTrue(app.buttons["person-Maya Imported"].exists)
        XCTAssertFalse(app.buttons["person-Alex Imported"].exists, "A combined filter must exclude a person matching only distance")
        XCTAssertEqual(app.staticTexts["people-count"].label, "1 person")
        attach("Combined relationship filters")
        app.buttons["people-filters"].tap(); attach("All relationship filters"); app.buttons["Close"].tap()
        shortcut("Grow closer")
        XCTAssertTrue(app.staticTexts["No one matches yet."].exists)
        app.buttons["Clear filters"].tap()
        XCTAssertTrue(app.buttons["person-Maya Imported"].exists); XCTAssertTrue(app.buttons["person-Alex Imported"].exists)
    }
    func testQuickLogCallsTextsVisitsAndNotesSurviveReopen() throws {
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo"]; app.launch()
        for (channel, note) in [("Call", ""), ("Messages", "Ask about the new job"), ("In person", "Walked by the lake")] {
            app.buttons["quick-log"].tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Sofia")
            let person = app.buttons["log-person-Sofia Chen"]
            XCTAssertTrue(person.waitForExistence(timeout: 5))
            if channel == "Call" { attach("Quick person chooser") }
            person.tap()
            let choice = app.buttons["channel-\(channel)"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(choice.frame.height, 44); choice.tap()
            XCTAssertTrue(choice.isSelected, "A one-tap channel choice must actually select \(channel)")
            XCTAssertTrue(app.descendants(matching: .any)["moment-person"].firstMatch.label.contains("Sofia Chen"))
            if channel == "Call" { attach("Quick moment editor") }
            if !note.isEmpty { let field = app.textFields["moment-note"]; field.tap(); field.typeText(note) }
            app.buttons["save-moment"].tap()
            XCTAssertTrue(app.buttons["quick-log"].waitForExistence(timeout: 5))
        }
        // Cancelling a draft must not create a fourth entry.
        app.buttons["quick-log"].tap(); app.buttons["log-person-Sofia Chen"].tap()
        XCTAssertTrue(app.buttons["save-moment"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch(); app.buttons["tab-2"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sofia Chen ·")).count, 4, "Three saves and one cancelled draft must add exactly three moments to Sofia’s existing history")
        for (channel, note) in [("Call", ""), ("Messages", "Ask about the new job"), ("In person", "Walked by the lake")] {
            let predicate = note.isEmpty ? NSPredicate(format: "label BEGINSWITH %@", "Sofia Chen · \(channel)") : NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Sofia Chen · \(channel)", note)
            let row = app.buttons.matching(predicate).firstMatch
            for _ in 0..<4 { if row.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(row.exists, "The saved \(channel) and its note must survive reopening")
        }
        app.swipeDown(); attach("Quick moment history")
        let text = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ask about the new job")).firstMatch
        text.tap(); let field = app.textFields["moment-note"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertEqual(field.value as? String, "Ask about the new job")
        app.segmentedControls.buttons["Reached out"].tap(); app.buttons["save-moment"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Ask about the new job", "Reached out")).firstMatch.waitForExistence(timeout: 5))
    }
    func testQuickLogDarkAndLargeText() throws {
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo", "--dark"]; app.launch()
        app.buttons["quick-log"].tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Mum")
        app.buttons["log-person-Mum"].tap()
        XCTAssertTrue(app.buttons["channel-Messages"].waitForExistence(timeout: 5)); waitForRelationshipEditor(); attach("Dark quick moment")
        app.buttons["Cancel"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        let quickLog = app.buttons["quick-log"]
        XCTAssertTrue(quickLog.isHittable && quickLog.frame.maxY <= app.buttons["tab-0"].frame.minY && quickLog.frame.minY >= 0, "Quick logging must stay visible above the introduction at the largest text size")
        app.buttons["quick-log"].tap()
        let largeSearch = app.searchFields.firstMatch
        XCTAssertTrue(largeSearch.waitForExistence(timeout: 5)); largeSearch.tap(); largeSearch.typeText("Mum")
        app.buttons["log-person-Mum"].tap()
        let met = app.buttons["channel-In person"]
        for _ in 0..<4 { if met.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(met.isHittable); met.tap(); XCTAssertTrue(met.isSelected); attach("Large quick moment")
        app.buttons["save-moment"].tap()
        XCTAssertTrue(app.buttons["quick-log"].waitForExistence(timeout: 5))
    }
    func waitForRelationshipEditor() {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let button = value as? XCUIElement else { return false }
            return button.isHittable && button.frame.minY < 150
        }, object: app.buttons["Cancel"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, "The relationship sheet must finish presenting before capture or input")
    }
    func choose(_ identifier: String, _ value: String) {
        let control = app.buttons[identifier]
        for _ in 0..<3 { if control.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(control.isHittable, "The relationship choice must be reachable: \(identifier)")
        control.tap(); app.buttons[value].tap()
    }
    func shortcut(_ label: String) {
        let control = app.buttons["filter-\(label)"]
        let strip = app.scrollViews["people-shortcuts"]
        if !control.isHittable { strip.swipeRight() }
        for _ in 0..<3 { if control.isHittable { break }; strip.swipeLeft() }
        XCTAssertTrue(control.isHittable); control.tap()
    }
    func assertDarkBackground() {
        let image = app.screenshot().image
        guard let cg = image.cgImage, let crop = cg.cropping(to: CGRect(x: 10 * image.scale, y: 160 * image.scale, width: 1, height: 1)) else { XCTFail("Couldn’t sample the rendered canvas"); return }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let brightness = Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 765
        XCTAssertLessThan(brightness, 0.3, "Dark mode must render a dark canvas, not just accept a launch argument")
    }
    func attach(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
