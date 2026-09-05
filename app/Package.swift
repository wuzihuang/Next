// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NextBodySyncCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NextBodySyncCore", targets: ["NextBodySyncCore"])],
    targets: [
        .target(
            name: "NextBodyLocalData",
            path: "NextBody/Services/Storage",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "LocalDataTests",
            dependencies: ["NextBodyLocalData"],
            path: "tests/LocalDataTests"
        ),
        .target(
            name: "NextBodyChatCore",
            path: "NextBody/Features/Chat",
            exclude: ["ChatDetailView.swift", "ChatHistorySheet.swift", "ChatModels.swift", "ChatStore.swift"],
            sources: ["ChatArchive.swift"]
        ),
        .testTarget(
            name: "NextBodyChatTests",
            dependencies: ["NextBodyChatCore"],
            path: "NextBodyChatTests"
        ),
        .target(
            name: "NextBodySyncCore",
            path: "NextBody/Services/Band",
            exclude: [
                "BandPresence.swift", "BandReadiness.swift", "BandLiveLifecycle.swift", "BandService.swift", "BluetoothState.swift",
                "HoopQueue.swift", "LiveReadout.swift", "MockBand.swift",
                "OpticalAutoSwitch.swift", "OriginDataSync.swift", "VeepooBand.swift",
            ],
            sources: [
                "AutoMeasurementIntervalPolicy.swift",
                "AutoMeasurementSwitchFallback.swift",
                "BodyBatteryEngine.swift",
                "BandDomainSyncState.swift",
                "AIFreshnessPolicy.swift",
                "SessionBoundTransport.swift",
                "DailyDirectionPolicy.swift",
                "HealthSampleMapping.swift",
                "MealResponseIndex.swift",
                "HomeLaunchPolicy.swift",
                "LaunchGate.swift",
                "BandReadinessFlight.swift",
                "SportSessionLifetime.swift",
                "ActivityEnergyPolicy.swift",
                "SportMetricAccumulator.swift",
                "SportLiveInfo.swift",
                "BandSportSubscription.swift",
                "BandLivePolicy.swift",
                "BandMeasurementReply.swift",
                "BandHealthLight.swift",
                "BandPersonalInfoPolicy.swift",
                "VitalSample.swift",
                "VitalsTimelinePolicy.swift",
            ]
        ),
        .testTarget(
            name: "NextBodySyncCoreTests",
            dependencies: ["NextBodySyncCore"],
            path: "NextBodySyncCoreTests"
        ),
    ]
)
