//
//  AutoEmbeddingService.swift
//  BrainOS
//
//  Automatically embed messages on creation for instant semantic search
//

import Foundation
import Combine

/// Automatically processes messages for semantic search as they're created
@MainActor
class AutoEmbeddingService: ObservableObject {
    static let shared = AutoEmbeddingService()
    
    private(set) var coordinator: SemanticMemoryCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private var processingQueue: [PendingMessage] = []
    private var isProcessing = false
    
    @Published var embedCount: Int = 0
    @Published var lastError: Error?
    @Published var isConfigured: Bool = false
    
    struct PendingMessage {
        let message: ChatTurnData
        let sessionId: UUID
    }
    
    // MARK: - Configuration
    
    /// Initialize with OpenAI API key - CALL THIS ON APP LAUNCH
    func configure(openAIKey: String) {
        self.coordinator = SemanticMemoryCoordinator(openAIKey: openAIKey)
        self.isConfigured = true
        BrainLogger.info("AutoEmbeddingService configured and ready", category: .core)
    }
    
    // MARK: - Auto Processing
    
    /// Automatically process a message (CALL THIS AFTER EVERY MESSAGE)
    func autoProcess(message: ChatTurnData, sessionId: UUID) {
        guard coordinator != nil else {
            BrainLogger.error("AutoEmbeddingService not configured - skipping embedding", category: .core)
            return
        }
        
        // Skip empty messages
        guard !message.content.isEmpty else { return }
        
        // Add to queue
        processingQueue.append(PendingMessage(message: message, sessionId: sessionId))
        
        // Process queue
        Task {
            await processQueue()
        }
    }
    
    /// Process the queue in batches for efficiency
    private func processQueue() async {
        guard !isProcessing, !processingQueue.isEmpty else { return }
        guard let coordinator = coordinator else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Take up to 10 messages at a time
        let batch = Array(processingQueue.prefix(10))
        processingQueue.removeFirst(min(10, processingQueue.count))
        
        for pending in batch {
            do {
                await coordinator.processNewMessage(pending.message, inSession: pending.sessionId)
                embedCount += 1
                BrainLogger.info("Embedded message \(pending.message.id)", category: .core)
            } catch {
                lastError = error
                BrainLogger.error("Failed to embed message: \(error)", category: .core)
            }
        }
        
        // Continue processing if more in queue
        if !processingQueue.isEmpty {
            await processQueue()
        }
    }
    
    // MARK: - Batch Operations
    
    /// Process all messages in a session (for backfilling)
    func processSession(_ sessionId: UUID) async {
        guard let coordinator = coordinator else { return }
        
        await coordinator.processSessionEmbeddings(sessionId: sessionId)
        BrainLogger.info("Processed session \(sessionId) embeddings", category: .core)
    }
    
    /// Process all existing sessions (one-time setup)
    func backfillAllSessions() async {
        let sessions = ChatSessionStore.loadAll()
        BrainLogger.info("Backfilling \(sessions.count) sessions...", category: .core)
        
        for (index, session) in sessions.enumerated() {
            BrainLogger.info("Processing session \(index + 1)/\(sessions.count): \(session.title)", category: .core)
            await processSession(session.id)
        }
        
        BrainLogger.info("✅ Backfill complete!", category: .core)
    }
    
    // MARK: - Statistics
    
    func getStats() -> Stats {
        let allMessages = MemoryStorage.loadAllMessages()
        let embeddedMessages = allMessages.filter { $0.embedding != nil }
        let qualityMessages = allMessages.filter { ($0.qualityScore ?? 0.0) >= 0.7 }
        
        return Stats(
            totalMessages: allMessages.count,
            embeddedMessages: embeddedMessages.count,
            qualityMessages: qualityMessages.count,
            queueSize: processingQueue.count
        )
    }
    
    struct Stats {
        let totalMessages: Int
        let embeddedMessages: Int
        let qualityMessages: Int
        let queueSize: Int
        
        var embeddingProgress: Double {
            guard totalMessages > 0 else { return 0.0 }
            return Double(embeddedMessages) / Double(totalMessages)
        }
    }
}

// MARK: - ChatView Integration Hook

extension ChatTurn {
    /// Convenience method to auto-embed this turn
    @MainActor
    func autoEmbed(sessionId: UUID) {
        Task {
            let data = ChatTurnData(from: self)
            AutoEmbeddingService.shared.autoProcess(message: data, sessionId: sessionId)
        }
    }
}

// MARK: - Usage Instructions

/*
 
 ═══════════════════════════════════════════════════════════════════════════════
 
 HOW TO INTEGRATE AUTO-EMBEDDING (3 STEPS)
 
 ═══════════════════════════════════════════════════════════════════════════════
 
 STEP 1: Configure on App Launch
 ─────────────────────────────────────────────────────────────────────────────
 
 In your AppDelegate or main app initialization:
 
 ```swift
 @main
 struct BrainOSApp: App {
     init() {
         // Get OpenAI key from your config
         if let apiKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey") {
             AutoEmbeddingService.shared.configure(openAIKey: apiKey)
         }
     }
 }
 ```
 
 ─────────────────────────────────────────────────────────────────────────────
 STEP 2: Auto-Process Every Message
 ─────────────────────────────────────────────────────────────────────────────
 
 In ChatView.swift, after adding a message to the session:
 
 ```swift
 // After creating a new ChatTurn and adding to session
 let newTurn = ChatTurn(role: .user, content: userMessage)
 session.turns.append(newTurn)
 
 // ✨ ADD THIS LINE - Auto-embed the message
 newTurn.autoEmbed(sessionId: session.id)
 
 // Continue with API call...
 ```
 
 ─────────────────────────────────────────────────────────────────────────────
 STEP 3: Backfill Existing Data (One Time)
 ─────────────────────────────────────────────────────────────────────────────
 
 Add a settings button or run once:
 
 ```swift
 Button("Process All Messages") {
     Task {
         await AutoEmbeddingService.shared.backfillAllSessions()
     }
 }
 ```
 
 ═══════════════════════════════════════════════════════════════════════════════
 
 THAT'S IT! Now every message automatically:
 ✅ Gets embedded for semantic search
 ✅ Gets a quality score
 ✅ Gets token count calculated
 ✅ Is ready for smart context building
 
 ═══════════════════════════════════════════════════════════════════════════════
 
 */
