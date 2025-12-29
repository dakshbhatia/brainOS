//
//  RealTimeEventStream.swift
//  BrainCore
//
//  Real-time event stream processor for continuous data ingestion
//

import Foundation
import Combine

/// Event types that can flow through the stream
public enum BrainEvent: Sendable {
    case messageReceived(sender: String, text: String, timestamp: Date)
    case calendarEventStarting(title: String, startDate: Date, location: String?)
    case healthDataUpdated(type: String, value: Double, unit: String)
    case locationChanged(latitude: Double, longitude: Double, placeName: String?)
    case appUsageDetected(appName: String, startTime: Date)
    case safariPageVisited(url: String, title: String)
    case screenshotCaptured(path: String, timestamp: Date)
    case contactsChanged(changeType: String, contactName: String)
}

/// Real-time event stream processor with debouncing and batching
public actor RealTimeEventStream {
    public static let shared = RealTimeEventStream()
    
    private var eventBuffer: [BrainEvent] = []
    private var isProcessing = false
    private var processingTask: Task<Void, Never>?
    
    // Configuration
    private let bufferSize = 10
    private let flushInterval: TimeInterval = 30 // seconds
    private let maxWaitTime: TimeInterval = 300 // 5 minutes
    
    private init() {
        // Start background processing loop asynchronously
        Task {
            await startProcessingLoop()
        }
    }
    
    /// Add event to stream
    public func emit(_ event: BrainEvent) {
        eventBuffer.append(event)
        NSLog("📡 EventStream: Event added, buffer size: \(eventBuffer.count)")
        
        // Flush if buffer is full
        if eventBuffer.count >= bufferSize {
            Task {
                await flushBuffer()
            }
        }
    }
    
    /// Add multiple events at once
    public func emitBatch(_ events: [BrainEvent]) {
        eventBuffer.append(contentsOf: events)
        NSLog("📡 EventStream: Batch added (\(events.count) events), buffer size: \(eventBuffer.count)")
        
        if eventBuffer.count >= bufferSize {
            Task {
                await flushBuffer()
            }
        }
    }
    
    /// Start continuous processing loop
    private func startProcessingLoop() {
        processingTask = Task {
            while !Task.isCancelled {
                // Wait for flush interval
                try? await Task.sleep(for: .seconds(flushInterval))
                
                // Flush buffer if it has events
                if !eventBuffer.isEmpty {
                    await flushBuffer()
                }
            }
        }
    }
    
    /// Flush event buffer to memory generation pipeline
    private func flushBuffer() async {
        guard !isProcessing, !eventBuffer.isEmpty else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        NSLog("🚰 EventStream: Flushing \(eventBuffer.count) events")
        
        // Convert events to DataItems
        let dataItems = eventBuffer.compactMap { event -> DataItem? in
            convertToDataItem(event)
        }
        
        // Clear buffer
        eventBuffer.removeAll()
        
        // Send to memory generation pipeline
        if !dataItems.isEmpty {
            await MemoryGenerationPipeline.shared.processDataBatch(dataItems)
        }
    }
    
    /// Convert BrainEvent to DataItem
    private func convertToDataItem(_ event: BrainEvent) -> DataItem? {
        switch event {
        case .messageReceived(let sender, let text, let timestamp):
            return .message(text: text, sender: sender, timestamp: timestamp)
            
        case .calendarEventStarting(let title, let startDate, let location):
            let endDate = startDate.addingTimeInterval(3600) // Default 1 hour
            return .calendarEvent(title: title, startDate: startDate, endDate: endDate, location: location)
            
        case .healthDataUpdated(let type, let value, let unit):
            return .healthData(type: type, value: value, unit: unit, timestamp: Date())
            
        case .locationChanged(let lat, let lon, let placeName):
            return .location(latitude: lat, longitude: lon, placeName: placeName, timestamp: Date())
            
        case .appUsageDetected(let appName, let startTime):
            let duration = Date().timeIntervalSince(startTime)
            return .usageEvent(appName: appName, duration: duration, timestamp: startTime)
            
        case .safariPageVisited(let url, let title):
            return .safariPage(url: url, title: title, visitTime: Date())
            
        case .screenshotCaptured(_, _):
            // Skip screenshots for now (too frequent)
            return nil
            
        case .contactsChanged(_, _):
            // Skip contact changes (not memory-worthy)
            return nil
        }
    }
    
    /// Get current buffer status
    public func getStatus() -> EventStreamStatus {
        EventStreamStatus(
            bufferSize: eventBuffer.count,
            isProcessing: isProcessing,
            maxBufferSize: bufferSize
        )
    }
    
    /// Stop processing loop
    public func stop() {
        processingTask?.cancel()
        processingTask = nil
    }
}

/// Event stream status
public struct EventStreamStatus: Sendable {
    public let bufferSize: Int
    public let isProcessing: Bool
    public let maxBufferSize: Int
    
    public var bufferPercentage: Double {
        Double(bufferSize) / Double(maxBufferSize) * 100.0
    }
}

// MARK: - Event Emitters

/// Extension to emit events from various managers
extension BrainMessagesManager {
    /// Emit message events to real-time stream
    func emitMessageEvents(_ messages: [MessageEntry]) async {
        let events = messages.compactMap { message -> BrainEvent? in
            guard let text = message.text else { return nil }
            return BrainEvent.messageReceived(
                sender: message.senderName ?? message.sender,
                text: text,
                timestamp: message.timestamp
            )
        }
        await RealTimeEventStream.shared.emitBatch(events)
    }
}

extension BrainCalendarManager {
    /// Emit calendar events to real-time stream
    func emitCalendarEvents(_ events: [(title: String, startDate: Date, location: String?)]) async {
        let brainEvents = events.map { event in
            BrainEvent.calendarEventStarting(
                title: event.title,
                startDate: event.startDate,
                location: event.location
            )
        }
        await RealTimeEventStream.shared.emitBatch(brainEvents)
    }
}

extension BrainHealthManager {
    /// Emit health data updates to real-time stream
    func emitHealthUpdate(type: String, value: Double, unit: String) async {
        await RealTimeEventStream.shared.emit(
            .healthDataUpdated(type: type, value: value, unit: unit)
        )
    }
}

extension BrainLocationManager {
    /// Emit location changes to real-time stream
    func emitLocationUpdate(latitude: Double, longitude: Double, placeName: String?) async {
        await RealTimeEventStream.shared.emit(
            .locationChanged(latitude: latitude, longitude: longitude, placeName: placeName)
        )
    }
}

extension BrainSafariManager {
    /// Emit Safari page visits to real-time stream
    func emitPageVisits(_ pages: [(url: String, title: String)]) async {
        let events = pages.map { page in
            BrainEvent.safariPageVisited(url: page.url, title: page.title)
        }
        await RealTimeEventStream.shared.emitBatch(events)
    }
}

extension BrainUsageManager {
    /// Emit app usage events to real-time stream
    func emitUsageEvent(appName: String, startTime: Date) async {
        await RealTimeEventStream.shared.emit(
            .appUsageDetected(appName: appName, startTime: startTime)
        )
    }
}
