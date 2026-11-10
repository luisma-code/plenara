import XCTest

extension XCTestCase {
    func assertMinimumTapHeight(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // Native coordinate subtraction returned 43.99999999999994 for a 44pt target.
        // One millionth of a point admits arithmetic noise, far below one device pixel;
        // calibration must still reject a native 43pt target.
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.000001, 44, "Touch targets must be at least 44 points", file: file, line: line)
    }
    func searchAndSubmit(_ value: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        tapVisible(field, app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Search must have keyboard focus before typing", file: file, line: line)
        if let old = field.value as? String, !old.isEmpty && old != field.placeholderValue {
            let clear = field.buttons["Clear text"]
            guard clear.waitForExistence(timeout: 5) else {
                let tree = XCTAttachment(string: app.debugDescription); tree.name = "Search clear action hierarchy"; tree.lifetime = .keepAlways; add(tree)
                XCTFail("The native clear-search action must be available", file: file, line: line); return
            }
            clear.tap()
            let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let actual = field.value as? String ?? ""
                return actual.isEmpty || actual == field.placeholderValue
            }, object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed, "Clear must finish before replacing the query", file: file, line: line)
        }
        // An empty native search has no enabled Search action. Clearing is complete;
        // the caller can use the still-visible footer without inventing a submit event.
        if value.isEmpty { return }
        field.typeText(value + "\n")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let actual = field.value as? String ?? ""
            return actual == value || (value.isEmpty && actual == field.placeholderValue)
        }, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "The submitted query must reach the search field", file: file, line: line)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Submitting search must finish before selecting a result", file: file, line: line)
    }
    func tapVisible(_ element: XCUIElement, app: XCUIApplication, in container: XCUIElement? = nil) {
        let surface = container ?? app
        for _ in 0..<12 {
            let top = max(app.frame.minY + 65, surface.frame.minY)
            var bottom = min(app.frame.maxY - 28, surface.frame.maxY)
            let tab = app.buttons["tab-0"]
            if tab.exists && tab.isHittable { bottom = min(bottom, tab.frame.minY) }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
            let height = bottom - top
            guard height > 44 else { break }
            if element.exists {
                let frame = element.frame
                let visibleTop = max(top, frame.minY), visibleBottom = min(bottom, frame.maxY)
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom { element.tap(); return }
                if element.isHittable && frame.height > height && visibleBottom - visibleTop >= 44 {
                    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: (visibleTop + visibleBottom)/2)).tap(); return
                }
                let up = frame.midY > (top + bottom)/2
                drag(surface, app: app, from: top + height * (up ? 0.78 : 0.22), to: top + height * (up ? 0.28 : 0.72))
            } else { drag(surface, app: app, from: top + height * 0.78, to: top + height * 0.28) }
        }
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "Unreachable action hierarchy"; tree.lifetime = .keepAlways; add(tree)
        XCTFail("The action must be reachable in the visible interface: \(element)")
    }
    private func drag(_ surface: XCUIElement, app: XCUIApplication, from start: CGFloat, to end: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: surface.frame.midX, dy: start)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: surface.frame.midX, dy: end)))
    }
}
