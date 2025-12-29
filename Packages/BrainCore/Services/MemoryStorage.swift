//
//  MemoryStorage.swift
//  BrainOS
//
//  Extended storage functionality for semantic memory
//

import Foundation

/// Storage extensions for tool memories and semantic search optimization
@MainActor
enum MemoryStorage {
    /// Optional directory override for tests
    static var overrideDirectory: URL?
    
    // MARK: - Tool Memory Storage
    
    /// Load all tool memories
    static func loadToolMemories() -> [MemoryManager.ToolMemory] {
        let url = toolMemoriesFileURL()
        ensureDirectoryExists(url.deletingLastPathComponent())
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([MemoryManager.ToolMemory].self, from: data)
        } catch {
            print("[BrainOS] Failed to load tool memories: \(error)")
            return []
        }
    }
    
    /// Save tool memories
    static func saveToolMemories(_ memories: [MemoryManager.ToolMemory]) {
        let url = toolMemoriesFileURL()
        ensureDirectoryExists(url.deletingLastPathComponent())
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(memories)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[BrainOS] Failed to save tool memories: \(error)")
        }
    }
    
    /// Add a new tool memory
    static func addToolMemory(_ memory: MemoryManager.ToolMemory) {
        var memories = loadToolMemories()
        memories.append(memory)
        
        // Keep only last 1000 memories to prevent unbounded growth
        if memories.count > 1000 {
            memories = Array(memories.suffix(1000))
        }
        
        saveToolMemories(memories)
    }
    
    // MARK: - Session Query Helpers
    
    /// Load all messages across all sessions for cross-session semantic search
    static func loadAllMessages() -> [ChatTurnData] {
        let sessions = ChatSessionStore.loadAll()
        return sessions.flatMap { $0.turns }
    }
    
    /// Load high-quality messages across all sessions
    static func loadQualityMessages(minScore: Double = 0.7) -> [ChatTurnData] {
        return loadAllMessages().filter { ($0.qualityScore ?? 0.0) >= minScore }
    }
    
    /// Load messages with embeddings (ready for semantic search)
    static func loadEmbeddedMessages() -> [ChatTurnData] {
        return loadAllMessages().filter { $0.embedding != nil }
    }
    
    // MARK: - Batch Update Helpers
    
    /// Update a specific message within a session
    static func updateMessage(_ message: ChatTurnData, inSession sessionId: UUID) {
        guard var session = ChatSessionStore.load(id: sessionId) else {
            print("[BrainOS] Session \(sessionId) not found for message update")
            return
        }
        
        if let index = session.turns.firstIndex(where: { $0.id == message.id }) {
            session.turns[index] = message
            session.updatedAt = Date()
            ChatSessionStore.save(session)
        }
    }
    
    /// Batch update multiple messages in a session
    static func updateMessages(_ messages: [ChatTurnData], inSession sessionId: UUID) {
        guard var session = ChatSessionStore.load(id: sessionId) else {
            print("[BrainOS] Session \(sessionId) not found for batch update")
            return
        }
        
        let messageDict = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        
        for i in 0..<session.turns.count {
            if let updatedMessage = messageDict[session.turns[i].id] {
                session.turns[i] = updatedMessage
            }
        }
        
        session.updatedAt = Date()
        ChatSessionStore.save(session)
    }
    
    // MARK: - Private Helpers
    
    private static func storageDirectory() -> URL {
        if let overrideDirectory {
            return overrideDirectory.appendingPathComponent("Memory", isDirectory: true)
        }
        let fm = FileManager.default
        let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "BrainOS"
        return
            supportDir
            .appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("Memory", isDirectory: true)
    }
    
    private static func toolMemoriesFileURL() -> URL {
        storageDirectory().appendingPathComponent("tool_memories.json")
    }
    
    private static func ensureDirectoryExists(_ url: URL) {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                print("[BrainOS] Failed to create directory \(url.path): \(error)")
            }
        }
    }
}

// MARK: - Async Background Processing

extension MemoryStorage {
    /// Process embeddings for a session in the background
    static func processEmbeddings(
        for sessionId: UUID,
        using embeddingService: EmbeddingService
    ) async throws {
        guard let session = ChatSessionStore.load(id: sessionId) else {
            throw MemoryStorageError.sessionNotFound
        }
        
        var textsToEmbed: [String] = []
        var indicesToUpdate: [Int] = []
        
        // Find messages without embeddings
        for (index, turn) in session.turns.enumerated() {
            if turn.embedding == nil && !turn.content.isEmpty {
                textsToEmbed.append(turn.content)
                indicesToUpdate.append(index)
            }
        }
        
        guard !textsToEmbed.isEmpty else { return }
        
        // Generate embeddings in batch
        let embeddings = try await embeddingService.embedBatch(textsToEmbed)
        
        // Update messages with embeddings and quality scores
        var modifiedSession = session
        for (i, index) in indicesToUpdate.enumerated() {
            var turn = modifiedSession.turns[index]
            turn.embedding = embeddings[i]
            turn.qualityScore = MemoryManager.assessQuality(of: turn)
            turn.tokenCount = ContextBuilder.estimateTokens(for: turn)
            modifiedSession.turns[index] = turn
        }
        
        modifiedSession.updatedAt = Date()
        ChatSessionStore.save(modifiedSession)
    }
}

// MARK: - Errors

enum MemoryStorageError: LocalizedError {
    case sessionNotFound
    case messageNotFound
    
    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Session not found in storage"
        case .messageNotFound:
            return "Message not found in session"
        }
    }
}
