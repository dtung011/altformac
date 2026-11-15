import Foundation

/// Result of looking a typed key buffer up in the trie.
public enum TrieLookup<Value> {
    /// Nothing starts with this buffer.
    case noMatch
    /// The buffer is only a prefix; `next` lists the keys that can follow, sorted.
    case prefix(next: [Character])
    /// The buffer is a complete sequence. `hasLonger` is true when a longer
    /// sequence starts with it too (Windows then waits for the next key).
    case exact(Value, hasLonger: Bool)
}

private func normalizeKeys(_ keys: String) -> [Character] {
    Array(keys.uppercased().filter { !$0.isWhitespace })
}

/// Prefix tree of Windows-style Alt sequences such as "W V G" or "H O I".
public final class SequenceTrie<Value> {
    private final class Node {
        var children: [Character: Node] = [:]
        var value: Value?
    }

    private let root = Node()

    public init() {}

    /// Adds or replaces a sequence. Spaces and case are ignored: "h o i" == "HOI".
    public func insert(_ keys: String, value: Value) {
        var node = root
        for ch in normalizeKeys(keys) {
            if let next = node.children[ch] {
                node = next
            } else {
                let created = Node()
                node.children[ch] = created
                node = created
            }
        }
        node.value = value
    }

    public func lookup(_ keys: String) -> TrieLookup<Value> {
        var node = root
        for ch in normalizeKeys(keys) {
            guard let next = node.children[ch] else { return .noMatch }
            node = next
        }
        if let value = node.value {
            return .exact(value, hasLonger: !node.children.isEmpty)
        }
        if node.children.isEmpty { return .noMatch }
        return .prefix(next: node.children.keys.sorted())
    }

    /// Keys that can follow `keys`, for the overlay HUD. Empty if none.
    public func nextKeys(after keys: String) -> [Character] {
        var node = root
        for ch in normalizeKeys(keys) {
            guard let next = node.children[ch] else { return [] }
            node = next
        }
        return node.children.keys.sorted()
    }
}
