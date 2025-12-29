//
//  RelationshipProfile.swift
//  BrainOS
//
//  Comprehensive relationship profile model for the personal CRM system.
//

import Foundation

// MARK: - Relationship Tier

/// Categorizes relationships based on closeness and interaction frequency
public enum RelationshipTier: String, Codable, Sendable, CaseIterable {
    case innerCircle   // Top 5-10 people - family, best friends, partner
    case friends       // Regular contact - weekly or more
    case acquaintances // Occasional contact - monthly
    case fading        // Was active, now declining - hasn't been contacted in 14-60 days
    case dormant       // Haven't talked in 60+ days
    
    public var displayName: String {
        switch self {
        case .innerCircle: return "Inner Circle"
        case .friends: return "Friends"
        case .acquaintances: return "Acquaintances"
        case .fading: return "Fading"
        case .dormant: return "Dormant"
        }
    }
    
    public var emoji: String {
        switch self {
        case .innerCircle: return "💎"
        case .friends: return "👋"
        case .acquaintances: return "🤝"
        case .fading: return "⚠️"
        case .dormant: return "💤"
        }
    }
    
    public var priority: Int {
        switch self {
        case .innerCircle: return 4
        case .friends: return 3
        case .acquaintances: return 2
        case .fading: return 1
        case .dormant: return 0
        }
    }
}

// MARK: - Relationship Trajectory

/// Tracks whether a relationship is growing, stable, or declining
public enum RelationshipTrajectory: String, Codable, Sendable {
    case growing   // More interaction recently vs. previously
    case stable    // Consistent interaction level
    case declining // Less interaction recently
    
    public var emoji: String {
        switch self {
        case .growing: return "📈"
        case .stable: return "➡️"
        case .declining: return "📉"
        }
    }
    
    public var description: String {
        switch self {
        case .growing: return "Growing closer"
        case .stable: return "Stable"
        case .declining: return "Drifting apart"
        }
    }
}

// MARK: - Interaction Event

/// A single interaction with a contact
public struct InteractionEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let contactId: String
    public let eventType: InteractionType
    public let source: InteractionSource
    public let contentPreview: String?
    public let sentiment: Double?  // -1 to +1
    public let timestamp: Date
    public let isFromMe: Bool
    public let responseTimeSeconds: Int?
    
    public init(
        id: UUID = UUID(),
        contactId: String,
        eventType: InteractionType,
        source: InteractionSource,
        contentPreview: String? = nil,
        sentiment: Double? = nil,
        timestamp: Date,
        isFromMe: Bool,
        responseTimeSeconds: Int? = nil
    ) {
        self.id = id
        self.contactId = contactId
        self.eventType = eventType
        self.source = source
        self.contentPreview = contentPreview
        self.sentiment = sentiment
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.responseTimeSeconds = responseTimeSeconds
    }
    
    public enum InteractionType: String, Codable, Sendable {
        case messageSent
        case messageReceived
        case callMade
        case callReceived
        case meeting
        case tapback
    }
    
    public enum InteractionSource: String, Codable, Sendable {
        case imessage
        case sms
        case calendar
        case phone
        case email
    }
}

// MARK: - Smart Grouping Models

/// Groups related interactions (e.g. a single conversation session)
public struct InteractionGroup: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let messages: [MessageEntry]
    public let timestamp: Date
    public var summary: String
    
    public init(messages: [MessageEntry]) {
        self.messages = messages
        self.timestamp = messages.first?.timestamp ?? Date()
        
        // AI-ready summary of the group
        let first = messages.first?.text ?? ""
        if messages.count > 1 {
            self.summary = "\(first.prefix(30))... (+ \(messages.count - 1) more)"
        } else {
            self.summary = first
        }
    }
}

// MARK: - Relationship Profile

/// Complete profile for a single relationship
public struct RelationshipProfile: Identifiable, Codable, Sendable {
    public let id: String  // Contact identifier (phone number or email)
    
    // MARK: Core Identity
    public var name: String
    public var aliases: [String]  // "Mom", "Mother", phone number
    public var photoData: Data?
    
    // MARK: Quantitative Metrics
    public var relationshipScore: Double  // 0-100, computed
    public var interactionCount: Int
    public var firstInteraction: Date?
    public var lastInteraction: Date?
    
    // MARK: Communication Patterns
    public var averageResponseTimeSeconds: Double?
    public var messageBalance: Double  // -1 (you talk more) to +1 (they talk more)
    public var messagesSent: Int
    public var messagesReceived: Int
    public var peakInteractionDays: [Int]  // Day of week (1=Sunday, 7=Saturday)
    public var peakInteractionHours: [Int]  // Hour of day (0-23)
    
    // MARK: Qualitative
    public var sentimentScore: Double?  // -1 to +1, from message analysis
    public var tags: [String]  // "family", "work", "close friend"
    public var notes: String?
    
    // MARK: Derived Status
    public var tier: RelationshipTier
    public var trajectory: RelationshipTrajectory
    
