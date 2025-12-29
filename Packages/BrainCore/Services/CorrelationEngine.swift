import Foundation
import Combine

/// Listens to the LifeEventBus and identifies patterns across different vitals.
public actor CorrelationEngine {
    public static let shared = CorrelationEngine()
    
    private var cancellables = Set<AnyCancellable>()
    private let notificationService = NotificationService.shared
    
    private init() {
        Task {
            await setupSubscriptions()
        }
    }
    
    private func setupSubscriptions() async {
        LifeEventBus.shared.subscribe()
            .sink { [weak self] event in
                guard let self = self else { return }
                Task {
                    await self.handleEvent(event)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleEvent(_ event: LifeEvent) async {
        // Pattern Matching: Correlating different signals
        switch event {
        case .lowActivity(let steps):
            await handleActivityEvent(steps: steps)
            
        case .socialDrift(let contact, let days):
            await checkDriftRelevance(contact: contact, days: days)
            
        case .screenshotCaptured(let url, let text):
            await analyzeScreenshotContext(url: url, text: text)
            
        default:
            break
        }
    }
    
    private func handleActivityEvent(steps: Int) async {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // 1. Standard Health Alerts (Moved from BrainManager for centralization)
        if hour == 14 && steps < 2000 {
            await notificationService.postHealthAlert(
                title: "Low Activity Today",
                body: "You've only taken \(steps) steps. How about a 10-minute walk?"
            )
        }
        
        if hour == 18 && steps < 5000 {
            await notificationService.postHealthAlert(
                title: "Movement Reminder",
                body: "Only \(steps) steps today. A short evening walk could help!"
            )
        }

        // 2. Cross-Vital Correlation: Social Walk
        let staleContacts = await BrainDatabaseManager.shared.getStaleContacts(days: 14)
        if steps < 2000 && !staleContacts.isEmpty {
            if let friend = staleContacts.first {
                await notificationService.postHealthAlert(
                    title: "Social Walk Opportunity",
                    body: "You've been inactive today and haven't talked to \(friend.name) in a while. Maybe a walk together?"
                )
            }
        }
    }
    
    private func checkDriftRelevance(contact: String, days: Int) async {
        // Future: Check if they are in your calendar soon
    }
    
    private func analyzeScreenshotContext(url: URL, text: String) async {
        // Vision-to-Action: If screenshot contains a date or price, bridge to calendar/finance
        if text.contains("$") || text.localizedStandardContains("Total") {
            BrainLogger.info("Financial intent detected in screenshot", category: .knowledge)
            // Logic to prompt for finance logging
        }
        
        if text.localizedStandardContains("PM") || text.localizedStandardContains("AM") {
             BrainLogger.info("Temporal intent detected in screenshot", category: .knowledge)
             // Logic to prompt for calendar entry
        }
    }
}
