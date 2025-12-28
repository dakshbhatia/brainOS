//
//  BrainOSApp.swift
//  BrainOS
//
//  Created by Terence on 8/17/25.
//

import AppKit
import BrainCore
import SwiftUI

@main
struct BrainOSApp: SwiftUI.App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some SwiftUI.Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") {
          appDelegate.showPopover()
        }
        .keyboardShortcut(",", modifiers: .command)
      }
    }
  }
}
