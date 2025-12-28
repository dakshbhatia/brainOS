import Foundation
import MLX
import NaturalLanguage

/// Manages semantic memory and knowledge graph for BrainOS.
public actor BrainKnowledgeManager {
    public static let shared = BrainKnowledgeManager()
    
    private let embeddingModel = NLEmbedding.sentenceEmbedding(for: .english)
    private let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
    
    private init() {}
    
    public func addMemory(text: String, metadata: [String: String] = [:]) {
        guard let embedding = embeddingModel?.vector(for: text) else {
            BrainLogger.error("Failed to generate embedding for text", category: .knowledge)
            return
        }
        
        // 1. Extract entities for Knowledge Graph
        extractAndStoreEntities(from: text)
        
        // 2. Store in SQLite via DatabaseManager
        Task {
            await BrainDatabaseManager.shared.saveMemory(
                id: UUID().uuidString,
                content: text,
                embedding: embedding.map { Float($0) },
                metadata: metadata
            )
        }
    }
    
    private func extractAndStoreEntities(from text: String) {
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let tags: [NLTag] = [.personalName, .placeName, .organizationName]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag, tags.contains(tag) {
                let entityName = String(text[range])
                let type: String
                switch tag {
                case .personalName: type = "person"
                case .placeName: type = "place"
                case .organizationName: type = "organization"
                default: type = "other"
                }
                
                Task {
                    await BrainDatabaseManager.shared.upsertEntity(name: entityName, type: type)
                }
            }
            return true
        }
    }
    
    public func search(query: String, limit: Int = 5) async -> [String] {
        guard let queryEmbedding = embeddingModel?.vector(for: query) else {
            return []
        }
        
        let floatEmbedding = queryEmbedding.map { Float($0) }
        
        // 1. Vector Search
        let vectorResults = await BrainDatabaseManager.shared.searchMemories(embedding: floatEmbedding, limit: limit * 2)
        
        // 2. Entity Search (Knowledge Graph)
        let entities = extractEntities(from: query)
        var graphResults: [String] = []
        for entity in entities {
            let related = await BrainDatabaseManager.shared.getRelatedMemories(entityName: entity)
            graphResults.append(contentsOf: related)
        }
        
        // 3. Combine and Rerank (Simple deduplication and priority for graph results)
        var combined = Array(Set(vectorResults + graphResults))
        
        // Future: Use a small local Cross-Encoder for better reranking
        return Array(combined.prefix(limit))
    }
    
    private func extractEntities(from text: String) -> [String] {
        tagger.string = text
        var entities: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if tag != nil {
                entities.append(String(text[range]))
            }
            return true
        }
        return entities
    }
}
