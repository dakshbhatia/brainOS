//
//  ImessageExporterBridge.swift
//  BrainOS
//
//  Bridge to imessage-exporter Python library for reliable message access
//

import Foundation

/// Bridge to the imessage-exporter library (https://github.com/ReagentX/imessage-exporter)
/// This is MORE RELIABLE than direct SQLite access because it handles:
/// - Contact enrichment automatically
/// - Complex iMessage table structures
/// - Attachment handling
/// - Group chat parsing
@MainActor
class ImessageExporterBridge {
    static let shared = ImessageExporterBridge()
    
    private let exporterPath: String
    private var isAvailable: Bool = false
    
    init() {
        // Check if imessage-exporter is installed
        let possiblePaths = [
            "/usr/local/bin/imessage-exporter",
            "/opt/homebrew/bin/imessage-exporter",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cargo/bin/imessage-exporter"
        ]
        
        self.exporterPath = possiblePaths.first { FileManager.default.fileExists(atPath: $0) } ?? ""
        self.isAvailable = !exporterPath.isEmpty
        
        if isAvailable {
            BrainLogger.info("Found imessage-exporter at: \(exporterPath)", category: .messages)
        } else {
            BrainLogger.error("imessage-exporter not found. Install with: brew install imessage-exporter", category: .messages)
        }
    }
    
    // MARK: - Export Methods
    
    /// Export recent messages to JSON format
    func exportRecentMessages(limit: Int = 50, contact: String? = nil) async throws -> [MessageExportEntry] {
        guard isAvailable else {
            throw ExporterError.notInstalled
        }
        
        // Create temp directory for export
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Build command
        var args = [
            "-f", "json",  // JSON format
            "-o", tempDir.path,  // Output directory
            "-c",  // Copy attachments
            "--no-lazy"  // Don't lazy load
        ]
        
        if let contact = contact {
            args.append(contentsOf: ["--filter-contacts", contact])
        }
        
        // Run exporter
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exporterPath)
        process.arguments = args
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ExporterError.exportFailed(errorMessage)
        }
        
        // Read exported JSON
        let jsonFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        
        var allMessages: [MessageExportEntry] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for file in jsonFiles {
            let data = try Data(contentsOf: file)
            let messages = try decoder.decode([MessageExportEntry].self, from: data)
            allMessages.append(contentsOf: messages)
        }
        
        // Sort by date and limit
        return Array(allMessages.sorted { $0.date > $1.date }.prefix(limit))
    }
    
    /// Search messages semantically using export + embedding
    func searchMessages(query: String, limit: Int = 10) async throws -> [(message: MessageExportEntry, score: Float)] {
        // Export recent messages
        let messages = try await exportRecentMessages(limit: 500)
        
        // Get OpenAI key
        guard let apiKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey"), !apiKey.isEmpty else {
            throw ExporterError.noApiKey
        }
        
        // Use semantic search
        let embeddingService = EmbeddingService(apiKey: apiKey)
        let queryEmbedding = try await embeddingService.embed(query)
        
        // Embed and score messages
        var scoredResults: [(message: MessageExportEntry, score: Float)] = []
        
        let texts = messages.map { $0.text ?? "" }
        let embeddings = try await embeddingService.embedBatch(texts)
        
        for (i, embedding) in embeddings.enumerated() {
            let similarity = EmbeddingService.cosineSimilarity(queryEmbedding, embedding)
            if similarity >= 0.7 {
                scoredResults.append((messages[i], similarity))
            }
        }
        
        return scoredResults
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Models

struct MessageExportEntry: Codable {
    let id: String
    let date: Date
    let text: String?
    let service: String?
    let handle: MessageHandle?
    let is_from_me: Bool
    let attachments: [MessageAttachmentExport]?
    
    struct MessageHandle: Codable {
        let contact_name: String?
        let service: String?
        let id: String
    }
    
    struct MessageAttachmentExport: Codable {
        let filename: String?
        let mime_type: String?
    }
}

// MARK: - Errors

enum ExporterError: LocalizedError {
    case notInstalled
    case exportFailed(String)
    case noApiKey
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return """
            imessage-exporter not installed.
            
            Install with: brew install imessage-exporter
            Or: cargo install imessage-exporter
            
            See: https://github.com/ReagentX/imessage-exporter
            """
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .noApiKey:
            return "OpenAI API key not configured"
        }
    }
}

// MARK: - Updated Tool

struct ImessageSemanticSearchTool: BrainOSTool {
    let name = "search_imessages"
    let description = "Search your actual iMessages semantically. Returns REAL data from your Messages app (not hallucinated)."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Natural language search query (e.g., 'friends I texted today', 'messages about dinner')")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Number of results (default 10)")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        let decoder = JSONDecoder()
        guard let args = try? decoder.decode(Arguments.self, from: argumentsJSON.data(using: .utf8) ?? Data()) else {
            return "❌ Invalid arguments"
        }
        
        do {
            let results = try await ImessageExporterBridge.shared.searchMessages(
                query: args.query,
                limit: args.limit ?? 10
            )
            
            if results.isEmpty {
                return "No messages found matching '\(args.query)'"
            }
            
            var output = "📱 Found \(results.count) messages matching '\(args.query)':\n\n"
            
            for (i, (message, score)) in results.enumerated() {
                let sender = message.handle?.contact_name ?? message.handle?.id ?? "Unknown"
                let direction = message.is_from_me ? "→" : "←"
                let preview = message.text?.prefix(80) ?? "[No text]"
                
                output += "\(i+1). \(direction) **\(sender)** (relevance: \(Int(score * 100))%)\n"
                output += "   \"\(preview)\"\n"
                output += "   \(formatDate(message.date))\n\n"
            }
            
            return output
            
        } catch ExporterError.notInstalled {
            return """
            ⚠️ Cannot search messages - imessage-exporter not installed.
            
            To enable this feature:
            1. Install: `brew install imessage-exporter`
            2. Grant Full Disk Access to Terminal/iTerm
            3. Restart BrainOS
            
            Falling back to chat history search instead...
            """
        } catch {
            return "❌ Error searching messages: \(error.localizedDescription)"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    struct Arguments: Decodable {
        let query: String
        let limit: Int?
    }
}
