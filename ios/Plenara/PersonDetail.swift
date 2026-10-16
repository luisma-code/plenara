import SwiftUI

struct PersonDetail: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @Environment(\.dynamicTypeSize) var typeSize
    var id: UUID
    @State private var editing = false
    @State private var rhythm = false
    @State private var logging = false
    @State private var reach = false
    @State private var deleting = false
    @State private var showArchived = false
    @State private var editingMemory: Memory?
    @State private var editingMoment: Moment?
    @State private var addMemory = false
    @State private var deepenSuggestion = false
    @State private var contactError = false
    var person: Person? { store.journal.people.first { $0.id == id } }
    var body: some View {
        Group {
            if let p = person {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { Button { dismiss() } label: { Label(typeSize.isAccessibilitySize ? "Back" : "Your people", systemImage: "chevron.left").font(.subheadline).frame(minHeight: 44) }; Spacer(); Button("Edit") { editing = true }.frame(minHeight: 44) }
                        header(p)
                        HStack { ActionButton(title: "Log a moment") { logging = true }; ActionButton(title: "Reach out", icon: "message", primary: false) { reach = true } }
                        catchUp(p)
                        rhythmCard(p)
                        HStack { Text("Little things to remember").font(Theme.title(25)); Spacer(); Button { addMemory = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Add a note") }
                        memories(p)
                        Text("Time together").font(Theme.title(25))
                        if store.journal.history(p.id).isEmpty { Text("Your calls, coffees, and little hellos will collect here.").foregroundStyle(Theme.muted) }
                        ForEach(store.journal.history(p.id)) { m in Button { editingMoment = m } label: { MomentRow(moment: m, name: nil) }.buttonStyle(.plain).accessibilityIdentifier("moment-row") }
                        Button("Remove this person", role: .destructive) { deleting = true }.font(.footnote).frame(minHeight: 44).frame(maxWidth: .infinity).padding(.top)
                    }.padding(24)
                }
                .sheet(isPresented: $editing) { PersonEditor(person: p) }
                .sheet(isPresented: $rhythm) { RhythmEditor(person: p) }
                .sheet(isPresented: $logging) { MomentEditor(personID: p.id) }
                .sheet(isPresented: $addMemory) { MemoryEditor(personID: p.id, memory: Memory()) }
                .sheet(item: $editingMemory) { MemoryEditor(personID: p.id, memory: $0) }
                .sheet(item: $editingMoment) { MomentEditor(personID: p.id, moment: $0) }
                .confirmationDialog("Reach out to \(p.name)", isPresented: $reach, titleVisibility: .visible) {
                    ForEach(p.phones, id: \.self) { phone in
                        Button("Message \(phone)") { contact("sms", phone) }
                        Button("Call \(phone)") { contact("tel", phone) }
                        Button("FaceTime \(phone)") { contact("facetime", phone) }
                    }
                    ForEach(p.emails, id: \.self) { email in Button("Email \(email)") { contact("mailto", email) } }
                    Button("Edit contact methods") { editing = true }
                    Button("Cancel", role: .cancel) { }
                } message: { Text(p.phones.isEmpty && p.emails.isEmpty ? "Add a phone number or email to reach out." : "Preferred: \(p.preferredMethod). Opening a contact method won’t mark a connection. Log it when you’ve caught up.") }
                .confirmationDialog("Remove \(p.name)?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Remove person and journal", role: .destructive) { store.deletePerson(p.id); if store.errorMessage == nil { dismiss() } }
                    Button("Cancel", role: .cancel) { }
                } message: { Text("This removes their notes and moments from Plenara. Their phone contact is untouched. Export a backup first to keep a copy.") }
                .confirmationDialog("Make a little more room?", isPresented: $deepenSuggestion, titleVisibility: .visible) {
                    Button("Adjust contact rhythm") { rhythm = true }
                    Button("Keep my rhythm", role: .cancel) { }
                } message: { Text("You can choose a shorter rhythm for this relationship. Your current rhythm hasn’t changed.") }
            } else { QuietEmpty(title: "This person was removed.", message: "Your other relationships are still here.").padding() }
        }.background(Theme.paper).toolbar(.hidden, for: .navigationBar)
            .alert("Contact method unavailable", isPresented: $contactError) { Button("OK") {} } message: { Text("This device couldn’t open that app. You can copy the number or email from Edit.") }
    }
    func header(_ p: Person) -> some View {
        VStack(spacing: 14) {
            Avatar(person: p, size: 88)
            Text(p.name).font(Theme.title(38)).multilineTextAlignment(.center)
            if !p.pronunciation.isEmpty { Text(p.pronunciation).font(.subheadline).foregroundStyle(Theme.muted) }
            if !p.relationshipDetail.isEmpty { Text(p.relationshipDetail).font(.subheadline).foregroundStyle(Theme.muted) }
            Text(location(p)).font(.subheadline).foregroundStyle(Theme.muted)
            if let birthday = birthdayText(p) { Text("Birthday · \(birthday)").font(.subheadline).foregroundStyle(Theme.muted).accessibilityIdentifier("birthday-info") }
            if p.relationship == "Not set" && p.closeness == "Not set" && p.distance == "Not set" {
                Button("Add relationship details") { editing = true }.font(.subheadline).frame(minHeight: 44)
            } else { ViewThatFits { HStack { relationshipTags(p) }; VStack { relationshipTags(p) } } }
            Button {
                var changed = p; changed.deepen.toggle(); if store.save(changed) && changed.deepen { deepenSuggestion = true }
            } label: { Label(p.deepen ? "A relationship I want to deepen" : "I’d like to deepen this", systemImage: "leaf").font(.subheadline).padding(13).frame(minHeight: 44).background(Theme.lavender, in: RoundedRectangle(cornerRadius: 15)) }.accessibilityIdentifier("deepen-toggle").accessibilityValue(p.deepen ? "On" : "Off")
            if !p.intention.isEmpty { Text(p.intention).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity)
    }
    func birthdayText(_ p: Person) -> String? {
        guard p.birthdayMonth > 0, p.birthdayDay > 0, let date = Calendar.current.date(from: DateComponents(year: 2024, month: p.birthdayMonth, day: p.birthdayDay, hour: 12)) else { return nil }
        return date.formatted(.dateTime.month(.wide).day())
    }
    func location(_ p: Person) -> String {
        var parts = [p.city].filter { !$0.isEmpty }
        if let zone = TimeZone(identifier: p.timeZone) { let f = DateFormatter(); f.timeZone = zone; f.timeStyle = .short; parts.append(f.string(from: Date())) }
        return parts.isEmpty ? "A place in your life" : parts.joined(separator: " · ")
    }
    @ViewBuilder func relationshipTags(_ p: Person) -> some View {
        if p.relationship != "Not set" { tag(p.relationship) }
        if p.closeness != "Not set" { tag(p.closeness) }
        if p.distance != "Not set" { tag(p.distance) }
    }
    func tag(_ text: String) -> some View { Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 7).background(Theme.line.opacity(0.65), in: Capsule()) }
    func catchUp(_ p: Person) -> some View {
        let note = p.notes.first(where: { $0.pinned && !$0.archived }) ?? p.notes.first(where: { !$0.archived && $0.category == "On their mind" })
        return Surface(color: Theme.peach) { VStack(alignment: .leading, spacing: 13) {
            Eyebrow(text: "Before you catch up")
            Text("A thread to pick up.").font(Theme.title(26))
            Text(note?.text ?? "Something they’re looking forward to, a question to revisit, an idea for your next time together.").lineSpacing(4)
            if let note { Text("Noted \(note.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.muted) }
            Button("Add a reminder for next time →") { addMemory = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        } }
    }
    func rhythmCard(_ p: Person) -> some View {
        Surface { VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Your rhythm").font(Theme.title(25)); Spacer(); Button("Adjust") { rhythm = true }.frame(minHeight: 44) }
            Label(p.paused ? "Reminders paused" : rhythmLabel(p.cadence), systemImage: "heart").font(.body)
            Text(connectionLabel(p, journal: store.journal)).font(.subheadline).foregroundStyle(Theme.muted).accessibilityIdentifier("last-connection")
            if let outreach = store.journal.lastOutreach(p), outreach > (store.journal.lastConnection(p) ?? .distantPast), store.journal.daysSince(outreach) < 7 { Text("You reached out recently. A little space for a reply.").font(.footnote).foregroundStyle(Theme.muted) }
            if let snooze = p.snoozeUntil, snooze > Date() { Text("Snoozed until \(snooze.formatted(date: .abbreviated, time: .omitted))").font(.footnote); Button("End snooze") { var c = p; c.snoozeUntil = nil; store.save(c) }.frame(minHeight: 44) }
        } }
    }
    func memories(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            let visible = p.notes.filter { showArchived || !$0.archived }.sorted { if $0.pinned != $1.pinned { return $0.pinned }; return $0.date > $1.date }
            if visible.isEmpty { Text("Their people, favourite places, what’s going on. Keep the little things here.").foregroundStyle(Theme.muted) }
            ForEach(visible) { n in Button { editingMemory = n } label: { VStack(alignment: .leading, spacing: 9) {
                HStack { Eyebrow(text: n.category); Spacer(); if n.pinned { Image(systemName: "pin.fill").font(.caption).accessibilityLabel("Pinned") }; if n.archived { Text("Archived").font(.caption) } }
                Text(n.text).frame(maxWidth: .infinity, alignment: .leading).lineSpacing(4)
                Text("Noted \(n.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.muted)
                if let due = n.followUp { Text("Follow up \(due.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.plum) }
                Divider().overlay(Theme.line)
            } }.buttonStyle(.plain).accessibilityIdentifier("memory-row") }
            if p.notes.contains(where: \.archived) { Button(showArchived ? "Hide archived notes" : "Show archived notes") { showArchived.toggle() }.font(.footnote).frame(minHeight: 44) }
        }
    }
    func contact(_ scheme: String, _ raw: String) {
        let value = scheme == "mailto" ? raw : raw.filter { $0.isNumber || $0 == "+" }
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "\(scheme):\(encoded)") else { contactError = true; return }
        openURL(url) { accepted in if !accepted { contactError = true } }
    }
}
struct MomentRow: View {
    var moment: Moment
    var name: String?
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: moment.connected ? "heart" : "message").frame(width: 36, height: 36).background(Theme.lavender, in: Circle()).foregroundStyle(Theme.plum)
            VStack(alignment: .leading, spacing: 6) {
                Text([name, moment.channel].compactMap { $0 }.joined(separator: " · ")).font(.subheadline.weight(.semibold))
                Text("\(moment.date.formatted(date: .abbreviated, time: .omitted)) · \(moment.connected ? "Connected" : "Reached out")").font(.caption).foregroundStyle(Theme.muted)
                if !moment.note.isEmpty { Text(moment.note).font(.body).lineSpacing(3) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6)
    }
}
struct MomentsView: View {
    @EnvironmentObject var store: JournalStore
    @State private var selecting = false
        @State private var editing: Moment?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 25) {
            HStack { Eyebrow(text: "A little history"); Spacer(); Button { selecting = true } label: { Image(systemName: "plus").frame(width: 46, height: 46).overlay(Circle().stroke(Theme.line)) }.accessibilityLabel("Log a moment").disabled(store.journal.people.isEmpty) }
            Text("Time well spent.").font(Theme.title()).tracking(-1.3)
            Text("The calls, coffees, and little hellos\nthat make a life together.").foregroundStyle(Theme.muted).lineSpacing(4)
            Divider()
            if store.journal.moments.isEmpty { QuietEmpty(title: "A little history starts here.", message: "After a call, a coffee, or a proper catch-up, keep a moment to remember.") }
            ForEach(store.journal.history()) { m in VStack(alignment: .leading, spacing: 3) {
                Button { editing = m } label: { MomentRow(moment: m, name: store.journal.people.first { $0.id == m.personID }?.name) }.buttonStyle(.plain)
                NavigationLink(value: m.personID) { Text("View person →").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }.padding(.leading, 50)
            } }
        }.padding(24) }.sheet(isPresented: $selecting) {
            LogMomentFlow()
        }.sheet(item: $editing) { MomentEditor(personID: $0.personID, moment: $0) }
    }
}

struct LogMomentFlow: View {
    @EnvironmentObject var store: JournalStore
    @State private var selectedID: UUID?
    var body: some View {
        if let selectedID { MomentEditor(personID: selectedID) }
        else { NavigationStack { List(store.journal.people.sorted { $0.name < $1.name }) { p in Button(p.name) { selectedID = p.id } }.navigationTitle("Who was it with?").toolbar { DismissButton() } } }
    }
}
