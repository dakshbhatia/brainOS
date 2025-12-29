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
        
        // 2. Build conversation timeline with direction indicators and wait time
        let conversationMap = Dictionary(grouping: messages) { $0.senderName ?? $0.sender }
        var conversationSummaries: [String] = []
        var unbalancedContacts: [String] = []
        
        for (contact, msgs) in conversationMap.prefix(15) {
            let recentMsgs = Array(msgs.prefix(5))
            let lastMsg = recentMsgs.first
            let daysSince = lastMsg.map { -Int($0.timestamp.timeIntervalSinceNow / 86400) } ?? 999
            
            let isWaitingForMe = lastMsg?.isFromMe == false
            let direction = isWaitingForMe ? "They messaged" : "You messaged"
            
            // Wait Time Analysis: If they messaged and it's been > 4 hours, it's unbalanced
            if isWaitingForMe && lastMsg!.timestamp.timeIntervalSinceNow < -14400 {
                unbalancedContacts.append("\(contact) (waiting \(Int(-lastMsg!.timestamp.timeIntervalSinceNow / 3600))h)")
            }
            
            // Get holistic score
            let score = await calculateRelationshipScore(contactId: contact)
            
            conversationSummaries.append("\(contact) [Score: \(Int(score))]: \(direction) \(daysSince)d ago")
        }
        
        // 3. Social Drift Detection (> 60 days)
        let driftingContacts = await BrainDatabaseManager.shared.getStaleContacts(days: 60)
        let driftText = driftingContacts.isEmpty 
            ? "" 
            : "\nSOCIAL DRIFT (Critical): " + driftingContacts.prefix(3).map { "\($0.name) (\(Int(-$0.lastSpoken.timeIntervalSinceNow / 86400))d)" }.joined(separator: ", ")
        
        let waitText = unbalancedContacts.isEmpty ? "" : "\nPENDING REPLIES: " + unbalancedContacts.joined(separator: ", ")
        
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
        - contactId: string
        - reason: string (why this matters)
        - suggestion: string (what to say or do)
        - urgency: number (0.0 to 1.0)
        - deepLinkURL: string (optional, e.g. imessage://contact_name)
        
        If nothing urgent, output: []
        """
        
        let userPrompt = """
        Context:
        \(conversationSummaries.joined(separator: "\n"))
        \(waitText)
        \(driftText)
        
        Current time: \(Date().formatted())
        
        Analyze and generate relationship nudges. Focus on balancing the 'Social' vital.
        """
        
        do {
            let engine = ChatEngine()
            let request = ChatCompletionRequest(
                model: "default",
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt)
                ],
                temperature: 0.3,
                max_tokens: 800
            )
            
            let response = try await engine.completeChat(request: request)
            
            guard let content = response.choices.first?.message.content else {
                return generateFallbackNudges(staleContacts: staleContacts)
            }
            
            let jsonString = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            guard let data = jsonString.data(using: String.Encoding.utf8) else {
                return generateFallbackNudges(staleContacts: staleContacts)
            }
            
            return try JSONDecoder().decode([RelationshipNudge].self, from: data)
            
        } catch {
            BrainLogger.error("AI analysis failed: \(error)", category: .agent)
            return generateFallbackNudges(staleContacts: staleContacts)
        }
    }
    
    /// Calculates a 0-100 score for a relationship based on history and balance.
    public func calculateRelationshipScore(contactId: String) async -> Double {
        // 1. Recency Score (0-50 pts)
        // High score for contact within 7 days, drops to 0 after 60 days
        let recentMessages = (try? await BrainMessagesManager.shared.fetchRecentMessages(limit: 50)) ?? []
        let contactMsgs = recentMessages.filter { ($0.senderName ?? $0.sender) == contactId }
        
        let lastMsgDate = contactMsgs.first?.timestamp ?? Date.distantPast
        let daysSince = -lastMsgDate.timeIntervalSinceNow / 86400
        let recencyScore = max(0, 50 - (daysSince * 0.83)) // 50 / 60 = 0.83
        
        // 2. Consistency Score (0-30 pts)
        // Based on "daily streaks" in the last 30 days
        let trends = await BrainDatabaseManager.shared.getRelationshipTrends(contactId: contactId, days: 30)
        let daysActive = Double(trends.filter { $0 > 0 }.count)
        let consistencyScore = (daysActive / 30.0) * 30.0
        
        // 3. Balance Score (0-20 pts)
        // Ratio of Me vs Them messages. Perfect balance = 1.0 (20 pts)
        let myMsgs = contactMsgs.filter { $0.isFromMe }.count
        let theirMsgs = contactMsgs.filter { !$0.isFromMe }.count
        let total = Double(myMsgs + theirMsgs)
        let balanceScore: Double
        if total > 0 {
            let ratio = Double(min(myMsgs, theirMsgs)) / Double(max(myMsgs, theirMsgs))
            balanceScore = ratio * 20.0
        } else {
            balanceScore = 0
        }
        
        return recencyScore + consistencyScore + balanceScore
    }
    
    /// Generate simple heuristic-based nudges when AI fails
    private func generateFallbackNudges(staleContacts: [(name: String, lastSpoken: Date)]) -> [RelationshipNudge] {
        var nudges: [RelationshipNudge] = []
        
        for contact in staleContacts.prefix(2) {
            let daysSince = Int(-contact.lastSpoken.timeIntervalSinceNow / 86400)
            nudges.append(RelationshipNudge(
                contactName: contact.name,
                contactId: contact.name,
                reason: "It's been \(daysSince) days since you last connected.",
                suggestion: "Send a quick hello to catch up.",
                urgency: daysSince > 30 ? 0.9 : 0.6,
                deepLinkURL: "imessage://\(contact.name)"
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

public struct RelationshipNudge: Identifiable, Codable {
    public let id: UUID
    public let contactName: String
    public let contactId: String
    public let reason: String
    public let suggestion: String
    public let urgency: Double // 0.0 to 1.0
    public let deepLinkURL: String?
    
    public init(id: UUID = UUID(), contactName: String, contactId: String, reason: String, suggestion: String, urgency: Double, deepLinkURL: String? = nil) {
        self.id = id
        self.contactName = contactName
        self.contactId = contactId
        self.reason = reason
        self.suggestion = suggestion
        self.urgency = urgency
        self.deepLinkURL = deepLinkURL
    }
}
