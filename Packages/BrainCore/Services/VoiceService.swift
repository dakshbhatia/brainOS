import Foundation
import AppKit

/// Manages the Chatterbox Python sidecar and provides TTS capabilities.
@MainActor
public class VoiceService: ObservableObject {
    public static let shared = VoiceService()
    
    private var process: Process?
    @Published public private(set) var isReady = false
    
    private init() {}
    
    public func start() {
        guard process == nil else { return }
        
        BrainLogger.info("Starting Voice Sidecar...", category: .core)
        
        let process = Process()
        let pythonPath = "/Users/dakshbhatia/BrainOS/.venv/bin/python" // Use the workspace venv
        let scriptPath = "/Users/dakshbhatia/BrainOS/scripts/voice_server.py"
        
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        process.environment = ["VOICE_PORT": "8001"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            self.process = process
            
            // Wait for health check
            Task {
                await waitForReady()
            }
        } catch {
            BrainLogger.error("Failed to start Voice Sidecar: \(error)", category: .core)
        }
    }
    
    public func stop() {
        process?.terminate()
        process = nil
        isReady = false
    }
    
    private func waitForReady() async {
        let url = URL(string: "http://127.0.0.1:8001/health")!
        for _ in 0..<30 { // Try for 30 seconds
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String, status == "ok" {
                    self.isReady = true
                    BrainLogger.info("Voice Sidecar is ready", category: .core)
                    return
                }
            } catch {
                // Wait and retry
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        BrainLogger.error("Voice Sidecar failed to become ready", category: .core)
    }
    
    public func speak(_ text: String, voiceId: String = "default") async {
        guard isReady else {
            BrainLogger.warn("Voice Service not ready, skipping speech", category: .core)
            return
        }
        
        let url = URL(string: "http://127.0.0.1:8001/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "text": text,
            "voice_id": voiceId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            // Play the audio data
            AudioStreamPlayer.shared.play(data: data)
        } catch {
            BrainLogger.error("Speech generation failed: \(error)", category: .core)
        }
    }
}
