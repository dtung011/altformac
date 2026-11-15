import Foundation
import AppKit
import ApplicationServices
import AltForMacKit

// ribbon-dump: writes Excel's menu bar and focused-window AX tree to JSON.
//   swift run ribbon-dump [--app excel|word|powerpoint] [--out FILE] [--depth N] [--max-nodes N] [--menu-only]
// Needs Accessibility permission for the terminal that launches it. The app must be running.

var outPath: String?
var office = OfficeApp.excel
var depth = 12
var maxNodes = 8000
var menuOnly = false
var probe = false
var ribbonTabs = false
var selectTab: String?
var listWindows = false
var openDropdown: [String] = []

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--app":
        guard let name = args.next(), let found = OfficeApp.named(name) else {
            FileHandle.standardError.write(Data("--app must be excel, word or powerpoint\n".utf8)); exit(2)
        }
        office = found
    case "--out": outPath = args.next()
    case "--depth": depth = Int(args.next() ?? "") ?? depth
    case "--max-nodes": maxNodes = Int(args.next() ?? "") ?? maxNodes
    case "--menu-only": menuOnly = true
    case "--probe": probe = true
    case "--ribbon-tabs": ribbonTabs = true
    case "--select-tab": selectTab = args.next()
    case "--windows": listWindows = true
    case "--open-dropdown":
        // --open-dropdown TAB CONTROL [ROLE]
        openDropdown = [args.next() ?? "", args.next() ?? ""]
        if let role = args.next() { openDropdown.append(role) }
    default:
        FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
        exit(2)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ribbon-dump: \(message)\n".utf8))
    exit(1)
}

guard AXPermission.isTrusted else {
    AXPermission.requestPrompt()
    fail("Accessibility permission missing. Allow your terminal in System Settings > Privacy & Security > Accessibility, then run again.")
}
guard let running = office.running else { fail("\(office.displayName) is not running") }

let app = AXNode.application(pid: running.processIdentifier, timeout: 2.0)

// --probe: read-only latency measurements (resolves menu items, never presses them,
// runs an AppleScript that only reads a window property).
if probe {
    func time(_ label: String, runs: Int = 5, _ body: () throws -> Void) {
        var samples: [Double] = []
        var failure: String?
        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            do { try body() } catch { failure = String(describing: error) }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6)
        }
        let list = samples.map { String(format: "%.1f", $0) }.joined(separator: ", ")
        print("\(label): [\(list)] ms\(failure.map { "  FAILED: \($0)" } ?? "")")
    }
    for path in [["Format", "Column", "AutoFit Selection"], ["View", "Ribbon"], ["Data", "Summarize with PivotTable"]] {
        time("menu resolve \(path.joined(separator: " > "))") { _ = try MenuNavigator.resolve(app: app, path: path) }
    }
    let script = NSAppleScript(source: "tell application \"\(office.scriptingName)\" to return name")!
    time("applescript read app name (incl. first-call compile+connect)") {
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if let err { throw NSError(domain: "as", code: 1, userInfo: [NSLocalizedDescriptionKey: String(describing: err[NSAppleScript.errorMessage] ?? "?")]) }
    }
    exit(0)
}
let dumper = TreeDumper(options: .init(maxDepth: depth, maxNodes: maxNodes))

var result: [String: Any] = [
    "app": office.displayName,
    "appVersion": office.version ?? "unknown",
    "generated": ISO8601DateFormatter().string(from: Date()),
    "note": "Titles/descriptions only. AXValue, window titles and grid content are never read."
]
if let menuBar = app.node(kAXMenuBarAttribute) {
    result["menuBar"] = dumper.dump(menuBar)
} else {
    fail("could not read Excel's menu bar (stalled, or Accessibility not granted to this terminal)")
}
// --windows: lists Excel's windows (role, subrole, child count) without touching anything.
if listWindows {
    for w in app.nodes(kAXWindowsAttribute) {
        print("window role=\(w.role ?? "?") subrole=\(w.subrole ?? "-") children=\(w.children.count) frame=\(w.frame().map { "\($0)" } ?? "?")")
    }
    print("focused window children: \(app.node(kAXFocusedWindowAttribute)?.children.count ?? -1)")
    exit(0)
}

