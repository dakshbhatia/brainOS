//
//  InternalMessage.swift
//  BrainOS
//
//  Extracted from MLXService for reuse across services.
//

import Foundation

/// Message role for chat interactions
enum OSMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// Chat message structure
struct OSMobileMessage: Codable, Sendable {
    let role: OSMessageRole
    let content: String

    init(role: OSMessageRole, content: String) {
        self.role = role
        self.content = content
    }
}
