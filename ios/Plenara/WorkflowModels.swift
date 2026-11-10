import Foundation

struct ContactDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    let personID: UUID
    let channel: String
    var date = Date()
    func moment(connected: Bool) -> Moment { Moment(personID: personID, date: date, channel: channel, connected: connected) }
}

// Scene lifecycle is evidence only that the user left/returned, never of contact.
struct ContactReturnState {
    private var departedID: UUID?
    mutating func departed(draft: ContactDraft?) { departedID = draft?.id }
    mutating func returned(draft: ContactDraft?) -> ContactDraft? {
        defer { departedID = nil }
        return draft?.id == departedID ? draft : nil
    }
}

enum RhythmAnchor {
    case today
    case approximate(Date)
}
struct RhythmState: Equatable {
    var cadence: Int
    var baseline: Date?
    var approximate: Bool
    var start: Date?
    init(_ person: Person) { cadence = person.cadence; baseline = person.baselineConnection; approximate = person.baselineApproximate; start = person.reminderStart }
}
struct RhythmEdit {
    let personID: UUID
    let before: RhythmState
    let after: RhythmState
    func canUndo(_ person: Person) -> Bool {
        let current = RhythmState(person)
        return (before.cadence == after.cadence || current.cadence == after.cadence) &&
            (before.baseline == after.baseline || current.baseline == after.baseline) &&
            (before.approximate == after.approximate || current.approximate == after.approximate) &&
            (before.start == after.start || current.start == after.start)
    }
    func undo(on person: inout Person) {
        if before.cadence != after.cadence { person.cadence = before.cadence }
        if before.baseline != after.baseline { person.baselineConnection = before.baseline }
        if before.approximate != after.approximate { person.baselineApproximate = before.approximate }
        if before.start != after.start { person.reminderStart = before.start }
    }
}
struct RhythmReceipt {
    let changes: [RhythmEdit]
}

struct ContactRoute: Identifiable, Equatable {
    let method: String
    let address: String
    let scheme: String
    let channel: String
    var id: String { method + ":" + address }
    var label: String { method + " " + address }
    var url: URL? {
        let value = scheme == "mailto" ? address : address.filter { $0.isNumber || $0 == "+" }
        guard !value.isEmpty, let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(scheme):\(encoded)")
    }
    static func options(_ person: Person) -> [ContactRoute] {
        var result: [ContactRoute] = []
        let methods = [("Message", "sms", "Messages"), ("Call", "tel", "Call"), ("FaceTime", "facetime", "Video call"), ("Voice note", "sms", "Voice notes")]
        var used = Set<String>()
        for phone in person.phones where !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for (method, scheme, channel) in methods {
                let route = ContactRoute(method: method, address: phone, scheme: scheme, channel: channel)
                if used.insert(route.id).inserted { result.append(route) }
            }
        }
        for email in person.emails where !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let route = ContactRoute(method: "Email", address: email, scheme: "mailto", channel: "Email")
            if used.insert(route.id).inserted { result.append(route) }
        }
        return result.sorted { left, right in
            if (left.method == person.preferredMethod) != (right.method == person.preferredMethod) { return left.method == person.preferredMethod }
            return left.label.localizedStandardCompare(right.label) == .orderedAscending
        }
    }
}
