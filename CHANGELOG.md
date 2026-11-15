# Changelog

All notable changes to AltForMac are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) (see "Versioning" in the README).

Each release also has user-facing notes in [docs/release-notes/](docs/release-notes/) and on the
[GitHub Releases page](https://github.com/dtung011/altformac/releases).

## [Unreleased]

Nothing yet.

## [0.1.0] - 2026-11-15

### Added
- Menu-bar app (no Dock icon). Tap Option in Excel, Word or PowerPoint, then type a Windows Alt sequence
  such as `W V G`, `H O I` or `N V`. Escape goes up one level, Backspace removes a letter.
- Mappings for Excel (206 sequences), Word (107) and PowerPoint (74) in `mappings/*.yaml`, checked
  against dumps of each app's menus and ribbon (Excel for Mac 16.104).
- Executors that try the fastest, most stable step first and fall through on failure:
  shortcut, menu bar, AppleScript, ribbon.
- On-screen HUD under the ribbon showing the typed keys and the valid next letters.
- Error badge instead of a wrong click when a menu or ribbon item cannot be found.
- Pass-through of all keys, with a warning in the menu-bar icon, when an Office app stops responding for 2 s.
- `AltForMac --self-test` to verify a packaged build loads its mappings.
- Dropdown items (Borders, Merge & Center, Change Case and more) are reachable by their last letter, opened
  with the Accessibility menu action so nothing is applied by accident.
- Uninstall instructions in the README.
- Developer tools: `ribbon-dump` (writes menu and ribbon titles to JSON, never workbook content) and
  `mapping-check` (validates a mappings file against those dumps).
- `scripts/package.sh` builds a signed `.app` and a `.dmg`; Homebrew cask in `packaging/homebrew/`.

### Known limitations
- The DMG is not notarized yet. On first launch, right-click the app and choose Open (or install with
  Homebrew, whose cask clears the quarantine flag).
- The 0.1.0 DMG is built for Apple Silicon. Intel Macs can build from source.
- Option is not skipped while you are editing a cell.
- No user overrides file and no kill switch yet.

[Unreleased]: https://github.com/dtung011/altformac/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dtung011/altformac/releases/tag/v0.1.0
