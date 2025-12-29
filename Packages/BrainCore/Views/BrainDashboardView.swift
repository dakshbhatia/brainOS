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
            VStack(alignment: .leading, spacing: 24) {
                // Header with Brain Orb
                headerSection
                
                // Vital Meters (The "Sims" Mirror)
                vitalsGridSection
                
                // Daily Brief (Surfaced Insights)
                dailyBriefSection
                
                // Active Action Hub (SURFACE ACTIONABLE NUDGES)
                actionHubSection
                
                // Recent Insights
                recentInsightsSection
                
                Spacer(minLength: 20)
                
                // Footer
                footerSection
            }
            .padding(24)
        }
        .frame(width: 400, height: 750)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: hasAppeared)
        .onAppear {
            loadDashboardData()
            hasAppeared = true
            startLiveUpdates()
        }
    }
    
    // MARK: - Header (The Orb)
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(theme.accentColor.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulseAnimation ? 1.2 : 0.9)
                    .blur(radius: 10)
                
                // The Core Orb
                DashboardOrbView(state: overallState)
                    .frame(width: 80, height: 80)
                    .shadow(color: orbColor.opacity(0.5), radius: 10)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
            
            VStack(spacing: 4) {
                Text("\(greeting), \(userName)")
                    .font(.system(size: 18, weight: .bold))
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(memoryStreamActive ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(memoryStreamActive ? "Cognition Active" : "Brain Idle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    // MARK: - Vitals Grid
    private var vitalsGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("LIFESTYLE VITALS", systemImage: "waveform.path.ecg")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                VitalMeter(title: "Social", icon: "person.2.fill", value: vitals["social"] ?? 0.5, color: .blue)
                VitalMeter(title: "Focus", icon: "bolt.fill", value: vitals["focus"] ?? 0.5, color: .purple)
                VitalMeter(title: "Physical", icon: "figure.walk", value: Double(stepCount) / 10000.0, color: .green)
                VitalMeter(title: "Finance", icon: "creditcard.fill", value: vitals["finance"] ?? 0.5, color: .orange)
            }
        }
    }

    // MARK: - Action Hub
    private var actionHubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ACTION HUB", systemImage: "command")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            
            if nudges.isEmpty {
                Text("Your state is optimal. No actions needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
            } else {
                ForEach(nudges) { nudge in
                    ActionCard(nudge: nudge)
                }
            }
        }
    }
    
    // MARK: - Supporting Views
    
    private var overallState: BrainOrbState {
        let avg = (vitals.values.reduce(0, +) + (Double(stepCount) / 10000.0)) / 5.0
        if avg > 0.8 { return .peak }
        if avg < 0.4 { return .low }
        return .normal
    }
    
    private var orbColor: Color {
        switch overallState {
        case .peak: return .purple
        case .normal: return theme.accentColor
        case .low: return .orange
        }
    }
    
    @State private var vitals: [String: Double] = [:]
    
    private func loadDashboardData() {
        userName = UserDefaults.standard.string(forKey: "userName") ?? NSFullUserName()
        let hour = Calendar.current.component(.hour, from: Date())
        greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        semanticMemoryStats = AutoEmbeddingService.shared.getStats()
        
        Task {
            // New snapshot retrieval
            let snapshot = await BrainDatabaseManager.shared.getDailyStatusSnapshot()
            let loadedNudges = await RelationshipAgent.shared.analyzeRecentInteractions()
            
            await MainActor.run {
                withAnimation {
                    self.vitals = snapshot
                    self.nudges = loadedNudges
                }
            }
            
            let generatedBrief = await BrainManager.shared.generateBrief()
            await MainActor.run {
                self.brief = generatedBrief
            }
            
            if let steps = try? await BrainHealthManager.shared.fetchStepCount(days: 1).first {
                await MainActor.run {
                    self.stepCount = Int(steps)
                }
            }
            
            await loadRecentInsights()
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
        // Check if there are any recent memories (within last 5 minutes)
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
    
    // MARK: - Sections
    
    private var recentInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("RECENT INSIGHTS", systemImage: "sparkles")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            
            if recentMemories.isEmpty {
                Text("No significant events captured today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
            } else {
                ForEach(recentMemories, id: \.self) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.purple.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(insight)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                }
            }
        }
    }

    private var dailyBriefSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("DAILY BRIEF", systemImage: "doc.text.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            
            Text(brief)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(.primary.opacity(0.9))
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        }
    }

    private var footerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LAST INGESTION")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.secondary)
                Text(lastIngestionTime)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            
            Spacer()
            
            if let stats = semanticMemoryStats {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("NEURAL GRAPH")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.secondary)
                    Text("\(stats.embeddedMessages) NODES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            }
        }
        .padding(.top, 10)
    }
}



#Preview {
    BrainDashboardView()
}
