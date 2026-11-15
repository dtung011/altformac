#!/bin/sh
# Runs the unit tests with only the Command Line Tools installed (no Xcode, so no XCTest).
# With full Xcode, plain `swift test` also works.
set -e
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
cd "$(dirname "$0")/.."
exec swift test --enable-swift-testing --disable-xctest \
  -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib "$@"