    // MARK: Calendar Integration
    public var upcomingEventCount: Int
    public var sharedEventCount: Int
    
    // MARK: Timestamps
    public var updatedAt: Date
    
    // MARK: Initialization
    
    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        photoData: Data? = nil,
        relationshipScore: Double = 0,
        interactionCount: Int = 0,
        firstInteraction: Date? = nil,
        lastInteraction: Date? = nil,
        averageResponseTimeSeconds: Double? = nil,
        messageBalance: Double = 0,
        messagesSent: Int = 0,
        messagesReceived: Int = 0,
        peakInteractionDays: [Int] = [],
        peakInteractionHours: [Int] = [],
        sentimentScore: Double? = nil,
        tags: [String] = [],
        notes: String? = nil,
        tier: RelationshipTier = .acquaintances,
        trajectory: RelationshipTrajectory = .stable,
        upcomingEventCount: Int = 0,
        sharedEventCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.photoData = photoData
        self.relationshipScore = relationshipScore
        self.interactionCount = interactionCount
        self.firstInteraction = firstInteraction
        self.lastInteraction = lastInteraction
        self.averageResponseTimeSeconds = averageResponseTimeSeconds
        self.messageBalance = messageBalance
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.peakInteractionDays = peakInteractionDays
        self.peakInteractionHours = peakInteractionHours
        self.sentimentScore = sentimentScore
        self.tags = tags
        self.notes = notes
        self.tier = tier
        self.trajectory = trajectory
        self.upcomingEventCount = upcomingEventCount
        self.sharedEventCount = sharedEventCount
        self.updatedAt = updatedAt
    }
    
    // MARK: Computed Properties
    
    /// Days since last interaction
    public var daysSinceLastInteraction: Int? {
        guard let lastInteraction = lastInteraction else { return nil }
        return Calendar.current.dateComponents([.day], from: lastInteraction, to: Date()).day
    }
    
    /// Human-readable last interaction time
    public var lastInteractionDescription: String {
        guard let lastInteraction = lastInteraction else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastInteraction, relativeTo: Date())
    }
    
    /// Total messages exchanged
    public var totalMessages: Int {
        return messagesSent + messagesReceived
    }
    
    /// Whether this relationship needs attention
    public var needsAttention: Bool {
        guard let days = daysSinceLastInteraction else { return false }
        switch tier {
        case .innerCircle: return days > 7
        case .friends: return days > 14
        case .acquaintances: return days > 30
        case .fading, .dormant: return true
        }
    }
    
    /// Deep link URL for iMessage
    public var imessageDeepLink: URL? {
        // Try to create a valid imessage:// URL
        let cleanId = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return URL(string: "imessage://\(cleanId)")
    }
    
    /// Deep link URL for FaceTime audio call
    public var facetimeAudioDeepLink: URL? {
        let cleanId = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return URL(string: "facetime-audio://\(cleanId)")
    }
    
    /// Summary for display
    public var summary: String {
        var parts: [String] = []
        
        if !tags.isEmpty {
            parts.append(tags.prefix(2).joined(separator: ", "))
        }
        
        parts.append("\(totalMessages) messages")
        
        if let days = daysSinceLastInteraction {
            if days == 0 {
                parts.append("talked today")
            } else if days == 1 {
                parts.append("talked yesterday")
            } else {
                parts.append("\(days)d ago")
            }
        }
        
        return parts.joined(separator: " • ")
    }
}

// MARK: - Relationship Analytics

/// Aggregate analytics across all relationships
public struct RelationshipAnalytics: Codable, Sendable {
    public let totalContacts: Int
    public let activeContacts: Int  // Interacted in last 30 days
    public let innerCircleSize: Int
    public let friendsCount: Int
    public let fadingCount: Int
    public let dormantCount: Int
    
    public let averageResponseTimeSeconds: Double?
    public let messagesSentPerDay: Double
    public let messagesReceivedPerDay: Double
    public let mostActiveDay: String  // "Monday"
    public let mostActiveHour: Int
    
    // Self-awareness metrics
    public let initiationRate: Double  // % of conversations you start
    public let responseRate: Double    // % of messages you reply to
    public let ghostedCount: Int       // They didn't reply to you
    public let beenGhostedCount: Int   // You didn't reply to them
    
    public let socialHealthScore: Double  // 0-100
    
    public let generatedAt: Date
    
