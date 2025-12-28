//
//  BrainCLITests.swift
//  BrainOS
//
//  Unit tests for the BrainOS CLI core functionality.
//

import XCTest
@testable import BrainCLICore

final class BrainCLITests: XCTestCase {
    func testConfiguration() {
        // Just a smoke test to ensure things link
        let root = Configuration.toolsRootDirectory()
        XCTAssertFalse(root.path.isEmpty)
    }
}
