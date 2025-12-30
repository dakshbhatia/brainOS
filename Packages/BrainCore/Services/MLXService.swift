//
//  MLXService.swift
//  BrainOS
//
//  Migrated to Swift 6 actors; delegates runtime state to ModelManager/ModelRuntime.
//

import Foundation

/// Lightweight reference to a local MLX model (name + repo id)
private struct LocalModelRef {
    let name: String
    let modelId: String
}

actor MLXService: ToolCapableService {

    nonisolated var id: String { "mlx" }

    // MARK: - Availability / Routing

    nonisolated func isAvailable() -> Bool {
        return !Self.getAvailableModels().isEmpty
    }

    nonisolated func handles(requestedModel: String?) -> Bool {
        let trimmed = (requestedModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased() == "default" {
            return !Self.getAvailableModels().isEmpty
        }
        return Self.findModel(named: trimmed) != nil
    }

    // MARK: - Static discovery wrappers (delegate to ModelManager)

    nonisolated static func getAvailableModels() -> [String] {
        return ModelManager.installedModelNames()
    }

    fileprivate nonisolated static func findModel(named name: String) -> LocalModelRef? {
        if let found = ModelManager.findInstalledModel(named: name) {
            return LocalModelRef(name: found.name, modelId: found.id)
        }
        return nil
    }

    // MARK: - Warm-up

    func warmUp(modelName: String? = nil, prefillChars: Int = 0, maxTokens: Int = 1) async {
        let chosen: LocalModelRef? = {
            if let name = modelName, let m = Self.findModel(named: name) { return m }
            if let first = Self.getAvailableModels().first, let m = Self.findModel(named: first) {
                return m
            }
            return nil
        }()
        guard let model = chosen else { return }
        await ModelRuntime.shared.warmUp(
            modelId: model.modelId,
            modelName: model.name,
            prefillChars: prefillChars,
            maxTokens: maxTokens
        )
    }

    // MARK: - ModelService

    func streamDeltas(
        messages: [ChatMessage],
        parameters: GenerationParameters,
        requestedModel: String?,
        stopSequences: [String]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let model = try selectModel(requestedName: requestedModel)
        return try await ModelRuntime.shared.streamWithTools(
            messages: messages,
            parameters: parameters,
            stopSequences: stopSequences,
            tools: [],
            toolChoice: nil,
            modelId: model.modelId,
            modelName: model.name
        )
    }

    func generateOneShot(
        messages: [ChatMessage],
        parameters: GenerationParameters,
        requestedModel: String?
    ) async throws -> String {
        let stream = try await streamDeltas(
            messages: messages,
            parameters: parameters,
            requestedModel: requestedModel,
            stopSequences: []
        )
        var out = ""
        for try await s in stream { out += s }
        return out
    }

    // MARK: - Message-based Tool-capable bridge

    func respondWithTools(
        messages: [ChatMessage],
        parameters: GenerationParameters,
        stopSequences: [String],
        tools: [Tool],
        toolChoice: ToolChoiceOption?,
        requestedModel: String?
    ) async throws -> String {
        let model = try selectModel(requestedName: requestedModel)
        return try await ModelRuntime.shared.respondWithTools(
            messages: messages,
            parameters: parameters,
            stopSequences: stopSequences,
            tools: tools,
            toolChoice: toolChoice,
            modelId: model.modelId,
            modelName: model.name
        )
    }

    func streamWithTools(
        messages: [ChatMessage],
        parameters: GenerationParameters,
        stopSequences: [String],
        tools: [Tool],
        toolChoice: ToolChoiceOption?,
        requestedModel: String?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let model = try selectModel(requestedName: requestedModel)
        return try await ModelRuntime.shared.streamWithTools(
            messages: messages,
            parameters: parameters,
            stopSequences: stopSequences,
            tools: tools,
            toolChoice: toolChoice,
            modelId: model.modelId,
            modelName: model.name
        )
    }

    // MARK: - Runtime cache management

    func cachedRuntimeSummaries() async -> [ModelRuntime.ModelCacheSummary] {
        await ModelRuntime.shared.cachedModelSummaries()
    }

    func unloadRuntimeModel(named name: String) async {
        await ModelRuntime.shared.unload(name: name)
    }

    func clearRuntimeCache() async {
        await ModelRuntime.shared.clearAll()
    }

    // MARK: - Helpers

    private func selectModel(requestedName: String?) throws -> LocalModelRef {
        let trimmed = (requestedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefault = trimmed.isEmpty || trimmed.lowercased() == "default"
        
        if isDefault {
            // Fallback: pick the first available installed model
            if let first = Self.getAvailableModels().first, let m = Self.findModel(named: first) {
                return m
            }
            throw NSError(
                domain: "MLXService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No MLX models installed. Please go to the Models tab in the Sidebar Hub to download recommended models like Gemma 3."]
            )
        }
        if let m = Self.findModel(named: trimmed) { return m }
        throw NSError(
            domain: "MLXService",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Requested model '\(trimmed)' not found locally. Ensure it's downloaded in the Models tab."]
        )
    }
}
