import Foundation
import SQLite3

/// The unified storage engine for all BrainOS data.
public actor BrainDatabaseManager {
    public static let shared = BrainDatabaseManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("BrainOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.dbPath = appSupport.appendingPathComponent("brain.db").path
        
        setupDatabase()
    }
    
    private func setupDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            BrainLogger.error("Failed to open brain database", category: .core)
            return
        }
        
        // Create tables
        let tables = [
            """
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                content TEXT,
                embedding BLOB,
                metadata TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS entities (
                id TEXT PRIMARY KEY,
                name TEXT,
                type TEXT, -- person, place, event, purchase, city
                metadata TEXT,
                last_seen DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS relationships (
                id TEXT PRIMARY KEY,
                source_id TEXT,
                target_id TEXT,
                relation_type TEXT, -- works_at, lives_in, friend_of, mentioned_in
                strength REAL DEFAULT 1.0,
                FOREIGN KEY(source_id) REFERENCES entities(id),
                FOREIGN KEY(target_id) REFERENCES entities(id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS journal_entries (
                id TEXT PRIMARY KEY,
                date TEXT UNIQUE, -- YYYY-MM-DD
                summary TEXT,
                mood TEXT,
                key_events TEXT, -- JSON array
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS location_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                latitude REAL,
                longitude REAL,
                address TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS interaction_stats (
                contact_id TEXT PRIMARY KEY,
                contact_name TEXT,
                last_spoken_at DATETIME,
                interaction_count INTEGER DEFAULT 0,
                sentiment_score REAL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS usage_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bundle_id TEXT,
                duration INTEGER,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """
        ]
        
        for table in tables {
            if sqlite3_exec(db, table, nil, nil, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                BrainLogger.error("Failed to create table: \(error)", category: .core)
            }
        }
    }
    
    public func logLocation(lat: Double, lon: Double, address: String?) {
        let query = "INSERT INTO location_logs (latitude, longitude, address) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, lat)
            sqlite3_bind_double(statement, 2, lon)
            if let addr = address {
                sqlite3_bind_text(statement, 3, (addr as NSString).utf8String, -1, nil)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to log location", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }
    
    public func updateInteraction(contactId: String, name: String, timestamp: Date) {
        let query = """
        INSERT INTO interaction_stats (contact_id, contact_name, last_spoken_at, interaction_count)
        VALUES (?, ?, ?, 1)
        ON CONFLICT(contact_id) DO UPDATE SET
            last_spoken_at = excluded.last_spoken_at,
            interaction_count = interaction_count + 1;
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (contactId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 3, timestamp.timeIntervalSince1970)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to update interaction stats", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }
    
    public func getStaleContacts(days: Int = 30) -> [(name: String, lastSpoken: Date)] {
        let threshold = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600)).timeIntervalSince1970
        let query = "SELECT contact_name, last_spoken_at FROM interaction_stats WHERE last_spoken_at < ? ORDER BY last_spoken_at ASC;"
        var statement: OpaquePointer?
        var results: [(String, Date)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, threshold)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 0))
                let timestamp = sqlite3_column_double(statement, 1)
                results.append((name, Date(timeIntervalSince1970: timestamp)))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    // MARK: - Knowledge Graph

    public func upsertEntity(name: String, type: String, metadata: [String: String] = [:]) {
        let id = "\(type):\(name.lowercased())"
        let metaJson = (try? JSONSerialization.data(withJSONObject: metadata)) ?? Data()
        let metaStr = String(data: metaJson, encoding: .utf8) ?? "{}"
        
        let query = """
        INSERT INTO entities (id, name, type, metadata, last_seen)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(id) DO UPDATE SET
            last_seen = CURRENT_TIMESTAMP,
            metadata = ?;
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (type as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (metaStr as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (metaStr as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to upsert entity: \(name)", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }

    public func addRelationship(source: String, target: String, type: String, strength: Float = 1.0) {
        let id = "\(source)-\(type)-\(target)"
        let query = """
        INSERT INTO relationships (id, source_id, target_id, relation_type, strength)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET strength = strength + 0.1;
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (source as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (target as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (type as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 5, Double(strength))
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to add relationship", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Journaling

    public func saveJournalEntry(date: String, summary: String, mood: String, events: [String]) {
        let id = UUID().uuidString
        let eventsJson = (try? JSONSerialization.data(withJSONObject: events)) ?? Data()
        let eventsStr = String(data: eventsJson, encoding: .utf8) ?? "[]"
        
        let query = """
        INSERT INTO journal_entries (id, date, summary, mood, key_events)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
            summary = excluded.summary,
            mood = excluded.mood,
            key_events = excluded.key_events;
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (summary as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (mood as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (eventsStr as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to save journal entry", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Memory Storage

    public func saveMemory(id: String, content: String, embedding: [Float], metadata: [String: String]) {
        let metaJson = (try? JSONSerialization.data(withJSONObject: metadata)) ?? Data()
        let metaStr = String(data: metaJson, encoding: .utf8) ?? "{}"
        
        let query = "INSERT INTO memories (id, content, embedding, metadata) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (content as NSString).utf8String, -1, nil)
            
            // Bind embedding as BLOB
            let data = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)
            sqlite3_bind_blob(statement, 3, (data as NSData).bytes, Int32(data.count), nil)
            
            sqlite3_bind_text(statement, 4, (metaStr as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to save memory", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }

    public func searchMemories(embedding: [Float], limit: Int = 5) -> [String] {
        let query = "SELECT content, embedding, timestamp FROM memories;"
        var statement: OpaquePointer?
        var results: [(String, Float)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let content = String(cString: sqlite3_column_text(statement, 0))
                
                let blob = sqlite3_column_blob(statement, 1)
                let blobSize = Int(sqlite3_column_bytes(statement, 1))
                let count = blobSize / MemoryLayout<Float>.size
                let storedEmbedding = Array(UnsafeBufferPointer(start: blob?.assumingMemoryBound(to: Float.self), count: count))
                
                let similarity = cosineSimilarity(embedding, storedEmbedding)
                
                // Recency boost
                let timestamp = sqlite3_column_double(statement, 2) // This might need adjustment if timestamp is string
                // For now, just use similarity
                results.append((content, similarity))
            }
        }
        sqlite3_finalize(statement)
        
        return results.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    public func getRelatedMemories(entityName: String) -> [String] {
        let query = "SELECT content FROM memories WHERE content LIKE ? LIMIT 5;"
        var statement: OpaquePointer?
        var results: [String] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            let pattern = "%\(entityName)%"
            sqlite3_bind_text(statement, 1, (pattern as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(String(cString: sqlite3_column_text(statement, 0)))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count > 0 else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom == 0 ? 0 : dotProduct / denom
    }
}
