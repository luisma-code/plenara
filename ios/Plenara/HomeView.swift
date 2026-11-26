import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dynamicTypeSize) private var typeSize
    var openSettings: () -> Void
    static var preferenceKey: String {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return "home.selection.ui-testing" }
        #endif
        return "home.selection"
    }
    @AppStorage(HomeView.preferenceKey) private var savedSelection = ""
    @State private var selection = FollowUpSelection()
    @State private var loaded = false
    @State private var now = Date()
    @State private var expanded: UUID?
    @State private var momentPerson: Person?
    @State private var reminderPerson: Person?
    @State private var snoozePerson: Person?
    @State private var quickLogging = false
    @State private var socialEvent = false
    @State private var rhythmSetup = false
    @State private var adding = false
    @State private var filtering = false
    var body: some View {
        let candidates = store.journal.followUpCandidates(selection: selection, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 7) { Image(systemName: "asterisk").foregroundStyle(Theme.plum); Text("plenara").font(Theme.title(25)) }
                    Spacer()
                    Button(action: openSettings) { Image(systemName: "bell").font(.title3).frame(width: 44, height: 44).overlay(Circle().stroke(Theme.line)) }.accessibilityLabel("Settings and reminders")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Follow up").font(Theme.title(32)); Spacer(); logMenu }
                    VStack(alignment: .leading) { Text("Follow up").font(Theme.title(32)); logMenu }
                }
                if store.journal.people.isEmpty {
                    QuietEmpty(title: "Add people to get started.", message: "Choose contacts to import, or add someone by name.")
                    ActionButton(title: "Add people", icon: "person.badge.plus") { adding = true }
                } else {
                    datedReminders
                    relationshipTabs
                    if typeSize.isAccessibilitySize { VStack(spacing: 8) { quickFilters } }
                    else { HStack(spacing: 7) { quickFilters } }
                    if !selection.extraChoices.isEmpty {
                        HStack {
                            Text(selection.extraChoices.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.plum)
                            Spacer()
                            Button("Clear") { selection.people.distance = "Everyone"; selection.people.direction = "Everyone"; selection.people.feeling = "Everyone"; selection.query = ""; if selection.people.connection == "Not set" { selection.people.connection = "Everyone" } }.font(.caption).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("home-clear-extra-filters")
                        }
                    }
                    HStack {
                        Text("\(candidates.count) \(candidates.count == 1 ? "person" : "people")").font(.caption).foregroundStyle(Theme.muted).accessibilityIdentifier("home-count")
                        Spacer()
                        Menu {
                            Picker("Sort people", selection: $selection.sort) { ForEach(FollowUpSort.allCases, id: \.self) { Text($0.title).tag($0) } }
                        } label: { Label(selection.sort.title, systemImage: "chevron.down").font(.caption).frame(minHeight: 44) }.accessibilityIdentifier("home-sort")
                    }
                    if candidates.isEmpty { emptyState }
                    LazyVStack(spacing: 0) {
                        ForEach(candidates) { candidate in
                            HomeFollowUpRow(candidate: candidate, expanded: expanded == candidate.id, toggle: { expanded = expanded == candidate.id ? nil : candidate.id }, log: { momentPerson = candidate.person }, remind: { reminderPerson = candidate.person }, later: { snoozePerson = candidate.person })
                        }
                    }
                    if candidates.contains(where: { $0.connection == nil }) {
                        Text("Some contact dates haven’t been recorded.").font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
                    }
                    Button("Set up reminders") { rhythmSetup = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("home-rhythm-setup")
                }
            }.padding(.horizontal, 20).padding(.vertical, 8)
        }
        .refreshable { now = Date() }
        .onAppear { now = Date(); if !loaded { selection = FollowUpSelection(saved: savedSelection); loaded = true } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in now = Date() }
        .onChange(of: selection) { _, value in if loaded { savedSelection = value.encoded }; expanded = nil }
        .onChange(of: store.journal) { _, _ in now = Date() }
        .sheet(isPresented: $filtering) { HomeFiltersView(selection: selection) { selection = $0 } }
        .sheet(isPresented: $quickLogging) { LogMomentFlow() }
        .sheet(item: $momentPerson) { MomentEditor(personID: $0.id) }
        .sheet(item: $reminderPerson) { RhythmEditor(person: $0, addingContactDate: true) }
        .sheet(item: $snoozePerson) { FollowUpSnoozeView(person: $0) }
        .sheet(isPresented: $adding) { AddPeopleView() }
        .sheet(isPresented: $socialEvent) { SocialEventEditor() }
        .sheet(isPresented: $rhythmSetup) { RhythmSetupView() }
    }
    var logMenu: some View {
        Menu {
            Button("One person", systemImage: "person") { quickLogging = true }.accessibilityIdentifier("home-log-person")
            Button("Group event", systemImage: "person.3") { socialEvent = true }.accessibilityIdentifier("log-social-event")
        } label: { Label("Log contact", systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44).foregroundStyle(.white).background(Theme.action, in: RoundedRectangle(cornerRadius: 14)) }.accessibilityIdentifier("quick-log")
    }
    var relationshipTabs: some View {
        HStack(spacing: 3) {
            ForEach([("All", "Everyone"), ("Family", "Family"), ("Friends", "Friend")], id: \.0) { label, value in
                Button { selection.people.connection = value } label: { Text(label).font(.subheadline.weight(selection.people.connection == value ? .semibold : .regular)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).background(selection.people.connection == value ? Theme.card : Color.clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).accessibilityIdentifier("home-type-\(label)").accessibilityAddTraits(selection.people.connection == value ? .isSelected : [])
            }
        }.padding(3).background(Theme.line, in: RoundedRectangle(cornerRadius: 13))
    }
    @ViewBuilder var quickFilters: some View {
        HomeFilterMenu(title: selection.people.closeness == "Everyone" ? "Any closeness" : selection.people.closeness, identifier: "home-closeness") {
            Picker("Closeness", selection: $selection.people.closeness) { Text("Any closeness").tag("Everyone"); ForEach(Person.closenessOptions, id: \.self) { Text($0).tag($0) } }
        }
        HomeFilterMenu(title: selection.status == .unknown ? "No history" : selection.status.title, identifier: "home-follow-up") {
            Picker("Follow-up status", selection: $selection.status) { ForEach(FollowUpStatus.allCases, id: \.self) { Text($0.title).tag($0) } }
        }
        Button(selection.extraChoices.isEmpty ? "Filters" : "Filters (\(selection.extraChoices.count))") { filtering = true }.font(.caption).padding(.horizontal, 10).frame(minHeight: 44).frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil).background(selection.extraChoices.isEmpty ? Theme.card : Theme.lavender, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line)).accessibilityIdentifier("home-filters")
    }
    @ViewBuilder var emptyState: some View {
        let anyDue = !store.journal.rankedSuggestions(now: now).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            Text(selection.status == .due && !anyDue ? "No reminders due." : selection.isActive ? "No one matches these filters." : "No follow-ups right now.").font(Theme.title(24))
            Text(selection.status == .due && !anyDue ? "Reminders need a schedule and a starting date. All suggestions also includes people with missing contact history." : selection.isActive ? "Change a filter to see more people." : "Recent contact, pauses and snoozes keep people out of this list. Your full list is in People.").font(.subheadline).foregroundStyle(Theme.muted)
            if selection.isActive { Button("Show all suggestions") { selection = FollowUpSelection() }.frame(minHeight: 44).accessibilityIdentifier("home-show-all") }
        }.padding(.vertical, 15)
    }
    @ViewBuilder var datedReminders: some View {
        let reminders = store.journal.datedReminders(now: now)
        if !reminders.isEmpty {
            Text("Dates and follow-ups").font(.headline)
            ForEach(reminders) { reminder in
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink(value: reminder.person.id) { VStack(alignment: .leading, spacing: 3) { Text("\(reminder.person.name) · \(reminder.caption)").font(.subheadline.weight(.semibold)); if reminder.noteID != nil { Text(reminder.text).font(.caption).foregroundStyle(Theme.muted) } }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("dated-\(reminder.person.name)")
                    if let noteID = reminder.noteID { Button("Mark followed up") { store.update { j in if let i = j.people.firstIndex(where: { $0.id == reminder.person.id }), let n = j.people[i].notes.firstIndex(where: { $0.id == noteID }) { j.people[i].notes[n].followUp = nil } } }.font(.caption).frame(minHeight: 44) }
                }.padding(12).background(Theme.peach, in: RoundedRectangle(cornerRadius: 15))
            }
        }
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
                PageHeading(eyebrow: "People", title: "Add people", subtitle: "Add someone by name, or select contacts to import.")
                ActionButton(title: "Import from Contacts", icon: "person.crop.circle.badge.plus") { countBeforeAdding = store.journal.people.count; importing = true }
                ActionButton(title: "Add by name", primary: false) { countBeforeAdding = store.journal.people.count; manual = true }
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
    @State private var settingRhythms = false
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
                HStack { Eyebrow(text: "People"); Spacer(); Button { adding = true } label: { Image(systemName: "plus").font(.title2).frame(width: 46, height: 46).overlay(Circle().stroke(Theme.line)) }.accessibilityLabel("Add a person") }
                if !store.journal.people.isEmpty {
                Button { searchFocused = false; organizing = true } label: { Label("Organize", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48).background(Theme.lavender, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).accessibilityIdentifier("people-organize")
                Button("Set up reminders") { searchFocused = false; settingRhythms = true }.frame(minHeight: 44).accessibilityIdentifier("people-rhythm-setup")
                }
                Text("People").font(Theme.title()).tracking(-1.3)
                Text("Find people and update relationship details.").foregroundStyle(Theme.muted)
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
                    QuietEmpty(title: filter.isActive || !query.isEmpty ? "No matching people." : "No people added.", message: filter.isActive || !query.isEmpty ? "Change the search or filters to see more people." : "Add by name, or choose a few people from Contacts.")
                }
                VStack(spacing: 11) { ForEach(filtered) { p in NavigationLink(value: p.id) { PersonRow(person: p) }.buttonStyle(.plain).accessibilityIdentifier("person-\(p.name)") } }
                ActionButton(title: "Import from Contacts", icon: "person.badge.plus", primary: false) { importing = true }
                Text("Import only the contacts you select.").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively).sheet(isPresented: $organizing) { OrganizePeopleView() }.sheet(isPresented: $showingFilters) { PeopleFiltersView(filter: $filter) }.sheet(isPresented: $adding) { PersonEditor(person: Person()) }.sheet(isPresented: $importing) { ImportContactsView() }.sheet(isPresented: $settingRhythms) { RhythmSetupView() }
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
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("Filter people").navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
        }
    }
}
