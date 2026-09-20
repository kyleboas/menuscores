// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuScores",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ScoreKit"),
        .executableTarget(name: "scorefeed-probe", dependencies: ["ScoreKit"]),
        .executableTarget(name: "MenuScoresApp", dependencies: ["ScoreKit"]),
        .testTarget(name: "ScoreKitTests", dependencies: ["ScoreKit"]),
    ]
)
