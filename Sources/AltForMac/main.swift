import AppKit
import AltForMacCore
import AltForMacKit

// `AltForMac --self-test`: loads the mappings and exits, so a packaged build can be verified without UI.
if CommandLine.arguments.contains("--self-test") {
    do {
        for office in OfficeApp.all {
            let url = try AppController.findMappingsFile(stem: office.stem)
            let mappings = try MappingLoader.load(yaml: String(contentsOf: url, encoding: .utf8))
            print("ok: \(office.displayName) \(mappings.count) mappings from \(url.path)")
        }
        exit(0)
    } catch {
        print("FAILED: \(error)")
        exit(1)
    }
}

// AltForMac Phase 0: menu-bar app. Option tap + letters inside Excel runs Windows-style Alt sequences.
// Privacy: no networking, no workbook content, nothing about keystrokes is written to disk.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = AppController()
    private let statusLine = NSMenuItem(title: "Starting\u{2026}", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "\u{2325}"
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AltForMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        controller.onStatus = { [weak self] status in
            switch status {
            case .ready:
                self?.statusItem?.button?.title = "\u{2325}"
                self?.statusLine.title = "Active in Excel, Word and PowerPoint"
            case .needsPermission:
                self?.statusItem?.button?.title = "\u{2325}!"
                self?.statusLine.title = "Needs Accessibility permission"
            case .appSlow:
                self?.statusItem?.button?.title = "\u{2325}!"
                self?.statusLine.title = "An Office app was slow to respond"
            }
        }
        controller.start()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
