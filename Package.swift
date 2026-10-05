// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
        name: "DocFetcherCore",
        dependencies: [.target(name: "CSQLite", condition: .when(platforms: [.linux]))],
        path: "Sources/DocFetcherCore"
    ),
    .testTarget(
        name: "DocFetcherCoreTests",
        dependencies: ["DocFetcherCore"],
        path: "Tests/DocFetcherCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "DocFetcherCore", targets: ["DocFetcherCore"]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "DocFetcher",
        dependencies: ["DocFetcherCore"],
        path: "Sources/App",
        resources: [.process("Resources")]
    )
)
products.append(.executable(name: "DocFetcher", targets: ["DocFetcher"]))
#endif

let package = Package(
    name: "DocFetcher",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
