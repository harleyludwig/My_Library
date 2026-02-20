import Foundation
import UserNotifications

enum LendingReminderService {
    private static let center = UNUserNotificationCenter.current()

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    static func scheduleReminder(for book: Book) async {
        removeReminder(forBookID: book.id)

        guard let reminderDate = book.reminderDate,
              reminderDate > .now,
              book.isLent else {
            return
        }

        let status = await authorizationStatus()
        if status == .notDetermined {
            _ = await requestAuthorization()
        }

        let content = UNMutableNotificationContent()
        content.title = "Lent book reminder"
        content.body = "\(book.title) was lent to \(book.lentTo). Time to follow up."
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )

        let request = UNNotificationRequest(
            identifier: identifier(for: book.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        )

        do {
            try await center.add(request)
        } catch {
            // Silent failure keeps lending flow unblocked.
        }
    }

    static func removeReminder(forBookID bookID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: bookID)])
    }

    private static func identifier(for id: UUID) -> String {
        "lend-reminder-\(id.uuidString)"
    }
}
