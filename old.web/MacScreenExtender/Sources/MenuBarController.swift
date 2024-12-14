import Cocoa

class MenuBarController {
    private var statusItem: NSStatusItem!
    private var screenExtender: ScreenExtender!
    
    init() {
        setupMenuBar()
        screenExtender = ScreenExtender()
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
        
        menu.addItem(NSMenuItem(title: "Connected Devices", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let resolutionMenu = NSMenu()
        resolutionMenu.addItem(NSMenuItem(title: "1920x1080", action: #selector(setResolution(_:)), keyEquivalent: ""))
        resolutionMenu.addItem(NSMenuItem(title: "1280x720", action: #selector(setResolution(_:)), keyEquivalent: ""))
        
        let resolutionItem = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
        resolutionItem.submenu = resolutionMenu
        menu.addItem(resolutionItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func setResolution(_ sender: NSMenuItem) {
        let components = sender.title.split(separator: "x")
        guard components.count == 2,
              let width = Int(components[0]),
              let height = Int(components[1]) else { return }
        
        ConfigurationManager.shared.setResolution(width: width, height: height)
        // Restart the virtual display with new resolution
        screenExtender = ScreenExtender()
    }
} 