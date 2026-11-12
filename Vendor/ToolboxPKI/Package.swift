// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ToolboxPKI", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "CToolboxPKI", targets: ["CToolboxPKI"])], targets: [
    .binaryTarget(name: "ToolboxCrypto", path: "ToolboxCrypto.xcframework"),
    .target(name: "CToolboxPKI", dependencies: ["ToolboxCrypto"], path: "Sources/CToolboxPKI", publicHeadersPath: "include")
])
