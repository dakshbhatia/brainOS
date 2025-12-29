//
//  ContextBuilder.swift
//  BrainOS
//
//  Intelligent context window management with semantic memory
//

import Foundation

/// Builds optimized context windows by combining recent and semantically relevant messages
actor ContextBuilder {
    private let memoryManager: MemoryManager
    private let maxTokens: Int
    
    /// Initialize context builder
    /// - Parameters:
    ///   - memoryManager: Semantic memory manager for finding relevant history
    ///   - maxTokens: Maximum tokens to use for context (default 8000 for typical model limits)
    init(memoryManager: MemoryManager, maxTokens: Int = 8000) {
        self.memoryManager = memoryManager
        self.maxTokens = maxTokens
    }
    
    // MARK: - Context Building
    
    /// Build smart context by combining recent messages with semantically relevant ones
    /// - Parameters:
    ///   - query: Current user query
    ///   - allMessages: Complete message history from session
    ///   - recentCount: Number of most recent messages to always include
    /// - Returns: Array of messages optimized for context window
    func buildContext(
        for query: String,
        from allMessages: [ChatTurnData],
        recentCount: Int = 10
    ) async throws -> [ChatTurnData] {
        guard !allMessages.isEmpty else { return [] }
        
        // Step 1: Take the most recent N messages (conversational continuity)
        let recentMessages = Array(allMessages.suffix(recentCount))
        var contextMessages = recentMessages
        var usedTokens = estimateTokens(for: recentMessages)
        
        // Step 2: Find semantically similar messages from earlier history
        let olderMessages = Array(allMessages.dropLast(recentCount))
        
        if !olderMessages.isEmpty && usedTokens < maxTokens {
            let similarMessages = try await memoryManager.findSimilarMessages(
                to: query,
                in: olderMessages,
                limit: 5,
                minScore: 0.75
            )
            
            // Add similar messages until we hit token budget
            var addedIds = Set(recentMessages.map { $0.id })
            
            for (message, _) in similarMessages {
                guard !addedIds.contains(message.id) else { continue }
                
                let messageTokens = estimateTokens(for: [message])
                if usedTokens + messageTokens > maxTokens {
                    break
                }
                
                // Insert semantically relevant message
                contextMessages.insert(message, at: 0)
                addedIds.insert(message.id)
                usedTokens += messageTokens
            }
        }
        
        // Step 3: Sort chronologically to maintain conversation flow
        return contextMessages.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    
    /// Build context with explicit semantic retrieval section
    /// This creates a "memory injection" pattern where retrieved context is clearly marked
    /// - Parameters:
    ///   - query: Current user query
    ///   - allMessages: Complete message history
    ///   - recentCount: Number of recent messages to include
    /// - Returns: Tuple of (recent messages, retrieved context messages)
    func buildSegmentedContext(
        for query: String,
        from allMessages: [ChatTurnData],
        recentCount: Int = 10
    ) async throws -> (recent: [ChatTurnData], retrieved: [ChatTurnData]) {
        guard !allMessages.isEmpty else { return ([], []) }
        
        let recentMessages = Array(allMessages.suffix(recentCount))
        let olderMessages = Array(allMessages.dropLast(recentCount))
        
        var retrievedMessages: [ChatTurnData] = []
        
        if !olderMessages.isEmpty {
            let similarMessages = try await memoryManager.findSimilarMessages(
                to: query,
                in: olderMessages,
                limit: 3,
                minScore: 0.75
            )
            
            retrievedMessages = similarMessages.map { $0.message }
        }
        
        return (recentMessages, retrievedMessages)
    }
    
    // MARK: - Token Estimation
    
    /// Simple token estimation (roughly 4 characters per token for English)
    private func estimateTokens(for messages: [ChatTurnData]) -> Int {
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        return totalChars / 4
    }
    
    /// Estimate tokens for a single message
    static func estimateTokens(for message: ChatTurnData) -> Int {
        return message.content.count / 4
    }
}

// MARK: - Context Strategies

extension ContextBuilder {
    /// Strategy for different context needs
    enum Strategy {
        /// Maximize recent context (good for ongoing conversations)
        case recentHeavy
        /// Balance recent and semantic (good for mixed tasks)
        case balanced
        /// Prioritize semantic matches (good for retrieval-heavy tasks)
        case semanticHeavy
        
        var recentMessageCount: Int {
            switch self {
            case .recentHeavy: return 15
            case .balanced: return 10
            case .semanticHeavy: return 5
            }
        }
        
        var semanticMessageCount: Int {
            switch self {
            case .recentHeavy: return 2
            case .balanced: return 5
            case .semanticHeavy: return 8
            }
        }
    }
    
    /// Build context using a specific strategy
    func buildContext(
        for query: String,
        from allMessages: [ChatTurnData],
        strategy: Strategy
    ) async throws -> [ChatTurnData] {
        return try await buildContext(
            for: query,
            from: allMessages,
            recentCount: strategy.recentMessageCount
        )
    }
}
