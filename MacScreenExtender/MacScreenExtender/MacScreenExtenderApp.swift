//
//  MacScreenExtenderApp.swift
//  MacScreenExtender
//
//  Created by Arman Mahjoor on 12/14/24.
//

import SwiftUI

@main
struct MacScreenExtenderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var screenExtender: ScreenExtender?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Screen Extender")
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Start Streaming", action: #selector(toggleStreaming), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func toggleStreaming(_ sender: NSMenuItem) {
        if screenExtender == nil {
            screenExtender = ScreenExtender()
            sender.title = "Stop Streaming"
        } else {
            screenExtender = nil
            sender.title = "Start Streaming"
        }
    }
}