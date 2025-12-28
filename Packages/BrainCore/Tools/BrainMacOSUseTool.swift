import Foundation
import MacosUseSDK
import CoreGraphics

struct BrainMacOSUseTool: BrainOSTool {
    let name = "macos_use"
    let description = "Control macOS applications via accessibility APIs - click, type, press keys, and traverse UI elements."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("open"), .string("click"), .string("type"), .string("press"), .string("refresh")]),
                    "description": .string("The action to perform.")
                ]),
                "identifier": .object([
                    "type": .string("string"),
                    "description": .string("Application name or bundle ID (for 'open' action).")
                ]),
                "pid": .object([
                    "type": .string("integer"),
                    "description": .string("Process ID of the target application.")
                ]),
                "x": .object([
                    "type": .string("number"),
                    "description": .string("X coordinate for click.")
                ]),
                "y": .object([
                    "type": .string("number"),
                    "description": .string("Y coordinate for click.")
                ]),
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Text to type.")
                ]),
                "keyName": .object([
                    "type": .string("string"),
                    "description": .string("Key name to press (e.g., 'Return', 'Escape').")
                ])
            ]),
            "required": .array([.string("action")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionStr = args["action"] as? String else {
            throw NSError(domain: "BrainMacOSUseTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"])
        }
        
        var options = ActionOptions()
        options.traverseAfter = true
        options.showAnimation = false
        
        let result: ActionResult
        
        switch actionStr {
        case "open":
            guard let identifier = args["identifier"] as? String else {
                throw NSError(domain: "BrainMacOSUseTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing identifier for open action"])
            }
            result = await performAction(action: .open(identifier: identifier), optionsInput: options)
            
        case "click":
            guard let pid = args["pid"] as? Int32,
                  let x = args["x"] as? Double,
                  let y = args["y"] as? Double else {
                throw NSError(domain: "BrainMacOSUseTool", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing pid, x, or y for click action"])
            }
            options.pidForTraversal = pid
            result = await performAction(action: .input(action: .click(point: CGPoint(x: x, y: y))), optionsInput: options)
            
        case "type":
            guard let pid = args["pid"] as? Int32,
                  let text = args["text"] as? String else {
                throw NSError(domain: "BrainMacOSUseTool", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing pid or text for type action"])
            }
            options.pidForTraversal = pid
            result = await performAction(action: .input(action: .type(text: text)), optionsInput: options)
            
        case "press":
            guard let pid = args["pid"] as? Int32,
                  let keyName = args["keyName"] as? String else {
                throw NSError(domain: "BrainMacOSUseTool", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing pid or keyName for press action"])
            }
            options.pidForTraversal = pid
            result = await performAction(action: .input(action: .press(keyName: keyName, flags: [])), optionsInput: options)
            
        case "refresh":
            guard let pid = args["pid"] as? Int32 else {
                throw NSError(domain: "BrainMacOSUseTool", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing pid for refresh action"])
            }
            options.pidForTraversal = pid
            result = await performAction(action: .traverseOnly, optionsInput: options)
            
        default:
            throw NSError(domain: "BrainMacOSUseTool", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unknown action: \(actionStr)"])
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(result)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
}
