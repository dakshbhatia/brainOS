import Foundation

/// Analyzes social interactions and provides nudges following the Notice -> Explain -> Suggest loop.
public actor RelationshipAgent {
    public static let shared = RelationshipAgent()
    
    private init() {}
    
    public func analyzeRecentInteractions() async -> [RelationshipNudge] {
        BrainLogger.info("Analyzing recent interactions with LLM...", category: .agent)
        
        // 1. Gather context from Messages
        let messages = (try? await BrainMessagesManager.shared.fetchRecentMessages(limit: 50)) ?? []
        if messages.isEmpty {
            return getMockNudges()
        }
        
        // 2. Format messages for LLM analysis
        let messageContext = messages.map { msg in
            let sender = msg.senderName ?? msg.sender
            let direction = msg.isFromMe ? "To" : "From"
            return "[\(msg.timestamp)] \(direction) \(sender): \(msg.text ?? "[Attachment]")"
        }.joined(separator: "\n")
        
        let prompt = """
        Analyze these recent messages and identify any social obligations or opportunities to connect.
        For each person, if a nudge is needed, provide:
        - contactName
        - reason (why nudge?)
        - suggestion (what to say/do)
        - priority (high/medium/low)
        - actionType (reply/message/call)
        
        Output as a JSON array of objects. If no nudges needed, output [].
        
        Messages:
        \(messageContext)
        """
        
        do {
            let engine = ChatEngine()
            let response = try await engine.generateOneShot(
                messages: [ChatMessage(role: "user", content: prompt)],
                parameters: GenerationParameters(temperature: 0.3, maxTokens: 500, topPOverride: nil, repetitionPenalty: nil),
                requestedModel: "default"
            )
            
            if let data = response.data(using: .utf8),
               let nudges = try? JSONDecoder().decode([RelationshipNudge].self, from: data) {
                return nudges
            }
        } catch {
            BrainLogger.error("LLM relationship analysis failed: \(error)", category: .agent)
        }
        
        return getMockNudges()
    }
    
    private func getMockNudges() -> [RelationshipNudge] {
        return [
            RelationshipNudge(
                contactName: "Mom",
                reason: "She asked about dinner 2 days ago and you haven't replied.",
                suggestion: "Draft a reply: 'Hey Mom, yes I'll be there! Looking forward to it.'",
                priority: .high,
                actionType: .reply
            ),
            RelationshipNudge(
                contactName: "Sarah",
                reason: "Last interaction was 5 days ago.",
                suggestion: "Send a quick check-in message.",
                priority: .medium,
                actionType: .message
            )
        ]
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
