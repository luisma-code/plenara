import SwiftUI

enum OrganizationField: String, CaseIterable, Identifiable {
    case connection = "Connection", distance = "Distance", closeness = "Closeness", direction = "What I want", feeling = "How it feels"
    var id: String { rawValue }
    var choices: [String] {
        switch self {
        case .connection: return ["Family", "Friend", "Family + Friend", "Not set"]
        case .distance: return Person.distanceOptions
        case .closeness: return Person.closenessOptions
        case .direction: return Person.directionOptions
        case .feeling: return Person.feelingOptions
        }
    }
    var bulkChoices: [String] { self == .connection ? ["Add Family", "Add Friend", "Remove Family", "Remove Friend", "Family + Friend", "Not set"] : choices }
    func value(_ person: Person) -> String {
        switch self {
        case .connection: return person.connectionKinds.isEmpty ? "Not set" : person.connectionKinds.joined(separator: " + ")
        case .distance: return person.distance
        case .closeness: return person.closeness
        case .direction: return person.directionChoice
        case .feeling: return person.feelingChoice
        }
    }
    func set(_ choice: String, on person: inout Person) {
        switch self {
        case .connection:
            if choice.hasPrefix("Add ") { let kind = String(choice.dropFirst(4)); person.connectionKinds = person.connectionKinds + [kind] }
            else if choice.hasPrefix("Remove ") { let kind = String(choice.dropFirst(7)); person.connectionKinds = person.connectionKinds.filter { $0 != kind } }
            else { person.connectionKinds = choice == "Not set" ? [] : choice.components(separatedBy: " + ") }
        case .distance: person.distance = choice
        case .closeness: person.closeness = choice
        case .direction: person.directionChoice = choice
        case .feeling: person.feelingChoice = choice
        }
    }
}
struct OrganizationFieldChange {
    let personID: UUID
    let field: OrganizationField
    let before: String
    let after: String
}
struct OrganizationReceipt {
    let changes: [OrganizationFieldChange]
    var peopleCount: Int { Set(changes.map(\.personID)).count }
}

