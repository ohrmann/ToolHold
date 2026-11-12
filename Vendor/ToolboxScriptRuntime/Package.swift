// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ToolboxScriptRuntime", platforms: [.macOS(.v14), .iOS(.v17)],
 products: [.library(name: "CQuickJS", targets: ["CQuickJS"])], targets: [
 .target(name: "CQuickJS", path: "Sources/CQuickJS", publicHeadersPath: "include",
 cSettings: [.unsafeFlags(["-O2"]), .define("_GNU_SOURCE"), .define("CONFIG_VERSION", to: "\"2026-06-04\"")])])
