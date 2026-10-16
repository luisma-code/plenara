import SwiftUI
import Contacts
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    var selected: ([Person]) -> Void
    var cancelled: () -> Void
    func makeUIViewController(context: Context) -> ContactPickerHost {
        let host = ContactPickerHost(); host.selected = selected; host.cancelled = cancelled; return host
    }
    func updateUIViewController(_ uiViewController: ContactPickerHost, context: Context) { }
}
// The picker dismisses itself. Its own host keeps that dismissal from also
// dismissing SwiftUI's import-review sheet; report completion after it returns.
final class ContactPickerHost: UIViewController, CNContactPickerDelegate {
    var selected: (([Person]) -> Void)?
    var cancelled: (() -> Void)?
    private var presentedPicker = false
    private var finished = false
    private var result: [Person]?
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .systemBackground }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !presentedPicker {
            presentedPicker = true
            let picker = CNContactPickerViewController(); picker.delegate = self; picker.modalPresentationStyle = .fullScreen
            picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey, CNContactBirthdayKey]
            present(picker, animated: true)
        } else if !finished {
            finished = true
            if let result { selected?(result) } else { cancelled?() }
        }
    }
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) { result = nil }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) { result = contacts.map(ContactImport.person) }
}

enum ContactImport {
    static func person(_ c: CNContact) -> Person {
        var p = Person()
        p.name = CNContactFormatter.string(from: c, style: .fullName) ?? ""
        if p.name.isEmpty { p.name = c.isKeyAvailable(CNContactOrganizationNameKey) && !c.organizationName.isEmpty ? c.organizationName : "Unnamed contact" }
        p.sourceContactID = c.identifier
        if c.isKeyAvailable(CNContactPhoneNumbersKey) { p.phones = c.phoneNumbers.map { $0.value.stringValue } }
        if c.isKeyAvailable(CNContactEmailAddressesKey) { p.emails = c.emailAddresses.map { String($0.value) } }
        if c.isKeyAvailable(CNContactPostalAddressesKey) { p.city = c.postalAddresses.first?.value.city ?? "" }
        if c.isKeyAvailable(CNContactBirthdayKey), let b = c.birthday { p.birthdayMonth = b.month ?? 0; p.birthdayDay = b.day ?? 0 }
        if c.isKeyAvailable(CNContactThumbnailImageDataKey), let bytes = c.thumbnailImageData, let image = UIImage(data: bytes) { p.photo = thumbnail(image) }
        return p
    }
    static func existing(_ candidate: Person, in people: [Person]) -> Person? {
        if let id = candidate.sourceContactID, let exact = people.first(where: { $0.sourceContactID == id }) { return exact }
        // One-time selections can have different IDs when broad access is denied.
        // Recognize only one previously imported, otherwise identical contact.
        func normalizedName(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        func phones(_ p: Person) -> Set<String> { Set(p.phones.map { $0.filter(\.isNumber) }.filter { !$0.isEmpty }) }
        func emails(_ p: Person) -> Set<String> { Set(p.emails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }) }
        let phoneSet = phones(candidate), emailSet = emails(candidate)
        guard !phoneSet.isEmpty || !emailSet.isEmpty else { return nil }
        let matches = people.filter { $0.sourceContactID != nil && normalizedName($0.name) == normalizedName(candidate.name) && phones($0) == phoneSet && emails($0) == emailSet && normalizedName($0.city) == normalizedName(candidate.city) && $0.birthdayMonth == candidate.birthdayMonth && $0.birthdayDay == candidate.birthdayDay && $0.photo == candidate.photo }
        return matches.count == 1 ? matches[0] : nil
    }
    static func possibleMatches(_ c: Person, in people: [Person]) -> [Person] {
        let phones = Set(c.phones.map { $0.filter(\.isNumber) }.filter { !$0.isEmpty }); let emails = Set(c.emails.map { $0.lowercased() })
        return people.filter { $0.name.localizedCaseInsensitiveCompare(c.name) == .orderedSame || !phones.isDisjoint(with: $0.phones.map { $0.filter(\.isNumber) }) || !emails.isDisjoint(with: $0.emails.map { $0.lowercased() }) }
    }
    static func apply(_ c: Person, to id: UUID?, forceNew: Bool = false, journal: inout Journal) {
        let existingID = forceNew ? nil : (id ?? existing(c, in: journal.people)?.id)
        if let id = existingID, let i = journal.people.firstIndex(where: { $0.id == id }) {
            journal.people[i].name = c.name
            journal.people[i].phones = c.phones; journal.people[i].emails = c.emails
            journal.people[i].photo = c.photo; journal.people[i].city = c.city
            journal.people[i].birthdayMonth = c.birthdayMonth; journal.people[i].birthdayDay = c.birthdayDay
            journal.people[i].sourceContactID = c.sourceContactID
        } else { journal.people.append(c) }
    }
}
struct ImportContactsView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) var dismiss
    @State private var picking = false
    @State private var candidates: [Person] = []
    @State private var selection: Set<UUID> = []
    @State private var links: [UUID: UUID] = [:]
    @State private var separatePeople: Set<UUID> = []
    @State private var imported = false
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "Your circle", title: candidates.isEmpty ? "Choose your\npeople." : "A little closer.", subtitle: candidates.isEmpty ? "Select a few people from your contacts. You decide who comes into Plenara." : "Review the people you’ve chosen. You can set closeness and a rhythm on their page later.")
                if candidates.isEmpty {
                    ActionButton(title: "Choose from Contacts", icon: "person.crop.circle.badge.plus") { picking = true }
                    Text("Apple’s picker shares only the contacts you select. It works without full address-book access, including when broader access is denied.").font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    Text("\(selection.count) selected").font(.subheadline).foregroundStyle(Theme.muted)
                    ForEach(candidates) { c in candidateRow(c) }
                    Text("Selected existing people have their name, phone, email, photo, city, and birthday refreshed from the contact shown above. Your notes, moments, intentions, time zone, and rhythm stay yours.").font(.footnote).foregroundStyle(Theme.muted)
                    ActionButton(title: "Import selected people", icon: "checkmark") {
                        if store.update({ j in for c in candidates where selection.contains(c.id) { ContactImport.apply(c, to: links[c.id], forceNew: separatePeople.contains(c.id), journal: &j) } }) { imported = true }
                    }.disabled(selection.isEmpty || candidates.contains { selection.contains($0.id) && !ready($0) })
                    Button("Choose different contacts") { picking = true }.frame(minHeight: 44)
                }
            }.padding(24) }.background(Theme.paper).navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
                .sheet(isPresented: $picking) { ContactPicker(selected: { people in candidates = people; selection = Set(people.filter { ContactImport.existing($0, in: store.journal.people) == nil && ContactImport.possibleMatches($0, in: store.journal.people).isEmpty }.map(\.id)); links = [:]; separatePeople = []; picking = false }, cancelled: { picking = false }) }
                .alert("Your people are here", isPresented: $imported) { Button("Done") { dismiss() } } message: { Text("Set a rhythm whenever you’re ready. No reminders were started by importing.") }
        }
    }
    func ready(_ c: Person) -> Bool {
        ContactImport.existing(c, in: store.journal.people) != nil || ContactImport.possibleMatches(c, in: store.journal.people).isEmpty || links[c.id] != nil || separatePeople.contains(c.id)
    }
    func candidateRow(_ c: Person) -> some View {
        let existing = ContactImport.existing(c, in: store.journal.people)
        let possible = ContactImport.possibleMatches(c, in: store.journal.people)
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { selection.contains(c.id) }, set: { if $0 { selection.insert(c.id) } else { selection.remove(c.id) } })) { HStack { Avatar(person: c); Text(c.name).font(.headline) } }
                Text(([c.city] + c.phones + c.emails).filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.muted)
                if let existing { Text("Already added as \(existing.name). Select to refresh contact details.").font(.footnote) }
                else if !possible.isEmpty {
                    if !possible.isEmpty { Text("This may already be someone in your journal. Choose a link below, or keep a separate person.").font(.footnote).foregroundStyle(Theme.plum) }
                    Picker("Import as", selection: Binding<String>(get: { links[c.id]?.uuidString ?? (separatePeople.contains(c.id) ? "new" : "choose") }, set: { value in
                        links[c.id] = UUID(uuidString: value)
                        if value == "new" { separatePeople.insert(c.id) } else { separatePeople.remove(c.id) }
                    })) {
                        Text("Choose how to add").tag("choose")
                        Text("A separate new person").tag("new")
                        ForEach(store.journal.people.sorted { $0.name < $1.name }) { p in Text("Link to \(p.name)").tag(p.id.uuidString) }
                    }
                }
            }
        }
    }
}
