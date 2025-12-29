//
//  MLXGenerationEngine.swift
//  BrainOS
//
//  Encapsulates MLX message preparation and generation stream construction.
//

import Foundation
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon

// MARK: - Sendable Wrapper for UserInput

/// Box to carry UserInput (which contains non-Sendable tools) across isolation boundaries.
/// Marked @unchecked Sendable because UserInput is immutable after construction.
final class SendableUserInputBox: @unchecked Sendable {
    let input: MLXLMCommon.UserInput
    
    nonisolated init(chat: [MLXLMCommon.Chat.Message], tools: [[String: Any]]?) {
        self.input = MLXLMCommon.UserInput(chat: chat, processing: .init(), tools: tools)
    }
}

// MARK: - Generation Engine

struct MLXGenerationEngine {
    
    /// Prepares chat + tools and starts MLX generation
    @MainActor
    static func prepareAndGenerate(
        container: ModelContainer,
        buildChat: @Sendable () -> [MLXLMCommon.Chat.Message],
        buildToolsSpec: @escaping () -> [[String: Any]]?,
        generation: GenerationParameters,
        runtime: RuntimeConfig
    ) async throws -> AsyncStream<MLXLMCommon.Generation> {
        // Build UserInput in nonisolated context via the box's init
        let chat = buildChat()
        let tools = buildToolsSpec()
        let inputBox = SendableUserInputBox(chat: chat, tools: tools)
        
        let stream: AsyncStream<MLXLMCommon.Generation> = try await container.perform { context in
            let parameters = ModelRuntime.makeGenerateParameters(
                temperature: generation.temperature ?? 0.7,
                maxTokens: generation.maxTokens,
                topP: generation.topPOverride ?? runtime.topP,
                repetitionPenalty: generation.repetitionPenalty,
                kvBits: runtime.kvBits,
                kvGroup: runtime.kvGroup,
                quantStart: runtime.quantStart,
                maxKV: runtime.maxKV,
                prefillStep: runtime.prefillStep
            )
            
            // Extract pre-built input from Sendable box
            let fullLMInput = try await context.processor.prepare(input: inputBox.input)

            var contextWithEOS = context
            let existing = context.configuration.extraEOSTokens
            let extra: Set<String> = Set(["</end_of_turn>", "<end_of_turn>", "<|end|>", "<eot>"])
            contextWithEOS.configuration.extraEOSTokens = existing.union(extra)

            return try MLXLMCommon.generate(
                input: fullLMInput,
                cache: nil,
                parameters: parameters,
                context: contextWithEOS
            )
        }
        return stream
    }
}
