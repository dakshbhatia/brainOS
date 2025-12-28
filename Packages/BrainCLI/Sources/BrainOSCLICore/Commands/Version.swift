//
//  Version.swift
//  BrainOS
//
//  Command to display the BrainOS version and build number from environment variables.
//

import Foundation

public struct VersionCommand: Command {
    public static let name = "version"

    public static func execute(args: [String]) async {
        var versionString: String?
        var buildString: String?

        if let v = ProcessInfo.processInfo.environment["BRAINOS_VERSION"] { versionString = v }
        if let b = ProcessInfo.processInfo.environment["BRAINOS_BUILD_NUMBER"] { buildString = b }

        let output: String
        if let v = versionString, let b = buildString, !b.isEmpty {
            output = "BrainOS \(v) (\(b))"
        } else if let v = versionString {
            output = "BrainOS \(v)"
        } else {
            output = "BrainOS dev"
        }
        print(output)
        exit(EXIT_SUCCESS)
    }
}
