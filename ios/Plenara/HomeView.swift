import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: JournalStore
    var openSettings: () -> Void
    @State private var momentPerson: Person?
    @State private var quickLogging = false
    @State private var adding = false
    @State private var showingAllSuggestions = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    HStack(spacing: 7) { Image(systemName: "asterisk").foregroundStyle(Theme.plum); Text("plenara").font(Theme.title(25)) }
                    Spacer()
                    Button(action: openSettings) { Image(systemName: "bell").font(.title3).frame(width: 46, height: 46).overlay(Circle().stroke(Theme.line)) }.accessibilityLabel("Settings and reminders")
                }
                if !store.journal.people.isEmpty {
                    ActionButton(title: "Log a moment", icon: "square.and.pencil") { quickLogging = true }
                        .accessibilityIdentifier("quick-log")
                }
                PageHeading(eyebrow: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()), title: "A little closer.", subtitle: "Small moments keep your people close.\nWho’s on your mind today?")
                if store.journal.people.isEmpty {
                    QuietEmpty(title: "Start with your people.", message: "Bring in a few friends or family members. A name is all you need to begin.")
                    ActionButton(title: "Bring your people in", icon: "person.badge.plus") { adding = true }
                } else {
                    if !store.journal.datedReminders().isEmpty {
                        Text("A little reminder").font(Theme.title(25))
                        ForEach(store.journal.datedReminders()) { reminder in
                            Surface(color: Theme.peach) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Eyebrow(text: reminder.caption)
                                    NavigationLink(value: reminder.person.id) {
                                        HStack { Avatar(person: reminder.person); Text(reminder.person.name).font(.headline); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 50).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("dated-\(reminder.person.name)")
                                    Text(reminder.text).lineSpacing(3)
                                    if let noteID = reminder.noteID {
                                        Button("Picked up this thread") {
                                            store.update { j in if let i = j.people.firstIndex(where: { $0.id == reminder.person.id }), let n = j.people[i].notes.firstIndex(where: { $0.id == noteID }) { j.people[i].notes[n].followUp = nil } }
                                        }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                                    }
                                }
                            }
                        }
                    }
                    let now = Date()
                    let ranked = store.journal.rankedSuggestions(now: now)
                    let suggestions = Array(ranked.prefix(3))
                    ReconnectionSection(ranked: ranked, showingAllSuggestions: $showingAllSuggestions, logMoment: { momentPerson = $0 })
                    let visibleIDs = Set((showingAllSuggestions ? ranked : suggestions).map(\.id))
                    let context = store.journal.contextualSuggestions(excluding: visibleIDs, ranked: ranked, now: now)
                    let growth = context.growth
                    if let local = growth {
                        Text("Make a little room").font(Theme.title(25))
                        NavigationLink(value: local.id) {
                            Surface(color: Theme.sage) {
                                VStack(alignment: .leading, spacing: 15) {
                                    HStack { Avatar(person: local); VStack(alignment: .leading) { Text(local.distance == "Nearby" ? "\(local.name.components(separatedBy: " ").first ?? local.name) is nearby." : "A little time for \(local.name.components(separatedBy: " ").first ?? local.name).").font(Theme.title(24)); Text(local.feelingChoice == "Needs care" ? "Grow closer · Needs care" : "A connection you’d like to grow").font(.subheadline).foregroundStyle(Theme.muted) } }
                                    Text(local.notes.first(where: { !$0.archived && $0.category == "An idea for us" })?.text ?? (local.distance == "Nearby" ? "A walk, a coffee, a little time together." : "A call or a voice note, and room for a proper catch-up.")).font(.body)
                                    Label("An idea for you two", systemImage: "arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.plum)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("growth-\(local.name)")
                    }
                    let care = context.care
                    if !care.isEmpty {
                        Text("A little care").font(Theme.title(25))
                        Text("Relationships you’ve chosen to give some care. There’s no countdown.").font(.subheadline).foregroundStyle(Theme.muted)
                        ForEach(Array(care.prefix(2))) { p in NavigationLink(value: p.id) { PersonRow(person: p, detail: p.intention.isEmpty ? "Needs care · at your own pace" : p.intention) }.buttonStyle(.plain).accessibilityIdentifier("care-\(p.name)") }
                    }
                    if store.journal.people.contains(where: { $0.cadence == 0 || (store.journal.lastConnection($0) == nil && $0.reminderStart == nil) }) {
                        Text("Your people are here. Set a rhythm on their page whenever you’re ready for reminders.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Text("A little attention, at your own pace.").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical)
                }
            }.padding(24)
        }.sheet(isPresented: $quickLogging) { LogMomentFlow() }
            .sheet(item: $momentPerson) { MomentEditor(personID: $0.id) }
            .sheet(isPresented: $adding) { AddPeopleView() }
    }

}
struct AddPeopleView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    @State private var countBeforeAdding = 0
    @State private var manual = false
    @State private var importing = false
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Your circle", title: "Bring your\npeople in.", subtitle: "Start with a few people. Your whole address book doesn’t have to become a to-do list.")
                ActionButton(title: "Import from Contacts", icon: "person.crop.circle.badge.plus") { countBeforeAdding = store.journal.people.count; importing = true }
                ActionButton(title: "Add someone yourself", primary: false) { countBeforeAdding = store.journal.people.count; manual = true }
                Text("Only the contacts you choose are shared with Plenara. Notes and moments stay in your private journal.").font(.footnote).foregroundStyle(Theme.muted)
            }.padding(24) }.background(Theme.paper).toolbar { DismissButton() }
                .sheet(isPresented: $manual, onDismiss: finishAdding) { PersonEditor(person: Person()) }
                .sheet(isPresented: $importing, onDismiss: finishAdding) { ImportContactsView() }
        }
    }
    func finishAdding() { if store.journal.people.count > countBeforeAdding { dismiss() } }
}
struct PeopleView: View {
    @EnvironmentObject var store: JournalStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var filter = PeopleFilter()
    @State private var showingFilters = false
    @State private var organizing = false
    @State private var adding = false
    @State private var importing = false
    let shortcuts = ["Everyone", "Grow closer", "Needs care", "Nearby", "Far away", "Family"]
    var filtered: [Person] {
        store.journal.people.filter { p in
            (query.isEmpty || "\(p.name) \(p.city)".localizedCaseInsensitiveContains(query)) && filter.includes(p)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func selected(_ choice: String) -> Bool {
        switch choice {
        case "Everyone": return !filter.isActive
        case "Grow closer": return filter.direction == choice
        case "Needs care": return filter.feeling == choice
        case "Family": return filter.connection == choice
        default: return filter.distance == choice
        }
    }
    func toggle(_ choice: String) {
        let next = selected(choice) ? "Everyone" : choice
        switch choice {
        case "Everyone": filter = PeopleFilter()
        case "Grow closer": filter.direction = next
        case "Needs care": filter.feeling = next
        case "Family": filter.connection = next
        default: filter.distance = next
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Eyebrow(text: "Your circle"); Spacer(); Button { adding = true } label: { Image(systemName: "plus").font(.title2).frame(width: 46, height: 46).overlay(Circle().stroke(Theme.line)) }.accessibilityLabel("Add a person") }
                if !store.journal.people.isEmpty {
                Button { searchFocused = false; organizing = true } label: { Label("Organize", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48).background(Theme.lavender, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).accessibilityIdentifier("people-organize")
                }
                Text("Your people.").font(Theme.title()).tracking(-1.3)
                Text("Different kinds of close. All in one place.").foregroundStyle(Theme.muted)
                HStack { Image(systemName: "magnifyingglass"); TextField("Find someone", text: $query, prompt: Text("Find someone").foregroundStyle(Theme.muted)).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }.accessibilityIdentifier("people-search").autocorrectionDisabled() }.padding(14).background(Theme.line.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
                HStack {
                    Text("\(filtered.count) \(filtered.count == 1 ? "person" : "people")").font(.footnote).foregroundStyle(Theme.muted).accessibilityIdentifier("people-count")
                    Spacer()
                    if filter.isActive { Button("Clear") { filter = PeopleFilter() }.font(.subheadline).frame(minHeight: 44).accessibilityLabel("Clear filters").accessibilityIdentifier("people-clear-filters") }
                    Button { searchFocused = false; showingFilters = true } label: { Label("Filters", systemImage: "line.3.horizontal.decrease").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }.accessibilityIdentifier("people-filters")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(shortcuts, id: \.self) { f in
                        Button { toggle(f) } label: { Text(f).font(.subheadline).padding(.horizontal, 15).frame(minHeight: 44).background(selected(f) ? Theme.action : Theme.card, in: Capsule()).foregroundStyle(selected(f) ? .white : Theme.ink).overlay(Capsule().stroke(Theme.line)) }.buttonStyle(.plain).accessibilityAddTraits(selected(f) ? .isSelected : []).accessibilityIdentifier("filter-\(f)")
                    } }
                }.accessibilityIdentifier("people-shortcuts")
                if filter.isActive {
                    Text([filter.connection, filter.distance, filter.closeness, filter.direction, filter.feeling].filter { $0 != "Everyone" }.joined(separator: " · ")).font(.footnote.weight(.medium)).foregroundStyle(Theme.plum).accessibilityIdentifier("active-filters")
                    Text("All selected choices apply. Tap Everyone to clear them.").font(.footnote).foregroundStyle(Theme.muted)
                }
                if filtered.isEmpty {
                    QuietEmpty(title: filter.isActive || !query.isEmpty ? "No one matches yet." : "Make room for someone.", message: filter.isActive || !query.isEmpty ? "Try another name or loosen a filter. Your people are still here." : "Add someone yourself, or choose a few people from Contacts.")
                }
                VStack(spacing: 11) { ForEach(filtered) { p in NavigationLink(value: p.id) { PersonRow(person: p) }.buttonStyle(.plain).accessibilityIdentifier("person-\(p.name)") } }
                ActionButton(title: "Import from Contacts", icon: "person.badge.plus", primary: false) { importing = true }
                Text("Choose just the people you want to keep close.").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively).sheet(isPresented: $organizing) { OrganizePeopleView() }.sheet(isPresented: $showingFilters) { PeopleFiltersView(filter: $filter) }.sheet(isPresented: $adding) { PersonEditor(person: Person()) }.sheet(isPresented: $importing) { ImportContactsView() }
    }
}
struct DismissButton: ToolbarContent {
    @Environment(\.dismiss) var dismiss
    var body: some ToolbarContent { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.buttonStyle(.automatic) } }
}


struct PeopleFiltersView: View {
    @Binding var filter: PeopleFilter
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Connection", selection: $filter.connection) { ForEach(["Everyone", "Not set"] + Person.connectionOptions, id: \.self) { Text($0) } }
                    Picker("Distance", selection: $filter.distance) { ForEach(["Everyone"] + Person.distanceOptions, id: \.self) { Text($0) } }
                    Picker("Closeness", selection: $filter.closeness) { ForEach(["Everyone"] + Person.closenessOptions, id: \.self) { Text($0) } }
                    Picker("What I want", selection: $filter.direction) { ForEach(["Everyone"] + Person.directionOptions, id: \.self) { Text($0) } }
                    Picker("How it feels", selection: $filter.feeling) { ForEach(["Everyone"] + Person.feelingOptions, id: \.self) { Text($0) } }
                } footer: { Text("Choose independently. For example, Family + Far away + Needs care. Everyone leaves that dimension open; Not set finds unanswered profiles.") }
                Button("Clear all filters") { filter = PeopleFilter() }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("Find your people").navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
        }
    }
}
