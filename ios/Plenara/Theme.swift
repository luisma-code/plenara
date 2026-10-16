import SwiftUI

extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
    static func adaptive(_ light: UInt, _ dark: UInt) -> Color { Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) }) }
}
enum Theme {
    static let paper = Color.adaptive(0xF8F6F2, 0x211F27)
    static let card = Color.adaptive(0xFFFDFA, 0x2B2832)
    static let ink = Color.adaptive(0x302C39, 0xF4EFF5)
    static let muted = Color.adaptive(0x716B78, 0xBDB4C5)
    static let plum = Color.adaptive(0x65516F, 0xD8C0E7)
    static let action = Color(hex: 0x65516F)
    static let lavender = Color.adaptive(0xECE5F0, 0x3B3046)
    static let sage = Color.adaptive(0xE5ECE4, 0x2E3A30)
    static let peach = Color.adaptive(0xF3E3D9, 0x49352D)
    static let line = Color.adaptive(0xE7E1DF, 0x49414D)
    static func title(_ size: CGFloat = 40) -> Font { .custom("Georgia", size: size, relativeTo: size > 30 ? .largeTitle : .title2) }
}
struct Eyebrow: View {
    var text: String
    var body: some View { Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(1.7).foregroundStyle(Theme.muted) }
}
struct Avatar: View {
    var person: Person
    var size: CGFloat = 50
    var avatarColor: Color {
        let colors: [UInt] = [0xD9CBE3, 0xDBE4D5, 0xECD3C6, 0xD7E2E9, 0xEED8DF]
        let index = person.name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count
        return Color(hex: colors[index])
    }
    var body: some View {
        Group {
            if let bytes = person.photo, let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFill() }
            else { Text(person.initials).font(.custom("Georgia", fixedSize: size * 0.4)).foregroundStyle(Color(hex: 0x51415F)).frame(maxWidth: .infinity, maxHeight: .infinity).background(avatarColor) }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}
struct ActionButton: View {
    var title: String
    var icon: String = "plus"
    var primary = true
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 10).fixedSize(horizontal: false, vertical: true).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(primary ? .white : Theme.ink).background(primary ? Theme.action : Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(primary ? Color.clear : Theme.line))
    }
}
struct Surface<Content: View>: View {
    var color: Color = Theme.card
    @ViewBuilder var content: Content
    var body: some View { content.padding(21).frame(maxWidth: .infinity, alignment: .leading).background(color, in: RoundedRectangle(cornerRadius: 25)) }
}
struct PersonRow: View {
    var person: Person
    var detail: String?
    var body: some View {
        HStack(spacing: 13) {
            Avatar(person: person)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(person.name).font(.headline); if person.wantsToGrow { Image(systemName: "leaf").foregroundStyle(Theme.plum).accessibilityLabel("Grow closer") }; if person.feelingChoice == "Needs care" { Image(systemName: "heart").foregroundStyle(Theme.plum).accessibilityLabel("Needs care") } }
                Text(detail ?? [person.city, person.closeness == "Not set" ? "" : person.closeness].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 21)).overlay(RoundedRectangle(cornerRadius: 21).stroke(Theme.line)).contentShape(Rectangle())
    }
}
struct PageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 12) { Eyebrow(text: eyebrow); Text(title).font(Theme.title()).tracking(-1.3); Text(subtitle).font(.body).foregroundStyle(Theme.muted).lineSpacing(4) }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct QuietEmpty: View {
    var title: String
    var message: String
    var body: some View { Surface(color: Theme.lavender) { VStack(alignment: .leading, spacing: 13) { Image(systemName: "leaf").font(.title).foregroundStyle(Theme.plum); Text(title).font(Theme.title(28)); Text(message).foregroundStyle(Theme.muted).lineSpacing(4) } } }
}
func rhythmLabel(_ days: Int) -> String {
    switch days { case 0: return "No regular reminder"; case 7: return "Every week"; case 14: return "Every 2 weeks"; case 30: return "About once a month"; case 60: return "About every 2 months"; case 90: return "About every 3 months"; default: return "Every \(days) days" }
}
func connectionLabel(_ p: Person, journal: Journal) -> String {
    guard let date = journal.lastConnection(p) else { return "Last contact not set" }
    let days = journal.daysSince(date)
    let approximate = p.baselineApproximate && date == p.baselineConnection ? "About " : ""
    return days == 0 ? "Connected today" : days == 1 ? "Connected yesterday" : "\(approximate)\(days) days since connecting"
}

struct PetalMotif: View {
    var body: some View {
        ZStack { ForEach([0.0, 60.0, 120.0], id: \.self) { angle in Ellipse().stroke(Theme.plum.opacity(0.16), lineWidth: 0.7).frame(width: 65, height: 145).rotationEffect(.degrees(angle)) } }
            .frame(width: 145, height: 145).accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct ComfortableButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .foregroundStyle(configuration.role == .destructive ? Color.red : Theme.plum)
            .opacity(enabled ? 1 : 0.5)
    }
}
