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
        app.buttons["tab-1"].tap(); openVisiblePeopleImport(); app.buttons["Choose from Contacts"].tap()
        let maya = app.collectionViews.staticTexts["Maya Plenara Test"].firstMatch
        XCTAssertTrue(maya.waitForExistence(timeout: 8), "The native picker must display the real seeded system contact")
        app.navigationBars["Contacts"].buttons["Done"].tap(); XCTAssertTrue(app.navigationBars["Contacts"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose from Contacts"].waitForExistence(timeout: 5), "Finishing without a selection must keep the import screen available")
        app.buttons["Choose from Contacts"].tap(); XCTAssertTrue(maya.waitForExistence(timeout: 5))
        maya.tap(); app.navigationBars["Contacts"].buttons["Done"].tap(); XCTAssertTrue(app.navigationBars["Contacts"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import selected people"].waitForExistence(timeout: 5)); app.buttons["Import selected people"].tap(); app.alerts.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["person-Maya Plenara Test"].waitForExistence(timeout: 5)); app.buttons["person-Maya Plenara Test"].tap()
        XCTAssertTrue(app.staticTexts["No regular reminder"].exists); XCTAssertTrue(app.staticTexts["Last contact not set"].exists)
        app.buttons["tab-1"].tap(); openVisiblePeopleImport(); app.buttons["Choose from Contacts"].tap()
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
        app.swipeDown()
        let clear = app.buttons["people-clear-filters"]
        XCTAssertTrue(clear.isHittable && clear.frame.maxY < app.buttons["tab-1"].frame.minY, "Clear filters must be visible beside Filters")
        clear.tap()
        XCTAssertEqual(app.staticTexts["people-count"].label, "2 people", "Clearing filters must restore the complete imported list")
        app.swipeUp()
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
    func testOrganizeBulkSelectionCancelUndoAndImportedJournalReopen() throws {
        let fixture = try XCTUnwrap(Bundle(for: PlenaraUITests.self).url(forResource: "journal-build-1001", withExtension: "json"))
        app.terminate(); app.launchArguments = ["--ui-testing", "--legacy-fixture"]
        app.launchEnvironment["PLENARA_LEGACY_JOURNAL"] = try Data(contentsOf: fixture).base64EncodedString(); app.launch()
        openOrganizer()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Alex")
        app.buttons["organize-person-Alex Imported"].tap()
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Maya")
        XCTAssertTrue(app.staticTexts["organize-selection-count"].label.contains("outside this search"), "Selection outside a search must stay visible in the count")
        app.buttons["organize-person-Maya Imported"].tap()
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertEqual(app.staticTexts["organize-selection-count"].label, "2 selected")
        app.buttons["organize-apply"].tap()
        XCTAssertTrue(app.buttons["batch-save"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["batch-save"].isEnabled)
        chooseOrganization("batch-Connection", "Add Friend"); chooseOrganization("batch-Distance", "Nearby"); chooseOrganization("batch-How it feels", "Needs care")
        assertSharedDetailsHasNoKeyboardPanel()
        attach("Organize shared details"); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["organize-apply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["organize-person-Alex Imported"].label.contains("Far away"), "Cancelling bulk choices must not save")
        XCTAssertFalse(app.buttons["organize-undo"].exists)
        attach("Organize selected people")
        applyOrganizationBatch()
        XCTAssertTrue(app.buttons["organize-undo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["organize-person-Maya Imported"].label.contains("Family + Friend"), "Adding Friend must preserve Family")
        XCTAssertTrue(app.buttons["organize-person-Alex Imported"].label.contains("Nearby"), "The shared distance must save for both selected people")
        attach("Organized people and undo")
        app.buttons["organize-undo"].tap()
        XCTAssertTrue(app.buttons["organize-person-Alex Imported"].label.contains("Far away"), "Undo must restore the prior distance")
        XCTAssertFalse(app.buttons["organize-person-Maya Imported"].label.contains("Family + Friend"))
        app.buttons["organize-select-shown"].tap(); applyOrganizationBatch()
        app.buttons["Close"].tap(); app.terminate(); app.launchEnvironment = [:]; app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["tab-1"].tap(); app.buttons["person-Maya Imported"].tap()
        XCTAssertTrue(app.staticTexts["Family"].exists); XCTAssertTrue(app.staticTexts["Friend"].exists)
        XCTAssertTrue(app.buttons["relationship-intention"].label.contains("Needs care"))
        XCTAssertTrue(app.buttons["relationship-intention"].label.contains("Grow closer"), "An untouched intention must survive bulk organization")
        let memory = app.staticTexts["Ask about the exhibition"]
        for _ in 0..<4 { if memory.exists { break }; app.swipeUp() }
        XCTAssertTrue(memory.exists, "Existing imported notes must survive bulk organization and reopening")
    }
    func testOrganizeQuickSortUnsetSkipUndoAndSave() throws {
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo"]; app.launch(); openOrganizer()
        app.segmentedControls.buttons["Quick sort"].tap()
        chooseOrganization("organize-field", "What I want")
        app.switches["organize-unset-only"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("Leo\n")
        let grow = app.buttons["sort-Leo Park-Grow closer"]
        XCTAssertTrue(grow.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(grow.frame.height, 44)
        attach("Quick sort unanswered")
        grow.tap()
        XCTAssertFalse(app.buttons["sort-skip-Leo Park"].exists, "Setting a value must remove it from the Not set only view")
        app.buttons["organize-undo"].tap()
        XCTAssertTrue(grow.waitForExistence(timeout: 5), "Undo must return a person to the unanswered list")
        app.buttons["sort-skip-Leo Park"].tap()
        XCTAssertFalse(grow.exists, "Skip must leave this person out of the current pass")
        app.buttons["Show skipped people"].tap(); XCTAssertTrue(grow.waitForExistence(timeout: 5))
        grow.tap(); app.buttons["Close"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch(); app.buttons["tab-1"].tap()
        app.buttons["Grow closer"].tap()
        let leo = app.buttons["person-Leo Park"]
        for _ in 0..<3 { if leo.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(leo.exists, "Quick-sort choices must persist and drive the real People filters")
        leo.tap(); XCTAssertTrue(app.staticTexts["Far away"].exists)
        XCTAssertTrue(app.buttons["relationship-intention"].label.contains("Needs care"), "Quick sorting intention must preserve feeling")
        attach("Quick sorted profile")
    }
    func testOrganizeDarkAndLargeText() throws {
        for (flag, label) in [(["--dark"], "Dark organizer"), (["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], "Large text organizer")] {
            app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo"] + flag; app.launch(); openOrganizer()
            app.segmentedControls.buttons["Quick sort"].tap()
            let nearby = app.buttons["sort-Amara Okafor-Nearby"]
            for _ in 0..<5 { if nearby.isHittable && nearby.frame.maxY < app.frame.maxY - 100 { break }; app.descendants(matching: .any)["organize-list"].firstMatch.swipeUp() }
            XCTAssertTrue(nearby.isHittable); nearby.tap(); attach(label)
            app.buttons["Close"].tap(); XCTAssertTrue(app.buttons["people-organize"].waitForExistence(timeout: 5))
        }
    }
    func sharedFormPanelColor() -> Double {
        let image = app.screenshot().image
        guard let cg = image.cgImage,
              let crop = cg.cropping(to: CGRect(x: CGFloat(cg.width) * 0.0166, y: CGFloat(cg.height) * 0.8093, width: CGFloat(cg.width) * 0.0332, height: CGFloat(cg.height) * 0.0763)) else { return 255 }
        var rgba = [UInt8](repeating: 0, count: 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return 255 }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Double(Int(rgba[2]) - Int(rgba[0]))
    }
    func assertSharedDetailsHasNoKeyboardPanel() {
        // This light iPhone simulator patch is warm paper without a keyboard,
        // cool/neutral when the inherited keyboard paints below the form.
        // Known broken/good native captures: B-R +0.25 / -3.16 (patch mean).
        // AX keyboard existence misses the retained, inaccessible panel entirely.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.sharedFormPanelColor() < -1 }, object: app)
        let result = XCTWaiter.wait(for: [ready], timeout: 5)
        print("Shared form rendered blue-minus-red: \(sharedFormPanelColor())")
        XCTAssertEqual(result, .completed, "The search keyboard must close before shared details open")
    }
    func openVisiblePeopleImport() {
        let entry = app.buttons["Import from Contacts"]
        let bottom = app.buttons["tab-1"].frame.minY
        for _ in 0..<6 {
            if entry.exists && entry.isHittable && entry.frame.minY > 0 && entry.frame.maxY < bottom { break }
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable && entry.frame.minY > 0 && entry.frame.maxY < bottom, "The actual import button must be visible above the tab bar before tapping")
        entry.tap()
        XCTAssertTrue(app.buttons["Choose from Contacts"].waitForExistence(timeout: 5), "The visible import action must open the native import flow")
    }
    func openOrganizer() {
        app.buttons["tab-1"].tap()
        let entry = app.buttons["people-organize"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); XCTAssertTrue(entry.isHittable && entry.frame.maxY < app.buttons["tab-1"].frame.minY, "Organize must be reachable above the People introduction")
        entry.tap(); XCTAssertTrue(app.segmentedControls["organize-mode"].waitForExistence(timeout: 5))
    }
    func applyOrganizationBatch() {
        app.buttons["organize-apply"].tap()
        XCTAssertTrue(app.buttons["batch-save"].waitForExistence(timeout: 5))
        chooseOrganization("batch-Connection", "Add Friend"); chooseOrganization("batch-Distance", "Nearby"); chooseOrganization("batch-How it feels", "Needs care")
        app.buttons["batch-save"].tap()
    }
    func chooseOrganization(_ identifier: String, _ value: String) {
        let control = app.buttons[identifier]
        for _ in 0..<4 { if control.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(control.isHittable); control.tap()
        // Native picker options live in the presented collection, while the
        // covered People screen retains a shortcut with the same Nearby label.
        let option = app.collectionViews.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5)); XCTAssertTrue(option.isHittable); option.tap()
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
