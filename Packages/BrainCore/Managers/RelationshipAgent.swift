import Foundation

/// Analyzes social interactions and provides nudges following the Notice -> Explain -> Suggest loop.
public actor RelationshipAgent {
    public static let shared = RelationshipAgent()
    
    private init() {}
    
    public func analyzeRecentInteractions() async -> [RelationshipNudge] {
        BrainLogger.info("Analyzing relationship patterns with AI...", category: .agent)
        
        // 1. Gather comprehensive context
        let messages = (try? await BrainMessagesManager.shared.fetchRecentMessages(limit: 100)) ?? []
        let staleContacts = await BrainDatabaseManager.shared.getStaleContacts(days: 7)
        
        if messages.isEmpty && staleContacts.isEmpty {
            BrainLogger.info("No conversation data to analyze", category: .agent)
            return []
        }
        
        // 2. Build conversation timeline with direction indicators
        let conversationMap = Dictionary(grouping: messages) { $0.senderName ?? $0.sender }
        var conversationSummaries: [String] = []
        
        for (contact, msgs) in conversationMap.prefix(10) {
            let recentMsgs = msgs.prefix(5)
            let lastMsg = recentMsgs.first
            let daysSince = lastMsg.map { -$0.timestamp.timeIntervalSinceNow / 86400 } ?? 999
            
            let direction = recentMsgs.first?.isFromMe == false ? "They messaged" : "You messaged"
            conversationSummaries.append("\(contact): \(direction) \(Int(daysSince))d ago")
        }
        
        // 3. Add stale contacts context
        let staleText = staleContacts.isEmpty 
            ? "" 
            : "\nLong-term quiet: " + staleContacts.map { "\($0.name) (\(Int(-$0.lastSpoken.timeIntervalSinceNow / 86400))d)" }.joined(separator: ", ")
        
        let systemPrompt = """
        You are BrainOS's relationship health analyzer. Your job:
        1. Identify social obligations (unanswered messages, pending replies)
        2. Detect relationship drift (friends going quiet)
        3. Suggest specific, actionable reconnection ideas
        
        Rules:
        - Only create nudges for HIGH-PRIORITY situations (urgent replies, close friends)
        - Be specific about WHY the nudge matters
        - Suggest what to SAY or DO (draft messages when relevant)
        - Limit to 3 nudges max (focus on most important)
        
        Output format: JSON array of objects with:
        - contactName: string
        - reason: string (why this matters)
        - suggestion: string (specific action)
        - priority: "high" | "medium" | "low"
        - actionType: "reply" | "message" | "call"
        
        If nothing urgent, output: []
        """
        
        let userPrompt = """
        Recent conversations:
        \(conversationSummaries.joined(separator: "\n"))
        \(staleText)
        
        Current time: \(Date().formatted())
        
        Analyze and generate relationship nudges.
        """
        
        do {
            let engine = ChatEngine()
            let request = ChatCompletionRequest(
                model: "default",
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt)
                ],
                temperature: 0.3,  // Lower temperature for consistency
                max_tokens: 800,
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
            
            guard let content = response.choices.first?.message.content else {
                BrainLogger.error("No content in relationship analysis response", category: .agent)
                return generateFallbackNudges(staleContacts: staleContacts)
            }
            
            // Extract JSON (handle markdown code blocks)
            let jsonString = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = jsonString.data(using: .utf8) else {
                BrainLogger.error("Failed to convert response to data", category: .agent)
                return generateFallbackNudges(staleContacts: staleContacts)
            }
            
            let decoder = JSONDecoder()
            let nudges = try decoder.decode([RelationshipNudge].self, from: data)
            
            BrainLogger.info("Generated \\(nudges.count) relationship nudges", category: .agent)
            return nudges
            
        } catch {
            BrainLogger.error("AI relationship analysis failed: \\(error)", category: .agent)
            return generateFallbackNudges(staleContacts: staleContacts)
        }
    }
    
    /// Generate simple heuristic-based nudges when AI fails
    private func generateFallbackNudges(staleContacts: [(name: String, lastSpoken: Date)]) -> [RelationshipNudge] {
        var nudges: [RelationshipNudge] = []
        
        // Create nudges for contacts quiet >7 days (max 2)
        for contact in staleContacts.prefix(2) {
            let daysSince = Int(-contact.lastSpoken.timeIntervalSinceNow / 86400)
            nudges.append(RelationshipNudge(
                contactName: contact.name,
                reason: "Last conversation was \\(daysSince) days ago",
                suggestion: "Send a quick check-in message or call",
                priority: daysSince > 14 ? .high : .medium,
                actionType: .message
            ))
        }
        
        return nudges
    }
}

public enum NudgePriority: String, Codable, Sendable {
    case low, medium, high
}

public enum ActionType: String, Codable, Sendable {
    case message, call, email, reply
}

public struct RelationshipNudge: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let contactName: String
    public let reason: String
    public let suggestion: String
    public let priority: NudgePriority
    public let actionType: ActionType
}
