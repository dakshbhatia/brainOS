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
        await ingestSafari()
        await ingestUsage()
        // await ingestPhotos() // Future: Vision embeddings
    }
    
    private func ingestUsage() async {
        let usage = await BrainUsageManager.shared.fetchRecentUsage(limit: 10)
        for item in usage {
            let content = "Used application: \(item.bundleId) for \(Int(item.duration)) seconds today."
            await BrainKnowledgeManager.shared.addMemory(
                text: content,
                metadata: [
                    "source": "usage",
                    "bundleId": item.bundleId,
                    "duration": String(item.duration),
                    "timestamp": Date().description
                ]
            )
        }
    }
        let history = await BrainSafariManager.shared.fetchRecentHistory(limit: 20)
        for item in history {
            let content = "Visited website: \(item.title) (\(item.url))"
            await BrainKnowledgeManager.shared.addMemory(
                text: content,
                metadata: [
                    "source": "safari",
                    "url": item.url,
                    "timestamp": item.timestamp.description
                ]
            )
        }
    }
    
    private func ingestMessages() async {
        do {
            let messages = try await BrainMessagesManager.shared.fetchRecentMessages(limit: 50)
            for message in messages {
                // 1. Add to semantic memory
                if let text = message.text, !text.isEmpty {
                    let sender = message.senderName ?? message.sender
                    let content = "Message from \(sender): \(text)"
                    
                    var metadata = [
                        "source": "messages",
                        "sender": sender,
                        "timestamp": message.timestamp.description
                    ]
                    
                    // Extract EXIF if there are image attachments
                    for attachment in message.attachments {
                        if let path = attachment.path, path.contains("Attachments") {
                            let exif = BrainMessagesManager.shared.extractEXIF(from: path)
                            for (key, value) in exif {
                                metadata["exif_\(key)"] = value
                            }
                        }
                    }
                    
                    await BrainKnowledgeManager.shared.addMemory(
                        text: content,
                        metadata: metadata
                    )
                }
                
                // 2. Update interaction stats in unified database
                let senderId = message.sender
                let senderName = message.senderName ?? message.sender
                await BrainDatabaseManager.shared.updateInteraction(
                    contactId: senderId,
                    name: senderName,
                    timestamp: message.timestamp
                )
            }
        } catch {
            BrainLogger.error("Failed to ingest messages: \(error)", category: .knowledge)
        }
    }
    
    private func ingestUsage() async {
        let usage = await BrainUsageManager.shared.fetchRecentUsage(limit: 5)
        for item in usage {
            let hours = String(format: "%.1f", item.duration / 3600.0)
            await BrainKnowledgeManager.shared.addMemory(
                text: "I used \(item.bundleId) for \(hours) hours today.",
                metadata: [
                    "source": "usage",
                    "bundleId": item.bundleId,
                    "duration": "\(item.duration)"
                ]
            )
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
