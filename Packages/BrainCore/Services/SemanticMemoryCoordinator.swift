//
//  SemanticMemoryCoordinator.swift
//  BrainOS
//
//  Coordinates semantic memory features with existing chat flow
//

import Foundation

/// High-level coordinator for semantic memory integration
@MainActor
class SemanticMemoryCoordinator: ObservableObject {
    private let embeddingService: EmbeddingService
    private let memoryManager: MemoryManager
    private let contextBuilder: ContextBuilder
    
    @Published var isProcessingEmbeddings = false
    @Published var lastError: Error?
    
    // MARK: - Initialization
    
    /// Initialize coordinator with OpenAI API key
    init(openAIKey: String) {
        let embeddingService = EmbeddingService(apiKey: openAIKey)
        self.embeddingService = embeddingService
        self.memoryManager = MemoryManager(embeddingService: embeddingService)
        self.contextBuilder = ContextBuilder(memoryManager: memoryManager)
    }
    
    // MARK: - Message Processing
    
    /// Process a new message: generate embedding and assess quality
    /// Call this after a message is added to the conversation
    func processNewMessage(_ message: ChatTurnData, inSession sessionId: UUID) async {
        guard !message.content.isEmpty else { return }
        
        do {
            // Generate embedding
            let embedding = try await embeddingService.embed(message.content)
            
            // Assess quality
            let quality = MemoryManager.assessQuality(of: message)
            
            // Update message
            var updatedMessage = message
            updatedMessage.embedding = embedding
            updatedMessage.qualityScore = quality
            updatedMessage.tokenCount = ContextBuilder.estimateTokens(for: message)
            
            // Save to storage
            MemoryStorage.updateMessage(updatedMessage, inSession: sessionId)
            
        } catch {
            lastError = error
            print("[BrainOS] Failed to process message embedding: \(error)")
        }
    }
    
    /// Process all messages in a session that don't have embeddings yet
    /// Good for backfilling historical sessions
    func processSessionEmbeddings(sessionId: UUID) async {
        isProcessingEmbeddings = true
        defer { isProcessingEmbeddings = false }
        
        do {
            try await MemoryStorage.processEmbeddings(
                for: sessionId,
                using: embeddingService
            )
        } catch {
            lastError = error
            print("[BrainOS] Failed to process session embeddings: \(error)")
        }
    }
    
    // MARK: - Context Building
    
    /// Build smart context for a new query using semantic memory
    /// Returns optimized message history for the API call
    func buildSmartContext(
        query: String,
        sessionId: UUID,
        strategy: ContextBuilder.Strategy = .balanced
    ) async throws -> [ChatTurnData] {
        guard let session = ChatSessionStore.load(id: sessionId) else {
            return []
        }
        
        return try await contextBuilder.buildContext(
            for: query,
            from: session.turns,
            strategy: strategy
        )
    }
    
    /// Build segmented context (recent + retrieved) for explicit memory injection
    func buildSegmentedContext(
        query: String,
        sessionId: UUID
    ) async throws -> (recent: [ChatTurnData], retrieved: [ChatTurnData]) {
        guard let session = ChatSessionStore.load(id: sessionId) else {
            return ([], [])
        }
        
        return try await contextBuilder.buildSegmentedContext(
            for: query,
            from: session.turns,
            recentCount: 10
        )
    }
    
    // MARK: - Semantic Search
    
    /// Find similar messages across all sessions
    func searchMemory(query: String, limit: Int = 10) async throws -> [(message: ChatTurnData, score: Float)] {
        let allMessages = MemoryStorage.loadEmbeddedMessages()
        
        return try await memoryManager.findSimilarMessages(
            to: query,
            in: allMessages,
            limit: limit,
            minScore: 0.7
        )
    }
    
