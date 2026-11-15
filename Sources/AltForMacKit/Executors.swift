import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import AltForMacCore

public enum ExecutorError: Error, CustomStringConvertible {
    case message(String)
    public var description: String {
        switch self { case .message(let m): return m }
    }
}

/// Marks synthetic events so the key tap lets them through.
public enum SyntheticEvent {
    public static let userData: Int64 = 0x414C_5442   // "ALTB"
}

public protocol StepExecutor {
    var name: String { get }
    func run(_ step: ExecutorStep, pid: pid_t) throws
}

// MARK: shortcut

/// Sends a key combo straight to Excel's process, e.g. "cmd+shift+l". Fastest, but breaks if remapped.
public struct ShortcutExecutor: StepExecutor {
    public let name = "shortcut"
    public init() {}

    public static func parse(_ spec: String) throws -> (code: CGKeyCode, flags: CGEventFlags) {
        var flags: CGEventFlags = []
        var key: Character?
        for part in spec.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default:
                guard part.count == 1, let ch = part.first else {
                    throw ExecutorError.message("unsupported shortcut key: \(part)")
                }
                key = ch
            }
        }
        guard let key, let code = KeyCodes.keyCode(for: key) else {
            throw ExecutorError.message("unsupported shortcut: \(spec)")
        }
        return (CGKeyCode(code), flags)
    }

    public func run(_ step: ExecutorStep, pid: pid_t) throws {
        guard case .shortcut(let spec) = step else { throw ExecutorError.message("not a shortcut step") }
        let (code, flags) = try Self.parse(spec)
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
                throw ExecutorError.message("could not create key event")
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.userData)
            event.postToPid(pid)
        }
    }
}

// MARK: menu

/// Presses a menu-bar item by title path through Accessibility.
public struct MenuExecutor: StepExecutor {
    public let name = "menu"
    public init() {}

    public func run(_ step: ExecutorStep, pid: pid_t) throws {
        guard case .menu(let path) = step else { throw ExecutorError.message("not a menu step") }
        let app = AXNode.application(pid: pid, timeout: 1.0)
        // Lookup is synchronous: a missing or disabled item fails right here and falls through.
        let item: AXNode
        do { item = try MenuNavigator.resolve(app: app, path: path) }
        catch { throw ExecutorError.message(String(describing: error)) }
        guard item.pressAllowingModal() else {
            throw ExecutorError.message("AXPress failed: \(path.joined(separator: " > "))")
        }
    }
}

// MARK: AppleScript

/// Runs AppleScript against Excel. Compiled scripts are cached; NSAppleScript is not thread-safe,
/// so call this from one serial queue only (the runner's queue).
public final class AppleScriptExecutor: StepExecutor {
    public let name = "applescript"
    private var cache: [String: NSAppleScript] = [:]

    public init() {}

    /// Compile ahead of time so the first real run does not pay the compile cost.
    public func precompile(_ source: String) {
        _ = compiled(source)
    }

    /// Opens the Apple Event connection to the app with a harmless read (its app name), so the first
    /// real command does not pay the ~140 ms connection cost. Only call while the app is running.
    public func warmUp(scriptingName: String) {
        guard let script = compiled("tell application \"\(scriptingName)\" to return name") else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    private func compiled(_ source: String) -> NSAppleScript? {
        if let script = cache[source] { return script }
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return nil }
        cache[source] = script
        return script
    }

    public func run(_ step: ExecutorStep, pid: pid_t) throws {
        guard case .applescript(let source) = step else { throw ExecutorError.message("not an applescript step") }
        guard let script = compiled(source) else { throw ExecutorError.message("AppleScript failed to compile") }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "unknown AppleScript error"
            let number = (error[NSAppleScript.errorNumber] as? Int).map { " (\($0))" } ?? ""
            throw ExecutorError.message(message + number)
        }
    }
}

// MARK: ribbon

/// Presses a ribbon control by tab and title through Accessibility. Slowest executor, so it is the
/// last resort. It resolves against the focused window every run, never clicks by position, and fails
/// (instead of guessing) when the tab, control or dropdown item is not found.
public struct RibbonExecutor: StepExecutor {
    public let name = "ribbon"
    public init() {}

    public static let roles: [String: String] = [
        "button": "AXButton", "menubutton": "AXMenuButton", "checkbox": "AXCheckBox",
        "radiobutton": "AXRadioButton", "popupbutton": "AXPopUpButton", "combobox": "AXComboBox"
    ]
    public static let pressable: Set<String> = [
        "AXButton", "AXMenuButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton"
    ]

    public static func norm(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func ribbonGroup(in window: AXNode) -> AXNode? {
        window.children.first { $0.role == "AXTabGroup" && $0.descriptionText == "ribbon" }
    }

    static func commandsArea(of ribbon: AXNode) -> AXNode? {
        ribbon.children.first { $0.role == kAXScrollAreaRole as String }
    }

    static func currentTab(of ribbon: AXNode) -> String? {
        commandsArea(of: ribbon)?.descriptionText?.replacingOccurrences(of: " Tab Commands", with: "")
    }

    public static func find(in node: AXNode, title: String, role: String?, depth: Int = 0) -> AXNode? {
        let wanted = norm(title)
        for child in node.children {
            let r = child.role ?? ""
            let label = child.title ?? child.descriptionText
            if let label, norm(label) == wanted,
               role.map({ $0 == r }) ?? pressable.contains(r) { return child }
            if depth < 8, let hit = find(in: child, title: title, role: role, depth: depth + 1) { return hit }
        }
        return nil
    }

    static func waitFor<T>(timeout: TimeInterval, _ probe: () -> T?) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = probe() { return value }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        return nil
    }

