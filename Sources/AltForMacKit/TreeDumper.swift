import ApplicationServices
import AppKit

/// Dumps an AX subtree to JSON-compatible dictionaries for building and verifying mappings.
/// Privacy: never reads AXValue. Skips titles of windows and children of grid-like roles so
/// document names and cell contents cannot end up in a dump.
public final class TreeDumper {
    public struct Options {
        public var maxDepth: Int
        public var maxNodes: Int
        public init(maxDepth: Int = 12, maxNodes: Int = 8000) {
            self.maxDepth = maxDepth
            self.maxNodes = maxNodes
        }
    }

    private let options: Options
    private var count = 0

    /// Roles whose children may be spreadsheet content.
    private static let contentRoles: Set<String> = [
        "AXCell", "AXRow", "AXColumn", "AXTable", "AXGrid", "AXOutline", "AXLayoutArea", "AXLayoutItem"
    ]
    /// Roles whose text is user content (document names, typed text), so titles and descriptions are not read.
    private static let redactedRoles: Set<String> = [
        "AXWindow", "AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXCell"
    ]

    /// Menus that list document or file names (Apple > Recent Items, File > Open Recent, Window).
    /// The title is kept, the children are not.
    private static let documentListMenus: Set<String> = ["Apple", "Recent Items", "Open Recent", "Window", "Subtitle Settings"]

    /// Containers whose children show values derived from the workbook (status bar: Sum, Average, Count).
    private static let contentContainers: Set<String> = ["Status Bar"]

    public init(options: Options = Options()) { self.options = options }

    public var nodeCount: Int { count }

    public func dump(_ node: AXNode, depth: Int = 0) -> [String: Any] {
        count += 1
        var out: [String: Any] = [:]
        let role = node.role ?? "?"
        out["role"] = role
        if let v = node.subrole { out["subrole"] = v }
        if !Self.redactedRoles.contains(role) {
            if var v = node.title, !v.isEmpty {
                // "Undo Typing 'abc' in B3" carries what the user typed and where: keep only the verb.
                if role == kAXMenuItemRole as String,
                   let verb = ["Undo", "Redo", "Repeat"].first(where: { v.hasPrefix($0) }) { v = verb }
                out["title"] = v
            }
            if let v = node.descriptionText, !v.isEmpty { out["description"] = v }
            if let v = node.help, !v.isEmpty { out["help"] = v }
        }
        if let v = node.identifier, !v.isEmpty { out["identifier"] = v }
        if node.isEnabled == false { out["enabled"] = false }
        let actions = node.actions
        if !actions.isEmpty { out["actions"] = actions }
        if role == kAXMenuItemRole as String {
            if let c = node.string("AXMenuItemCmdChar"), !c.isEmpty { out["cmdChar"] = c }
            if let m = node.int("AXMenuItemCmdModifiers") { out["cmdModifiers"] = m }
            if let k = node.int("AXMenuItemCmdVirtualKey"), k != 0 { out["cmdVirtualKey"] = k }
        }

        if let title = node.title, Self.documentListMenus.contains(title),
           role == kAXMenuBarItemRole as String || role == kAXMenuItemRole as String {
            out["childrenSkipped"] = "lists document names"
            return out
        }
        if let title = node.title, Self.contentContainers.contains(title) {
            out["childrenSkipped"] = "shows workbook-derived values"
            return out
        }
        if Self.contentRoles.contains(role) {
            out["childrenSkipped"] = "content role"
            return out
        }
        if depth >= options.maxDepth {
            if !node.children.isEmpty { out["childrenSkipped"] = "max depth" }
            return out
        }
        var kids: [[String: Any]] = []
        for child in node.children {
            if count >= options.maxNodes { out["truncated"] = true; break }
            kids.append(dump(child, depth: depth + 1))
        }
        if !kids.isEmpty { out["children"] = kids }
        return out
    }
}
