import Foundation
import EventKit

/// Manages access to the user's calendar and reminders.
@MainActor
public class BrainCalendarManager {
    public static let shared = BrainCalendarManager()
    private let eventStore = EKEventStore()
    
    private init() {}
    
    public func requestAccess() async throws -> Bool {
        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    public func fetchEvents(days: Int = 7) async -> [EKEvent] {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
    }
    
    public func getUpcomingBrief() async -> String {
        let events = await fetchEvents(days: 1)
        if events.isEmpty { return "No events scheduled for today." }
        
        let eventStrings = events.map { event in
            let time = event.startDate.formatted(date: .omitted, time: .shortened)
            return "\(time): \(event.title ?? "Untitled Event")"
        }
        
        return "Today's Schedule:\n" + eventStrings.joined(separator: "\n")
    }
}
