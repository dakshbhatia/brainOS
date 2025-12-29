import Foundation
import AppKit
import AVFoundation

/// Manages the Chatterbox Python sidecar and provides TTS/STT capabilities.
@MainActor
public class VoiceService: ObservableObject {
    public static let shared = VoiceService()
    
    private var process: Process?
    @Published public private(set) var isReady = false
    @Published public private(set) var ttsAvailable = false
    @Published public private(set) var sttAvailable = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var isTranscribing = false
    
    // Audio recording
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
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
        ttsAvailable = false
        sttAvailable = false
    }
    
    private func waitForReady() async {
        let url = URL(string: "http://127.0.0.1:8001/health")!
        var attemptCount = 0
        let maxAttempts = 10 // Reduced from 30 to avoid spam
        
        for attempt in 0..<maxAttempts {
            attemptCount = attempt + 1
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String, status == "ok" {
                    self.isReady = true
                    self.ttsAvailable = (json["tts_loaded"] as? Bool) ?? false
                    self.sttAvailable = (json["stt_loaded"] as? Bool) ?? false
                    BrainLogger.info("Voice Sidecar ready - TTS: \(ttsAvailable), STT: \(sttAvailable)", category: .core)
                    return
                }
            } catch {
                // Only log every 5th attempt to reduce spam
                if attemptCount % 5 == 0 {
                    BrainLogger.info("Voice Sidecar not ready yet (attempt \(attemptCount)/\(maxAttempts))...", category: .core)
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        BrainLogger.info("Voice Sidecar failed to become ready after \(maxAttempts) attempts. Voice features disabled.", category: .core)
    }
    
    // MARK: - TTS (Text-to-Speech)
    
    public func speak(_ text: String, voiceId: String = "default") async {
        guard isReady else {
            BrainLogger.info("Voice Service not ready, skipping speech", category: .core)
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
    
    // MARK: - STT (Speech-to-Text)
    
    /// Start recording audio for transcription
    public func startRecording() throws {
        guard !isRecording else { return }
        
        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("brain_recording_\(UUID().uuidString).wav")
        
        guard let recordingURL = recordingURL else {
            throw VoiceError.recordingFailed("Could not create recording URL")
        }
        
        // Configure recording settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            BrainLogger.info("Started recording for STT", category: .core)
        } catch {
            throw VoiceError.recordingFailed(error.localizedDescription)
        }
    }
    
    /// Stop recording and transcribe the audio
    public func stopRecordingAndTranscribe(language: String? = nil) async throws -> String {
        guard isRecording, let audioRecorder = audioRecorder, let recordingURL = recordingURL else {
            throw VoiceError.notRecording
        }
        
        audioRecorder.stop()
        isRecording = false
        self.audioRecorder = nil
        
        defer {
            // Clean up recording file
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }
        
        return try await transcribe(audioURL: recordingURL, language: language)
    }
    
    /// Transcribe an audio file
    public func transcribe(audioURL: URL, language: String? = nil) async throws -> String {
        guard isReady, sttAvailable else {
            throw VoiceError.sttNotAvailable
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        let url = URL(string: "http://127.0.0.1:8001/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file
        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add language if specified
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw VoiceError.transcriptionFailed(errorMessage)
            }
            
            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                BrainLogger.info("Transcription complete: \(text.prefix(50))...", category: .core)
                return text
            } else {
                throw VoiceError.transcriptionFailed("Invalid response format")
            }
        } catch let error as VoiceError {
            throw error
        } catch {
            throw VoiceError.transcriptionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Errors

public enum VoiceError: Error, LocalizedError {
    case sttNotAvailable
    case notRecording
    case recordingFailed(String)
    case transcriptionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .sttNotAvailable:
            return "Speech-to-text is not available. Install whisper: pip install openai-whisper"
        case .notRecording:
            return "Not currently recording"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
