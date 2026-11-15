import Foundation
import AltForMacCore
import AltForMacKit

// mapping-check: validates a mappings file against the app's UI dumps (offline, the app need not run).
//   swift run mapping-check [mappings/excel.yaml] [docs/dumps]    (dump names come from the file name:
//   mappings/word.yaml -> docs/dumps/word-menubar.json and word-ribbon.json)
// Checks: schema + duplicate sequences, menu paths exist in the menu-bar dump, ribbon tab/control/role
// exist in the ribbon dump, AppleScript compiles (never runs), shortcuts parse.
// Dropdown items (`item:`) cannot be checked offline and are counted separately.

let args = Array(CommandLine.arguments.dropFirst())
let yamlPath = args.first ?? "mappings/excel.yaml"
let dumpDir = args.count > 1 ? args[1] : "docs/dumps"

func loadJSON(_ name: String) -> [String: Any] {
    let url = URL(fileURLWithPath: dumpDir).appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("cannot read \(url.path)"); exit(2)
    }
    return obj
}

func children(_ n: [String: Any]) -> [[String: Any]] { n["children"] as? [[String: Any]] ?? [] }

/// Menu bar items and menu items: node -> AXMenu -> items.
func menuItems(of node: [String: Any]) -> [[String: Any]] {
    if node["role"] as? String == "AXMenu" { return children(node) }
    return children(node).first(where: { $0["role"] as? String == "AXMenu" }).map(children) ?? []
}

let stem = URL(fileURLWithPath: yamlPath).deletingPathExtension().lastPathComponent
let menuBar = loadJSON("\(stem)-menubar.json")["menuBar"] as? [String: Any] ?? [:]
let ribbon = loadJSON("\(stem)-ribbon.json")["ribbonTabs"] as? [String: Any] ?? [:]

func menuPathExists(_ path: [String]) -> Bool {
    var level = children(menuBar)
    var found = false
    for wanted in path {
        guard let m = level.first(where: { ($0["title"] as? String).map { MenuNavigator.titlesMatch($0, wanted) } ?? false }) else { return false }
        found = true
        level = menuItems(of: m)
    }
    return found
}

let roleNames = RibbonExecutor.roles
/// Every control in a tab whose title matches (and role, if given).
func ribbonMatches(_ t: RibbonTarget) -> [[String: Any]]? {
    guard let tab = ribbon[t.tab] as? [String: Any] else { return nil }
    let wanted = RibbonExecutor.norm(t.control)
    let wantedRole = t.role.flatMap { roleNames[$0.lowercased()] }
    var hits: [[String: Any]] = []
    func walk(_ n: [String: Any]) {
        let label = (n["title"] as? String) ?? (n["description"] as? String)
        let role = n["role"] as? String ?? ""
        if let label, RibbonExecutor.norm(label) == wanted,
           wantedRole.map({ $0 == role }) ?? RibbonExecutor.pressable.contains(role) { hits.append(n) }
        children(n).forEach(walk)
    }
    walk(tab)
    return hits
}

let mappings: [Mapping]
do {
    let yaml = try String(contentsOfFile: yamlPath, encoding: .utf8)
    mappings = try MappingLoader.load(yaml: yaml)
} catch {
    print("FAIL: \(yamlPath) did not load: \(error)"); exit(1)
}

var problems: [String] = []
var counts = ["shortcut": 0, "menu": 0, "applescript": 0, "ribbon": 0, "ribbon item (unchecked)": 0]
var unreachable: [String] = []

for m in mappings {
    var hasWorkingCandidate = false
    for step in m.run {
        switch step {
        case .shortcut(let spec):
            counts["shortcut"]! += 1
            if (try? ShortcutExecutor.parse(spec)) == nil { problems.append("\(m.keys): bad shortcut '\(spec)'") }
            else { hasWorkingCandidate = true }
        case .menu(let path):
            counts["menu"]! += 1
            if menuPathExists(path) { hasWorkingCandidate = true }
            else { problems.append("\(m.keys): menu path not in dump: \(path.joined(separator: " > "))") }
        case .applescript(let source):
            counts["applescript"]! += 1
            if let script = NSAppleScript(source: source) {
                var err: NSDictionary?
                if script.compileAndReturnError(&err) { hasWorkingCandidate = true }
                else { problems.append("\(m.keys): AppleScript does not compile: \(err?[NSAppleScript.errorMessage] ?? "?")") }
            }
        case .ribbon(let target):
            counts["ribbon"]! += 1
            if target.item != nil { counts["ribbon item (unchecked)"]! += 1 }
            if target.control.isEmpty {
                if ribbon[target.tab] != nil { hasWorkingCandidate = true }
                else { problems.append("\(m.keys): ribbon tab not in dump: \(target.tab)") }
            } else if let hits = ribbonMatches(target), !hits.isEmpty {
                if hits.count > 1 && target.role == nil {
                    problems.append("\(m.keys): ribbon control is ambiguous (\(hits.count) matches), add a role: \(target.tab) > \(target.control)")
                } else if (target.menu == true || target.item != nil),
                          !((hits[0]["actions"] as? [String]) ?? []).contains("AXShowMenu") {
                    problems.append("\(m.keys): \(target.control) has no dropdown (AXShowMenu), cannot use menu: true")
                } else { hasWorkingCandidate = true }
            } else {
                problems.append("\(m.keys): ribbon control not in dump: \(target.tab) > \(target.control)\(target.role.map { " [\($0)]" } ?? "")")
            }
        }
    }
    if !hasWorkingCandidate { unreachable.append("\(m.keys) (\(m.label))") }
}

print("\(mappings.count) mappings, steps: \(counts)")
if !problems.isEmpty { print("\nPROBLEMS (\(problems.count)):"); problems.forEach { print("  " + $0) } }
if !unreachable.isEmpty { print("\nNO RESOLVABLE STEP (\(unreachable.count)):"); unreachable.forEach { print("  " + $0) } }
exit(problems.isEmpty && unreachable.isEmpty ? 0 : 1)
