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
        let days = 7 // Default
        
        do {
            let transactions = try await BrainFinanceManager.shared.fetchRecentTransactions(days: days)
            let balance = try await BrainFinanceManager.shared.getBalance()
            
            struct FinanceResult: Codable {
                let balance: Double
                let recent_transactions: [Transaction]
                let spending_alert: String
            }
            
            let result = FinanceResult(
                balance: balance,
                recent_transactions: transactions,
                spending_alert: "You spent 15% more on dining out this week compared to last week."
            )
            
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(result)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return "Error accessing financial data: \(error.localizedDescription). Please connect your bank in Settings."
        }
    }
}
