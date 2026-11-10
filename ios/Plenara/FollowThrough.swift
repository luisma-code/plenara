import SwiftUI

struct WorkflowFeedbackBar: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var reviewContact: (ContactDraft) -> Void
    var reviewMoment: (UUID) -> Void
    var body: some View {
        if let draft = store.journal.pendingContact {
            HStack {
                Button { reviewContact(draft) } label: { Label("Review your reach-out", systemImage: "arrow.uturn.backward").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.accessibilityIdentifier("review-contact-draft")
                Button { store.dismissContact(draft.id) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Dismiss reach-out draft")
            }.padding(.horizontal, 20).background(Theme.lavender)
        } else if let id = store.recentMomentID, store.journal.moments.contains(where: { $0.id == id }) {
            HStack {
                Button { reviewMoment(id) } label: { Label(dynamicTypeSize.isAccessibilitySize ? "Saved · For next time" : "Saved · Keep something for next time", systemImage: "text.bubble").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.accessibilityLabel("Saved. Keep something for next time").accessibilityIdentifier("moment-follow-through")
                Button { store.recentMomentID = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Dismiss next-time suggestion")
            }.padding(.horizontal, 20).background(Theme.sage)
        }
    }
}

struct MemoryEditTarget: Identifiable {
    var id: UUID { memory.id }
    let personID: UUID
    let memory: Memory
}
struct FollowThroughView: View {
    @EnvironmentObject var store: JournalStore
    let momentID: UUID
    @State private var adding: MemoryEditTarget?
    @State private var later: MemoryEditTarget?
    @State private var resolving: MemoryEditTarget?
    @State private var kept: Set<UUID> = []
    @State private var status: String?
    var moment: Moment? { store.journal.moments.first { $0.id == momentID } }
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Your moment is saved. Keep a detail for the next conversation, or leave things here.").foregroundStyle(Theme.muted) }
                if let moment {
                    ForEach(moment.participantIDs, id: \.self) { id in
                        if let person = store.journal.people.first(where: { $0.id == id }) {
                            Section(person.name) {
                                Button { status = nil; adding = MemoryEditTarget(personID: id, memory: Memory(pinned: true)) } label: { Label("Keep something for next time", systemImage: "plus.bubble") }.accessibilityIdentifier("thread-add-\(person.name)")
                                let threads = person.notes.filter { !$0.archived && ($0.pinned || ($0.followUp.map { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: Date()) } ?? false)) }
                                ForEach(threads) { note in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(note.text).foregroundStyle(Theme.ink)
                                        if let due = note.followUp { Text("Follow up \(due.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.muted) }
                                        if kept.contains(note.id) { Label("Kept as it is", systemImage: "checkmark").font(.footnote).foregroundStyle(Theme.muted) }
                                        else {
                                            ViewThatFits(in: .horizontal) {
                                                HStack { threadActions(person, note) }
                                                VStack(alignment: .leading) { threadActions(person, note) }
                                            }
                                        }
                                    }.padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
                if let status { Section { Text(status).font(.footnote).foregroundStyle(Theme.muted) } }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("For next time").navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
                .sheet(item: $adding) { MemoryEditor(personID: $0.personID, memory: $0.memory) }
                .sheet(item: $later) { ThreadDateEditor(target: $0) }
                .confirmationDialog("Resolve this thread?", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
                    if let target = resolving {
                        Button("Resolve and unpin") { resolve(target, unpin: true) }
                        Button("Resolve, keep pinned") { resolve(target, unpin: false) }
                        Button("Cancel", role: .cancel) { resolving = nil }
                    }
                } message: { Text("The follow-up date is cleared. Your memory and its original text stay in the journal.") }
        }
    }
    @ViewBuilder private func threadActions(_ person: Person, _ note: Memory) -> some View {
        Button("Keep") { status = nil; kept.insert(note.id) }.buttonStyle(.borderless).frame(minHeight: 44)
        Button("Resolve") { status = nil; resolving = MemoryEditTarget(personID: person.id, memory: note) }.buttonStyle(.borderless).frame(minHeight: 44).accessibilityIdentifier("thread-resolve-\(note.id)")
        Button("Later") { status = nil; later = MemoryEditTarget(personID: person.id, memory: note) }.buttonStyle(.borderless).frame(minHeight: 44).accessibilityIdentifier("thread-later-\(note.id)")
    }
    private func resolve(_ target: MemoryEditTarget, unpin: Bool) {
        if store.updateThread(personID: target.personID, noteID: target.id, followUp: nil, unpin: unpin) { status = "Thread resolved. The memory is still here." }
        resolving = nil
    }
}
struct ThreadDateEditor: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let target: MemoryEditTarget
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(target.memory.text); DatePicker("Pick it up on", selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date) }
                Section { Text("Only this thread’s follow-up date changes. Notification choices stay as you set them.").font(.footnote).foregroundStyle(Theme.muted) }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("A little later").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.updateThread(personID: target.personID, noteID: target.id, followUp: date) { dismiss() } }.buttonStyle(.automatic).accessibilityIdentifier("save-thread-date") }
                }
        }
    }
}
