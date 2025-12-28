import SwiftUI

struct BrainDashboardView: View {
    @State private var greeting = "Good Morning, Daksh"
    @State private var brief = "You have 3 meetings today. Your sleep score was 82. You haven't replied to Mom about dinner."
    @State private var nudges: [RelationshipNudge] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(greeting)
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
                DashboardCard(title: "Health", value: "8,240 steps", icon: "figure.walk", color: .green)
                DashboardCard(title: "Finance", value: "$42.50 spent", icon: "creditcard", color: .orange)
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
            Task {
                self.nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
                self.brief = await BrainManager.shared.generateBrief()
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
