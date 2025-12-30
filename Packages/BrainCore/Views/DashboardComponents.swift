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
    @State private var breath = 1.0
    
    var body: some View {
        ZStack {
            // Multi-layered glass sphere + Neural core
            ForEach(0..<3) { i in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [orbColor.opacity(0.8 - Double(i)*0.2), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .scaleEffect(breath + (Double(i) * 0.05))
                    .offset(x: sin(rotation * .pi / 180 + Double(i)) * 5,
                            y: cos(rotation * .pi / 180 + Double(i)) * 5)
            }
            
            // Rotating "Neural Path" rings
            Circle()
                .stroke(orbColor.opacity(0.5), lineWidth: 0.5)
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(rotation))
            
            Circle()
                .stroke(orbColor.opacity(0.3), lineWidth: 1)
                .frame(width: 85, height: 85)
                .rotationEffect(.degrees(-rotation * 1.5))
            
            // Highlight
            Circle()
                .fill(
                    LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 30, height: 30)
                .offset(x: -15, y: -15)
                .blur(radius: 2)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breath = 1.15
            }
        }
    }
    
    private var orbColor: Color {
        switch state {
        case .peak: return .purple
            case .low: return .orange
        }
    }
}

struct MemoryFlowTicker: View {
    let items: [String]
    @State private var offset: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.prefix(3), id: \.self) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 4, height: 4)
                    
                    Text(item)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                      removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .frame(height: 50, alignment: .top)
        .clipped()
    }
}
