//
//  SpeechRecognizer.swift
//  BrainOS
//
//  Native macOS speech recognition using Speech framework
//

import Foundation
import Speech
import AVFoundation

/// Native macOS speech-to-text using Apple's Speech framework
@MainActor
public class SpeechRecognizer: ObservableObject {
    public static let shared = SpeechRecognizer()
    
    @Published public private(set) var isAvailable = false
    @Published public private(set) var isListening = false
    @Published public private(set) var currentTranscript = ""
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    private var completionHandler: ((Result<String, Error>) -> Void)?
    
    private init() {
        setupSpeechRecognizer()
    }
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    self?.isAvailable = true
                    BrainLogger.info("Speech recognition authorized", category: .core)
                case .denied:
                    self?.isAvailable = false
                    BrainLogger.info("Speech recognition denied", category: .core)
                case .restricted:
                    self?.isAvailable = false
                    BrainLogger.info("Speech recognition restricted", category: .core)
                case .notDetermined:
                    self?.isAvailable = false
                    BrainLogger.info("Speech recognition not determined", category: .core)
                @unknown default:
                    self?.isAvailable = false
                }
            }
        }
    }
    
    /// Start listening for speech input
    public func startListening(completion: @escaping (Result<String, Error>) -> Void) {
        guard isAvailable, !isListening else {
            if !isAvailable {
                completion(.failure(SpeechError.notAuthorized))
            }
            return
        }
        
        self.completionHandler = completion
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            completion(.failure(SpeechError.audioEngineError))
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            completion(.failure(SpeechError.requestCreationFailed))
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        guard let speechRecognizer = speechRecognizer else {
            completion(.failure(SpeechError.recognizerNotAvailable))
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    self.currentTranscript = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        self.stopListening()
                        self.completionHandler?(.success(self.currentTranscript))
                    }
                }
                
                if let error = error {
                    self.stopListening()
                    self.completionHandler?(.failure(error))
                }
            }
        }
        
        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            currentTranscript = ""
            BrainLogger.info("Speech recognition started", category: .core)
        } catch {
            stopListening()
            completion(.failure(error))
        }
    }
    
    /// Stop listening and finalize transcription
    public func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        audioEngine = nil
        isListening = false
        
        // If we have a transcript but task didn't finish, return it
        if !currentTranscript.isEmpty {
            completionHandler?(.success(currentTranscript))
        }
        
        BrainLogger.info("Speech recognition stopped", category: .core)
    }
}

// MARK: - Errors

public enum SpeechError: Error, LocalizedError {
    case notAuthorized
    case audioEngineError
    case requestCreationFailed
    case recognizerNotAvailable
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Enable in System Settings > Privacy > Speech Recognition"
        case .audioEngineError:
            return "Failed to initialize audio engine"
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        case .recognizerNotAvailable:
            return "Speech recognizer not available"
        }
    }
}
