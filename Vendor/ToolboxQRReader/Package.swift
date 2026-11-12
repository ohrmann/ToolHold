// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolboxQRReader", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CQRReader", targets: ["CQRReader"])],
    targets: [
        .target(name: "ZXing", path: "Sources/ZXing", exclude: ["libzueci/README.md"],
                publicHeadersPath: ".", cSettings: [.define("ZUECI_EMBED_NO_TO_ECI")],
                cxxSettings: [.define("ZXING_INTERNAL"), .unsafeFlags(["-O2"])]),
        .target(name: "CQRReader", dependencies: ["ZXing"], path: "Sources/CQRReader", publicHeadersPath: "include")
    ], cxxLanguageStandard: .cxx20)
