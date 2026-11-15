import ApplicationServices
import AppKit

public enum MenuError: Error, CustomStringConvertible {
    case appNotRunning
    case noMenuBar
    case itemNotFound(String)
    case itemDisabled(String)
    case pressFailed(String)
    case emptyPath

    public var description: String {
        switch self {
        case .appNotRunning: return "app is not running"
        case .noMenuBar: return "menu bar not reachable (Accessibility permission or stalled app)"
        case .itemNotFound(let t): return "menu item not found: \(t)"
        case .itemDisabled(let t): return "menu item disabled: \(t)"
        case .pressFailed(let t): return "AXPress failed: \(t)"
        case .emptyPath: return "empty menu path"
        }
    }
}

public enum MenuNavigator {
    /// Menu titles differ in ellipsis style and spacing between builds: compare loosely, never by position.
    public static func normalize(_ title: String) -> String {
        var t = title.replacingOccurrences(of: "\u{2026}", with: "...")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix(".") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces).lowercased()
    }

    public static func titlesMatch(_ a: String, _ b: String) -> Bool { normalize(a) == normalize(b) }

    /// Items directly inside a menu bar item or a menu item's submenu.
    static func menuItems(of node: AXNode) -> [AXNode] {
        // MenuBarItem/MenuItem -> [AXMenu] -> [AXMenuItem...]
        if node.role == kAXMenuRole { return node.children }
        return node.children.first(where: { $0.role == kAXMenuRole })?.children ?? []
    }

    /// Resolves a title path such as ["Format", "Column", "AutoFit Selection"] to the final menu item
    /// without opening any menu. Throws if any step is missing or the final item is disabled.
    public static func resolve(app: AXNode, path: [String]) throws -> AXNode {
        guard !path.isEmpty else { throw MenuError.emptyPath }
        guard let menuBar = app.node(kAXMenuBarAttribute) else { throw MenuError.noMenuBar }
        var level = menuBar.children
        var current: AXNode?
        for (index, wanted) in path.enumerated() {
            guard let match = level.first(where: { ($0.title).map { titlesMatch($0, wanted) } ?? false }) else {
                throw MenuError.itemNotFound(path[0...index].joined(separator: " > "))
            }
            current = match
            level = menuItems(of: match)
        }
        guard let target = current else { throw MenuError.emptyPath }
        guard target.isEnabled else { throw MenuError.itemDisabled(path.joined(separator: " > ")) }
        return target
    }

    public static func press(app: AXNode, path: [String]) throws {
        let item = try resolve(app: app, path: path)
        guard item.press() else { throw MenuError.pressFailed(path.joined(separator: " > ")) }
    }
}
