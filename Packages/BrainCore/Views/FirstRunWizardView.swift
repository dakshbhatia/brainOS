//
//  FirstRunWizardView.swift
//  BrainOS
//
//  Comprehensive first-run wizard for onboarding new users with
//  permission setup, semantic memory configuration, and historical data backfill.
//

import SwiftUI

/// First-run wizard steps
enum WizardStep: Int, CaseIterable {
    case welcome = 0
    case permissions
    case semanticMemory
    case historicalData
    case modelSelection
    case complete
    
    var title: String {
        switch self {
        case .welcome: return "Welcome to BrainOS"
        case .permissions: return "Enable Integrations"
        case .semanticMemory: return "Semantic Memory"
        case .historicalData: return "Build Your Memory"
        case .modelSelection: return "Choose Your Model"
        case .complete: return "You're All Set!"
        }
    }
    
    var subtitle: String {
        switch self {
        case .welcome: return "Your AI-powered second brain"
        case .permissions: return "Connect your data sources"
        case .semanticMemory: return "Enable smart context retrieval"
        case .historicalData: return "Import your recent history"
        case .modelSelection: return "Pick your default AI model"
        case .complete: return "BrainOS is ready to assist you"
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: return "brain.head.profile"
        case .permissions: return "link"
        case .semanticMemory: return "sparkles"
        case .historicalData: return "clock.arrow.circlepath"
        case .modelSelection: return "cube.box.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

@MainActor
struct FirstRunWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var permissionService = SystemPermissionService.shared
    @StateObject private var modelManager = ModelManager.shared
    
    @AppStorage("hasCompletedFirstRunWizard") private var hasCompletedFirstRunWizard = false
    
    @State private var currentStep: WizardStep = .welcome
    @State private var isProcessingBackfill = false
    @State private var backfillProgress: Double = 0.0
    @State private var backfillStatus: String = ""
    @State private var selectedModel: String? = nil
    @State private var openAIKey: String = ""
    @State private var isTestingKey = false
    @State private var keyTestResult: KeyTestResult?
    
    enum KeyTestResult {
        case success
        case failure(String)
    }
    
    // Calculate progress through wizard
    private var progressValue: Double {
        Double(currentStep.rawValue) / Double(WizardStep.allCases.count - 1)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(themeManager.currentTheme.secondaryBackground)
                    
                    Rectangle()
                        .fill(themeManager.currentTheme.accentColor)
                        .frame(width: geo.size.width * progressValue)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progressValue)
                }
            }
            .frame(height: 4)
            
