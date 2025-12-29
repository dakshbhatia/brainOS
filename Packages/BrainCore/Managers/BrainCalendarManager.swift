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
    
    /// Fetch events involving a specific contact name
    public func getEventsWithContact(name: String, days: Int = 30) async -> [EKEvent] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        return events.filter { event in
            let titleMatch = event.title?.localizedCaseInsensitiveContains(name) ?? false
            let participantMatch = event.attendees?.contains(where: { $0.name?.localizedCaseInsensitiveContains(name) ?? false }) ?? false
            return titleMatch || participantMatch
        }
    }
    
    /// Get count of shared events with a contact
    public func getSharedEventCount(name: String) async -> Int {
        let events = await getEventsWithContact(name: name, days: 365)
        return events.count
    }
    
    /// Find upcoming birthdays from contacts
    public func getUpcomingBirthdays(days: Int = 30) async -> [CNContact] {
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactBirthdayKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var birthdays: [CNContact] = []
        
        let store = CNContactStore()
        try? store.enumerateContacts(with: request) { contact, _ in
            if let birthday = contact.birthday {
                let calendar = Calendar.current
                var components = birthday
                components.year = calendar.component(.year, from: Date())
                
                if let nextBirthday = calendar.date(from: components) {
                    let diff = calendar.dateComponents([.day], from: Date(), to: nextBirthday).day ?? -1
                    if diff >= 0 && diff <= days {
                        birthdays.append(contact)
                    }
                }
            }
        }
        return birthdays
    }
}