struct OrganizePeopleView: View {
    @EnvironmentObject var store: JournalStore
    @State private var mode = "Together"
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var selected: Set<UUID> = []
    @State private var field: OrganizationField = .distance
    @State private var unsetOnly = false
    @State private var skipped: Set<UUID> = []
    @State private var editingBatch = false
    @State private var status = ""
    var people: [Person] {
        store.journal.people.filter { p in
            (query.isEmpty || "\(p.name) \(p.city)".localizedCaseInsensitiveContains(query)) &&
            (mode != "Quick sort" || ((!unsetOnly || field.value(p) == "Not set") && !skipped.contains(p.id)))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
                List {
                    controls.listRowSeparator(.hidden).listRowInsets(EdgeInsets()).listRowBackground(Theme.paper)
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(Theme.muted).accessibilityIdentifier("organize-status").listRowBackground(Theme.paper).listRowSeparator(.hidden) }
                    if people.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(query.isEmpty ? "All clear here." : "No one matches that search.").font(Theme.title(25))
                            Text("Your people are still here. Change the search or show everyone to continue.").foregroundStyle(Theme.muted)
                            Button("Show everyone") { query = ""; unsetOnly = false; skipped = [] }
                        }.padding(.vertical, 12)
                    }
                    ForEach(people) { person in
                        if mode == "Together" { selectionRow(person) }
                        else { sortRow(person) }
                    }
                }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("organize-list")
                .background(Theme.paper)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find people by name or city")
                .searchFocused($searchFocused)
                .onSubmit(of: .search) { searchFocused = false }
                .navigationTitle("Organize your people").navigationBarTitleDisplayMode(.inline)
                .toolbar { DismissButton() }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                .sheet(isPresented: $editingBatch) {
                    OrganizationBatchEditor(ids: selected) { count in
                        selected = []; status = "Updated \(count) \(count == 1 ? "person" : "people")."
                    }
                }
                .onChange(of: field) { _, _ in skipped = [] }
                .onChange(of: mode) { _, _ in skipped = [] }
        }
    }
    var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Organize mode", selection: $mode) { Text("Together").tag("Together"); Text("Quick sort").tag("Quick sort") }.pickerStyle(.segmented).accessibilityIdentifier("organize-mode")
            if mode == "Together" {
                Text("Select people, then change only the details they share.").font(.subheadline).foregroundStyle(Theme.muted)
                HStack {
                    Button("Select shown (\(people.count))") { selected.formUnion(people.map(\.id)) }.disabled(people.isEmpty).accessibilityIdentifier("organize-select-shown")
                    Spacer()
                    Button("Clear selection") { selected = [] }.disabled(selected.isEmpty)
                }.font(.subheadline).frame(minHeight: 44)
                Text("\(selected.count) selected\(selected.subtracting(Set(people.map(\.id))).isEmpty ? "" : " · includes people outside this search")").font(.footnote).foregroundStyle(Theme.muted).accessibilityIdentifier("organize-selection-count")
            } else {
                Picker("Sort by", selection: $field) { ForEach(OrganizationField.allCases) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("organize-field")
                Toggle("Not set only", isOn: $unsetOnly).accessibilityIdentifier("organize-unset-only")
                Text("Tap a choice to save. Skip leaves their details untouched. \(people.count) shown\(skipped.isEmpty ? "" : " · \(skipped.count) skipped").").font(.footnote).foregroundStyle(Theme.muted)
                if !skipped.isEmpty { Button("Show skipped people") { skipped = [] }.font(.subheadline) }
            }
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }
    func selectionRow(_ p: Person) -> some View {
        Button {
            if selected.contains(p.id) { selected.remove(p.id) } else { selected.insert(p.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(Theme.plum)
                Avatar(person: p, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(p.name).font(.headline).foregroundStyle(Theme.ink)
                    Text([OrganizationField.connection.value(p), p.distance, p.closeness].joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 62).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(p.id) ? .isSelected : []).accessibilityIdentifier("organize-person-\(p.name)").listRowBackground(Theme.paper)
    }
    func sortRow(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(person: p, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.headline)
                    Text("\(field.rawValue): \(field.value(p))").font(.subheadline).foregroundStyle(Theme.muted).accessibilityIdentifier("sort-value-\(p.name)")
                }
                Spacer(minLength: 0)
                Button("Skip") { skipped.insert(p.id) }.font(.footnote).accessibilityIdentifier("sort-skip-\(p.name)")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 8) {
                ForEach(field.choices, id: \.self) { choice in
                    Button {
                        if let receipt = store.organize([p.id], changes: [field: choice]) { status = "Updated \(receipt.peopleCount) person." }
                        else { status = store.errorMessage ?? "Already set." }
                    } label: {
                        Text(choice).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(field.value(p) == choice ? .white : Theme.ink)
                            .background(field.value(p) == choice ? Theme.action : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                    }.buttonStyle(.plain).accessibilityAddTraits(field.value(p) == choice ? .isSelected : []).accessibilityIdentifier("sort-\(p.name)-\(choice)")
                }
            }
        }.padding(.vertical, 12).listRowBackground(Theme.paper)
    }
    var bottomBar: some View {
        VStack(spacing: 8) {
            if store.organizationUndo != nil {
                Button("Undo") {
                    if store.undoOrganization() { status = "Undone. Your earlier details are restored." }
                    else { status = store.errorMessage ?? "Couldn’t undo this change." }
                }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityLabel("Undo last organization").accessibilityIdentifier("organize-undo")
            }
            if mode == "Together" {
                ActionButton(title: "Organize \(selected.count) \(selected.count == 1 ? "person" : "people")", icon: "slider.horizontal.3") { searchFocused = false; editingBatch = true }.disabled(selected.isEmpty).opacity(selected.isEmpty ? 0.5 : 1).accessibilityIdentifier("organize-apply")
            }
        }.padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: .infinity).background(Theme.paper).overlay(alignment: .top) { Divider() }
    }
}

struct OrganizationBatchEditor: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    let ids: Set<UUID>
    var saved: (Int) -> Void
    @State private var changes: [OrganizationField: String] = [:]
    @State private var status = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose the details for \(ids.count) \(ids.count == 1 ? "person" : "people"). Everything else stays as it is.")
                    Text("Adding Family or Friend keeps the other connection label. Not set clears only that attribute.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("Shared details") {
                    ForEach(OrganizationField.allCases) { field in
                        Picker(field.rawValue, selection: Binding(get: { changes[field] ?? "No change" }, set: { if $0 == "No change" { changes[field] = nil } else { changes[field] = $0 } })) {
                            Text("No change").tag("No change")
                            ForEach(field.bulkChoices, id: \.self) { Text($0).tag($0) }
                        }.accessibilityIdentifier("batch-\(field.rawValue)")
                    }
                }
                if !status.isEmpty { Text(status).foregroundStyle(Theme.muted).accessibilityIdentifier("batch-status") }
            }.scrollContentBackground(.hidden).background(Theme.paper)
                .navigationTitle("Organize \(ids.count) \(ids.count == 1 ? "person" : "people")").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            if let receipt = store.organize(ids, changes: changes) { saved(receipt.peopleCount); dismiss() }
                            else { status = store.errorMessage ?? "These people already match your choices. Nothing changed." }
                        }.buttonStyle(.automatic).disabled(changes.isEmpty).accessibilityIdentifier("batch-save")
                    }
                }
        }
    }
}
