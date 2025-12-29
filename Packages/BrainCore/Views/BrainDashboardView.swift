import SwiftUI

struct BrainDashboardView: View {
    @State private var greeting = "Good Morning"
    @State private var userName = NSFullUserName()
    @State private var brief = "Loading your daily brief..."
    @State private var nudges: [RelationshipNudge] = []
    @State private var stepCount: Int = 0
    @State private var currentLocation = "Unknown"
    @State private var recentMemories: [String] = []
    @State private var memoryStreamActive = false
    @State private var lastIngestionTime: String = "Never"
    @State private var showingFullBrief = false
    @State private var semanticMemoryStats: AutoEmbeddingService.Stats?
    @Environment(\.theme) private var theme
    
    // Animation states
    @State private var pulseAnimation = false
    @State private var hasAppeared = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with Brain Status
                headerSection
                
                // Memory Stream Status
                memoryStreamSection
                
                // Daily Brief
                dailyBriefSection
                
                // Recent Insights
                recentInsightsSection
                
                // Relationships Inbox
                relationshipsSection
                
                // Health & Context Cards
                contextCardsSection
                
                Spacer(minLength: 20)
                
                // Footer
                footerSection
            }
            .padding(20)
        }
        .frame(width: 380, height: 600)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: hasAppeared)
        .onAppear {
            loadDashboardData()
            hasAppeared = true
            startLiveUpdates()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            BrainAvatarView()
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(theme.accentColor.opacity(0.3), lineWidth: 2)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.8)
                )
                .onAppear {
                    withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                        pulseAnimation = true
                    }
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(userName)")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(memoryStreamActive ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(memoryStreamActive ? "Learning" : "Idle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Memory Stream Section
    private var memoryStreamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("MEMORY STREAM", systemImage: "brain.head.profile")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lastIngestionTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Semantic memory status
            if let stats = semanticMemoryStats {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(AutoEmbeddingService.shared.isConfigured ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(AutoEmbeddingService.shared.isConfigured ? "Semantic memory active" : "Configure OpenAI provider")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if stats.totalMessages > 0 {
                        HStack {
                            Text("\(stats.embeddedMessages)/\(stats.totalMessages) messages indexed")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(stats.embeddingProgress * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.accentColor)
                        }
                        
                        ProgressView(value: stats.embeddingProgress)
                            .progressViewStyle(.linear)
                            .tint(theme.accentColor)
                            .frame(height: 3)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            
            if memoryStreamActive {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing new experiences...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.accentColor.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("\(recentMemories.count) knowledge items indexed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Daily Brief Section
    private var dailyBriefSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("DAILY BRIEF", systemImage: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !brief.hasPrefix("Loading") {
                    Button(showingFullBrief ? "Show Less" : "Expand") {
                        withAnimation(.spring(response: 0.3)) {
                            showingFullBrief.toggle()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accentColor)
                }
            }
            
            Text(brief)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(4)
                .lineLimit(showingFullBrief ? nil : 4)
                .animation(.easeInOut(duration: 0.2), value: showingFullBrief)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.accentColor.opacity(0.08))
        )
    }
    
    // MARK: - Recent Insights Section
    private var recentInsightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("RECENT INSIGHTS", systemImage: "lightbulb.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            
            if recentMemories.isEmpty {
                Text("No insights yet today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(recentMemories.prefix(3).enumerated()), id: \.offset) { index, memory in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(theme.accentColor.opacity(0.6))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            Text(memory)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    // MARK: - Relationships Section
    private var relationshipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("RELATIONSHIPS", systemImage: "person.2.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            
            if nudges.isEmpty {
                Text("All caught up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(nudges.prefix(3).enumerated()), id: \.element.id) { index, nudge in
                        relationshipNudgeCard(nudge)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
    }
    
    private func relationshipNudgeCard(_ nudge: RelationshipNudge) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nudge.contactName)
                    .font(.system(size: 13, weight: .semibold))
                Text(nudge.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "paperplane.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(theme.accentColor)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
    
    // MARK: - Context Cards Section
    private var contextCardsSection: some View {
        HStack(spacing: 10) {
            contextCard(
                title: "Activity",
                value: stepCount > 0 ? "\(stepCount.formatted())" : "—",
                subtitle: stepCount > 0 ? "steps" : "No data",
                icon: "figure.walk",
                color: .green
            )
            
            contextCard(
                title: "Location",
                value: currentLocation == "Unknown" ? "—" : currentLocation,
                subtitle: currentLocation == "Unknown" ? "Unavailable" : "Current",
                icon: "location.fill",
                color: .blue
            )
        }
    }
    
    private func contextCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        HStack {
            Text("⌥Space to chat")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.caption2)
                Text("Powered by MLX")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary.opacity(0.7))
        }
    }
    
    // MARK: - Data Loading
    private func loadDashboardData() {
        // Load user profile
        userName = UserDefaults.standard.string(forKey: "userName") ?? NSFullUserName()
        
        // Set greeting based on time
        let hour = Calendar.current.component(.hour, from: Date())
        greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        
        // Load semantic memory stats immediately (sync)
        semanticMemoryStats = AutoEmbeddingService.shared.getStats()
        
        Task {
            // Load relationship nudges
            let loadedNudges = await RelationshipAgent.shared.analyzeRecentInteractions()
            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    self.nudges = loadedNudges
                }
            }
            
            // Generate AI brief
            let generatedBrief = await BrainManager.shared.generateBrief()
            await MainActor.run {
                withAnimation {
                    self.brief = generatedBrief
                }
            }
            
            // Load health data
            if let steps = try? await BrainHealthManager.shared.fetchStepCount(days: 1).first {
                await MainActor.run {
                    self.stepCount = Int(steps)
                }
            }
            
            // Load recent memories for insights
            await loadRecentInsights()
            
            // Check memory stream status
            await updateMemoryStreamStatus()
        }
    }
    
    private func loadRecentInsights() async {
        // Get recent high-importance memories from last 24 hours
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        
        if let memories = await BrainKnowledgeManager.shared.getMemories(
            from: yesterday,
            to: Date(),
            limit: 10
        ) {
            let insights = memories
                .filter { $0.importance > 0.6 }
                .sorted { $0.importance > $1.importance }
                .prefix(3)
                .map { $0.summary }
            
            await MainActor.run {
                withAnimation {
                    self.recentMemories = Array(insights)
                }
            }
        }
    }
    
    private func updateMemoryStreamStatus() async {
        // Check if BackgroundIngestionService is currently running
        // For now, we'll check if there are any recent memories (within last 5 minutes)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        
        if let recentMems = await BrainKnowledgeManager.shared.getMemories(
            from: fiveMinutesAgo,
            to: Date(),
            limit: 1
        ), !recentMems.isEmpty {
            await MainActor.run {
                self.memoryStreamActive = true
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                self.lastIngestionTime = formatter.localizedString(for: recentMems[0].timestamp, relativeTo: Date())
            }
        } else {
            await MainActor.run {
                self.memoryStreamActive = false
                self.lastIngestionTime = "Idle"
            }
        }
    }
    
    private func startLiveUpdates() {
        // Refresh insights and stream status every 60 seconds
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                await loadRecentInsights()
                await updateMemoryStreamStatus()
                // Refresh semantic memory stats
                semanticMemoryStats = AutoEmbeddingService.shared.getStats()
            }
        }
    }
}

#Preview {
    BrainDashboardView()
}
