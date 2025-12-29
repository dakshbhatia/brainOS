//
//  ChatTurnData.swift
//  BrainOS
//
//  Codable representation of ChatTurn for persistence
//

import Foundation

/// Codable version of ChatTurn for session persistence
struct ChatTurnData: Codable, Identifiable, Sendable {
    let id: UUID
    let role: OSMessageRole
    var content: String
    var attachedImages: [Data]
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var toolResults: [String: String]
    var thinking: String
    
    // MARK: - Semantic Memory Properties
    /// Quality score for this message (0.0-1.0) - higher means more valuable for recall
    var qualityScore: Double?
    /// OpenAI embedding vector for semantic search (1536 dimensions for text-embedding-3-small)
    var embedding: [Float]?
    /// Reference to parent message if this is a child chunk for hierarchical retrieval
    var parentMessageId: UUID?
    /// Index of this chunk in parent-child splitting strategy
    var chunkIndex: Int?
    /// Token count for context budget management
    var tokenCount: Int?

    init(
        id: UUID = UUID(),
        role: OSMessageRole,
        content: String,
        attachedImages: [Data] = [],
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        toolResults: [String: String] = [:],
        thinking: String = "",
        qualityScore: Double? = nil,
        embedding: [Float]? = nil,
        parentMessageId: UUID? = nil,
        chunkIndex: Int? = nil,
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachedImages = attachedImages
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolResults = toolResults
        self.thinking = thinking
        self.qualityScore = qualityScore
        self.embedding = embedding
        self.parentMessageId = parentMessageId
        self.chunkIndex = chunkIndex
        self.tokenCount = tokenCount
    }

    // Custom decoder for backward compatibility with sessions saved before thinking was added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(OSMessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachedImages = try container.decodeIfPresent([Data].self, forKey: .attachedImages) ?? []
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        toolResults = try container.decodeIfPresent([String: String].self, forKey: .toolResults) ?? [:]
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        qualityScore = try container.decodeIfPresent(Double.self, forKey: .qualityScore)
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding)
        parentMessageId = try container.decodeIfPresent(UUID.self, forKey: .parentMessageId)
        chunkIndex = try container.decodeIfPresent(Int.self, forKey: .chunkIndex)
        tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, attachedImages, toolCalls, toolCallId, toolResults, thinking
        case qualityScore, embedding, parentMessageId, chunkIndex, tokenCount
    }
}

// MARK: - Conversion Extensions

extension ChatTurnData {
    /// Convert from a ChatTurn instance
    @MainActor
    init(from turn: ChatTurn) {
        self.id = turn.id
        self.role = turn.role
        self.content = turn.content
        self.attachedImages = turn.attachedImages
        self.toolCalls = turn.toolCalls
        self.toolCallId = turn.toolCallId
        self.toolResults = turn.toolResults
        self.thinking = turn.thinking
        self.qualityScore = turn.qualityScore
        self.embedding = turn.embedding
        self.parentMessageId = turn.parentMessageId
        self.chunkIndex = turn.chunkIndex
        self.tokenCount = turn.tokenCount
    }
}

extension ChatTurn {
    /// Create a ChatTurn from persisted data
    convenience init(from data: ChatTurnData) {
        self.init(role: data.role, content: data.content, images: data.attachedImages)
        self.toolCalls = data.toolCalls
        self.toolCallId = data.toolCallId
        self.toolResults = data.toolResults
        self.thinking = data.thinking
        self.qualityScore = data.qualityScore
        self.embedding = data.embedding
        self.parentMessageId = data.parentMessageId
        self.chunkIndex = data.chunkIndex
        self.tokenCount = data.tokenCount
    }
}
