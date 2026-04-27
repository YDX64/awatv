// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AWAtv",
    platforms: [.tvOS(.v17)],
    products: [
        .executable(name: "AWAtv", targets: ["AWAtv"])
    ],
    targets: [
        .executableTarget(
            name: "AWAtv",
            path: "Sources/AWAtv"
        )
    ]
)
