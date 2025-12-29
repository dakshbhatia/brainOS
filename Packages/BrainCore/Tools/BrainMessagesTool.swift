import Foundation

struct BrainMessagesTool: BrainOSTool {
    let name = "get_recent_messages"
    let description = "Retrieve recent messages from a specific contact or all contacts."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "contactName": .object([
                    "type": .string("string"),
                    "description": .string("Optional contact name to filter by.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Number of messages to retrieve (default 20).")
                ])
            ]),
            "required": .array([])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        let decoder = JSONDecoder()
        let args = try? decoder.decode(Arguments.self, from: argumentsJSON.data(using: .utf8) ?? Data())
        
        let limit = args?.limit ?? 20
        let contactName = args?.contactName
        
        do {
            let messages = try await BrainMessagesManager.shared.fetchRecentMessages(
                limit: limit, contactName: contactName)
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(messages)
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            // NEVER return fake data - causes AI hallucinations
            let errorMessage = """
            ⚠️ Cannot access message database. Error: \(error.localizedDescription)
            
            This tool requires Full Disk Access permission:
            1. Go to System Settings → Privacy & Security → Full Disk Access
            2. Add BrainOS to the allowed apps
            3. Restart BrainOS
            
            Alternative: Use the 'search_messages_semantic' tool which works with chat history instead.
            """
            return errorMessage
        }
    }
    
    struct Arguments: Decodable {
        let contactName: String?
        let limit: Int?
    }
}
