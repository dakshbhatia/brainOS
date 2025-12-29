//
//  NotificationService.swift
//  BrainOS
//
//  Local notifications for model download completion
//

import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private let categoryId = "OSU_MODEL_READY"
    private let actionOpenId = "OSU_OPEN_MODELS"
    
    // BrainOS proactive notification categories
    private let categoryRelationship = "BRAINOS_RELATIONSHIP"
    private let categoryHealth = "BRAINOS_HEALTH"
    private let categoryInsight = "BRAINOS_INSIGHT"
    private let actionReply = "BRAINOS_REPLY"
    private let actionCall = "BRAINOS_CALL"
    private let actionDismiss = "BRAINOS_DISMISS"

    private override init() {
        super.init()
    }

    func configureOnLaunch() {
        center.delegate = self
        
        // Register model download category
        let openAction = UNNotificationAction(
            identifier: actionOpenId,
            title: "Open Models",
            options: [.foreground]
        )
        let modelCategory = UNNotificationCategory(
            identifier: categoryId,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register relationship nudge category with actions
        let replyAction = UNNotificationAction(
            identifier: actionReply,
            title: "Reply",
            options: [.foreground]
        )
        let callAction = UNNotificationAction(
            identifier: actionCall,
            title: "Call",
            options: [.foreground]
        )
        let relationshipCategory = UNNotificationCategory(
            identifier: categoryRelationship,
            actions: [replyAction, callAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register health category
        let dismissAction = UNNotificationAction(
            identifier: actionDismiss,
            title: "Got it",
            options: []
        )
        let healthCategory = UNNotificationCategory(
            identifier: categoryHealth,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register insight category
        let insightCategory = UNNotificationCategory(
            identifier: categoryInsight,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([modelCategory, relationshipCategory, healthCategory, insightCategory])

        // Request authorization (best-effort; user may have already granted/denied)
        Task.detached {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func postPluginVerificationFailed(name: String, version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Plugin verification failed"
        content.body = "\(name) @ \(version)"

        let request = UNNotificationRequest(
            identifier: "plugin-verify-fail-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    func postModelReady(modelId: String, modelName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Model ready"
        content.body = "\(modelName) is downloaded and ready to use."
        content.userInfo = ["modelId": modelId]
        content.categoryIdentifier = categoryId

        // Deliver shortly after scheduling
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "model-ready-\(modelId)",
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    func postPluginUpdatesAvailable(count: Int, pluginNames: [String]) {
        guard count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Plugin updates available"
        if count == 1 {
            content.body = "\(pluginNames.first ?? "1 plugin") has an update available."
        } else {
            content.body = "\(count) plugins have updates available."
        }
        content.userInfo = ["pluginCount": count]

        let request = UNNotificationRequest(
            identifier: "plugin-updates-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    func show(title: String, subtitle: String? = nil, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "generic-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
    
    // MARK: - Proactive Notifications
    
    /// Send a relationship nudge notification
    func postRelationshipNudge(contactName: String, reason: String, suggestion: String, priority: String) {
        let content = UNMutableNotificationContent()
        content.title = "💬 Relationship Nudge"
        content.subtitle = contactName
        content.body = reason
        content.userInfo = [
            "type": "relationship",
            "contactName": contactName,
            "suggestion": suggestion,
            "priority": priority
        ]
        content.categoryIdentifier = categoryRelationship
        content.sound = priority == "high" ? .defaultCritical : .default
        
        let request = UNNotificationRequest(
            identifier: "relationship-\(contactName)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
    
    /// Send a health alert notification
    func postHealthAlert(title: String, body: String, isUrgent: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = "🏃 Health Alert"
        content.subtitle = title
        content.body = body
        content.userInfo = ["type": "health"]
        content.categoryIdentifier = categoryHealth
        content.sound = isUrgent ? .defaultCritical : .default
        
        let request = UNNotificationRequest(
            identifier: "health-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
    
    /// Send a daily insight notification
    func postDailyInsight(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "✨ Daily Insight"
        content.subtitle = title
        content.body = body
        content.userInfo = ["type": "insight"]
        content.categoryIdentifier = categoryInsight
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "insight-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
    
    /// Send a daily brief notification (scheduled for morning)
    func scheduleDailyBrief(hour: Int, minute: Int, brief: String) {
        let content = UNMutableNotificationContent()
        content.title = "Good Morning! ☀️"
        content.body = brief
        content.userInfo = ["type": "dailyBrief"]
        content.sound = .default
        
        // Schedule for specific time
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-brief",  // Same ID so it replaces previous
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let info = response.notification.request.content.userInfo
        let modelId = info["modelId"] as? String

        if response.actionIdentifier == actionOpenId
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        {
            Task { @MainActor in
                AppDelegate.shared?.showManagementWindow(
                    initialTab: .models,
                    deeplinkModelId: modelId,
                    deeplinkFile: nil
                )
            }
        }
    }
}
