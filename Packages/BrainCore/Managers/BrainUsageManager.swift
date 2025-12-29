import Foundation
import SQLite3

/// Queries the macOS KnowledgeC database to track application usage (Screen Time).
public actor BrainUsageManager {
    public static let shared = BrainUsageManager()
    
    private let dbPath = NSString(string: "~/Library/Application Support/Knowledge/knowledgeC.db").expandingTildeInPath
    
    private init() {}
    
    public func fetchTimelineUsage(start: Date, end: Date, limit: Int = 100) -> [(bundleId: String, timestamp: Date, duration: Double)] {
        var db: OpaquePointer?
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK || db == nil {
            BrainLogger.error("Failed to open knowledgeC.db", category: .core)
            if db != nil { sqlite3_close(db) }
            return []
        }
        
        defer { sqlite3_close(db) }
        
        let startInterval = start.timeIntervalSinceReferenceDate
        let endInterval = end.timeIntervalSinceReferenceDate
        
        let query = """
        SELECT 
            ZOBJECT.ZVALUESTRING AS bundle_id,
            ZOBJECT.ZSTARTDATE + 978307200 AS timestamp,
            ZOBJECT.ZENDDATE - ZOBJECT.ZSTARTDATE AS duration
        FROM 
            ZOBJECT 
        LEFT JOIN 
            ZSTREAM ON ZOBJECT.ZSTREAMNAME = ZSTREAM.ZNAME 
        WHERE 
            ZSTREAMNAME = '/app/usage' 
            AND ZOBJECT.ZSTARTDATE BETWEEN ? AND ?
        ORDER BY 
            ZOBJECT.ZSTARTDATE DESC
        LIMIT ?;
        """
        
        var statement: OpaquePointer?
        var results: [(String, Date, Double)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, startInterval)
            sqlite3_bind_double(statement, 2, endInterval)
            sqlite3_bind_int(statement, 3, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let bundleId = String(cString: sqlite3_column_text(statement, 0))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
                let duration = sqlite3_column_double(statement, 2)
                results.append((bundleId, timestamp, duration))
            }
        }
        sqlite3_finalize(statement)
        return results
    }
    
    public func fetchRecentUsage(limit: Int = 10) -> [(bundleId: String, duration: Double)] {
        // Keeping original for compatibility if needed, though we could refactor it
        let start = Date().addingTimeInterval(-86400)
        let end = Date()
        let results = fetchTimelineUsage(start: start, end: end, limit: limit)
        
        // Group by bundleId and sum duration
        var aggregated: [String: Double] = [:]
        for res in results {
            aggregated[res.bundleId, default: 0] += res.duration
        }
        return aggregated.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}
