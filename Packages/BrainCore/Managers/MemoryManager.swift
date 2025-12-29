//
//  MemoryManager.swift
//  BrainOS
//
//  Semantic memory management with episodic and tool recall
//

import Foundation

/// Actor-based semantic memory manager for intelligent message recall
actor MemoryManager {
    private let embeddingService: EmbeddingService
    
    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
    }
    
    // MARK: - Episodic Memory
    
    /// Find semantically similar messages to the current query
    /// - Parameters:
    ///   - query: Current user query
    ///   - allMessages: All messages from session history
    ///   - limit: Maximum number of similar messages to return
    ///   - minScore: Minimum similarity threshold (0.0-1.0)
    /// - Returns: Array of messages with similarity scores, sorted by relevance
    func findSimilarMessages(
        to query: String,
        in allMessages: [ChatTurnData],
        limit: Int = 5,
        minScore: Float = 0.75
    ) async throws -> [(message: ChatTurnData, score: Float)] {
        // Generate query embedding
        let queryEmbedding = try await embeddingService.embed(query)
        
        // Filter messages that have embeddings and calculate similarity
        var scoredMessages: [(message: ChatTurnData, score: Float)] = []
        
        for message in allMessages {
            guard let embedding = message.embedding else { continue }
            
            let similarity = EmbeddingService.cosineSimilarity(queryEmbedding, embedding)
            
            if similarity >= minScore {
                scoredMessages.append((message: message, score: similarity))
            }
        }
        
        // Sort by similarity (highest first) and return top results
        return scoredMessages
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Find messages with high quality scores (valuable for learning)
    /// - Parameters:
    ///   - allMessages: All messages from session history
    ///   - minQuality: Minimum quality threshold (0.0-1.0)
    ///   - limit: Maximum number to return
    /// - Returns: Array of high-quality messages
    func findQualityMessages(
        in allMessages: [ChatTurnData],
        minQuality: Double = 0.7,
        limit: Int = 10
    ) -> [ChatTurnData] {
        return allMessages
            .filter { ($0.qualityScore ?? 0.0) >= minQuality }
            .sorted { ($0.qualityScore ?? 0.0) > ($1.qualityScore ?? 0.0) }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Tool Memory
    
    /// Remember successful tool usage for future suggestions
    struct ToolMemory: Codable, Sendable {
        let id: UUID
        let toolName: String
        let query: String
        let embedding: [Float]
        let success: Bool
        let timestamp: Date
        
        init(toolName: String, query: String, embedding: [Float], success: Bool) {
            self.id = UUID()
            self.toolName = toolName
            self.query = query
            self.embedding = embedding
            self.success = success
            self.timestamp = Date()
        }
    }
    
    /// Store tool usage for learning
    func rememberToolUsage(
        _ toolName: String,
        forQuery query: String,
        success: Bool
    ) async throws -> ToolMemory {
        let embedding = try await embeddingService.embed(query)
        return ToolMemory(
            toolName: toolName,
            query: query,
            embedding: embedding,
            success: success
        )
    }
    
    /// Suggest tools based on semantic similarity to past successful uses
    /// - Parameters:
    ///   - query: Current user query
    ///   - toolMemories: Historical tool usage data
    ///   - limit: Maximum tools to suggest
    /// - Returns: Array of tool names with confidence scores
    func suggestTools(
        for query: String,
        from toolMemories: [ToolMemory],
        limit: Int = 3
    ) async throws -> [(toolName: String, confidence: Float)] {
        guard !toolMemories.isEmpty else { return [] }
        
        let queryEmbedding = try await embeddingService.embed(query)
        
        // Group by tool name and calculate average similarity for successful uses
        var toolScores: [String: [Float]] = [:]
        
        for memory in toolMemories where memory.success {
            let similarity = EmbeddingService.cosineSimilarity(queryEmbedding, memory.embedding)
            toolScores[memory.toolName, default: []].append(similarity)
        }
        
        // Calculate average confidence per tool
        let suggestions = toolScores.map { toolName, scores -> (String, Float) in
            let avgScore = scores.reduce(0.0, +) / Float(scores.count)
            return (toolName, avgScore)
        }
        
        return suggestions
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Quality Scoring Heuristics
    
    /// Assess message quality based on various factors
    /// - Parameter message: Message to assess
    /// - Returns: Quality score (0.0-1.0)
    static func assessQuality(of message: ChatTurnData) -> Double {
        var score = 0.5 // Base score
        
        let contentLength = message.content.count
        
        // Length factor (prefer meaningful content)
        if contentLength > 50 && contentLength < 2000 {
            score += 0.2
        } else if contentLength > 20 {
            score += 0.1
        }
        
        // Assistant responses with tool usage are valuable
        if message.role == .assistant && message.toolCalls != nil {
            score += 0.15
        }
        
        // User questions with context are valuable
        if message.role == .user && contentLength > 100 {
            score += 0.1
        }
        
        // Presence of code blocks indicates technical content
        if message.content.contains("```") {
            score += 0.05
        }
        
        // Cap at 1.0
        return min(score, 1.0)
    }
}
