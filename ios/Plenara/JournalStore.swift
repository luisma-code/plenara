import Foundation
import Combine
import OSLog

@MainActor final class JournalStore: ObservableObject {
    @Published private(set) var journal: Journal
    @Published var errorMessage: String?
    @Published private(set) var locked = false
    @Published private(set) var organizationUndo: OrganizationReceipt?
    @Published private(set) var rhythmUndo: RhythmReceipt?
    @Published var recentMomentID: UUID?
    let file: URL
    let log = Logger(subsystem: "com.plenara.plenaraApp", category: "journal")
    // Foundation reference-date numbers round-trip subsecond dates losslessly.
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .deferredToDate; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate; return d }()
    var beforeRelationshipUpdate: URL { file.appendingPathExtension("before-relationship-update") }
    var beforeWorkflowUpdate: URL { file.appendingPathExtension("before-workflow-update") }
    static func readJournal(_ bytes: Data) throws -> Journal {
        var loaded = try decoder.decode(Journal.self, from: bytes)
        loaded.migrateRelationshipFields()
        try loaded.validate()
        return loaded
    }
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RelationshipJournal/journal-v1.json")
        journal = Journal()
        if FileManager.default.fileExists(atPath: self.file.path) {
            do { journal = try Self.readJournal(Data(contentsOf: self.file)) }
            catch { locked = true; errorMessage = "Your saved journal could not be opened. It has been left untouched. You can restore a backup in Settings. \(error.localizedDescription)" }
        }
        log.notice("Journal opened; read-only: \(self.locked)")
    }
    @discardableResult func update(_ change: (inout Journal) -> Void) -> Bool {
        guard !locked else { errorMessage = "The saved journal is protected after a read error. Restore a valid backup in Settings before making changes."; return false }
        var candidate = journal; change(&candidate)
        return persist(candidate)
    }
    @discardableResult private func persist(_ input: Journal) -> Bool {
        var candidate = input; candidate.migrateRelationshipFields(); candidate.workflowVersion = 1
        do {
            try candidate.validate()
            let bytes = try Self.encoder.encode(candidate)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !locked && FileManager.default.fileExists(atPath: file.path) {
                let old = try Data(contentsOf: file)
                if !FileManager.default.fileExists(atPath: beforeWorkflowUpdate.path),
                   let previous = try? Self.readJournal(old), previous.workflowVersion == nil {
                    try old.write(to: beforeWorkflowUpdate, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                if !FileManager.default.fileExists(atPath: beforeRelationshipUpdate.path),
                   let legacy = try? Self.decoder.decode(Journal.self, from: old), let upgraded = try? Self.readJournal(old), legacy != upgraded {
                    try old.write(to: beforeRelationshipUpdate, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                try old.write(to: file.appendingPathExtension("previous"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            journal = candidate; locked = false; errorMessage = nil
            log.notice("Journal committed")
            return true
        } catch { errorMessage = "Couldn’t save your changes. Your previous journal is safe. \(error.localizedDescription)"; log.error("Journal save failed"); return false }
    }
    @discardableResult func save(_ person: Person) -> Bool {
        update { j in if let i = j.people.firstIndex(where: { $0.id == person.id }) { j.people[i] = person } else { j.people.append(person) } }
    }
    @discardableResult func save(_ moment: Moment, completingHandoff id: UUID? = nil) -> Bool {
        if let id {
            guard journal.pendingContact?.id == id, journal.pendingContact?.personID == moment.personID, moment.participantIDs.count == 1 else {
                errorMessage = "This reach-out draft has already been handled. Nothing else was recorded."; return false
            }
        }
        let isNew = !journal.moments.contains { $0.id == moment.id }
        let saved = update { j in
            if let i = j.moments.firstIndex(where: { $0.id == moment.id }) { j.moments[i] = moment } else { j.moments.append(moment) }
            if id != nil { j.pendingContact = nil }
        }
        if saved && isNew { recentMomentID = moment.id }
        return saved
    }
    func deletePerson(_ id: UUID) {
        if update({ j in
            j.people.removeAll { $0.id == id }
            j.moments = j.moments.compactMap { moment in
                guard moment.participantIDs.contains(id) else { return moment }
                let remaining = moment.participantIDs.filter { $0 != id }
                guard let first = remaining.first else { return nil }
                var changed = moment; changed.personID = first
                changed.additionalPersonIDs = remaining.count > 1 ? Array(remaining.dropFirst()) : nil
                return changed
            }
            if j.pendingContact?.personID == id { j.pendingContact = nil }
        }), !journal.moments.contains(where: { $0.id == recentMomentID }) { recentMomentID = nil }
    }
    func deleteMoment(_ id: UUID) { if update({ $0.moments.removeAll { $0.id == id } }), recentMomentID == id { recentMomentID = nil } }
    func restore(_ bytes: Data) -> Bool {
        do { let loaded = try Self.readJournal(bytes); if persist(loaded) { organizationUndo = nil; rhythmUndo = nil; recentMomentID = nil; return true }; return false }
        catch { errorMessage = "Couldn’t restore this backup. Nothing was replaced. \(error.localizedDescription)"; return false }
    }
    @discardableResult func beginContact(personID: UUID, channel: String) -> ContactDraft? {
        guard journal.pendingContact == nil else { errorMessage = "Review or dismiss your earlier reach-out draft first. Nothing new was recorded."; return nil }
        guard journal.people.contains(where: { $0.id == personID }), Moment.channels.contains(channel) else { return nil }
        let draft = ContactDraft(personID: personID, channel: channel)
        return update({ $0.pendingContact = draft }) ? draft : nil
    }
    @discardableResult func dismissContact(_ id: UUID) -> Bool {
        guard journal.pendingContact?.id == id else { return true }
        return update { $0.pendingContact = nil }
    }
    @discardableResult func setRhythm(_ ids: Set<UUID>, cadence: Int, anchor: RhythmAnchor, replaceExisting: Bool = false, now: Date = Date()) -> Bool {
        guard !ids.isEmpty, (1...3650).contains(cadence), ids.isSubset(of: Set(journal.people.map(\.id))),
              replaceExisting || !journal.people.contains(where: { ids.contains($0.id) && $0.cadence > 0 }) else {
            errorMessage = "Choose people and a rhythm. Include existing rhythms explicitly before replacing them."; return false
        }
        if case .approximate(let date) = anchor, date > now { errorMessage = "Choose a starting connection in the past."; return false }
        var candidate = journal; var changes: [RhythmEdit] = []
        for i in candidate.people.indices where ids.contains(candidate.people[i].id) {
            let before = RhythmState(candidate.people[i]); candidate.people[i].cadence = cadence
            if journal.lastConnection(candidate.people[i]) == nil {
                switch anchor {
                case .today: candidate.people[i].reminderStart = Calendar.current.startOfDay(for: now)
                case .approximate(let date): candidate.people[i].baselineConnection = date; candidate.people[i].baselineApproximate = true
                }
            }
            let after = RhythmState(candidate.people[i])
            if before != after { changes.append(RhythmEdit(personID: candidate.people[i].id, before: before, after: after)) }
        }
        guard !changes.isEmpty else { errorMessage = "These people already have this rhythm. Nothing was changed."; return false }
        guard update({ $0 = candidate }) else { return false }
        rhythmUndo = RhythmReceipt(changes: changes)
        return true
    }
    @discardableResult func undoRhythm() -> Bool {
        guard let receipt = rhythmUndo else { return false }
        guard receipt.changes.allSatisfy({ edit in journal.people.first(where: { $0.id == edit.personID }).map { edit.canUndo($0) } ?? false }) else {
            errorMessage = "These rhythms changed after setup. Undo would replace a newer choice, so nothing was changed."; return false
        }
        guard update({ j in for edit in receipt.changes { if let i = j.people.firstIndex(where: { $0.id == edit.personID }) { edit.undo(on: &j.people[i]) } } }) else { return false }
        rhythmUndo = nil; return true
    }
    @discardableResult func updateThread(personID: UUID, noteID: UUID, followUp: Date?, unpin: Bool = false) -> Bool {
        guard let i = journal.people.firstIndex(where: { $0.id == personID }),
              let n = journal.people[i].notes.firstIndex(where: { $0.id == noteID }) else {
            errorMessage = "This memory is no longer in the journal."; return false
        }
        return update { j in j.people[i].notes[n].followUp = followUp; if unpin { j.people[i].notes[n].pinned = false } }
    }
    // Both organizing flows use this one atomic save; only selected attributes change.
    func organize(_ ids: Set<UUID>, changes: [OrganizationField: String]) -> OrganizationReceipt? {
        guard !ids.isEmpty, !changes.isEmpty,
              ids.isSubset(of: Set(journal.people.map(\.id))),
              changes.allSatisfy({ $0.key.bulkChoices.contains($0.value) || $0.key.choices.contains($0.value) }) else {
            errorMessage = "Choose existing people and valid relationship details."; return nil
        }
        var edits: [OrganizationFieldChange] = []
        var candidate = journal
        for i in candidate.people.indices where ids.contains(candidate.people[i].id) {
            for field in OrganizationField.allCases {
                guard let choice = changes[field] else { continue }
                let before = field.value(candidate.people[i])
                field.set(choice, on: &candidate.people[i])
                let after = field.value(candidate.people[i])
                if before != after { edits.append(OrganizationFieldChange(personID: candidate.people[i].id, field: field, before: before, after: after)) }
            }
        }
        guard !edits.isEmpty else { errorMessage = nil; return nil }
        guard update({ $0 = candidate }) else { return nil }
        let receipt = OrganizationReceipt(changes: edits)
        organizationUndo = receipt
        return receipt
    }
    @discardableResult func undoOrganization() -> Bool {
        guard let receipt = organizationUndo else { return false }
        // Refuse an outdated undo rather than overwrite a newer choice or restore a removed person.
        guard receipt.changes.allSatisfy({ edit in
            journal.people.first(where: { $0.id == edit.personID }).map { edit.field.value($0) == edit.after } ?? false
        }) else { errorMessage = "These details have changed since organizing. Undo would overwrite a newer choice, so nothing was changed."; return false }
        guard update({ j in
            for edit in receipt.changes {
                if let i = j.people.firstIndex(where: { $0.id == edit.personID }) { edit.field.set(edit.before, on: &j.people[i]) }
            }
        }) else { return false }
        organizationUndo = nil
        return true
    }
    func exportData() throws -> Data { guard !locked else { throw JournalError.unreadable("The saved journal could not be opened. Restore a backup before exporting.") }; return try Self.encoder.encode(journal) }
    func exportText() -> String {
        func dateText(_ date: Date?) -> String { date?.formatted(date: .long, time: .shortened) ?? "Not set" }
        var lines = ["# Plenara relationship journal", "Exported \(Date().formatted(date: .long, time: .shortened))", ""]
        for p in journal.people.sorted(by: { $0.name < $1.name }) {
            lines += ["## \(p.name)", "\(p.connectionKinds.joined(separator: " + ")) · \(p.closeness) · \(p.city) · \(p.distance)", "Contact rhythm: \(p.cadence) days; paused: \(p.paused)", "What I want: \(p.directionChoice); how it feels: \(p.feelingChoice)", "Context: \(p.intention)", "Earlier closeness description: \(p.previousCloseness ?? "None")", "Phone: \(p.phones.joined(separator: ", ")); email: \(p.emails.joined(separator: ", "))", ""]
            lines += ["Pronunciation: \(p.pronunciation)", "Relationship detail: \(p.relationshipDetail)", "Time zone: \(p.timeZone.isEmpty ? "Not set" : p.timeZone)", "Preferred way: \(p.preferredMethod)", "Birthday: \(p.birthdayMonth > 0 && p.birthdayDay > 0 ? String(format: "%02d-%02d", p.birthdayMonth, p.birthdayDay) : "Not set")", "Birthday reminder: \(p.birthdayReminder)", "Starting connection: \(dateText(p.baselineConnection)); approximate: \(p.baselineApproximate)", "Rhythm starts: \(dateText(p.reminderStart))", "Snoozed until: \(dateText(p.snoozeUntil))", ""]
            lines += p.notes.map { "- [\($0.category)] \($0.text) (\($0.date.formatted(date: .abbreviated, time: .omitted)))\($0.pinned ? " [pinned]" : "")\($0.archived ? " [archived]" : "")\($0.followUp.map { " · Follow up: \(dateText($0))" } ?? "")" }
            lines += historyText(p.id)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
    private func historyText(_ id: UUID) -> [String] { journal.history(id).map { "- \($0.date.formatted(date: .abbreviated, time: .omitted)): \($0.eventTitle.map { $0 + " · " } ?? "")\($0.channel), \($0.connected ? "Connected" : "Reached out")\($0.isSocialEvent ? "; With: \(journal.participantNames($0))" : ""). \($0.note)" } }
}
