import ApplicationServices
import AppKit
import AltForMacCore

/// Where a badge goes on screen (screen coordinates, origin top-left).
public struct BadgePlacement {
    public let badge: RibbonBadge
    public let frame: CGRect
    /// True for an item inside an open dropdown: the badge sits at its left edge instead of under it.
    public let leading: Bool

    public init(badge: RibbonBadge, frame: CGRect, leading: Bool = false) {
        self.badge = badge
        self.frame = frame
        self.leading = leading
    }
}

/// A ribbon dropdown that AltForMac opened (AXShowMenu) so its items can carry badges. It must be closed
/// before the chosen command runs, or when the sequence ends.
public final class DropdownSession: @unchecked Sendable {
    public let popup: AXNode
    let control: AXNode

    init(popup: AXNode, control: AXNode) {
        self.popup = popup
        self.control = control
    }

    /// Dismisses the dropdown by sending Escape to the app. The popup window offers no Accessibility cancel
    /// action. The event is marked as synthetic so AltForMac's own key tap lets it through.
    public func close(pid: pid_t) {
        // Only while the popup is really showing: an Escape sent to a closed dropdown could cancel the
        // user's cell edit instead.
        guard isOnScreen(pid: pid) else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCodes.escape), keyDown: down)
            else { return }
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.userData)
            event.postToPid(pid)
        }
        // Give Excel a moment to take the popup down, so a command that runs next finds a clean screen.
        let deadline = Date().addingTimeInterval(0.15)
        while isOnScreen(pid: pid), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    }

    /// True while a window of the app is on screen at the popup's position (window bounds only).
    public func isOnScreen(pid: pid_t) -> Bool {
        guard let frame = popup.frame(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return list.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"] else { return false }
            return abs(x - frame.minX) < 2 && abs(y - frame.minY) < 2 && abs(w - frame.width) < 2 && abs(h - frame.height) < 2
        }
    }
}

