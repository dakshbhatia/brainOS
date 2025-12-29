//
//  SemanticMessageSearch.swift
//  BrainOS
//
//  Semantic search over actual iMessage/SMS data
//

import Foundation

/// Semantic search wrapper for BrainMessagesManager
actor SemanticMessageSearch {
    private let embeddingService: EmbeddingService
    private var messageCache: [String: EmbeddedMessage] = [:]
    
    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
    }
    
    // MARK: - Models
    
    struct EmbeddedMessage: Codable {
        let guid: String
        let sender: String
        let senderName: String?
        let text: String?
        let timestamp: Date
        let isFromMe: Bool
        let embedding: [Float]
        
        init(from message: MessageEntry, embedding: [Float]) {
            self.guid = message.guid
            self.sender = message.sender
            self.senderName = message.senderName
            self.text = message.text
            self.timestamp = message.timestamp
            self.isFromMe = message.isFromMe
            self.embedding = embedding
        }
    }
    
    // MARK: - Semantic Search
    
    /// Search messages semantically (by meaning, not keywords)
    /// - Parameters:
    ///   - query: Natural language query like "friends I texted recently"
    ///   - limit: Maximum results to return
    ///   - minScore: Minimum similarity threshold (0.0-1.0)
    ///   - timeframe: Optional time filter (e.g., "last 30 days")
    /// - Returns: Array of messages with similarity scores

    func searchMessages(
        query: String,
        limit: Int = 10,
        minScore: Float = 0.7,
        timeframe: String? = nil
    ) async throws -> [(message: MessageEntry, score: Float)] {
        // Parse timeframe
        let startDate = parseTimeframe(timeframe)
        
        // Fetch recent messages (larger pool to search from)
        let recentMessages = try await BrainMessagesManager.shared.fetchRecentMessages(
            limit: 500,
            contactName: nil
        )
        
        // Filter by timeframe if specified
        let filteredMessages = startDate != nil 
            ? recentMessages.filter { $0.timestamp >= startDate! }
            : recentMessages
        
        // Generate query embedding
        let queryEmbedding = try await embeddingService.embed(query)
        
        // Embed messages that aren't cached
        var embeddedMessages: [EmbeddedMessage] = []
        var textsToEmbed: [(guid: String, text: String)] = []
        var indicesToProcess: [Int] = []
        
        for (index, message) in filteredMessages.enumerated() {
            guard let text = message.text, !text.isEmpty else { continue }
            
            if let cached = messageCache[message.guid] {
                embeddedMessages.append(cached)
            } else {
                // Prepare for batch embedding
                let searchableText = formatForSearch(message)
                textsToEmbed.append((message.guid, searchableText))
                indicesToProcess.append(index)
            }
        }
        
        // Batch embed new messages
        if !textsToEmbed.isEmpty {
            let embeddings = try await embeddingService.embedBatch(textsToEmbed.map { $0.text })
            
            for (i, embedding) in embeddings.enumerated() {
                let messageIndex = indicesToProcess[i]
                let message = filteredMessages[messageIndex]
                let guid = textsToEmbed[i].guid
                
                let embedded = EmbeddedMessage(from: message, embedding: embedding)
                embeddedMessages.append(embedded)
                messageCache[guid] = embedded
            }
        }
        
        // Calculate similarity scores
        var scoredResults: [(message: MessageEntry, score: Float)] = []
        
        for embedded in embeddedMessages {
            let similarity = EmbeddingService.cosineSimilarity(queryEmbedding, embedded.embedding)
            
            if similarity >= minScore {
                // Find original message for full data
                if let original = filteredMessages.first(where: { $0.guid == embedded.guid }) {
                    scoredResults.append((message: original, score: similarity))
                }
            }
        }
        
        // Sort by similarity and return top results
        return scoredResults
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Search for specific contacts semantically
    /// E.g., "friends", "real friends", "close contacts", "people I trust"
    func findContacts(
        matching query: String,
        limit: Int = 10
    ) async throws -> [(contact: String, score: Float, messageCount: Int)] {
        // Get recent messages
        let messages = try await BrainMessagesManager.shared.fetchRecentMessages(
            limit: 1000,
            contactName: nil
        )
        
        // Group by contact
        var contactMessages: [String: [MessageEntry]] = [:]
        for message in messages {
            let contact = message.senderName ?? message.sender
            contactMessages[contact, default: []].append(message)
        }
        
        // Create summary for each contact (conversation style + frequency)
        var contactSummaries: [(contact: String, summary: String, count: Int)] = []
        for (contact, msgs) in contactMessages {
            let recentTexts = msgs.prefix(10).compactMap { $0.text }.joined(separator: " ")
            let summary = "Contact: \(contact). Recent conversations: \(recentTexts)"
            contactSummaries.append((contact, summary, msgs.count))
        }
        
        // Embed summaries
        let summaryTexts = contactSummaries.map { $0.summary }
        let embeddings = try await embeddingService.embedBatch(summaryTexts)
        
        // Query embedding
        let queryEmbedding = try await embeddingService.embed(query)
        
        // Score each contact
        var scoredContacts: [(contact: String, score: Float, messageCount: Int)] = []
        for (i, embedding) in embeddings.enumerated() {
            let similarity = EmbeddingService.cosineSimilarity(queryEmbedding, embedding)
            let (contact, _, count) = contactSummaries[i]
            scoredContacts.append((contact, similarity, count))
        }
        
        return scoredContacts
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Helpers
    
    private func formatForSearch(_ message: MessageEntry) -> String {
        var parts: [String] = []
        
        if let sender = message.senderName {
            parts.append("From: \(sender)")
        } else if !message.isFromMe {
            parts.append("From: \(message.sender)")
        } else {
            parts.append("From: Me")
        }
        
        if let text = message.text {
            parts.append(text)
        }
        
        return parts.joined(separator: ". ")
    }
    
    private func parseTimeframe(_ timeframe: String?) -> Date? {
        guard let tf = timeframe?.lowercased() else { return nil }
        
        let now = Date()
        let calendar = Calendar.current
        
        if tf.contains("last 24 hours") || tf.contains("today") {
            return calendar.date(byAdding: .day, value: -1, to: now)
        } else if tf.contains("last 7 days") || tf.contains("this week") {
            return calendar.date(byAdding: .day, value: -7, to: now)
        } else if tf.contains("last 30 days") || tf.contains("this month") {
            return calendar.date(byAdding: .day, value: -30, to: now)
        } else if tf.contains("last 90 days") {
            return calendar.date(byAdding: .day, value: -90, to: now)
        }
        
        return nil
    }
}

// MARK: - Enhanced Tool

struct SemanticMessageSearchTool: BrainOSTool {
    let name = "search_messages_semantic"
    let description = "Semantically search messages by meaning (e.g., 'friends I texted', 'important work discussions'). Much better than keyword search."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Natural language query describing what you're looking for (e.g., 'friends I recently talked to', 'urgent messages')")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Number of messages to retrieve (default 10)")
                ]),
                "timeframe": .object([
                    "type": .string("string"),
                    "description": .string("Optional time filter like 'last 7 days', 'last 30 days', 'this week'")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        let decoder = JSONDecoder()
        guard let args = try? decoder.decode(Arguments.self, from: argumentsJSON.data(using: .utf8) ?? Data()) else {
            return "Error: Invalid arguments"
        }
        
        // Get OpenAI key from app configuration
        guard let apiKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey"), !apiKey.isEmpty else {
            return "Error: OpenAI API key not configured. Cannot perform semantic search."
        }
        
        let embeddingService = EmbeddingService(apiKey: apiKey)
        let searchService = SemanticMessageSearch(embeddingService: embeddingService)
        
        do {
            // Determine if this is a contact search or message search
            let isContactSearch = args.query.lowercased().contains("friend") || 
                                  args.query.lowercased().contains("contact") ||
                                  args.query.lowercased().contains("people")
            
            if isContactSearch {
                // Search for contacts
                let contacts = try await searchService.findContacts(
                    matching: args.query,
                    limit: args.limit ?? 10
                )
                
                if contacts.isEmpty {
                    return "No matching contacts found for '\(args.query)'"
                }
                
                var result = "Found \(contacts.count) contacts matching '\(args.query)':\n\n"
                for (i, (contact, score, msgCount)) in contacts.enumerated() {
                    result += "\(i+1). **\(contact)** (relevance: \(Int(score * 100))%, \(msgCount) messages)\n"
                }
                
                return result
                
            } else {
                // Search for messages
                let results = try await searchService.searchMessages(
                    query: args.query,
                    limit: args.limit ?? 10,
                    minScore: 0.7,
                    timeframe: args.timeframe
                )
                
                if results.isEmpty {
                    return "No messages found matching '\(args.query)'"
                }
                
                var output = "Found \(results.count) messages matching '\(args.query)':\n\n"
                for (i, (message, score)) in results.enumerated() {
                    let sender = message.senderName ?? message.sender
                    let preview = message.text?.prefix(100) ?? "[No text]"
                    output += "\(i+1). From **\(sender)** (relevance: \(Int(score * 100))%)\n"
                    output += "   \"\(preview)\"\n"
                    output += "   \(formatDate(message.timestamp))\n\n"
                }
                
                return output
            }
            
        } catch {
            return "Error performing semantic search: \(error.localizedDescription)"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    struct Arguments: Decodable {
        let query: String
        let limit: Int?
        let timeframe: String?
    }
}
