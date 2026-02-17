//
//  InvestmentReminderService.swift
//  Finance
//
//  Created by OpenCode on 17/02/2026.
//

import Foundation
import UserNotifications

enum InvestmentReminderService {
    private static let reminderPrefix = "investment-reminder-weekday-"

    static func configureWeekdayReminder(enabled: Bool, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()

        if !enabled {
            removeWeekdayReminders(center: center)
            return
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            removeWeekdayReminders(center: center)
            scheduleWeekdayReminders(center: center, hour: hour, minute: minute)
        }
    }

    private static func scheduleWeekdayReminders(center: UNUserNotificationCenter, hour: Int, minute: Int) {
        for weekday in 2...6 { // lunes-viernes
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let content = UNMutableNotificationContent()
            content.title = "Actualiza tus inversiones"
            content.body = "Registra el valor de mercado de hoy para mantener tu evolución al día."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "\(reminderPrefix)\(weekday)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    private static func removeWeekdayReminders(center: UNUserNotificationCenter) {
        let identifiers = (2...6).map { "\(reminderPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
