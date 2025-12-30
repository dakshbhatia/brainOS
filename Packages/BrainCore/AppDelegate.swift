//
//  AppDelegate.swift
//  BrainOS
//
//  Created by Terence on 8/17/25.
//

import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    static weak var shared: AppDelegate?
    let serverController = ServerController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    let updater = UpdaterViewModel()

    private var activityDot: NSView?
    private var voiceRecordingDot: NSView?
    private var managementWindow: NSWindow?
    private var chatWindow: NSWindow?
    private var wizardWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Configure as regular app (show Dock icon) by default, or accessory if hidden
        let hideDockIcon = ServerConfigurationStore.load()?.hideDockIcon ?? false
        if hideDockIcon {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }

        // App has launched
        NSLog("BrainOS server app launched")
        
        // Check if first-run wizard should be shown
        let hasCompletedWizard = UserDefaults.standard.bool(forKey: "hasCompletedFirstRunWizard")
        if !hasCompletedWizard {
            // Show wizard after a short delay to let the app initialize
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                showFirstRunWizard()
            }
        } else {
            // Show Hub (Management Window) by default as per the new UI direction
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000) // Give a bit more time for background services
                showManagementWindow(initialTab: .brain)
            }
        }

        // Configure local notifications
        NotificationService.shared.configureOnLaunch()

        // Start BrainOS proactive intelligence
        Task {
            await BrainDatabaseManager.shared.initialize()
            await BrainManager.shared.start()
            BrainLocationManager.shared.start()
            _ = try? await BrainCalendarManager.shared.requestAccess()
        }

        // Register BrainOS internal tools
        Task { @MainActor in
            ToolRegistry.shared.register(BrainHealthKitTool())
            ToolRegistry.shared.register(BrainPhotosTool())
            ToolRegistry.shared.register(BrainScreenshotTool())
            ToolRegistry.shared.register(BrainMacOSUseTool())
            ToolRegistry.shared.register(BrainTimeTool())
            ToolRegistry.shared.register(BrainFinanceTool())
            // ToolRegistry.shared.register(BrainMessagesTool())  // OLD: Causes hallucinations when DB unavailable
            ToolRegistry.shared.register(SemanticMessageSearchTool())  // NEW: Semantic search over chat history
            ToolRegistry.shared.register(BrainContactsTool())
            ToolRegistry.shared.register(BrainDraftTool())
            ToolRegistry.shared.register(BrainAppleScriptTool())
        }

        // Configure semantic memory system
        // NOTE: Actual configuration moved to AFTER provider connection (see configureSemanticMemoryFromConnectedProviders)
        // This prevents the race condition where we check providers before they're connected

        // Set up observers for server state changes
        setupObservers()

        // Set up distributed control listeners (local-only management)
        setupControlNotifications()

        // Apply saved Start at Login preference on launch
        let launchedByCLI = ProcessInfo.processInfo.arguments.contains("--launched-by-cli")
        if !launchedByCLI {
            LoginItemService.shared.applyStartAtLogin(serverController.configuration.startAtLogin)
        }

        // Create status bar item and attach click handler
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(named: "brainos") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "BrainOS"
            }
            button.toolTip = "BrainOS Server"
            button.target = self
            button.action = #selector(togglePopover(_:))

            // Add a small green blinking dot at the bottom-right of the status bar button
            let dot = NSView()
            dot.wantsLayer = true
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.isHidden = true
            button.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
                dot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),
            ])
            if let layer = dot.layer {
                layer.backgroundColor = NSColor.systemGreen.cgColor
                layer.cornerRadius = 3.5
                layer.borderWidth = 1
                layer.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            }
            activityDot = dot
            
            // Add a red blinking dot for voice recording (below green dot)
            let voiceDot = NSView()
            voiceDot.wantsLayer = true
            voiceDot.translatesAutoresizingMaskIntoConstraints = false
            voiceDot.isHidden = true
            button.addSubview(voiceDot)
            NSLayoutConstraint.activate([
                voiceDot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
                voiceDot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -12),
                voiceDot.widthAnchor.constraint(equalToConstant: 7),
                voiceDot.heightAnchor.constraint(equalToConstant: 7),
            ])
            if let layer = voiceDot.layer {
                layer.backgroundColor = NSColor.systemRed.cgColor
                layer.cornerRadius = 3.5
                layer.borderWidth = 1
                layer.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            }
            voiceRecordingDot = voiceDot
        }
        statusItem = item
        updateStatusItemAndMenu()
        
        // Monitor voice recording state
        setupVoiceRecordingMonitor()

        // Initialize directory access early so security-scoped bookmark is active
        let _ = DirectoryPickerService.shared

        // Load external tool plugins at launch (after core is initialized)
        PluginManager.shared.loadAll()

        // Auto-connect to enabled providers on launch, then configure semantic memory
        Task { @MainActor in
            await MCPProviderManager.shared.connectEnabledProviders()
            await RemoteProviderManager.shared.connectEnabledProviders()
            
            // NOW configure semantic memory (after providers are actually connected)
            await configureSemanticMemoryFromConnectedProviders()
        }

        // Start plugin repository background refresh for update checking
        PluginRepositoryService.shared.startBackgroundRefresh()

        // Auto-start server on app launch
        Task { @MainActor in
            await serverController.startServer()
        }

        // Setup global hotkey for Chat overlay (configured)
        applyChatHotkey()
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleDeepLink(url)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                self.showManagementWindow(initialTab: .brain)
            }
        }
        return true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quit immediately without confirmation; still shut down server gracefully if running
        guard serverController.isRunning else {
            return .terminateNow
        }

        // Delay termination briefly to allow async shutdown
        Task { @MainActor in
            await serverController.ensureShutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("BrainOS server app terminating")
        PluginRepositoryService.shared.stopBackgroundRefresh()
        Task { @MainActor in
            await MCPServerManager.shared.stopAll()
        }
        SharedConfigurationService.shared.remove()
    }

    // MARK: Status Item / Menu

    private func setupObservers() {
        cancellables.removeAll()
        serverController.$serverHealth
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)
        serverController.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)
        serverController.$configuration
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)

        serverController.$activeRequestCount
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)

        // Publish shared configuration on state/config/address changes
        Publishers.CombineLatest3(
            serverController.$serverHealth,
            serverController.$configuration,
            serverController.$localNetworkAddress
        )
        .receive(on: RunLoop.main)
        .sink { health, config, address in
            SharedConfigurationService.shared.update(
                health: health,
                configuration: config,
                localAddress: address
            )
        }
        .store(in: &cancellables)
    }

    private func updateStatusItemAndMenu() {
        guard let statusItem else { return }
        // Ensure no NSMenu is attached so button action is triggered
        statusItem.menu = nil
        if let button = statusItem.button {
            // Update status bar icon
            if let image = NSImage(named: "brainos") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            }
            // Toggle green blinking dot overlay
            let isGenerating = serverController.activeRequestCount > 0
            if let dot = activityDot {
                if isGenerating {
                    dot.isHidden = false
                    if let layer = dot.layer, layer.animation(forKey: "blink") == nil {
                        let anim = CABasicAnimation(keyPath: "opacity")
                        anim.fromValue = 1.0
                        anim.toValue = 0.2
                        anim.duration = 0.8
                        anim.autoreverses = true
                        anim.repeatCount = .infinity
                        layer.add(anim, forKey: "blink")
                    }
                } else {
                    if let layer = dot.layer {
                        layer.removeAnimation(forKey: "blink")
                    }
                    dot.isHidden = true
                }
            }
            
            // Update voice recording indicator
            if let voiceDot = voiceRecordingDot {
                let isRecording = SpeechRecognizer.shared.isListening
                if isRecording {
                    voiceDot.isHidden = false
                    if let layer = voiceDot.layer, layer.animation(forKey: "voiceBlink") == nil {
                        let anim = CABasicAnimation(keyPath: "opacity")
                        anim.fromValue = 1.0
                        anim.toValue = 0.3
                        anim.duration = 0.6
                        anim.autoreverses = true
                        anim.repeatCount = .infinity
                        layer.add(anim, forKey: "voiceBlink")
                    }
                } else {
                    if let layer = voiceDot.layer {
                        layer.removeAnimation(forKey: "voiceBlink")
                    }
                    voiceDot.isHidden = true
                }
            }
            
            var tooltip: String
            switch serverController.serverHealth {
            case .stopped:
                tooltip =
                    serverController.isRestarting ? "BrainOS — Restarting…" : "BrainOS — Ready to start"
            case .starting:
                tooltip = "BrainOS — Starting…"
            case .restarting:
                tooltip = "BrainOS — Restarting…"
            case .running:
                tooltip = "BrainOS — Running on port \(serverController.port)"
            case .stopping:
                tooltip = "BrainOS — Stopping…"
            case .error(let message):
                tooltip = "BrainOS — Error: \(message)"
            }
            if serverController.activeRequestCount > 0 {
                tooltip += " — Generating…"
            }
            if SpeechRecognizer.shared.isListening {
                tooltip += " — 🎤 Recording"
            }
            // Advertise MCP HTTP endpoints on the same port
            tooltip += " — MCP: /mcp/*"
            button.toolTip = tooltip
        }
    }

    // MARK: - Actions

    @objc private func togglePopover(_ sender: Any?) {
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        showPopover()
    }

    // Expose a method to show the popover programmatically (e.g., for Cmd+,)
    public func showPopover() {
        guard let statusButton = statusItem?.button else { return }
        if let popover, popover.isShown {
            // Already visible; bring app to front
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let themeManager = ThemeManager.shared
        let contentView = ContentView()
            .environmentObject(serverController)
            .environment(\.theme, themeManager.currentTheme)
            .environmentObject(updater)

        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover

        popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

}

// MARK: - Distributed Control (Local Only)
extension AppDelegate {
    fileprivate static let controlToolsReloadNotification = Notification.Name(
        "com.dinoki.BrainOS.control.toolsReload"
    )
    fileprivate static let controlServeNotification = Notification.Name(
        "com.dinoki.BrainOS.control.serve"
    )
    fileprivate static let controlStopNotification = Notification.Name(
        "com.dinoki.BrainOS.control.stop"
    )
    fileprivate static let controlShowUINotification = Notification.Name(
        "com.dinoki.BrainOS.control.ui"
    )

    private func setupControlNotifications() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handleServeCommand(_:)),
            name: Self.controlServeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleStopCommand(_:)),
            name: Self.controlStopNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleShowUICommand(_:)),
            name: Self.controlShowUINotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleToolsReloadCommand(_:)),
            name: Self.controlToolsReloadNotification,
            object: nil
        )
    }

    @objc private func handleServeCommand(_ note: Notification) {
        var desiredPort: Int? = nil
        var exposeFlag: Bool = false
        if let ui = note.userInfo {
            if let p = ui["port"] as? Int {
                desiredPort = p
            } else if let s = ui["port"] as? String, let p = Int(s) {
                desiredPort = p
            }
            if let e = ui["expose"] as? Bool {
                exposeFlag = e
            } else if let es = ui["expose"] as? String {
                let v = es.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                exposeFlag = (v == "1" || v == "true" || v == "yes" || v == "y")
            }
        }

        // Apply defaults if not provided
        let targetPort = desiredPort ?? (ServerConfigurationStore.load()?.port ?? 1337)
        guard (1 ..< 65536).contains(targetPort) else { return }

        // Apply exposure policy based on request (default localhost-only)
        serverController.configuration.exposeToNetwork = exposeFlag
        serverController.port = targetPort
        serverController.saveConfiguration()

        Task { @MainActor in
            await serverController.startServer()
        }
    }

    @objc private func handleStopCommand(_ note: Notification) {
        Task { @MainActor in
            await serverController.stopServer()
        }
    }

    @objc private func handleShowUICommand(_ note: Notification) {
        Task { @MainActor in
            self.showPopover()
        }
    }

    @objc private func handleToolsReloadCommand(_ note: Notification) {
        Task { @MainActor in
            PluginManager.shared.loadAll()
        }
    }
}

