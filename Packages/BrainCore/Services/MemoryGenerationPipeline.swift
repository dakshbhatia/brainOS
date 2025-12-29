//
//  MemoryGenerationPipeline.swift
//  BrainCore
//
//  Parallel AI memory generation pipeline for continuous learning
//

import Foundation

/// Data item types that can be converted into memories
public enum DataItem: Sendable {
    case message(text: String, sender: String, timestamp: Date)
    case calendarEvent(title: String, startDate: Date, endDate: Date, location: String?)
    case healthData(type: String, value: Double, unit: String, timestamp: Date)
    case safariPage(url: String, title: String, visitTime: Date)
    case usageEvent(appName: String, duration: TimeInterval, timestamp: Date)
    case location(latitude: Double, longitude: Double, placeName: String?, timestamp: Date)
}

/// Generated memory with metadata
public struct GeneratedMemory: Sendable {
    public let id: UUID
    public let text: String
    public let summary: String
    public let entities: [String]
    public let sentiment: String?
    public let importance: Int // 1-10
    public let timestamp: Date
    public let sourceType: String
    
    public init(id: UUID = UUID(), text: String, summary: String, entities: [String], sentiment: String?, importance: Int, timestamp: Date, sourceType: String) {
        self.id = id
        self.text = text
        self.summary = summary
        self.entities = entities
        self.sentiment = sentiment
        self.importance = importance
        self.timestamp = timestamp
        self.sourceType = sourceType
    }
}

