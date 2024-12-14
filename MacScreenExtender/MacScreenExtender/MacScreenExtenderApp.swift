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
    private var pendingStreamStart = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        screenExtender = ScreenExtender()
        screenExtender?.onInitialized = { [weak self] in
            if self?.pendingStreamStart == true {
                self?.pendingStreamStart = false
                self?.screenExtender?.startStreaming()
            }
        }
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
        guard let screenExtender = screenExtender else { return }
        
        if sender.title == "Start Streaming" {
            if screenExtender.isInitialized {
                screenExtender.startStreaming()
            } else {
                pendingStreamStart = true
            }
            sender.title = "Stop Streaming"
        } else {
            screenExtender.stopStreaming()
            sender.title = "Start Streaming"
        }
    }
}