// --open-dropdown TAB CONTROL [ROLE]: opens one ribbon dropdown with AXShowMenu (never AXPress: on split
// buttons such as Borders, AXPress APPLIES the default action to the user's selection), dumps whatever
// popup appears (titles only), then asks it to close with AXCancel. It never presses anything else.
if openDropdown.count >= 2, let window = office.focusedWindow(of: app), let ribbon = RibbonExecutor.ribbonGroup(in: window) {
    let tab = openDropdown[0], control = openDropdown[1]
    let role = openDropdown.count > 2 ? RibbonExecutor.roles[openDropdown[2]] : nil
    if let b = ribbon.children.first(where: { $0.role == kAXRadioButtonRole as String && $0.title == tab }) { b.press(); Thread.sleep(forTimeInterval: 0.8) }
    guard let area = ribbon.children.first(where: { $0.role == kAXScrollAreaRole as String }) else { fail("no commands area") }
    guard let node = RibbonExecutor.find(in: area, title: control, role: role) else {
        fail("control not found (tab now: \(area.descriptionText ?? "?"))")
    }
    guard node.actions.contains("AXShowMenu") else { fail("\(control) has no AXShowMenu action, not opening it") }
    AXUIElementPerformAction(node.ref, "AXShowMenu" as CFString)
    Thread.sleep(forTimeInterval: 0.6)
    var popup: [String: Any] = ["control": dumper.dump(node, depth: 6)]
    popup["appLevelMenus"] = app.children.filter { $0.role == "AXMenu" }.map { dumper.dump($0) }
    popup["windows"] = app.nodes(kAXWindowsAttribute).map { ["role": $0.role ?? "?", "children": $0.children.count] as [String: Any] }
    if let focused = app.node(kAXFocusedUIElementAttribute) { popup["focusedElement"] = dumper.dump(focused, depth: 6) }
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: popup, options: [.prettyPrinted, .sortedKeys]))
    func cancelMenu(_ n: AXNode, _ depth: Int = 0) -> Bool {
        for c in n.children {
            if c.role == "AXMenu" { _ = AXUIElementPerformAction(c.ref, "AXCancel" as CFString); return true }
            if depth < 3, cancelMenu(c, depth + 1) { return true }
        }
        return false
    }
    if !(cancelMenu(node) || cancelMenu(app)) {
        FileHandle.standardError.write(Data("popup not exposed in AX: if a menu is open on screen, press Escape\n".utf8))
    }
    exit(0)
}

// --select-tab NAME: switches the ribbon to a tab (used to restore the user's tab).
if let selectTab, let window = office.focusedWindow(of: app),
   let ribbon = window.children.first(where: { $0.role == "AXTabGroup" && $0.descriptionText == "ribbon" }),
   let button = ribbon.children.first(where: { $0.role == kAXRadioButtonRole as String && $0.title == selectTab }) {
    print(button.press() ? "selected \(selectTab)" : "could not select \(selectTab)")
    exit(0)
}

// --ribbon-tabs: visits every ribbon tab (presses its tab button, waits for it to draw, dumps the
// commands) and then goes back to the tab that was open. Only the ribbon is dumped, nothing else.
if ribbonTabs, let window = office.focusedWindow(of: app),
   let ribbon = window.children.first(where: { $0.role == "AXTabGroup" && $0.descriptionText == "ribbon" }) {
    func currentTab() -> String? {
        ribbon.children.first(where: { $0.role == kAXScrollAreaRole as String })?
            .descriptionText?.replacingOccurrences(of: " Tab Commands", with: "")
    }
    let original = currentTab()
    let tabButtons = ribbon.children.filter { $0.role == kAXRadioButtonRole as String }
    var tabs: [String: Any] = [:]
    for button in tabButtons {
        guard let name = button.title else { continue }
        // Pressing the tab that is already open can collapse the ribbon, so only press other tabs.
        if currentTab() != name {
            button.press()
            for _ in 0..<20 where currentTab() != name { Thread.sleep(forTimeInterval: 0.05) }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if let commands = ribbon.children.first(where: { $0.role == kAXScrollAreaRole as String }) {
            tabs[name] = dumper.dump(commands)
        }
    }
    if let original, let back = tabButtons.first(where: { $0.title == original }) { back.press() }
    result["ribbonTabs"] = tabs
    result["restoredTab"] = original ?? "unknown"
}
if !menuOnly && !ribbonTabs {
    if let window = office.focusedWindow(of: app) {
        result["window"] = dumper.dump(window)
    } else {
        result["window"] = NSNull()
    }
}
result["nodeCount"] = dumper.nodeCount

let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
if let outPath {
    try data.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath): \(dumper.nodeCount) nodes, \(office.displayName) \(office.version ?? "?")")
} else {
    FileHandle.standardOutput.write(data)
}