/// Parallel memory generation pipeline using MLX models
public actor MemoryGenerationPipeline {
    public static let shared = MemoryGenerationPipeline()
    
    private let maxConcurrentInferences = 3
    private let modelService = MLXService()
    private var isProcessing = false
    private var queuedItems: [DataItem] = []
    
    private init() {}
    
    /// Process a batch of data items in parallel
    public func processDataBatch(_ items: [DataItem]) async {
        guard !items.isEmpty else { return }
        
        NSLog("🧠 MemoryPipeline: Processing \(items.count) items with \(maxConcurrentInferences) parallel workers")
        
        var generatedMemories: [GeneratedMemory] = []
        
        await withTaskGroup(of: GeneratedMemory?.self) { group in
            var pendingItems = items
            var activeCount = 0
            
            while !pendingItems.isEmpty || activeCount > 0 {
                // Add tasks up to max concurrent limit
                while activeCount < maxConcurrentInferences && !pendingItems.isEmpty {
                    let item = pendingItems.removeFirst()
                    group.addTask {
                        await self.generateMemory(from: item)
                    }
                    activeCount += 1
                }
                
                // Wait for one task to complete
                if let memory = await group.next() {
                    activeCount -= 1
                    if let memory = memory {
                        generatedMemories.append(memory)
                    }
                }
            }
        }
        
        // Store generated memories in knowledge base
        for memory in generatedMemories {
            await storeMemory(memory)
        }
        
        NSLog("✅ MemoryPipeline: Generated \(generatedMemories.count)/\(items.count) memories")
    }
    
    /// Generate a single memory from a data item using AI inference
    private func generateMemory(from item: DataItem) async -> GeneratedMemory? {
        let prompt = buildMemoryPrompt(item)
        
        do {
            // Use MLX model to generate memory analysis
            let response = try await modelService.generateText(
                prompt: prompt,
                maxTokens: 256,
                temperature: 0.7
            )
            
            return parseMemoryResponse(response, sourceItem: item)
        } catch {
            NSLog("⚠️ MemoryPipeline: Failed to generate memory - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Build prompt for memory generation
    private func buildMemoryPrompt(_ item: DataItem) -> String {
        switch item {
        case .message(let text, let sender, let timestamp):
            return """
            Analyze this message and extract key information:
            
            Message: "\(text)"
            From: \(sender)
            Time: \(timestamp.formatted())
            
            Extract:
            1. Summary (one sentence)
            2. Important entities (people, places, topics)
            3. Sentiment (positive/negative/neutral)
            4. Importance (1-10)
            
            Format as JSON:
            {"summary": "...", "entities": ["..."], "sentiment": "...", "importance": 7}
            """
            
        case .calendarEvent(let title, let startDate, let endDate, let location):
            return """
            Analyze this calendar event:
            
            Event: \(title)
            Start: \(startDate.formatted())
            End: \(endDate.formatted())
            Location: \(location ?? "None")
            
            Extract key context and importance.
            Format as JSON: {"summary": "...", "entities": ["..."], "importance": 7}
            """
            
        case .healthData(let type, let value, let unit, let timestamp):
            return """
            Analyze health data point:
            
            Type: \(type)
            Value: \(value) \(unit)
            Time: \(timestamp.formatted())
            
            Assess importance and context.
            Format as JSON: {"summary": "...", "importance": 5}
            """
            
        case .safariPage(let url, let title, let visitTime):
            return """
            Analyze browsing activity:
            
            Page: \(title)
            URL: \(url)
            Time: \(visitTime.formatted())
            
            Extract topics and research intent.
            Format as JSON: {"summary": "...", "entities": ["..."], "importance": 5}
            """
            
        case .usageEvent(let appName, let duration, let timestamp):
            return """
            Analyze app usage:
            
            App: \(appName)
            Duration: \(Int(duration))s
            Time: \(timestamp.formatted())
            
            Assess context and productivity relevance.
            Format as JSON: {"summary": "...", "importance": 3}
            """
            
        case .location(let lat, let lon, let placeName, let timestamp):
            return """
            Analyze location data:
            
            Place: \(placeName ?? "Unknown")
            Coordinates: \(lat), \(lon)
            Time: \(timestamp.formatted())
            
            Extract context and significance.
            Format as JSON: {"summary": "...", "entities": ["..."], "importance": 6}
            """
        }
    }
    
    /// Parse AI response into structured memory
    private func parseMemoryResponse(_ response: String, sourceItem: DataItem) -> GeneratedMemory? {
        // Extract JSON from response (handle markdown code blocks)
        let jsonString = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let summary = json["summary"] as? String else {
            NSLog("⚠️ MemoryPipeline: Failed to parse JSON response")
            return nil
        }
        
        let entities = (json["entities"] as? [String]) ?? []
        let sentiment = json["sentiment"] as? String
        let importance = json["importance"] as? Int ?? 5
        
        // Get timestamp and source type from original item
        let (timestamp, sourceType) = extractMetadata(from: sourceItem)
        
        return GeneratedMemory(
            text: extractFullText(from: sourceItem),
            summary: summary,
            entities: entities,
            sentiment: sentiment,
            importance: importance,
            timestamp: timestamp,
            sourceType: sourceType
        )
    }
    
    /// Extract metadata from data item
    private func extractMetadata(from item: DataItem) -> (timestamp: Date, sourceType: String) {
        switch item {
        case .message(_, _, let timestamp):
            return (timestamp, "message")
        case .calendarEvent(_, let startDate, _, _):
            return (startDate, "calendar")
        case .healthData(_, _, _, let timestamp):
            return (timestamp, "health")
        case .safariPage(_, _, let visitTime):
            return (visitTime, "browsing")
        case .usageEvent(_, _, let timestamp):
            return (timestamp, "usage")
        case .location(_, _, _, let timestamp):
            return (timestamp, "location")
        }
    }
    
    /// Extract full text from data item
    private func extractFullText(from item: DataItem) -> String {
        switch item {
        case .message(let text, let sender, _):
            return "Message from \(sender): \(text)"
        case .calendarEvent(let title, _, _, let location):
            return "Calendar event: \(title) at \(location ?? "unknown location")"
        case .healthData(let type, let value, let unit, _):
            return "Health: \(type) = \(value) \(unit)"
        case .safariPage(_, let title, _):
            return "Browsed: \(title)"
        case .usageEvent(let appName, let duration, _):
            return "Used \(appName) for \(Int(duration))s"
        case .location(_, _, let placeName, _):
            return "Visited: \(placeName ?? "unknown place")"
        }
    }
    
    /// Store generated memory in knowledge base
    private func storeMemory(_ memory: GeneratedMemory) async {
        await BrainKnowledgeManager.shared.addMemory(
            text: memory.summary,
            metadata: [
                "full_text": memory.text,
                "entities": memory.entities.joined(separator: ", "),
                "sentiment": memory.sentiment ?? "",
                "importance": "\(memory.importance)",
                "source_type": memory.sourceType,
                "timestamp": ISO8601DateFormatter().string(from: memory.timestamp)
            ]
        )
    }
    
    /// Queue items for background processing
    public func queueForProcessing(_ items: [DataItem]) {
        queuedItems.append(contentsOf: items)
        
        // Process queue if not already processing
        if !isProcessing {
            Task {
                await processQueue()
            }
        }
    }
    
    /// Process queued items in batches
    private func processQueue() async {
        guard !isProcessing, !queuedItems.isEmpty else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        while !queuedItems.isEmpty {
            // Process in batches of 10
            let batchSize = min(10, queuedItems.count)
            let batch = Array(queuedItems.prefix(batchSize))
            queuedItems.removeFirst(batchSize)
            
            await processDataBatch(batch)
            
            // Small delay between batches to avoid overload
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

// MARK: - MLXService Extension for Memory Generation

extension MLXService {
    /// Generate text using the current model with proper MLX inference
    func generateText(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        // Use the actual MLX generateOneShot method
        let message = ChatMessage(role: "user", content: prompt)
        let parameters = GenerationParameters(
            temperature: Float(temperature),
            maxTokens: maxTokens,
            topPOverride: 0.9,
            repetitionPenalty: nil
        )
        
        return try await generateOneShot(
            messages: [message],
            parameters: parameters,
            requestedModel: nil  // Use default model
        )
    }
}
