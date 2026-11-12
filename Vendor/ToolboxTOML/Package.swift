// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ToolboxTOML", products: [.library(name: "CToml", targets: ["CToml"])],
    targets: [.target(name: "CToml")], cLanguageStandard: .c17)
