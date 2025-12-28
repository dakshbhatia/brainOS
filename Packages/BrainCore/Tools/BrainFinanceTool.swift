import Foundation

struct BrainFinanceTool: BrainOSTool {
    let name = "get_finance_summary"
    let description = "Retrieve financial summary and recent transactions (Plaid-powered)."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "days": .object([
                    "type": .string("integer"),
                    "description": .string("Number of days of history to retrieve (default 7).")
                ])
            ]),
            "required": .array([])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        // Mock finance data
        return """
            {
              "balance": 12450.75,
              "recent_transactions": [
                {"date": "2024-12-26", "amount": -42.50, "merchant": "Starbucks", "category": "Food & Drink"},
                {"date": "2024-12-25", "amount": -120.00, "merchant": "Apple", "category": "Entertainment"},
                {"date": "2024-12-24", "amount": 2500.00, "merchant": "Employer", "category": "Income"}
              ],
              "spending_alert": "You spent 15% more on dining out this week compared to last week."
            }
            """
    }
}