    public func run(_ step: ExecutorStep, pid: pid_t) throws {
        guard case .ribbon(let target) = step else { throw ExecutorError.message("not a ribbon step") }
        let app = AXNode.application(pid: pid, timeout: 1.0)
        // The focused window, unless it is a leftover dropdown popup (no ribbon): then the main document window.
        let candidates = [app.node(kAXFocusedWindowAttribute), app.node(kAXMainWindowAttribute)].compactMap { $0 }
            + app.nodes(kAXWindowsAttribute)
        guard let window = candidates.first(where: { Self.ribbonGroup(in: $0) != nil }) ?? candidates.first
        else { throw ExecutorError.message("no window") }
        guard let ribbon = Self.ribbonGroup(in: window) else {
            throw ExecutorError.message("ribbon not found (is it hidden?)")
        }
        var wantedRole: String?
        if let r = target.role {
            guard let mapped = Self.roles[r.lowercased()] else { throw ExecutorError.message("unknown ribbon role: \(r)") }
            wantedRole = mapped
        }

        if Self.currentTab(of: ribbon) != target.tab {
            guard let tabButton = ribbon.children.first(where: {
                $0.role == kAXRadioButtonRole as String && $0.title == target.tab
            }) else { throw ExecutorError.message("ribbon tab not found: \(target.tab)") }
            guard tabButton.press() else { throw ExecutorError.message("could not open tab \(target.tab)") }
            guard Self.waitFor(timeout: 0.6, { Self.currentTab(of: ribbon) == target.tab ? true : nil }) != nil else {
                throw ExecutorError.message("tab \(target.tab) did not open")
            }
        }
        // Tab-only step (control is empty): the tab switch was the whole command, like Alt+H in Windows.
        if target.control.isEmpty { return }
        // Controls appear a moment after the tab switch.
        guard let control = Self.waitFor(timeout: 0.4, {
            Self.commandsArea(of: ribbon).flatMap { Self.find(in: $0, title: target.control, role: wantedRole) }
        }) else { throw ExecutorError.message("ribbon control not found: \(target.tab) > \(target.control)") }
        guard control.isEnabled else { throw ExecutorError.message("ribbon control disabled: \(target.control)") }

        var popupsBefore: [(ref: AXUIElement, frame: CGRect?)] = []
        if target.item != nil || target.menu == true {
            // Never AXPress to open a dropdown: on split buttons that runs the default action.
            guard control.actions.contains("AXShowMenu") else {
                throw ExecutorError.message("\(target.control) has no dropdown (AXShowMenu)")
            }
            popupsBefore = Self.popupSnapshot(of: app, besides: window)
            guard AXUIElementPerformAction(control.ref, "AXShowMenu" as CFString) == .success else {
                throw ExecutorError.message("could not open dropdown: \(target.control)")
            }
        } else {
            guard control.pressAllowingModal() else { throw ExecutorError.message("press failed: \(target.control)") }
        }

        if let itemTitle = target.item {
            // Dropdown: the popup menu hangs off the control once it is open.
            guard let item = Self.waitFor(timeout: 0.8, {
                Self.findMenuItem(under: control, title: itemTitle)
                    ?? Self.findPopupItem(in: app, besides: window, ignoring: popupsBefore, title: itemTitle)
            }) else {
                throw ExecutorError.message("dropdown item not found: \(target.control) > \(itemTitle)")
            }
            guard item.isEnabled else { throw ExecutorError.message("dropdown item disabled: \(itemTitle)") }
            guard item.pressAllowingModal() else { throw ExecutorError.message("press failed: \(itemTitle)") }
        }
    }

    /// Excel for Mac opens ribbon dropdowns (Borders, Shading ...) as a separate small window next to the
    /// document window, with each choice an AXMenuButton, so the items are not under the control.
    /// Searches every window except the document window `main`; matches the exact title only.
    /// Popup windows already present (ref and frame), so a run only looks at the popup its own ShowMenu opened.
    /// Excel keeps closed popups in the AX tree, hidden, and they hold the same titles ("Unmerge Cells" ...).
    static func popupSnapshot(of app: AXNode, besides main: AXNode) -> [(ref: AXUIElement, frame: CGRect?)] {
        app.nodes(kAXWindowsAttribute).filter { !CFEqual($0.ref, main.ref) }.map { ($0.ref, $0.frame()) }
    }

    static func findPopupItem(in app: AXNode, besides main: AXNode,
                              ignoring before: [(ref: AXUIElement, frame: CGRect?)], title: String) -> AXNode? {
        let wanted = norm(title)
        func search(_ node: AXNode, _ depth: Int) -> AXNode? {
            for child in node.children {
                let r = child.role ?? ""
                if ["AXMenuItem", "AXMenuButton", "AXButton"].contains(r),
                   let label = child.title ?? child.descriptionText, norm(label) == wanted { return child }
                if depth < 5, let hit = search(child, depth + 1) { return hit }
            }
            return nil
        }
        for window in app.nodes(kAXWindowsAttribute) where !CFEqual(window.ref, main.ref) {
            let frame = window.frame()
            if before.contains(where: { CFEqual($0.ref, window.ref) && $0.frame == frame }) { continue }
            if let hit = search(window, 0) { return hit }
        }
        return nil
    }

    static func findMenuItem(under node: AXNode, title: String, depth: Int = 0) -> AXNode? {
        for child in node.children {
            if child.role == kAXMenuItemRole as String, let t = child.title, MenuNavigator.titlesMatch(t, title) {
                return child
            }
            if depth < 4, let hit = findMenuItem(under: child, title: title, depth: depth + 1) { return hit }
        }
        return nil
    }
}
