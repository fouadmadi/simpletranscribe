//
//  simpletranscribeApp.swift
//  simpletranscribe
//
//  Created by user on 2/22/26.
//

import SwiftUI

@main
struct simpletranscribeApp: App {
    @State private var hotKeyManager = HotKeyManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(hotKeyManager)
        }
        .defaultSize(width: 700, height: 550)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SimpleTranscribe") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "SimpleTranscribe",
                        .version: "",
                    ])
                }
            }
        }
    }
}
