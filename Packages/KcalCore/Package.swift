// swift-tools-version: 6.0
import PackageDescription

// Pure Foundation logic (label parsing, energy maths, API decoding) kept out of the
// app target so it can be unit tested with `swift test` without a simulator.
let package = Package(
    name: "KcalCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KcalCore", targets: ["KcalCore"])
    ],
    targets: [
        .target(name: "KcalCore"),
        .testTarget(name: "KcalCoreTests", dependencies: ["KcalCore"])
    ]
)
