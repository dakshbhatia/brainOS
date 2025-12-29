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
            """,
            // MARK: - Enhanced Relationship Management Tables
            """
            CREATE TABLE IF NOT EXISTS relationship_profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                aliases TEXT,
                photo_data BLOB,
                relationship_score REAL DEFAULT 0,
                tier TEXT DEFAULT 'acquaintances',
                trajectory TEXT DEFAULT 'stable',
                tags TEXT,
                notes TEXT,
                sentiment_score REAL,
                message_balance REAL DEFAULT 0,
                messages_sent INTEGER DEFAULT 0,
                messages_received INTEGER DEFAULT 0,
                average_response_time_seconds REAL,
                first_interaction DATETIME,
                last_interaction DATETIME,
                peak_days TEXT,
                peak_hours TEXT,
                upcoming_event_count INTEGER DEFAULT 0,
                shared_event_count INTEGER DEFAULT 0,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS interaction_events (
                id TEXT PRIMARY KEY,
                contact_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                source TEXT NOT NULL,
                content_preview TEXT,
                sentiment REAL,
                timestamp DATETIME NOT NULL,
                is_from_me INTEGER NOT NULL,
                response_time_seconds INTEGER,
                FOREIGN KEY(contact_id) REFERENCES relationship_profiles(id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS relationship_daily_stats (
                contact_id TEXT NOT NULL,
                date TEXT NOT NULL,
                messages_sent INTEGER DEFAULT 0,
                messages_received INTEGER DEFAULT 0,
                calls INTEGER DEFAULT 0,
                meetings INTEGER DEFAULT 0,
                sentiment_avg REAL,
                PRIMARY KEY(contact_id, date),
                FOREIGN KEY(contact_id) REFERENCES relationship_profiles(id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS relationship_insights (
                id TEXT PRIMARY KEY,
                contact_id TEXT,
                contact_name TEXT,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                priority REAL DEFAULT 0.5,
                action_type TEXT,
                action_data TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                dismissed INTEGER DEFAULT 0,
                acted_on INTEGER DEFAULT 0
            );
            """,
            // Create indexes for faster queries
            """
            CREATE INDEX IF NOT EXISTS idx_interaction_events_contact 
            ON interaction_events(contact_id, timestamp DESC);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_relationship_daily_stats_date 
            ON relationship_daily_stats(date DESC);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_relationship_profiles_tier 
            ON relationship_profiles(tier, relationship_score DESC);
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
    
    // MARK: - Enhanced Relationship Profile Management
    
    /// Save or update a relationship profile
    public func saveRelationshipProfile(_ profile: RelationshipProfile) {
        let aliasesJson = (try? JSONSerialization.data(withJSONObject: profile.aliases)) ?? Data()
        let tagsJson = (try? JSONSerialization.data(withJSONObject: profile.tags)) ?? Data()
        let peakDaysJson = (try? JSONSerialization.data(withJSONObject: profile.peakInteractionDays)) ?? Data()
        let peakHoursJson = (try? JSONSerialization.data(withJSONObject: profile.peakInteractionHours)) ?? Data()
        
        let query = """
        INSERT INTO relationship_profiles (
            id, name, aliases, photo_data, relationship_score, tier, trajectory, 
            tags, notes, sentiment_score, message_balance, messages_sent, messages_received,
            average_response_time_seconds, first_interaction, last_interaction,
            peak_days, peak_hours, upcoming_event_count, shared_event_count, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            aliases = excluded.aliases,
            photo_data = excluded.photo_data,
            relationship_score = excluded.relationship_score,
            tier = excluded.tier,
            trajectory = excluded.trajectory,
            tags = excluded.tags,
            notes = excluded.notes,
            sentiment_score = excluded.sentiment_score,
            message_balance = excluded.message_balance,
            messages_sent = excluded.messages_sent,
            messages_received = excluded.messages_received,
            average_response_time_seconds = excluded.average_response_time_seconds,
            first_interaction = COALESCE(first_interaction, excluded.first_interaction),
            last_interaction = excluded.last_interaction,
            peak_days = excluded.peak_days,
            peak_hours = excluded.peak_hours,
            upcoming_event_count = excluded.upcoming_event_count,
            shared_event_count = excluded.shared_event_count,
            updated_at = CURRENT_TIMESTAMP;
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (profile.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (profile.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, ((String(data: aliasesJson, encoding: .utf8) ?? "[]") as NSString).utf8String, -1, nil)
            if let photoData = profile.photoData {
                sqlite3_bind_blob(statement, 4, (photoData as NSData).bytes, Int32(photoData.count), nil)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            sqlite3_bind_double(statement, 5, profile.relationshipScore)
            sqlite3_bind_text(statement, 6, (profile.tier.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 7, (profile.trajectory.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 8, ((String(data: tagsJson, encoding: .utf8) ?? "[]") as NSString).utf8String, -1, nil)
            if let notes = profile.notes {
                sqlite3_bind_text(statement, 9, (notes as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            if let sentiment = profile.sentimentScore {
                sqlite3_bind_double(statement, 10, sentiment)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            sqlite3_bind_double(statement, 11, profile.messageBalance)
            sqlite3_bind_int(statement, 12, Int32(profile.messagesSent))
            sqlite3_bind_int(statement, 13, Int32(profile.messagesReceived))
            if let responseTime = profile.averageResponseTimeSeconds {
                sqlite3_bind_double(statement, 14, responseTime)
            } else {
                sqlite3_bind_null(statement, 14)
            }
            if let firstInteraction = profile.firstInteraction {
                sqlite3_bind_double(statement, 15, firstInteraction.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 15)
            }
            if let lastInteraction = profile.lastInteraction {
                sqlite3_bind_double(statement, 16, lastInteraction.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 16)
            }
            sqlite3_bind_text(statement, 17, ((String(data: peakDaysJson, encoding: .utf8) ?? "[]") as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 18, ((String(data: peakHoursJson, encoding: .utf8) ?? "[]") as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 19, Int32(profile.upcomingEventCount))
            sqlite3_bind_int(statement, 20, Int32(profile.sharedEventCount))
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to save relationship profile: \(profile.name)", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }
    
    /// Get a relationship profile by ID
    public func getRelationshipProfile(id: String) -> RelationshipProfile? {
        let query = "SELECT * FROM relationship_profiles WHERE id = ?;"
        var statement: OpaquePointer?
        var profile: RelationshipProfile?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                profile = parseRelationshipProfile(from: statement)
            }
        }
        sqlite3_finalize(statement)
        return profile
    }
    
    /// Get all relationship profiles
    public func getAllRelationshipProfiles() -> [RelationshipProfile] {
        let query = "SELECT * FROM relationship_profiles ORDER BY relationship_score DESC, last_interaction DESC;"
        var statement: OpaquePointer?
        var profiles: [RelationshipProfile] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let profile = parseRelationshipProfile(from: statement) {
                    profiles.append(profile)
                }
            }
        }
        sqlite3_finalize(statement)
        return profiles
    }
    
    /// Get relationship profiles by tier
    public func getRelationshipProfiles(tier: RelationshipTier) -> [RelationshipProfile] {
        let query = "SELECT * FROM relationship_profiles WHERE tier = ? ORDER BY relationship_score DESC;"
        var statement: OpaquePointer?
        var profiles: [RelationshipProfile] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (tier.rawValue as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let profile = parseRelationshipProfile(from: statement) {
                    profiles.append(profile)
                }
            }
        }
        sqlite3_finalize(statement)
        return profiles
    }
    
    /// Get profiles needing attention (based on tier-specific thresholds)
    public func getRelationshipsNeedingAttention() -> [RelationshipProfile] {
        let query = """
        SELECT * FROM relationship_profiles 
        WHERE (tier = 'innerCircle' AND last_interaction < datetime('now', '-7 days'))
           OR (tier = 'friends' AND last_interaction < datetime('now', '-14 days'))
           OR (tier = 'acquaintances' AND last_interaction < datetime('now', '-30 days'))
           OR tier IN ('fading', 'dormant')
        ORDER BY 
            CASE tier WHEN 'innerCircle' THEN 0 WHEN 'friends' THEN 1 WHEN 'fading' THEN 2 ELSE 3 END,
            last_interaction DESC;
        """
        var statement: OpaquePointer?
        var profiles: [RelationshipProfile] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let profile = parseRelationshipProfile(from: statement) {
                    profiles.append(profile)
                }
            }
        }
        sqlite3_finalize(statement)
        return profiles
    }
    
    /// Parse a relationship profile from a SQLite statement
    private func parseRelationshipProfile(from statement: OpaquePointer?) -> RelationshipProfile? {
        guard let statement = statement else { return nil }
        
        guard let idPtr = sqlite3_column_text(statement, 0),
              let namePtr = sqlite3_column_text(statement, 1) else {
            return nil
        }
        
        let id = String(cString: idPtr)
        let name = String(cString: namePtr)
        
        // Parse aliases and tags from JSON
        let aliasesStr = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "[]"
        let aliases = (try? JSONSerialization.jsonObject(with: Data(aliasesStr.utf8)) as? [String]) ?? []
        
        // Photo data
        var photoData: Data?
        if let blob = sqlite3_column_blob(statement, 3) {
            let blobSize = Int(sqlite3_column_bytes(statement, 3))
            photoData = Data(bytes: blob, count: blobSize)
        }
        
        let relationshipScore = sqlite3_column_double(statement, 4)
        let tierStr = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "acquaintances"
        let tier = RelationshipTier(rawValue: tierStr) ?? .acquaintances
        let trajectoryStr = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "stable"
        let trajectory = RelationshipTrajectory(rawValue: trajectoryStr) ?? .stable
        
        let tagsStr = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? "[]"
        let tags = (try? JSONSerialization.jsonObject(with: Data(tagsStr.utf8)) as? [String]) ?? []
        
        let notes = sqlite3_column_text(statement, 8).map { String(cString: $0) }
        
        let sentimentScore: Double? = sqlite3_column_type(statement, 9) != SQLITE_NULL ? sqlite3_column_double(statement, 9) : nil
        let messageBalance = sqlite3_column_double(statement, 10)
        let messagesSent = Int(sqlite3_column_int(statement, 11))
        let messagesReceived = Int(sqlite3_column_int(statement, 12))
        let averageResponseTime: Double? = sqlite3_column_type(statement, 13) != SQLITE_NULL ? sqlite3_column_double(statement, 13) : nil
        
        let firstInteraction: Date? = sqlite3_column_type(statement, 14) != SQLITE_NULL ? Date(timeIntervalSince1970: sqlite3_column_double(statement, 14)) : nil
        let lastInteraction: Date? = sqlite3_column_type(statement, 15) != SQLITE_NULL ? Date(timeIntervalSince1970: sqlite3_column_double(statement, 15)) : nil
        
        let peakDaysStr = sqlite3_column_text(statement, 16).map { String(cString: $0) } ?? "[]"
        let peakDays = (try? JSONSerialization.jsonObject(with: Data(peakDaysStr.utf8)) as? [Int]) ?? []
        let peakHoursStr = sqlite3_column_text(statement, 17).map { String(cString: $0) } ?? "[]"
        let peakHours = (try? JSONSerialization.jsonObject(with: Data(peakHoursStr.utf8)) as? [Int]) ?? []
        
        let upcomingEventCount = Int(sqlite3_column_int(statement, 18))
        let sharedEventCount = Int(sqlite3_column_int(statement, 19))
        
        return RelationshipProfile(
            id: id,
            name: name,
            aliases: aliases,
            photoData: photoData,
            relationshipScore: relationshipScore,
            interactionCount: messagesSent + messagesReceived,
            firstInteraction: firstInteraction,
            lastInteraction: lastInteraction,
            averageResponseTimeSeconds: averageResponseTime,
            messageBalance: messageBalance,
            messagesSent: messagesSent,
            messagesReceived: messagesReceived,
            peakInteractionDays: peakDays,
            peakInteractionHours: peakHours,
            sentimentScore: sentimentScore,
            tags: tags,
            notes: notes,
            tier: tier,
            trajectory: trajectory,
            upcomingEventCount: upcomingEventCount,
            sharedEventCount: sharedEventCount,
            updatedAt: Date()
        )
    }
    
    // MARK: - Interaction Event Logging
    
    /// Log an interaction event
    public func logInteractionEvent(_ event: InteractionEvent) {
        let query = """
        INSERT INTO interaction_events (id, contact_id, event_type, source, content_preview, sentiment, timestamp, is_from_me, response_time_seconds)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (event.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (event.contactId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (event.eventType.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (event.source.rawValue as NSString).utf8String, -1, nil)
            if let preview = event.contentPreview {
                sqlite3_bind_text(statement, 5, (preview as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            if let sentiment = event.sentiment {
                sqlite3_bind_double(statement, 6, sentiment)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_double(statement, 7, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_int(statement, 8, event.isFromMe ? 1 : 0)
            if let responseTime = event.responseTimeSeconds {
                sqlite3_bind_int(statement, 9, Int32(responseTime))
            } else {
                sqlite3_bind_null(statement, 9)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to log interaction event", category: .core)
            }
        }
        sqlite3_finalize(statement)
        
        // Update daily stats
        updateDailyStats(for: event)
    }
    
    /// Update daily stats for an interaction
    private func updateDailyStats(for event: InteractionEvent) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: event.timestamp)
        
        let sentIncrement = event.isFromMe ? 1 : 0
        let receivedIncrement = event.isFromMe ? 0 : 1
        
        let query = """
        INSERT INTO relationship_daily_stats (contact_id, date, messages_sent, messages_received)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(contact_id, date) DO UPDATE SET
            messages_sent = messages_sent + excluded.messages_sent,
            messages_received = messages_received + excluded.messages_received;
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (event.contactId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (dateStr as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 3, Int32(sentIncrement))
            sqlite3_bind_int(statement, 4, Int32(receivedIncrement))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    /// Get interaction events for a contact
    public func getInteractionEvents(for contactId: String, limit: Int = 100) -> [InteractionEvent] {
        let query = """
        SELECT * FROM interaction_events 
        WHERE contact_id = ? 
        ORDER BY timestamp DESC 
        LIMIT ?;
        """
        var statement: OpaquePointer?
        var events: [InteractionEvent] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (contactId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let event = parseInteractionEvent(from: statement) {
                    events.append(event)
                }
            }
        }
        sqlite3_finalize(statement)
        return events
    }
    
    private func parseInteractionEvent(from statement: OpaquePointer?) -> InteractionEvent? {
        guard let statement = statement,
              let idPtr = sqlite3_column_text(statement, 0),
              let contactIdPtr = sqlite3_column_text(statement, 1),
              let eventTypePtr = sqlite3_column_text(statement, 2),
              let sourcePtr = sqlite3_column_text(statement, 3) else {
            return nil
        }
        
        guard let id = UUID(uuidString: String(cString: idPtr)),
              let eventType = InteractionEvent.InteractionType(rawValue: String(cString: eventTypePtr)),
              let source = InteractionEvent.InteractionSource(rawValue: String(cString: sourcePtr)) else {
            return nil
        }
        
        let contactId = String(cString: contactIdPtr)
        let contentPreview = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let sentiment: Double? = sqlite3_column_type(statement, 5) != SQLITE_NULL ? sqlite3_column_double(statement, 5) : nil
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        let isFromMe = sqlite3_column_int(statement, 7) != 0
        let responseTime: Int? = sqlite3_column_type(statement, 8) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 8)) : nil
        
        return InteractionEvent(
            id: id,
            contactId: contactId,
            eventType: eventType,
            source: source,
            contentPreview: contentPreview,
            sentiment: sentiment,
            timestamp: timestamp,
            isFromMe: isFromMe,
            responseTimeSeconds: responseTime
        )
    }
    
    // MARK: - Relationship Insights
    
    /// Save a relationship insight
    public func saveRelationshipInsight(_ insight: RelationshipInsight) {
        let query = """
        INSERT INTO relationship_insights (id, contact_id, contact_name, type, title, description, priority, action_type, created_at, dismissed, acted_on)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            dismissed = excluded.dismissed,
            acted_on = excluded.acted_on;
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (insight.id.uuidString as NSString).utf8String, -1, nil)
            if let contactId = insight.contactId {
                sqlite3_bind_text(statement, 2, (contactId as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            if let contactName = insight.contactName {
                sqlite3_bind_text(statement, 3, (contactName as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_text(statement, 4, (insight.type.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (insight.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (insight.description as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 7, insight.priority)
            // Action type/data would need serialization - simplified for now
            sqlite3_bind_null(statement, 8)
            sqlite3_bind_double(statement, 9, insight.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(statement, 10, insight.dismissed ? 1 : 0)
            sqlite3_bind_int(statement, 11, insight.actedOn ? 1 : 0)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                BrainLogger.error("Failed to save relationship insight", category: .core)
            }
        }
        sqlite3_finalize(statement)
    }
    
    /// Get active (non-dismissed) relationship insights
    public func getActiveRelationshipInsights(limit: Int = 10) -> [RelationshipInsight] {
        let query = """
        SELECT * FROM relationship_insights 
        WHERE dismissed = 0 
        ORDER BY priority DESC, created_at DESC 
        LIMIT ?;
        """
        var statement: OpaquePointer?
        var insights: [RelationshipInsight] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let insight = parseRelationshipInsight(from: statement) {
                    insights.append(insight)
                }
            }
        }
        sqlite3_finalize(statement)
        return insights
    }
    
    private func parseRelationshipInsight(from statement: OpaquePointer?) -> RelationshipInsight? {
        guard let statement = statement,
              let idPtr = sqlite3_column_text(statement, 0),
              let typePtr = sqlite3_column_text(statement, 3),
              let titlePtr = sqlite3_column_text(statement, 4),
              let descPtr = sqlite3_column_text(statement, 5) else {
            return nil
        }
        
        guard let id = UUID(uuidString: String(cString: idPtr)),
              let type = RelationshipInsight.InsightType(rawValue: String(cString: typePtr)) else {
            return nil
        }
        
        let contactId = sqlite3_column_text(statement, 1).map { String(cString: $0) }
        let contactName = sqlite3_column_text(statement, 2).map { String(cString: $0) }
        let title = String(cString: titlePtr)
        let description = String(cString: descPtr)
        let priority = sqlite3_column_double(statement, 6)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        let dismissed = sqlite3_column_int(statement, 9) != 0
        let actedOn = sqlite3_column_int(statement, 10) != 0
        
        return RelationshipInsight(
            id: id,
            contactId: contactId,
            contactName: contactName,
            type: type,
            title: title,
            description: description,
            priority: priority,
            action: nil,  // Simplified - would need deserialization
            createdAt: createdAt,
            dismissed: dismissed,
            actedOn: actedOn
        )
    }
    
    /// Dismiss an insight
    public func dismissInsight(id: UUID) {
        let query = "UPDATE relationship_insights SET dismissed = 1 WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    /// Mark an insight as acted upon
    public func markInsightActedOn(id: UUID) {
        let query = "UPDATE relationship_insights SET acted_on = 1 WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - Analytics Aggregations
    
    /// Get aggregate stats for analytics
    public func getRelationshipAnalyticsData() -> (
        byTier: [RelationshipTier: Int],
        active30Days: Int,
        totalMessages: Int,
        avgResponseTime: Double?
    ) {
        var tierCounts: [RelationshipTier: Int] = [:]
        var active30Days = 0
        var totalMessages = 0
        var avgResponseTime: Double?
        
        // Count by tier
        let tierQuery = "SELECT tier, COUNT(*) FROM relationship_profiles GROUP BY tier;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, tierQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let tierPtr = sqlite3_column_text(statement, 0),
                   let tier = RelationshipTier(rawValue: String(cString: tierPtr)) {
                    tierCounts[tier] = Int(sqlite3_column_int(statement, 1))
                }
            }
        }
        sqlite3_finalize(statement)
        
        // Active in last 30 days
        let activeQuery = "SELECT COUNT(*) FROM relationship_profiles WHERE last_interaction > datetime('now', '-30 days');"
        if sqlite3_prepare_v2(db, activeQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                active30Days = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Total messages
        let messagesQuery = "SELECT SUM(messages_sent + messages_received) FROM relationship_profiles;"
        if sqlite3_prepare_v2(db, messagesQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                totalMessages = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        // Average response time
        let responseQuery = "SELECT AVG(average_response_time_seconds) FROM relationship_profiles WHERE average_response_time_seconds IS NOT NULL;"
        if sqlite3_prepare_v2(db, responseQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_type(statement, 0) != SQLITE_NULL {
                avgResponseTime = sqlite3_column_double(statement, 0)
            }
        }
        sqlite3_finalize(statement)
        
        return (tierCounts, active30Days, totalMessages, avgResponseTime)
    }
}

