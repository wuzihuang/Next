// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NextBodySyncCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NextBodySyncCore", targets: ["NextBodySyncCore"])],
    targets: [
        .target(
            name: "NextBodySyncCore",
            path: "NextBody/Services/Band",
            exclude: [
                "BandPresence.swift", "BandService.swift", "BluetoothState.swift",
                "HoopQueue.swift", "MockBand.swift", "OriginDataSync.swift", "VeepooBand.swift",
            ],
            sources: ["HealthSampleMapping.swift"]
        ),
        .testTarget(
            name: "NextBodySyncCoreTests",
            dependencies: ["NextBodySyncCore"],
            path: "NextBodySyncCoreTests"
        ),
    ]
)
