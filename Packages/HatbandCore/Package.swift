// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HatbandCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "HatbandCore", targets: ["HatbandCore"]),
    ],
    dependencies: [
        // Apple's CryptoKit API for Linux. Linked only on Linux; the app links CryptoKit.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "HatbandCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "HatbandCoreTests",
            dependencies: ["HatbandCore"]
        ),
    ]
)
