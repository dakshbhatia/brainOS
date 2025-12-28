import Foundation

struct BrainDraftTool: BrainOSTool {
    let name = "draft_message"
    let description = "Draft a message to a contact for user approval."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "contactName": .object([
                    "type": .string("string"),
                    "description": .string("The name of the contact.")
                ]),
                "message": .object([
                    "type": .string("string"),
                    "description": .string("The content of the message to draft.")
                ])
            ]),
            "required": .array([.string("contactName"), .string("message")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contact = args["contactName"] as? String,
              let message = args["message"] as? String else {
            throw NSError(domain: "BrainDraftTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"])
        }
        
        // In a real app, this would trigger a UI state change to show the draft
        // For now, we'll return a success message that the LLM can use.
        return "Drafted message to \(contact): \"\(message)\". Awaiting user approval."
    }
}
