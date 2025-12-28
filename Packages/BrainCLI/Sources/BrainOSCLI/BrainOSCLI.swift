//
//  BrainOSCLI.swift
//  BrainOS
//
//  Main entry point for the BrainOS CLI. Parses command-line arguments and routes to appropriate command handlers.
//

import Foundation
import BrainOSCLICore

@main
struct BrainOSCLI {
    private enum CommandType {
        case status
        case serve([String])
        case stop
        case list
        case show(String)
        case run(String)
        case mcp
        case ui
        case tools([String])
        case version
        case help
    }

    private static func parseCommand(_ args: ArraySlice<String>) -> CommandType? {
        guard let command = args.first else { return nil }
        let rest = Array(args.dropFirst())
        switch command {
        case "status": return .status
        case "serve": return .serve(rest)
        case "stop": return .stop
        case "list": return .list
        case "show":
            if let modelId = rest.first, !modelId.isEmpty { return .show(modelId) }
            return nil
        case "run":
            if let modelId = rest.first, !modelId.isEmpty { return .run(modelId) }
            return nil
        case "mcp": return .mcp
        case "ui": return .ui
        case "tools": return .tools(rest)
        case "version", "--version", "-v": return .version
        case "help", "-h", "--help": return .help
        default: return nil
        }
    }

    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        guard let cmd = parseCommand(arguments) else {
            if let first = arguments.first { fputs("Unknown or invalid command: \(first)\n\n", stderr) }
            printUsage()
            exit(EXIT_FAILURE)
        }

        switch cmd {
        case .status:
            await StatusCommand.execute(args: [])
        case .serve(let args):
            await ServeCommand.execute(args: args)
        case .stop:
            await StopCommand.execute(args: [])
        case .list:
            await ListCommand.execute(args: [])
        case .show(let modelId):
            await ShowCommand.execute(args: [modelId])
        case .run(let modelId):
            await RunCommand.execute(args: [modelId])
        case .mcp:
            await MCPCommand.execute(args: [])
        case .ui:
            await UICommand.execute(args: [])
        case .tools(let args):
            await ToolsCommand.execute(args: args)
        case .version:
            await VersionCommand.execute(args: [])
        case .help:
            printUsage()
            exit(EXIT_SUCCESS)
        }
    }

    private static func printUsage() {
        let usage = """
            BrainOS - CLI for BrainOS

            Usage:
              BrainOS serve [--port N] [--expose] [--yes|-y]
                                      Start the server (default: localhost only). If --expose
                                      is set, a warning prompt will appear unless --yes is provided.
              BrainOS stop            Stop the server
              BrainOS mcp             Run MCP stdio server proxying to local HTTP
              BrainOS version         Show version (also: --version or -v)
              BrainOS status          Check if the BrainOS server is running
              BrainOS list            List available model IDs
              BrainOS show <model_id> Show metadata for a model
              BrainOS run <model_id>  Chat with a downloaded model (interactive)
              BrainOS ui              Show the BrainOS menu popover in the menu bar
              BrainOS tools list      List installed tools
              BrainOS tools install <plugin_id|url-or-path>
                                      Install a tool from registry or local/URL
              BrainOS tools search <query>
                                      Search for tools in the registry
              BrainOS tools outdated  Check for outdated tools
              BrainOS tools upgrade   Upgrade installed tools
              BrainOS tools uninstall <tool_name>
                                      Uninstall a tool
              BrainOS tools verify    Verify installed tools
              BrainOS tools create <name> [--language swift|rust]
                                      Scaffold a tool project
              BrainOS tools package   Build and zip the current tool
              BrainOS tools reload    Ask the app to rescan tools
              BrainOS help            Show this help

            """
        print(usage)
    }
}
