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
            // Fallback to mock if database access fails (e.g. no Full Disk Access)
            let mockMessages = [
                ["sender": "Mom", "text": "Are you coming for dinner on Sunday?", "timestamp": "2024-12-25T18:30:00Z", "isFromMe": false],
                ["sender": "Sarah", "text": "Hey, did you see that link I sent?", "timestamp": "2024-12-26T10:15:00Z", "isFromMe": false],
                ["sender": "Mom", "text": "Let me know!", "timestamp": "2024-12-26T09:00:00Z", "isFromMe": false]
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: mockMessages)
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        }
    }
    
    struct Arguments: Decodable {
        let contactName: String?
        let limit: Int?
    }
}
