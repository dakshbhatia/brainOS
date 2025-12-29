import SwiftUI

struct VitalMeter: View {
    let title: String
    let icon: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.1))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(min(1.0, value)))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

struct ActionCard: View {
    let nudge: RelationshipNudge
    
    var body: some View {
        Button(action: {
            if let url = nudge.deepLinkURL, let link = URL(string: url) {
                #if os(macOS)
                NSWorkspace.shared.open(link)
                #else
                UIApplication.shared.open(link)
                #endif
            }
        }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(nudge.urgency > 0.8 ? Color.red : Color.blue)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(nudge.contactName)
                        .font(.system(size: 13, weight: .bold))
                    Text(nudge.reason)
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

enum BrainOrbState {
    case low, normal, peak
}

struct DashboardOrbView: View {
    let state: BrainOrbState
    @State private var rotation = 0.0
    
    var body: some View {
        ZStack {
            // Multi-layered glass sphere
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor.opacity(0.8), .clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 40
                    )
                )
            
            // Rotating "Energy" rings
            Circle()
                .stroke(orbColor.opacity(0.4), lineWidth: 1)
                .rotationEffect(.degrees(rotation))
            
            Circle()
                .stroke(orbColor.opacity(0.2), lineWidth: 3)
                .padding(5)
                .rotationEffect(.degrees(-rotation * 0.5))
        }
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
    
    private var orbColor: Color {
        switch state {
        case .peak: return .purple
        case .normal: return .blue
        case .low: return .orange
        }
    }
}
