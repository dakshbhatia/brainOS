import Foundation
import BrainRepository

/// The central coordinator for BrainOS proactive intelligence.
public actor BrainManager {
    public static let shared = BrainManager()
    
    private let notificationService = NotificationService.shared
    private let pluginManager = PluginManager.shared
    
    private var isRunning = false
    private var timer: Task<Void, Never>?
    
    private init() {}
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Start the proactive loop
        timer = Task {
            while !Task.isCancelled {
                await performProactiveCheck()
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000) // Every hour
            }
        }
    }
    
    public func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }
    
    public func generateBrief() async -> String {
        // In a real implementation, this would use the LLM to summarize all data
        let steps = (try? await BrainHealthManager.shared.fetchStepCount(days: 1).first) ?? 0
        let nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
        
        var brief = "You've taken \(Int(steps)) steps today. "
        
        if let highPriority = nudges.first(where: { $0.priority == .high }) {
            brief += "You should really reply to \(highPriority.contactName). "
        } else {
            brief += "Your relationships are looking good! "
        }
        
        return brief
    }
    
    private func performProactiveCheck() async {
        print("BrainOS: Performing proactive life check...")
        
        // 1. Check Relationships
        await checkRelationships()
        
        // 2. Check Health
        await checkHealth()
        
        // 3. Check Spending
        await checkSpending()
        
        // For MVP, we'll just trigger a notification if it's morning
        let hour = Calendar.current.component(.hour, from: Date())
        if hour == 8 {
            await sendDailyBrief()
        }
    }
    
    private func checkRelationships() async {
        print("BrainOS: Checking relationship health...")
        let nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
        
        // If there's a high priority nudge, show a notification
        if let highPriority = nudges.first(where: { $0.priority == .high }) {
            notificationService.show(
                title: "Relationship Nudge",
                subtitle: highPriority.contactName,
                body: highPriority.reason
            )
        }
        
        for nudge in nudges {
            print("BrainOS Nudge: \(nudge.contactName) - \(nudge.suggestion)")
        }
    }
    
    private func checkHealth() async {
        // Logic to query HealthKit
        print("BrainOS: Checking physical health...")
    }
    
    private func checkSpending() async {
        // Logic to query Finance/Plaid
        print("BrainOS: Checking financial health...")
    }
    
    private func sendDailyBrief() async {
        notificationService.show(
            title: "Good Morning!",
            subtitle: "Your BrainOS Daily Brief is ready.",
            body: "You have 3 meetings today. Don't forget to text Mom!"
        )
    }
}
