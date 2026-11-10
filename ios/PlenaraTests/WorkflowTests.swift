import XCTest
@testable import Plenara

@MainActor final class WorkflowTests: XCTestCase {
    var root: URL!
    override func setUp() { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }
    func store(_ name: String = "journal.json") -> JournalStore { JournalStore(file: root.appendingPathComponent(name)) }
    func people(_ count: Int = 5) -> [Person] {
        (0..<count).map { i in var p = Person(); p.name = "Friend \(i)"; p.cadence = 7; p.baselineConnection = Date().addingTimeInterval(-40 * 86400); return p }
    }
    func dinner(_ guests: [Person]) -> Moment {
        var event = Moment(personID: guests[0].id, date: Date().addingTimeInterval(-86400), channel: "In person", note: "Made pasta and talked about our summer trips")
        event.additionalPersonIDs = guests.dropFirst().map(\.id); event.eventTitle = "Dinner with friends"; return event
    }
    func testFiveGuestEventIsOneRecordAndRecomputesEveryHistory() throws {
        let s = store(); let friends = people(6); XCTAssertTrue(s.update { $0.people = friends })
        var event = dinner(Array(friends.prefix(5))); XCTAssertTrue(s.save(event))
        XCTAssertEqual(s.journal.moments.count, 1, "A five-person dinner must be stored once")
        for friend in friends.prefix(5) {
            XCTAssertEqual(s.journal.history(friend.id).map(\.id), [event.id], "Every guest must see the same event identity")
            XCTAssertEqual(s.journal.lastConnection(friend), event.date)
            XCTAssertFalse(s.journal.isDue(friend)); XCTAssertFalse(s.journal.rankedSuggestions().contains { $0.id == friend.id })
        }
        XCTAssertTrue(s.journal.isDue(friends[5])); XCTAssertTrue(s.journal.history(friends[5].id).isEmpty)
        XCTAssertEqual(store().journal, s.journal)
        let restored = store("restored.json"); XCTAssertTrue(restored.restore(try s.exportData())); XCTAssertEqual(restored.journal, s.journal)
        XCTAssertTrue(s.exportText().contains("Dinner with friends")); XCTAssertTrue(s.exportText().contains("With: Friend 0, Friend 1, Friend 2, Friend 3, Friend 4"))
        event.additionalPersonIDs = Array(friends[1..<4]).map(\.id); event.note = "Updated dinner memory"; XCTAssertTrue(s.save(event))
        XCTAssertEqual(s.journal.moments.count, 1); XCTAssertTrue(s.journal.history(friends[4].id).isEmpty)
        XCTAssertEqual(s.journal.lastConnection(friends[4]), friends[4].baselineConnection, "Removing a guest must recompute that guest's actual connection")
        s.deletePerson(friends[0].id)
        XCTAssertEqual(s.journal.moments.first?.id, event.id, "Removing a person must preserve other guests' shared event")
        XCTAssertEqual(s.journal.moments.first?.personID, friends[1].id)
        XCTAssertEqual(s.journal.moments.first?.note, "Updated dinner memory")
        s.deleteMoment(event.id)
        for friend in friends[1..<4] { XCTAssertTrue(s.journal.history(friend.id).isEmpty); XCTAssertEqual(s.journal.lastConnection(friend), friend.baselineConnection) }
    }
    func testGroupValidationAndFailedSaveAreAtomic() throws {
        let s = store(); let friends = people(); XCTAssertTrue(s.update { $0.people = friends }); let before = s.journal
        var malformed = dinner(friends); malformed.additionalPersonIDs = [friends[0].id]
        XCTAssertFalse(s.save(malformed)); XCTAssertEqual(s.journal, before)
        malformed.additionalPersonIDs = [UUID()]; XCTAssertFalse(s.save(malformed)); XCTAssertEqual(s.journal, before)
        let disk = try Data(contentsOf: s.file)
        try FileManager.default.removeItem(at: s.file); try FileManager.default.createDirectory(at: s.file, withIntermediateDirectories: false)
        XCTAssertFalse(s.save(dinner(friends)), "An unwritable event must not publish any attendee connection")
        XCTAssertEqual(s.journal, before); XCTAssertNil(s.recentMomentID)
        try FileManager.default.removeItem(at: s.file); try disk.write(to: s.file)
        XCTAssertEqual(store().journal, before)
    }
    func testBuild1007UpgradeKeepsImportsAndRecoveryBytes() throws {
        let url = try XCTUnwrap(Bundle(for: WorkflowTests.self).url(forResource: "journal-build-1007", withExtension: "json"))
        let bytes = try Data(contentsOf: url); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bytes.write(to: root.appendingPathComponent("journal.json"))
        let previous = try JournalStore.readJournal(bytes); let s = store()
        XCTAssertFalse(s.locked); XCTAssertEqual(s.journal, previous); XCTAssertNil(s.journal.workflowVersion)
        XCTAssertEqual(try Data(contentsOf: s.file), bytes, "Opening build 1007 must not rewrite its journal")
        XCTAssertTrue(s.save(dinner(s.journal.people)))
        XCTAssertEqual(s.journal.people, previous.people); XCTAssertEqual(s.journal.preferences, previous.preferences)
        XCTAssertEqual(s.journal.moments.first, previous.moments.first)
        XCTAssertEqual(try Data(contentsOf: s.beforeWorkflowUpdate), bytes, "First edit must preserve exact pre-workflow recovery bytes")
        XCTAssertTrue(s.setRhythm([s.journal.people[2].id], cadence: 14, anchor: .today))
        XCTAssertEqual(try Data(contentsOf: s.beforeWorkflowUpdate), bytes, "Later saves cannot replace the before-update recovery point")
        XCTAssertEqual(store().journal, s.journal)
        let restored = store("backup.json"); XCTAssertTrue(restored.restore(try s.exportData())); XCTAssertEqual(restored.journal, s.journal)
    }
    func testRhythmSetupRequiresChoiceAndUndoPreservesOtherEdits() throws {
        let s = store(); var friends = people(3); friends[0].cadence = 0; friends[0].baselineConnection = nil
        friends[1].cadence = 0; friends[1].baselineConnection = nil
        XCTAssertTrue(s.update { $0.people = friends }); let before = s.journal
        XCTAssertFalse(s.setRhythm([], cadence: 7, anchor: .today)); XCTAssertFalse(s.setRhythm([friends[0].id], cadence: 0, anchor: .today))
        XCTAssertFalse(s.setRhythm(Set(friends.map(\.id)), cadence: 14, anchor: .today), "Existing rhythms must require explicit inclusion")
        XCTAssertEqual(s.journal, before)
        XCTAssertTrue(s.setRhythm([friends[0].id, friends[1].id], cadence: 14, anchor: .today))
        XCTAssertEqual(s.journal.people.map(\.cadence), [14,14,7]); XCTAssertTrue(s.journal.moments.isEmpty)
        XCTAssertNil(s.journal.lastConnection(s.journal.people[0]), "Starting a rhythm must never invent contact")
        XCTAssertNotNil(s.journal.people[0].reminderStart)
        XCTAssertTrue(s.update { $0.people[0].notes.append(Memory(text: "A newer memory")) })
        XCTAssertTrue(s.undoRhythm()); XCTAssertEqual(s.journal.people.map(\.cadence), [0,0,7]); XCTAssertEqual(s.journal.people[0].notes.first?.text, "A newer memory")
        let date = Date().addingTimeInterval(-10*86400)
        XCTAssertTrue(s.setRhythm([friends[0].id], cadence: 21, anchor: .approximate(date)))
        XCTAssertEqual(s.journal.people[0].baselineConnection, date); XCTAssertTrue(s.journal.people[0].baselineApproximate)
        XCTAssertTrue(s.update { $0.people[0].cadence = 30 }); XCTAssertFalse(s.undoRhythm(), "Undo must not overwrite a newer rhythm")
        XCTAssertEqual(s.journal.people[0].cadence, 30)
    }
    func testRhythmUndoAndSetupFailureDoNotPublishOrConsumeReceipt() throws {
        let s = store(); var friend = people(1)[0]; friend.cadence = 0; friend.baselineConnection = nil; XCTAssertTrue(s.save(friend))
        XCTAssertTrue(s.setRhythm([friend.id], cadence: 14, anchor: .today)); let before = s.journal; XCTAssertNotNil(s.rhythmUndo)
        let bytes = try Data(contentsOf: s.file); try FileManager.default.removeItem(at: s.file); try FileManager.default.createDirectory(at: s.file, withIntermediateDirectories: false)
        XCTAssertFalse(s.undoRhythm()); XCTAssertEqual(s.journal, before); XCTAssertNotNil(s.rhythmUndo)
        XCTAssertFalse(s.setRhythm([friend.id], cadence: 30, anchor: .today, replaceExisting: true)); XCTAssertEqual(s.journal, before)
        try FileManager.default.removeItem(at: s.file); try bytes.write(to: s.file)
        XCTAssertTrue(s.undoRhythm()); XCTAssertEqual(s.journal.people[0].cadence, 0)
        XCTAssertTrue(s.setRhythm([friend.id], cadence: 7, anchor: .today)); XCTAssertTrue(s.restore(try s.exportData())); XCTAssertNil(s.rhythmUndo)
    }
    func testHandoffSurvivesReopenAndRequiresExactlyOneConfirmedSave() throws {
        let s = store(); let friend = people(1)[0]; XCTAssertTrue(s.save(friend)); let old = s.journal.lastConnection(friend)
        let draft = try XCTUnwrap(s.beginContact(personID: friend.id, channel: "Messages"))
        XCTAssertTrue(s.journal.moments.isEmpty); XCTAssertEqual(s.journal.lastConnection(friend), old)
        let reopened = store(); XCTAssertEqual(reopened.journal.pendingContact, draft)
        var lifecycle = ContactReturnState()
        XCTAssertNil(lifecycle.returned(draft: draft), "Foreground entry alone is not proof of departure or contact")
        lifecycle.departed(draft: draft); XCTAssertEqual(lifecycle.returned(draft: draft), draft); XCTAssertNil(lifecycle.returned(draft: draft))
        let outreach = Moment(personID: friend.id, channel: "Messages", connected: false)
        XCTAssertTrue(reopened.save(outreach, completingHandoff: draft.id)); XCTAssertNil(reopened.journal.pendingContact)
        XCTAssertEqual(reopened.journal.lastConnection(friend), old); XCTAssertEqual(reopened.journal.moments.count, 1)
        XCTAssertFalse(reopened.save(Moment(personID: friend.id), completingHandoff: draft.id), "A handled draft cannot append another moment")
        XCTAssertEqual(reopened.journal.moments.count, 1)
        let second = try XCTUnwrap(reopened.beginContact(personID: friend.id, channel: "Call"))
        XCTAssertTrue(reopened.dismissContact(second.id)); XCTAssertNil(store().journal.pendingContact); XCTAssertEqual(store().journal.moments.count, 1)
        XCTAssertTrue(reopened.dismissContact(draft.id)); XCTAssertEqual(reopened.journal.moments.count, 1)
    }
    func testThreadsResolveAndPostponeWithoutChangingMemoryOrConnection() throws {
        let s = store(); var friend = people(1)[0]; let note = Memory(text: "Ask about the exhibition", pinned: true, followUp: Date())
        friend.notes = [note]; XCTAssertTrue(s.save(friend)); let original = s.journal.lastConnection(friend)
        let later = Date().addingTimeInterval(3*86400)
        XCTAssertTrue(s.updateThread(personID: friend.id, noteID: note.id, followUp: later)); XCTAssertEqual(s.journal.people[0].notes[0].followUp, later)
        XCTAssertTrue(s.updateThread(personID: friend.id, noteID: note.id, followUp: nil, unpin: true))
        let saved = s.journal.people[0].notes[0]; XCTAssertEqual(saved.text, note.text); XCTAssertEqual(saved.date, note.date); XCTAssertFalse(saved.pinned); XCTAssertNil(saved.followUp)
        XCTAssertEqual(s.journal.lastConnection(friend), original); XCTAssertTrue(s.journal.moments.isEmpty)
        XCTAssertEqual(store().journal.people[0].notes[0], saved)
    }
    func testRhythmUndoOnlyRestoresFieldsItChanged() throws {
        let s = store(); let friend = people(1)[0]; XCTAssertTrue(s.save(friend))
        XCTAssertTrue(s.setRhythm([friend.id], cadence: 14, anchor: .today, replaceExisting: true))
        let correctedDate = Date().addingTimeInterval(-5 * 86400)
        XCTAssertTrue(s.update { $0.people[0].baselineConnection = correctedDate; $0.people[0].intention = "A newer context" })
        XCTAssertTrue(s.undoRhythm(), "An unrelated date correction must not block cadence-only Undo")
        XCTAssertEqual(s.journal.people[0].cadence, 7); XCTAssertEqual(s.journal.people[0].baselineConnection, correctedDate); XCTAssertEqual(s.journal.people[0].intention, "A newer context")
    }
    func testFailedHandoffConfirmationRetainsDraftAndNoMoment() throws {
        let s = store(); let friend = people(1)[0]; XCTAssertTrue(s.save(friend))
        let draft = try XCTUnwrap(s.beginContact(personID: friend.id, channel: "Call")); let before = s.journal
        let bytes = try Data(contentsOf: s.file); try FileManager.default.removeItem(at: s.file); try FileManager.default.createDirectory(at: s.file, withIntermediateDirectories: false)
        XCTAssertFalse(s.save(Moment(personID: friend.id), completingHandoff: draft.id)); XCTAssertEqual(s.journal, before); XCTAssertNil(s.recentMomentID)
        try FileManager.default.removeItem(at: s.file); try bytes.write(to: s.file)
        XCTAssertEqual(store().journal.pendingContact, draft)
        XCTAssertTrue(s.save(Moment(personID: friend.id), completingHandoff: draft.id)); XCTAssertNil(store().journal.pendingContact); XCTAssertEqual(store().journal.moments.count, 1)
    }
    func testOvernightDraftUsesOriginalDateForEitherConfirmedOutcome() throws {
        for connected in [true, false] {
            let s = store(connected ? "connected.json" : "outreach.json"); let friend = people(1)[0]; XCTAssertTrue(s.save(friend))
            var draft = ContactDraft(personID: friend.id, channel: "Messages"); draft.date = Date().addingTimeInterval(-2 * 86400)
            XCTAssertTrue(s.update { $0.pendingContact = draft })
            let reopened = store(connected ? "connected.json" : "outreach.json")
            let persisted = try XCTUnwrap(reopened.journal.pendingContact)
            let moment = persisted.moment(connected: connected)
            XCTAssertEqual(moment.date, draft.date, "An overnight draft must default to its original date")
            XCTAssertTrue(reopened.save(moment, completingHandoff: draft.id))
            XCTAssertEqual(reopened.journal.moments.first?.date, draft.date)
            XCTAssertEqual(reopened.journal.moments.first?.connected, connected)
        }
    }
    func testUnchangedRhythmDoesNotPretendToReplaceEarlierUndo() throws {
        let s = store(); var friends = people(2); friends[0].cadence = 0; friends[1].cadence = 14
        XCTAssertTrue(s.update { $0.people = friends })
        XCTAssertTrue(s.setRhythm([friends[0].id], cadence: 14, anchor: .today))
        let before = s.journal; let bytes = try Data(contentsOf: s.file)
        XCTAssertFalse(s.setRhythm([friends[1].id], cadence: 14, anchor: .today, replaceExisting: true), "An unchanged batch must not report a new save")
        XCTAssertEqual(s.journal, before); XCTAssertEqual(try Data(contentsOf: s.file), bytes)
        XCTAssertEqual(s.rhythmUndo?.changes.map(\.personID), [friends[0].id])
        XCTAssertTrue(s.undoRhythm()); XCTAssertEqual(s.journal.people.map(\.cadence), [0,14])
    }
    func testContactRoutesPreferUserChoiceAndKeepAddressesDistinct() {
        var friend = Person(); friend.name = "Friend"; friend.preferredMethod = "Email"; friend.phones = ["+1 (555) 123", "+1 (555) 456", "+1 (555) 123"]; friend.emails = ["friend@example.invalid"]
        let routes = ContactRoute.options(friend)
        XCTAssertEqual(routes.first?.method, "Email"); XCTAssertEqual(Set(routes.map(\.id)).count, routes.count)
        XCTAssertEqual(routes.filter { $0.method == "Call" }.map(\.address).count, 2)
        XCTAssertEqual(routes.first { $0.method == "Call" }?.url?.scheme, "tel")
        friend.phones = []; friend.emails = []; XCTAssertTrue(ContactRoute.options(friend).isEmpty)
    }
}
