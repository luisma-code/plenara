import SwiftUI

// A separate construction seam keeps Home's declarative tree bounded.
struct ReconnectionSection: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let ranked: [Person]
    @Binding var showingAllSuggestions: Bool
    var logMoment: (Person) -> Void
    var body: some View {
        let suggestions = Array(ranked.prefix(3))
        VStack(alignment: .leading, spacing: 24) {
            Text("Time to connect").font(Theme.title(25))
            if let featured = suggestions.first {
                hero(featured)
                ForEach(Array(suggestions.dropFirst())) { p in suggestionRow(p) }
                if ranked.count > 3 {
                    Button(showingAllSuggestions ? "Show fewer suggestions" : "See everyone ready to reconnect (\(ranked.count))") { showingAllSuggestions.toggle() }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("suggestions-expand")
                        .accessibilityValue(showingAllSuggestions ? "Expanded" : "Collapsed")
                    if showingAllSuggestions {
                        LazyVStack(alignment: .leading, spacing: 16) { ForEach(Array(ranked.dropFirst(3))) { p in suggestionRow(p) } }
                    }
                }
            } else {
                QuietEmpty(title: "Room to breathe.", message: "No one is due for a reminder. There’s always room for a hello just because.")
            }
        }
    }
    func suggestionRow(_ p: Person) -> some View {
        NavigationLink(value: p.id) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Avatar(person: p, size: 42); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted) }
                    Text(p.name).font(.headline)
                    Text(suggestionReason(p, journal: store.journal)).font(.subheadline).foregroundStyle(Theme.muted)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 21))
                    .overlay(RoundedRectangle(cornerRadius: 21).stroke(Theme.line)).contentShape(Rectangle())
            } else {
                PersonRow(person: p, detail: suggestionReason(p, journal: store.journal))
            }
        }.buttonStyle(.plain).accessibilityIdentifier("suggestion-\(p.name)")
    }
    func hero(_ p: Person) -> some View {
        Surface(color: Theme.lavender) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Avatar(person: p, size: 68); Spacer()
                    VStack(alignment: .trailing, spacing: 7) {
                        if p.wantsToGrow { Label("Grow closer", systemImage: "leaf").font(.caption.weight(.semibold)).padding(9).background(Theme.card.opacity(0.75), in: Capsule()) }
                        if p.feelingChoice == "Needs care" { Label("Needs care", systemImage: "heart").font(.caption.weight(.semibold)).padding(9).background(Theme.card.opacity(0.75), in: Capsule()) }
                    }
                }
                NavigationLink(value: p.id) { Text(p.name).font(Theme.title(32)).multilineTextAlignment(.leading).frame(minHeight: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("suggestion-hero-\(p.name)")
                Text([p.city, suggestionReason(p, journal: store.journal)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.muted).accessibilityIdentifier("suggestion-reason-\(p.name)")
                Text(p.notes.first(where: { !$0.archived && $0.pinned })?.text ?? p.notes.first(where: { !$0.archived })?.text ?? (p.distance == "Nearby" ? "Maybe a walk or coffee, and a little time together." : "A call or a voice note can make the distance feel smaller."))
                ViewThatFits(in: .horizontal) {
                    HStack { heroLog(p); heroNotes(p) }
                    VStack { heroLog(p); heroNotes(p) }
                }
                Button("Another week") {
                    var changed = p; changed.snoozeUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date()); store.save(changed)
                }.font(.footnote).underline().foregroundStyle(Theme.muted).frame(minHeight: 44)
            }
        }.overlay(alignment: .topTrailing) { PetalMotif().offset(x: 32, y: 38) }.clipShape(RoundedRectangle(cornerRadius: 25))
    }
    func heroLog(_ p: Person) -> some View { ActionButton(title: "Log with \(p.name.components(separatedBy: " ").first ?? p.name)") { logMoment(p) } }
    func heroNotes(_ p: Person) -> some View { NavigationLink(value: p.id) { Text("Catch-up notes").font(.subheadline).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 10).background(Theme.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) }
}
