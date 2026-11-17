import Foundation

/// One KeyTip badge to draw on the ribbon, like the dark letter tags in Windows Office.
public struct RibbonBadge: Equatable {
    /// Letters still to type for this control, for example "M" or "AC".
    public let text: String
    public let tab: String
    /// Control title. Empty means the tab button itself.
    public let control: String
    /// Ribbon role (button, menubutton ...) when the mapping names one; separates equal titles.
    public let role: String?

    public init(text: String, tab: String, control: String, role: String? = nil) {
        self.text = text
        self.tab = tab
        self.control = control
        self.role = role
    }
}

/// One letter tag on an item inside an open dropdown.
public struct DropdownBadge: Equatable {
    public let text: String
    public let item: String
}

/// A dropdown to open (control on a ribbon tab) and the badges for its items.
public struct DropdownPlan: Equatable {
    public let tab: String
    public let control: String
    public let role: String?
    public let items: [DropdownBadge]
}

/// Decides which ribbon controls get a badge for the keys typed so far. Pure logic (no AppKit, no
/// Accessibility), so it is unit-tested without Office. Works for every Office app: each one passes
/// its own mappings.
///
/// - Nothing typed: one badge per ribbon tab (H = Home, N = Insert ...).
/// - A tab letter typed (H): one badge per control of that tab. The badge is the part of the
///   sequence that every command under that control shares, so "H M C", "H M A" and "H M M" give the
///   Merge & Center button the badge "M", and the single command "H A C" gives its button "AC".
/// - Deeper than that the choices are dropdown items, which are not on screen until the dropdown is
///   open, so the plan is empty and the caller falls back to the HUD list.
public enum BadgePlanner {
    public static func plan(mappings: [Mapping], buffer: String) -> [RibbonBadge] {
        let typed = normalize(buffer)
        if typed.isEmpty { return tabBadges(mappings) }

        // The tab the first typed letter switched to.
        guard let first = typed.first,
              let tab = tabSwitch(mappings, key: first)
        else { return [] }

        let groups = controlGroups(mappings, typed: typed, tab: tab)

        return groups.compactMap { g in
            let shared = commonPrefix(g.rests)
            guard !shared.isEmpty else { return nil }   // keys diverge: the choices are dropdown items
            return RibbonBadge(text: String(shared), tab: tab, control: g.control, role: g.role)
        }
    }


    /// Once the typed keys have narrowed everything down to ONE ribbon control whose commands then diverge
    /// ("H O" -> Format: I, A, H, W ...), that control is a dropdown. Returns what to open and which letter
    /// goes on which item. nil when the keys still span several controls, or no item can be named.
    public static func dropdown(mappings: [Mapping], buffer: String) -> DropdownPlan? {
        let typed = normalize(buffer)
        guard typed.count >= 2, let first = typed.first, let tab = tabSwitch(mappings, key: first) else { return nil }
        let groups = controlGroups(mappings, typed: typed, tab: tab)
        guard groups.count == 1, let g = groups.first, commonPrefix(g.rests).isEmpty else { return nil }

        // Items in the order of first appearance, one badge each: the letters their commands share.
        var order: [String] = []
        var rests: [String: [[Character]]] = [:]
        for (m, rest) in zip(g.mappings, g.rests) {
            guard let title = itemTitle(of: m) else { continue }
            if rests[title] == nil { order.append(title) }
            rests[title, default: []].append(rest)
        }
        let items = order.compactMap { title -> DropdownBadge? in
            let shared = commonPrefix(rests[title] ?? [])
            return shared.isEmpty ? nil : DropdownBadge(text: String(shared), item: title)
        }
        return items.isEmpty ? nil : DropdownPlan(tab: tab, control: g.control, role: g.role, items: items)
    }

