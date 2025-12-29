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
        
        // Collect all entities first for relationship extraction
        var foundEntities: [(name: String, type: String)] = []
        
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
                
                foundEntities.append((entityName, type))
                
                Task {
                    await BrainDatabaseManager.shared.upsertEntity(name: entityName, type: type)
                }
            }
            return true
        }
        
        // Create relationships between co-occurring entities (entities in same text are related)
        if foundEntities.count >= 2 {
            Task {
                for i in 0..<foundEntities.count {
                    for j in (i+1)..<foundEntities.count {
                        let entity1 = foundEntities[i]
                        let entity2 = foundEntities[j]
                        
                        // Determine relationship type based on entity types
                        let relationType = determineRelationType(entity1.type, entity2.type)
                        
                        // Build entity IDs (matching upsertEntity format)
                        let sourceId = "\(entity1.type):\(entity1.name.lowercased())"
                        let targetId = "\(entity2.type):\(entity2.name.lowercased())"
                        
                        await BrainDatabaseManager.shared.addRelationship(
                            source: sourceId,
                            target: targetId,
                            type: relationType,
                            strength: 0.1  // Co-occurrence adds weak relationship strength
                        )
                    }
                }
            }
        }
    }
    
    /// Determine relationship type based on entity types
    private func determineRelationType(_ type1: String, _ type2: String) -> String {
        let types = Set([type1, type2])
        
        if types == Set(["person", "person"]) {
            return "knows"
        } else if types == Set(["person", "organization"]) {
            return "associated_with"
        } else if types == Set(["person", "place"]) {
            return "located_at"
        } else if types == Set(["organization", "place"]) {
            return "based_in"
        } else {
            return "related_to"
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
    
    /// Get memories within a date range sorted by importance
    public func getMemories(from startDate: Date, to endDate: Date, limit: Int = 10) async -> [(summary: String, timestamp: Date, importance: Double)]? {
        // Query database for memories in date range
        let memories = await BrainDatabaseManager.shared.getMemoriesInDateRange(
            start: startDate,
            end: endDate,
            limit: limit
        )
        
        return memories.map { memory in
            (
                summary: memory.content,
                timestamp: memory.timestamp,
                importance: memory.importance
            )
        }
    }
}
