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
        
        // Schedule daily brief notification for 8 AM
        scheduleDailyBriefNotification()
        
        // Start the proactive loop (runs every hour)
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
        BrainLogger.info("Generating AI-powered daily brief...", category: .core)
        
        // 1. Gather comprehensive context
        let userName = UserDefaults.standard.string(forKey: "userName") ?? "there"
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let greeting = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        
        // 2. Get data from various sources
        let steps = (try? await BrainHealthManager.shared.fetchStepCount(days: 1).first) ?? 0
        let nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
        let calendar = await BrainCalendarManager.shared.getUpcomingBrief()
        
        // 3. Semantic memory search for recent important events
        let recentMemories = await BrainKnowledgeManager.shared.search(
            query: "important events meetings deadlines work",
            limit: 5
        )
        
        // 4. Build rich context for AI
        let nudgesText = nudges.isEmpty 
            ? "No relationship alerts" 
            : nudges.map { "- \($0.contactName): \($0.reason)" }.joined(separator: "\n")
        
        let memoriesText = recentMemories.isEmpty
            ? "No recent memories found"
            : recentMemories.joined(separator: "\\n")
        
        let systemPrompt = """
        You are BrainOS's briefing assistant. Generate a warm, personal, actionable daily brief.
        Style: Friendly but professional. 2-3 sentences max.
        Focus on: What's important today, relationships, and wellbeing.
        """
        
        let userPrompt = """
        Generate a \\(greeting) brief for \\(userName):
        
        Current Time: \\(now.formatted(date: .abbreviated, time: .shortened))
        
        Health:
        - Steps today: \\(Int(steps))
        
        Relationships:
        \\(nudgesText)
        
        Calendar:
        \\(calendar)
        
        Recent Context:
        \\(memoriesText)
        """
        
        do {
            let engine = ChatEngine()
            let request = ChatCompletionRequest(
                model: "default",
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt)
                ],
                temperature: 0.7,
                max_tokens: 150,
                stream: nil,
                top_p: nil,
                frequency_penalty: nil,
                presence_penalty: nil,
                stop: nil,
                n: nil,
                tools: nil,
                tool_choice: nil,
                session_id: nil
            )
            let response = try await engine.completeChat(request: request)
            return response.choices.first?.message.content ?? generateFallbackBrief(steps: steps, nudges: nudges, calendar: calendar)
        } catch {
            BrainLogger.error("Failed to generate brief with LLM: \\(error)", category: .core)
            return generateFallbackBrief(steps: steps, nudges: nudges, calendar: calendar)
        }
    }
    
    /// Fallback brief when AI generation fails
    private func generateFallbackBrief(steps: Double, nudges: [RelationshipNudge], calendar: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        
        var brief = "\(greeting)! "
        
        if steps > 0 {
            brief += "You've taken \(Int(steps)) steps today. "
        }
        
        if !nudges.isEmpty {
            brief += nudges.first.map { "Don't forget to reach out to \($0.contactName). " } ?? ""
        }
        
        if !calendar.isEmpty && calendar != "No upcoming events." {
            brief += calendar
        } else {
            brief += "Your schedule looks clear."
        }
        
        return brief
    }
    
    private func performProactiveCheck() async {
        BrainLogger.info("Performing proactive life check...", category: .core)
        
        // 1. Gather all recent data
        let steps = (try? await BrainHealthManager.shared.fetchStepCount(days: 1).first) ?? 0
        let nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
        let staleContacts = await BrainDatabaseManager.shared.getStaleContacts(days: 14)
        let calendarBrief = await BrainCalendarManager.shared.getUpcomingBrief()
        
        // 2. Send relationship nudge notifications (high priority only)
        for nudge in nudges.filter({ $0.priority == .high }) {
            await notificationService.postRelationshipNudge(
                contactName: nudge.contactName,
                reason: nudge.reason,
                suggestion: nudge.suggestion,
                priority: "high"
            )
        }
        
        // 3. Check health metrics and send alerts
        await checkHealthAndNotify(steps: steps)
        
        // 4. Run AI reflection for general insights
        await runReflectionTask(
            steps: steps,
            nudges: nudges,
            staleContacts: staleContacts,
            calendar: calendarBrief
        )
        
        // 5. Time-based triggers
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Generate and cache daily brief at 7 AM (ready for 8 AM notification)
        if hour == 7 {
            await generateAndCacheDailyBrief()
        }
        
        // Midnight journaling
        if hour == 23 {
            await generateDailyJournal()
        }
    }
    
    /// Check health metrics and send proactive notifications
    private func checkHealthAndNotify(steps: Double) async {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Afternoon activity check (2 PM)
        if hour == 14 && steps < 2000 {
            await notificationService.postHealthAlert(
                title: "Low Activity Today",
                body: "You've only taken \(Int(steps)) steps. How about a 10-minute walk?"
            )
        }
        
        // Evening check (6 PM)
        if hour == 18 && steps < 5000 {
            await notificationService.postHealthAlert(
                title: "Movement Reminder",
                body: "Only \(Int(steps)) steps today. A short evening walk could help!"
            )
        }
    }
    
    /// Generate daily brief and cache for morning notification
    private func generateAndCacheDailyBrief() async {
        let brief = await generateBrief()
        
        // Cache for morning notification
        UserDefaults.standard.set(brief, forKey: "cachedDailyBrief")
        UserDefaults.standard.set(Date(), forKey: "cachedBriefDate")
        
        BrainLogger.info("Daily brief generated and cached", category: .core)
    }
    
    /// Schedule recurring daily brief notification
    private func scheduleDailyBriefNotification() {
        // Get cached brief or generate fallback
        let brief = UserDefaults.standard.string(forKey: "cachedDailyBrief") 
            ?? "Good morning! Your BrainOS daily brief is ready."
        
        // Schedule for 8 AM daily
        notificationService.scheduleDailyBrief(hour: 8, minute: 0, brief: brief)
        BrainLogger.info("Scheduled daily brief notification for 8:00 AM", category: .core)
    }

    public func generateDailyJournal() async {
        BrainLogger.info("Generating daily journal entry...", category: .agent)
        
        let steps = (try? await BrainHealthManager.shared.fetchStepCount(days: 1).first) ?? 0
        let memories = await BrainKnowledgeManager.shared.search(query: "what happened today", limit: 10)
        
        let context = """
        Today's Data:
        - Steps: \(Int(steps))
        - Key Memories: \(memories.joined(separator: " | "))
        
        Task: Write a short, reflective journal entry for today (2-3 sentences). 
        Also identify the overall mood (e.g., Productive, Relaxed, Social).
        Output JSON: {"summary": "...", "mood": "...", "events": ["event1", "event2"]}
        """
        
        do {
            let engine = ChatEngine()
            let request = ChatCompletionRequest(
                model: "default",
                messages: [ChatMessage(role: "user", content: context)],
                temperature: 0.7,
                max_tokens: 300,
                stream: nil,
                top_p: nil,
                frequency_penalty: nil,
                presence_penalty: nil,
                stop: nil,
                n: nil,
                tools: nil,
                tool_choice: nil,
                session_id: nil
            )
            let result = try await engine.completeChat(request: request)
            let response = result.choices.first?.message.content ?? ""
            
            if let data = response.data(using: String.Encoding.utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summary = json["summary"] as? String,
               let mood = json["mood"] as? String,
               let events = json["events"] as? [String] {
                
                let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10) // YYYY-MM-DD
                await BrainDatabaseManager.shared.saveJournalEntry(
                    date: String(dateStr),
                    summary: summary,
                    mood: mood,
                    events: events
                )
                BrainLogger.info("Journal entry saved for \(dateStr)", category: .agent)
            }
        } catch {
            BrainLogger.error("Failed to generate journal: \(error)", category: .agent)
        }
    }
    
    private func runReflectionTask(
        steps: Double,
        nudges: [RelationshipNudge],
        staleContacts: [(name: String, lastSpoken: Date)],
        calendar: String
    ) async {
        BrainLogger.info("Running AI Reflection Task for proactive insights...", category: .agent)
        
        let systemPrompt = """
        You are BrainOS's Internal Architect analyzing the user's life data for critical insights.
        
        Your job:
        1. Identify non-obvious patterns or concerns
        2. Generate actionable insights (not just observations)
        3. Prioritize truly important items only
        
        Rules:
        - Only create insights for HIGH-IMPACT situations
        - Be specific about WHY it matters and WHAT to do
        - Output JSON: {"title": "...", "body": "...", "priority": "high/medium"}
        - If nothing actionable, output: null
        """
        
        let staleContactsStr = staleContacts
            .map { "\($0.name) (\(Int(-$0.lastSpoken.timeIntervalSinceNow / 86400))d)" }
            .joined(separator: ", ")
        
        let nudgesStr = nudges
            .map { "\($0.contactName): \($0.reason)" }
            .joined(separator: "\n")
        
        // Get recent memories for additional context
        let recentMemories = await BrainKnowledgeManager.shared.search(
            query: "work deadlines projects important upcoming",
            limit: 3
        )
        
        let context = """
        Current State:
        - Physical Activity: \\(Int(steps)) steps today
        - Time: \\(Date().formatted(date: .abbreviated, time: .shortened))
        
        Relationships:
        \\(nudgesStr.isEmpty ? "No urgent relationship items" : nudgesStr)
        Stale Contacts: \\(staleContactsStr.isEmpty ? "None" : staleContactsStr)
        
        Calendar: \\(calendar)
        
        Recent Context:
        \\(recentMemories.isEmpty ? "No recent memories" : recentMemories.joined(separator: "\\n"))
        
        Analyze for actionable insights.
        """
        
        do {
            let engine = ChatEngine()
            let request = ChatCompletionRequest(
                model: "default",
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: context)
                ],
                temperature: 0.3,
                max_tokens: 250,
                stream: nil,
                top_p: nil,
                frequency_penalty: nil,
                presence_penalty: nil,
                stop: nil,
                n: nil,
                tools: nil,
                tool_choice: nil,
                session_id: nil
            )
            let result = try await engine.completeChat(request: request)
            let response = result.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if response == "null" || response.isEmpty {
                BrainLogger.debug("No actionable insights from reflection", category: .agent)
                return
            }
            
            // Parse JSON response
            let jsonString = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let title = json["title"],
               let body = json["body"] {
                
                // Send as insight notification
                await notificationService.postDailyInsight(title: title, body: body)
                BrainLogger.info("Generated proactive insight: \\(title)", category: .agent)
            }
        } catch {
            BrainLogger.error("Reflection task failed: \\(error)", category: .agent)
        }
    }
}