    /// Search within a specific session
    func searchSession(
        query: String,
        sessionId: UUID,
        limit: Int = 5
    ) async throws -> [(message: ChatTurnData, score: Float)] {
        guard let session = ChatSessionStore.load(id: sessionId) else {
            return []
        }
        
        return try await memoryManager.findSimilarMessages(
            to: query,
            in: session.turns,
            limit: limit,
            minScore: 0.75
        )
    }
    
    // MARK: - Tool Suggestions
    
    /// Remember tool usage for learning
    func rememberToolUse(
        toolName: String,
        query: String,
        success: Bool
    ) async {
        do {
            let memory = try await memoryManager.rememberToolUsage(
                toolName,
                forQuery: query,
                success: success
            )
            MemoryStorage.addToolMemory(memory)
        } catch {
            lastError = error
            print("[BrainOS] Failed to remember tool usage: \(error)")
        }
    }
    
    /// Get tool suggestions based on query
    func suggestTools(for query: String, limit: Int = 3) async throws -> [(toolName: String, confidence: Float)] {
        let toolMemories = MemoryStorage.loadToolMemories()
        
        return try await memoryManager.suggestTools(
            for: query,
            from: toolMemories,
            limit: limit
        )
    }
    
    // MARK: - Quality Analysis
    
    /// Get high-quality messages from current session
    func getQualityMessages(sessionId: UUID, minQuality: Double = 0.7) -> [ChatTurnData] {
        guard let session = ChatSessionStore.load(id: sessionId) else {
            return []
        }
        
        return session.turns.filter { ($0.qualityScore ?? 0.0) >= minQuality }
    }
    
    /// Get quality statistics for a session
    func getSessionStats(sessionId: UUID) -> SessionStats? {
        guard let session = ChatSessionStore.load(id: sessionId) else {
            return nil
        }
        
        let messagesWithEmbeddings = session.turns.filter { $0.embedding != nil }.count
        let qualityScores = session.turns.compactMap { $0.qualityScore }
        let avgQuality = qualityScores.isEmpty ? 0.0 : qualityScores.reduce(0.0, +) / Double(qualityScores.count)
        
        return SessionStats(
            totalMessages: session.turns.count,
            embeddedMessages: messagesWithEmbeddings,
            averageQuality: avgQuality,
            highQualityMessages: session.turns.filter { ($0.qualityScore ?? 0.0) >= 0.7 }.count
        )
    }
    
    struct SessionStats {
        let totalMessages: Int
        let embeddedMessages: Int
        let averageQuality: Double
        let highQualityMessages: Int
        
        var embeddingProgress: Double {
            guard totalMessages > 0 else { return 0.0 }
            return Double(embeddedMessages) / Double(totalMessages)
        }
    }
}

// MARK: - Usage Examples

/*
 INTEGRATION EXAMPLE 1: Process messages as they're created
 
 // In ChatView or wherever messages are added:
 let coordinator = SemanticMemoryCoordinator(openAIKey: "your-key")
 
 // After adding a message to the session:
 Task {
     await coordinator.processNewMessage(newMessage, inSession: sessionId)
 }
 
 
 INTEGRATION EXAMPLE 2: Smart context for API calls
 
 // Before sending to ChatEngine:
 let smartContext = try await coordinator.buildSmartContext(
     query: userMessage,
     sessionId: currentSessionId,
     strategy: .balanced
 )
 
 // Use smartContext instead of session.turns for the API request
 
 
 INTEGRATION EXAMPLE 3: Tool usage tracking
 
 // After a tool is executed:
 Task {
     await coordinator.rememberToolUse(
         toolName: "BrainCalendar",
         query: userQuery,
         success: toolResult.success
     )
 }
 
 // Before processing a query:
 let suggestions = try await coordinator.suggestTools(for: userQuery)
 // Use suggestions to pre-filter or prioritize tools
 
 
 INTEGRATION EXAMPLE 4: Backfill existing sessions
 
 // Run once to process historical data:
 for session in ChatSessionStore.loadAll() {
     await coordinator.processSessionEmbeddings(sessionId: session.id)
 }
 */
