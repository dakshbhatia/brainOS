import Foundation
import SQLite3

/// Queries the macOS KnowledgeC database to track application usage (Screen Time).
public actor BrainUsageManager {
    public static let shared = BrainUsageManager()
    
    private let dbPath = NSString(string: "~/Library/Application Support/Knowledge/knowledgeC.db").expandingTildeInPath
    
    private init() {}
    
    public func fetchRecentUsage(limit: Int = 10) -> [(bundleId: String, duration: Double)] {
        var db: OpaquePointer?
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK || db == nil {
            BrainLogger.error("Failed to open knowledgeC.db. Requires Full Disk Access.", category: .core)
            if db != nil {
                sqlite3_close(db)
            }
            return []
        }
        
        defer { sqlite3_close(db) }
        
        // Query for application foreground events
        let query = """
        SELECT 
            ZOBJECT.ZVALUESTRING AS bundle_id,
            SUM(ZOBJECT.ZENDDATE - ZOBJECT.ZSTARTDATE) AS duration
        FROM 
            ZOBJECT 
        LEFT JOIN 
            ZSTREAM ON ZOBJECT.ZSTREAMNAME = ZSTREAM.ZNAME 
        WHERE 
            ZSTREAMNAME = '/app/usage' 
            AND ZOBJECT.ZSTARTDATE > (strftime('%s', 'now', '-1 day') - 978307200)
        GROUP BY 
            bundle_id
        ORDER BY 
            duration DESC
        LIMIT ?;
        """
        
        var statement: OpaquePointer?
        var results: [(String, Double)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let bundleId = String(cString: sqlite3_column_text(statement, 0))
                let duration = sqlite3_column_double(statement, 1)
                results.append((bundleId, duration))
            }
        }
        sqlite3_finalize(statement)
        return results
    }
}
