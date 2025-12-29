//
//  BrainSidebarWindow.swift
//  BrainCore
//
//  Ambient sidebar window for Brain OS - the magical always-present interface
//

import AppKit
import SwiftUI

// MARK: - Window Controller

/// Manages the ambient Brain sidebar floating window
@MainActor
public final class BrainSidebarWindowController: NSObject, NSWindowDelegate {
    public static let shared = BrainSidebarWindowController()
    
    private var sidebarWindow: NSWindow?
    private var isExpanded = false
    
    private let collapsedWidth: CGFloat = 72
    private let expandedWidth: CGFloat = 380
    private let windowHeight: CGFloat = 600
    private let edgeMargin: CGFloat = 12
    
    private override init() {
        super.init()
    }
    
    public func showSidebar() {
        guard sidebarWindow == nil else {
            sidebarWindow?.makeKeyAndOrderFront(nil)
            return
        }
        
        let contentView = BrainSidebarView(
            isExpanded: Binding(
                get: { self.isExpanded },
                set: { self.setExpanded($0) }
            )
        )
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let window = NSWindow(
            contentRect: calculateWindowFrame(expanded: false),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.hasShadow = true
        window.delegate = self
        window.isMovableByWindowBackground = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        sidebarWindow = window
        window.orderFront(nil)
        
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }
    
    public func hideSidebar() {
        guard let window = sidebarWindow else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            self.sidebarWindow = nil
        })
    }
    
    public func toggleSidebar() {
        if sidebarWindow?.isVisible == true {
            hideSidebar()
        } else {
            showSidebar()
        }
    }
    
    public func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        
        guard let window = sidebarWindow else { return }
        
        let newFrame = calculateWindowFrame(expanded: expanded)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
    
    private func calculateWindowFrame(expanded: Bool) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 100, width: collapsedWidth, height: windowHeight)
        }
        
        let screenFrame = screen.visibleFrame
        let width = expanded ? expandedWidth : collapsedWidth
        
        return NSRect(
            x: screenFrame.maxX - width - edgeMargin,
            y: screenFrame.midY - windowHeight / 2,
            width: width,
            height: windowHeight
        )
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowDidMove(_ notification: Notification) {
        // Handle window movement if needed
    }
    
    public func windowDidResignKey(_ notification: Notification) {
        // Optional: collapse when focus lost
    }
}

// MARK: - Brain State

enum BrainState: String, CaseIterable {
    case idle, learning, thinking, listening, speaking, alert
    
    var primaryColor: Color {
        switch self {
        case .idle: return .cyan
        case .learning: return .blue
        case .thinking: return .purple
        case .listening: return .green
        case .speaking: return .mint
        case .alert: return .orange
        }
    }
    
    var secondaryColor: Color {
        switch self {
        case .idle: return .blue
        case .learning: return .cyan
        case .thinking: return .pink
        case .listening: return .teal
        case .speaking: return .cyan
        case .alert: return .red
        }
    }
}

// MARK: - Data Models

struct MemoryStreamItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let time: String
    let color: Color
}

struct ContextItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let color: Color
}

