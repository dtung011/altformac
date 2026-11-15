import Foundation

/// Input events the key-capture layer feeds to the state machine.
public enum KeyTipEvent: Equatable {
    /// Option was pressed and released alone, within the tap window (default 350 ms).
    case optionTap
    /// A letter or digit key (physical key mapped to a character by the caller).
    case key(Character)
    case escape
    case backspace
    /// Mouse click, inactivity timeout, or the frontmost app changed.
    case cancel
}

/// What the caller should do after an event.
public enum KeyTipAction<Value> {
    /// Not in KeyTip mode: let the event through to Excel untouched.
    case passthrough
    /// Nothing to do (event swallowed or ignored).
    case none
    /// Update the overlay: typed buffer and the keys that can follow.
    case show(buffer: String, next: [Character])
    /// A complete sequence: run it. Keyboard stays blocked until the executor returns.
    case execute(Value, buffer: String)
    /// The key matched nothing: show an error badge, then the machine is idle.
    case invalid(buffer: String)
    /// Leave KeyTip mode and hide the overlay.
    case hide
}

/// Windows-style KeyTip navigation. Pure logic, no timers: the caller sends
/// `.cancel` on inactivity and calls `commitPending()` when it decides an
/// ambiguous sequence (for example "H F" while "H F C" also exists) has waited long enough.
public final class KeyTipStateMachine<Value> {
    public private(set) var buffer = ""
    public private(set) var isActive = false
    private let trie: SequenceTrie<Value>

    public init(trie: SequenceTrie<Value>) {
        self.trie = trie
    }

    public func handle(_ event: KeyTipEvent) -> KeyTipAction<Value> {
        switch event {
        case .optionTap:
            if isActive {
                reset()
                return .hide
            }
            isActive = true
            buffer = ""
            return .show(buffer: buffer, next: trie.nextKeys(after: ""))

        case .key(let ch):
            guard isActive else { return .passthrough }
            let candidate = buffer + String(ch).uppercased()
            switch trie.lookup(candidate) {
            case .noMatch:
                reset()
                return .invalid(buffer: candidate)
            case .prefix(let next):
                buffer = candidate
                return .show(buffer: buffer, next: next)
            case .exact(let value, let hasLonger):
                if hasLonger {
                    // Ambiguous: wait for another key, like Windows does.
                    buffer = candidate
                    return .show(buffer: buffer, next: trie.nextKeys(after: candidate))
                }
                reset()
                return .execute(value, buffer: candidate)
            }

        case .escape:
            guard isActive else { return .passthrough }
            if buffer.isEmpty {
                reset()
                return .hide
            }
            buffer.removeLast()
            return .show(buffer: buffer, next: trie.nextKeys(after: buffer))

        case .backspace:
            guard isActive else { return .passthrough }
            guard !buffer.isEmpty else { return .none }
            buffer.removeLast()
            return .show(buffer: buffer, next: trie.nextKeys(after: buffer))

        case .cancel:
            guard isActive else { return .none }
            reset()
            return .hide
        }
    }

    /// Runs the pending sequence if the current buffer is a complete one
    /// (used after the ambiguity wait expires). Otherwise does nothing.
    public func commitPending() -> KeyTipAction<Value> {
        guard isActive, !buffer.isEmpty else { return .none }
        if case .exact(let value, _) = trie.lookup(buffer) {
            let done = buffer
            reset()
            return .execute(value, buffer: done)
        }
        return .none
    }

    private func reset() {
        isActive = false
        buffer = ""
    }
}
