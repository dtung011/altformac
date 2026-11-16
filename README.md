# AltForMac

Windows-style Alt key sequences for Excel, Word and PowerPoint on Mac. Tap Option, type `W V G`,
`H O I` or `N V`, and the command runs, including the final letters inside dropdowns that Office for
Mac's built-in KeyTips leave out.

Free and open source (MIT). Microsoft's code is never modified or shipped.

**Current version: 0.1.2** | [Download](https://github.com/dtung011/altformac/releases/latest) | [Changelog](CHANGELOG.md)

## Download and install

Requires macOS 13 (Ventura) or later. The 0.1.2 build is for Apple Silicon; Intel Macs can build from source.

### Option 1: Homebrew

```sh
brew install --cask dtung011/altformac/altformac
```

Update later with `brew upgrade --cask altformac`.

### Option 2: Direct download

1. Open the [latest release](https://github.com/dtung011/altformac/releases/latest) and download
   `AltForMac-<version>.dmg`.
2. Open the DMG and drag **AltForMac** to **Applications**.
3. The app is not notarized yet, so macOS blocks the first launch. Right-click AltForMac in Applications,
   choose **Open**, then **Open** again.

You can check the download against the SHA-256 printed in the release notes:
`shasum -a 256 AltForMac-<version>.dmg`.

### Option 3: Build from source

Needs Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/dtung011/altformac.git
cd altformac
scripts/package.sh        # builds dist/AltForMac.app and the DMG
```

## Set up

1. **Turn off Office's own KeyTips.** In Excel, Word and PowerPoint open Preferences > Accessibility and
   switch off the Option-key KeyTips. Otherwise both react.
2. **Allow Accessibility.** Start AltForMac, then in System Settings > Privacy & Security > Accessibility
   switch it on. Without this it cannot see or drive the menus.
3. **Allow Automation** for each Office app when macOS asks (needed for commands that use AppleScript).

The menu-bar icon shows `⌥` when ready and `⌥!` when it needs permission or an app was slow to respond.

## Use

With Excel, Word or PowerPoint in front:

| Keys | What happens |
| --- | --- |
| tap Option | start a sequence; a small HUD shows the typed keys and the valid next letters |
| letters / digits | follow the Windows sequence, for example `W V G` toggles gridlines |
| Escape | go up one level (exits at the top) |
| Backspace | remove the last letter |
| click, or 5 s idle | cancel |

Holding Option with another key (Option+arrows, Option+Enter) works as normal. Destructive commands keep
Office's own confirmation dialogs.

Sequences live in [mappings/](mappings/): `excel.yaml` (206), `word.yaml` (107), `powerpoint.yaml` (74).

## Uninstall

1. **Quit AltForMac** from its menu-bar icon.
2. **Remove the app.**
   - Installed with Homebrew: `brew uninstall --cask altformac` (add `--zap` to also remove its support files).
     Remove the tap with `brew untap dtung011/altformac` if you no longer want it.
   - Installed from the DMG or built from source: drag **AltForMac** from Applications to the Trash.
3. **Remove its permissions** (optional, they are inert once the app is gone). In System Settings >
   Privacy & Security, open Accessibility and Automation, select AltForMac and click the minus button.
   Or reset them from Terminal: `tccutil reset Accessibility dev.altformac.app` and
   `tccutil reset AppleEvents dev.altformac.app`.
4. **Turn Office's own KeyTips back on** if you want them: Preferences > Accessibility in Excel, Word and
   PowerPoint.

AltForMac installs no background services and writes nothing outside its own app bundle, so there is
nothing else to clean up. If you added it to Login Items, remove it there too (System Settings > General >
Login Items).

## Privacy

- No networking code at all.
- Never reads cell values, formulas, file paths or document content. Accessibility is used only for
  menu, ribbon and focus elements.
- Keys are inspected only while an Office app is frontmost, held in memory only while a sequence is in
  progress, and never written to disk.
- If an app stops responding for 2 s, all keys pass straight through. It never blocks typing.

## Versioning

AltForMac uses [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

- **PATCH** (0.1.0 to 0.1.1): bug fixes and corrected or added mappings.
- **MINOR** (0.1.x to 0.2.0): new features or apps. While the version is below 1.0, a minor release may
  change behavior.
- **MAJOR** (1.0.0 and up): breaking changes, such as a changed mappings format.
- Pre-releases use a suffix, for example `0.2.0-beta.1`, and are marked "Pre-release" on GitHub.

The version is stored in the [VERSION](VERSION) file and stamped into the app by `scripts/package.sh`.
Releases are tagged `vX.Y.Z`.

## Changelog and release notes

- [CHANGELOG.md](CHANGELOG.md): every notable change, newest first.
- [docs/release-notes/](docs/release-notes/): user-facing notes per release (also shown on the
  [Releases page](https://github.com/dtung011/altformac/releases), next to each download).

Maintainers: see [docs/RELEASING.md](docs/RELEASING.md) for how to cut a release.

## Develop

```sh
swift build
scripts/test.sh                      # Swift Testing; plain `swift test` needs full Xcode
swift run AltForMac
swift run mapping-check mappings/excel.yaml
swift run ribbon-dump --out docs/dumps/excel-menubar.json --menu-only
```

Design: [docs/architecture.md](docs/architecture.md). Build rules and conventions: [CLAUDE.md](CLAUDE.md).
Dumps used for validation must contain no workbook content; read the privacy rules in CLAUDE.md first.

## License

MIT, see [LICENSE](LICENSE).
