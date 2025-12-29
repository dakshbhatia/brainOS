//
//  ChatEmptyState.swift
//  BrainOS
//
//  Cinematic empty state with animated gradient and quick actions
//

import AppKit
import SwiftUI

struct ChatEmptyState: View {
    let hasModels: Bool
    let selectedModel: String?
    let personas: [Persona]
    let activePersonaId: UUID
    let onOpenModelManager: () -> Void
    let onUseFoundation: (() -> Void)?
    let onQuickAction: (String) -> Void
    let onSelectPersona: (UUID) -> Void

    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var permissionService = SystemPermissionService.shared
    @AppStorage("hasCompletedIntegrationsOnboarding") private var hasCompletedIntegrationsOnboarding = false
    @AppStorage("hasCompletedProfileSetup") private var hasCompletedProfileSetup = false
    @State private var showProfileSetup = false
    @State private var glowIntensity: CGFloat = 0.6
    @State private var hasAppeared = false
    @State private var isVisible = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var activePersona: Persona {
        personas.first { $0.id == activePersonaId } ?? Persona.default
    }

    /// Top suggested models to display in empty state
    private var topSuggestions: [MLXModel] {
        modelManager.suggestedModels.filter { $0.isTopSuggestion }
    }

    private let quickActions = [
        QuickAction(icon: "lightbulb", text: "Explain a concept", prompt: "Explain "),
        QuickAction(icon: "doc.text", text: "Summarize text", prompt: "Summarize the following: "),
        QuickAction(icon: "chevron.left.forwardslash.chevron.right", text: "Write code", prompt: "Write code that "),
        QuickAction(icon: "pencil.line", text: "Help me write", prompt: "Help me write "),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if !hasModels {
                noModelsState
            } else if !hasCompletedIntegrationsOnboarding {
                integrationsState
            } else {
                readyState
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showProfileSetup) {
            UserProfileSetupView()
        }
        .onAppear {
            isVisible = true
            withAnimation(theme.animationSlow().delay(0.1)) {
                hasAppeared = true
            }
            startGradientAnimation()
            
            // Show profile setup after integrations if not completed
            if hasCompletedIntegrationsOnboarding && !hasCompletedProfileSetup {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showProfileSetup = true
                }
            }
        }
        .onDisappear {
            // Stop animations when view is hidden
            isVisible = false
            stopGradientAnimation()
        }
    }

    // MARK: - Integrations State

    private var integrationsState: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(theme.accentColor.opacity(0.1))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "link")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(theme.accentColor)
                    }
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.9)
                    
                    Text("Connect your life")
                        .font(theme.font(size: CGFloat(theme.headingSize) + 2, weight: .semibold))
                        .foregroundColor(theme.primaryText)
                    
                    Text("Grant access to your local data to enable powerful agent capabilities.")
                        .font(theme.font(size: CGFloat(theme.bodySize) - 1))
                        .foregroundColor(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(theme.springAnimation().delay(0.1), value: hasAppeared)

                // Permissions list
                VStack(spacing: 10) {
                    IntegrationRow(permission: .calendar, service: permissionService)
                    IntegrationRow(permission: .reminders, service: permissionService)
                    IntegrationRow(permission: .contacts, service: permissionService)
                    IntegrationRow(permission: .health, service: permissionService)
                }
                .frame(maxWidth: 380)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(theme.springAnimation().delay(0.2), value: hasAppeared)
                
                // Optional Vision Model Section
                visionModelSection
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(theme.springAnimation().delay(0.25), value: hasAppeared)

                // Actions
                VStack(spacing: 12) {
                    Button(action: {
                        withAnimation(theme.animationSlow()) {
                            hasCompletedIntegrationsOnboarding = true
                        }
                    }) {
                        Text("Continue to Chat")
                            .font(theme.font(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(theme.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        withAnimation(theme.animationSlow()) {
                            hasCompletedIntegrationsOnboarding = true
                        }
                    }) {
                        Text("Skip for now")
                            .font(theme.font(size: 12, weight: .medium))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(theme.springAnimation().delay(0.3), value: hasAppeared)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Vision Model Section
    
    private var visionModelSection: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.accentColor)
                        Text("Screenshot Vision (Optional)")
                            .font(theme.font(size: 13, weight: .semibold))
                            .foregroundColor(theme.primaryText)
                    }
                    
                    Text("Enable AI-powered visual analysis of your screenshots")
                        .font(theme.font(size: 10))
                        .foregroundColor(theme.tertiaryText)
                }
                Spacer()
            }
            
            // Vision model download card
            if let visionModel = topSuggestions.first(where: { ModelManager.isVisionModel(modelId: $0.id) }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "eye.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.purple)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(visionModel.name)
                                .font(theme.font(size: 12, weight: .semibold))
                                .foregroundColor(theme.primaryText)
                                .lineLimit(1)
                            Text("Understands images and screenshots")
                                .font(theme.font(size: 10))
                                .foregroundColor(theme.secondaryText)
                        }
                        
                        Spacer()
                        
                        if visionModel.isDownloaded {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                Text("Installed")
                                    .font(theme.font(size: 10, weight: .medium))
                                    .foregroundColor(theme.secondaryText)
                            }
                        } else {
                            Button(action: {
                                modelManager.downloadModel(visionModel)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 10))
                                    Text("Download")
                                        .font(theme.font(size: 10, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.purple)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if !visionModel.isDownloaded {
                        Text("💡 You can always download this later from Model Manager")
                            .font(theme.font(size: 9))
                            .foregroundColor(theme.tertiaryText)
                            .padding(.leading, 42)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.secondaryBackground.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
        .frame(maxWidth: 380)
    }

    // MARK: - Ready State (has models)

    private var readyState: some View {
        VStack(spacing: 32) {
            // Greeting section
            VStack(spacing: 20) {
                // Greeting text
                VStack(spacing: 8) {
                    Text(greeting)
                        .font(theme.font(size: CGFloat(theme.titleSize) + 4, weight: .semibold))
                        .foregroundColor(theme.primaryText)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 15)

                    Text("How can I help you today?")
                        .font(theme.font(size: CGFloat(theme.bodySize) + 2))
                        .foregroundColor(theme.secondaryText)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                }

                // Persona selector - always visible
                personaDropdown
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
            }
            .animation(theme.springAnimation().delay(0.1), value: hasAppeared)

            // Quick actions
            quickActionsGrid
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(theme.springAnimation().delay(0.25), value: hasAppeared)

            // Model indicator
            if let model = selectedModel {
                modelIndicator(model)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: hasAppeared)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - No Models State

    private var noModelsState: some View {
        VStack(spacing: 28) {
            // Glowing icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(theme.accentColor)
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)
                    .opacity(glowIntensity * 0.3)

                // Inner glow
                Circle()
                    .fill(theme.accentColor)
                    .frame(width: 80, height: 80)
                    .blur(radius: 10)
                    .opacity(glowIntensity * 0.2)

                // Base circle
                Circle()
                    .fill(theme.secondaryBackground)
                    .frame(width: 80, height: 80)

                // Icon
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.accentColor, theme.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.8)
            .animation(theme.springAnimation().delay(0.1), value: hasAppeared)

            // Title and description - uses theme typography
            VStack(spacing: 8) {
                Text("Get started with a model")
                    .font(theme.font(size: CGFloat(theme.headingSize) + 4, weight: .semibold))
                    .foregroundColor(theme.primaryText)

                Text("Download a recommended model to start chatting")
                    .font(theme.font(size: CGFloat(theme.bodySize)))
                    .foregroundColor(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(theme.springAnimation().delay(0.15), value: hasAppeared)

            // Top suggested model cards
            VStack(spacing: 12) {
                ForEach(Array(topSuggestions.enumerated()), id: \.element.id) { index, model in
                    SuggestedModelCard(
                        model: model
                    )
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 15)
                    .animation(theme.springAnimation().delay(0.25 + Double(index) * 0.08), value: hasAppeared)
                }
            }

            // Secondary actions - uses theme caption size
            HStack(spacing: 16) {
                Button(action: onOpenModelManager) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                            .font(theme.font(size: CGFloat(theme.captionSize) - 1))
                        Text("Browse all models")
                    }
                    .font(theme.font(size: CGFloat(theme.captionSize) + 1, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                if let useFoundation = onUseFoundation {
                    Text("·")
                        .foregroundColor(theme.tertiaryText)

                    Button(action: useFoundation) {
                        HStack(spacing: 5) {
                            Image(systemName: "apple.logo")
                                .font(theme.font(size: CGFloat(theme.captionSize) - 1))
                            Text("Use Apple Foundation")
                        }
                        .font(theme.font(size: CGFloat(theme.captionSize) + 1, weight: .medium))
                        .foregroundColor(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.5), value: hasAppeared)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Persona Dropdown

    private var personaDropdown: some View {
        Menu {
            ForEach(personas) { persona in
                Button(action: { onSelectPersona(persona.id) }) {
                    HStack {
                        Text(persona.name)
                        if persona.id == activePersonaId {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                }
            }

            Divider()

            Button(action: {
                AppDelegate.shared?.showManagementWindow(initialTab: .personas)
            }) {
                Label("Manage Personas...", systemImage: "person.2.badge.gearshape")
            }
        } label: {
            HStack(spacing: 8) {
                // Persona icon
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.accentColor)

                Text(activePersona.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.primaryText)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(theme.secondaryBackground.opacity(colorScheme == .dark ? 0.5 : 0.7))
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.primaryBorder.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
        ) {
            ForEach(quickActions) { action in
                QuickActionButton(action: action, onTap: onQuickAction)
            }
        }
        .frame(maxWidth: 440)
    }

    // MARK: - Model Indicator

    private func modelIndicator(_ model: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)

            Text("Using \(displayModelName(model))")
                .font(.system(size: 12))
                .foregroundColor(theme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(theme.secondaryBackground.opacity(colorScheme == .dark ? 0.5 : 0.8))
        )
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12: return "Good morning"
        case 12 ..< 17: return "Good afternoon"
        case 17 ..< 22: return "Good evening"
        default: return "Hello"
        }
    }

    private func displayModelName(_ raw: String) -> String {
        if raw.lowercased() == "foundation" { return "Foundation" }
        if let last = raw.split(separator: "/").last { return String(last) }
        return raw
    }

    private func startGradientAnimation() {
        guard isVisible else { return }
        // Glow pulse animation - subtle breathing effect
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowIntensity = 1.0
        }
    }

    private func stopGradientAnimation() {
        // Reset animation values without animation to stop the repeating animations
        withAnimation(.linear(duration: 0)) {
            glowIntensity = 0.6
        }
        hasAppeared = false
    }
}

// MARK: - Quick Action Model

private struct QuickAction: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let prompt: String
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let action: QuickAction
    let onTap: (String) -> Void

    @State private var isHovered = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: { onTap(action.prompt) }) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? theme.accentColor : theme.secondaryText)
                    .frame(width: 20)

                Text(action.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.primaryText)

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
                    .opacity(isHovered ? 1 : 0)
                    .offset(x: isHovered ? 0 : -5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isHovered
                            ? theme.secondaryBackground
                            : theme.secondaryBackground.opacity(colorScheme == .dark ? 0.5 : 0.8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isHovered
                                    ? theme.primaryBorder
                                    : theme.primaryBorder.opacity(colorScheme == .dark ? 0.3 : 0.5),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(theme.animationQuick()) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Suggested Model Card

private struct SuggestedModelCard: View {
    let model: MLXModel

    @StateObject private var modelManager = ModelManager.shared
    @State private var isHovered = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var downloadState: DownloadState {
        modelManager.downloadStates[model.id] ?? .notStarted
    }

    private var isVLM: Bool {
        model.isLikelyVLM
    }

    private var modelTypeIcon: String {
        isVLM ? "eye" : "text.bubble"
    }

    private var modelTypeLabel: String {
        isVLM ? "Vision" : "Text"
    }

    private var canDownload: Bool {
        if case .notStarted = downloadState { return true }
        if case .failed = downloadState { return true }
        return false
    }

    var body: some View {
        Button(action: {
            if case .notStarted = downloadState {
                modelManager.downloadModel(model)
            }
        }) {
            HStack(spacing: 16) {
                // Model icon with gradient background
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    theme.accentColor.opacity(0.2),
                                    theme.accentColor.opacity(0.1),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: isVLM ? "eye" : "cpu")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(theme.accentColor)
                }

                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.primaryText)
                            .lineLimit(1)

                        // Model type badge
                        HStack(spacing: 3) {
                            Image(systemName: modelTypeIcon)
                                .font(.system(size: 8, weight: .semibold))
                            Text(modelTypeLabel)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(isVLM ? .purple : theme.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((isVLM ? Color.purple : theme.accentColor).opacity(0.12))
                        )

                        // Quantization badge if available
                        if let quant = model.quantization {
                            Text(quant)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(theme.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(theme.tertiaryBackground)
                                )
                        }
                    }

                    if case .downloading(let progress) = downloadState {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(theme.accentColor)
                            Text("\(Int(progress * 100))% downloaded")
                                .font(.system(size: 10))
                                .foregroundColor(theme.secondaryText)
                        }
                    } else {
                        Text(model.description)
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Download status icon
                Group {
                    switch downloadState {
                    case .notStarted:
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 24))
                            .foregroundColor(isHovered ? theme.accentColor : theme.secondaryText)
                    case .downloading:
                        ProgressView()
                            .controlSize(.small)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(theme.successColor)
                    case .failed:
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 24))
                            .foregroundColor(theme.errorColor)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.secondaryBackground.opacity(isHovered ? 0.8 : (colorScheme == .dark ? 0.5 : 0.8)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isHovered
                                    ? theme.accentColor.opacity(0.3)
                                    : theme.primaryBorder.opacity(colorScheme == .dark ? 0.3 : 0.5),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDownload)
        .onHover { hovering in
            withAnimation(theme.animationQuick()) {
                isHovered = hovering
            }
        }
        .frame(maxWidth: 520)
    }
}

// MARK: - Preview

#if DEBUG
    struct ChatEmptyState_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                ChatEmptyState(
                    hasModels: true,
                    selectedModel: "foundation",
                    personas: [.default],
                    activePersonaId: Persona.default.id,
                    onOpenModelManager: {},
                    onUseFoundation: {},
                    onQuickAction: { _ in },
                    onSelectPersona: { _ in }
                )
            }
            .frame(width: 700, height: 600)
            .background(Color(hex: "0f0f10"))

            VStack {
                ChatEmptyState(
                    hasModels: false,
                    selectedModel: nil,
                    personas: [.default],
                    activePersonaId: Persona.default.id,
                    onOpenModelManager: {},
                    onUseFoundation: {},
                    onQuickAction: { _ in },
                    onSelectPersona: { _ in }
                )
            }
            .frame(width: 700, height: 600)
            .background(Color(hex: "0f0f10"))
        }
    }
#endif

struct IntegrationRow: View {
    let permission: SystemPermission
    @ObservedObject var service: SystemPermissionService
    @Environment(\.theme) private var theme

    var isGranted: Bool {
        service.permissionStates[permission] ?? false
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isGranted ? theme.accentColor.opacity(0.1) : theme.secondaryBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: permission.systemIconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isGranted ? theme.accentColor : theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                    .font(theme.font(size: 14, weight: .medium))
                    .foregroundColor(theme.primaryText)
                
                Text(permission.description)
                    .font(theme.font(size: 11))
                    .foregroundColor(theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(theme.accentColor)
                    .font(.system(size: 20))
            } else {
                Button(action: {
                    service.requestPermission(permission)
                }) {
                    Text("Grant")
                        .font(theme.font(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(theme.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.secondaryBackground.opacity(0.5))
        )
    }
}
