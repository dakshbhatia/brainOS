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
    }
    
    public func initialize() {
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
            """,
            """
            CREATE TABLE IF NOT EXISTS entity_aliases (
                alias TEXT PRIMARY KEY,
                canonical_id TEXT,
                FOREIGN KEY(canonical_id) REFERENCES entities(id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS social_vitals_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                contact_id TEXT,
                date TEXT, -- YYYY-MM-DD
                interaction_count INTEGER DEFAULT 0,
                score REAL DEFAULT 0,
                UNIQUE(contact_id, date),
                FOREIGN KEY(contact_id) REFERENCES interaction_stats(contact_id)
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
    
    public func fetchLocations(start: Date, end: Date) -> [(lat: Double, lon: Double, address: String?, timestamp: Date)] {
        let query = "SELECT latitude, longitude, address, timestamp FROM location_logs WHERE datetime(timestamp) BETWEEN datetime(?) AND datetime(?) ORDER BY timestamp ASC;"
        var statement: OpaquePointer?
        var results: [(Double, Double, String?, Date)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (ISO8601DateFormatter().string(from: start) as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (ISO8601DateFormatter().string(from: end) as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let lat = sqlite3_column_double(statement, 0)
                let lon = sqlite3_column_double(statement, 1)
                let addr = sqlite3_column_text(statement, 2).map { String(cString: $0) }
                let tsStr = String(cString: sqlite3_column_text(statement, 3))
                let ts = ISO8601DateFormatter().date(from: tsStr) ?? Date()
                
                results.append((lat, lon, addr, ts))
            }
        }
        sqlite3_finalize(statement)
        return results
    }
    
    /// Provides a unified snapshot of the user's state for the Mirror OS Vitals.
    public func getDailyStatusSnapshot() -> [String: Double] {
        var snapshot: [String: Double] = [
            "social": 0.5,
            "focus": 0.8,
            "physical": 0.3,
            "finance": 0.9
        ]
        
        // 1. Calculate Social score based on interaction frequency today
        let socialCountQuery = "SELECT COUNT(*) FROM interaction_stats WHERE datetime(last_spoken_at) >= datetime('now', 'start of day');"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, socialCountQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = Double(sqlite3_column_int(statement, 0))
                // Normalize: 5 interactions = 1.0 (arbitrary but fits 'Sims' vibe)
                snapshot["social"] = min(1.0, count / 5.0)
            }
        }
        sqlite3_finalize(statement)
        
        // 2. Physical score from step logs (if we had them in DB, usually in HealthKit)
        // For now, we'll keep health retrieval in the View/Manager, but we can store a cached 'vitals' table later.
        
        return snapshot
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
        
        // Log daily tally for trends
        let dateStr = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: timestamp)
        }()
        
        let dailyQuery = """
        INSERT INTO social_vitals_log (contact_id, date, interaction_count)
        VALUES (?, ?, 1)
        ON CONFLICT(contact_id, date) DO UPDATE SET
            interaction_count = interaction_count + 1;
        """
        var dailyStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, dailyQuery, -1, &dailyStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(dailyStmt, 1, (contactId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(dailyStmt, 2, (dateStr as NSString).utf8String, -1, nil)
            sqlite3_step(dailyStmt)
        }
        sqlite3_finalize(dailyStmt)
    }
    
    public func getRelationshipTrends(contactId: String, days: Int = 7) -> [Double] {
        let query = "SELECT interaction_count FROM social_vitals_log WHERE contact_id = ? AND date >= date('now', ?) ORDER BY date ASC;"
        var statement: OpaquePointer?
        var results: [Double] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (contactId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, ("-\(days) days" as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(Double(sqlite3_column_int(statement, 0)))
            }
        }
        sqlite3_finalize(statement)
        return results
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
        let canonicalId = resolveCanonicalEntity(name: name, type: type)
        let id = canonicalId ?? "\(type):\(name.lowercased())"
        
        // If it's a new alias, record it
        if canonicalId == nil {
            saveEntityAlias(alias: name, canonicalId: id)
        }
        
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

    private func resolveCanonicalEntity(name: String, type: String) -> String? {
        let query = "SELECT canonical_id FROM entity_aliases WHERE LOWER(alias) = LOWER(?);"
        var statement: OpaquePointer?
        var result: String? = nil
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                result = String(cString: sqlite3_column_text(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return result
    }

    public func saveEntityAlias(alias: String, canonicalId: String) {
        let query = "INSERT OR IGNORE INTO entity_aliases (alias, canonical_id) VALUES (?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (alias as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (canonicalId as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
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
    
    /// Get memories within a date range with importance scores
    public func getMemoriesInDateRange(start: Date, end: Date, limit: Int) -> [(content: String, timestamp: Date, importance: Double)] {
        let query = """
        SELECT content, timestamp, metadata FROM memories 
        WHERE datetime(timestamp) BETWEEN datetime(?) AND datetime(?)
        ORDER BY timestamp DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        var results: [(String, Date, Double)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
            sqlite3_bind_int(statement, 3, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let content = String(cString: sqlite3_column_text(statement, 0))
                let timestampStr = String(cString: sqlite3_column_text(statement, 1))
                
                // Parse timestamp (SQLite CURRENT_TIMESTAMP format)
                let formatter = ISO8601DateFormatter()
                let timestamp = formatter.date(from: timestampStr) ?? Date()
                
                // Extract importance from metadata JSON
                let metadataStr = String(cString: sqlite3_column_text(statement, 2))
                var importance = 0.5 // default
                if let metadataData = metadataStr.data(using: .utf8),
                   let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                   let importanceValue = metadata["importance"] as? Double {
                    importance = importanceValue
                }
                
                results.append((content, timestamp, importance))
            }
        }
        sqlite3_finalize(statement)
        
        // Sort by importance descending
        return results.sorted { $0.2 > $1.2 }
    }
    
    /// Get all entities for knowledge graph
    public func getAllEntities() -> [(name: String, type: String, lastSeen: Date)] {
        let query = "SELECT name, type, last_seen FROM entities ORDER BY last_seen DESC LIMIT 100;"
        var statement: OpaquePointer?
        var results: [(String, String, Date)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 0))
                let type = String(cString: sqlite3_column_text(statement, 1))
                let lastSeenStr = String(cString: sqlite3_column_text(statement, 2))
                
                let formatter = ISO8601DateFormatter()
                let lastSeen = formatter.date(from: lastSeenStr) ?? Date()
                
                results.append((name, type, lastSeen))
            }
        }
        sqlite3_finalize(statement)
        return results
    }
    
    /// Get all relationships for knowledge graph
    public func getAllRelationships() -> [(sourceName: String, targetName: String, type: String, strength: Float)] {
        let query = """
        SELECT e1.name, e2.name, r.relation_type, r.strength
        FROM relationships r
        JOIN entities e1 ON r.source_id = e1.id
        JOIN entities e2 ON r.target_id = e2.id
        ORDER BY r.strength DESC
        LIMIT 200;
        """
        var statement: OpaquePointer?
        var results: [(String, String, String, Float)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let sourceName = String(cString: sqlite3_column_text(statement, 0))
                let targetName = String(cString: sqlite3_column_text(statement, 1))
                let type = String(cString: sqlite3_column_text(statement, 2))
                let strength = Float(sqlite3_column_double(statement, 3))
                
                results.append((sourceName, targetName, type, strength))
            }
        }
        sqlite3_finalize(statement)
        return results
    }
}
