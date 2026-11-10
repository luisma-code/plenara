import SwiftUI

@main struct PlenaraApp: App {
    @StateObject private var store: JournalStore
    @StateObject private var notifications = NotificationManager()
    @Environment(\.scenePhase) private var phase
    init() {
        var url: URL? = nil
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") {
            url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UITestJournal/journal.json")
            if args.contains("--reset") { try? FileManager.default.removeItem(at: url!.deletingLastPathComponent()) }
            // A frozen fictional journal from build 1001 is supplied by the UI test bundle.
            // This never reads, replaces, or resets the production journal.
            if args.contains("--legacy-fixture"), let encoded = ProcessInfo.processInfo.environment["PLENARA_LEGACY_JOURNAL"], let bytes = Data(base64Encoded: encoded) {
                try? FileManager.default.createDirectory(at: url!.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? bytes.write(to: url!, options: .atomic)
            }
        }
        #endif
        let s = JournalStore(file: url)
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ranking-demo"), s.journal.people.isEmpty { s.update { $0 = DemoData.rankingJournal() } }
        if ProcessInfo.processInfo.arguments.contains("--demo"), s.journal.people.isEmpty { s.update { $0 = DemoData.journal() } }
        if ProcessInfo.processInfo.arguments.contains("--contact-fixture") { DemoData.seedSystemContact() }
        let workflowArgs = ProcessInfo.processInfo.arguments
        if workflowArgs.contains("--ui-testing"), workflowArgs.contains("--rhythm-demo") {
            s.update { j in
                j.moments = []
                for i in j.people.indices { j.people[i].cadence = j.people[i].name == "Mum" ? 7 : 0; j.people[i].baselineConnection = nil; j.people[i].reminderStart = nil }
            }
        }
        if workflowArgs.contains("--ui-testing"), workflowArgs.contains("--contact-demo") {
            s.update { j in if let i = j.people.firstIndex(where: { $0.name == "Sofia Chen" }) { j.people[i].phones = ["5550100", "5550101"]; j.people[i].emails = ["sofia@example.invalid"]; j.people[i].preferredMethod = "Email" } }
        }
        #endif
        _store = StateObject(wrappedValue: s)
    }
    private var simulatorAppearance: ColorScheme? {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil
        #else
        return nil
        #endif
    }
    var body: some Scene {
        WindowGroup {
            RootView().modifier(ContactHandoffTestBoundary()).buttonStyle(ComfortableButtonStyle()).preferredColorScheme(simulatorAppearance).environmentObject(store).environmentObject(notifications).tint(Theme.plum).foregroundStyle(Theme.ink)
                .task { await notifications.refresh(store.journal) }
                .onChange(of: store.journal) { _, j in Task { await notifications.refresh(j) } }
                .onChange(of: phase) { _, value in if value == .active { Task { await notifications.refresh(store.journal) } } }
                .alert("Your journal", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        }
    }
}
// Replace only the external URL boundary in simulator UI tests. Real scene
// departure/return, confirmation, storage and cancellation still run normally.
struct ContactHandoffTestBoundary: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") && args.contains("--contact-handoff-fixture") {
            content.environment(\.openURL, OpenURLAction { _ in args.contains("--contact-unavailable-fixture") ? .discarded : .handled })
        } else { content }
        #else
        content
        #endif
    }
}
struct RootView: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var path: [UUID] = []
    @State private var settings = false
    @State private var contactReturn = ContactReturnState()
    @State private var returnedDraft: ContactDraft?
    @State private var offeredDraftID: UUID?
    @State private var checkedInitialDraft = false
    @State private var followThroughID: UUID?
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab { case 0: HomeView(openSettings: { settings = true }); case 1: PeopleView(); default: MomentsView() }
            }
            .background(Theme.paper).toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { PersonDetail(id: $0) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                WorkflowFeedbackBar(reviewContact: offerContact, reviewMoment: { followThroughID = $0 })
                HStack(spacing: 0) {
                    tabButton("Stay close", icon: "heart", index: 0)
                    tabButton("People", icon: "person.2", index: 1)
                    tabButton("Moments", icon: "clock.arrow.circlepath", index: 2)
                }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.top, 8).background(Theme.paper).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            }
            }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(item: $returnedDraft, onDismiss: { if let id = offeredDraftID { store.dismissContact(id) }; offeredDraftID = nil }) { ContactReturnView(draft: $0) }
        .sheet(isPresented: Binding(get: { followThroughID != nil }, set: { if !$0 { followThroughID = nil } })) { if let id = followThroughID { FollowThroughView(momentID: id) } }
        .task { if !checkedInitialDraft { checkedInitialDraft = true; if let draft = store.journal.pendingContact { offerContact(draft) } } }
        .onChange(of: phase) { _, value in
            if value == .background { contactReturn.departed(draft: store.journal.pendingContact) }
            if value == .active, let draft = contactReturn.returned(draft: store.journal.pendingContact) { offerContact(draft) }
        }
    }
    private func offerContact(_ draft: ContactDraft) { offeredDraftID = draft.id; returnedDraft = draft }
    func tabButton(_ name: String, icon: String, index: Int) -> some View {
        Button { path = []; tab = index } label: {
            VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 23, weight: tab == index ? .semibold : .regular)); Text(name).font(.caption2.weight(tab == index ? .semibold : .regular)) }.frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(tab == index ? Theme.plum : Theme.muted).accessibilityIdentifier("tab-\(index)").accessibilityAddTraits(tab == index ? .isSelected : [])
    }
}