/// Finds the on-screen position of ribbon tabs and controls so KeyTip badges can sit on them.
/// Privacy: reads only roles, titles and geometry of the ribbon, never values or document content.
/// It presses nothing.
public enum RibbonGeometry {
    /// Resolves each badge to a frame. Returns nil when the ribbon cannot be read, or when
    /// `shouldContinue` turned false (a newer key arrived), so stale work stops early.
    public static func place(_ badges: [RibbonBadge], pid: pid_t,
                             shouldContinue: () -> Bool) -> [BadgePlacement]? {
        let app = AXNode.application(pid: pid, timeout: 0.5)
        let candidates = [app.node(kAXFocusedWindowAttribute), app.node(kAXMainWindowAttribute)].compactMap { $0 }
            + app.nodes(kAXWindowsAttribute)
        guard let window = candidates.first(where: { RibbonExecutor.ribbonGroup(in: $0) != nil }),
              let ribbon = RibbonExecutor.ribbonGroup(in: window)
        else { return nil }

        var placements: [BadgePlacement] = []

        // Tab buttons: direct children of the ribbon group.
        let tabBadges = badges.filter { $0.control.isEmpty }
        if !tabBadges.isEmpty {
            let buttons = ribbon.children.filter { $0.role == kAXRadioButtonRole as String }
            for badge in tabBadges {
                guard let button = buttons.first(where: { $0.title == badge.tab }), let frame = button.frame()
                else { continue }
                placements.append(BadgePlacement(badge: badge, frame: frame))
            }
        }

        // Controls: only once the tab they belong to is showing.
        let controlBadges = badges.filter { !$0.control.isEmpty }
        if !controlBadges.isEmpty {
            guard let tab = controlBadges.first?.tab else { return nil }
            let deadline = Date().addingTimeInterval(0.8)
            while RibbonExecutor.currentTab(of: ribbon) != tab {
                guard shouldContinue(), Date() < deadline else { return nil }
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard let area = RibbonExecutor.commandsArea(of: ribbon), let areaFrame = area.frame() else { return nil }

            let wanted = Set(controlBadges.map { RibbonExecutorNames.norm($0.control) })
            var found: [(title: String, role: String, frame: CGRect)] = []
            func walk(_ node: AXNode, _ depth: Int) -> Bool {
                for child in node.children {
                    guard shouldContinue() else { return false }
                    let role = child.role ?? ""
                    if let label = child.title ?? child.descriptionText,
                       wanted.contains(RibbonExecutorNames.norm(label)),
                       RibbonExecutor.pressable.contains(role) || role == "AXComboBox",
                       let frame = child.frame(), frame.width > 0, frame.height > 0 {
                        found.append((RibbonExecutorNames.norm(label), role, frame))
                    }
                    if depth < 8, !walk(child, depth + 1) { return false }
                }
                return true
            }
            guard walk(area, 0) else { return nil }

            // Badges that name a role claim their control first; the rest take a control with that title that
            // is still free. This keeps two controls with one title apart (Format Painter and Format).
            var used = Set<Int>()
            var chosen: [Int: CGRect] = [:]
            let ordered = controlBadges.indices.sorted { (controlBadges[$0].role != nil ? 0 : 1) < (controlBadges[$1].role != nil ? 0 : 1) }
            for i in ordered {
                let badge = controlBadges[i]
                let title = RibbonExecutorNames.norm(badge.control)
                let role = badge.role.flatMap { RibbonExecutor.roles[$0.lowercased()] }
                let hit = found.indices.first { !used.contains($0) && found[$0].title == title && (role == nil || found[$0].role == role) }
                    ?? found.indices.first { found[$0].title == title && (role == nil || found[$0].role == role) }
                guard let hit else { continue }
                used.insert(hit)
                // Controls pushed out of view by a narrow window are not on screen: no badge for them.
                let f = found[hit].frame
                if areaFrame.contains(CGPoint(x: f.midX, y: f.midY)) { chosen[i] = f }
            }
            for i in controlBadges.indices {
                if let frame = chosen[i] { placements.append(BadgePlacement(badge: controlBadges[i], frame: frame)) }
            }
        }

        return placements
    }

    /// Title comparison for dropdown items: ignores case and a trailing "..." or ellipsis, because the
    /// ribbon path says "Row Height" where the menu says "Row Height...".
    static func itemKey(_ title: String) -> String {
        var t = RibbonExecutorNames.norm(title)
        while t.hasSuffix("...") || t.hasSuffix("\u{2026}") { t = String(t.dropLast(t.hasSuffix("...") ? 3 : 1)) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Opens the plan's dropdown with AXShowMenu (never AXPress: on split buttons that would run the default
    /// action on the user's selection) and finds its items. nil when the control, its menu or the items cannot
    /// be found, or `shouldContinue` turned false. The caller closes the returned session.
    public static func openDropdown(_ plan: DropdownPlan, pid: pid_t,
                                    shouldContinue: () -> Bool) -> (session: DropdownSession, placements: [BadgePlacement])? {
        let app = AXNode.application(pid: pid, timeout: 0.5)
        let candidates = [app.node(kAXFocusedWindowAttribute), app.node(kAXMainWindowAttribute)].compactMap { $0 }
            + app.nodes(kAXWindowsAttribute)
        guard let window = candidates.first(where: { RibbonExecutor.ribbonGroup(in: $0) != nil }),
              let ribbon = RibbonExecutor.ribbonGroup(in: window)
        else { return nil }

        let deadline = Date().addingTimeInterval(0.8)
        while RibbonExecutor.currentTab(of: ribbon) != plan.tab {
            guard shouldContinue(), Date() < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let role = plan.role.flatMap { RibbonExecutor.roles[$0.lowercased()] }
        guard shouldContinue(), let area = RibbonExecutor.commandsArea(of: ribbon),
              let control = (role != nil ? RibbonExecutor.find(in: area, title: plan.control, role: role) : findDropdownControl(in: area, title: plan.control)),
              control.isEnabled, control.actions.contains("AXShowMenu")
        else { return nil }

        let before = RibbonExecutor.popupSnapshot(of: app, besides: window)
        guard AXUIElementPerformAction(control.ref, "AXShowMenu" as CFString) == .success else { return nil }

        let wanted = Dictionary(plan.items.map { (itemKey($0.item), $0) }, uniquingKeysWith: { a, _ in a })
        var popup: AXNode?
        var found: [(DropdownBadge, CGRect)] = []
        let end = Date().addingTimeInterval(0.8)
        repeat {
            for w in app.nodes(kAXWindowsAttribute) where !CFEqual(w.ref, window.ref) {
                let frame = w.frame()
                if before.contains(where: { CFEqual($0.ref, w.ref) && $0.frame == frame }) { continue }
                var hits: [(DropdownBadge, CGRect)] = []
                func walk(_ node: AXNode, _ depth: Int) {
                    for child in node.children {
                        let r = child.role ?? ""
                        if ["AXMenuItem", "AXMenuButton", "AXButton"].contains(r),
                           let label = child.title ?? child.descriptionText,
                           let badge = wanted[itemKey(label)], let f = child.frame(), f.height > 0 {
                            hits.append((badge, f))
                        }
                        if depth < 6 { walk(child, depth + 1) }
                    }
                }
                walk(w, 0)
                if !hits.isEmpty { popup = w; found = hits; break }
            }
            if popup != nil { break }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < end && shouldContinue()

        guard let popup else { return nil }
        let session = DropdownSession(popup: popup, control: control)
        let placements = found.map {
            BadgePlacement(badge: RibbonBadge(text: $0.0.text, tab: plan.tab, control: $0.0.item), frame: $0.1, leading: true)
        }
        return (session, placements)
    }

    /// A dropdown button is a menubutton or popupbutton; used when the mapping names no role.
    private static func findDropdownControl(in area: AXNode, title: String) -> AXNode? {
        RibbonExecutor.find(in: area, title: title, role: "AXMenuButton")
            ?? RibbonExecutor.find(in: area, title: title, role: "AXPopUpButton")
    }
}
