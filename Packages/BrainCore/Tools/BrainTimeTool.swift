import Foundation

struct BrainTimeTool: BrainOSTool {
    let name = "current_time"
    let description = "Get the current date and time, optionally in a specific timezone."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "timezone": .object([
                    "type": .string("string"),
                    "description": .string("IANA timezone identifier (e.g., 'America/New_York', 'UTC'). Defaults to system timezone.")
                ])
            ]),
            "required": .array([])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        struct Args: Decodable {
            let timezone: String?
        }

        let input: Args
        if let data = argumentsJSON.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(Args.self, from: data)
        {
            input = decoded
        } else {
            input = Args(timezone: nil)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var timeZone = TimeZone.current
        if let tz = input.timezone, let parsedTZ = TimeZone(identifier: tz) {
            timeZone = parsedTZ
        }
        formatter.timeZone = timeZone

        let now = Date()
        let iso = formatter.string(from: now)
        let unix = now.timeIntervalSince1970

        return """
            {"datetime": "\(iso)", "unix_timestamp": \(unix), "timezone": "\(timeZone.identifier)"}
            """
    }
}
