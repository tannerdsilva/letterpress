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
        // argument parsing for the `letterpress-md` cli. the exporter and the
        // markdown layer stay dependency-free; only the executable pulls this in.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    ],
    targets: [
        // ── PDF framework ────────────────────────────────────────
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
            ]
        ),

        // ── Example ──────────────────────────────────────────────
        .executableTarget(
            name: "LetterpressExample",
            dependencies: [
                "Letterpress",
            ]
        ),

        // ── Tests ────────────────────────────────────────────────
        .testTarget(
            name: "LetterpressTests",
            dependencies: [
                "Letterpress",
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
            ]
        ),
        // depending on the executable target forces it to build, so the
        // subprocess suite always has a binary to drive.
        .testTarget(
            name: "LetterpressCLITests",
            dependencies: [
                "LetterpressMarkdownCLI",
            ]
        ),
    ]
)