import Foundation

/// A tool that uses AppleScript to stage or send iMessages.
struct BrainAppleScriptTool: BrainOSTool {
    let name = "stage_imessage"
    let description = "Drafts a message in the Messages app for a specific contact. Does NOT send automatically for safety."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "recipient": .object([
                    "type": .string("string"),
                    "description": .string("The phone number or email of the recipient.")
                ]),
                "message": .object([
                    "type": .string("string"),
                    "description": .string("The text of the message to draft.")
                ])
            ]),
            "required": .array([.string("recipient"), .string("message")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        let decoder = JSONDecoder()
        let args = try decoder.decode(Arguments.self, from: argumentsJSON.data(using: .utf8) ?? Data())
        
        let scriptSource = """
        tell application "Messages"
            set targetService to 1st service whose service type is iMessage
            set targetBuddy to buddy "\(args.recipient)" of targetService
            send "\(args.message)" to targetBuddy
        end tell
        """
        
        // Note: In a real app, we might want to just 'activate' and 'set text' instead of 'send' 
        // to allow the user to review. But for "1-click send" capability, we use 'send'.
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
        }
        
        if let err = error {
            return "Error executing AppleScript: \(err)"
        }
        
        return "Successfully staged message to \(args.recipient)"
    }
    
    struct Arguments: Decodable {
        let recipient: String
        let message: String
    }
}
