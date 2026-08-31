// swift-tools-version: 6.0
// SPDX-License-Identifier: MPL-2.0

import PackageDescription

let package = Package(
    name: "SignalSieve",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SignalSieveCore", targets: ["SignalSieveCore"]),
        .executable(name: "SignalSieve", targets: ["SignalSieve"]),
        .executable(name: "SignalSievePixelBaseline", targets: ["SignalSievePixelBaseline"]),
        .executable(name: "SignalSievePixelSpectral", targets: ["SignalSievePixelSpectral"])
    ],
    targets: [
        .target(
            name: "CSignalSieveZip",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "SignalSieveCore",
            dependencies: ["CSignalSieveZip"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "SignalSieve",
            dependencies: ["SignalSieveCore"]
        ),
        .executableTarget(
            name: "SignalSievePixelBaseline",
            dependencies: ["SignalSieveCore"]
        ),
        .executableTarget(
            name: "SignalSievePixelSpectral",
            dependencies: ["SignalSieveCore"]
        ),
        .testTarget(
            name: "SignalSieveCoreTests",
            dependencies: ["SignalSieveCore"]
        ),
        .testTarget(
            name: "SignalSieveAppTests",
            dependencies: ["SignalSieve"]
        )
    ]
)