struct SidebarTimelineEvent: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let type: EventType
    
    enum EventType {
        case past, current, upcoming
        
        var color: Color {
            switch self {
            case .past: return .gray
            case .current: return .green
            case .upcoming: return .blue
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class BrainSidebarViewModel: ObservableObject {
    @Published var brainState: BrainState = .idle
    @Published var currentTime: String = ""
    @Published var greeting: String = "Hello"
    @Published var isLearning: Bool = false
    
    @Published var pendingNudges: Int = 0
    @Published var hasUrgentNudge: Bool = false
    @Published var upcomingEvents: Int = 0
    @Published var hasImmediateEvent: Bool = false
    @Published var newInsights: Int = 0
    @Published var stepCount: Int = 0
    
    @Published var nudges: [RelationshipNudge] = []
    @Published var memoryItems: [MemoryStreamItem] = []
    @Published var brief: String = ""
    @Published var contextItems: [ContextItem] = []
    @Published var timelineEvents: [SidebarTimelineEvent] = []
    
    @Published var isVoiceActive: Bool = false
    @Published var voiceTranscript: String = ""
    
    private var timer: Timer?
    
    init() {
        updateTime()
        loadData()
        startTimer()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTime()
            }
        }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        currentTime = formatter.string(from: Date())
        
        let hour = Calendar.current.component(.hour, from: Date())
        greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }
    
    func loadData() {
        Task {
            // Load relationship nudges
            let loadedNudges = await RelationshipAgent.shared.analyzeRecentInteractions()
            await MainActor.run {
                self.nudges = loadedNudges
                self.pendingNudges = loadedNudges.count
                self.hasUrgentNudge = loadedNudges.contains { $0.priority == .high }
            }
            
            // Load daily brief
            let generatedBrief = await BrainManager.shared.generateBrief()
            await MainActor.run {
                self.brief = generatedBrief
            }
            
            // Load health data
            if let steps = try? await BrainHealthManager.shared.fetchStepCount(days: 1).first {
                await MainActor.run {
                    self.stepCount = Int(steps)
                }
            }
            
            // Load calendar events count
            let events = await BrainCalendarManager.shared.getUpcomingBrief()
            await MainActor.run {
                self.upcomingEvents = events.isEmpty ? 0 : min(events.components(separatedBy: ",").count, 5)
            }
            
            // Build context items
            await MainActor.run {
                self.contextItems = [
                    ContextItem(icon: "figure.walk", title: "Steps", value: "\(self.stepCount)", color: self.stepCount > 5000 ? .green : .orange),
                    ContextItem(icon: "calendar", title: "Events", value: "\(self.upcomingEvents) today", color: .blue),
                    ContextItem(icon: "message.fill", title: "Pending", value: "\(self.pendingNudges) replies", color: .purple)
                ]
                
                // Build timeline
                self.timelineEvents = [
                    SidebarTimelineEvent(time: "Now", title: "Focus Time", type: .current),
                    SidebarTimelineEvent(time: "2 PM", title: "Next Event", type: .upcoming),
                    SidebarTimelineEvent(time: "4 PM", title: "Later", type: .upcoming)
                ]
                
                // Mock memory stream items
                self.memoryItems = [
                    MemoryStreamItem(icon: "message.fill", text: "Recent message indexed", time: "2m ago", color: .blue),
                    MemoryStreamItem(icon: "safari", text: "Browser activity learned", time: "5m ago", color: .orange),
                    MemoryStreamItem(icon: "brain.head.profile", text: "New entity extracted", time: "8m ago", color: .purple)
                ]
            }
        }
    }
    
    func activateVoice() {
        isVoiceActive.toggle()
        brainState = isVoiceActive ? .listening : .idle
    }
    
    func refresh() {
        loadData()
    }
}

// MARK: - Main Sidebar View

struct BrainSidebarView: View {
    @Binding var isExpanded: Bool
    @State private var isHovering = false
    @StateObject private var viewModel = BrainSidebarViewModel()
    
    var body: some View {
        ZStack {
            BrainGlassBackground()
            
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: -5, y: 0)
        .onHover { hovering in
            isHovering = hovering
            if hovering && !isExpanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isHovering {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Collapsed View
    
    private var collapsedContent: some View {
        VStack(spacing: 16) {
            BrainOrbView(state: viewModel.brainState, size: 48)
                .padding(.top, 16)
            
            Text(viewModel.currentTime)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            
            Divider()
                .padding(.horizontal, 12)
            
            VStack(spacing: 12) {
                CollapsedStatusItem(icon: "message.fill", count: viewModel.pendingNudges, color: .blue, urgent: viewModel.hasUrgentNudge)
                CollapsedStatusItem(icon: "calendar", count: viewModel.upcomingEvents, color: .orange, urgent: viewModel.hasImmediateEvent)
                CollapsedStatusItem(icon: "brain.head.profile", count: viewModel.newInsights, color: .purple, urgent: false)
                CollapsedStatusItem(icon: "figure.walk", count: viewModel.stepCount / 1000, color: viewModel.stepCount > 5000 ? .green : .orange, urgent: false, suffix: "k")
            }
            
            Spacer()
            
            Button(action: { viewModel.activateVoice() }) {
                Image(systemName: viewModel.isVoiceActive ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(viewModel.isVoiceActive ? .green : .white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Expanded View
    
    private var expandedContent: some View {
        VStack(spacing: 0) {
            expandedHeader
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    MemoryStreamCard(items: viewModel.memoryItems, isLearning: viewModel.isLearning)
                    ActiveContextCard(brief: viewModel.brief, items: viewModel.contextItems)
                    TimelinePreviewCard(events: viewModel.timelineEvents)
                    
                    if !viewModel.nudges.isEmpty {
                        RelationshipNudgesCard(nudges: viewModel.nudges)
                    }
                }
                .padding(16)
            }
            
            VoiceInterfaceBar(isActive: $viewModel.isVoiceActive, transcript: viewModel.voiceTranscript)
        }
    }
    
    private var expandedHeader: some View {
        HStack(spacing: 12) {
            BrainOrbView(state: viewModel.brainState, size: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.greeting)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isLearning ? Color.green : Color.cyan)
                        .frame(width: 6, height: 6)
                    Text(viewModel.isLearning ? "Learning" : "Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            Button(action: { 
                withAnimation(.spring(response: 0.3)) {
                    isExpanded = false 
                }
            }) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
    }
}

// MARK: - Glass Background

struct BrainGlassBackground: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
            
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.05),
                    Color.cyan.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        }
    }
}

// MARK: - Brain Orb View

struct BrainOrbView: View {
    let state: BrainState
    let size: CGFloat
    
    @State private var innerPulse: CGFloat = 1.0
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [state.primaryColor.opacity(0.4), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 1.2
                    )
                )
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(innerPulse)
                .blur(radius: 8)
            
            Circle()
                .fill(
                    AngularGradient(
                        colors: [state.primaryColor, state.secondaryColor, state.primaryColor],
                        center: .center,
                        angle: .degrees(rotation)
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size * 0.7, height: size * 0.7)
                        .offset(x: -size * 0.08, y: -size * 0.08)
                        .blur(radius: 3)
                )
                .shadow(color: state.primaryColor.opacity(0.5), radius: 10)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                innerPulse = 1.15
            }
        }
    }
}