    /// The dropdown entry a mapping lands on: the third segment of its ribbon path ("Home > Format >
    /// AutoFit Column Width"), which for sub-menus is the sub-menu itself ("Hide & Unhide").
    private static func itemTitle(of m: Mapping) -> String? {
        let segments = (m.ribbon ?? "").components(separatedBy: " > ")
        if segments.count >= 3, !segments[2].isEmpty { return segments[2] }
        for case .ribbon(let t) in m.run { if let item = t.item { return item } }
        return nil
    }

    // MARK: helpers

    private struct Group {
        var control: String
        var role: String?
        var rests: [[Character]] = []
        var mappings: [Mapping] = []
    }

    /// Commands under the typed keys, grouped by the ribbon control they live on.
    private static func controlGroups(_ mappings: [Mapping], typed: [Character], tab: String) -> [Group] {
        var groups: [Group] = []
        var index: [String: Int] = [:]

        for m in mappings where !m.isTabSwitch {
            let keys = normalize(m.keys)
            guard keys.count > typed.count, keys.starts(with: typed),
                  let target = target(of: m, tab: tab)
            else { continue }
            let id = RibbonExecutorNames.norm(target.control) + "|" + (target.role ?? "")
            let rest = Array(keys.dropFirst(typed.count))
            if let i = index[id] {
                groups[i].rests.append(rest)
                groups[i].mappings.append(m)
            } else {
                index[id] = groups.count
                groups.append(Group(control: target.control, role: target.role, rests: [rest], mappings: [m]))
            }
        }

        // A mapping that names no role (found through its ribbon path, or `menu: true`) belongs to the same
        // control as role-naming mappings whose keys start the same way ("H F I" with "H F I D" -> Fill).
        // If the keys share nothing they are a different control with the same title (Format Painter vs Format).
        for i in groups.indices.reversed() where groups[i].role == nil {
            let title = RibbonExecutorNames.norm(groups[i].control)
            if let j = groups.indices.first(where: { $0 != i && groups[$0].role != nil
                && RibbonExecutorNames.norm(groups[$0].control) == title
                && !commonPrefix(groups[$0].rests + groups[i].rests).isEmpty }) {
                groups[j].rests += groups[i].rests
                groups[j].mappings += groups[i].mappings
                groups.remove(at: i)
            }
        }

        return groups
    }

    private static func tabBadges(_ mappings: [Mapping]) -> [RibbonBadge] {
        mappings.compactMap { m in
            guard m.isTabSwitch, case .ribbon(let t) = m.run[0] else { return nil }
            return RibbonBadge(text: String(normalize(m.keys)), tab: t.tab, control: "")
        }
    }

    private static func tabSwitch(_ mappings: [Mapping], key: Character) -> String? {
        for m in mappings where m.isTabSwitch {
            guard normalize(m.keys) == [key], case .ribbon(let t) = m.run[0] else { continue }
            return t.tab
        }
        return nil
    }

    /// The control a mapping ends up on: its ribbon step if it has one for this tab, else the first
    /// segment after the tab in its `ribbon:` path ("Home > Percent Style" -> "Percent Style").
    private static func target(of m: Mapping, tab: String) -> (control: String, role: String?)? {
        for case .ribbon(let t) in m.run where t.tab == tab && !t.control.isEmpty {
            return (t.control, t.role)
        }
        let segments = (m.ribbon ?? "").components(separatedBy: " > ")
        if segments.count >= 2, segments[0] == tab, !segments[1].isEmpty { return (segments[1], nil) }
        return nil
    }

    private static func commonPrefix(_ lists: [[Character]]) -> [Character] {
        guard var prefix = lists.first else { return [] }
        for list in lists.dropFirst() {
            var n = 0
            while n < prefix.count, n < list.count, prefix[n] == list[n] { n += 1 }
            prefix = Array(prefix.prefix(n))
        }
        return prefix
    }

    private static func normalize(_ keys: String) -> [Character] {
        Array(keys.uppercased().filter { !$0.isWhitespace })
    }
}

/// Title normalisation shared by the planner and the Accessibility lookup, so both compare the same way.
public enum RibbonExecutorNames {
    public static func norm(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
