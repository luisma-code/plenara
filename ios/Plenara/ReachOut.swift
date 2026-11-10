import SwiftUI

struct ReachOutButton: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.openURL) private var openURL
    let person: Person
    var compact = false
    @State private var choosing = false
    @State private var selected: ContactRoute?
    @State private var unavailable = false
    var body: some View {
        ActionButton(title: compact ? "Reach out" : "Reach out to \(person.name.components(separatedBy: " ").first ?? person.name)", icon: "arrow.up.right.message") { choosing = true }
            .accessibilityIdentifier("reach-out-\(person.name)")
            .sheet(isPresented: $choosing, onDismiss: launchSelected) {
                ContactRoutesView(personID: person.id) { route in selected = route; choosing = false }
            }
            .alert("Contact method unavailable", isPresented: $unavailable) { Button("OK") { } } message: { Text("This device couldn’t open that app. Nothing was recorded. You can review the number or email in Edit.") }
    }
    private func launchSelected() {
        guard let route = selected else { return }; selected = nil
        guard let url = route.url else { unavailable = true; return }
        guard let draft = store.beginContact(personID: person.id, channel: route.channel) else { return }
        openURL(url) { accepted in
            if !accepted, store.dismissContact(draft.id) { unavailable = true }
        }
    }
}

struct ContactRoutesView: View {
    @EnvironmentObject var store: JournalStore
    let personID: UUID
    var choose: (ContactRoute) -> Void
    @State private var editing = false
    var body: some View {
        if let person = store.journal.people.first(where: { $0.id == personID }) {
            if ContactRoute.options(person).isEmpty { PersonEditor(person: person) }
            else {
                NavigationStack {
                    List {
                        let routes = ContactRoute.options(person)
                        let preferred = routes.filter { $0.method == person.preferredMethod }
                        if !preferred.isEmpty { Section("Preferred way") { ForEach(preferred) { route in routeButton(route) } } }
                        Section(preferred.isEmpty ? "Choose a way" : "Other ways") { ForEach(routes.filter { $0.method != person.preferredMethod }) { route in routeButton(route) } }
                        Section { Button("Edit contact methods") { editing = true } }
                        Section { Text("Opening another app does not record contact. When you return, you can choose what actually happened.").font(.footnote).foregroundStyle(Theme.muted) }
                    }.scrollContentBackground(.hidden).background(Theme.paper)
                        .navigationTitle("Reach out to \(person.name)").navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
                        .sheet(isPresented: $editing) { PersonEditor(person: person) }
                }
            }
        } else { NavigationStack { Text("This person is no longer in your journal.").padding().toolbar { DismissButton() } } }
    }
    private func routeButton(_ route: ContactRoute) -> some View { Button(route.label) { choose(route) }.frame(minHeight: 44).accessibilityIdentifier("contact-route-\(route.method)-\(route.address)") }
}

struct ContactReturnView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let draft: ContactDraft
    @State private var recording: Moment?
    var body: some View {
        if let recording { MomentEditor(personID: draft.personID, moment: recording, handoffID: draft.id) }
        else {
            NavigationStack {
                Form {
                    Section {
                        Text(store.journal.people.first(where: { $0.id == draft.personID })?.name ?? "Your reach-out").font(Theme.title(28))
                        Text("What happened? Nothing has been recorded yet.").foregroundStyle(Theme.muted)
                    }
                    Section {
                        Button("We connected") { recording = draft.moment(connected: true) }.accessibilityIdentifier("handoff-connected")
                        Button("I reached out") { recording = draft.moment(connected: false) }.accessibilityIdentifier("handoff-outreach")
                        Button("Nothing to record") { if store.dismissContact(draft.id) { dismiss() } }.accessibilityIdentifier("handoff-discard")
                    } footer: { Text("An unanswered message or missed call is outreach. Only a confirmed catch-up changes your connection date.") }
                }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("A little follow-through").navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
            }
        }
    }
}