// MARK: - Collapsed Status Item

struct CollapsedStatusItem: View {
    let icon: String
    let count: Int
    let color: Color
    let urgent: Bool
    var suffix: String = ""
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                
                if count > 0 {
                    Text("\(count)\(suffix)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 44, height: 44)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            if urgent {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
            }
        }
    }
}

// MARK: - Memory Stream Card

struct MemoryStreamCard: View {
    let items: [MemoryStreamItem]
    let isLearning: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("MEMORY STREAM")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                
                Spacer()
                
                if isLearning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Learning")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
            }
            
            VStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(item.color)
                            .frame(width: 24)
                        
                        Text(item.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(item.time)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - Active Context Card

struct ActiveContextCard: View {
    let brief: String
    let items: [ContextItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                Text("DAILY BRIEF")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Text(brief.isEmpty ? "Loading your personalized brief..." : brief)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.cyan.opacity(0.1), .purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(8)
            
            HStack(spacing: 8) {
                ForEach(items) { item in
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(item.color)
                        Text(item.value)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(item.color.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - Timeline Preview Card

struct TimelinePreviewCard: View {
    let events: [SidebarTimelineEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            HStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(event.type.color)
                            .frame(width: event.type == .current ? 12 : 8, height: event.type == .current ? 12 : 8)
                        
                        Text(event.time)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text(event.title)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    
                    if index < events.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)
                            .frame(maxWidth: 30)
                            .offset(y: -20)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - Relationship Nudges Card

struct RelationshipNudgesCard: View {
    let nudges: [RelationshipNudge]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                Text("RELATIONSHIPS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                
                Spacer()
                
                Text("\(nudges.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.pink.opacity(0.3)))
            }
            
            ForEach(nudges.prefix(3), id: \.contactName) { nudge in
                HStack(spacing: 10) {
                    Circle()
                        .fill(nudge.priority == .high ? Color.red : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nudge.contactName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        Text(nudge.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Text("Reply")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.blue.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - Voice Interface Bar

struct VoiceInterfaceBar: View {
    @Binding var isActive: Bool
    let transcript: String
    
    var body: some View {
        VStack(spacing: 8) {
            if isActive {
                Text(transcript.isEmpty ? "Listening..." : transcript)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            
            HStack(spacing: 12) {
                Button(action: { isActive.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: isActive ? "waveform" : "mic.fill")
                            .font(.system(size: 16))
                        
                        Text(isActive ? "Listening..." : "Ask Brain")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(isActive ? .green : .white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(isActive ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - Preview

#if DEBUG
struct BrainSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3).ignoresSafeArea()
            
            HStack {
                Spacer()
                BrainSidebarView(isExpanded: .constant(true))
                    .frame(width: 380, height: 600)
            }
        }
    }
}
#endif
