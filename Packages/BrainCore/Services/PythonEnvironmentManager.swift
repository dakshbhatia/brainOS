//
//  PythonEnvironmentManager.swift
//  BrainCore
//
//  Manages Python virtual environment for voice sidecar services
//

import Foundation

/// Manages Python virtual environment setup and dependency installation
public actor PythonEnvironmentManager {
    public static let shared = PythonEnvironmentManager()
    
    private let venvPath: String
    private let pythonPath: String
    private let pipPath: String
    private let voiceScriptPath: String
    
    private init() {
        // Use home directory for venv
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.venvPath = "\(homeDir)/.brainos_voice_venv"
        self.pythonPath = "\(venvPath)/bin/python3"
        self.pipPath = "\(venvPath)/bin/pip3"
        
        // Voice server script path
        let workspaceRoot = Self.findWorkspaceRoot()
        self.voiceScriptPath = "\(workspaceRoot)/scripts/voice_server.py"
    }
    
    /// Find BrainOS workspace root directory
    private nonisolated static func findWorkspaceRoot() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDir)/BrainOS",
            "/Users/dakshbhatia/BrainOS",
            Bundle.main.bundlePath.components(separatedBy: "/BrainOS").first ?? ""
        ]
        
        for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        
        NSLog("⚠️ PythonEnv: Could not find workspace root, using home directory")
        return homeDir
    }
    
    /// Ensure Python virtual environment exists and is ready
    public func ensureVoiceEnvironment() async -> Bool {
        NSLog("🐍 PythonEnv: Checking voice environment at \(venvPath)")
        
        // Check if venv already exists
        if FileManager.default.fileExists(atPath: pythonPath) {
            NSLog("✅ PythonEnv: Virtual environment already exists")
            return true
        }
        
        // Create new venv
        NSLog("🐍 PythonEnv: Creating virtual environment...")
        let success = await createVirtualEnvironment()
        
        if success {
            NSLog("✅ PythonEnv: Virtual environment created successfully")
        } else {
            NSLog("❌ PythonEnv: Failed to create virtual environment")
        }
        
        return success
    }
    
    /// Create Python virtual environment
    private func createVirtualEnvironment() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "venv", venvPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if process.terminationStatus != 0 {
                NSLog("❌ PythonEnv: venv creation failed: \(output)")
                return false
            }
            
            return true
        } catch {
            NSLog("❌ PythonEnv: Failed to run python3: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Install voice dependencies in virtual environment
    public func installVoiceDependencies() async -> Bool {
        NSLog("📦 PythonEnv: Installing voice dependencies...")
        
        // Dependencies needed for voice services
        let dependencies = [
            "fastapi>=0.104.0",
            "uvicorn[standard]>=0.24.0",
            "pydantic>=2.5.0",
            "numpy>=1.24.0",
            "soundfile>=0.12.0",
            "resampy>=0.4.2",
            "openai-whisper>=20231117"  // For STT (speech-to-text)
        ]
        
        // Check if already installed
        let alreadyInstalled = await checkDependenciesInstalled(dependencies)
        if alreadyInstalled {
            NSLog("✅ PythonEnv: Dependencies already installed")
            return true
        }
        
        // Install using pip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pipPath)
        process.arguments = ["install", "--upgrade"] + dependencies
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            // Don't wait indefinitely - timeout after 5 minutes
            let startTime = Date()
            while process.isRunning {
                try await Task.sleep(for: .seconds(1))
                if Date().timeIntervalSince(startTime) > 300 {
                    NSLog("⚠️ PythonEnv: Installation taking too long, continuing...")
                    process.terminate()
                    break
                }
            }
            
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if process.terminationStatus != 0 {
                NSLog("❌ PythonEnv: Dependency installation failed: \(output)")
                return false
            }
            
            NSLog("✅ PythonEnv: Dependencies installed successfully")
            return true
        } catch {
            NSLog("❌ PythonEnv: Failed to install dependencies: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Pre-download Whisper model in background (non-blocking)
    /// Call this when user first triggers voice recognition to warm the cache
    public func preloadWhisperModel() async -> Bool {
        NSLog("🎤 PythonEnv: Warming Whisper model cache (will download ~140MB if needed)...")
        
        let loadScript = """
        import whisper
        import sys
        try:
            model = whisper.load_model('base')
            print('Whisper model ready')
            sys.exit(0)
        except Exception as e:
            print(f'Whisper load error: {e}')
            sys.exit(1)
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", loadScript]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            // Wait with shorter timeout (30s - if not cached yet, let it continue in background)
            let startTime = Date()
            while process.isRunning {
                try await Task.sleep(for: .seconds(1))
                if Date().timeIntervalSince(startTime) > 30 {
                    NSLog("ℹ️  PythonEnv: Whisper warming continues in background (first download takes 1-2 min)")
                    // Process continues, but we return to avoid blocking
                    return true
                }
            }
            
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                NSLog("✅ PythonEnv: Whisper model cached and ready")
                return true
            } else {
                NSLog("⚠️ PythonEnv: Whisper warming issue (will retry on use): \(output)")
                return false
            }
        } catch {
            NSLog("⚠️ PythonEnv: Whisper warming error: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check if dependencies are already installed
    private func checkDependenciesInstalled(_ packages: [String]) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pipPath)
        process.arguments = ["list", "--format=freeze"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else { return false }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Check if all packages are present
            let installedPackages = output.lowercased()
            for package in packages {
                let packageName = package.components(separatedBy: ">=").first ?? package
                if !installedPackages.contains(packageName.lowercased()) {
                    return false
                }
            }
            
            return true
        } catch {
            return false
        }
    }
    
    /// Create basic voice server script if it doesn't exist
    public func ensureVoiceScript() async -> Bool {
        // Check if voice_server.py already exists
        if FileManager.default.fileExists(atPath: voiceScriptPath) {
            NSLog("✅ PythonEnv: Voice server script exists")
            return true
        }
        
        NSLog("📝 PythonEnv: Creating voice server script...")
        
        // Create basic FastAPI server
        let scriptContent = """
        #!/usr/bin/env python3
        \"\"\"
        BrainOS Voice Server
        Provides TTS and STT services via FastAPI
        \"\"\"
        
        from fastapi import FastAPI, HTTPException
        from fastapi.responses import Response
        from pydantic import BaseModel
        import uvicorn
        
        app = FastAPI(title="BrainOS Voice Server")
        
        class TextToSpeechRequest(BaseModel):
            text: str
            voice: str = "default"
            speed: float = 1.0
        
        class SpeechToTextRequest(BaseModel):
            audio_data: str  # Base64 encoded
        
        @app.get("/health")
        async def health():
            return {"status": "healthy", "version": "1.0.0"}
        
        @app.post("/tts")
        async def text_to_speech(request: TextToSpeechRequest):
            # TODO: Implement actual TTS (piper-tts, coqui, or system voice)
            return {"audio_data": "", "format": "wav", "sample_rate": 22050}
        
        @app.post("/stt")
        async def speech_to_text(request: SpeechToTextRequest):
            # TODO: Implement actual STT (whisper.cpp or similar)
            return {"text": "", "confidence": 0.0}
        
        if __name__ == "__main__":
            uvicorn.run(app, host="127.0.0.1", port=8001, log_level="info")
        
        """
        
        do {
            // Ensure scripts directory exists
            let scriptsDir = (voiceScriptPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: scriptsDir, withIntermediateDirectories: true)
            
            // Write script
            try scriptContent.write(toFile: voiceScriptPath, atomically: true, encoding: .utf8)
            
            // Make executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: voiceScriptPath
            )
            
            NSLog("✅ PythonEnv: Voice server script created")
            return true
        } catch {
            NSLog("❌ PythonEnv: Failed to create voice script: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get full setup status
    public func getSetupStatus() async -> VoiceEnvironmentStatus {
        let venvExists = FileManager.default.fileExists(atPath: pythonPath)
        let scriptExists = FileManager.default.fileExists(atPath: voiceScriptPath)
        let depsInstalled = await checkDependenciesInstalled([
            "fastapi", "uvicorn", "pydantic"
        ])
        
        return VoiceEnvironmentStatus(
            venvExists: venvExists,
            scriptExists: scriptExists,
            dependenciesInstalled: depsInstalled,
            pythonPath: pythonPath,
            scriptPath: voiceScriptPath
        )
    }
    
    /// Complete voice environment setup
    public func setupCompleteEnvironment() async -> Bool {
        NSLog("🚀 PythonEnv: Starting complete voice environment setup...")
        
        // Step 1: Create venv
        guard await ensureVoiceEnvironment() else {
            NSLog("❌ PythonEnv: Failed at venv creation")
            return false
        }
        
        // Step 2: Install dependencies
        guard await installVoiceDependencies() else {
            NSLog("❌ PythonEnv: Failed at dependency installation")
            return false
        }
        
        // Step 3: Create voice script
        guard await ensureVoiceScript() else {
            NSLog("❌ PythonEnv: Failed at script creation")
            return false
        }
        
        NSLog("✅ PythonEnv: Complete voice environment setup successful")
        NSLog("ℹ️  PythonEnv: Whisper model will download on first use (prevents startup delay)")
        return true
    }
}

/// Voice environment setup status
public struct VoiceEnvironmentStatus: Sendable {
    public let venvExists: Bool
    public let scriptExists: Bool
    public let dependenciesInstalled: Bool
    public let pythonPath: String
    public let scriptPath: String
    
    public var isReady: Bool {
        venvExists && scriptExists && dependenciesInstalled
    }
}
