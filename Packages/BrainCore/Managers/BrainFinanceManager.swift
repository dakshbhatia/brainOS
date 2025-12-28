import Foundation
import BrainRepository

/// Manages financial data integration (Plaid-powered).
public actor BrainFinanceManager {
    public static let shared = BrainFinanceManager()
    
    private init() {}
    
    /// Fetches recent transactions. 
    /// In a real implementation, this would use a stored Plaid access_token.
    public func fetchRecentTransactions(days: Int = 7) async throws -> [[String: Any]] {
        BrainLogger.info("Fetching transactions for last \(days) days...", category: .finance)
        
        // 1. Check for Plaid access_token in Keychain
        // let token = try RemoteProviderKeychain.shared.get("plaid_access_token")
        
        // 2. If no token, throw error to trigger Plaid Link flow in UI
        // throw FinanceError.noToken
        
        // 3. Fetch from Plaid API
        // let transactions = try await PlaidService.shared.getTransactions(token: token, days: days)
        
        // Mock data for now, but structured for real use
        return [
            ["date": "2024-12-26", "amount": -42.50, "merchant": "Starbucks", "category": "Food & Drink"],
            ["date": "2024-12-25", "amount": -120.00, "merchant": "Apple", "category": "Entertainment"],
            ["date": "2024-12-24", "amount": 2500.00, "merchant": "Employer", "category": "Income"]
        ]
    }
    
    public func getBalance() async throws -> Double {
        return 12450.75
    }
}

public enum FinanceError: Error {
    case noToken
    case apiError(String)
}
