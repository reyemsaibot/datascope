// swift-tools-version: 6.0
import PackageDescription
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let package = Package(
    name: "DataScope", platforms: [.macOS(.v14)],
    products: [.executable(name: "DataScope", targets: ["DataScope"]),
               .executable(name: "profile", targets: ["ProfileCLI"])],
    targets: [
        .systemLibrary(name: "CDuckDB"),
        .target(name: "ProfilingCore", dependencies: ["CDuckDB"],
                linkerSettings: [.unsafeFlags(["-L", root + "/Vendor", "-Xlinker", "-rpath", "-Xlinker", root + "/Vendor"])]),
        .executableTarget(name: "DataScope", dependencies: ["ProfilingCore"]),
        .executableTarget(name: "ProfileCLI", dependencies: ["ProfilingCore"]),
        .testTarget(name: "ProfilingCoreTests", dependencies: ["ProfilingCore"])
    ])
