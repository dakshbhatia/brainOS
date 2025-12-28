import Foundation
import MLX

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
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("BrainOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.storageURL = appSupport.appendingPathComponent("knowledge_graph.json")
        loadMemories()
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
    
    public func addMemory(text: String, embedding: [Float], metadata: [String: String] = [:]) {
        let entry = MemoryEntry(
            id: UUID(),
            text: text,
            embedding: embedding,
            metadata: metadata,
            timestamp: Date()
        )
        memories.append(entry)
        saveMemories()
    }
    
    public func search(queryEmbedding: [Float], limit: Int = 5) -> [String] {
        // Simple cosine similarity search
        let results = memories.map { entry in
            (entry.text, cosineSimilarity(queryEmbedding, entry.embedding))
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
