// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotosOrganizer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PhotosOrganizer", targets: ["PhotosOrganizer"]),
        .library(name: "PhotosOrganizerCore", targets: ["PhotosOrganizerCore"]),
    ],
    targets: [
        // Scanning, metadata and file operations. No SwiftUI/AppKit, so it can be unit-tested.
        .target(name: "PhotosOrganizerCore"),
        // SwiftUI desktop app.
        .executableTarget(name: "PhotosOrganizer", dependencies: ["PhotosOrganizerCore"]),
        .testTarget(name: "PhotosOrganizerCoreTests", dependencies: ["PhotosOrganizerCore"]),
    ]
)