    public init(
        totalContacts: Int = 0,
        activeContacts: Int = 0,
        innerCircleSize: Int = 0,
        friendsCount: Int = 0,
        fadingCount: Int = 0,
        dormantCount: Int = 0,
        averageResponseTimeSeconds: Double? = nil,
        messagesSentPerDay: Double = 0,
        messagesReceivedPerDay: Double = 0,
        mostActiveDay: String = "Unknown",
        mostActiveHour: Int = 12,
        initiationRate: Double = 0.5,
        responseRate: Double = 1.0,
        ghostedCount: Int = 0,
        beenGhostedCount: Int = 0,
        socialHealthScore: Double = 50,
        generatedAt: Date = Date()
    ) {
        self.totalContacts = totalContacts
        self.activeContacts = activeContacts
        self.innerCircleSize = innerCircleSize
        self.friendsCount = friendsCount
        self.fadingCount = fadingCount
        self.dormantCount = dormantCount
        self.averageResponseTimeSeconds = averageResponseTimeSeconds
        self.messagesSentPerDay = messagesSentPerDay
        self.messagesReceivedPerDay = messagesReceivedPerDay
        self.mostActiveDay = mostActiveDay
        self.mostActiveHour = mostActiveHour
        self.initiationRate = initiationRate
        self.responseRate = responseRate
        self.ghostedCount = ghostedCount
        self.beenGhostedCount = beenGhostedCount
        self.socialHealthScore = socialHealthScore
        self.generatedAt = generatedAt
    }
    
    // MARK: Formatted Display
    
    public var formattedInitiationRate: String {
        return String(format: "%.0f%%", initiationRate * 100)
    }
    
    public var formattedResponseRate: String {
        return String(format: "%.0f%%", responseRate * 100)
    }
    
    public var formattedAverageResponseTime: String {
        guard let seconds = averageResponseTimeSeconds else { return "N/A" }
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        } else {
            return "\(Int(seconds / 86400))d"
        }
    }
}

// MARK: - Relationship Insight

/// An AI-generated insight about relationships
public struct RelationshipInsight: Identifiable, Codable, Sendable {
    public let id: UUID
    public let contactId: String?  // nil for global insights
    public let contactName: String?
    public let type: InsightType
    public let title: String
    public let description: String
    public let priority: Double  // 0-1
    public let action: InsightAction?
    public let createdAt: Date
    public var dismissed: Bool
    public var actedOn: Bool
    
    public init(
        id: UUID = UUID(),
        contactId: String? = nil,
        contactName: String? = nil,
        type: InsightType,
        title: String,
        description: String,
        priority: Double,
        action: InsightAction? = nil,
        createdAt: Date = Date(),
        dismissed: Bool = false,
        actedOn: Bool = false
    ) {
        self.id = id
        self.contactId = contactId
        self.contactName = contactName
        self.type = type
        self.title = title
        self.description = description
        self.priority = priority
        self.action = action
        self.createdAt = createdAt
        self.dismissed = dismissed
        self.actedOn = actedOn
    }
    
    public enum InsightType: String, Codable, Sendable {
        case pattern       // "You message Mom every Sunday"
        case drift         // "Lost touch with 5 college friends"
        case opportunity   // "3 friends have birthdays this week"
        case balance       // "You've been doing all the texting with Jake"
        case milestone     // "1 year since you met Sarah"
        case reconnect     // "You used to talk to Bob weekly"
        case celebration   // "Your relationship with Amy is thriving"
    }
    
    public enum InsightAction: Codable, Sendable {
        case message(contactId: String, suggestedText: String?)
        case call(contactId: String)
        case schedule(contactId: String)
        case viewProfile(contactId: String)
        case viewList(tier: RelationshipTier)
    }
    
    public var emoji: String {
        switch type {
        case .pattern: return "🔁"
        case .drift: return "🌊"
        case .opportunity: return "🎯"
        case .balance: return "⚖️"
        case .milestone: return "🏆"
        case .reconnect: return "🔗"
        case .celebration: return "🎉"
        }
    }
}

// MARK: - Recommended Action

/// A recommended action to take with a contact
public struct RecommendedAction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let contactId: String
    public let contactName: String
    public let actionType: ActionType
    public let reason: String
    public let priority: Double  // 0-1
    public let suggestedText: String?
    public let deepLinkURL: URL?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        contactId: String,
        contactName: String,
        actionType: ActionType,
        reason: String,
        priority: Double,
        suggestedText: String? = nil,
        deepLinkURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contactId = contactId
        self.contactName = contactName
        self.actionType = actionType
        self.reason = reason
        self.priority = priority
        self.suggestedText = suggestedText
        self.deepLinkURL = deepLinkURL
        self.createdAt = createdAt
    }
    
    public enum ActionType: String, Codable, Sendable {
        case sendMessage
        case reply
        case call
        case scheduleTime
        case sendBirthdayWish
        case followUp
        case checkIn
    }
    
    public var emoji: String {
        switch actionType {
        case .sendMessage: return "💬"
        case .reply: return "↩️"
        case .call: return "📞"
        case .scheduleTime: return "📅"
        case .sendBirthdayWish: return "🎂"
        case .followUp: return "🔔"
        case .checkIn: return "👋"
        }
    }
    
    public var actionTitle: String {
        switch actionType {
        case .sendMessage: return "Send Message"
        case .reply: return "Reply"
        case .call: return "Call"
        case .scheduleTime: return "Schedule Time"
        case .sendBirthdayWish: return "Send Birthday Wish"
        case .followUp: return "Follow Up"
        case .checkIn: return "Check In"
        }
    }
}
