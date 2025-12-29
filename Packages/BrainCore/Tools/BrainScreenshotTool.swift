import Foundation

struct BrainScreenshotTool: BrainOSTool {
    let name = "search_screenshots"
    let description = "Search through your visual memory (screenshots) for text or visual elements."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Text or visual description to search for.")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        // Check if vision model is available
        let hasVisionModel = await BrainVisionManager.shared.isAvailable()
        let modelId = await BrainVisionManager.shared.currentModelId()
        
        // Mock screenshot search (TODO: implement actual search)
        var result = "Found 2 screenshots matching '\(argumentsJSON)'. 1. Receipt from Amazon (2024-12-20), 2. Code snippet for MLX (2024-12-21)."
        
        if !hasVisionModel {
            result += "\n\n⚠️ Note: Vision analysis is currently unavailable. Screenshots are indexed by OCR text only. To enable visual understanding, download a vision model like 'Qwen3-VL-4B' from the Model Manager."
        } else if let modelId = modelId {
            result += "\n\nℹ️ Using vision model: \(modelId)"
        }
        
        return result
    }
}
