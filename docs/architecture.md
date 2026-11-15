# AltForMac architecture (condensed)

Full version with diagrams: https://claude.ai/artifact/SDidNGHgAVPW4Kmqgg8etE

## Flow

keyboard -> event tap (only while Excel is frontmost) -> KeyTip state machine (trie of Windows
sequences) -> executor runner (tries each step of the command in order) -> Excel for Mac.
Overlay HUD shows typed keys and valid next letters. Health check verifies mapping paths at launch.

## Decisions

| Decision | Choice |
| --- | --- |
| Language/UI | Swift + AppKit/SwiftUI, menu-bar app, outside the Mac App Store |
| Who owns the sequence | AltForMac owns the whole Option sequence; native Excel KeyTips switched off |
| Action execution | Per-command chain: shortcut -> menu bar (AXPress) -> AppleScript -> ribbon (AX) |
| Mapping data | `mappings/excel.yaml`, versioned, loaded at launch; user overrides in `~/Library/Application Support/AltForMac/user.yaml` |
| License | MIT |

## Keyboard state machine

1. Idle. Option pressed and released alone within 350 ms (no other key) enters KeyTip mode and swallows
   Option. Option held with another key passes through (Option+Enter, Option+arrows keep working).
2. Collecting. Each letter or digit is swallowed, appended, and looked up in the trie: exact match with no
   longer sequence executes; prefix keeps waiting and updates the HUD; no match shows an error badge.
3. Ambiguous prefix (for example `H F` and `H F C`): wait for the next key like Windows; `commitPending()`
   runs the shorter one after the wait.
4. Escape goes up one level (exits at the top). Backspace removes the last letter. Click or 5 s idle exits.
5. While executing, the keyboard stays blocked until the executor returns (max 1 s).

Edge cases: pass Option through while editing a cell unless "KeyTips while editing" is on; match physical
key codes so layouts do not matter; optional Left-Option-only trigger; no action during IME composition;
pause with a visible state under macOS Secure Input; re-enable the tap on timeout.

## Executors

| Executor | How | Notes |
| --- | --- | --- |
| shortcut | synthetic key combo via `CGEvent.postToPid` | fastest; breaks if the combo is remapped |
| menu | `AXPress` on a menu-bar item by title path | fast; breaks if renamed or non-English UI |
| applescript | Apple Event to Excel's scripting dictionary | language-independent, stable |
| ribbon | find ribbon tab/control via AX, press, then item | slowest, last resort |

Menu and ribbon lookups resolve against the focused window each run. AX element refs are cached per window
and invalidated on `AXUIElementDestroyed`.

## Mapping file

```yaml
- keys: "W V G"
  label: Toggle gridlines
  ribbon: View > Show > Gridlines
  run:
    - applescript: '...'
    - ribbon: { tab: View, control: Gridlines }
```

Quote `keys`. `min_excel` / `max_excel` limit an entry to Excel builds. CI validates the schema and fails on
duplicate sequences.

## Reliability

Health check at Excel launch/update resolves the 50 most-used mappings and flags failures; fallbacks degrade
speed, not function; CI runs the real event tap against Excel (Insider and Current channels) and checks effects
through AppleScript; diagnostics are opt-in text reports for GitHub issues, never sent automatically.

## Permissions and privacy

Accessibility (event tap, AX), Automation to Excel (AppleScript), Input Monitoring only if required.
No networking code, no reading workbook data, no keystroke logging, kill switch (Option+Option+Escape).
