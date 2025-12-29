import Foundation
import MLX
import MLXVLM
import MLXLMCommon
import Hub
import AppKit

/// Uses local VLM (Vision Language Model) to describe images and screenshots.
public actor BrainVisionManager {
    public static let shared = BrainVisionManager()
    
    private var container: ModelContainer?
    private var loadedModelId: String?
    
    private init() {}
    
    /// Check if any vision model is currently available/loaded
    public func isAvailable() -> Bool {
        return container != nil
    }
    
    /// Get the ID of the currently loaded vision model, if any
    public func currentModelId() -> String? {
        return loadedModelId
    }
    
    /// Find and return the first installed vision model, or nil if none found
    public func findInstalledVisionModel() -> String? {
        // Check the recommended vision model first
        let recommendedVisionModel = "mlx-community/Qwen3-VL-4B-Instruct-8bit"
        if ModelManager.isVisionModel(modelId: recommendedVisionModel),
           let dir = ModelManager.findLocalModelDirectory(forModelId: recommendedVisionModel),
           FileManager.default.fileExists(atPath: dir.path) {
            return recommendedVisionModel
        }
        
        // Fall back to checking other known vision models from curated list
        let knownVisionModels = [
            "mlx-community/Kimi-VL-A3B-Thinking-4bit",
            "mlx-community/Qwen2-VL-2B-Instruct",
        ]
        
        for modelId in knownVisionModels {
            if ModelManager.isVisionModel(modelId: modelId),
               let dir = ModelManager.findLocalModelDirectory(forModelId: modelId),
               FileManager.default.fileExists(atPath: dir.path) {
                return modelId
            }
        }
        
        return nil
    }
    
    public func loadModel() async {
        guard container == nil else { return }
        BrainLogger.info("Loading local Vision model...", category: .core)
        
        // Find an installed vision model
        guard let modelId = findInstalledVisionModel() else {
            BrainLogger.info("No vision model installed. Vision features disabled.", category: .core)
            return
        }
        
        guard let localDirectory = ModelManager.findLocalModelDirectory(forModelId: modelId) else {
            BrainLogger.error("Vision model directory not found: \(modelId)", category: .core)
            return
        }
        
        do {
            // Load the model using proper MLX API
            let configuration = ModelConfiguration(directory: localDirectory)
            let loadedContainer = try await VLMModelFactory.shared.loadContainer(configuration: configuration)
            
            self.container = loadedContainer
            self.loadedModelId = modelId
            
            BrainLogger.info("Vision model loaded successfully: \(modelId)", category: .core)
        } catch {
            BrainLogger.error("Failed to load VLM model: \(error)", category: .core)
        }
    }
    
    public func describeImage(at url: URL) async -> String {
        guard let image = NSImage(contentsOf: url) else { return "Failed to load image" }
        
        BrainLogger.info("Describing image at \(url.lastPathComponent)...", category: .core)
        
        guard let container = container else {
            return "Vision model not loaded"
        }
        
        // TODO: Implement actual VLM inference using container.perform
        // This would require:
        // 1. Converting NSImage to appropriate format
        // 2. Using container.perform to access ModelContext
        // 3. Preparing image input with processor
        // 4. Running inference with the VLM model
        
        // Placeholder for now
        let prompt = "Describe this image in detail."
        return "A screenshot or image containing visual information. [VLM inference not yet implemented]"
    }
}
