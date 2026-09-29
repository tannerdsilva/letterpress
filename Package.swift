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
        .executable(
            name: "LetterpressExample",
            targets: ["LetterpressExample"]
        ),
    ],
    targets: [
        // ── PDF framework ────────────────────────────────────────
        .target(
            name: "Letterpress"
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
    ]
)
