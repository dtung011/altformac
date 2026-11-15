# AltForMac: build brief for Claude Code

AltForMac is a small open-source macOS menu-bar app that makes Windows Excel Alt sequences
(W V G, H O I, N V ...) work end to end in real Excel for Mac, including the last letter
inside dropdowns that Excel's native KeyTips leave out. Microsoft's code is never modified or
shipped. The app watches the keyboard while Excel is frontmost and drives Excel through the
Accessibility API (AX), menu commands and AppleScript.

Full design: `docs/architecture.md`. The name must not contain "Excel", "Word" or "PowerPoint".

## Rules (do not break)

- Never read cell values, formulas, file paths or any workbook content. AX code may only query
  menu, ribbon and focus elements.
- No networking code anywhere. Do not link or import networking frameworks (URLSession, Network, etc.).
- Never log keystrokes to disk. Keys are only inspected while Excel is frontmost, and only kept
  in memory while a KeyTip sequence is in progress.
- Executor order is fastest and most stable first: shortcut -> menu -> applescript -> ribbon.
  A failed step falls through to the next; a failed lookup shows an error badge, never a wrong click.
- Resolve menu and ribbon items against the focused window on every run (several workbooks may be open).
- Keep `AltForMacCore` free of AppKit so it stays unit-testable without Excel.
- Never AXPress a ribbon dropdown or split button to "open" it: AXPress runs its default action on the
  user's selection (Borders applies a border). Open dropdowns with AXShowMenu. Probing tools must not
  press anything but ribbon tab buttons on a workbook the user has open.
- Dumps must contain no workbook content: skip status bar (Sum/Average), Undo/Redo/Repeat titles
  (they quote typed text), Recent Items/Open Recent/Window menus (file names). Check dumps before keeping them.
- Destructive commands keep Excel's own confirmation dialogs. Never auto-confirm.
- If AX calls stall for 2 s, pass all keys through and show a warning. Never block typing.
- Distribute outside the Mac App Store (sandboxed apps cannot control other apps through AX).

## Apps

Excel, Word and PowerPoint (`OfficeApp` in AltForMacKit), one mappings file each in `mappings/<stem>.yaml`.
Every file is validated against that app's dumps: `swift run mapping-check mappings/word.yaml` reads
`docs/dumps/word-menubar.json` and `word-ribbon.json`. Regenerate dumps with
`ribbon-dump --app word --menu-only --out docs/dumps/word-menubar.json` and
`ribbon-dump --app word --menu-only --ribbon-tabs --depth 14 --out docs/dumps/word-ribbon.json`
(the app must be open with an empty document; read the privacy rules above before keeping a dump).

## Current state

Builds clean with Swift 6.3 (Command Line Tools only, no Xcode). Tests use Swift Testing, not XCTest,
because XCTest needs full Xcode: run them with `scripts/test.sh`.

- `Sources/AltForMacCore`: `SequenceTrie`, `KeyTipStateMachine`, `Mapping` + YAML loader (Yams).
- `Sources/AltForMacKit`: `AX` (AXNode wrapper, permission, ExcelApp), `MenuNavigator`, `TreeDumper`,
  `KeyCodes`, `Executors` (shortcut, menu, applescript; ribbon is a stub that fails cleanly), `CommandRunner`.
- `Sources/AltForMac`: `KeyCapture` (CGEventTap, enabled only while Excel is frontmost), `Overlay` (HUD),
  `AppController` (wiring, timers, latency logs to stderr), `main.swift`, embedded `Info.plist`.
- `Sources/ribbon-dump`: writes Excel's menu bar / window AX tree to JSON (`docs/dumps/`).
- `mappings/excel.yaml`: three sequences; verify against the dump before trusting.
- Not done yet: skipping Option while editing a cell, ribbon executor, user.yaml overrides, kill switch.

## Phase 0: spike (goal of this session)

Prove that these three sequences work from the real Option key, under 150 ms, in current Excel for Mac:
`W V G` (toggle gridlines), `H O I` (AutoFit column width), `N V` (Insert PivotTable).

1. Build and test the scaffold; fix compile errors.
2. `KeyCapture`: CGEventTap that is active only while Excel (`com.microsoft.Excel`) is frontmost
   (NSWorkspace activation observer enables and disables handling). Detect an Option tap (down and
   up within 350 ms, no other key between) and feed `KeyTipEvent`s to the state machine. Swallow keys
   while KeyTip mode is on. Match physical key codes, not typed characters. Re-enable the tap on
   `tapDisabledByTimeout`. Do the minimum work in the callback; hand execution to a background queue.
3. `AXKit`: helpers to find the frontmost Excel window, press a menu-bar item by title path,
   and a CLI/tool target `ribbon-dump` that writes Excel's menu bar and ribbon AX tree to JSON.
4. Executors: `applescript` (NSAppleScript via Apple Events to Excel), `menu` (AXPress by title path),
   and a runner that tries steps in order and logs which one worked.
5. Run the ribbon dumper against the installed Excel and CORRECT `mappings/excel.yaml` to the real
   menu titles. Add a note of the Excel version used.
6. Latency probe: log time from Option release to HUD shown, and from last key to action finished.
7. Minimal HUD: borderless non-activating NSPanel under the ribbon showing the typed keys and next
   valid letters with labels.

Exit gate: all three sequences work, each under 150 ms for menu/AppleScript-backed actions,
with Excel's native KeyTips switched off.

## Manual setup the human must do

- Excel > Preferences > Accessibility: turn OFF the Option-key KeyTips (otherwise both react).
- System Settings > Privacy & Security > Accessibility: allow the built AltForMac binary (and the
  terminal you launch it from while developing). Automation permission for Excel is asked on first
  AppleScript use. Input Monitoring only if macOS demands it for the event tap.
- Ask the human to run the final manual test; you cannot press keys in Excel yourself.

## Commands

```
swift build
scripts/test.sh          # plain `swift test` needs Xcode (XCTest); this works with Command Line Tools
swift run AltForMac
swift run ribbon-dump --out docs/dumps/excel-menubar.json --menu-only
```

## Later phases (not now)

v0.1: 300 mappings, ribbon fallback, onboarding, Homebrew cask. v0.5: learn mode, health check + CI,
ribbon badges, localized menus, PPPC profile. 1.0+: Word and PowerPoint, auto-update build.
