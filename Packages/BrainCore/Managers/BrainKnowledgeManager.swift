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
        
        // 2. Extract relationships via LLM if available, otherwise fallback to pattern matching
        Task {
            await processAndStoreRelationships(from: text)
        }
        
        // 3. Store in SQLite via DatabaseManager
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
        let combined = Array(Set(vectorResults + graphResults))
        
        // Future: Use a small local Cross-Encoder for better reranking
        return Array(combined.prefix(limit))
    }
    
    /// Extract entities with their types from text
    private func extractEntitiesWithTypes(from text: String) -> [(name: String, type: String)] {
        tagger.string = text
        var entities: [(String, String)] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag {
                let name = String(text[range])
                let type: String
                switch tag {
                case .personalName: type = "person"
                case .placeName: type = "place"
                case .organizationName: type = "organization"
                default: type = "entity"
                }
                entities.append((name, type))
            }
            return true
        }
        return entities
    }
    
    /// Extract entity names only (for backward compatibility)
    private func extractEntities(from text: String) -> [String] {
        return extractEntitiesWithTypes(from: text).map { $0.name }
    }
    
    /// Extract semantic relationships from text using pattern matching (fallback) or LLM
    /// Returns tuples of (subject, predicate, object)
    public func extractRelationships(from text: String) async -> [(subject: String, predicate: String, object: String)] {
        // Try LLM first
        if let llmResults = await llmExtractRelationships(from: text) {
            return llmResults
        }
        
        // Fallback to pattern matching
        return patternExtractRelationships(from: text)
    }
    
    /// Extract relationships using LLM
    private func llmExtractRelationships(from text: String) async -> [(subject: String, predicate: String, object: String)]? {
        let systemPrompt = """
        Extract structured knowledge from the provided text.
        Identify entities and the semantic relationships between them.
        
        Output format: JSON array of objects with "subject", "predicate", and "object" fields.
        Examples:
        - "Alice works at Google" -> [{"subject": "Alice", "predicate": "employed_by", "object": "Google"}]
        - "I met Bob in Paris" -> [{"subject": "User", "predicate": "met", "object": "Bob"}, {"subject": "Bob", "predicate": "located_at", "object": "Paris"}]
        
        Predicates should be concise snake_case: employed_by, lives_in, knows, met, founded, etc.
        If no clear relationships found, return [].
        """
        
        let userPrompt = "Text to analyze: \"\(text)\""
        
        do {
            let engine = ChatEngine()
            let request = ChatCompletionRequest(
                model: "default",
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt)
                ],
                temperature: 0.1,
                max_tokens: 500
            )
            
            let response = try await engine.completeChat(request: request)
            guard let content = response.choices.first?.message.content else { return nil }
            
            let jsonString = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            struct Rel: Codable {
                let subject: String
                let predicate: String
                let object: String
            }
            
            guard let data = jsonString.data(using: String.Encoding.utf8) else { return nil }
            let extracted = try JSONDecoder().decode([Rel].self, from: data)
            
            return extracted.map { ($0.subject, $0.predicate, $0.object) }
        } catch {
            BrainLogger.error("LLM relationship extraction failed: \(error)", category: .knowledge)
            return nil
        }
    }
    
    /// Extract semantic relationships from text using pattern matching (Heuristic fallback)
    private func patternExtractRelationships(from text: String) -> [(subject: String, predicate: String, object: String)] {
        let entities = extractEntitiesWithTypes(from: text)
        guard entities.count >= 2 else { return [] }
        
        var relationships: [(String, String, String)] = []
        
        // Split into sentences for better accuracy
        let sentenceDetector = NLTokenizer(unit: .sentence)
        sentenceDetector.string = text
        
        sentenceDetector.enumerateTokens(in: text.startIndex..<text.endIndex) { sentenceRange, _ in
            let sentence = String(text[sentenceRange]).lowercased()
            
            // Find entities in this sentence
            let sentenceEntities = entities.filter { sentence.contains($0.name.lowercased()) }
            guard sentenceEntities.count >= 2 else { return true }
            
            // Extract relationships between pairs
            for i in 0..<sentenceEntities.count {
                for j in (i+1)..<sentenceEntities.count {
                    let entity1 = sentenceEntities[i]
                    let entity2 = sentenceEntities[j]
                    
                    // Try to find a verb/relationship between them
                    if let predicate = self.findPredicate(between: entity1.name, and: entity2.name, in: sentence, entityTypes: (entity1.type, entity2.type)) {
                        relationships.append((entity1.name, predicate, entity2.name))
                    }
                }
            }
            return true
        }
        
        return relationships
    }
    
    /// Find the predicate (verb/relationship) between two entities in a sentence
    /// Uses priority-ordered patterns with entity type awareness
    private func findPredicate(between entity1: String, and entity2: String, in sentence: String, entityTypes: (String, String)) -> String? {
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
        
        // Priority-ordered relationship patterns (longest/most specific first)
        let relationshipPatterns: [(pattern: String, predicate: String, priority: Int)] = [
            // High priority - specific multi-word patterns
            ("is the ceo of", "leads", 10),
            ("is the founder of", "founded", 10),
            ("is married to", "married_to", 10),
            ("is friends with", "friends_with", 10),
            ("graduated from", "studied_at", 10),
            ("partnered with", "partnered_with", 10),
            
            // Medium priority - employment/professional
            ("works at", "employed_by", 8),
            ("works for", "employed_by", 8),
            ("employed by", "employed_by", 8),
            ("manages", "manages", 7),
            ("leads", "leads", 7),
            
            // Medium priority - creation/ownership
            ("founded", "founded", 8),
            ("created", "created", 7),
            ("built", "built", 7),
            ("acquired", "acquired", 7),
            ("bought", "acquired", 7),
            ("invested in", "invested_in", 8),
            ("sold", "sold_to", 7),
            
            // Medium priority - location/movement
            ("lives in", "resides_in", 8),
            ("moved to", "relocated_to", 8),
            ("visited", "visited", 7),
            ("went to", "visited", 7),
            ("studied at", "studied_at", 8),
            ("is from", "originates_from", 8),
            
            // Medium priority - communication
            ("talked to", "communicated_with", 7),
            ("met with", "met", 7),
            ("called", "communicated_with", 6),
            ("emailed", "communicated_with", 6),
            
            // Lower priority - simple/ambiguous
            ("met", "met", 5),
            ("married", "married_to", 5),
            ("knows", "knows", 5),
        ]
        
        // Sort by priority (highest first), then by pattern length (longest first for tie-breaking)
        let sortedPatterns = relationshipPatterns.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.pattern.count > rhs.pattern.count
        }
        
        // Find best matching pattern
        for (pattern, predicate, _) in sortedPatterns {
            if between.contains(pattern) {
                // Validate pattern makes sense for entity types
                if isValidRelationship(predicate: predicate, entityTypes: entityTypes) {
                    return predicate
                }
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
    
    /// Validate that a predicate makes sense for given entity types
    private func isValidRelationship(predicate: String, entityTypes: (String, String)) -> Bool {
        let types = Set([entityTypes.0, entityTypes.1])
        
        // Relationship type constraints
        switch predicate {
        case "employed_by", "manages", "leads":
            // Person-Organization relationships
            return types.contains("person") && (types.contains("organization") || types.contains("entity"))
            
        case "married_to", "friends_with", "knows":
            // Person-Person relationships
            return types.contains("person")
            
        case "resides_in", "visited", "relocated_to", "located_at":
            // Person/Org-Place relationships
            return types.contains("place") || types.contains("entity")
            
        case "founded", "created", "built", "acquired", "invested_in":
            // Creation/ownership - flexible
            return true
            
        default:
            // Allow generic relationships
            return true
        }
    }
    
    /// Process text and store extracted relationships in the knowledge graph
    /// Returns the number of relationships successfully stored
    public func processAndStoreRelationships(from text: String) async -> Int {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }
        
        let relationships = await extractRelationships(from: text)
        guard !relationships.isEmpty else {
            return 0
        }
        
        var successCount = 0
        
        for (subject, predicate, object) in relationships {
            do {
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
                    strength: 0.7  // Higher confidence with type-aware matching
                )
                
                successCount += 1
                NSLog("🔗 KnowledgeGraph: \(subject) --[\(predicate)]--> \(object)")
            } catch {
                NSLog("⚠️ KnowledgeGraph: Failed to store relationship \(subject)-\(predicate)-\(object): \(error.localizedDescription)")
                // Continue processing remaining relationships
            }
        }
        
        return successCount
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
