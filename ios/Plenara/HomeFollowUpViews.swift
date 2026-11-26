import SwiftUI

struct HomeFilterMenu<Content: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: {
            HStack(spacing: 5) { Text(title).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0); Image(systemName: "chevron.down").font(.caption2) }
                .font(.caption).padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line))
        }.accessibilityIdentifier(identifier)
    }
}

struct HomeFollowUpRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let candidate: FollowUpCandidate
    let expanded: Bool
    var toggle: () -> Void
    var log: () -> Void
    var remind: () -> Void
    var later: () -> Void
    var person: Person { candidate.person }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: toggle) {
                    HStack(spacing: 11) {
                        Avatar(person: person, size: typeSize.isAccessibilitySize ? 44 : 37)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(candidate.relationshipLabel).font(.caption).foregroundStyle(Theme.muted)
                            Text(candidate.reason).font(.caption).foregroundStyle(candidate.due ? Theme.plum : Theme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(person.name), \(candidate.relationshipLabel), \(candidate.reason)").accessibilityValue(expanded ? "Expanded" : "Collapsed").accessibilityIdentifier("home-person-\(person.name)")
                Button(action: toggle) { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Actions for \(person.name)").accessibilityIdentifier("home-actions-\(person.name)")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reminderContext).font(.caption).foregroundStyle(Theme.muted).accessibilityIdentifier("home-reason-\(person.name)")
                    if typeSize.isAccessibilitySize { VStack(spacing: 7) { actions } }
                    else { HStack(spacing: 7) { actions } }
                    HStack {
                        if candidate.connection == nil { Button("Add a contact date", action: remind).font(.caption).frame(minHeight: 44).accessibilityIdentifier("home-date-\(person.name)") }
                        Spacer(minLength: 8)
                        NavigationLink("View profile", value: person.id).font(.caption).frame(minHeight: 44).accessibilityIdentifier("home-profile-\(person.name)")
                    }
                }.padding(.bottom, 10)
            }
            Divider().overlay(Theme.line)
        }.padding(.horizontal, expanded ? 10 : 0).background(expanded ? Theme.lavender : Color.clear, in: RoundedRectangle(cornerRadius: 14))
    }
    var reminderContext: String {
        var parts = [rhythmLabel(person.cadence)]
        if let connection = candidate.connection {
            let approximate = person.baselineApproximate && person.baselineConnection == connection
            parts.append("\(approximate ? "Approximate contact" : "Last recorded contact"): \(connection.formatted(date: .abbreviated, time: .omitted))")
        } else if let start = person.reminderStart, person.cadence > 0 { parts.append("Reminders started \(start.formatted(date: .abbreviated, time: .omitted)); no contact recorded") }
        return parts.joined(separator: " · ")
    }
    @ViewBuilder var actions: some View {
        ReachOutButton(person: person, compact: true, dense: true)
        Button("Log contact", action: log).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("home-log-\(person.name)")
        Button("Later", action: later).font(.subheadline).frame(maxWidth: .infinity, minHeight: 48).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("home-later-\(person.name)")
    }
}

struct HomeFiltersView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @State var selection: FollowUpSelection
    @FocusState private var searching: Bool
    var apply: (FollowUpSelection) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Find someone", text: $selection.query).autocorrectionDisabled().focused($searching).submitLabel(.done).onSubmit { searching = false }.accessibilityIdentifier("home-filter-search") }
                Section {
                    Picker("Relationship", selection: $selection.people.connection) { Text("All").tag("Everyone"); Text("Family").tag("Family"); Text("Friends").tag("Friend"); Text("Not set").tag("Not set") }.accessibilityIdentifier("home-filter-relationship")
                    Picker("Closeness", selection: $selection.people.closeness) { Text("Any").tag("Everyone"); ForEach(Person.closenessOptions, id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("home-filter-closeness")
                    Picker("Follow-up", selection: $selection.status) { ForEach(FollowUpStatus.allCases, id: \.self) { Text($0.title).tag($0) } }.accessibilityIdentifier("home-filter-status")
                    Picker("Distance", selection: $selection.people.distance) { Text("Any").tag("Everyone"); ForEach(Person.distanceOptions, id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("home-filter-distance")
                    Picker("What I want", selection: $selection.people.direction) { Text("Any").tag("Everyone"); ForEach(Person.directionOptions, id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("home-filter-direction")
                    Picker("How it feels", selection: $selection.people.feeling) { Text("Any").tag("Everyone"); ForEach(Person.feelingOptions, id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("home-filter-feeling")
                } footer: { Text("Filters apply together. They don’t change reminder schedules.") }
                Button("Reset filters") { selection = FollowUpSelection() }.accessibilityIdentifier("home-filter-reset")
            }.pickerStyle(.menu).scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
                .toolbar { if !typeSize.isAccessibilitySize { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) } } }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if typeSize.isAccessibilitySize { Button("Cancel") { dismiss() }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 48).accessibilityIdentifier("home-filter-cancel") }
                        ActionButton(title: "Show people", icon: "line.3.horizontal.decrease") { apply(selection); dismiss() }.accessibilityIdentifier("home-filter-apply")
                    }.padding(16).background(Theme.paper).accessibilityElement(children: .contain).accessibilityIdentifier("home-filter-footer")
                }
        }
    }
}

struct FollowUpSnoozeView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Hide \(person.name) from suggestions until the date you choose."); DatePicker("Show again", selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date).accessibilityIdentifier("home-snooze-date") }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("Show later").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { guard var current = store.journal.people.first(where: { $0.id == person.id }) else { return }; current.snoozeUntil = Calendar.current.startOfDay(for: date); if store.save(current) { dismiss() } }.buttonStyle(.automatic).accessibilityIdentifier("home-snooze-save") }
                }
        }
    }
}
