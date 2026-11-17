import Testing
import Foundation
@testable import AltForMacCore

@Suite struct BadgePlanTests {
    private func tab(_ keys: String, _ name: String) -> Mapping {
        Mapping(keys: keys, label: "\(name) tab", ribbon: name, run: [.ribbon(RibbonTarget(tab: name, control: ""))])
    }

    private func control(_ keys: String, _ path: String, control: String, role: String? = nil, item: String? = nil) -> Mapping {
        Mapping(keys: keys, label: path, ribbon: path,
                run: [.ribbon(RibbonTarget(tab: "Home", control: control, item: item, role: role))])
    }

    private var sample: [Mapping] {
        [
            tab("H", "Home"), tab("N", "Insert"),
            control("H M C", "Home > Merge & Center > Merge & Center", control: "Merge & Center", role: "menubutton", item: "Merge & Center"),
            control("H M A", "Home > Merge & Center > Merge Across", control: "Merge & Center", role: "menubutton", item: "Merge Across"),
            control("H M M", "Home > Merge & Center > Merge Cells", control: "Merge & Center", role: "menubutton", item: "Merge Cells"),
            control("H A C", "Home > Center", control: "Center"),
            control("H O I", "Home > Format > AutoFit", control: "Format", role: "menubutton", item: "AutoFit Column Width"),
            control("H O W", "Home > Format > Column Width", control: "Format", role: "menubutton", item: "Column Width"),
            Mapping(keys: "H P", label: "Percent style", ribbon: "Home > Percent Style", run: [.shortcut("cmd+shift+5")])
        ]
    }

    @Test func nothingTypedGivesOneBadgePerTab() {
        let badges = BadgePlanner.plan(mappings: sample, buffer: "")
        #expect(badges == [
            RibbonBadge(text: "H", tab: "Home", control: ""),
            RibbonBadge(text: "N", tab: "Insert", control: "")
        ])
    }

    @Test func tabLetterGivesTheSharedLettersOfEachControl() {
        let badges = BadgePlanner.plan(mappings: sample, buffer: "H")
        let byControl = Dictionary(uniqueKeysWithValues: badges.map { ($0.control, $0.text) })
        #expect(byControl["Merge & Center"] == "M")   // H M C / H M A / H M M share "M"
        #expect(byControl["Format"] == "O")           // H O I / H O W share "O"
        #expect(byControl["Center"] == "AC")          // a single command shows both letters
        #expect(byControl["Percent Style"] == "P")    // no ribbon step: control comes from the ribbon path
    }

    @Test func typedLettersAreRemovedFromTheBadge() {
        let badges = BadgePlanner.plan(mappings: sample, buffer: "HA")
        #expect(badges == [RibbonBadge(text: "C", tab: "Home", control: "Center", role: nil)])
    }

    @Test func dropdownLevelHasNoBadges() {
        // After H M the choices (C, A, M) are items inside the open dropdown, not ribbon controls.
        #expect(BadgePlanner.plan(mappings: sample, buffer: "HM").isEmpty)
    }

    @Test func unknownTabLetterHasNoBadges() {
        #expect(BadgePlanner.plan(mappings: sample, buffer: "Z").isEmpty)
    }

    @Test func roleIsKeptSoEqualTitlesStaySeparate() {
        let maps = [
            tab("H", "Home"),
            control("H F A", "Home > Format > A", control: "Format", role: "menubutton"),
            control("H F B", "Home > Format > B", control: "Format", role: "popupbutton")
        ]
        let badges = BadgePlanner.plan(mappings: maps, buffer: "H")
        #expect(badges.count == 2)
    }

    @Test func roleLessMappingMergesIntoSameControlButNotAnotherWithTheSameTitle() {
        let maps = [
            tab("H", "Home"),
            control("H F I", "Home > Fill", control: "Fill"),                                   // menu opener, no role
            control("H F I D", "Home > Fill > Down", control: "Fill", role: "menubutton", item: "Down"),
            control("H F P", "Home > Format Painter", control: "Format", role: "checkbox"),
            control("H O I", "Home > Format > AutoFit", control: "Format")                       // the dropdown
        ]
        let badges = BadgePlanner.plan(mappings: maps, buffer: "H")
        #expect(badges.filter { $0.control == "Fill" }.map(\.text) == ["FI"])
        #expect(Set(badges.filter { $0.control == "Format" }.map(\.text)) == ["FP", "OI"])
    }

    @Test func dropdownPlanNamesTheItemsOfTheOpenedControl() {
        let plan = BadgePlanner.dropdown(mappings: sample, buffer: "HM")
        #expect(plan?.control == "Merge & Center")
        #expect(plan?.items.map(\.text) == ["C", "A", "M"])
        #expect(plan?.items.map(\.item) == ["Merge & Center", "Merge Across", "Merge Cells"])
    }

    @Test func noDropdownWhileSeveralControlsRemain() {
        #expect(BadgePlanner.dropdown(mappings: sample, buffer: "H") == nil)
        #expect(BadgePlanner.dropdown(mappings: sample, buffer: "") == nil)
    }

    @Test func subMenuGetsOneBadgeForTheWholeSubMenu() {
        let maps = [
            tab("H", "Home"),
            control("H O I", "Home > Format > AutoFit Column Width", control: "Format"),
            control("H O U R", "Home > Format > Hide & Unhide > Hide Rows", control: "Format"),
            control("H O U C", "Home > Format > Hide & Unhide > Hide Columns", control: "Format")
        ]
        let plan = BadgePlanner.dropdown(mappings: maps, buffer: "HO")
        #expect(plan?.items == [DropdownBadge(text: "I", item: "AutoFit Column Width"),
                                DropdownBadge(text: "U", item: "Hide & Unhide")])
    }
}
