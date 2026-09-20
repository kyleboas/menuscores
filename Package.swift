// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuScores",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ScoreKit"),
        .target(name: "MenuScoresUI", dependencies: ["ScoreKit"]),
        .executableTarget(name: "scorefeed-probe", dependencies: ["ScoreKit"]),
        .executableTarget(name: "render-preview", dependencies: ["MenuScoresUI", "ScoreKit"]),
        .executableTarget(name: "MenuScoresApp", dependencies: ["MenuScoresUI", "ScoreKit"]),
        .testTarget(name: "ScoreKitTests", dependencies: ["ScoreKit"]),
    ]
)
