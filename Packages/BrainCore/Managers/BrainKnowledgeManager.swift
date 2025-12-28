import Foundation
import MLX
import NaturalLanguage

/// Manages semantic memory and knowledge graph for BrainOS.
public actor BrainKnowledgeManager {
    public static let shared = BrainKnowledgeManager()
    
    private struct MemoryEntry: Codable {
        let id: UUID
        let text: String
        let embedding: [Float]
        let metadata: [String: String]
        let timestamp: Date
    }
    
    private var memories: [MemoryEntry] = []
    private let storageURL: URL
    private let embeddingModel = NLEmbedding.sentenceEmbedding(for: .english)
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("BrainOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.storageURL = appSupport.appendingPathComponent("knowledge_graph.json")
        
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([MemoryEntry].self, from: data) {
            self.memories = decoded
        } else {
            self.memories = []
        }
    }
    
    private func loadMemories() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([MemoryEntry].self, from: data) else {
            return
        }
        self.memories = decoded
    }
    
    private func saveMemories() {
        if let data = try? JSONEncoder().encode(memories) {
            try? data.write(to: storageURL)
        }
    }
    
    public func addMemory(text: String, metadata: [String: String] = [:]) {
        guard let embedding = embeddingModel?.vector(for: text) else {
            BrainLogger.error("Failed to generate embedding for text", category: .knowledge)
            return
        }
        
        let entry = MemoryEntry(
            id: UUID(),
            text: text,
            embedding: embedding.map { Float($0) },
            metadata: metadata,
            timestamp: Date()
        )
        memories.append(entry)
        saveMemories()
    }
    
    public func search(query: String, limit: Int = 5) -> [String] {
        guard let queryEmbedding = embeddingModel?.vector(for: query) else {
            return []
        }
        
        let floatEmbedding = queryEmbedding.map { Float($0) }
        
        // Simple cosine similarity search with a small boost for recent memories
        let results = memories.map { entry in
            let similarity = cosineSimilarity(floatEmbedding, entry.embedding)
            
            // Boost score based on recency (up to 10% boost for memories from today)
            let timeInterval = abs(entry.timestamp.timeIntervalSinceNow)
            let recencyBoost = Float(max(0, 1.0 - (timeInterval / 86400.0))) * 0.1
            
            return (entry.text, similarity + recencyBoost)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map { $0.0 }
        
        return Array(results)
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
}
