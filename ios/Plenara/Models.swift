import Foundation

struct Person: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var pronunciation = ""
    var relationship = "Not set"
    var relationshipDetail = ""
    var closeness = "Not set"
    var city = ""
    var distance = "Not set"
    var timeZone = ""
    var deepen = false
    var intention = ""
    var cadence = 0
    var paused = false
    var snoozeUntil: Date?
    var baselineConnection: Date?
    var baselineApproximate = false
    var reminderStart: Date?
    var sourceContactID: String?
    var phones: [String] = []
    var emails: [String] = []
    var preferredMethod = "Message"
    var photo: Data?
    var birthdayMonth = 0
    var birthdayDay = 0
    var birthdayReminder = false
    var notes: [Memory] = []
    var created = Date()
    var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
    static let closenessOptions = ["Not set", "Inner circle", "Close", "Getting to know", "Acquaintance"]
    static func suggestedCadence(_ closeness: String, deepen: Bool) -> Int {
        switch closeness { case "Inner circle": return deepen ? 3 : 7; case "Close": return deepen ? 14 : 30; case "Getting to know": return deepen ? 30 : 60; case "Acquaintance": return deepen ? 30 : 90; default: return 0 }
    }
}
struct Memory: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var category = "On their mind"
    var date = Date()
    var pinned = false
    var archived = false
    var followUp: Date?
    static let categories = ["On their mind", "Good to know", "Their world", "An idea for us", "Our story", "Important date"]
}
struct Moment: Identifiable, Codable, Equatable {
    var id = UUID()
    var personID: UUID
    var date = Date()
    var channel = "Call"
    var connected = true
    var note = ""
    static let channels = ["Call", "Video call", "In person", "Messages", "Voice notes", "Email"]
}
struct Preferences: Codable, Equatable {
    var notifications = false
    var weekday = 1
    var hour = 10
    var minute = 0
    var quietStart = 21
    var quietEnd = 8
    var birthdays = false
    var followUps = false
    func allowedHour(_ hour: Int) -> Int {
        let quiet = quietStart > quietEnd ? (hour >= quietStart || hour < quietEnd) : (hour >= quietStart && hour < quietEnd)
        return quiet ? quietEnd : hour
    }
}
struct Journal: Codable, Equatable {
    var schemaVersion = 1
    var people: [Person] = []
    var moments: [Moment] = []
    var preferences = Preferences()
    func lastConnection(_ p: Person) -> Date? {
        ([p.baselineConnection].compactMap { $0 } + moments.filter { $0.personID == p.id && $0.connected }.map(\.date)).max()
    }
    func lastOutreach(_ p: Person) -> Date? { moments.filter { $0.personID == p.id && !$0.connected }.map(\.date).max() }
    func daysSince(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)
    }
    func isDue(_ p: Person, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard p.cadence > 0, !p.paused, !(p.snoozeUntil.map { $0 > now } ?? false), let anchor = lastConnection(p) ?? p.reminderStart else { return false }
        if let outreach = lastOutreach(p), outreach > (lastConnection(p) ?? .distantPast), daysSince(outreach, now: now, calendar: calendar) < 7 { return false }
        return daysSince(anchor, now: now, calendar: calendar) >= p.cadence
    }
    func suggestions(now: Date = Date(), calendar: Calendar = .current) -> [Person] {
        let eligible = people.filter { isDue($0, now: now, calendar: calendar) }.sorted {
            let l = Double(daysSince(lastConnection($0) ?? $0.reminderStart!, now: now, calendar: calendar)) / Double($0.cadence)
            let r = Double(daysSince(lastConnection($1) ?? $1.reminderStart!, now: now, calendar: calendar)) / Double($1.cadence)
            if l != r { return l > r }; if $0.deepen != $1.deepen { return $0.deepen }; return $0.id.uuidString < $1.id.uuidString
        }
        guard eligible.count > 3 else {
            if let featured = eligible.first(where: \.deepen) { return [featured] + eligible.filter { $0.id != featured.id } }; return eligible
        }
        let day = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: calendar.startOfDay(for: now)).day ?? 0
        // A rotating daily slice prevents one long gap from occupying the home forever.
        let start = abs(day) % eligible.count
        let slice = (0..<3).map { eligible[(start + $0) % eligible.count] }
        return slice.sorted { $0.deepen && !$1.deepen }
    }
    func history(_ id: UUID? = nil) -> [Moment] { moments.filter { id == nil || $0.personID == id }.sorted { $0.date > $1.date } }
    func validate() throws {
        guard schemaVersion == 1, people.count <= 10000, moments.count <= 200000,
              Set(people.map(\.id)).count == people.count, Set(moments.map(\.id)).count == moments.count,
              people.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (0...3650).contains($0.cadence) && (0...12).contains($0.birthdayMonth) && (0...31).contains($0.birthdayDay) && ($0.timeZone.isEmpty || TimeZone(identifier: $0.timeZone) != nil) }),
              moments.allSatisfy({ m in people.contains { $0.id == m.personID } && m.date <= Date().addingTimeInterval(60) }),
              (1...7).contains(preferences.weekday), (0...23).contains(preferences.hour), (0...59).contains(preferences.minute),
              (0...23).contains(preferences.quietStart), (0...23).contains(preferences.quietEnd), preferences.quietStart != preferences.quietEnd
        else { throw JournalError.invalidBackup }
    }
}
enum JournalError: LocalizedError {
    case invalidBackup, unreadable(String)
    var errorDescription: String? {
        switch self { case .invalidBackup: return "This file is not a valid Plenara relationship backup."; case .unreadable(let s): return s }
    }
}

struct DatedReminder: Identifiable {
    var id: String
    var person: Person
    var caption: String
    var text: String
    var noteID: UUID?
}
extension Journal {
    func datedReminders(now: Date = Date(), calendar: Calendar = .current) -> [DatedReminder] {
        var reminders: [DatedReminder] = []
        let month = calendar.component(.month, from: now), day = calendar.component(.day, from: now)
        for p in people.filter({ !$0.paused }).sorted(by: { $0.name < $1.name }) {
            if p.birthdayReminder && p.birthdayMonth == month && p.birthdayDay == day {
                reminders.append(DatedReminder(id: "birthday-\(p.id)", person: p, caption: "Birthday today", text: "A day for a little extra love."))
            }
            for n in p.notes.filter({ !$0.archived && $0.followUp.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: now) } == true }).sorted(by: { $0.followUp! < $1.followUp! }) {
                reminders.append(DatedReminder(id: "note-\(n.id)", person: p, caption: "A thread to pick up", text: n.text, noteID: n.id))
            }
        }
        return reminders
    }
}
