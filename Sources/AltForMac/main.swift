import AppKit
import AltForMacCore
import AltForMacKit

// `AltForMac --self-test`: loads the mappings and exits, so a packaged build can be verified without UI.
if CommandLine.arguments.contains("--self-test") {
    guard AppController.bundleMatchesSignature() else {
        print("FAILED: app bundle does not match its signature")
        exit(1)
    }
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
        let badgeItem = NSMenuItem(title: "Show key badges on the ribbon", action: #selector(toggleBadges(_:)), keyEquivalent: "")
        badgeItem.target = self
        badgeItem.state = AppController.badgesEnabled ? .on : .off
        menu.addItem(badgeItem)
        menu.addItem(.separator())
        let uninstallItem = NSMenuItem(title: "Uninstall AltForMac\u{2026}", action: #selector(uninstall), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)
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
            case .bundleModified:
                self?.statusItem?.button?.title = "\u{2325}!"
                self?.statusLine.title = "AltForMac's files were changed. Reinstall it."
            }
        }
        controller.start()
    }

    /// Badges drawn on the ribbon, or the small HUD list instead. Only a display preference is stored.
    @objc private func toggleBadges(_ sender: NSMenuItem) {
        let enabled = !AppController.badgesEnabled
        UserDefaults.standard.set(enabled, forKey: AppController.badgesKey)
        sender.state = enabled ? .on : .off
    }

    /// macOS keeps an app's privacy permissions after the app is deleted, and a deleted app cannot clean up.
    /// So uninstalling from here removes AltForMac's own permissions first (Accessibility, Automation, ...),
    /// then moves the app to the Trash and quits. Nothing else is installed, so nothing else is left.
    @objc private func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall AltForMac?"
        var info = "This removes AltForMac's Accessibility and Automation permissions, moves the app to the Trash and quits."
        if ["/opt/homebrew/Caskroom/altformac", "/usr/local/Caskroom/altformac"].contains(where: FileManager.default.fileExists) {
            info += "\n\nInstalled with Homebrew? Run \u{201C}brew uninstall --cask altformac\u{201D} instead, so Homebrew knows it is gone."
        }
        info += "\n\nOffice's own KeyTips stay off until you turn them back on (Preferences > Accessibility in each app)."
        alert.informativeText = info
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "All", Bundle.main.bundleIdentifier ?? "dev.altformac.app"]
        try? reset.run()
        reset.waitUntilExit()

        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {   // not when run with `swift run` during development
            try? FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        }
        NSApp.terminate(nil)
    }
}

UserDefaults.standard.register(defaults: [AppController.badgesKey: true])
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
