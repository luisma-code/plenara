import XCTest
@testable import Plenara

final class FollowUpTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))! }
    func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }
    func person(_ n: Int, _ name: String, _ closeness: String, kinds: [String] = ["Friend"]) -> Person {
        var p = Person(); p.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!; p.name = name; p.closeness = closeness; p.connectionKinds = kinds; return p
    }
    func testFamilyAndIndependentFiltersCombineWithoutChangingJournal() throws {
        var mei = person(1, "Mei", "Close", kinds: ["Family", "Friend"]); mei.distance = "Nearby"; mei.directionChoice = "Keep it steady"; mei.feelingChoice = "Feels good"
        var lena = person(2, "Lena", "Close", kinds: ["Family"]); lena.distance = "Nearby"; lena.directionChoice = "Grow closer"; lena.feelingChoice = "Needs care"
        var friend = lena; friend.id = UUID(); friend.name = "Another friend"; friend.connectionKinds = ["Friend"]
        var journal = Journal(); journal.people = [friend, lena, mei]; let original = journal
        var selection = FollowUpSelection(); selection.people.connection = "Family"
        XCTAssertEqual(journal.followUpCandidates(selection: selection, now: now).map(\.id), [mei.id, lena.id])
        selection.people.connection = "Friend"
        XCTAssertEqual(Set(journal.followUpCandidates(selection: selection, now: now).map(\.id)), [friend.id, mei.id], "Family + Friend belongs to either type")
        selection.people.connection = "Family"; selection.people.closeness = "Close"; selection.people.distance = "Nearby"; selection.people.direction = "Grow closer"; selection.people.feeling = "Needs care"; selection.status = .unknown
        XCTAssertEqual(journal.followUpCandidates(selection: selection, now: now).map(\.id), [lena.id], "Every selected filter must apply together")
        selection.query = "No match"; XCTAssertTrue(journal.followUpCandidates(selection: selection, now: now).isEmpty)
        XCTAssertEqual(journal, original, "Filtering must not change history, classifications, or reminder permission")
        selection.query = "Lena"; XCTAssertEqual(FollowUpSelection(saved: selection.encoded), selection, "Home choices must survive reopening")
        XCTAssertEqual(FollowUpSelection(saved: "invalid"), FollowUpSelection())
    }
    func testRecentContactSharedEventsPauseSnoozeAndOutreachSuppressOptionalInvitations() {
        var a = person(1, "A", "Inner circle"); a.directionChoice = "Grow closer"
        let b = person(2, "B", "Close")
        var paused = person(3, "Paused", "Inner circle"); paused.paused = true
        var snoozed = person(4, "Snoozed", "Inner circle"); snoozed.snoozeUntil = ago(-1)
        let unanswered = person(5, "Waiting", "Inner circle")
        var j = Journal(); j.people = [a, b, paused, snoozed, unanswered]
        j.moments = [Moment(personID: a.id, date: now, additionalPersonIDs: [b.id], eventTitle: "Lunch"), Moment(personID: unanswered.id, date: ago(2), connected: false)]
        XCTAssertTrue(j.followUpCandidates(now: now, calendar: calendar).isEmpty, "Recent shared contact must cool down every attendee; pause, snooze and unanswered outreach must apply everywhere")
        XCTAssertEqual(Set(j.followUpCandidates(now: ago(-7), calendar: calendar).map(\.id)), [a.id, b.id, snoozed.id, unanswered.id])
        a.cadence = 3; j.people[0] = a; j.moments[0].date = ago(3)
        XCTAssertEqual(j.followUpCandidates(now: now, calendar: calendar).map(\.id), [a.id], "A due short chosen rhythm still wins inside the optional cooldown")
    }
    func testDueOrderAnchorsFamilyFallbackAndStableIdentity() {
        var inner = person(1, "Inner", "Inner circle"); inner.cadence = 7; inner.baselineConnection = ago(8)
        let starter = person(2, "Close starter", "Close")
        var casual = person(3, "Casual due", "Casual"); casual.cadence = 90; casual.baselineConnection = ago(360)
        var close = person(4, "Close due", "Close"); close.cadence = 30; close.baselineConnection = ago(31)
        let family = person(5, "Family", "Not set", kinds: ["Family"])
        var grow = person(6, "Aaron", "Casual"); grow.directionChoice = "Grow closer"
        var unknownDue = person(7, "Started reminder", "Casual"); unknownDue.cadence = 7; unknownDue.reminderStart = ago(8)
        var j = Journal(); j.people = [grow, close, family, casual, starter, inner, unknownDue]
        XCTAssertEqual(j.followUpCandidates(now: now, calendar: calendar).map(\.id), [inner.id, starter.id, casual.id, unknownDue.id, close.id, family.id, grow.id])
        var selection = FollowUpSelection(); selection.status = .due
        XCTAssertEqual(j.followUpCandidates(selection: selection, now: now, calendar: calendar).map(\.id), j.rankedSuggestions(now: now, calendar: calendar).map(\.id), "Due-only Home must preserve the factual due ordering")
        let reason = j.followUpCandidates(now: now, calendar: calendar).first { $0.id == unknownDue.id }!
        XCTAssertNil(reason.connection); XCTAssertTrue(reason.due); XCTAssertEqual(reason.reason, "Reminder due · No contact recorded")
        selection.status = .all; selection.sort = .oldest
        XCTAssertEqual(j.followUpCandidates(selection: selection, now: now, calendar: calendar).first?.id, casual.id, "Unknown contact is not an infinitely old conversation")
        let original = j.followUpCandidates(now: now, calendar: calendar).map(\.id)
        j.people.reverse(); for i in j.people.indices { j.people[i].name = "Renamed \(i)" }
        XCTAssertEqual(j.followUpCandidates(now: now, calendar: calendar).map(\.id), original, "Names and storage order must not determine relationship priority")
    }
    func testApproximateContactReasonsRemainApproximate() {
        var p = person(1, "Person", "Close"); p.baselineConnection = ago(40); p.baselineApproximate = true; p.cadence = 30
        var j = Journal(); j.people = [p]
        XCTAssertTrue(j.followUpCandidates(now: now, calendar: calendar)[0].reason.contains("About 40d"), "An approximate contact date must not become an exact elapsed-contact claim")
        j.people[0].cadence = 0
        XCTAssertEqual(j.followUpCandidates(now: now, calendar: calendar)[0].reason, "Contact about 40d ago")
    }
    func testSavingOffCannotPlantAnOldClockForLaterEnablement() {
        var p = person(1, "Person", "Close"); p.reminderStart = ago(30)
        let off = p; p.prepareReminderSave(previous: off, knownConnection: nil, now: now, calendar: calendar)
        XCTAssertNil(p.reminderStart, "Saving reminders off must not retain or create a schedule anchor")
        p.cadence = 7; p.prepareReminderSave(previous: off, knownConnection: nil, now: now, calendar: calendar)
        XCTAssertEqual(p.reminderStart, calendar.startOfDay(for: now), "Enabling from Off must start today, not revive a disabled clock")
        var j = Journal(); j.people = [p]; XCTAssertFalse(j.isDue(p, now: now, calendar: calendar)); XCTAssertNil(j.lastConnection(p))
        let active = p; p.prepareReminderSave(previous: active, knownConnection: nil, now: ago(-2), calendar: calendar)
        XCTAssertEqual(p.reminderStart, active.reminderStart, "Editing an already enabled schedule must preserve its chosen start")
    }
}
