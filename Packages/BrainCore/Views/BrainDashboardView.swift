import SwiftUI

struct BrainDashboardView: View {
    @State private var greeting = "Good Morning"
    @State private var userName = NSFullUserName()
    @State private var brief = "Loading your daily brief..."
    @State private var nudges: [RelationshipNudge] = []
    @State private var stepCount: Int = 0
    @State private var currentLocation = "Unknown"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                BrainAvatarView()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                
                VStack(alignment: .leading) {
                    Text("\(greeting), \(userName)")
                        .font(.headline)
                    Text("BrainOS is active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("DAILY BRIEF")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                Text(brief)
                    .font(.system(size: 14, weight: .medium))
                    .lineSpacing(4)
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("RELATIONSHIPS INBOX")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                ForEach(nudges) { nudge in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(nudge.contactName)
                                .font(.system(size: 14, weight: .bold))
                            Text(nudge.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Draft") {
                            // Action to draft message
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            HStack(spacing: 12) {
                DashboardCard(title: "Health", value: "\(stepCount.formatted()) steps", icon: "figure.walk", color: .green)
                DashboardCard(title: "Location", value: currentLocation, icon: "location.fill", color: .blue)
            }
            
            Spacer()
            
            HStack {
                Text("Press ⌥Space to chat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
        }
        .padding(20)
        .frame(width: 350, height: 500)
        .onAppear {
            // Load user profile
            userName = UserDefaults.standard.string(forKey: "userName") ?? NSFullUserName()
            
            // Set greeting based on time
            let hour = Calendar.current.component(.hour, from: Date())
            greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
            
            Task {
                // Load relationship nudges
                self.nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
                
                // Generate AI brief
                self.brief = await BrainManager.shared.generateBrief()
                
                // Load health data
                if let steps = try? await BrainHealthManager.shared.fetchStepCount(days: 1).first {
                    self.stepCount = Int(steps)
                }
                
                // Note: Location tracking is logged but not currently exposed for display
                // Future: Add BrainDatabaseManager.shared.getRecentLocation() method
            }
        }
    }
}

struct DashboardCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    BrainDashboardView()
}
