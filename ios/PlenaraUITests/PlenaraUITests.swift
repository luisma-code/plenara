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
        app.terminate(); app.launchArguments = ["--ui-testing", "--reset", "--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["tab-1"].waitForExistence(timeout: 5)); app.buttons["tab-1"].tap(); attach("Large text People")
        let search = app.textFields["people-search"]; search.tap(); search.typeText("Sofia\n")
        app.swipeUp(); app.buttons["person-Sofia Chen"].tap(); XCTAssertTrue(app.buttons["deepen-toggle"].waitForExistence(timeout: 5)); attach("Large text person")
        app.buttons["tab-0"].tap(); XCTAssertTrue(app.staticTexts["A little closer."].exists)
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
