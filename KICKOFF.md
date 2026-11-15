# Start the build

In Terminal on your Mac:

```
cd ~/Documents/altformac
claude
```

Then paste this as your first message:

> Read CLAUDE.md and docs/architecture.md. Run `swift build` and `swift test` and fix anything that
> doesn't compile in the scaffold (it was written without a Swift toolchain). Then implement Phase 0
> from CLAUDE.md step by step. Check the current Excel for Mac menus with the ribbon dumper before
> trusting mappings/excel.yaml, and correct it. Stop and tell me when I need to grant permissions or
> press keys in Excel for a manual test.

Tips:

- Have Excel open with any workbook before the first manual test.
- Turn off Option-key KeyTips in Excel > Preferences > Accessibility first.
- Requires Xcode (or the Command Line Tools) for `swift`: run `xcode-select --install` if `swift` is missing.
