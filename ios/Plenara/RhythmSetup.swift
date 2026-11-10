import SwiftUI

struct RhythmSetupView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Set<UUID> = []
    @State private var cadence = 0
    @State private var includeExisting = false
    @State private var approximate = false
    @State private var earlierDate = Date()
    @State private var savedCount = 0
    var shown: [Person] { store.journal.people.filter { query.isEmpty || "\($0.name) \($0.city)".localizedCaseInsensitiveContains(query) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    private func apply() {
        savedCount = 0
        let count = selected.count
        if store.setRhythm(selected, cadence: cadence, anchor: approximate ? .approximate(earlierDate) : .today, replaceExisting: includeExisting) { savedCount = count; selected = [] }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose who you’d like a rhythm with. Nothing is selected and no reminder starts until you apply your choices.").foregroundStyle(Theme.muted)
                    Toggle("Include people with existing rhythms", isOn: $includeExisting).accessibilityIdentifier("rhythm-include-existing")
                    Text("Existing rhythms are shown beside each name. They stay as they are unless you explicitly include and select them.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("Your choice") {
                    Picker("Contact rhythm", selection: $cadence) {
                        Text("Choose a rhythm").tag(0)
                        ForEach(Array(Set([3, 7, 14, 21, 30, 60, 90, cadence])).filter { $0 > 0 }.sorted(), id: \.self) { Text(rhythmLabel($0)).tag($0) }
                    }.accessibilityIdentifier("setup-rhythm-cadence")
                    if cadence > 0 { Stepper("Every \(cadence) days", value: $cadence, in: 1...3650).accessibilityIdentifier("setup-rhythm-custom") }
                    Toggle("Set an approximate earlier connection", isOn: $approximate).accessibilityIdentifier("setup-approximate")
                    if approximate { DatePicker("Roughly when?", selection: $earlierDate, in: ...Date(), displayedComponents: .date) }
                    Text(approximate ? "For people with no known connection, this becomes an approximate starting date. Recorded connections are preserved." : "For people with no known connection, reminders start from today. This does not invent a conversation.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section {
                    Text("\(selected.count) selected").font(.subheadline.weight(.semibold)).accessibilityIdentifier("setup-rhythm-selection")
                    ForEach(shown) { person in
                        let enabled = includeExisting || person.cadence == 0
                        Button { if selected.contains(person.id) { selected.remove(person.id) } else { selected.insert(person.id) } } label: {
                            HStack(spacing: 12) {
                                Avatar(person: person, size: 42)
                                VStack(alignment: .leading, spacing: 5) { Text(person.name).foregroundStyle(Theme.ink); Text(rhythmLabel(person.cadence)).font(.footnote).foregroundStyle(Theme.muted) }
                                Spacer(); Image(systemName: selected.contains(person.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.plum)
                            }.frame(minHeight: 48).opacity(enabled ? 1 : 0.5)
                        }.disabled(!enabled).accessibilityIdentifier("rhythm-person-\(person.name)").accessibilityValue(selected.contains(person.id) ? "Selected" : "Not selected")
                    }
                    if shown.isEmpty { Text("No one matches. Your other people are still here.").foregroundStyle(Theme.muted) }
                    Button("Clear selection") { selected = [] }.disabled(selected.isEmpty)
                } header: { Text("Choose your people") } footer: { Text("Selections stay selected while searching. Apply uses all selected people, including those outside this search.") }
            }.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a person or place")
                .scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Theme.paper)
                .navigationTitle("Find your rhythms").navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 6) {
                        if savedCount > 0 { Text("Rhythm saved for \(savedCount) \(savedCount == 1 ? "person" : "people").").font(.footnote).accessibilityIdentifier("rhythm-saved") }
                        HStack {
                            ActionButton(title: "Apply rhythm (\(selected.count))", icon: "checkmark") { apply() }
                                .disabled(selected.isEmpty || cadence == 0).opacity(selected.isEmpty || cadence == 0 ? 0.5 : 1).accessibilityIdentifier("apply-rhythm")
                            Button("Done") { dismiss() }.frame(minWidth: 60, minHeight: 48).accessibilityIdentifier("rhythm-done")
                        }
                        if store.rhythmUndo != nil { Button("Undo last rhythm setup") { if store.undoRhythm() { savedCount = 0 } }.frame(minHeight: 44).accessibilityIdentifier("undo-rhythm") }
                    }.padding(16).background(Theme.paper)
                }
                .onChange(of: includeExisting) { _, enabled in if !enabled { selected.subtract(store.journal.people.filter { $0.cadence > 0 }.map(\.id)) } }
        }
    }
}
