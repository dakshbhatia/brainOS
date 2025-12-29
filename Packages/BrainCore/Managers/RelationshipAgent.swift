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
    
    // MARK: - Enhanced Relationship Profile Building
    
    /// Build comprehensive relationship profiles from iMessage data
    public func buildRelationshipProfiles() async -> [RelationshipProfile] {
        BrainLogger.info("Building comprehensive relationship profiles...", category: .agent)
        
        // Fetch a larger message pool for more accurate profiles
        let allMessages = (try? await BrainMessagesManager.shared.fetchRecentMessages(limit: 1000)) ?? []
        
        if allMessages.isEmpty {
            BrainLogger.info("No messages to analyze for profile building", category: .agent)
            return []
        }
        
        // Group messages by contact
        let contactGroups = Dictionary(grouping: allMessages) { message -> String in
            if message.isFromMe {
                // For messages I sent, we need to identify the recipient
                // Currently using sender which is me - we'd need chat_id for proper attribution
                return message.senderName ?? message.sender
            } else {
                return message.senderName ?? message.sender
            }
        }
        
        var profiles: [RelationshipProfile] = []
        
        for (contactId, messages) in contactGroups {
            // Skip empty or "Me" entries
            if contactId.isEmpty || contactId.lowercased() == "me" { continue }
            
            let profile = await buildProfileForContact(
                contactId: contactId,
                messages: messages,
                allMessages: allMessages
            )
            profiles.append(profile)
            
            // Save to database
            await BrainDatabaseManager.shared.saveRelationshipProfile(profile)
        }
        
        BrainLogger.info("Built \(profiles.count) relationship profiles", category: .agent)
        return profiles.sorted { $0.relationshipScore > $1.relationshipScore }
    }
    
    /// Build a profile for a single contact
    private func buildProfileForContact(
        contactId: String,
        messages: [MessageEntry],
        allMessages: [MessageEntry]
    ) async -> RelationshipProfile {
        let sortedMessages = messages.sorted { $0.timestamp > $1.timestamp }
        
        // Basic counts
        let sentMessages = messages.filter { $0.isFromMe }
        let receivedMessages = messages.filter { !$0.isFromMe }
        let messagesSent = sentMessages.count
        let messagesReceived = receivedMessages.count
        let totalMessages = messagesSent + messagesReceived
        
        // Time-based
        let lastInteraction = sortedMessages.first?.timestamp
        let firstInteraction = sortedMessages.last?.timestamp
        
        // Message balance: -1 (you talk more) to +1 (they talk more)
        let messageBalance: Double
        if totalMessages > 0 {
            messageBalance = Double(messagesReceived - messagesSent) / Double(totalMessages)
        } else {
            messageBalance = 0
        }
        
        // Calculate average response time (when you replied to them)
        let avgResponseTime = calculateAverageResponseTime(messages: sortedMessages)
        
        // Peak interaction days and hours
        let (peakDays, peakHours) = calculatePeakInteractionTimes(messages: messages)
        
        // Calculate relationship score
        let score = await calculateRelationshipScore(contactId: contactId)
        
        // Determine tier based on score and recency
        let tier = determineTier(score: score, lastInteraction: lastInteraction, totalMessages: totalMessages)
        
        // Determine trajectory
        let trajectory = await determineTrajectory(contactId: contactId, messages: messages)
        
        // Extract the best name
        let name = messages.first?.senderName ?? contactId
        
        return RelationshipProfile(
            id: contactId,
            name: name,
            aliases: [contactId],
            photoData: nil,
            relationshipScore: score,
            interactionCount: totalMessages,
            firstInteraction: firstInteraction,
            lastInteraction: lastInteraction,
            averageResponseTimeSeconds: avgResponseTime,
            messageBalance: messageBalance,
            messagesSent: messagesSent,
            messagesReceived: messagesReceived,
            peakInteractionDays: peakDays,
            peakInteractionHours: peakHours,
            sentimentScore: nil,  // Would require sentiment analysis
            tags: [],
            notes: nil,
            tier: tier,
            trajectory: trajectory,
            upcomingEventCount: 0,
            sharedEventCount: 0,
            updatedAt: Date()
        )
    }
    
    /// Calculate average response time
    private func calculateAverageResponseTime(messages: [MessageEntry]) -> Double? {
        var responseTimes: [Double] = []
        
        for i in 0..<messages.count - 1 {
            let current = messages[i]
            let next = messages[i + 1]
            
            // If I received a message and then sent one, calculate response time
            if !current.isFromMe && next.isFromMe {
                let responseTime = current.timestamp.timeIntervalSince(next.timestamp)
                if responseTime > 0 && responseTime < 86400 * 7 { // Max 7 days
                    responseTimes.append(abs(responseTime))
                }
            }
        }
        
        if responseTimes.isEmpty { return nil }
        return responseTimes.reduce(0, +) / Double(responseTimes.count)
    }
    
    /// Calculate peak interaction times
    private func calculatePeakInteractionTimes(messages: [MessageEntry]) -> ([Int], [Int]) {
        var dayCounts: [Int: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        
        for message in messages {
            let day = Calendar.current.component(.weekday, from: message.timestamp)
            let hour = Calendar.current.component(.hour, from: message.timestamp)
            dayCounts[day, default: 0] += 1
            hourCounts[hour, default: 0] += 1
        }
        
        // Get top 3 days and hours
        let topDays = dayCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        let topHours = hourCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        
        return (Array(topDays), Array(topHours))
    }
    
    /// Determine relationship tier
    private func determineTier(score: Double, lastInteraction: Date?, totalMessages: Int) -> RelationshipTier {
        let daysSinceContact = lastInteraction.map { Int(-$0.timeIntervalSinceNow / 86400) } ?? 999
        
        // Dormant check first
        if daysSinceContact > 60 {
            return .dormant
        }
        
        // Fading check
        if daysSinceContact > 14 && daysSinceContact <= 60 {
            return .fading
        }
        
        // Active contacts - tier by score
        if score >= 70 && totalMessages >= 50 {
            return .innerCircle
        } else if score >= 40 && totalMessages >= 20 {
            return .friends
        } else {
            return .acquaintances
        }
    }
    
    /// Determine if relationship is growing, stable, or declining
    private func determineTrajectory(contactId: String, messages: [MessageEntry]) async -> RelationshipTrajectory {
        // Compare last 14 days to previous 14 days
        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: now)!
        
        let recentCount = messages.filter { $0.timestamp >= twoWeeksAgo }.count
        let previousCount = messages.filter { $0.timestamp >= fourWeeksAgo && $0.timestamp < twoWeeksAgo }.count
        
        if recentCount > previousCount * 2 {
            return .growing
        } else if recentCount < previousCount / 2 {
            return .declining
        } else {
            return .stable
        }
    }
    
    // MARK: - Comprehensive Analytics
    
    /// Get complete relationship analytics
    public func getRelationshipAnalytics() async -> RelationshipAnalytics {
        BrainLogger.info("Computing relationship analytics...", category: .agent)
        
        let profiles = await BrainDatabaseManager.shared.getAllRelationshipProfiles()
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        
        // Count by tier
        var tierCounts: [RelationshipTier: Int] = [:]
        for tier in RelationshipTier.allCases {
            tierCounts[tier] = 0
        }
        
        var totalMessagesLast30Days = 0
        var responseTimeSumSeconds: Double = 0
        var responseTimeCount = 0
        var initiationCount = 0
        var totalConversations = 0
        var ghostedCount = 0
        var beenGhostedCount = 0
        
        for profile in profiles {
            tierCounts[profile.tier, default: 0] += 1
            
            // Calculate messages in last 30 days
            if let lastInteraction = profile.lastInteraction, lastInteraction >= thirtyDaysAgo {
                totalMessagesLast30Days += profile.messagesSent + profile.messagesReceived
            }
            
            // Response time
            if let responseTime = profile.averageResponseTimeSeconds {
                responseTimeSumSeconds += responseTime
                responseTimeCount += 1
            }
            
            // Initiation tracking (if you send more than receive, you're initiating more)
            if profile.messagesSent > profile.messagesReceived {
                initiationCount += 1
            }
            totalConversations += 1
            
            // Ghost detection (simplified - if balance is heavily towards them, you're ghosting)
            if profile.messageBalance > 0.5 {
                ghostedCount += 1
            } else if profile.messageBalance < -0.5 {
                beenGhostedCount += 1
            }
        }
        
        let totalContacts = profiles.count
        let activeContacts = profiles.filter { profile in
            guard let last = profile.lastInteraction else { return false }
            return last >= thirtyDaysAgo
        }.count
        
        let avgResponseTime: Double? = responseTimeCount > 0 ? responseTimeSumSeconds / Double(responseTimeCount) : nil
        let messagesPerDay = Double(totalMessagesLast30Days) / 30.0
        
        // Find most active day/hour from all messages
        let allMessages = (try? await BrainMessagesManager.shared.fetchRecentMessages(limit: 500)) ?? []
        var dayCounts: [Int: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        var sentCount = 0
        var receivedCount = 0
        
        for msg in allMessages {
            let day = Calendar.current.component(.weekday, from: msg.timestamp)
            let hour = Calendar.current.component(.hour, from: msg.timestamp)
            dayCounts[day, default: 0] += 1
            hourCounts[hour, default: 0] += 1
            if msg.isFromMe {
                sentCount += 1
            } else {
                receivedCount += 1
            }
        }
        
        let mostActiveDay = dayCounts.max(by: { $0.value < $1.value })?.key ?? 1
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let mostActiveDayName = dayNames[mostActiveDay]
        let mostActiveHour = hourCounts.max(by: { $0.value < $1.value })?.key ?? 12
        
        // Calculate social health score
        let socialHealthScore = calculateSocialHealthScore(
            activeContacts: activeContacts,
            totalContacts: totalContacts,
            innerCircleSize: tierCounts[.innerCircle] ?? 0,
            initiationRate: totalConversations > 0 ? Double(initiationCount) / Double(totalConversations) : 0.5,
            fadingCount: tierCounts[.fading] ?? 0,
            dormantCount: tierCounts[.dormant] ?? 0
        )
        
        return RelationshipAnalytics(
            totalContacts: totalContacts,
            activeContacts: activeContacts,
            innerCircleSize: tierCounts[.innerCircle] ?? 0,
            friendsCount: tierCounts[.friends] ?? 0,
            fadingCount: tierCounts[.fading] ?? 0,
            dormantCount: tierCounts[.dormant] ?? 0,
            averageResponseTimeSeconds: avgResponseTime,
            messagesSentPerDay: Double(sentCount) / 30.0,
            messagesReceivedPerDay: Double(receivedCount) / 30.0,
            mostActiveDay: mostActiveDayName,
            mostActiveHour: mostActiveHour,
            initiationRate: totalConversations > 0 ? Double(initiationCount) / Double(totalConversations) : 0.5,
            responseRate: 1.0 - (Double(ghostedCount) / Double(max(1, totalContacts))),
            ghostedCount: beenGhostedCount,
            beenGhostedCount: ghostedCount,
            socialHealthScore: socialHealthScore,
            generatedAt: Date()
        )
    }
    
    /// Calculate overall social health score
    private func calculateSocialHealthScore(
        activeContacts: Int,
        totalContacts: Int,
        innerCircleSize: Int,
        initiationRate: Double,
        fadingCount: Int,
        dormantCount: Int
    ) -> Double {
        var score: Double = 50.0  // Base score
        
        // Active engagement (0-25 pts)
        let activeRatio = totalContacts > 0 ? Double(activeContacts) / Double(totalContacts) : 0
        score += activeRatio * 25.0
        
        // Inner circle health (0-15 pts) - 3-7 is ideal
        let idealInnerCircle = innerCircleSize >= 3 && innerCircleSize <= 7
        if idealInnerCircle {
            score += 15.0
        } else if innerCircleSize > 0 {
            score += 7.0
        }
        
        // Initiation balance (0-10 pts) - 40-60% is balanced
        let balancedInitiation = initiationRate >= 0.4 && initiationRate <= 0.6
        if balancedInitiation {
            score += 10.0
        } else if initiationRate >= 0.3 && initiationRate <= 0.7 {
            score += 5.0
        }
        
        // Penalty for drifting relationships
        let driftPenalty = min(20.0, Double(fadingCount + dormantCount) * 2.0)
        score -= driftPenalty
        
        return min(100, max(0, score))
    }
    
    // MARK: - Relationship Insights
    
    /// Generate AI-powered relationship insights
    public func generateRelationshipInsights() async -> [RelationshipInsight] {
        let profiles = await BrainDatabaseManager.shared.getAllRelationshipProfiles()
        let analytics = await getRelationshipAnalytics()
        
        var insights: [RelationshipInsight] = []
        
        // Insight 1: Social drift warning
        let fadingProfiles = profiles.filter { $0.tier == .fading }
        if fadingProfiles.count >= 3 {
            insights.append(RelationshipInsight(
                type: .drift,
                title: "Social Drift Detected",
                description: "You've lost touch with \(fadingProfiles.count) people recently: \(fadingProfiles.prefix(3).map(\.name).joined(separator: ", ")). Consider reaching out.",
                priority: 0.8,
                action: .viewList(tier: .fading)
            ))
        }
        
        // Insight 2: Balance issues
        let unbalancedProfiles = profiles.filter { $0.messageBalance < -0.4 }  // You talk much more
        if let first = unbalancedProfiles.first {
            insights.append(RelationshipInsight(
                contactId: first.id,
                contactName: first.name,
                type: .balance,
                title: "One-sided conversation with \(first.name)",
                description: "You've sent \(first.messagesSent) messages but only received \(first.messagesReceived). They might be busy, or it's time to give them space.",
                priority: 0.5
            ))
        }
        
        // Insight 3: Inner circle health
        if analytics.innerCircleSize < 3 {
            insights.append(RelationshipInsight(
                type: .pattern,
                title: "Nurture Your Inner Circle",
                description: "You have only \(analytics.innerCircleSize) people in your inner circle. Consider deepening a few friendships.",
                priority: 0.6
            ))
        }
        
        // Insight 4: Growing relationships (celebration)
        let growingProfiles = profiles.filter { $0.trajectory == .growing }
        if let growing = growingProfiles.first {
            insights.append(RelationshipInsight(
                contactId: growing.id,
                contactName: growing.name,
                type: .celebration,
                title: "Growing Closer to \(growing.name)",
                description: "Your conversations with \(growing.name) have increased recently. Keep the momentum!",
                priority: 0.4
            ))
        }
        
        // Insight 5: Response patterns
        if analytics.initiationRate > 0.7 {
            insights.append(RelationshipInsight(
                type: .pattern,
                title: "You're Often the Initiator",
                description: "You start \(Int(analytics.initiationRate * 100))% of conversations. Others might reach out more if you wait sometimes.",
                priority: 0.5
            ))
        }
        
        // Save insights to database
        for insight in insights {
            await BrainDatabaseManager.shared.saveRelationshipInsight(insight)
        }
        
        return insights.sorted { $0.priority > $1.priority }
    }
    
    // MARK: - Recommended Actions
    
    /// Get recommended actions based on relationship state
    public func getRecommendedActions(limit: Int = 5) async -> [RecommendedAction] {
        let profiles = await BrainDatabaseManager.shared.getRelationshipsNeedingAttention()
        var actions: [RecommendedAction] = []
        
        for profile in profiles.prefix(limit) {
            let action = createActionForProfile(profile)
            actions.append(action)
        }
        
        return actions.sorted { $0.priority > $1.priority }
    }
    
    /// Create an appropriate action for a profile
    private func createActionForProfile(_ profile: RelationshipProfile) -> RecommendedAction {
        let daysSince = profile.daysSinceLastInteraction ?? 999
        
        let actionType: RecommendedAction.ActionType
        let reason: String
        let priority: Double
        
        switch profile.tier {
        case .innerCircle:
            actionType = .checkIn
            reason = "Haven't chatted with \(profile.name) in \(daysSince) days - they're in your inner circle!"
            priority = 0.9
            
        case .friends:
            actionType = .sendMessage
            reason = "It's been \(daysSince) days since you talked to \(profile.name)."
            priority = 0.7
            
        case .fading:
            actionType = .checkIn
            reason = "\(profile.name) is drifting away - last contact was \(daysSince) days ago."
            priority = 0.6
            
        case .dormant:
            actionType = .sendMessage
            reason = "Reconnection opportunity: you haven't talked to \(profile.name) in \(daysSince) days."
            priority = 0.4
            
        case .acquaintances:
            actionType = .sendMessage
            reason = "Consider reaching out to \(profile.name)."
            priority = 0.3
        }
        
        return RecommendedAction(
            contactId: profile.id,
            contactName: profile.name,
            actionType: actionType,
            reason: reason,
            priority: priority,
            suggestedText: nil,  // Will be generated lazily via generateSuggestedMessage()
            deepLinkURL: profile.imessageDeepLink
        )
    }
    
    // MARK: - AI-Generated Message Suggestions
    
    /// Generate a personalized message suggestion using local AI model
    /// This uses your local MLX model to create contextually appropriate messages
    public func generateSuggestedMessage(for profile: RelationshipProfile) async -> String? {
        BrainLogger.info("Generating AI message suggestion for \(profile.name)...", category: .agent)
        
        // Get recent conversation context
        let recentMessages = (try? await BrainMessagesManager.shared.fetchRecentMessages(
            limit: 10,
            contactName: profile.name
        )) ?? []
        
        let conversationContext: String
        if recentMessages.isEmpty {
            conversationContext = "No recent messages found with this person."
        } else {
            let preview = recentMessages.prefix(5).compactMap { msg -> String? in
                guard let text = msg.text, !text.isEmpty else { return nil }
                let direction = msg.isFromMe ? "You" : profile.name
                return "\(direction): \(text.prefix(100))"
            }.joined(separator: "\n")
            conversationContext = preview
        }
        
        let daysSince = profile.daysSinceLastInteraction ?? 0
        let relationshipContext = """
        Relationship tier: \(profile.tier.displayName)
        Days since last contact: \(daysSince)
        Message balance: \(profile.messageBalance > 0 ? "They message more" : "You message more")
        Relationship trajectory: \(profile.trajectory.description)
        """
        
        let systemPrompt = """
        You are helping compose a friendly, natural message to reconnect with someone.
        
        Rules:
        - Be casual and warm, not formal
        - Keep it short (1-2 sentences max)
        - Reference something natural like checking in, thinking of them
        - DON'T be generic - make it feel personal
        - DON'T include greetings like "Hey" at the start
        - Output ONLY the message text, nothing else
        """
        
        let userPrompt = """
        Help me write a message to \(profile.name).
        
        \(relationshipContext)
        
        Recent conversation:
        \(conversationContext)
        
        Write a short, natural message to reconnect:
        """
        
        do {
            let engine = ChatEngine()
            let request = ChatCompletionRequest(
                model: "default",
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt)
                ],
                temperature: 0.8,
                max_tokens: 80
            )
            
            let response = try await engine.completeChat(request: request)
            
            if let content = response.choices.first?.message.content {
                let cleaned = content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                return cleaned.isEmpty ? nil : cleaned
            }
        } catch {
            BrainLogger.error("Failed to generate message suggestion: \(error)", category: .agent)
        }
        
        // Fallback to simple templates if AI fails
        return getFallbackSuggestion(for: profile)
    }
    
    /// Simple fallback suggestions when AI is unavailable
    private func getFallbackSuggestion(for profile: RelationshipProfile) -> String? {
        let daysSince = profile.daysSinceLastInteraction ?? 0
        
        switch profile.tier {
        case .innerCircle:
            return "Been thinking about you! How's everything going?"
        case .friends:
            return "Hope you're doing well! Wanted to check in."
        case .fading:
            if daysSince > 30 {
                return "It's been a while! Would love to catch up sometime."
            }
            return "Hey! How have you been?"
        case .dormant, .acquaintances:
            return nil
        }
    }
    
    /// Get recommended actions with AI-generated suggestions (optional, more expensive)
    public func getRecommendedActionsWithSuggestions(limit: Int = 3) async -> [RecommendedAction] {
        let profiles = await BrainDatabaseManager.shared.getRelationshipsNeedingAttention()
        var actions: [RecommendedAction] = []
        
        for profile in profiles.prefix(limit) {
            var action = createActionForProfile(profile)
            
            // Generate AI suggestion for high-priority actions
            if action.priority >= 0.6 {
                if let suggestion = await generateSuggestedMessage(for: profile) {
                    action = RecommendedAction(
                        id: action.id,
                        contactId: action.contactId,
                        contactName: action.contactName,
                        actionType: action.actionType,
                        reason: action.reason,
                        priority: action.priority,
                        suggestedText: suggestion,
                        deepLinkURL: action.deepLinkURL,
                        createdAt: action.createdAt
                    )
                }
            }
            
            actions.append(action)
        }
        
        return actions.sorted { $0.priority > $1.priority }
    }
    
    // MARK: - Search
    
    /// Search relationships by natural language query
    public func searchRelationships(
        query: String,
        tier: RelationshipTier? = nil,
        minScore: Double? = nil
    ) async -> [RelationshipProfile] {
        var profiles = await BrainDatabaseManager.shared.getAllRelationshipProfiles()
        
        // Filter by tier if specified
        if let tier = tier {
            profiles = profiles.filter { $0.tier == tier }
        }
        
        // Filter by minimum score if specified
        if let minScore = minScore {
            profiles = profiles.filter { $0.relationshipScore >= minScore }
        }
        
        // Simple keyword search for now
        let queryLower = query.lowercased()
        
        // Natural language patterns
        if queryLower.contains("inner circle") || queryLower.contains("close") || queryLower.contains("best") {
            profiles = profiles.filter { $0.tier == .innerCircle }
        } else if queryLower.contains("neglect") || queryLower.contains("forgot") || queryLower.contains("haven't") {
            profiles = profiles.filter { $0.tier == .fading || $0.tier == .dormant }
        } else if queryLower.contains("growing") || queryLower.contains("new") {
            profiles = profiles.filter { $0.trajectory == .growing }
        } else if queryLower.contains("declin") || queryLower.contains("drift") {
            profiles = profiles.filter { $0.trajectory == .declining || $0.tier == .fading }
        } else {
            // Name search
            profiles = profiles.filter { profile in
                profile.name.lowercased().contains(queryLower) ||
                profile.aliases.contains { $0.lowercased().contains(queryLower) } ||
                profile.tags.contains { $0.lowercased().contains(queryLower) }
            }
        }
        
        return profiles.sorted { $0.relationshipScore > $1.relationshipScore }
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

