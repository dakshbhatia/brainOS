//
//  ChatTurn.swift
//  BrainOS
//
//  Reference-type chat turn for efficient UI updates
//

import Combine
import Foundation

final class ChatTurn: ObservableObject, Identifiable {
    let id = UUID()
    @Published var role: OSMessageRole
    @Published var content: String
    /// Attached images for multimodal messages (stored as PNG data)
    @Published var attachedImages: [Data] = []
    /// Assistant-issued tool calls attached to this turn (OpenAI compatible)
    @Published var toolCalls: [ToolCall]? = nil
    /// For role==.tool messages, associates this result with the originating call id
    var toolCallId: String? = nil
    /// Convenience map for UI to show tool results grouped under the assistant turn
    @Published var toolResults: [String: String] = [:]
    /// Thinking/reasoning content from models that support extended thinking (e.g., DeepSeek, QwQ)
    @Published var thinking: String = ""
    
    // MARK: - Semantic Memory Properties
    /// Quality score for this message (0.0-1.0) - higher means more valuable for recall
    @Published var qualityScore: Double? = nil
    /// OpenAI embedding vector for semantic search (1536 dimensions for text-embedding-3-small)
    var embedding: [Float]? = nil
    /// Reference to parent message if this is a child chunk for hierarchical retrieval
    var parentMessageId: UUID? = nil
    /// Index of this chunk in parent-child splitting strategy
    var chunkIndex: Int? = nil
    /// Token count for context budget management
    var tokenCount: Int? = nil

    init(role: OSMessageRole, content: String) {
        self.role = role
        self.content = content
    }

    init(role: OSMessageRole, content: String, images: [Data]) {
        self.role = role
        self.content = content
        self.attachedImages = images
    }

    /// Whether this turn has any attached images
    var hasImages: Bool {
        !attachedImages.isEmpty
    }

    /// Whether this turn has any thinking/reasoning content
    var hasThinking: Bool {
        !thinking.isEmpty
    }
}