            // Main content
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(themeManager.currentTheme.accentColor.opacity(0.15))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: currentStep.icon)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.accentColor)
                        }
                        
                        Text(currentStep.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.primaryText)
                        
                        Text(currentStep.subtitle)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(themeManager.currentTheme.secondaryText)
                    }
                    .padding(.top, 40)
                    
                    // Step content
                    stepContent
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 100)
            }
            
            // Navigation buttons
            HStack(spacing: 16) {
                if currentStep != .welcome {
                    Button(action: goBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(themeManager.currentTheme.secondaryBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                if currentStep == .complete {
                    Button(action: completeWizard) {
                        Text("Get Started")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(themeManager.currentTheme.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: goNext) {
                        HStack(spacing: 6) {
                            Text(currentStep == .historicalData && !isProcessingBackfill ? "Skip" : "Continue")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(themeManager.currentTheme.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessingBackfill)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .background(themeManager.currentTheme.primaryBackground)
        }
        .frame(width: 600, height: 650)
        .background(themeManager.currentTheme.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 10)
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeContent
        case .permissions:
            permissionsContent
        case .semanticMemory:
            semanticMemoryContent
        case .historicalData:
            historicalDataContent
        case .modelSelection:
            modelSelectionContent
        case .complete:
            completeContent
        }
    }
    
    // MARK: - Welcome Step
    
    private var welcomeContent: some View {
        VStack(spacing: 24) {
            Text("BrainOS is your AI-powered second brain that learns from your digital life and helps you work smarter.")
                .font(.system(size: 15))
                .foregroundColor(themeManager.currentTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "brain.head.profile", title: "Semantic Memory", description: "Remembers your conversations and finds relevant context")
                featureRow(icon: "calendar", title: "Integrated Life", description: "Connects to your calendar, messages, and more")
                featureRow(icon: "sparkles", title: "Local AI", description: "Runs powerful models right on your Mac")
                featureRow(icon: "lock.shield", title: "Privacy First", description: "Your data stays on your device")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.currentTheme.secondaryBackground.opacity(0.5))
            )
        }
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(themeManager.currentTheme.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.primaryText)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.currentTheme.secondaryText)
            }
        }
    }
    
    // MARK: - Permissions Step
    
    private var permissionsContent: some View {
        VStack(spacing: 20) {
            Text("Grant access to these sources to unlock BrainOS's full potential. You can change these anytime in Settings.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                permissionRow(permission: .calendar, title: "Calendar", description: "See your schedule and events")
                permissionRow(permission: .reminders, title: "Reminders", description: "Track your tasks and to-dos")
                permissionRow(permission: .contacts, title: "Contacts", description: "Know who you're talking about")
                permissionRow(permission: .health, title: "Health", description: "Track your wellness data")
                permissionRow(permission: .disk, title: "Full Disk Access", description: "Read iMessages and Safari history")
            }
        }
        .onAppear {
            permissionService.startPeriodicRefresh(interval: 2.0)
        }
        .onDisappear {
            permissionService.stopPeriodicRefresh()
        }
    }
    
    private func permissionRow(permission: SystemPermission, title: String, description: String) -> some View {
        let isGranted = permissionService.permissionStates[permission] ?? false
        
        return HStack(spacing: 16) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(isGranted ? .green : themeManager.currentTheme.tertiaryText)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.primaryText)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.currentTheme.secondaryText)
            }
            
            Spacer()
            
            if !isGranted {
                Button("Enable") {
                    permissionService.requestPermission(permission)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.currentTheme.accentColor)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isGranted ? Color.green.opacity(0.1) : themeManager.currentTheme.secondaryBackground)
        )
    }
    
    // MARK: - Semantic Memory Step
    
    private var semanticMemoryContent: some View {
        VStack(spacing: 20) {
            if AutoEmbeddingService.shared.isConfigured {
                // Already configured
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("Semantic Memory is Active!")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.currentTheme.primaryText)
                    
                    Text("Your conversations will be indexed for smart context retrieval.")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Enter your OpenAI API key to enable semantic memory. This allows BrainOS to index your conversations and retrieve relevant context automatically.")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.currentTheme.secondaryText)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                    
                    SecureField("sk-...", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack(spacing: 8) {
                        Button(action: testAPIKey) {
                            if isTestingKey {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("Test Key")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(themeManager.currentTheme.accentColor)
                        .disabled(openAIKey.isEmpty || isTestingKey)
                        
                        if let result = keyTestResult {
                            switch result {
                            case .success:
                                Label("Valid!", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case .failure(let error):
                                Label(error, systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.currentTheme.secondaryBackground)
                )
                
                Button("Skip for Now") {
                    goNext()
                }
                .font(.system(size: 13))
                .foregroundColor(themeManager.currentTheme.tertiaryText)
            }
        }
    }
    
    private func testAPIKey() {
        guard !openAIKey.isEmpty else { return }
        
        isTestingKey = true
        keyTestResult = nil
        
        Task {
            do {
                // Simple test: try to get embeddings for a test string
                let testService = EmbeddingService(apiKey: openAIKey)
                _ = try await testService.embed("Hello, world!")
                
                // Success - configure the service
                AutoEmbeddingService.shared.configure(openAIKey: openAIKey)
                keyTestResult = .success
            } catch {
                keyTestResult = .failure("Invalid key")
            }
            isTestingKey = false
        }
    }
    
    // MARK: - Historical Data Step
    
    private var historicalDataContent: some View {
        VStack(spacing: 20) {
            Text("Import the last 7 days of your messages, calendar events, and browsing history to jumpstart your semantic memory.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            if isProcessingBackfill {
                VStack(spacing: 16) {
                    ProgressView(value: backfillProgress)
                        .progressViewStyle(.linear)
                        .tint(themeManager.currentTheme.accentColor)
                    
                    Text(backfillStatus)
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                    
                    Text("\(Int(backfillProgress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.primaryText)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.currentTheme.secondaryBackground)
                )
            } else {
                Button(action: startBackfill) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Start Import")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.currentTheme.accentColor)
                    )
                }
                .buttonStyle(.plain)
                
                Text("This may take a few minutes depending on your data volume.")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.currentTheme.tertiaryText)
            }
        }
    }
    
    private func startBackfill() {
        isProcessingBackfill = true
        backfillProgress = 0.0
        backfillStatus = "Starting..."
        
        Task {
            // Step 1: Backfill chat sessions
            backfillStatus = "Processing chat history..."
            await AutoEmbeddingService.shared.backfillAllSessions()
            backfillProgress = 0.5
            
            // Step 2: Trigger background ingestion for messages/safari/etc
            backfillStatus = "Importing recent data..."
            await BackgroundIngestionService.shared.start()
            backfillProgress = 0.8
            
            // Step 3: Wait a moment for ingestion
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            backfillProgress = 1.0
            backfillStatus = "Complete!"
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isProcessingBackfill = false
            goNext()
        }
    }
    
    // MARK: - Model Selection Step
    
    private var modelSelectionContent: some View {
        VStack(spacing: 20) {
            Text("Choose a default model for your conversations. You can download more models anytime from Settings.")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                // Foundation model (always available on Apple Silicon)
                if FoundationModelService.isDefaultModelAvailable() {
                    modelOption(
                        id: "foundation",
                        name: "Apple Foundation",
                        description: "Built-in on-device model. Fast and private.",
                        isRecommended: true
                    )
                }
                
                // Show top local models if downloaded
                let localModels = ModelManager.discoverLocalModels().prefix(3)
                ForEach(localModels, id: \.id) { model in
                    modelOption(
                        id: model.id,
                        name: model.displayName,
                        description: model.parameterSize ?? "Local model"
                    )
                }
                
                // Prompt to download if no models
                if localModels.isEmpty {
                    Button(action: {
                        AppDelegate.shared?.showManagementWindow(initialTab: .models)
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Download More Models")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func modelOption(id: String, name: String, description: String, isRecommended: Bool = false) -> some View {
        let isSelected = selectedModel == id
        
        return Button(action: { selectedModel = id }) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? themeManager.currentTheme.accentColor : themeManager.currentTheme.tertiaryText)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(themeManager.currentTheme.primaryText)
                        
                        if isRecommended {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green)
                                )
                        }
                    }
                    
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? themeManager.currentTheme.accentColor.opacity(0.1) : themeManager.currentTheme.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? themeManager.currentTheme.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Complete Step
    
    private var completeContent: some View {
        VStack(spacing: 24) {
            Text("BrainOS is ready to be your intelligent assistant. Here's what you can do next:")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 16) {
                nextStepRow(icon: "bubble.left.and.bubble.right", text: "Start a conversation with your AI")
                nextStepRow(icon: "keyboard", text: "Use ⌘+Space to open chat anywhere")
                nextStepRow(icon: "gearshape", text: "Explore settings to customize your experience")
                nextStepRow(icon: "person.2", text: "Create custom personas for different tasks")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.currentTheme.secondaryBackground.opacity(0.5))
            )
        }
    }
    
    private func nextStepRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(themeManager.currentTheme.accentColor)
                .frame(width: 28)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.primaryText)
        }
    }
    
    // MARK: - Navigation
    
    private func goNext() {
        if let nextStep = WizardStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = nextStep
            }
        }
    }
    
    private func goBack() {
        if let prevStep = WizardStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = prevStep
            }
        }
    }
    
    private func completeWizard() {
        // Save selected model as default
        if let model = selectedModel {
            var chatConfig = ChatConfigurationStore.load()
            chatConfig.defaultModel = model
            ChatConfigurationStore.save(chatConfig)
        }
        
        // Mark wizard as complete
        hasCompletedFirstRunWizard = true
        
        // Dismiss
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    FirstRunWizardView()
}
