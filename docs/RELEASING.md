# Releasing AltForMac

The version number lives in one place: the `VERSION` file. `scripts/package.sh` reads it and stamps it
into the app's Info.plist and the DMG file name.

## Checklist

1. **Pick the number** (see Versioning in the README) and write it to `VERSION`.
2. **Changelog.** In `CHANGELOG.md`, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`, add a fresh empty
   `[Unreleased]` above it, and update the compare links at the bottom.
3. **Release notes.** Copy the previous `docs/release-notes/vX.Y.Z.md` to the new version and edit it.
   Write for users: what changed, how to download, known limitations.
4. **Test.** `scripts/test.sh`, then `swift run mapping-check mappings/excel.yaml` (and `word`, `powerpoint`).
   Ask a human to run the manual test in Excel, since keys cannot be pressed from here.
5. **Build.**
   ```sh
   scripts/package.sh
   # with a Developer ID and notarization:
   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=altformac scripts/package.sh
   ```
   It prints the DMG's sha256. Put it in the release notes.
6. **Tag and publish.**
   ```sh
   git tag -a vX.Y.Z -m "AltForMac X.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z dist/AltForMac-X.Y.Z.dmg dist/AltForMac.dmg \
     --title "AltForMac X.Y.Z" --notes-file docs/release-notes/vX.Y.Z.md
   ```
   Add `--prerelease` for betas such as `v0.2.0-beta.1`.
   Always upload both files. `AltForMac.dmg` (same bytes, fixed name) is what the website's Download
   button links to, via `releases/latest/download/AltForMac.dmg`. Pre-releases are skipped by
   `latest`, so betas do not replace the website download.
7. **Homebrew.** In the `homebrew-altformac` tap, update `version` and `sha256` in `Casks/altformac.rb`,
   run `brew audit --cask --online dtung011/altformac/altformac`, and push.
   Keep `packaging/homebrew/altformac.rb` in this repo in sync.
   Browsers cache the site's video and pictures (GitHub Pages sends `max-age=600`), so when you replace a media
   file, change the `?v=` number on its URL in `site/index.html` (the video, poster and pictures use the version).
8. **Verify** by downloading the DMG from the release page on a clean Mac (or `brew install --cask`) and
   running `AltForMac.app/Contents/MacOS/AltForMac --self-test`.
