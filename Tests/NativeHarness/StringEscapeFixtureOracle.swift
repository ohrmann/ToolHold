import Foundation

/// Development-only oracle generator. All inputs are fixed synthetic fixtures, never app/user input.
/// Compile with StringEscapeTypes.swift and StringEscapeProcessor.swift, then run the generated
/// static Swift and JavaScript programs with development compilers (not from the application).
@main struct StringEscapeFixtureOracle {
    static func main() throws {
        let directory = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var text = "e\u{301}é😀\r\n\t\\(name) ${name} \" ' </script>"
        for value in Array(0...255)+[0x061C,0x200F,0x2028,0x202E,0x2069,0xFFFF,0x10FFFF] {
            text.unicodeScalars.append(Unicode.Scalar(value)!)
        }
        let expected = text.utf16.map(String.init).joined(separator:",")
        var swift = "import Foundation\nlet expected: [UInt16] = [\(expected)]\n"
        var javascript = "const expected = [\(expected)];\n"
        for ascii in [false,true] {
            let result = StringEscapeProcessor.process(text,options:.init(language:.swift,nonASCII:ascii))
            let literal = result.artifact!.text
            swift += "precondition(Array((\(literal)).utf16) == expected)\n"
            for quote in StringEscapeQuote.allCases {
                let js = StringEscapeProcessor.process(text,options:.init(language:.javascript,quote:quote,nonASCII:ascii)).artifact!.text
                javascript += "{ const s = \(js); if (s.length !== expected.length || expected.some((u,i)=>s.charCodeAt(i)!==u)) throw new Error('UTF16 mismatch'); }\n"
            }
        }
        swift += "print(\"T017_SWIFT_ORACLE_PASSED\")\n"
        javascript += "console.log('T017_JS_ORACLE_PASSED');\n"
        try swift.write(to:directory.appendingPathComponent("swift.swift"),atomically:true,encoding:.utf8)
        try javascript.write(to:directory.appendingPathComponent("javascript.mjs"),atomically:true,encoding:.utf8)
    }
}
