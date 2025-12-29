import SwiftUI

struct VitalMeter: View {
    let title: String
    let icon: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("\(Int(value * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(min(1.0, value)))
                        .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
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
            HStack(spacing: 16) {
                // Priority Indicator
                let priorityColor = nudge.urgency > 0.8 ? Color.red : Color.blue
                
                ZStack {
                    Circle()
                        .fill(priorityColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(priorityColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(nudge.contactName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(nudge.reason)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
            )
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
