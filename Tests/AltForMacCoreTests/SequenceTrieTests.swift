import Testing
@testable import AltForMacCore

@Suite struct SequenceTrieTests {
    private func makeTrie() -> SequenceTrie<String> {
        let t = SequenceTrie<String>()
        t.insert("H O I", value: "autofit-col")
        t.insert("H O A", value: "autofit-row")
        t.insert("H F", value: "font-menu")
        t.insert("H F C", value: "font-color")
        t.insert("W V G", value: "gridlines")
        return t
    }

    @Test func prefixListsNextKeys() {
        guard case .prefix(let next) = makeTrie().lookup("H O") else { Issue.record("expected prefix"); return }
        #expect(next == ["A", "I"])
    }

    @Test func exactWithoutLonger() {
        guard case .exact(let v, let longer) = makeTrie().lookup("W V G") else { Issue.record("expected exact"); return }
        #expect(v == "gridlines")
        #expect(!longer)
    }

    @Test func exactWithLongerIsAmbiguous() {
        guard case .exact(let v, let longer) = makeTrie().lookup("H F") else { Issue.record("expected exact"); return }
        #expect(v == "font-menu")
        #expect(longer)
    }

    @Test func noMatch() {
        guard case .noMatch = makeTrie().lookup("Q Q") else { Issue.record("expected noMatch"); return }
    }

    @Test func caseAndSpacesIgnored() {
        guard case .exact(let v, _) = makeTrie().lookup("hoi") else { Issue.record("expected exact"); return }
        #expect(v == "autofit-col")
    }

    @Test func rootNextKeys() {
        #expect(makeTrie().nextKeys(after: "") == ["H", "W"])
    }
}
