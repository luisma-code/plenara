import Foundation
import UserNotifications
import Combine
import OSLog

struct ReminderPlan: Equatable {
    var id: String
    var title: String
    var body: String
    var components: DateComponents
    var repeats: Bool
    static func make(_ j: Journal, now: Date = Date(), calendar: Calendar = .current) -> [ReminderPlan] {
        let p = j.preferences
        guard p.notifications else { return [] }
        let hour = p.allowedHour(p.hour)
        let weekly = ReminderPlan(id: "weekly", title: "A little time for your people?", body: "Make room for a small hello. Your people are here when you’re ready.", components: DateComponents(calendar: calendar, hour: hour, minute: p.minute, weekday: p.weekday), repeats: true)
        var dated: [(date: Date, plan: ReminderPlan)] = []
        if p.birthdays {
            for person in j.people.filter({ !$0.paused && $0.birthdayReminder && $0.birthdayMonth > 0 && $0.birthdayDay > 0 }) {
                let components = DateComponents(calendar: calendar, month: person.birthdayMonth, day: person.birthdayDay, hour: hour, minute: p.minute)
                // Strict matching preserves the saved birthday: February 29 is not March 1.
                // A malformed legacy date is left in the journal, without inventing a reminder.
                guard let date = calendar.nextDate(after: now, matching: components, matchingPolicy: .strict) else { continue }
                dated.append((date, ReminderPlan(id: "birthday-\(person.id)", title: "A date worth remembering", body: "An important birthday is today. Open Plenara for a little reminder.", components: components, repeats: true)))
            }
        }
        if p.followUps {
            for note in j.people.filter({ !$0.paused }).flatMap(\.notes) where !note.archived {
                guard let followUp = note.followUp,
                      let date = calendar.date(bySettingHour: hour, minute: p.minute, second: 0, of: followUp), date > now else { continue }
                var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: date)
                components.calendar = calendar
                dated.append((date, ReminderPlan(id: "followup-\(note.id)", title: "A thread to pick up", body: "You saved something to follow up on. Open Plenara when you have a moment.", components: components, repeats: false)))
            }
        }
        // Reserve the weekly invitation, then use the finite slots for the nearest
        // dates across both kinds. Distant annual birthdays must not starve tomorrow's note.
        dated.sort { $0.date == $1.date ? $0.plan.id < $1.plan.id : $0.date < $1.date }
        return [weekly] + dated.prefix(47).map(\.plan)
    }
}
@MainActor final class NotificationManager: ObservableObject {
    @Published var status: UNAuthorizationStatus = .notDetermined
    @Published var message: String?
    @Published var weeklyReady = false
    private let log = Logger(subsystem: "com.plenara.plenaraApp", category: "reminders")
    private var pending: Journal?
    private var running = false
    let center = UNUserNotificationCenter.current()
    func request() async -> Bool {
        do { let allowed = try await center.requestAuthorization(options: [.alert, .sound]); await refreshStatus(); return allowed }
        catch { message = "Notifications couldn’t be enabled. \(error.localizedDescription)"; return false }
    }
    func refreshStatus() async { status = await center.notificationSettings().authorizationStatus }
    // Every reschedule is serialized; a newer request is applied after any in-flight add.
    func refresh(_ journal: Journal) async {
        pending = journal
        guard !running else { return }
        running = true
        defer { running = false }
        while let next = pending {
            pending = nil
            weeklyReady = false
            center.removeAllPendingNotificationRequests()
            await refreshStatus()
            guard status == .authorized || status == .provisional else { continue }
            do {
                for plan in ReminderPlan.make(next) {
                    let content = UNMutableNotificationContent(); content.title = plan.title; content.body = plan.body; content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: plan.components, repeats: plan.repeats)
                    try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
                }
                weeklyReady = await center.pendingNotificationRequests().contains { $0.identifier == "weekly" }
                message = nil
                log.notice("Local reminders refreshed")
            } catch { message = "Some reminders couldn’t be scheduled. Open reminder settings to try again. \(error.localizedDescription)" }
        }
    }
}