// MARK: Deep Link Handling
extension AppDelegate {
    func applyChatHotkey() {
        let cfg = ChatConfigurationStore.load()
        HotKeyManager.shared.register(hotkey: cfg.hotkey) { [weak self] in
            Task { @MainActor in
                self?.toggleChatOverlay()
            }
        }
        
        // Register voice input hotkey (Cmd+Shift+V)
        applyVoiceHotkey()
    }
    
    private func applyVoiceHotkey() {
        // Default: Cmd+Shift+V for voice input (V = keyCode 9)
        // Carbon modifiers: cmdKey=256, shiftKey=512, combined = 768
        let voiceHotkey = Hotkey(keyCode: 9, carbonModifiers: 768, displayString: "⇧⌘V")
        HotKeyManager.shared.register(hotkey: voiceHotkey) { [weak self] in
            Task { @MainActor in
                self?.triggerVoiceInput()
            }
        }
    }
    
    @MainActor private func triggerVoiceInput() {
        // Start voice input - toggle recording
        let recognizer = SpeechRecognizer.shared
        if recognizer.isListening {
            recognizer.stopListening()
        } else {
            // Show chat overlay first if not visible
            if chatWindow == nil || !chatWindow!.isVisible {
                showChatOverlay()
            }
            // Start listening
            recognizer.startListening { result in
                switch result {
                case .success(let text):
                    // Post notification with transcribed text
                    NotificationCenter.default.post(
                        name: .voiceInputReceived,
                        object: nil,
                        userInfo: ["text": text]
                    )
                case .failure(let error):
                    NSLog("🎤 Voice input error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func setupVoiceRecordingMonitor() {
        // Monitor SpeechRecognizer.isListening changes
        SpeechRecognizer.shared.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)
    }
    
    fileprivate func handleDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "huggingface" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        let modelId = items.first(where: { $0.name.lowercased() == "model" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let file = items.first(where: { $0.name.lowercased() == "file" })?.value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let modelId, !modelId.isEmpty else {
            // No model id provided; ignore silently
            return
        }

        // Resolve to ensure it appears in the UI; enforce MLX-only via metadata
        Task { @MainActor in
            if await ModelManager.shared.resolveModelIfMLXCompatible(byRepoId: modelId) == nil {
                let alert = NSAlert()
                alert.messageText = "Unsupported model"
                alert.informativeText = "BrainOS only supports MLX-compatible Hugging Face repositories."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            // Open Model Manager in its own window for deeplinks
            showManagementWindow(initialTab: .models, deeplinkModelId: modelId, deeplinkFile: file)
        }
    }
}

// MARK: - Chat Overlay Window
extension AppDelegate {
    private func setupChatHotKey() {}

    @MainActor private func toggleChatOverlay() {
        if let win = chatWindow, win.isVisible {
            closeChatOverlay()
        } else {
            showChatOverlay()
        }
    }

    @MainActor func showChatOverlay() {
        if chatWindow == nil {
            let themeManager = ThemeManager.shared
            let root = ChatView()
                .environmentObject(serverController)
                .environment(\.theme, themeManager.currentTheme)

            let controller = NSHostingController(rootView: root)
            // Create already centered on the active screen to avoid any reposition jank
            // Match the empty state ideal height for proper centering
            let defaultSize = NSSize(width: 720, height: 550)
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let initialRect: NSRect
            if let s = screen {
                initialRect = centeredRect(size: defaultSize, on: s)
            } else {
                initialRect = NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height)
            }
            let win = NSPanel(
                contentRect: initialRect,
                styleMask: [.titled, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            // Enable glass-style translucency
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = true
            win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true
            win.standardWindowButton(.closeButton)?.isHidden = true
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = false
            let chatConfig = ChatConfigurationStore.load()
            win.level = chatConfig.alwaysOnTop ? .floating : .normal
            if chatConfig.alwaysOnTop {
                win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
            win.contentViewController = controller
            win.delegate = self
            win.animationBehavior = .none
            chatWindow = win
            // Pre-layout before showing to avoid initial jank
            controller.view.layoutSubtreeIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
            chatWindow?.makeKeyAndOrderFront(nil)
            Task { @MainActor in
                NotificationCenter.default.post(name: .chatOverlayActivated, object: nil)
            }
            return
        }

        guard let win = chatWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        if win.isMiniaturized { win.deminiaturize(nil) }
        centerWindowOnActiveScreen(win)
        win.makeKeyAndOrderFront(nil)
        
        // Ensure grounding avatar/orb is visible in dashboard if it's the first time
        NotificationCenter.default.post(name: .chatOverlayActivated, object: nil)
    }

    @MainActor func closeChatOverlay() {
        chatWindow?.orderOut(nil)
    }

    @MainActor func applyChatWindowLevel() {
        guard let win = chatWindow else { return }
        let chatConfig = ChatConfigurationStore.load()
        win.level = chatConfig.alwaysOnTop ? .floating : .normal
    }
}

// MARK: - Chat Overlay Helpers
extension AppDelegate {
    fileprivate func centerWindowOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let s = screen else {
            window.center()
            return
        }
        // Use visibleFrame to avoid menu bar and dock overlap
        let vf = s.visibleFrame
        let size = window.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.midY - size.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    fileprivate func centeredRect(size: NSSize, on screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        return NSRect(origin: origin, size: size)
    }
}

extension Notification.Name {
    static let chatOverlayActivated = Notification.Name("chatOverlayActivated")
    static let toolsListChanged = Notification.Name("toolsListChanged")
    static let voiceInputReceived = Notification.Name("voiceInputReceived")
}

// MARK: Management Window
extension AppDelegate {
    @MainActor func showManagementWindow(
        initialTab: ManagementTab = .models,
        deeplinkModelId: String? = nil,
        deeplinkFile: String? = nil
    ) {
        let presentWindow: () -> Void = { [weak self] in
            guard let self = self else { return }

            let themeManager = ThemeManager.shared
            let root = ManagementView(
                initialTab: initialTab,
                deeplinkModelId: deeplinkModelId,
                deeplinkFile: deeplinkFile
            )
            .environmentObject(self.serverController)
            .environmentObject(self.updater)
            .environment(\.theme, themeManager.currentTheme)

            let hostingController = NSHostingController(rootView: root)

            if let window = self.managementWindow {
                window.contentViewController = hostingController
                if window.isMiniaturized { window.deminiaturize(nil) }
                NSApp.activate(ignoringOtherApps: true)
                self.centerWindowOnActiveScreen(window)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSLog("[Management] Reused existing window and brought to front")
                return
            }

            // Calculate centered position on active screen before creating window
            let defaultSize = NSSize(width: 900, height: 640)
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let initialRect: NSRect
            if let s = screen {
                initialRect = self.centeredRect(size: defaultSize, on: s)
            } else {
                initialRect = NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height)
            }

            let window = NSWindow(
                contentRect: initialRect,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.contentViewController = hostingController
            window.delegate = self
            window.isReleasedWhenClosed = false
            self.managementWindow = window

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSLog("[Management] Created new window and presented")
        }

        if let pop = popover, pop.isShown {
            pop.performClose(nil)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                presentWindow()
            }
        } else {
            presentWindow()
        }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        if win == managementWindow { managementWindow = nil }
        if win == wizardWindow { wizardWindow = nil }
    }
    
    // MARK: - Semantic Memory Configuration
    
    /// Configure semantic memory AFTER providers are connected (fixes timing race condition)
    private func configureSemanticMemoryFromConnectedProviders() async {
        // Check connected providers (not just disk config)
        let connectedStates = RemoteProviderManager.shared.providerStates.values.filter { $0.isConnected }
        
        NSLog("🧠 [Core] Found \(connectedStates.count) CONNECTED providers (timing fix applied)")
        
        // First pass: Look for OpenAI provider specifically
        for state in connectedStates {
            guard let provider = RemoteProviderManager.shared.configuration.provider(id: state.providerId),
                  let apiKey = RemoteProviderKeychain.getAPIKey(for: provider.id), !apiKey.isEmpty else { continue }
            
            let urlString = provider.baseURL?.absoluteString ?? ""
            NSLog("🧠 [Core] Checking connected provider: \(provider.name), URL: \(urlString)")
            
            if urlString.contains("openai.com") || provider.name.lowercased().contains("openai") {
                AutoEmbeddingService.shared.configure(openAIKey: apiKey)
                NSLog("🧠 [Core] ✅ Semantic memory configured with OpenAI provider: \(provider.name)")
                return
            }
        }
        
        // Second pass: Fallback to any provider with API key
        if !AutoEmbeddingService.shared.isConfigured {
            NSLog("🧠 [Core] No OpenAI provider found, trying fallback...")
            for state in connectedStates {
                guard let provider = RemoteProviderManager.shared.configuration.provider(id: state.providerId),
                      let apiKey = RemoteProviderKeychain.getAPIKey(for: provider.id), !apiKey.isEmpty else { continue }
                
                AutoEmbeddingService.shared.configure(openAIKey: apiKey)
                NSLog("🧠 [Core] ✅ Semantic memory configured with fallback provider: \(provider.name)")
                return
            }
        }
        
        // No providers available
        if !AutoEmbeddingService.shared.isConfigured {
            NSLog("🧠 [Core] ⚠️ Semantic memory NOT configured - no connected providers with API keys")
            NSLog("🧠 [Core] Add an OpenAI provider in Settings → Providers to enable semantic memory")
        }
    }
    
    // MARK: - First-Run Wizard
    
    private func showFirstRunWizard() {
        guard wizardWindow == nil else { return }
        
        let wizardView = FirstRunWizardView()
            .environmentObject(serverController)
        
        let hostingController = NSHostingController(rootView: wizardView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to BrainOS"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.delegate = self
        
        wizardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
