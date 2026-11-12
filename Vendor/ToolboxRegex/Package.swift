// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ToolboxRegex", platforms: [.macOS(.v14), .iOS(.v17)],
 products: [.library(name: "CRegex", targets: ["CRegex"])], targets: [
 .target(name: "PCRE2", path: "Sources/PCRE2", publicHeadersPath: "include", cSettings: [.define("HAVE_CONFIG_H"), .define("PCRE2_CODE_UNIT_WIDTH", to: "16"), .define("SUPPORT_PCRE2_16"), .define("SUPPORT_UNICODE"), .define("HAVE_STDINT_H"), .define("HAVE_MEMMOVE")]),
 .target(name: "CRegex", dependencies: ["PCRE2"], path: "Sources/CRegex", publicHeadersPath: "include")])
