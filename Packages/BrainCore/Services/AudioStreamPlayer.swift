import Foundation
import AVFoundation

/// Native audio player for streaming PCM/WAV data.
@MainActor
public class AudioStreamPlayer: NSObject {
    public static let shared = AudioStreamPlayer()
    
    private var audioPlayer: AVAudioPlayer?
    
    private override init() {
        super.init()
    }
    
    public func play(data: Data) {
        do {
            // For now, use AVAudioPlayer for the full buffer.
            // Future: Use AVAudioEngine and AVAudioSourceNode for real-time streaming.
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            BrainLogger.error("Failed to play audio: \(error)", category: .core)
        }
    }
    
    public func stop() {
        audioPlayer?.stop()
    }
}
