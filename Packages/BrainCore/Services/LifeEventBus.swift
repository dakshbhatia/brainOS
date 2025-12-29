import Foundation
import Combine

/// Types of events that can occur across the BrainOS ecosystem
public enum LifeEvent: Sendable {
    // Health Events
    case lowActivity(steps: Int)
    case highStress(heartRate: Double)
    
    // Social Events
    case socialDrift(contactName: String, days: Int)
    case pendingReply(contactName: String, waitTimeHours: Int)
    case positiveInteraction(contactName: String)
    case negativeInteraction(contactName: String)
    
    // Digital/Deep Work Events
    case deepWorkStarted(appName: String)
    case distractionDetected(appName: String)
    
    // Financial Events
    case largeSpending(amount: Double, merchant: String)
    
    // Screen/Vision Events
    case screenshotCaptured(url: URL, ocrText: String)
}

/// A central dispatcher for cross-vital events, enabling correlation between modules.
public final class LifeEventBus: Sendable {
    public static let shared = LifeEventBus()
    
    private let eventSubject = PassthroughSubject<LifeEvent, Never>()
    private let queue = DispatchQueue(label: "com.brainos.eventbus", qos: .userInitiated)
    
    private init() {}
    
    /// Publish an event to the bus
    public func publish(_ event: LifeEvent) {
        queue.async {
            BrainLogger.info("Event Published: \(event)", category: .core)
            self.eventSubject.send(event)
        }
    }
    
    /// Subscribe to events on the bus
    public func subscribe() -> AnyPublisher<LifeEvent, Never> {
        return eventSubject
            .receive(on: queue)
            .eraseToAnyPublisher()
    }
}
