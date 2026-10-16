import XCTest
import Contacts
@testable import Plenara

@MainActor final class JournalTests: XCTestCase {
    var root: URL!
    override func setUp() { super.setUp(); root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: root); super.tearDown() }
    func store() -> JournalStore { JournalStore(file: root.appendingPathComponent("journal.json")) }
    func testConnectionPersistsAndDeleteRecomputes() throws {
        let s = store(); var p = Person(); p.name = "A friend"; p.cadence = 30
        XCTAssertTrue(s.save(p))
        let old = Moment(personID: p.id, date: Date().addingTimeInterval(-45 * 86400))
        let fresh = Moment(personID: p.id)
        XCTAssertTrue(s.save(old)); XCTAssertTrue(s.save(fresh))
        XCTAssertEqual(s.journal.daysSince(s.journal.lastConnection(p)!), 0)
        let reloaded = store(); XCTAssertEqual(reloaded.journal.people.count, 1); XCTAssertEqual(reloaded.journal.moments.count, 2)
        reloaded.deleteMoment(fresh.id)
        XCTAssertEqual(reloaded.journal.daysSince(try XCTUnwrap(reloaded.journal.lastConnection(p))), 45, "Deleting the latest moment must restore the earlier connection")
        XCTAssertTrue(reloaded.journal.isDue(p))
    }
    func testOutreachDoesNotResetConnectionAndGivesReplySpace() {
        var j = Journal(); var p = Person(); p.name = "Faraway friend"; p.cadence = 30; j.people = [p]
        let old = Date().addingTimeInterval(-60 * 86400)
        j.moments = [Moment(personID: p.id, date: old), Moment(personID: p.id, connected: false)]
        XCTAssertEqual(j.lastConnection(p), old, "An unanswered outreach is not a connection")
        XCTAssertFalse(j.isDue(p), "Recent outreach leaves room for a reply")
        XCTAssertTrue(j.isDue(p, now: Date().addingTimeInterval(8 * 86400)))
    }
    func testSnoozePauseUnknownContactAndRotation() {
        var j = Journal(); var p = Person(); p.name = "New friend"; p.cadence = 7; j.people = [p]
        XCTAssertFalse(j.isDue(p), "An imported person has no fabricated contact history")
        p.reminderStart = Date().addingTimeInterval(-14 * 86400); XCTAssertTrue(j.isDue(p))
        p.snoozeUntil = Date().addingTimeInterval(86400); XCTAssertFalse(j.isDue(p))
        p.snoozeUntil = nil; p.paused = true; XCTAssertFalse(j.isDue(p))
        p.paused = false
        j.people = (0..<6).map { i in var q = p; q.id = UUID(); q.name = "Friend \(i)"; return q }
        let today = j.suggestions(); let tomorrow = j.suggestions(now: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        XCTAssertEqual(today.count, 3); XCTAssertNotEqual(Set(today.map(\.id)), Set(tomorrow.map(\.id)), "Suggestions must rotate rather than strand a distant friend")
    }
    func testCalendarDaysAcrossDaylightSaving() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        let end = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        XCTAssertEqual(Journal().daysSince(start, now: end, calendar: cal), 1)
    }
    func testImportDeduplicatesPreservesJournalAndCanLinkManualPerson() {
        var j = Journal(); var p = Person(); p.name = "Maya"; p.cadence = 14; p.deepen = true; p.notes = [Memory(text: "Loves pottery")]; j.people = [p]
        XCTAssertEqual(Person().relationship, "Not set", "Import must not assume that a family member is a friend")
        var contact = Person(); contact.name = "Maya Thompson"; contact.sourceContactID = "system-id"; contact.phones = ["5551234"]
        ContactImport.apply(contact, to: p.id, journal: &j)
        XCTAssertEqual(j.people.count, 1); XCTAssertEqual(j.people[0].notes, p.notes); XCTAssertTrue(j.people[0].deepen); XCTAssertEqual(j.people[0].cadence, 14)
        ContactImport.apply(contact, to: nil, journal: &j)
        XCTAssertEqual(j.people.count, 1, "Repeat import must use the linked source identifier")
        XCTAssertEqual(j.people[0].phones, ["5551234"])
        contact.sourceContactID = "new-one-time-id"
        ContactImport.apply(contact, to: nil, journal: &j)
        XCTAssertEqual(j.people.count, 1, "One-time contact identifiers must not cause duplicate people")
        XCTAssertEqual(j.people[0].notes, p.notes)
    }
    func testBackupRestoresNotesHistoryAndProtectsAgainstInvalidInput() throws {
        let s = store(); var p = Person(); p.name = "Mum"; p.notes = [Memory(text: "New balcony plants", pinned: true)]; XCTAssertTrue(s.save(p)); XCTAssertTrue(s.save(Moment(personID: p.id)))
        let bytes = try s.exportData(); let other = JournalStore(file: root.appendingPathComponent("restored.json"))
        XCTAssertTrue(other.restore(bytes)); XCTAssertEqual(other.journal, s.journal)
        let original = other.journal
        XCTAssertFalse(other.restore(Data("not a journal".utf8))); XCTAssertEqual(other.journal, original)
        XCTAssertTrue(s.exportText().contains("New balcony plants"))
    }
    func testFailedDiskWriteNeverPublishesUnsavedState() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let obstacle = root.appendingPathComponent("not-a-directory"); try Data("occupied".utf8).write(to: obstacle)
        let s = JournalStore(file: obstacle.appendingPathComponent("journal.json")); var p = Person(); p.name = "Friend"
        XCTAssertFalse(s.save(p)); XCTAssertTrue(s.journal.people.isEmpty, "A failed save must leave the published journal unchanged")
        XCTAssertNotNil(s.errorMessage)
    }
    func testCorruptJournalIsNotOverwritten() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("journal.json"); let bytes = Data("damaged".utf8); try bytes.write(to: file)
        let previous = try JournalStore.encoder.encode(Journal()); try previous.write(to: file.appendingPathExtension("previous"))
        let s = store(); XCTAssertTrue(s.locked); var p = Person(); p.name = "Friend"; XCTAssertFalse(s.save(p)); XCTAssertEqual(try Data(contentsOf: file), bytes)
        let j = Journal(); XCTAssertTrue(s.restore(try JournalStore.encoder.encode(j))); XCTAssertFalse(s.locked); XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("previous")), previous, "Recovery must not overwrite a good previous save with the damaged file")
    }
    func testDatedRemindersHaveVisiblePersonContext() {
        let now = Date(); var j = Journal(); var p = Person(); p.name = "Mum"; p.birthdayMonth = Calendar.current.component(.month, from: now); p.birthdayDay = Calendar.current.component(.day, from: now); p.birthdayReminder = true
        p.notes = [Memory(text: "Ask about the plants", followUp: now), Memory(text: "Old thread", archived: true, followUp: now), Memory(text: "For later", followUp: now.addingTimeInterval(86400 * 3))]; j.people = [p]
        let reminders = j.datedReminders(now: now)
        XCTAssertEqual(reminders.count, 2, "Birthday and dated notes must be visible in context")
        XCTAssertTrue(reminders.allSatisfy { $0.person.id == p.id })
        j.people[0].paused = true; XCTAssertTrue(j.datedReminders(now: now).isEmpty, "Pausing a person hides their dated reminders")
    }
    func testRemindersHonorQuietHoursAndDoNotExposePrivateNotes() {
        var j = Journal(); var p = Person(); p.name = "Private Person"; p.birthdayMonth = 12; p.birthdayDay = 2; p.birthdayReminder = true; p.notes = [Memory(text: "Private medical note", followUp: Date().addingTimeInterval(86400 * 5))]; j.people = [p]
        XCTAssertTrue(ReminderPlan.make(j).isEmpty)
        j.preferences.notifications = true; j.preferences.hour = 22; j.preferences.birthdays = true; j.preferences.followUps = true
        let plans = ReminderPlan.make(j)
        XCTAssertEqual(plans.count, 3); XCTAssertTrue(plans.allSatisfy { $0.components.hour == 8 })
        XCTAssertTrue(plans.allSatisfy { !$0.body.contains(p.name) && !$0.body.contains("medical") })
        XCTAssertTrue(plans[0].repeats)
        j.people[0].paused = true
        XCTAssertEqual(ReminderPlan.make(j).count, 1, "Pausing a person also pauses their birthday and follow-up reminders")
    }
}
