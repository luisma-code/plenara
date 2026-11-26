import XCTest
@testable import Plenara

final class RankingTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))! }
    func person(_ id: Int, _ closeness: String, days: Int, cadence: Int, growth: Bool = false) -> Person {
        var p = Person(); p.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!
        p.name = "Person \(id)"; p.closeness = closeness; p.cadence = cadence
        p.baselineConnection = calendar.date(byAdding: .day, value: -days, to: now)!
        p.directionChoice = growth ? "Grow closer" : "Keep it steady"
        return p
    }
    func testColdStartStartsWithClosePeopleWithoutInventingHistory() {
        var aaron = person(1, "Casual", days: 0, cadence: 0, growth: true); aaron.name = "Aaron"; aaron.baselineConnection = nil
        var inner = person(2, "Inner circle", days: 0, cadence: 0); inner.name = "Zoe"; inner.baselineConnection = nil
        var family = person(3, "Close", days: 0, cadence: 0); family.name = "Mei"; family.connectionKinds = ["Family"]; family.baselineConnection = nil
        var journal = Journal(); journal.people = [aaron, family, inner]
        XCTAssertEqual(journal.followUpCandidates(now: now, calendar: calendar).first?.id, inner.id, "Home must start with chosen closeness when contact history and reminders are missing, including Keep it steady")
        XCTAssertTrue(journal.people.allSatisfy { journal.lastConnection($0) == nil && $0.cadence == 0 })
    }
    func testInnerCircleCannotBeDisplacedByGrowthOrCalendarRotation() {
        let inner = person(1, "Inner circle", days: 8, cadence: 7)
        let close = person(2, "Close", days: 90, cadence: 30, growth: true)
        var journal = Journal(); journal.people = [close, inner]
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).first?.id, inner.id, "A due inner-circle person must lead even when Close has growth intent and a longer relative gap")
        journal.people += (3...7).map { person($0, "Casual", days: 360, cadence: 90, growth: true) }
        for day in 0..<8 {
            let date = calendar.date(byAdding: .day, value: day, to: now)!
            XCTAssertEqual(journal.rankedSuggestions(now: date, calendar: calendar).first?.id, inner.id, "Calendar rotation must never displace the due inner-circle leader")
        }
    }
    func testFullOrderUsesTwoGroupsRatiosAndExactTies() {
        let innerA = person(1, "Inner circle", days: 15, cadence: 7)
        let innerB = person(2, "Inner circle", days: 40, cadence: 30)
        let close = person(3, "Close", days: 31, cadence: 30, growth: true)
        let casual = person(4, "Casual", days: 360, cadence: 90)
        var journal = Journal(); journal.people = [close, casual, innerB, innerA]
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), [innerA.id, innerB.id, casual.id, close.id])
        let steady = person(5, "Close", days: 60, cadence: 30)
        let grow = person(6, "Close", days: 14, cadence: 7, growth: true)
        let unknown = person(7, "Not set", days: 180, cadence: 90, growth: true)
        let casualTie = person(8, "Casual", days: 60, cadence: 30, growth: true)
        var same = steady; same.id = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        journal.people = [same, casualTie, unknown, steady, grow]
        let expected = [grow.id, steady.id, same.id, casualTie.id, unknown.id]
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), expected, "Exact ties use closeness, then growth, then stable identity")
        journal.people.reverse()
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), expected, "Storage order must not affect priority")
    }
    func testEligibilityHonorsCustomRhythmsUnknownHistoryAndReplySpace() {
        var journal = Journal()
        var monthlyInner = person(1, "Inner circle", days: 20, cadence: 30, growth: true)
        var unknown = person(2, "Inner circle", days: 200, cadence: 7); unknown.baselineConnection = nil
        let casual = person(3, "Casual", days: 100, cadence: 90)
        journal.people = [monthlyInner, unknown, casual]
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), [casual.id], "Classification and growth cannot override a custom rhythm or fabricate history")
        unknown.reminderStart = calendar.date(byAdding: .day, value: -8, to: now)
        journal.people[1] = unknown
        XCTAssertNil(journal.lastConnection(unknown))
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), [unknown.id, casual.id])
        monthlyInner.cadence = 0; monthlyInner.feelingChoice = "Needs care"; journal.people[0] = monthlyInner
        XCTAssertFalse(journal.rankedSuggestions(now: now, calendar: calendar).contains { $0.id == monthlyInner.id })
        journal.moments = [Moment(personID: unknown.id, date: calendar.date(byAdding: .day, value: -2, to: now)!, connected: false)]
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), [casual.id], "Recent outreach suppresses inner circle too")
        journal.moments = []; unknown.snoozeUntil = now.addingTimeInterval(60); journal.people[1] = unknown
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), [casual.id])
        unknown.snoozeUntil = nil; unknown.paused = true; journal.people[1] = unknown
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), [casual.id])
    }
    func testMomentsAndNotesRecomputeRealPriorityWithoutInventingContact() {
        var journal = Journal(); let inner = person(1, "Inner circle", days: 15, cadence: 7)
        let close = person(2, "Close", days: 90, cadence: 30); journal.people = [inner, close]
        let original = journal.rankedSuggestions(now: now, calendar: calendar).map(\.id)
        journal.people[0].notes = [Memory(text: "Remember this", date: now)]
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), original)
        journal.moments = [Moment(personID: inner.id, date: now)]
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), [close.id])
        journal.moments[0].date = calendar.date(byAdding: .day, value: -8, to: now)!
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), original)
        journal.moments.removeAll()
        XCTAssertEqual(journal.rankedSuggestions(now: now, calendar: calendar).map(\.id), original, "Deleting a moment must restore the remaining real connection anchor")
    }
}
