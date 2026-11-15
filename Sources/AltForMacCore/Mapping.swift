import Foundation
import Yams

public struct RibbonTarget: Codable, Equatable {
    public var tab: String
    public var control: String
    public var item: String?
    /// Disambiguates controls that share a title (Home has two "Format"): button, menubutton,
    /// checkbox, radiobutton, popupbutton or combobox.
    public var role: String?
    /// Open the control's dropdown (AXShowMenu) instead of pressing it. Implied when `item` is set.
    /// On split buttons such as Borders, a plain press APPLIES the default action to the selection.
    public var menu: Bool?

    public init(tab: String, control: String, item: String? = nil, role: String? = nil, menu: Bool? = nil) {
        self.tab = tab
        self.control = control
        self.item = item
        self.role = role
        self.menu = menu
    }
}

/// One way to perform a command. A mapping lists steps in order; the runner
/// tries each until one succeeds (shortcut -> menu -> applescript -> ribbon).
public enum ExecutorStep: Equatable {
    case shortcut(String)
    case menu([String])
    case applescript(String)
    case ribbon(RibbonTarget)
}

extension ExecutorStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case shortcut, menu, applescript, ribbon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(String.self, forKey: .shortcut) {
            self = .shortcut(v)
        } else if let v = try c.decodeIfPresent([String].self, forKey: .menu) {
            self = .menu(v)
        } else if let v = try c.decodeIfPresent(String.self, forKey: .applescript) {
            self = .applescript(v)
        } else if let v = try c.decodeIfPresent(RibbonTarget.self, forKey: .ribbon) {
            self = .ribbon(v)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Executor step needs one of: shortcut, menu, applescript, ribbon")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shortcut(let v): try c.encode(v, forKey: .shortcut)
        case .menu(let v): try c.encode(v, forKey: .menu)
        case .applescript(let v): try c.encode(v, forKey: .applescript)
        case .ribbon(let v): try c.encode(v, forKey: .ribbon)
        }
    }
}

public struct Mapping: Codable, Equatable {
    /// Windows sequence, e.g. "H O I". Quote it in YAML: a bare `N` parses as a boolean.
    public var keys: String
    public var label: String
    /// Ribbon path shown in the overlay, e.g. "Home > Format > AutoFit Column Width".
    public var ribbon: String?
    public var run: [ExecutorStep]
    public var minExcel: String?
    public var maxExcel: String?

    enum CodingKeys: String, CodingKey {
        case keys, label, ribbon, run
        case minExcel = "min_excel"
        case maxExcel = "max_excel"
    }

    /// True for a ribbon tab letter (Excel "N" = Insert tab): the tab switches at once, but the sequence
    /// stays open for the letters that follow, like Windows KeyTips. Never auto-committed.
    public var isTabSwitch: Bool {
        guard run.count == 1, case .ribbon(let target) = run[0] else { return false }
        return target.control.isEmpty && target.item == nil
    }

    /// True for an entry that only opens a ribbon dropdown (`menu: true`, no `item`), e.g. "H M" opening the
    /// Merge & Center menu. When longer sequences exist (H M C ...) the HUD already lists the letters, so
    /// such an entry is never auto-committed: opening the menu mid-sequence would swallow the next letter.
    public var isMenuOpener: Bool {
        guard run.count == 1, case .ribbon(let target) = run[0] else { return false }
        return target.menu == true && target.item == nil
    }

    public init(keys: String, label: String, ribbon: String? = nil, run: [ExecutorStep],
                minExcel: String? = nil, maxExcel: String? = nil) {
        self.keys = keys
        self.label = label
        self.ribbon = ribbon
        self.run = run
        self.minExcel = minExcel
        self.maxExcel = maxExcel
    }
}

public enum MappingError: Error, Equatable {
    case duplicateKeys(String)
    case emptyKeys
    case noExecutor(keys: String)
}

public enum MappingLoader {
    /// Parses and validates a mappings YAML document (a list of mappings).
    public static func load(yaml: String) throws -> [Mapping] {
        let mappings = try YAMLDecoder().decode([Mapping].self, from: yaml)
        try validate(mappings)
        return mappings
    }

    public static func validate(_ mappings: [Mapping]) throws {
        var seen = Set<String>()
        for m in mappings {
            let normalized = String(m.keys.uppercased().filter { !$0.isWhitespace })
            if normalized.isEmpty { throw MappingError.emptyKeys }
            if m.run.isEmpty { throw MappingError.noExecutor(keys: m.keys) }
            if !seen.insert(normalized).inserted { throw MappingError.duplicateKeys(m.keys) }
        }
    }

    public static func buildTrie(_ mappings: [Mapping]) -> SequenceTrie<Mapping> {
        let trie = SequenceTrie<Mapping>()
        for m in mappings { trie.insert(m.keys, value: m) }
        return trie
    }
}
