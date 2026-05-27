// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FolderQuick",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FolderQuick", targets: ["FolderQuick"])
    ],
    targets: [
        .executableTarget(
            name: "FolderQuick",
            path: "Sources"
        )
    ]
)
