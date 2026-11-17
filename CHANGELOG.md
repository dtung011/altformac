# Changelog

All notable changes to AltForMac are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) (see "Versioning" in the README).

Each release also has user-facing notes in [docs/release-notes/](docs/release-notes/) and on the
[GitHub Releases page](https://github.com/dtung011/altformac/releases).

## [Unreleased]

Nothing yet.

## [0.1.4] - 2026-11-17

### Added
- Key badges on the ribbon, like the KeyTips in Windows Office, in Excel, Word and PowerPoint. Tap Option and
  every tab shows its letter; type a tab letter and each control of that tab shows the letters to type next
  (for example `M` on Merge & Center, `AC` on Center). When the letters lead to a dropdown (`H O` for Format,
  `H M` for Merge & Center), AltForMac opens Excel's real dropdown and puts a badge on each item, so `I` is on
  "AutoFit Column Width". It opens the dropdown with the Accessibility "show menu" action, never a press, and
  closes it (Escape, only while it is showing) before the chosen command runs. The small HUD list is still used
  inside sub-menus and when the ribbon cannot be read. The menu-bar item
  "Show key badges on the ribbon" switches between badges and the HUD list. Badges are placed from the ribbon's
  titles and positions only; no document content is read.
- `mapping-check <file> --badges <keys>` prints where the badges would go in the running app (dev tool,
  presses nothing).

### Changed
- The promo video on the website is re-recorded with the badges, plus a GIF and a picture of the Format
  dropdown. `scripts/make-promo-clips.py` and `scripts/make-cards.swift` build them.

## [0.1.3] - 2026-11-16

### Security
- A packaged app now loads mappings only from its own bundle. The `ALTFORMAC_MAPPINGS_DIR` variable and the
  folder search are for development builds only, so another program cannot point AltForMac at mapping files
  with its own AppleScript and run them with AltForMac's permissions.
- The app checks that its bundle still matches its code signature before loading mappings. If the installed
  app was modified, it loads nothing, keeps the keyboard tap off and says so in the menu-bar menu.
- The keyboard tap is re-enabled after a macOS timeout only while an Office app is still in front.
- The website's deploy workflow pins its GitHub Actions to exact commits.

### Added
- **Uninstall AltForMac…** in the menu-bar menu: removes AltForMac's privacy permissions (Accessibility,
  Automation), moves the app to the Trash and quits. macOS keeps a deleted app's permissions otherwise.
- `brew uninstall --cask altformac` now quits the app and removes its permissions as well.

### Changed
- The DMG hint now points to System Settings > Privacy & Security > Open Anyway (right-click > Open no longer
  bypasses Gatekeeper on macOS 15 and later).

## [0.1.2] - 2026-11-16

### Fixed
- The DMG window was drawn at double size on macOS 26, hiding the heading and arrow. The background is now a
  single 660 x 400 image and the window is sized to fit it below the title bar.

## [0.1.1] - 2026-11-16

### Added
- App icon (an alt key on a green grid), also used as the disk icon of the DMG.
- Website at https://dtung011.github.io/altformac/ with a demo video.

### Changed
- The DMG now opens as a drag-to-Applications window (background, arrow and positioned icons) instead of a
  plain folder.
- Each release also carries `AltForMac.dmg` (same file, fixed name) so the website's Download button
  always serves the latest version.

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

[Unreleased]: https://github.com/dtung011/altformac/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/dtung011/altformac/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/dtung011/altformac/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/dtung011/altformac/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/dtung011/altformac/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/dtung011/altformac/releases/tag/v0.1.0
