// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenBlipCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "OpenBlipCore", targets: ["OpenBlipCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "OpenBlipCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OpenBlipCoreTests",
            dependencies: ["OpenBlipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
