// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "letterpress",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Letterpress",
            targets: ["Letterpress"]
        ),
        .library(
            name: "LetterpressMarkdown",
            targets: ["LetterpressMarkdown"]
        ),
        .executable(
            name: "letterpress-md",
            targets: ["LetterpressMarkdownCLI"]
        ),
        .executable(
            name: "LetterpressExample",
            targets: ["LetterpressExample"]
        ),
    ],
    dependencies: [
        // file i/o for the two executables and the test harness. the exporter
        // and the markdown layer stay dependency-free AND Foundation-free: the
        // core hands back `[UInt8]` and never touches the filesystem, so the
        // only targets that open a file are the ones a user actually runs.
        .package(url: "https://github.com/apple/swift-system.git", from: "1.8.1"),
        // argument parsing for the `letterpress-md` cli.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    ],
    targets: [
        // ── PDF framework (no dependencies, no Foundation) ───────
        .target(
            name: "Letterpress"
        ),

        // ── markdown → pdf layer (zero-dependency, pure consumer) ─
        .target(
            name: "LetterpressMarkdown",
            dependencies: [
                "Letterpress",
            ]
        ),

        // ── CLI ──────────────────────────────────────────────────
        .executableTarget(
            name: "LetterpressMarkdownCLI",
            dependencies: [
                "Letterpress",
                "LetterpressMarkdown",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),

        // ── Example ──────────────────────────────────────────────
        .executableTarget(
            name: "LetterpressExample",
            dependencies: [
                "Letterpress",
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),

        // ── Tests ────────────────────────────────────────────────
        // the subprocess + scratch-file harness the suites share. a target
        // rather than a file inside one test target because three of them need
        // it and test targets cannot import each other. not a product, so it
        // ships nowhere.
        .target(
            name: "LetterpressTestSupport",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "LetterpressTests",
            dependencies: [
                "Letterpress",
                "LetterpressTestSupport",
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
        // deliberately does NOT use @testable: this target proves the public
        // surface is enough to implement a `Mark` and a `MarkModifier` from
        // outside the module, and fails the build if that ever regresses.
        .testTarget(
            name: "LetterpressPublicAPITests",
            dependencies: [
                "Letterpress",
            ]
        ),
        .testTarget(
            name: "LetterpressMarkdownTests",
            dependencies: [
                "Letterpress",
                "LetterpressMarkdown",
                "LetterpressTestSupport",
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
        // depending on the executable target forces it to build, so the
        // subprocess suite always has a binary to drive.
        .testTarget(
            name: "LetterpressCLITests",
            dependencies: [
                "LetterpressMarkdownCLI",
                "LetterpressTestSupport",
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
    ]
)