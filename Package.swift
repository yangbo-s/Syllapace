// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Syllapace", platforms: [.macOS(.v26)], targets: [
    .target(name: "SyllapaceKit"),
    .executableTarget(name: "Syllapace", dependencies: ["SyllapaceKit"], swiftSettings: [.defaultIsolation(MainActor.self)]),
    .testTarget(name: "SyllapaceKitTests", dependencies: ["SyllapaceKit"])
])
