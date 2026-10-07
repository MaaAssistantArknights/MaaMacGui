// swift-tools-version: 6.2
import PackageDescription

// Standalone checks for the diagnostic code; no MaaCore binaries or game installation required.
let package = Package(
    name: "PlayCoverDiagnostics",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PlayCoverDiagnostics", path: "MeoAsstMac",
            exclude: [
                "Assets.xcassets", "AppIcon.icon", "Configuration Views", "Main Menu", "Model",
                "Navigation", "Preview Content", "Resources", "Settings", "Task Configurations", "Views",
                "MeoAsstMacApp.swift", "Info.plist", "MAADev.entitlements", "MeoAsstMac.entitlements",
                "Core/Maa.swift", "Core/MaaMessage.swift", "Core/MaaToolClient.swift",
                "Utils/FileLogger.swift", "Utils/HGCalendar.swift",
                "Utils/GitHub.swift", "Utils/MirrorChyan.swift",
                "Utils/OTAFetcher.swift", "Utils/PixelPainter.swift",
                "Utils/ResourceUpdater.swift", "Utils/TaskTimerManager.swift", "Utils/URL+contentType.swift",
                "Utils/URLSession+downloadProgress.swift", "Utils/Binding+semicolonString.swift",
                "Utils/Codeable+JSON.swift", "Utils/FileManager+Atomic.swift", "Utils/UserDefaults+KVO.swift",
            ],
            sources: [
                "Core/MaaToolsClient.swift", "Utils/ByteReader.swift", "Utils/TCPConnection.swift",
                "Diagnostics/PlayCoverDiagnosticModels.swift", "Diagnostics/PlayCoverStaticChecks.swift",
                "Diagnostics/MachOLibraries.swift", "Diagnostics/MaaImageDiagnostics.swift",
                "Diagnostics/ScreenCaptureProbe.swift", "Diagnostics/PlayCoverRuntimeChecks.swift",
                "Diagnostics/PlayCoverAccess.swift", "Diagnostics/PlayCoverDiagnosticModel.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "PlayCoverDiagnosticsTests", dependencies: ["PlayCoverDiagnostics"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
