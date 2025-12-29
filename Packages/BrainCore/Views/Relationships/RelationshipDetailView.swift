import SwiftUI
import Models
import EventKit

public struct RelationshipDetailView: View {
    let profileId: String
    @State private var profile: RelationshipProfile?
    @State private var interactionGroups: [InteractionGroup] = []
    @State private var sharedEvents: [EKEvent] = []
    @State private var suggestedMessage: String?
    @State private var isGeneratingSuggestion = false
    
    public init(profileId: String) {
        self.profileId = profileId
    }
    
    public var body: some View {
        if let profile = profile {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Card
                    headerSection(profile)
                    
                    // Vitals & Stats
                    metricsGrid(profile)
                    
                    // Recommended Action (AI Suggestions)
                    aiActionSection(profile)
                    
                    // Shared History (CALENDAR + iMESSAGE)
                    historySection
                }
                .padding(24)
            }
            .onAppear {
                loadData()
            }
            .onChange(of: profileId) { _ in
                loadData()
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { loadData() }
        }
    }
    
    // MARK: - Sections
    
    private func headerSection(_ profile: RelationshipProfile) -> some View {
        HStack(spacing: 20) {
            // Large Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.gradient.opacity(0.1))
                    .frame(width: 80, height: 80)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.system(size: 28, weight: .bold))
                
                HStack(spacing: 12) {
                    StatusPill(text: profile.tier.displayName, color: .blue)
                    StatusPill(text: profile.trajectory.description, color: .green)
                    if profile.needsAttention {
                        StatusPill(text: "Needs Attention", color: .orange)
                    }
                }
            }
            
            Spacer()
            
            // Interaction Shortcuts
            HStack(spacing: 12) {
                ActionButton(icon: "message.fill", color: .blue) {
                    if let url = profile.imessageDeepLink { NSWorkspace.shared.open(url) }
                }
                ActionButton(icon: "phone.fill", color: .green) {
                    if let url = profile.facetimeAudioDeepLink { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
    
    private func metricsGrid(_ profile: RelationshipProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RELATIONSHIP VITALS")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricCard(title: "Social Score", value: "\(Int(profile.relationshipScore))", subtitle: "0-100", color: .blue)
                MetricCard(title: "Balance", value: String(format: "%.1f", profile.messageBalance), subtitle: "Me vs Them", color: .purple)
                MetricCard(title: "Recency", value: profile.lastInteractionDescription, subtitle: "Last spoken", color: .orange)
            }
        }
    }
    
    private func aiActionSection(_ profile: RelationshipProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROACTIVE INTELLIGENCE")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("AI-Drafted Reply")
                        .font(.headline)
                }
                
                if isGeneratingSuggestion {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let suggestion = suggestedMessage {
                    Text(suggestion)
                        .font(.system(size: 14, design: .serif))
                        .italic()
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                        )
                    
                    Button(action: {
                        // Copy to clipboard or open iMessage
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(suggestion, forType: .string)
                        if let url = profile.imessageDeepLink { NSWorkspace.shared.open(url) }
                    }) {
                        Label("Copy & Open Messages", systemImage: "paperplane.fill")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Generate Thoughtful Reply") {
                        generateSuggestion()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(20)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
        }
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SHARED HISTORY")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
            
            // Combined Timeline
            VStack(spacing: 12) {
                // Calendar Events (if any)
                ForEach(sharedEvents, id: \.eventIdentifier) { event in
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .bold))
                            Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(10)
                }
                
                // Smartly Grouped Messages
                ForEach(interactionGroups) { group in
                    InteractionGroupView(group: group)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadData() {
        Task {
            let loadedProfile = await BrainDatabaseManager.shared.getRelationshipProfile(id: profileId)
            let groups = await RelationshipAgent.shared.getSmartGroupedInteractions(for: profileId)
            let events = await BrainCalendarManager.shared.getEventsWithContact(name: profileId)
            
            await MainActor.run {
                self.profile = loadedProfile
                self.interactionGroups = groups
                self.sharedEvents = events
            }
            
            // Auto-generate suggestion if profile exists
            if let profile = loadedProfile {
                generateSuggestion(for: profile)
            }
        }
    }
    
    private func generateSuggestion(for profile: RelationshipProfile? = nil) {
        let p = profile ?? self.profile
        guard let targetProfile = p else { return }
        
        isGeneratingSuggestion = true
        Task {
            let suggestion = await RelationshipAgent.shared.generateSuggestedMessage(for: targetProfile)
            await MainActor.run {
                self.suggestedMessage = suggestion
                self.isGeneratingSuggestion = false
            }
        }
    }
}

// MARK: - Subcomponents

struct StatusPill: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(12)
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .foregroundStyle(color)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct InteractionGroupView: View {
    let group: InteractionGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "message.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text(group.summary)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(group.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(group.messages.prefix(3), id: \.guid) { msg in
                    Text(msg.text ?? "[Attachment]")
                        .font(.system(size: 12))
                        .foregroundStyle(msg.isFromMe ? .primary : .secondary)
                        .padding(8)
                        .background(msg.isFromMe ? Color.blue.opacity(0.05) : Color.primary.opacity(0.03))
                        .cornerRadius(8)
                }
                
                if group.messages.count > 3 {
                    Text("+ \(group.messages.count - 3) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(12)
    }
}
