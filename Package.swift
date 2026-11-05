// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Syllapace", defaultLocalization: "en", platforms: [.macOS(.v26)], dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
], targets: [
    .target(name: "SyllapaceKit", resources: [.process("Resources")]),
    .executableTarget(name: "SyllapaceAudit", dependencies: ["SyllapaceKit"]),
    .executableTarget(name: "Syllapace", dependencies: ["SyllapaceKit", .product(name: "Sparkle", package: "Sparkle")],
                      swiftSettings: [.defaultIsolation(MainActor.self)],
                      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "SyllapaceKitTests", dependencies: ["SyllapaceKit"])
])
