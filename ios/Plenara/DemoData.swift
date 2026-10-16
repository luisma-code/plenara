#if targetEnvironment(simulator)
import Foundation
import Contacts

enum DemoData {
    static func journal(now: Date = Date()) -> Journal {
        func ago(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now)! }
        var sofia = Person(); sofia.name = "Sofia Chen"; sofia.city = "Brooklyn, New York"; sofia.timeZone = "America/New_York"; sofia.closeness = "Close"; sofia.distance = "Far away"; sofia.directionChoice = "Grow closer"; sofia.feelingChoice = "Feels good"; sofia.cadence = 30
        sofia.notes = [Memory(text: "Her ceramics show opens in November. Ask how the pieces are coming along.", date: ago(47), pinned: true), Memory(text: "Sunday mornings are usually good for a call. Loves a long voice note.", category: "Good to know", date: ago(90)), Memory(text: "Partner: Alex. Their dog is called Miso.", category: "Their world", date: ago(90))]
        var daniel = Person(); daniel.name = "Daniel Rivera"; daniel.city = "San Francisco"; daniel.closeness = "Close"; daniel.distance = "Nearby"; daniel.cadence = 21; daniel.directionChoice = "Keep it steady"; daniel.feelingChoice = "Feels good"
        var mum = Person(); mum.name = "Mum"; mum.relationship = "Family"; mum.city = "Madrid, Spain"; mum.timeZone = "Europe/Madrid"; mum.closeness = "Inner circle"; mum.distance = "Far away"; mum.cadence = 7; mum.directionChoice = "Keep it steady"; mum.feelingChoice = "Feels good"; mum.connectionKinds = ["Family", "Friend"]
        var amara = Person(); amara.name = "Amara Okafor"; amara.city = "Oakland"; amara.closeness = "Casual"; amara.relationshipDetail = "New friend"; amara.distance = "Nearby"; amara.directionChoice = "Grow closer"; amara.feelingChoice = "Feels good"; amara.cadence = 30; amara.notes = [Memory(text: "We both want to try the bookshop café on Telegraph.", category: "An idea for us", date: ago(12))]
        var leo = Person(); leo.name = "Leo Park"; leo.city = "Seattle"; leo.distance = "Far away"; leo.closeness = "Casual"; leo.feelingChoice = "Needs care"; leo.intention = "We’ve drifted; I’d like to reconnect."; leo.cadence = 90
        var j = Journal(); j.people = [sofia, daniel, mum, amara, leo].map { p in var person = p; if person.relationship == "Not set" { person.relationship = "Friend" }; return person }
        j.moments = [Moment(personID: sofia.id, date: ago(47), channel: "Video call", note: "A proper catch-up. Sofia is making time for ceramics again."), Moment(personID: daniel.id, date: ago(26), channel: "In person", note: "Coffee after a walk in the park."), Moment(personID: mum.id, date: ago(4), note: "A slow call, and a tour of the balcony."), Moment(personID: amara.id, date: ago(12), channel: "In person", note: "Met through Maya at dinner. Talked books for an hour.")]
        if ProcessInfo.processInfo.arguments.contains("--dated-demo") {
            let i = j.people.firstIndex { $0.id == mum.id }!
            j.people[i].birthdayMonth = Calendar.current.component(.month, from: now); j.people[i].birthdayDay = Calendar.current.component(.day, from: now); j.people[i].birthdayReminder = true
            let s = j.people.firstIndex { $0.id == sofia.id }!; j.people[s].notes[0].followUp = now
        }
        return j
    }
    static func seedSystemContact() {
        let store = CNContactStore()
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }
        do {
            let matches = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: "Maya Plenara Test"), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            guard matches.isEmpty else { return }
            let c = CNMutableContact(); c.givenName = "Maya"; c.familyName = "Plenara Test"; c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+15555550123"))]
            let request = CNSaveRequest(); request.add(c, toContainerWithIdentifier: nil); try store.execute(request)
        } catch { /* Test fixture only; the picker test asserts the system contact exists. */ }
    }
}
#endif
