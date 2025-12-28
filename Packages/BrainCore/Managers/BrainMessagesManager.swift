import Foundation
import SQLite3
import Contacts
import ImageIO
import UniformTypeIdentifiers

    public enum TapbackType: String, Codable, Sendable {
    case loved = "Loved"
    case liked = "Liked"
    case disliked = "Disliked"
    case laughed = "Laughed"
    case emphasized = "Emphasized"
    case questioned = "Questioned"
    case emoji = "Emoji"
    case sticker = "Sticker"
    case unknown = "Unknown"
    
    static func from(type: Int32) -> TapbackType {
        switch type {
        case 2000, 3000: return .loved
        case 2001, 3001: return .liked
        case 2002, 3002: return .disliked
        case 2003, 3003: return .laughed
        case 2004, 3004: return .emphasized
        case 2005, 3005: return .questioned
        case 2006, 3006: return .emoji
        case 2007, 3007, 1000: return .sticker
        default: return .unknown
        }
    }
}

    public struct MessageAttachment: Codable, Sendable {
    public let filename: String?
    public let mimeType: String?
    public let path: String?
}

    public struct MessageEntry: Codable, Sendable {
    public let guid: String
    public let sender: String
    public let senderName: String?
    public let text: String?
    public let timestamp: Date
    public let isFromMe: Bool
    public let threadOriginatorGuid: String?
    public let associatedMessageGuid: String?
    public let associatedMessageType: Int32?
    public let associatedMessageEmoji: String?
    public let tapbackType: TapbackType?
    public let attachments: [MessageAttachment]
    
    public var isTapback: Bool {
        return associatedMessageType != nil && associatedMessageType! > 0
    }

    public func extractEXIF(from path: String) -> [String: String] {
        let fullPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: fullPath)
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return [:]
        }
        
        var exifData: [String: String] = [:]
        
        if let exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                exifData["dateTime"] = dateTime
            }
            if let lens = exif[kCGImagePropertyExifLensModel] as? String {
                exifData["lens"] = lens
            }
        }
        
        if let gps = metadata[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                exifData["location"] = "\(lat), \(lon)"
            }
        }
        
        return exifData
    }
}

import Contacts

@MainActor
public class BrainMessagesManager {
    public static let shared = BrainMessagesManager()
    
    private let dbPath = NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath
    private let contactStore = CNContactStore()
    private var contactCache: [String: String] = [:]
    
    public func fetchRecentMessages(limit: Int = 20, contactName: String? = nil) throws -> [MessageEntry] {
        BrainLogger.info("Fetching \(limit) recent messages...", category: .messages)
        var db: OpaquePointer?
        
        // Open database in read-only mode
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            BrainLogger.error("Failed to open chat.db: \(error)", category: .messages)
            throw NSError(domain: "BrainMessagesManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open chat.db: \(error)"])
        }
        
        defer {
            sqlite3_close(db)
        }
        
        var query = """
        SELECT 
            m.guid,
            m.text, 
            h.id AS sender, 
            m.date / 1000000000 + 978307200 AS timestamp, 
            m.is_from_me,
            m.thread_originator_guid,
            m.associated_message_guid,
            m.associated_message_type,
            m.associated_message_emoji,
            (SELECT GROUP_CONCAT(a.filename || '|' || a.mime_type || '|' || a.relative_path, ';') 
             FROM message_attachment_join maj 
             JOIN attachment a ON maj.attachment_id = a.ROWID 
             WHERE maj.message_id = m.ROWID) as attachments
        FROM 
            message m
        LEFT JOIN 
            handle h ON m.handle_id = h.ROWID
        WHERE 
            (m.text IS NOT NULL OR m.associated_message_type > 0 OR 
             EXISTS (SELECT 1 FROM message_attachment_join maj WHERE maj.message_id = m.ROWID))
        """
        
        if let contact = contactName {
            query += " AND h.id LIKE '%\(contact)%'"
        }
        
        query += " ORDER BY m.date DESC LIMIT \(limit);"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "BrainMessagesManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare query: \(error)"])
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        var messages: [MessageEntry] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let guid = String(cString: sqlite3_column_text(statement, 0))
            let text = sqlite3_column_text(statement, 1) != nil ? String(cString: sqlite3_column_text(statement, 1)) : nil
            let sender = sqlite3_column_text(statement, 2) != nil ? String(cString: sqlite3_column_text(statement, 2)) : "Unknown"
            let timestamp = sqlite3_column_double(statement, 3)
            let isFromMe = sqlite3_column_int(statement, 4) != 0
            let threadGuid = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : nil
            let assocGuid = sqlite3_column_text(statement, 6) != nil ? String(cString: sqlite3_column_text(statement, 6)) : nil
            let assocType = sqlite3_column_int(statement, 7)
            let assocEmoji = sqlite3_column_text(statement, 8) != nil ? String(cString: sqlite3_column_text(statement, 8)) : nil
            
            var attachments: [MessageAttachment] = []
            if let attachmentsStr = sqlite3_column_text(statement, 9) {
                let parts = String(cString: attachmentsStr).components(separatedBy: ";")
                for part in parts {
                    let subparts = part.components(separatedBy: "|")
                    if subparts.count >= 3 {
                        attachments.append(MessageAttachment(
                            filename: subparts[0].isEmpty ? nil : subparts[0],
                            mimeType: subparts[1].isEmpty ? nil : subparts[1],
                            path: subparts[2].isEmpty ? nil : subparts[2]
                        ))
                    }
                }
            }
            
            let tapbackType = assocType > 0 ? TapbackType.from(type: assocType) : nil
            let senderName = resolveContactName(for: sender)
            
            messages.append(MessageEntry(
                guid: guid,
                sender: sender,
                senderName: senderName,
                text: text,
                timestamp: Date(timeIntervalSince1970: timestamp),
                isFromMe: isFromMe,
                threadOriginatorGuid: threadGuid,
                associatedMessageGuid: assocGuid,
                associatedMessageType: assocType > 0 ? assocType : nil,
                associatedMessageEmoji: assocEmoji,
                tapbackType: tapbackType,
                attachments: attachments
            ))
        }
        
        BrainLogger.debug("Successfully fetched \(messages.count) messages from chat.db", category: .messages)
        return messages
    }
    
    private func resolveContactName(for identifier: String) -> String? {
        if identifier == "Unknown" { return nil }
        if let cached = contactCache[identifier] { return cached }
        
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
        let predicate: NSPredicate
        
        if identifier.contains("@") {
            predicate = CNContact.predicateForContacts(matchingEmailAddress: identifier)
        } else {
            // Clean phone number
            let digits = identifier.filter { $0.isNumber }
            if digits.isEmpty { return nil }
            predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: identifier))
        }
        
        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keys)
            if let contact = contacts.first {
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                contactCache[identifier] = name
                return name
            }
        } catch {
            BrainLogger.error("Failed to resolve contact \(identifier): \(error)", category: .messages)
        }
        
        return nil
    }
}
