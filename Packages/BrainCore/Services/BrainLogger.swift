import Foundation
import OSLog

/// A unified logging service for BrainOS using Apple's OSLog system.
public enum BrainLogger {
    private static let subsystem = "com.brainos.BrainOS"
    
    /// Categories for different parts of the system
    public enum Category: String {
        case core = "Core"
        case agent = "Agent"
        case tool = "Tool"
        case model = "Model"
        case ui = "UI"
        case health = "Health"
        case messages = "Messages"
        case knowledge = "Knowledge"
        case finance = "Finance"
    }
    
    /// Log a message with a specific category and level
    public static func log(_ message: String, category: Category = .core, level: OSLogType = .default) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        default:
            logger.log("\(message, privacy: .public)")
        }
        
        // Also print to console for immediate visibility during development
        #if DEBUG
        let prefix = "🧠 [\(category.rawValue)]"
        print("\(prefix) \(message)")
        #endif
    }
    
    public static func debug(_ message: String, category: Category = .core) {
        log(message, category: category, level: .debug)
    }
    
    public static func info(_ message: String, category: Category = .core) {
        log(message, category: category, level: .info)
    }
    
    public static func error(_ message: String, category: Category = .core) {
        log(message, category: category, level: .error)
    }
    
    public static func fault(_ message: String, category: Category = .core) {
        log(message, category: category, level: .fault)
    }
}
