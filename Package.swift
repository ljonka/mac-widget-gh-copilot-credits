// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopilotCredits",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CopilotCredits", targets: ["CopilotCredits"])],
    targets: [
        .target(name: "CreditsCore"),
        .executableTarget(name: "CopilotCredits", dependencies: ["CreditsCore"]),
        .testTarget(name: "CreditsCoreTests", dependencies: ["CreditsCore"])
    ]
)
