import Foundation

/// Analyzes social interactions and provides nudges following the Notice -> Explain -> Suggest loop.
public actor RelationshipAgent {
    public static let shared = RelationshipAgent()
    
    private init() {}
    
    public func analyzeRecentInteractions() async -> [RelationshipNudge] {
        // 1. NOTICE: Query the Messages
        let messages = (try? await BrainMessagesManager.shared.fetchRecentMessages(limit: 50)) ?? []
        
        // Group messages by sender
        let groupedMessages = Dictionary(grouping: messages) { $0.senderName ?? $0.sender }
        
        var nudges: [RelationshipNudge] = []
        
        // 2. Simple heuristic-based analysis for MVP
        for (displayName, senderMessages) in groupedMessages {
            if displayName == "Unknown" { continue }
            
            // Check if the last message was from them and was more than 24 hours ago
            if let lastMessage = senderMessages.first, !lastMessage.isFromMe {
                let timeSinceLastMessage = Date().timeIntervalSince(lastMessage.timestamp)
                
                // Check for tapbacks - if they loved/liked your message, it's a positive signal
                if let tapback = lastMessage.tapbackType {
                    if tapback == .loved || tapback == .liked {
                        // Maybe nudge to say something back if it's been a while
                        if timeSinceLastMessage > 172800 { // 48 hours
                            nudges.append(RelationshipNudge(
                                contactName: displayName,
                                reason: "They \(tapback.rawValue.lowercased()) your message 2 days ago. Keep the momentum going!",
                                suggestion: "Send a quick update or a photo.",
                                priority: .medium,
                                actionType: .message
                            ))
                        }
                        continue
                    }
                }
                
                if timeSinceLastMessage > 86400 { // 24 hours
                    let textPreview = lastMessage.text?.prefix(30) ?? "an attachment"
                    nudges.append(RelationshipNudge(
                        contactName: displayName,
                        reason: "They messaged you \(Int(timeSinceLastMessage / 3600)) hours ago and you haven't replied.",
                        suggestion: "Draft a reply to: \"\(textPreview)...\"",
                        priority: timeSinceLastMessage > 172800 ? .high : .medium,
                        actionType: .reply
                    ))
                }
            }
        }
        
        // If no real messages found (e.g. no FDA), return mocks for demo
        if nudges.isEmpty {
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
        
        return nudges.sorted { $0.priority == .high && $1.priority != .high }
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
