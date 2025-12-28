import Foundation
import BrainRepository

/// The central coordinator for BrainOS proactive intelligence.
@MainActor
public class BrainManager {
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
        print("BrainOS: Checking physical health...")
        do {
            try await BrainHealthManager.shared.requestPermissions()
            let steps = try await BrainHealthManager.shared.fetchStepCount(days: 1)
            if let todaySteps = steps.first, todaySteps < 2000 {
                let hour = Calendar.current.component(.hour, from: Date())
                if hour > 14 { // Afternoon nudge
                    notificationService.show(
                        title: "Movement Nudge",
                        subtitle: "You've only taken \(Int(todaySteps)) steps",
                        body: "How about a quick 10-minute walk to clear your head?"
                    )
                }
            }
        } catch {
            print("BrainOS: Health check failed: \(error)")
        }
    }
    
    private func checkSpending() async {
        print("BrainOS: Checking financial health...")
        // Placeholder for Plaid/Finance integration
        // In a real implementation, this would query the BrainFinanceTool
    }
    
    private func sendDailyBrief() async {
        notificationService.show(
            title: "Good Morning!",
            subtitle: "Your BrainOS Daily Brief is ready.",
            body: "You have 3 meetings today. Don't forget to text Mom!"
        )
    }
}
