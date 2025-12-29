import Foundation
import SQLite3

/// Ingests Safari browsing history to understand user interests.
public actor BrainSafariManager {
    public static let shared = BrainSafariManager()
    
    private let dbPath = NSString(string: "~/Library/Safari/History.db").expandingTildeInPath
    
    private init() {}
    
    public func fetchRecentHistory(limit: Int = 20) -> [(title: String, url: String, timestamp: Date)] {
        var db: OpaquePointer?
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            BrainLogger.error("Failed to open Safari History.db. Requires Full Disk Access.", category: .core)
            return []
        }
        
        defer { sqlite3_close(db) }
        
        let query = """
        SELECT 
            i.url, 
            i.url, 
            v.visit_time + 978307200 AS timestamp
        FROM 
            history_items i
        JOIN 
            history_visits v ON i.id = v.history_item
        ORDER BY 
            v.visit_time DESC
        LIMIT ?;
        """
        
        var statement: OpaquePointer?
        var results: [(String, String, Date)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let title = sqlite3_column_text(statement, 0) != nil ? String(cString: sqlite3_column_text(statement, 0)) : "No Title"
                let url = String(cString: sqlite3_column_text(statement, 1))
                let timestamp = sqlite3_column_double(statement, 2)
                results.append((title, url, Date(timeIntervalSince1970: timestamp)))
            }
        }
        sqlite3_finalize(statement)
        return results
    }
}
