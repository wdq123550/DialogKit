// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DialogKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DialogKit",
            targets: ["DialogKit"]
        ),
    ],
    dependencies: [
        // SwiftUIPlus 远端目前没有版本 tag，只能跟 main；from: 0.1.0 会解析失败。
        .package(url: "https://github.com/wdq123550/SwiftUIPlus.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DialogKit",
            dependencies: [
                .product(name: "SwiftUIPlus", package: "SwiftUIPlus"),
            ]
        ),
        .testTarget(
            name: "DialogKitTests",
            dependencies: ["DialogKit"]
        ),
    ]
)
