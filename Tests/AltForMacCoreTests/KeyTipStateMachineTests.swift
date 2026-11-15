import Testing
@testable import AltForMacCore

@Suite struct KeyTipStateMachineTests {
    private func makeMachine() -> KeyTipStateMachine<String> {
        let t = SequenceTrie<String>()
        t.insert("H O I", value: "autofit-col")
        t.insert("H F", value: "font-menu")
        t.insert("H F C", value: "font-color")
        t.insert("W V G", value: "gridlines")
        return KeyTipStateMachine(trie: t)
    }

    @Test func keysPassThroughWhenIdle() {
        let m = makeMachine()
        guard case .passthrough = m.handle(.key("H")) else { Issue.record("expected passthrough"); return }
    }

    @Test func optionTapShowsRootKeys() {
        let m = makeMachine()
        guard case .show(let buffer, let next) = m.handle(.optionTap) else { Issue.record("expected show"); return }
        #expect(buffer == "")
        #expect(next == ["H", "W"])
        #expect(m.isActive)
    }

    @Test func fullSequenceExecutesAndResets() {
        let m = makeMachine()
        _ = m.handle(.optionTap)
        _ = m.handle(.key("W"))
        _ = m.handle(.key("V"))
        guard case .execute(let value, let buffer) = m.handle(.key("G")) else { Issue.record("expected execute"); return }
        #expect(value == "gridlines")
        #expect(buffer == "WVG")
        #expect(!m.isActive)
    }

    @Test func invalidKeyResetsWithError() {
        let m = makeMachine()
        _ = m.handle(.optionTap)
        guard case .invalid(let buffer) = m.handle(.key("Z")) else { Issue.record("expected invalid"); return }
        #expect(buffer == "Z")
        #expect(!m.isActive)
    }

    @Test func ambiguousPrefixWaitsThenCommits() {
        let m = makeMachine()
        _ = m.handle(.optionTap)
        _ = m.handle(.key("H"))
        guard case .show(let buffer, _) = m.handle(.key("F")) else { Issue.record("expected wait"); return }
        #expect(buffer == "HF")
        guard case .execute(let value, _) = m.commitPending() else { Issue.record("expected commit"); return }
        #expect(value == "font-menu")
    }

    @Test func ambiguousPrefixExtendsToLongerSequence() {
        let m = makeMachine()
        _ = m.handle(.optionTap)
        _ = m.handle(.key("H"))
        _ = m.handle(.key("F"))
        guard case .execute(let value, _) = m.handle(.key("C")) else { Issue.record("expected execute"); return }
        #expect(value == "font-color")
    }

    @Test func escapeGoesUpOneLevelThenExits() {
        let m = makeMachine()
        _ = m.handle(.optionTap)
        _ = m.handle(.key("H"))
        guard case .show(let buffer, _) = m.handle(.escape) else { Issue.record("expected show"); return }
        #expect(buffer == "")
        guard case .hide = m.handle(.escape) else { Issue.record("expected hide"); return }
        #expect(!m.isActive)
    }

    @Test func secondOptionTapExits() {
        let m = makeMachine()
        _ = m.handle(.optionTap)
        guard case .hide = m.handle(.optionTap) else { Issue.record("expected hide"); return }
        #expect(!m.isActive)
    }

    @Test func cancelHidesOnlyWhenActive() {
        let m = makeMachine()
        guard case .none = m.handle(.cancel) else { Issue.record("expected none"); return }
        _ = m.handle(.optionTap)
        guard case .hide = m.handle(.cancel) else { Issue.record("expected hide"); return }
    }
}
