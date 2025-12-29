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
        BrainLogger.info("Starting background ingestion with AI pipeline...", category: .knowledge)
        
        // Collect data items for parallel AI processing
        var dataItems: [DataItem] = []
        
        // Gather from all sources
        dataItems += await gatherMessages()
        dataItems += await gatherSafari()
        dataItems += await gatherUsage()
        // dataItems += await gatherPhotos() // Future: Vision embeddings
        
        // Process through AI pipeline for intelligent memory generation
        if !dataItems.isEmpty {
            await MemoryGenerationPipeline.shared.processDataBatch(dataItems)
            BrainLogger.info("Processed \(dataItems.count) items through AI pipeline", category: .knowledge)
        }
    }
    
    /// Gather app usage data as DataItems for AI processing
    private func gatherUsage() async -> [DataItem] {
        let usage = await BrainUsageManager.shared.fetchRecentUsage(limit: 10)
        return usage.map { item in
            DataItem.usageEvent(
                appName: item.bundleId,
                duration: item.duration,
                timestamp: Date()
            )
        }
    }
    
    /// Gather Safari browsing history as DataItems for AI processing
    private func gatherSafari() async -> [DataItem] {
        let history = await BrainSafariManager.shared.fetchRecentHistory(limit: 20)
        return history.map { item in
            DataItem.safariPage(
                url: item.url,
                title: item.title,
                visitTime: item.timestamp
            )
        }
    }
    
    /// Gather messages as DataItems for AI processing
    private func gatherMessages() async -> [DataItem] {
        do {
            let messages: [MessageEntry] = try await BrainMessagesManager.shared.fetchRecentMessages(limit: 50)
            var dataItems: [DataItem] = []
            
            for message in messages {
                // Convert message to DataItem for AI analysis
                if let text = message.text, !text.isEmpty {
                    let sender = message.senderName ?? message.sender
                    dataItems.append(
                        DataItem.message(
                            text: text,
                            sender: sender,
                            timestamp: message.timestamp
                        )
                    )
                }
                
                // Still update interaction stats (this is database tracking, not AI memory)
                let senderId = message.sender
                let senderName = message.senderName ?? message.sender
                await BrainDatabaseManager.shared.updateInteraction(
                    contactId: senderId,
                    name: senderName,
                    timestamp: message.timestamp
                )
            }
            
            return dataItems
        } catch {
            BrainLogger.error("Failed to gather messages: \(error)", category: .knowledge)
            return []
        }
    }
    
    /// Gather health data as DataItems for AI processing (iOS only)
    private func gatherHealth() async -> [DataItem] {
        #if os(iOS)
        do {
            try await BrainHealthManager.shared.requestPermissions()
            let steps = try await BrainHealthManager.shared.fetchStepCount(days: 1)
            if let todaySteps = steps.first {
                return [
                    DataItem.healthData(
                        type: "steps",
                        value: todaySteps,
                        unit: "count",
                        timestamp: Date()
                    )
                ]
            }
        } catch {
            BrainLogger.error("Failed to gather health data: \(error)", category: .knowledge)
        }
        #endif
        return []
    }
}
