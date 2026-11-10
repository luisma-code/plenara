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
    // These two v1 fields are retained for backward-compatible backup decoding.
    // Active classification uses connectionKinds and directionChoice below.
    var deepen = false
    var connections: [String]?
    var direction: String?
    var feeling: String?
    var previousCloseness: String?
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
    static let connectionOptions = ["Family", "Friend"]
    static let closenessOptions = ["Not set", "Inner circle", "Close", "Casual"]
    static let distanceOptions = ["Not set", "Nearby", "Far away"]
    static let directionOptions = ["Not set", "Keep it steady", "Grow closer"]
    static let feelingOptions = ["Not set", "Feels good", "Needs care"]
    var connectionKinds: [String] {
        get { connections ?? (Self.connectionOptions.contains(relationship) ? [relationship] : []) }
        set { connections = Self.connectionOptions.filter { newValue.contains($0) }; relationship = connections?.first ?? "Not set" }
    }
    var directionChoice: String {
        get { direction ?? (deepen ? "Grow closer" : "Not set") }
        set { direction = newValue; deepen = newValue == "Grow closer" }
    }
    var feelingChoice: String {
        get { feeling ?? "Not set" }
        set { feeling = newValue }
    }
    var wantsToGrow: Bool { directionChoice == "Grow closer" }
    mutating func migrateRelationshipFields() {
        if connections == nil { connectionKinds = Self.connectionOptions.contains(relationship) ? [relationship] : [] }
        if direction == nil { directionChoice = deepen ? "Grow closer" : "Not set" }
        if feeling == nil { feelingChoice = "Not set" }
        if distance == "Local" { distance = "Nearby" }
        if closeness == "Getting to know" || closeness == "Acquaintance" {
            previousCloseness = previousCloseness ?? closeness
            // A relationship stage does not establish how close someone feels.
            closeness = closeness == "Acquaintance" ? "Casual" : "Not set"
        }
    }
    static func suggestedCadence(_ closeness: String, deepen: Bool) -> Int {
        switch closeness { case "Inner circle": return deepen ? 3 : 7; case "Close": return deepen ? 14 : 30; case "Casual": return deepen ? 30 : 90; default: return 0 }
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
    // Keep the original owner key so every old journal remains readable.
    // One shared record, never one duplicated moment per guest.
    var additionalPersonIDs: [UUID]?
    var eventTitle: String?
    var participantIDs: [UUID] { [personID] + (additionalPersonIDs ?? []) }
    var isSocialEvent: Bool { eventTitle != nil || !(additionalPersonIDs ?? []).isEmpty }
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
    var workflowVersion: Int? = 1
    var pendingContact: ContactDraft?
    var people: [Person] = []
    var moments: [Moment] = []
    var preferences = Preferences()
    mutating func migrateRelationshipFields() {
        for i in people.indices { people[i].migrateRelationshipFields() }
    }
    func lastConnection(_ p: Person) -> Date? {
        ([p.baselineConnection].compactMap { $0 } + moments.filter { $0.participantIDs.contains(p.id) && $0.connected }.map(\.date)).max()
    }
    func lastOutreach(_ p: Person) -> Date? { moments.filter { $0.participantIDs.contains(p.id) && !$0.connected }.map(\.date).max() }
    func daysSince(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)
    }
    // Shared suppression for due reminders and optional growth/care invitations.
    private func invitationAllowed(_ p: Person, connection: Date?, outreach: Date?, now: Date, calendar: Calendar) -> Bool {
        guard !p.paused, !(p.snoozeUntil.map { $0 > now } ?? false) else { return false }
        return !(outreach.map { $0 > (connection ?? .distantPast) && daysSince($0, now: now, calendar: calendar) < 7 } ?? false)
    }
    func isDue(_ p: Person, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let connection = lastConnection(p)
        guard p.cadence > 0, let anchor = connection ?? p.reminderStart,
              invitationAllowed(p, connection: connection, outreach: lastOutreach(p), now: now, calendar: calendar) else { return false }
        return daysSince(anchor, now: now, calendar: calendar) >= p.cadence
    }
    private func momentDates() -> (connections: [UUID: Date], outreach: [UUID: Date]) {
        var connections: [UUID: Date] = [:], outreach: [UUID: Date] = [:]
        for moment in moments {
            for id in moment.participantIDs {
                if moment.connected { connections[id] = connections[id].map { max($0, moment.date) } ?? moment.date }
                else { outreach[id] = outreach[id].map { max($0, moment.date) } ?? moment.date }
            }
        }
        return (connections, outreach)
    }
    func rankedSuggestions(now: Date = Date(), calendar: Calendar = .current) -> [Person] {
        let dates = momentDates()
        // Index moments once, rather than rescan all history during every sort comparison.
        let candidates = people.compactMap { p -> (person: Person, elapsed: Int)? in
            let connection = [p.baselineConnection, dates.connections[p.id]].compactMap { $0 }.max()
            guard p.cadence > 0, let anchor = connection ?? p.reminderStart,
                  invitationAllowed(p, connection: connection, outreach: dates.outreach[p.id], now: now, calendar: calendar) else { return nil }
            let elapsed = daysSince(anchor, now: now, calendar: calendar)
            return elapsed >= p.cadence ? (p, elapsed) : nil
        }
        let tiers = ["Inner circle": 0, "Close": 1, "Casual": 2, "Not set": 3]
        return candidates.sorted { left, right in
            let l = left.person, r = right.person
            if (l.closeness == "Inner circle") != (r.closeness == "Inner circle") { return l.closeness == "Inner circle" }
            let ratioL = Double(left.elapsed) / Double(l.cadence), ratioR = Double(right.elapsed) / Double(r.cadence)
            if ratioL != ratioR { return ratioL > ratioR }
            if tiers[l.closeness] != tiers[r.closeness] { return (tiers[l.closeness] ?? 3) < (tiers[r.closeness] ?? 3) }
            if l.wantsToGrow != r.wantsToGrow { return l.wantsToGrow }
            return l.id.uuidString < r.id.uuidString
        }.map(\.person)
    }
    func suggestions(now: Date = Date(), calendar: Calendar = .current) -> [Person] {
        Array(rankedSuggestions(now: now, calendar: calendar).prefix(3))
    }
    func contextualSuggestions(excluding ids: Set<UUID>, ranked: [Person], now: Date = Date(), calendar: Calendar = .current) -> (growth: Person?, care: [Person]) {
        let dates = momentDates()
        let allowed = people.filter { p in
            let connection = [p.baselineConnection, dates.connections[p.id]].compactMap { $0 }.max()
            return !ids.contains(p.id) && invitationAllowed(p, connection: connection, outreach: dates.outreach[p.id], now: now, calendar: calendar)
        }.sorted { l, r in
            let order = l.name.localizedStandardCompare(r.name)
            return order == .orderedSame ? l.id.uuidString < r.id.uuidString : order == .orderedAscending
        }
        let growers = allowed.filter(\.wantsToGrow)
        let growIDs = Set(growers.map(\.id))
        let growth = ranked.first { growIDs.contains($0.id) } ?? growers.first
        return (growth, allowed.filter { $0.feelingChoice == "Needs care" && $0.id != growth?.id })
    }
    func history(_ id: UUID? = nil) -> [Moment] { moments.filter { id.map($0.participantIDs.contains) ?? true }.sorted { $0.date > $1.date } }
    func participantNames(_ moment: Moment, excluding id: UUID? = nil) -> String {
        moment.participantIDs.filter { $0 != id }.compactMap { guest in people.first { $0.id == guest }?.name }.joined(separator: ", ")
    }
    func validate() throws {
        let personIDs = Set(people.map(\.id))
        let noteIDs = people.flatMap { $0.notes.map(\.id) }
        guard Set(noteIDs).count == noteIDs.count,
              schemaVersion == 1, (workflowVersion == nil || workflowVersion == 1), people.count <= 10000, moments.count <= 200000,
              personIDs.count == people.count, Set(moments.map(\.id)).count == moments.count,
              people.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (0...3650).contains($0.cadence) && (0...12).contains($0.birthdayMonth) && (0...31).contains($0.birthdayDay) && ($0.timeZone.isEmpty || TimeZone(identifier: $0.timeZone) != nil) &&
                  Set($0.connectionKinds).isSubset(of: Set(Person.connectionOptions)) &&
                  Person.closenessOptions.contains($0.closeness) && Person.distanceOptions.contains($0.distance) &&
                  Person.directionOptions.contains($0.directionChoice) && Person.feelingOptions.contains($0.feelingChoice) }),
              moments.allSatisfy({ m in Set(m.participantIDs).count == m.participantIDs.count && Set(m.participantIDs).isSubset(of: personIDs) && m.date <= Date().addingTimeInterval(60) }),
              pendingContact.map({ personIDs.contains($0.personID) && Moment.channels.contains($0.channel) }) ?? true,
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


struct PeopleFilter: Equatable {
    var connection = "Everyone"
    var distance = "Everyone"
    var closeness = "Everyone"
    var direction = "Everyone"
    var feeling = "Everyone"
    var isActive: Bool { [connection, distance, closeness, direction, feeling].contains { $0 != "Everyone" } }
    func includes(_ p: Person) -> Bool {
        (connection == "Everyone" || (connection == "Not set" ? p.connectionKinds.isEmpty : p.connectionKinds.contains(connection))) &&
        (distance == "Everyone" || p.distance == distance) &&
        (closeness == "Everyone" || p.closeness == closeness) &&
        (direction == "Everyone" || p.directionChoice == direction) &&
        (feeling == "Everyone" || p.feelingChoice == feeling)
    }
}
