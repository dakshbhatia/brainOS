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
        
        // Start background services
        Task {
            await BackgroundIngestionService.shared.start()
            await ScreenshotWatcherService.shared.start()
            VoiceService.shared.start()
        }
        
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
        BrainLogger.info("Generating daily brief...", category: .core)
        
        // Gather context for the brief
        let steps = (try? await BrainHealthManager.shared.fetchStepCount(days: 1).first) ?? 0
        let nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
        let memories = await BrainKnowledgeManager.shared.search(query: "important events today", limit: 3)
        
        let context = """
        Today's Stats:
        - Steps: \(Int(steps))
        - Recent Memories: \(memories.joined(separator: ", "))
        - Relationship Nudges: \(nudges.map { $0.reason }.joined(separator: "; "))
        
        Task: Summarize this into a concise, friendly 2-sentence morning brief.
        """
        
        do {
            let engine = ChatEngine()
            let response = try await engine.generateOneShot(
                messages: [ChatMessage(role: "user", content: context)],
                parameters: GenerationParameters(temperature: 0.7, maxTokens: 100, topPOverride: nil, repetitionPenalty: nil),
                requestedModel: "default"
            )
            return response
        } catch {
            BrainLogger.error("Failed to generate brief with LLM: \(error)", category: .core)
            return "You've taken \(Int(steps)) steps today. Your relationships are looking good!"
        }
    }
    
    private func performProactiveCheck() async {
        BrainLogger.info("Performing proactive life check...", category: .core)
        
        // 1. Gather all recent data
        let steps = (try? await BrainHealthManager.shared.fetchStepCount(days: 1).first) ?? 0
        let nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
        
        // 2. Run Reflection Task (The "Reasoning Loop")
        await runReflectionTask(steps: steps, nudges: nudges)
        
        // 3. Check for immediate alerts (Heuristics)
        let hour = Calendar.current.component(.hour, from: Date())
        if hour == 8 {
            await sendDailyBrief()
        }
    }
    
    private func runReflectionTask(steps: Double, nudges: [RelationshipNudge]) async {
        BrainLogger.info("Running Reflection Task...", category: .agent)
        
        let systemPrompt = """
        You are the BrainOS Internal Architect. Your job is to analyze the user's daily stream of data 
        and identify critical insights or urgent actions.
        
        Rules:
        1. Be extremely concise.
        2. Only notify for high-priority items (e.g., missed important messages, health alerts).
        3. Output ONLY a JSON object with "title", "body", and "priority" (high/medium).
        4. If nothing is urgent, output "NONE".
        """
        
        let context = """
        Current State:
        - Steps: \(Int(steps))
        - Relationship Nudges: \(nudges.map { "\($0.contactName): \($0.reason)" }.joined(separator: "\n"))
        
        Analyze and decide if a notification is needed.
        """
        
        do {
            let engine = ChatEngine()
            let response = try await engine.generateOneShot(
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: context)
                ],
                parameters: GenerationParameters(temperature: 0.3, maxTokens: 200, topPOverride: nil, repetitionPenalty: nil),
                requestedModel: "default"
            )
            
            let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedResponse != "NONE" && !trimmedResponse.isEmpty {
                // Try to extract JSON if the model added extra text
                let jsonString: String
                if let range = trimmedResponse.range(of: "{.*}", options: .regularExpression) {
                    jsonString = String(trimmedResponse[range])
                } else {
                    jsonString = trimmedResponse
                }
                
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let title = json["title"],
                   let body = json["body"] {
                    notificationService.show(title: title, subtitle: nil, body: body)
                    
                    // If high priority, speak it
                    if json["priority"] == "high" {
                        Task {
                            await VoiceService.shared.speak(body)
                        }
                    }
                }
            }
        } catch {
            BrainLogger.error("Reflection task failed: \(error)", category: .agent)
        }
    }
    
    private func checkRelationships() async {
        BrainLogger.info("Checking relationship health...", category: .agent)
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
            BrainLogger.debug("Nudge: \(nudge.contactName) - \(nudge.suggestion)", category: .agent)
        }
    }
    
    private func checkHealth() async {
        BrainLogger.info("Checking physical health...", category: .health)
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
            BrainLogger.error("Health check failed: \(error)", category: .health)
        }
    }
    
    private func checkSpending() async {
        BrainLogger.info("Checking financial health...", category: .core)
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
