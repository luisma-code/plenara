import SwiftUI

struct SocialEventEditor: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var moment: Moment
    @State private var guests: Set<UUID>
    @State private var title: String
    @State private var choosingPeople = false
    @State private var deleting = false
    init(moment: Moment? = nil, personID: UUID? = nil) {
        let value = moment ?? Moment(personID: personID ?? UUID(), channel: "In person")
        _moment = State(initialValue: value)
        _guests = State(initialValue: moment.map { Set($0.participantIDs) } ?? personID.map { [$0] } ?? [])
        _title = State(initialValue: value.eventTitle ?? "")
    }
    var existing: Bool { store.journal.moments.contains { $0.id == moment.id } }
    var selectedPeople: [Person] { store.journal.people.filter { guests.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event name (optional)", text: $title, prompt: Text("Dinner, a walk, a celebration…").foregroundStyle(Theme.muted)).accessibilityIdentifier("event-title")
                    Button { choosingPeople = true } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(guests.isEmpty ? "Choose people" : "\(guests.count) \(guests.count == 1 ? "person" : "people") included", systemImage: "person.3")
                            if !selectedPeople.isEmpty { Text(selectedPeople.map(\.name).joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.muted) }
                        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }.accessibilityIdentifier("event-people")
                } header: { Text("Time together") } footer: { Text("Choose everyone who was there. This is one shared event in each person’s history.") }
                Section("What did you do?") {
                    TextField("A few things to remember", text: $moment.note, prompt: Text("A few things to remember").foregroundStyle(Theme.muted), axis: .vertical).lineLimit(4...10).accessibilityIdentifier("event-note")
                    DatePicker("When?", selection: $moment.date, in: ...Date(), displayedComponents: .date)
                    Picker("How did you get together?", selection: $moment.channel) { ForEach(Moment.channels, id: \.self) { Text($0) } }
                }
                Section { Text("Saving counts as a connection with each person included. Editing this event updates the same record everywhere.").font(.footnote).foregroundStyle(Theme.muted) }
                if existing { Section { Button("Delete social event", role: .destructive) { deleting = true } } }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Theme.paper)
                .navigationTitle(existing ? "Edit social event" : "Log a social event").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(.automatic).disabled(guests.isEmpty).opacity(guests.isEmpty ? 0.4 : 1).accessibilityIdentifier("save-event") }
                }
                .sheet(isPresented: $choosingPeople) { EventPeoplePicker(selection: $guests) }
                .confirmationDialog("Delete this shared event?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete social event", role: .destructive) { store.deleteMoment(moment.id); if store.errorMessage == nil { dismiss() } }
                    Button("Cancel", role: .cancel) { }
                } message: { Text("It will be removed from every attendee’s history. Connection dates will be recalculated from the remaining moments.") }
        }
    }
    private func save() {
        guard let first = selectedPeople.first else { return }
        let primary = guests.contains(moment.personID) ? moment.personID : first.id
        moment.personID = primary
        moment.additionalPersonIDs = selectedPeople.map(\.id).filter { $0 != primary }
        moment.eventTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Time together" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        moment.note = moment.note.trimmingCharacters(in: .whitespacesAndNewlines)
        moment.connected = true
        if store.save(moment) { dismiss() }
    }
}

struct EventPeoplePicker: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    @State private var query = ""
    var people: [Person] { store.journal.people.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var body: some View {
        NavigationStack {
            List {
                Section { Text("\(selection.count) selected. Selection stays with you while searching.").foregroundStyle(Theme.muted) }
                ForEach(people) { person in
                    Button { if selection.contains(person.id) { selection.remove(person.id) } else { selection.insert(person.id) } } label: {
                        HStack(spacing: 12) { Avatar(person: person, size: 42); Text(person.name).foregroundStyle(Theme.ink); Spacer(); Image(systemName: selection.contains(person.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.plum) }.frame(minHeight: 48)
                    }.accessibilityIdentifier("event-guest-\(person.name)").accessibilityValue(selection.contains(person.id) ? "Selected" : "Not selected")
                }
                if people.isEmpty { Text("No one matches. Try another name.") }
            }.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find someone")
                .scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Theme.paper)
                .navigationTitle("Who was there?").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    ActionButton(title: "Done", icon: "checkmark") { dismiss() }.accessibilityIdentifier("event-people-done").padding(16).background(Theme.paper)
                }
        }
    }
}

struct MomentEditingView: View {
    let moment: Moment
    var body: some View {
        if moment.isSocialEvent { SocialEventEditor(moment: moment) }
        else { MomentEditor(personID: moment.personID, moment: moment) }
    }
}
