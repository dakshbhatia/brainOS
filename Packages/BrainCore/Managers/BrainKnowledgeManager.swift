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
    
    // MARK: - Relationship Extraction
    
    /// Extract semantic relationships from text using pattern matching
    /// Returns tuples of (subject, predicate, object)
    public func extractRelationships(from text: String) -> [(subject: String, predicate: String, object: String)] {
        let entities = extractEntities(from: text)
        guard entities.count >= 2 else { return [] }
        
        var relationships: [(String, String, String)] = []
        
        // Split into sentences for better accuracy
        let sentenceDetector = NLTokenizer(unit: .sentence)
        sentenceDetector.string = text
        
        sentenceDetector.enumerateTokens(in: text.startIndex..<text.endIndex) { sentenceRange, _ in
            let sentence = String(text[sentenceRange]).lowercased()
            
            // Find entities in this sentence
            let sentenceEntities = entities.filter { sentence.contains($0.lowercased()) }
            guard sentenceEntities.count >= 2 else { return true }
            
            // Extract relationships between pairs
            for i in 0..<sentenceEntities.count {
                for j in (i+1)..<sentenceEntities.count {
                    let entity1 = sentenceEntities[i]
                    let entity2 = sentenceEntities[j]
                    
                    // Try to find a verb/relationship between them
                    if let predicate = findPredicate(between: entity1, and: entity2, in: sentence) {
                        relationships.append((entity1, predicate, entity2))
                    }
                }
            }
            return true
        }
        
        return relationships
    }
    
    /// Find the predicate (verb/relationship) between two entities in a sentence
    private func findPredicate(between entity1: String, and entity2: String, in sentence: String) -> String? {
        let e1Lower = entity1.lowercased()
        let e2Lower = entity2.lowercased()
        
        guard let range1 = sentence.range(of: e1Lower),
              let range2 = sentence.range(of: e2Lower) else { return nil }
        
        // Determine order
        let startRange: Range<String.Index>
        let endRange: Range<String.Index>
        
        if range1.lowerBound < range2.lowerBound {
            startRange = range1
            endRange = range2
        } else {
            startRange = range2
            endRange = range1
        }
        
        // Extract text between entities
        let betweenStart = startRange.upperBound
        let betweenEnd = endRange.lowerBound
        guard betweenStart < betweenEnd else { return nil }
        
        let between = String(sentence[betweenStart..<betweenEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Common relationship patterns
        let relationshipPatterns: [(pattern: String, predicate: String)] = [
            ("works at", "employed_by"),
            ("works for", "employed_by"),
            ("employed by", "employed_by"),
            ("founded", "founded"),
            ("created", "created"),
            ("built", "built"),
            ("is the ceo of", "leads"),
            ("leads", "leads"),
            ("manages", "manages"),
            ("met", "met"),
            ("met with", "met"),
            ("talked to", "communicated_with"),
            ("called", "communicated_with"),
            ("emailed", "communicated_with"),
            ("lives in", "resides_in"),
            ("moved to", "relocated_to"),
            ("visited", "visited"),
            ("went to", "visited"),
            ("is married to", "married_to"),
            ("married", "married_to"),
            ("is friends with", "friends_with"),
            ("knows", "knows"),
            ("is from", "originates_from"),
            ("studied at", "studied_at"),
            ("graduated from", "studied_at"),
            ("invested in", "invested_in"),
            ("bought", "acquired"),
            ("acquired", "acquired"),
            ("sold", "sold_to"),
            ("partnered with", "partnered_with"),
        ]
        
        // Check for matching patterns
        for (pattern, predicate) in relationshipPatterns {
            if between.contains(pattern) {
                return predicate
            }
        }
        
        // Fallback: Extract verb using NLTagger
        let verbTagger = NLTagger(tagSchemes: [.lexicalClass])
        verbTagger.string = between
        
        var foundVerb: String?
        verbTagger.enumerateTags(in: between.startIndex..<between.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if tag == .verb {
                foundVerb = String(between[range])
                return false // Stop after first verb
            }
            return true
        }
        
        return foundVerb
    }
    
    /// Process text and store extracted relationships in the knowledge graph
    public func processAndStoreRelationships(from text: String) async {
        let relationships = extractRelationships(from: text)
        
        for (subject, predicate, object) in relationships {
            // First ensure entities exist
            await BrainDatabaseManager.shared.upsertEntity(name: subject, type: "extracted")
            await BrainDatabaseManager.shared.upsertEntity(name: object, type: "extracted")
            
            // Create relationship
            let sourceId = "extracted:\(subject.lowercased())"
            let targetId = "extracted:\(object.lowercased())"
            
            await BrainDatabaseManager.shared.addRelationship(
                source: sourceId,
                target: targetId,
                type: predicate,
                strength: 0.5  // Medium confidence from pattern extraction
            )
            
            NSLog("🔗 KnowledgeGraph: Added relationship \(subject) --[\(predicate)]--> \(object)")
        }
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
