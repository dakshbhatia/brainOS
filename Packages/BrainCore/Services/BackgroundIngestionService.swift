import Foundation
import BrainRepository

/// Periodically ingests data from various sources into the semantic memory.
public actor BackgroundIngestionService {
    public static let shared = BackgroundIngestionService()
    
    private var isRunning = false
    private var timer: Task<Void, Never>?
    
    private init() {}
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        timer = Task {
            while !Task.isCancelled {
                await ingestAll()
                try? await Task.sleep(nanoseconds: 1800 * 1_000_000_000) // Every 30 minutes
            }
        }
    }
    
    public func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }
    
    private func ingestAll() async {
        BrainLogger.info("Starting background ingestion...", category: .knowledge)
        
        await ingestMessages()
        await ingestHealth()
        // await ingestPhotos() // Future: Vision embeddings
    }
    
    private func ingestMessages() async {
        do {
            let messages = try await BrainMessagesManager.shared.fetchRecentMessages(limit: 20)
            for message in messages {
                if let text = message.text, !text.isEmpty {
                    let sender = message.senderName ?? message.sender
                    let content = "Message from \(sender): \(text)"
                    await BrainKnowledgeManager.shared.addMemory(
                        text: content,
                        metadata: [
                            "source": "messages",
                            "sender": sender,
                            "timestamp": message.timestamp.description
                        ]
                    )
                }
            }
        } catch {
            BrainLogger.error("Failed to ingest messages: \(error)", category: .knowledge)
        }
    }
    
    private func ingestHealth() async {
        do {
            try await BrainHealthManager.shared.requestPermissions()
            let steps = try await BrainHealthManager.shared.fetchStepCount(days: 1)
            if let todaySteps = steps.first {
                await BrainKnowledgeManager.shared.addMemory(
                    text: "I have taken \(Int(todaySteps)) steps today.",
                    metadata: [
                        "source": "health",
                        "type": "steps",
                        "timestamp": Date().description
                    ]
                )
            }
        } catch {
            BrainLogger.error("Failed to ingest health data: \(error)", category: .knowledge)
        }
    }
}
