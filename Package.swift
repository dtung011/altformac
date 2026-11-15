// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AltForMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AltForMac", targets: ["AltForMac"]),
        .executable(name: "ribbon-dump", targets: ["ribbon-dump"]),
        .executable(name: "mapping-check", targets: ["mapping-check"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        // Pure logic: trie, state machine, mapping loader. No AppKit, fully unit-testable.
        .target(
            name: "AltForMacCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        // macOS plumbing shared by the app and the dump tool: Accessibility helpers,
        // executors (shortcut, menu, AppleScript, ribbon), key code table.
        .target(
            name: "AltForMacKit",
            dependencies: ["AltForMacCore"]
        ),
        // Menu-bar app: key capture, controller, HUD.
        .executableTarget(
            name: "AltForMac",
            dependencies: ["AltForMacCore", "AltForMacKit"],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embeds an Info.plist so macOS can attribute Automation (Apple Events) consent
                // to this binary and so the app has no Dock icon. Path is relative to the package root.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", "Sources/AltForMac/Info.plist"])
            ]
        ),
        // Writes Excel's menu bar and ribbon Accessibility tree to JSON (titles only, never cell values).
        .executableTarget(
            name: "ribbon-dump",
            dependencies: ["AltForMacKit"]
        ),
        // Offline validator: checks every mapping step against the dumps in docs/dumps.
        .executableTarget(
            name: "mapping-check",
            dependencies: ["AltForMacCore", "AltForMacKit"]
        ),
        .testTarget(
            name: "AltForMacCoreTests",
            dependencies: ["AltForMacCore"]
        )
    ]
)
