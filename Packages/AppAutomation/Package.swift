// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AppAutomation",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "AutomationRuntime", targets: ["AutomationRuntime"]),
        .library(name: "AutomationCLI", targets: ["AutomationCLI"]),
        .library(name: "AutomationHTTP", targets: ["AutomationHTTP"]),
        .executable(name: "app-interface", targets: ["InterfaceGenerator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.13.1"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.12.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", exact: "2.26.0"),
        .package(url: "https://github.com/hummingbird-project/swift-openapi-hummingbird", exact: "2.0.1"),
        .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
        .package(url: "https://github.com/apple/swift-http-types", exact: "1.8.0"),
        .package(url: "https://github.com/apple/swift-log", exact: "1.15.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", exact: "2.12.0"),
    ],
    targets: [
        .target(name: "AutomationRuntime", dependencies: [
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
        ]),
        .target(name: "AutomationCLI", dependencies: ["AutomationRuntime",
            .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .target(name: "AutomationHTTP", dependencies: ["AutomationRuntime",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdCore", package: "hummingbird"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird")]),
        .executableTarget(name: "InterfaceGenerator", dependencies: [
            .product(name: "Yams", package: "Yams")]),
        .testTarget(name: "AutomationTests", dependencies: ["AutomationRuntime", "AutomationCLI", "AutomationHTTP"]),
    ],
    swiftLanguageModes: [.v5]
)
