import Foundation

enum FollowUpStatus: String, Codable, CaseIterable {
    case all, due, unknown
    var title: String {
        switch self { case .all: "All suggestions"; case .due: "Due reminders"; case .unknown: "No contact history" }
    }
}
enum FollowUpSort: String, Codable, CaseIterable {
    case priority, closest, oldest
    var title: String {
        switch self { case .priority: "Priority order"; case .closest: "Closest first"; case .oldest: "Oldest contact first" }
    }
}
struct FollowUpSelection: Codable, Equatable {
    var people = PeopleFilter()
    var status = FollowUpStatus.all
    var sort = FollowUpSort.priority
    var query = ""
    var isActive: Bool { people.isActive || status != .all || !query.isEmpty }
    var extraChoices: [String] {
        (people.connection == "Not set" ? ["Relationship not set"] : []) +
        [people.distance, people.direction, people.feeling].filter { $0 != "Everyone" } +
        (query.isEmpty ? [] : ["Name: \(query)"])
    }
    var encoded: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    init() { }
    init(saved: String) { self = saved.data(using: .utf8).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self() }
}
struct FollowUpCandidate: Identifiable, Equatable {
    let person: Person
    let connection: Date?
    let due: Bool
    let elapsed: Int?
    let duePosition: Int?
    var id: UUID { person.id }
    var closenessTier: Int { ["Inner circle": 0, "Close": 1, "Casual": 2][person.closeness] ?? 3 }
    var priorityBand: Int {
        if due && person.closeness == "Inner circle" { return 0 }
        if !due && closenessTier <= 1 { return 1 }
        if due { return 2 }
        if person.connectionKinds.contains("Family") && person.closeness == "Not set" { return 3 }
        if person.wantsToGrow || person.feelingChoice == "Needs care" { return 4 }
        return 5
    }
    var relationshipLabel: String {
        let kinds = person.connectionKinds.joined(separator: " + ")
        if person.closeness == "Not set" { return kinds.isEmpty ? "Relationship details not set" : kinds + " · Closeness not set" }
        return kinds.isEmpty ? person.closeness : kinds + " · " + person.closeness
    }
    var reason: String {
        let approximate = person.baselineApproximate && person.baselineConnection == connection
        if due {
            if let elapsed { return "Reminder due · \(approximate ? "About " : "")\(elapsed)d since contact" }
            return "Reminder due · No contact recorded"
        }
        if let elapsed { return approximate ? "Contact about \(elapsed)d ago" : "Last recorded contact: \(elapsed)d ago" }
        return "No contact recorded"
    }
}
extension Journal {
    func followUpCandidates(selection: FollowUpSelection = FollowUpSelection(), now: Date = Date(), calendar: Calendar = .current) -> [FollowUpCandidate] {
        let dates = momentDates()
        let duePositions = Dictionary(uniqueKeysWithValues: rankedSuggestions(now: now, calendar: calendar).enumerated().map { ($0.element.id, $0.offset) })
        return people.compactMap { person -> FollowUpCandidate? in
            let connection = [person.baselineConnection, dates.connections[person.id]].compactMap { $0 }.max()
            guard invitationAllowed(person, connection: connection, outreach: dates.outreach[person.id], now: now, calendar: calendar),
                  selection.people.includes(person),
                  selection.query.isEmpty || "\(person.name) \(person.city)".localizedStandardContains(selection.query) else { return nil }
            let due = duePositions[person.id] != nil
            let elapsed = connection.map { daysSince($0, now: now, calendar: calendar) }
            // A short explicitly chosen rhythm can be due within the optional invitation cooldown.
            guard due || (elapsed.map { $0 >= 7 } ?? true) else { return nil }
            guard due || connection == nil || person.cadence == 0 || person.wantsToGrow || person.feelingChoice == "Needs care" else { return nil }
            guard selection.status != .due || due, selection.status != .unknown || connection == nil else { return nil }
            return FollowUpCandidate(person: person, connection: connection, due: due, elapsed: elapsed, duePosition: duePositions[person.id])
        }.sorted { left, right in
            if selection.sort == .oldest {
                if left.connection != right.connection {
                    guard let l = left.connection else { return false }
                    guard let r = right.connection else { return true }
                    return l < r
                }
            } else if selection.sort == .closest {
                if left.closenessTier != right.closenessTier { return left.closenessTier < right.closenessTier }
                if left.due != right.due { return left.due }
            } else if left.priorityBand != right.priorityBand { return left.priorityBand < right.priorityBand }
            if let l = left.duePosition, let r = right.duePosition, l != r { return l < r }
            if left.closenessTier != right.closenessTier { return left.closenessTier < right.closenessTier }
            return left.id.uuidString < right.id.uuidString
        }
    }
}

extension Person {
    // Saving Off never starts a clock. Enabling or re-enabling reminders without
    // known contact starts today, rather than reviving an old disabled clock.
    mutating func prepareReminderSave(previous: Person, knownConnection: Date?, configuringReminders: Bool = false, now: Date = Date(), calendar: Calendar = .current) {
        if cadence == 0 { reminderStart = nil }
        else if knownConnection == nil && (previous.cadence == 0 || (reminderStart == nil && (configuringReminders || cadence != previous.cadence))) { reminderStart = calendar.startOfDay(for: now) }
    }
}
