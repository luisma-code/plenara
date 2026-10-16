import SwiftUI
import PhotosUI
import ImageIO

struct PersonEditor: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    @State var person: Person
    @State private var birthday = Date()
    @State private var hasBirthday = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var photoError: String?
    @State private var choosingZone = false
    var valid: Bool { !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (person.timeZone.isEmpty || TimeZone(identifier: person.timeZone) != nil) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); Avatar(person: person, size: 84); Spacer() }.listRowBackground(Color.clear)
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose a photo", systemImage: "photo") }
                    if photoLoading { Text("Loading photo…").font(.footnote).foregroundStyle(Theme.muted) }
                    if person.photo != nil { Button("Remove photo", role: .destructive) { photoItem = nil; person.photo = nil } }
                    TextField("Name", text: $person.name).accessibilityIdentifier("person-name")
                    TextField("Pronunciation (optional)", text: $person.pronunciation)
                }
                Section("Your relationship") {
                    Picker("Relationship", selection: $person.relationship) { ForEach(["Not set", "Friend", "Family"], id: \.self) { Text($0) } }
                    TextField("Cousin, university friend…", text: $person.relationshipDetail)
                    Picker("Closeness", selection: $person.closeness) { ForEach(Person.closenessOptions, id: \.self) { Text($0) } }
                    Toggle("I want to deepen this", isOn: $person.deepen)
                    TextField("What I’d like to grow (optional)", text: $person.intention, axis: .vertical)
                }
                Section { TextField("City or area", text: $person.city)
                    Picker("Near or far?", selection: $person.distance) { ForEach(["Not set", "Local", "Far away"], id: \.self) { Text($0) } }
                    Button { choosingZone = true } label: { HStack { Text("Local time zone"); Spacer(); Text(zoneLabel(person.timeZone)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing) } }
                } header: { Text("Their place in the world") } footer: { Text("You decide what local means. No location tracking.") }
                Section("Reach out") {
                    TextField("Phone numbers, one per line", text: Binding(get: { person.phones.joined(separator: "\n") }, set: { person.phones = $0.components(separatedBy: "\n") }), axis: .vertical).keyboardType(.phonePad)
                    TextField("Email addresses, one per line", text: Binding(get: { person.emails.joined(separator: "\n") }, set: { person.emails = $0.components(separatedBy: "\n") }), axis: .vertical).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Preferred way", selection: $person.preferredMethod) { ForEach(["Message", "Call", "Email", "FaceTime", "Voice note"], id: \.self) { Text($0) } }
                    if person.sourceContactID != nil {
                        Text("Linked to a selected phone contact. Reimport to review and refresh contact fields.").font(.footnote).foregroundStyle(Theme.muted)
                        Button("Unlink and keep my journal") { person.sourceContactID = nil }
                        Button("Remove imported contact fields", role: .destructive) { person.sourceContactID = nil; person.phones = []; person.emails = []; person.photo = nil; person.city = ""; person.birthdayMonth = 0; person.birthdayDay = 0; hasBirthday = false }
                    }
                }
                Section("Important dates") {
                    Toggle("Keep their birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                        Text("Only the month and day are kept.").font(.caption).foregroundStyle(Theme.muted)
                        Toggle("Birthday reminder", isOn: $person.birthdayReminder)
                    }
                    Text("Keep other important dates as dated notes on their page.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section {
                    Picker("Contact rhythm", selection: $person.cadence) {
                        ForEach(Array(Set([0, 3, 7, 14, 21, 30, 60, 90, person.cadence])).sorted(), id: \.self) { Text(rhythmLabel($0)).tag($0) }
                    }
                    let suggested = Person.suggestedCadence(person.closeness, deepen: person.deepen)
                    if suggested > 0 && suggested != person.cadence { Button("Use suggestion: \(rhythmLabel(suggested).lowercased())") { person.cadence = suggested } }
                    if person.cadence > 0 && person.baselineConnection == nil && store.journal.lastConnection(person) == nil { Text("Reminders start from today. This won’t mark a connection. You can set your last contact or a custom rhythm on their page.").font(.footnote).foregroundStyle(Theme.muted) }
                } header: { Text("A gentle rhythm") } footer: { Text("Optional. Importing or adding someone never starts reminders unless you choose a rhythm.") }
            }.scrollContentBackground(.hidden).background(Theme.paper)
                .navigationTitle(store.journal.people.contains(where: { $0.id == person.id }) ? "About \(person.name)" : "Add someone").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(.automatic).disabled(!valid || photoLoading).accessibilityIdentifier("save-person") } }
                .onAppear { if person.birthdayMonth > 0 { hasBirthday = true; birthday = Calendar.current.date(from: DateComponents(year: 2024, month: person.birthdayMonth, day: person.birthdayDay)) ?? Date() } }
                .sheet(isPresented: $choosingZone) { TimeZoneChooser(selection: $person.timeZone) }
                .task(id: photoItem) {
                    guard let item = photoItem else { photoLoading = false; return }
                    photoLoading = true
                    defer { if !Task.isCancelled { photoLoading = false } }
                    do {
                        guard let bytes = try await item.loadTransferable(type: Data.self), !Task.isCancelled else { return }
                        guard bytes.count < 20_000_000, let image = photoThumbnail(bytes) else { photoError = "Please choose a smaller supported image."; return }
                        guard !Task.isCancelled else { return }
                        person.photo = image
                    } catch { if !Task.isCancelled { photoError = "This photo couldn’t be opened." } }
                }
                .alert("Photo", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) { Button("OK") { photoError = nil } } message: { Text(photoError ?? "") }
        }
    }
    func save() {
        person.name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        person.phones = person.phones.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        person.emails = person.emails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if hasBirthday { person.birthdayMonth = Calendar.current.component(.month, from: birthday); person.birthdayDay = Calendar.current.component(.day, from: birthday) }
        else { person.birthdayMonth = 0; person.birthdayDay = 0; person.birthdayReminder = false }
        if person.cadence > 0 && person.reminderStart == nil && store.journal.lastConnection(person) == nil { person.reminderStart = Calendar.current.startOfDay(for: Date()) }
        if store.save(person) { dismiss() }
    }
}
func thumbnail(_ image: UIImage) -> Data? {
    let side: CGFloat = 256
    let ratio = max(side / image.size.width, side / image.size.height)
    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    return renderer.image { _ in image.draw(in: CGRect(x: (side - size.width)/2, y: (side - size.height)/2, width: size.width, height: size.height)) }.jpegData(compressionQuality: 0.8)
}
struct RhythmEditor: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    @State var person: Person
    @State private var hasLast = false
    @State private var last = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("How often would you like to connect with \(person.name)? Choose what feels right for this relationship.").foregroundStyle(Theme.muted) }
                Section("Your rhythm") {
                    Picker("A gentle reminder", selection: $person.cadence) { ForEach(Array(Set([0, 3, 7, 14, 21, 30, 60, 90, person.cadence])).sorted(), id: \.self) { Text(rhythmLabel($0)).tag($0) } }
                    Toggle("Custom rhythm", isOn: Binding(get: { person.cadence > 0 }, set: { person.cadence = $0 ? max(1, person.cadence) : 0 }))
                    if person.cadence > 0 { Stepper("Every \(person.cadence) days", value: $person.cadence, in: 1...3650).accessibilityIdentifier("cadence-stepper") }
                    let suggestion = Person.suggestedCadence(person.closeness, deepen: person.deepen)
                    if suggestion > 0 { Button("Use suggested rhythm: \(rhythmLabel(suggestion).lowercased())") { person.cadence = suggestion } }
                    Toggle("Pause reminders for this person", isOn: $person.paused)
                }
                Section {
                    Toggle("Set an earlier connection", isOn: $hasLast)
                    if hasLast { DatePicker("Last connection", selection: $last, in: ...Date(), displayedComponents: .date); Toggle("This is an approximate date", isOn: $person.baselineApproximate) }
                    Text("Logged moments also count. The latest confirmed connection sets the rhythm.").font(.footnote).foregroundStyle(Theme.muted)
                } header: { Text("A starting point") } footer: { Text("If last contact is unknown, choosing a rhythm starts reminders from today without inventing a connection.") }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("Find your rhythm").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { person.baselineConnection = hasLast ? last : nil; if person.reminderStart == nil { person.reminderStart = Date() }; if store.save(person) { dismiss() } }.buttonStyle(.automatic) } }
                .onAppear { hasLast = person.baselineConnection != nil; last = person.baselineConnection ?? Date() }
        }
    }
}
struct MemoryEditor: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    let personID: UUID
    @State var memory: Memory
    @State private var followUp = false
    @State private var due = Date()
    @State private var deleting = false
    var existing: Bool { store.journal.people.first { $0.id == personID }?.notes.contains { $0.id == memory.id } ?? false }
    var body: some View {
        NavigationStack {
            Form {
                Section("A little thing to remember") {
                    Picker("Keep it under", selection: $memory.category) { ForEach(Memory.categories, id: \.self) { Text($0) } }
                    TextField("Your note", text: $memory.text, axis: .vertical).lineLimit(4...12).accessibilityIdentifier("memory-text")
                    Toggle("Pin for the next catch-up", isOn: $memory.pinned)
                    Toggle("Archived", isOn: $memory.archived)
                }
                Section { Toggle("Follow up on a date", isOn: $followUp); if followUp { DatePicker("Follow-up date", selection: $due, displayedComponents: .date) }; Text("A reminder is scheduled only if follow-up notifications are enabled in Settings.").font(.footnote).foregroundStyle(Theme.muted) }
                if existing { Section { Button("Delete note", role: .destructive) { deleting = true } } }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle(existing ? "Edit a memory" : "Keep a little memory").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(.automatic).disabled(memory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("save-memory") } }
                .onAppear { followUp = memory.followUp != nil; due = memory.followUp ?? Date() }
                .confirmationDialog("Delete this note?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete note", role: .destructive) { if store.update({ j in if let i = j.people.firstIndex(where: { $0.id == personID }) { j.people[i].notes.removeAll { $0.id == memory.id } } }) { dismiss() } } }
        }
    }
    func save() {
        memory.text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines); memory.followUp = followUp ? due : nil
        if store.update({ j in if let i = j.people.firstIndex(where: { $0.id == personID }) { if let n = j.people[i].notes.firstIndex(where: { $0.id == memory.id }) { j.people[i].notes[n] = memory } else { j.people[i].notes.insert(memory, at: 0) } } }) { dismiss() }
    }
}
struct MomentEditor: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    let personID: UUID
    @State var moment: Moment
    @State private var deleting = false
    init(personID: UUID, moment: Moment? = nil) { self.personID = personID; _moment = State(initialValue: moment ?? Moment(personID: personID)) }
    var existing: Bool { store.journal.moments.contains { $0.id == moment.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("A short note is plenty. Remember what mattered.").foregroundStyle(Theme.muted) }
                Section {
                    Picker("How did you connect?", selection: $moment.channel) { ForEach(Moment.channels, id: \.self) { Text($0) } }
                    DatePicker("When?", selection: $moment.date, in: ...Date(), displayedComponents: .date)
                    Picker("What happened?", selection: $moment.connected) { Text("Connected").tag(true); Text("Reached out").tag(false) }.accessibilityIdentifier("moment-status")
                    Text("Only Connected resets your contact rhythm. An unanswered message can stay an outreach, with a little space for a reply.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("Anything to remember?") { TextField("What’s happening in their world?", text: $moment.note, axis: .vertical).lineLimit(3...10).accessibilityIdentifier("moment-note") }
                if existing { Section { Button("Delete moment", role: .destructive) { deleting = true } } }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle(existing ? "Edit a moment" : "A moment together").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { moment.note = moment.note.trimmingCharacters(in: .whitespacesAndNewlines); if store.save(moment) { dismiss() } }.buttonStyle(.automatic).accessibilityIdentifier("save-moment") } }
                .confirmationDialog("Delete this moment?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete moment", role: .destructive) { store.deleteMoment(moment.id); if store.errorMessage == nil { dismiss() } } } message: { Text("Your last connection and reminders will be recalculated from the remaining history.") }
        }
    }
}

func zoneLabel(_ identifier: String) -> String {
    if identifier.isEmpty { return "Not set" }
    return identifier.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? identifier
}
struct TimeZoneChooser: View {
    @Binding var selection: String
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    var choices: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { query.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query) }.sorted { zoneLabel($0) < zoneLabel($1) }
    }
    var body: some View {
        NavigationStack {
            List {
                Button("Not set") { selection = ""; dismiss() }
                Button("Same time zone as me") { selection = TimeZone.current.identifier; dismiss() }
                ForEach(choices, id: \.self) { identifier in
                    Button { selection = identifier; dismiss() } label: {
                        HStack { VStack(alignment: .leading) { Text(zoneLabel(identifier)); Text(identifier.components(separatedBy: "/").dropLast().joined(separator: " · ").replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(Theme.muted) }; Spacer(); if identifier == selection { Image(systemName: "checkmark") } }
                    }
                }
            }.searchable(text: $query, prompt: "Find a city or region").navigationTitle("Their local time").toolbar { DismissButton() }
        }
    }
}

func photoThumbnail(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary) else { return nil }
    return thumbnail(UIImage(cgImage: cg))
}
