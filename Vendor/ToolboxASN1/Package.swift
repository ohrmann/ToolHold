// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "ToolboxASN1", products: [.library(name: "SwiftASN1", targets: ["SwiftASN1"])], targets: [.target(name: "SwiftASN1", path: "Sources/SwiftASN1", exclude: ["CMakeLists.txt", "Docs.docc"])])
