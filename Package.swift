// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BucharestTransit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app, plus any app extension products.
        .library(
            name: "BucharestTransit",
            targets: ["BucharestTransit"]
        ),
        .library(
            name: "TransitLiveActivityWidget",
            targets: ["TransitLiveActivityWidget"]
        )
    ],
    targets: [
        .target(
            name: "BucharestTransit",
            dependencies: ["TransitLiveActivityShared"],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-adhoc_codesign"])
            ]
        ),
        .target(name: "TransitLiveActivityShared"),
        .target(
            name: "TransitLiveActivityWidget",
            dependencies: ["TransitLiveActivityShared"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-adhoc_codesign",
                    "-Xlinker", "-u", "-Xlinker", "_main"
                ])
            ]
        ),
    ]
)
