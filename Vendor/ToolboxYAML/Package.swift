// swift-tools-version: 6.0
import PackageDescription

// Pinned libyaml sources distributed by Yams 6.2.2. No remote dependencies.
let package = Package(
    name: "ToolboxYAML",
    products: [.library(name: "CYaml", targets: ["CYaml"])],
    targets: [.target(name: "CYaml", exclude: ["CMakeLists.txt"], cSettings: [.define("YAML_DECLARE_STATIC")])]
)
