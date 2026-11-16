import AppKit
import CoreGraphics
import AltForMacKit

/// Already classified keyboard/mouse input. Physical key codes only, never typed characters.
enum RawInput {
    case optionTap
    /// A letter or digit with no Cmd/Ctrl/Shift. `optionHeld` is true for the Option+letter chord.
    case key(Character, optionHeld: Bool)
    case escape
    case backspace
    /// Any other key, or a key with Cmd/Ctrl/Shift held: ends KeyTip mode and is never swallowed.
    case other
    case mouse
}

/// CGEventTap that is enabled only while Excel is frontmost. The tap runs on its own high-priority
/// thread, so drawing the HUD or any main-thread work can never delay a key (fast typing stays correct,
/// and macOS has no reason to disable a slow tap). It keeps no history: the only state is the
/// Option-tap timer and the set of key-downs it swallowed (so their key-ups are swallowed too).
final class KeyCapture {
    /// Called ON THE INPUT THREAD with the classified input. Return true to swallow the event.
    var handler: ((RawInput) -> Bool)?

    private var tap: CFMachPort?
    /// What `setActive` last asked for. A tap that macOS disabled for being slow is re-enabled only if
    /// this is still true, so a timeout that races an app switch cannot turn the tap on for another app.
    private var wantsActive = false
    private var runLoop: CFRunLoop?
    private var optionDownAt: UInt64?
    private var otherInputDuringOption = false
    private var swallowedKeyDowns = Set<Int64>()
    private let tapWindowNanos: UInt64 = 350_000_000

    var isInstalled: Bool { tap != nil }

    /// Creates the tap (disabled) and its thread. Returns false while Accessibility permission is missing.
    func install() -> Bool {
        if tap != nil { return true }
        let ready = DispatchSemaphore(value: 0)
        var created = false
        let thread = Thread { [unowned self] in
            guard self.createTap() else { ready.signal(); return }
            created = true
            self.runLoop = CFRunLoopGetCurrent()
            ready.signal()
            while true { CFRunLoopRunInMode(.defaultMode, 3600, false) }
        }
        thread.name = "altformac.input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return created
    }

    /// Runs a block on the input thread (all KeyTip state lives there).
    func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { block(); return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Enabled only while Excel is frontmost: no other app's keys are ever inspected.
    func setActive(_ active: Bool) {
        wantsActive = active
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: active)
        if !active { perform { [self] in resetTracking() } }
    }

    private func createTap() -> Bool {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let capture = Unmanaged<KeyCapture>.fromOpaque(userInfo).takeUnretainedValue()
            return capture.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: false)
        tap = port
        return true
    }

    private func resetTracking() {
        optionDownAt = nil
        otherInputDuringOption = false
        swallowedKeyDowns.removeAll()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, wantsActive && OfficeApp.frontmost != nil {
                CGEvent.tapEnable(tap: tap, enable: true)
                FileHandle.standardError.write(Data("[altformac] WARNING: event tap was disabled by macOS, re-enabled\n".utf8))
            }
            return passThrough
        }
        // Our own synthetic key events (shortcut executor) must reach Excel untouched.
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticEvent.userData { return passThrough }

        let start = DispatchTime.now().uptimeNanoseconds
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var input: RawInput?

        switch type {
        case .flagsChanged:
            let others: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskSecondaryFn]
            if keyCode == KeyCodes.optionLeft || keyCode == KeyCodes.optionRight {
                if flags.contains(.maskAlternate) {
                    if optionDownAt == nil && flags.intersection(others).isEmpty {
                        optionDownAt = start
                        otherInputDuringOption = false
                    } else {
                        otherInputDuringOption = true
                    }
                } else if let down = optionDownAt {
                    optionDownAt = nil
                    if !otherInputDuringOption && start - down <= tapWindowNanos { input = .optionTap }
                }
            } else if optionDownAt != nil {
                otherInputDuringOption = true
            }

        case .keyDown:
            if optionDownAt != nil { otherInputDuringOption = true }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat && swallowedKeyDowns.contains(keyCode) { return nil }
            let blocking: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
            if !flags.intersection(blocking).isEmpty {
                input = .other
            } else if keyCode == KeyCodes.escape {
                input = .escape
            } else if keyCode == KeyCodes.delete {
                input = .backspace
            } else if let ch = KeyCodes.character(forKeyCode: keyCode) {
                input = .key(ch, optionHeld: flags.contains(.maskAlternate))
            } else {
                input = .other
            }

        case .keyUp:
            if swallowedKeyDowns.remove(keyCode) != nil { return nil }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if optionDownAt != nil { otherInputDuringOption = true }
            input = .mouse

        default:
            break
        }

        guard let input else { return passThrough }
        let swallow = handler?(input) ?? false
        if swallow, type == .keyDown { swallowedKeyDowns.insert(keyCode) }

        let tookMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        if tookMs > 3 {
            FileHandle.standardError.write(Data(String(format: "[altformac] slow tap callback: %.1f ms\n", tookMs).utf8))
        }
        return swallow ? nil : passThrough
    }
}
