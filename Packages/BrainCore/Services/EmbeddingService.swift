//
//  EmbeddingService.swift
//  BrainOS
//
//  Semantic embedding generation using OpenAI API
//

import Foundation

/// Service for generating text embeddings for semantic search
actor EmbeddingService {
    private let apiKey: String
    private let model: String
    private let baseURL: String
    
    init(
        apiKey: String,
        model: String = "text-embedding-3-small",
        baseURL: String = "https://api.openai.com/v1"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }
    
    // MARK: - Public API
    
    /// Generate embedding for a single text
    func embed(_ text: String) async throws -> [Float] {
        let results = try await embedBatch([text])
        guard let first = results.first else {
            throw EmbeddingError.emptyResponse
        }
        return first
    }
    
    /// Generate embeddings for multiple texts in one API call (more efficient)
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        
        let request = EmbeddingRequest(input: texts, model: model)
        let url = URL(string: "\(baseURL)/embeddings")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw EmbeddingError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        
        // Sort by index to maintain order
        let sortedData = embeddingResponse.data.sorted { $0.index < $1.index }
        return sortedData.map { $0.embedding }
    }
    
    // MARK: - Cosine Similarity
    
    /// Calculate cosine similarity between two embedding vectors (0.0 to 1.0)
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        
        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        
        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        guard magnitude > 0 else { return 0.0 }
        
        return dotProduct / magnitude
    }
}

// MARK: - API Models

private struct EmbeddingRequest: Codable {
    let input: [String]
    let model: String
    let encoding_format: String = "float"
}

private struct EmbeddingResponse: Codable {
    let data: [EmbeddingData]
    let model: String
    let usage: EmbeddingUsage
}

private struct EmbeddingData: Codable {
    let embedding: [Float]
    let index: Int
}

private struct EmbeddingUsage: Codable {
    let prompt_tokens: Int
    let total_tokens: Int
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
    case emptyResponse
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Embedding service returned no data"
        case .invalidResponse:
            return "Invalid response from embedding service"
        case .apiError(let statusCode, let message):
            return "Embedding API error (\(statusCode)): \(message)"
        }
    }
}
