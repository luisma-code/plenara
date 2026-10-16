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
        }
        #endif
        let s = JournalStore(file: url)
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--demo"), s.journal.people.isEmpty { s.update { $0 = DemoData.journal() } }
        if ProcessInfo.processInfo.arguments.contains("--contact-fixture") { DemoData.seedSystemContact() }
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
            RootView().buttonStyle(ComfortableButtonStyle()).preferredColorScheme(simulatorAppearance).environmentObject(store).environmentObject(notifications).tint(Theme.plum).foregroundStyle(Theme.ink)
                .task { await notifications.refresh(store.journal) }
                .onChange(of: store.journal) { _, j in Task { await notifications.refresh(j) } }
                .onChange(of: phase) { _, value in if value == .active { Task { await notifications.refresh(store.journal) } } }
                .alert("Your journal", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        }
    }
}
struct RootView: View {
    @State private var tab = 0
    @State private var path: [UUID] = []
    @State private var settings = false
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab { case 0: HomeView(openSettings: { settings = true }); case 1: PeopleView(); default: MomentsView() }
            }
            .background(Theme.paper).toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { PersonDetail(id: $0) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 0) {
                    tabButton("Stay close", icon: "heart", index: 0)
                    tabButton("People", icon: "person.2", index: 1)
                    tabButton("Moments", icon: "clock.arrow.circlepath", index: 2)
                }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.top, 8).background(Theme.paper).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            }
        .sheet(isPresented: $settings) { SettingsView() }
    }
    func tabButton(_ name: String, icon: String, index: Int) -> some View {
        Button { path = []; tab = index } label: {
            VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 23, weight: tab == index ? .semibold : .regular)); Text(name).font(.caption2.weight(tab == index ? .semibold : .regular)) }.frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(tab == index ? Theme.plum : Theme.muted).accessibilityIdentifier("tab-\(index)").accessibilityAddTraits(tab == index ? .isSelected : [])
    }
}
