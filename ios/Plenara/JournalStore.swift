import Foundation
import Combine
import OSLog

@MainActor final class JournalStore: ObservableObject {
    @Published private(set) var journal: Journal
    @Published var errorMessage: String?
    @Published private(set) var locked = false
    let file: URL
    let log = Logger(subsystem: "com.plenara.plenaraApp", category: "journal")
    // Foundation reference-date numbers round-trip subsecond dates losslessly.
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .deferredToDate; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate; return d }()
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RelationshipJournal/journal-v1.json")
        journal = Journal()
        if FileManager.default.fileExists(atPath: self.file.path) {
            do { let loaded = try Self.decoder.decode(Journal.self, from: Data(contentsOf: self.file)); try loaded.validate(); journal = loaded }
            catch { locked = true; errorMessage = "Your saved journal could not be opened. It has been left untouched. You can restore a backup in Settings. \(error.localizedDescription)" }
        }
        log.notice("Journal opened; read-only: \(self.locked)")
    }
    @discardableResult func update(_ change: (inout Journal) -> Void) -> Bool {
        guard !locked else { errorMessage = "The saved journal is protected after a read error. Restore a valid backup in Settings before making changes."; return false }
        var candidate = journal; change(&candidate)
        return persist(candidate)
    }
    @discardableResult private func persist(_ candidate: Journal) -> Bool {
        do {
            try candidate.validate()
            let bytes = try Self.encoder.encode(candidate)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !locked && FileManager.default.fileExists(atPath: file.path) {
                let old = try Data(contentsOf: file)
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
    @discardableResult func save(_ moment: Moment) -> Bool {
        update { j in if let i = j.moments.firstIndex(where: { $0.id == moment.id }) { j.moments[i] = moment } else { j.moments.append(moment) } }
    }
    func deletePerson(_ id: UUID) { update { j in j.people.removeAll { $0.id == id }; j.moments.removeAll { $0.personID == id } } }
    func deleteMoment(_ id: UUID) { update { $0.moments.removeAll { $0.id == id } } }
    func restore(_ bytes: Data) -> Bool {
        do { guard bytes.count < 50_000_000 else { throw JournalError.invalidBackup }; let loaded = try Self.decoder.decode(Journal.self, from: bytes); try loaded.validate(); return persist(loaded) }
        catch { errorMessage = "Couldn’t restore this backup. Nothing was replaced. \(error.localizedDescription)"; return false }
    }
    func exportData() throws -> Data { guard !locked else { throw JournalError.unreadable("The saved journal could not be opened. Restore a backup before exporting.") }; return try Self.encoder.encode(journal) }
    func exportText() -> String {
        var lines = ["# Plenara relationship journal", "Exported \(Date().formatted(date: .long, time: .shortened))", ""]
        for p in journal.people.sorted(by: { $0.name < $1.name }) {
            lines += ["## \(p.name)", "\(p.relationship) · \(p.closeness) · \(p.city) · \(p.distance)", "Contact rhythm: \(p.cadence) days; paused: \(p.paused); deepen: \(p.deepen)", "Intention: \(p.intention)", "Phone: \(p.phones.joined(separator: ", ")); email: \(p.emails.joined(separator: ", "))", ""]
            lines += p.notes.map { "- [\($0.category)] \($0.text) (\($0.date.formatted(date: .abbreviated, time: .omitted)))\($0.archived ? " [archived]" : "")" }
            lines += historyText(p.id)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
    private func historyText(_ id: UUID) -> [String] { journal.history(id).map { "- \($0.date.formatted(date: .abbreviated, time: .omitted)): \($0.channel), \($0.connected ? "Connected" : "Reached out"). \($0.note)" } }
}
