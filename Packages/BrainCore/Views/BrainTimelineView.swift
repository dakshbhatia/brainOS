import SwiftUI

/// Timeline view showing chronological events from all data sources
struct BrainTimelineView: View {
    @State private var events: [TimelineEvent] = []
    @State private var isLoading = true
    @State private var selectedDate = Date()
    @State private var filterType: EventType? = nil
    @Environment(\.theme) private var theme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with date selector
            headerSection
            
            Divider()
            
            // Filter chips
            filterSection
            
            // Timeline content
            if isLoading {
                ProgressView("Loading timeline...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedByDate, id: \.key) { date, events in
                            dateSection(date: date, events: events)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 600)
        .onAppear {
            loadTimelineData()
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            Text("Timeline")
                .font(.system(size: 20, weight: .semibold))
            
            Spacer()
            
            // Date picker
            DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                .labelsHidden()
                .onChange(of: selectedDate) { _, _ in
                    loadTimelineData()
                }
            
            Button(action: { selectedDate = Date() }) {
                Text("Today")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }
    
    // MARK: - Filters
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: filterType == nil) {
                    filterType = nil
                }
                
                ForEach(EventType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.displayName,
                        icon: type.icon,
                        color: type.color,
                        isSelected: filterType == type
                    ) {
                        filterType = type
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No events for this day")
                .font(.headline)
            Text("Try selecting a different date")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Date Section
    private func dateSection(date: Date, events: [TimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            Text(date, style: .date)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            // Events for this date
            VStack(spacing: 8) {
                ForEach(events) { event in
                    eventCard(event)
                }
            }
        }
    }
    
    // MARK: - Event Card
    private func eventCard(_ event: TimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Time indicator
            VStack(spacing: 4) {
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Circle()
                    .fill(event.type.color)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 60)
            
            // Event content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: event.type.icon)
                        .font(.caption)
                        .foregroundStyle(event.type.color)
                    
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Spacer()
                    
                    if let importance = event.importance {
                        importanceBadge(importance)
                    }
                }
                
                if let description = event.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                if !event.entities.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(event.entities.prefix(3), id: \.self) { entity in
                            Text(entity)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.accentColor.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }
    
    private func importanceBadge(_ importance: Double) -> some View {
        let color: Color = importance > 0.7 ? .red : importance > 0.4 ? .orange : .gray
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
    
    // MARK: - Data Loading
    private var filteredEvents: [TimelineEvent] {
        if let filterType = filterType {
            return events.filter { $0.type == filterType }
        }
        return events
    }
    
    private var groupedByDate: [(key: Date, value: [TimelineEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    private func loadTimelineData() {
        isLoading = true
        
        Task {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            // Gather all events for the selected date
            var loadedEvents: [TimelineEvent] = []
            
            // 1. Messages
            if let messages = try? await BrainMessagesManager.shared.fetchRecentMessages(limit: 200) {
                let dayMessages = messages.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
                loadedEvents += dayMessages.map { msg in
                    TimelineEvent(
                        timestamp: msg.timestamp,
                        type: .message,
                        title: msg.senderName ?? msg.sender,
                        description: msg.text ?? "",
                        entities: [],
                        importance: nil
                    )
                }
            }
            
            // 2. Calendar events - fetch today's events (1 day)
            let calendarEvents = await BrainCalendarManager.shared.fetchEvents(days: 1)
            let dayCalendarEvents = calendarEvents.filter { $0.startDate >= startOfDay && $0.startDate < endOfDay }
            loadedEvents += dayCalendarEvents.map { event in
                TimelineEvent(
                    timestamp: event.startDate,
                    type: .calendar,
                    title: event.title ?? "Untitled Event",
                    description: event.notes,
                    entities: [],
                    importance: nil
                )
            }
            
            // 3. Safari browsing
            let pages = await BrainSafariManager.shared.fetchRecentHistory(limit: 500)
            let dayPages = pages.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
            loadedEvents += dayPages.map { page in
                TimelineEvent(
                    timestamp: page.timestamp,
                    type: .web,
                    title: page.title,
                    description: page.url,
                    entities: [],
                    importance: nil
                )
            }
            
            // 4. Location changes
            let locations = await BrainDatabaseManager.shared.fetchLocations(start: startOfDay, end: endOfDay)
            loadedEvents += locations.map { loc in
                TimelineEvent(
                    timestamp: loc.timestamp,
                    type: .location,
                    title: "Location Update",
                    description: loc.address ?? "Near \(String(format: "%.4f", loc.lat)), \(String(format: "%.4f", loc.lon))",
                    entities: [],
                    importance: nil
                )
            }
            
            // 5. App usage
            let usage = await BrainUsageManager.shared.fetchTimelineUsage(start: startOfDay, end: endOfDay)
            loadedEvents += usage.map { item in
                let durationStr = item.duration > 60 ? "\(Int(item.duration/60))m" : "\(Int(item.duration))s"
                return TimelineEvent(
                    timestamp: item.timestamp,
                    type: .activity,
                    title: item.bundleId.split(separator: ".").last.map(String.init) ?? item.bundleId,
                    description: "Used for \(durationStr)",
                    entities: [],
                    importance: item.duration > 300 ? 0.4 : 0.2
                )
            }
            
            // 6. Memories (AI-generated insights)
            if let memories = await BrainKnowledgeManager.shared.getMemories(
                from: startOfDay,
                to: endOfDay,
                limit: 50
            ) {
                loadedEvents += memories.map { memory in
                    TimelineEvent(
                        timestamp: memory.timestamp,
                        type: .memory,
                        title: "Memory",
                        description: memory.summary,
                        entities: [],
                        importance: memory.importance
                    )
                }
            }
            
            await MainActor.run {
                self.events = loadedEvents.sorted { $0.timestamp > $1.timestamp }
                self.isLoading = false
            }
        }
    }
}

// MARK: - Supporting Types

struct TimelineEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: EventType
    let title: String
    let description: String?
    let entities: [String]
    let importance: Double?
}

enum EventType: String, CaseIterable {
    case message, calendar, web, activity, memory, health, location
    
    var displayName: String {
        switch self {
        case .message: return "Messages"
        case .calendar: return "Calendar"
        case .web: return "Web"
        case .activity: return "Activity"
        case .memory: return "Memories"
        case .health: return "Health"
        case .location: return "Location"
        }
    }
    
    var icon: String {
        switch self {
        case .message: return "message.fill"
        case .calendar: return "calendar"
        case .web: return "safari.fill"
        case .activity: return "app.fill"
        case .memory: return "brain.head.profile"
        case .health: return "heart.fill"
        case .location: return "location.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .message: return .blue
        case .calendar: return .red
        case .web: return .cyan
        case .activity: return .purple
        case .memory: return .pink
        case .health: return .green
        case .location: return .orange
        }
    }
}

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    var color: Color? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? (color ?? Color.accentColor).opacity(0.2) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? (color ?? Color.accentColor) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BrainTimelineView()
}
