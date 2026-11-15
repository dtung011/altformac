import ApplicationServices
import AppKit

/// Thin wrapper over AXUIElement. Privacy rule: this layer must never read
/// AXValue (cell contents, text fields) or document paths. Only structure, titles and geometry.
public struct AXNode {
    public let ref: AXUIElement

    public init(_ ref: AXUIElement) { self.ref = ref }

    public static func application(pid: pid_t, timeout: Float = 1.0) -> AXNode {
        let element = AXUIElementCreateApplication(pid)
        // Bounded waits: a stalled Excel must never freeze typing (see CLAUDE.md, 2 s rule).
        AXUIElementSetMessagingTimeout(element, timeout)
        return AXNode(element)
    }

    private func copy(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    public func string(_ attribute: String) -> String? { copy(attribute) as? String }

    public func bool(_ attribute: String) -> Bool? { (copy(attribute) as? NSNumber)?.boolValue }

    public func int(_ attribute: String) -> Int? { (copy(attribute) as? NSNumber)?.intValue }

    public func node(_ attribute: String) -> AXNode? {
        guard let value = copy(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXNode(unsafeBitCast(value, to: AXUIElement.self))
    }

    public func nodes(_ attribute: String) -> [AXNode] {
        guard let array = copy(attribute) as? [AXUIElement] else { return [] }
        return array.map(AXNode.init)
    }

    public var role: String? { string(kAXRoleAttribute) }
    public var subrole: String? { string(kAXSubroleAttribute) }
    public var title: String? { string(kAXTitleAttribute) }
    public var descriptionText: String? { string(kAXDescriptionAttribute) }
    public var identifier: String? { string(kAXIdentifierAttribute) }
    public var help: String? { string(kAXHelpAttribute) }
    public var isEnabled: Bool { bool(kAXEnabledAttribute) ?? true }
    public var children: [AXNode] { nodes(kAXChildrenAttribute) }

    public var actions: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(ref, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    @discardableResult
    public func press() -> Bool {
        AXUIElementPerformAction(ref, kAXPressAction as CFString) == .success
    }

    /// Presses on a helper thread. Items that open a modal dialog may not return from AXPress until the
    /// dialog closes, so "still running after `grace`" counts as success. Returns false only if the
    /// press itself failed within the grace period.
    public func pressAllowingModal(grace: TimeInterval = 0.25) -> Bool {
        let done = DispatchSemaphore(value: 0)
        var pressed = false
        let target = self
        Thread.detachNewThread {
            pressed = target.press()
            done.signal()
        }
        if done.wait(timeout: .now() + grace) == .success { return pressed }
        return true
    }

    /// Window geometry in screen coordinates (origin top-left). Geometry only, no content.
    public func frame() -> CGRect? {
        guard let p = copy(kAXPositionAttribute), let s = copy(kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

public enum AXPermission {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings when not yet trusted.
    @discardableResult
    public static func requestPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// The Office apps AltForMac drives. Each has its own mappings file and its own sequence state.
public struct OfficeApp: Equatable {
    public let bundleID: String
    /// Short name for messages: "Excel".
    public let displayName: String
    /// Name used in AppleScript `tell application`.
    public let scriptingName: String
    /// File stem of the mappings (`mappings/<stem>.yaml`) and of the UI dumps (`docs/dumps/<stem>-*.json`).
    public let stem: String

    public static let excel = OfficeApp(bundleID: "com.microsoft.Excel", displayName: "Excel",
                                        scriptingName: "Microsoft Excel", stem: "excel")
    public static let word = OfficeApp(bundleID: "com.microsoft.Word", displayName: "Word",
                                       scriptingName: "Microsoft Word", stem: "word")
    public static let powerpoint = OfficeApp(bundleID: "com.microsoft.Powerpoint", displayName: "PowerPoint",
                                             scriptingName: "Microsoft PowerPoint", stem: "powerpoint")
    public static let all: [OfficeApp] = [.excel, .word, .powerpoint]

    public static func from(bundleID: String?) -> OfficeApp? {
        all.first { $0.bundleID == bundleID }
    }

    public static func named(_ name: String) -> OfficeApp? {
        all.first { $0.stem == name.lowercased() }
    }

    public static var frontmost: OfficeApp? {
        from(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    public var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    public var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    public var version: String? {
        guard let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Focused window of the app. Resolved fresh on every call: several documents can be open.
    public func focusedWindow(of app: AXNode) -> AXNode? {
        app.node(kAXFocusedWindowAttribute) ?? app.node(kAXMainWindowAttribute) ?? app.nodes(kAXWindowsAttribute).first
    }
}
