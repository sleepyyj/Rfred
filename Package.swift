// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rfred",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rfred", targets: ["Rfred"])
    ],
    targets: [
        .target(
            name: "RfredCore",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .executableTarget(
            name: "Rfred",
            dependencies: ["RfredCore"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library", "-warnings-as-errors"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Vision"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("Quartz"),
            ]
        ),
        .testTarget(
            name: "RfredCoreTests",
            dependencies: ["RfredCore"],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
    ]
)
