import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @EnvironmentObject var store: JournalStore
    @EnvironmentObject var notifications: NotificationManager
    @Environment(\.openURL) var openURL
    @State private var preferences = Preferences()
    @State private var exporting = false
    @State private var exportFilename = "Plenara backup.json"
    @State private var textExport = false
    @State private var document = BackupDocument(data: Data())
    @State private var importing = false
    @State private var pendingRestore: Data?
    @State private var restoreName = ""
    @State private var confirmRestore = false
    @State private var statusMessage: String?
    var digestTime: Binding<Date> { Binding(get: { Calendar.current.date(from: DateComponents(hour: preferences.hour, minute: preferences.minute)) ?? Date() }, set: { preferences.hour = Calendar.current.component(.hour, from: $0); preferences.minute = Calendar.current.component(.minute, from: $0) }) }
    func backupName(readable: Bool) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Plenara \(readable ? "journal" : "backup") \(formatter.string(from: Date())).\(readable ? "txt" : "json")"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("A little attention, at your own pace.").font(Theme.title(27)); Text("Your journal stays on this iPhone. No account, subscription, or message monitoring.").foregroundStyle(Theme.muted) }
                Section {
                    Toggle("Gentle reminders", isOn: Binding(get: { preferences.notifications }, set: { enabled in
                        if enabled { Task { if await notifications.request() { preferences.notifications = true } else { statusMessage = "Notifications are off in iPhone Settings. Your in-app reminders still work." } } }
                        else { preferences.notifications = false }
                    })).accessibilityIdentifier("notifications-toggle")
                    if preferences.notifications {
                        if notifications.weeklyReady { Text("Your weekly reminder is ready.").font(.footnote).foregroundStyle(Theme.plum) }
                        Picker("Weekly digest", selection: $preferences.weekday) { ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) } }
                        DatePicker("At", selection: digestTime, displayedComponents: .hourAndMinute)
                        Toggle("Birthday reminders", isOn: $preferences.birthdays)
                        Toggle("Dated follow-up reminders", isOn: $preferences.followUps)
                        Picker("Quiet hours start", selection: $preferences.quietStart) { ForEach(0...23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                        Picker("Quiet hours end", selection: $preferences.quietEnd) { ForEach(0...23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                        Text("A time inside quiet hours uses the hour when they end. Lock-screen reminders don’t include names or personal notes.").font(.footnote).foregroundStyle(Theme.muted)
                        Text("Up to 48 upcoming reminders are scheduled. Open Plenara periodically to refresh dated reminders.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    if notifications.status == .denied { Button("Open iPhone notification settings") { if let u = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(u) } } }
                    if let message = notifications.message { Text(message).font(.footnote).foregroundStyle(.red) }
                } header: { Text("Gentle reminders") } footer: { Text("Connection reminders use your chosen rhythm. A weekly notification simply invites you back to your people.") }
                Section {
                    Button("Export a restorable backup") { do { document = BackupDocument(data: try store.exportData()); textExport = false; exportFilename = backupName(readable: false); exporting = true } catch { statusMessage = error.localizedDescription } }
                    Button("Export a readable journal") { document = BackupDocument(data: Data(store.exportText().utf8)); textExport = true; exportFilename = backupName(readable: true); exporting = true }.disabled(store.locked)
                    Button("Restore from a backup") { importing = true }
                    if FileManager.default.fileExists(atPath: store.file.appendingPathExtension("previous").path) {
                        Button("Recover previous local save") {
                            do { let bytes = try Data(contentsOf: store.file.appendingPathExtension("previous")); let previous = try JournalStore.readJournal(bytes); pendingRestore = bytes; restoreName = "\(previous.people.count) people and \(previous.moments.count) moments from the previous local save"; confirmRestore = true }
                            catch { statusMessage = "The previous save couldn’t be opened. Please restore an exported backup." }
                        }
                    }
                    if FileManager.default.fileExists(atPath: store.beforeRelationshipUpdate.path) {
                        Button("Recover before relationship update") {
                            do {
                                let bytes = try Data(contentsOf: store.beforeRelationshipUpdate)
                                let previous = try JournalStore.readJournal(bytes)
                                pendingRestore = bytes; restoreName = "\(previous.people.count) people and \(previous.moments.count) moments from before the relationship update"; confirmRestore = true
                            } catch { statusMessage = "The before-update backup couldn’t be opened. Your current journal is untouched." }
                        }
                    }
                    Text("Save the backup somewhere you trust, such as your private iCloud Drive. Backups include your personal notes and contact details. A readable journal is for reading; the JSON backup is for restoring.").font(.footnote).foregroundStyle(Theme.muted)
                    if store.locked { Text("Your journal couldn’t be opened and remains protected. Restore a backup to resume editing.").foregroundStyle(.red) }
                } header: { Text("Keep your memories safe") } footer: { Text("On-device storage is not sync. Removing the app can remove the journal. Export regularly, and before changing phones.") }
                if let statusMessage { Section { Text(statusMessage).font(.footnote).accessibilityIdentifier("settings-status") } }
                if let error = store.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                Section { Text("Plenara 1.0 · A little closer").font(.footnote).foregroundStyle(Theme.muted) }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("Your space").navigationBarTitleDisplayMode(.inline).toolbar { DismissButton() }
                .onAppear { preferences = store.journal.preferences }
                .onChange(of: preferences) { old, value in
                    guard value != store.journal.preferences else { return }
                    guard value.quietStart != value.quietEnd else { statusMessage = "Choose different start and end hours for quiet hours."; preferences = old; return }
                    if !store.update({ $0.preferences = value }) { preferences = old }
                }
                .fileExporter(isPresented: $exporting, document: document, contentType: textExport ? .plainText : .json, defaultFilename: exportFilename) { result in switch result { case .success: statusMessage = "Your export was saved."; case .failure(let error): statusMessage = "Export couldn’t finish. \(error.localizedDescription)" } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size < 50_000_000 else { throw JournalError.invalidBackup }
                        let bytes = try Data(contentsOf: url); let loaded = try JournalStore.readJournal(bytes)
                        pendingRestore = bytes; restoreName = "\(loaded.people.count) people and \(loaded.moments.count) moments"; confirmRestore = true
                    } catch { statusMessage = "That backup couldn’t be opened. Your current journal is untouched. \(error.localizedDescription)" }
                }
                .confirmationDialog("Replace your journal?", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button("Replace with backup", role: .destructive) { if let bytes = pendingRestore, store.restore(bytes) { preferences = store.journal.preferences; statusMessage = "Restored \(restoreName)." }; pendingRestore = nil }
                    Button("Cancel", role: .cancel) { pendingRestore = nil }
                } message: { Text("This backup contains \(restoreName). It will replace the people, notes, moments, and settings on this iPhone. Export your current journal first to keep a copy.") }
        }
    }
}
