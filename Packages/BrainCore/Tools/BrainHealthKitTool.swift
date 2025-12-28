import Foundation
import HealthKit

struct BrainHealthKitTool: BrainOSTool {
    let name = "get_health_data"
    let description = "Retrieve health data like steps, sleep, and heart rate from HealthKit."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "metric": .object([
                    "type": .string("string"),
                    "enum": .array([.string("steps"), .string("sleep"), .string("heart_rate")]),
                    "description": .string("The health metric to retrieve.")
                ]),
                "days": .object([
                    "type": .string("integer"),
                    "description": .string("Number of days of history to retrieve (default 7).")
                ])
            ]),
            "required": .array([.string("metric")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metric = args["metric"] as? String else {
            throw NSError(domain: "BrainHealthKitTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"])
        }
        
        let days = args["days"] as? Int ?? 7
        
        do {
            try await BrainHealthManager.shared.requestPermissions()
            
            if metric == "steps" {
                let steps = try await BrainHealthManager.shared.fetchStepCount(days: days)
                let jsonData = try JSONSerialization.data(withJSONObject: ["metric": "steps", "values": steps])
                return String(data: jsonData, encoding: .utf8) ?? "[]"
            }
            
            return "Metric \(metric) not yet fully implemented, but permissions granted."
        } catch {
            return "Error accessing HealthKit: \(error.localizedDescription). Please ensure BrainOS has Health permissions in System Settings."
        }
    }
}
