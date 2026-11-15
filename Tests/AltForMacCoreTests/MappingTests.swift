import Testing
import Foundation
@testable import AltForMacCore

@Suite struct MappingTests {
    private let sample = """
    - keys: "W V G"
      label: Toggle gridlines
      ribbon: View > Show > Gridlines
      run:
        - applescript: 'tell application "Microsoft Excel" to return 1'
        - ribbon: { tab: View, control: Gridlines }
    - keys: "H O I"
      label: AutoFit column width
      run:
        - menu: [Format, Column, AutoFit Selection]
    """

    @Test func loadsMappingsAndExecutorOrder() throws {
        let mappings = try MappingLoader.load(yaml: sample)
        #expect(mappings.count == 2)
        #expect(mappings[0].keys == "W V G")
        guard case .applescript = mappings[0].run[0] else { Issue.record("first step should be applescript"); return }
        guard case .ribbon(let target) = mappings[0].run[1] else { Issue.record("second step should be ribbon"); return }
        #expect(target.tab == "View")
        #expect(mappings[1].run == [.menu(["Format", "Column", "AutoFit Selection"])])
    }

    @Test func duplicateKeysRejected() {
        let dup = """
        - keys: "H O I"
          label: A
          run:
            - shortcut: "cmd+1"
        - keys: "h o i"
          label: B
          run:
            - shortcut: "cmd+2"
        """
        #expect(throws: MappingError.duplicateKeys("h o i")) {
            try MappingLoader.load(yaml: dup)
        }
    }

    @Test func mappingWithoutExecutorRejected() {
        let empty = """
        - keys: "H O I"
          label: A
          run: []
        """
        #expect(throws: MappingError.self) { try MappingLoader.load(yaml: empty) }
    }

    @Test(arguments: ["excel", "word", "powerpoint"])
    func bundledMappingsFileIsValid(app: String) throws {
        // Tests/AltForMacCoreTests/MappingTests.swift -> repo root -> mappings/<app>.yaml
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let yaml = try String(contentsOf: root.appendingPathComponent("mappings/\(app).yaml"), encoding: .utf8)
        let mappings = try MappingLoader.load(yaml: yaml)
        #expect(!mappings.isEmpty)
        let trie = MappingLoader.buildTrie(mappings)
        // Every app has the Home tab key and the File > Save sequence.
        guard case .exact = trie.lookup("H") else { Issue.record("H (Home tab) should be mapped"); return }
        guard case .exact = trie.lookup("F S") else { Issue.record("F S should be mapped"); return }
    }
}
