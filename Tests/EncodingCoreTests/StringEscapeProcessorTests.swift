import Foundation
import Testing
@testable import EncodingCore

struct StringEscapeProcessorTests {
    private func decode(_ text: String, _ language: StringEscapeLanguage = .json,
                        representation: StringEscapeRepresentation = .contents, quote: StringEscapeQuote = .double) -> StringEscapeResult {
        StringEscapeProcessor.process(text, options: .init(language: language, direction: .unescape, representation: representation, quote: quote))
    }
    private func exact(_ result: StringEscapeResult, _ expected: String) -> Bool {
        result.artifact?.text.utf16.elementsEqual(expected.utf16) == true
    }
    @Test func jsonGoldenAndSinglePass() {
        #expect(exact(decode(#"a\nb"#), "a\nb"))
        #expect(exact(decode(#"a\\nb"#), #"a\nb"#))
        #expect(exact(decode(#"\"\\\/\b\f\n\r\t\u0041"#), "\"\\/\u{8}\u{C}\n\r\tA"))
        #expect(exact(decode(#"\uD83D\uDE00"#), "😀"))
        for source in [#"\x41"#, #"\u{41}"#, #"\'"#, #"\0"#, #"\q"#, "a\tb", "a\nb", "a\rb", "a\u{0}b", "a\"b"] {
            let result = decode(source)
            #expect(result.status == .invalidSyntax, "\(source.debugDescription)")
            #expect(result.artifact == nil)
        }
    }
    @Test func framingAndEmptyValues() {
        #expect(exact(decode("  \"a\"\r\n", representation: .quoted), "a"))
        #expect(exact(decode("\"\"", representation: .quoted), ""))
        #expect(exact(decode(""), ""))
        #expect(decode("", representation: .quoted).issues.first?.code == .openingQuote)
        #expect(decode("\"a\" \"b\"", representation: .quoted).issues.first?.code == .unexpectedToken)
        #expect(decode("\u{FEFF}\"a\"", representation: .quoted).issues.first?.code == .openingQuote)
        #expect(exact(decode("   "), "   "))
        for source in ["{}", "'a'", "// comment\n\"a\"", "\"a\" + \"b\""] {
            #expect(decode(source, representation: .quoted).status == .invalidSyntax)
        }
        #expect(exact(StringEscapeProcessor.process(""), "\"\""))
        #expect(exact(StringEscapeProcessor.process("",options:.init(representation:.contents)), ""))
    }
    @Test func swiftGolden() {
        #expect(exact(decode(#"\u{1F600}\u{00000041}\0\\\t\n\r\"\'"#, .swift), "😀A\u{0}\\\t\n\r\"'"))
        for source in [#"\u{D800}"#, #"\u{110000}"#, #"\u{}"#, #"\u{000000041}"#, #"\b"#, #"\f"#, #"\u0041"#, "\\\n"] {
            #expect(decode(source, .swift).status == .invalidSyntax, "\(source)")
        }
        #expect(decode(#"\(name)"#, .swift).status == .unsupportedSyntax)
        #expect(exact(decode(#"\\(name)"#, .swift), #"\(name)"#))
        #expect(exact(decode(#"\u{5C}(name)"#, .swift), #"\(name)"#))
        #expect(exact(decode("a\tb", .swift), "a\tb"))
        for source in ["#\"a\"#", "\"\"\"\na\n\"\"\""] {
            #expect(decode(source, .swift, representation:.quoted).status == .unsupportedSyntax)
        }
    }
    @Test func javascriptGoldenAndQuotes() {
        #expect(exact(decode(#"\x41\u0042\u{1F600}"#, .javascript), "AB😀"))
        #expect(exact(decode(#"\u{000000000041}"#, .javascript), "A"))
        #expect(exact(decode(#"\q\/\0\v\'"#, .javascript), "q/\u{0}\u{B}'"))
        #expect(decode(#"\q"#, .javascript).issues.first?.code == .identityEscape)
        for source in [#"\01"#, #"\07"#, #"\08"#, #"\8"#, #"\9"#, #"\u{110000}"#, #"\xG1"#, #"\u{Z}"#] {
            #expect(decode(source, .javascript).status == .invalidSyntax, "\(source)")
        }
        #expect(exact(decode("'it\\'s'", .javascript, representation:.quoted,quote:.single), "it's"))
        #expect(decode("'a'", .javascript, representation:.quoted).issues.first?.code == .openingQuote)
        #expect(decode("`a`", .javascript, representation:.quoted).status == .unsupportedSyntax)
        #expect(exact(decode("a\u{2028}\u{2029}b", .javascript), "a\u{2028}\u{2029}b"))
        for newline in ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}"] {
            let result = decode("a\\" + newline + "b", .javascript)
            #expect(exact(result, "ab")); #expect(result.issues.first?.code == .continuation)
            #expect(result.issues.first?.range == NSRange(location:1,length:1+newline.utf16.count))
        }
    }
    @Test func exactUnicodeCodeUnitSemantics() {
        for language in [StringEscapeLanguage.json, .javascript] {
            for source in [#"\uD800"#, #"\uDE00"#, #"\uD800x"#, #"\uD800\uD801"#, #"\uDE00\uD800"#] {
                let result = decode(source,language)
                #expect(result.status == .notRepresentableAsText)
                #expect(result.artifact == nil)
                #expect(result.issues.first?.code == .unpairedSurrogate)
            }
            let malformed = decode(#"\uD800x\uG000"#,language)
            #expect(malformed.status == .invalidSyntax)
            #expect(malformed.issues.first { $0.severity == .error }?.code == .hexDigit)
        }
        #expect(exact(decode("\\uD83D\\\n\\uDE00", .javascript), "😀"))
        #expect(exact(decode(#"\u{D83D}\uDE00"#, .javascript), "😀"))
        #expect(exact(decode(#"\uD83D\u{DE00}"#, .javascript), "😀"))
        #expect(decode(#"\u{D800}"#, .javascript).status == .notRepresentableAsText)
        #expect(exact(decode(#"\uD800\uDC00"#), "\u{10000}"))
    }
    @Test func preciseAnchorsAndSourceCoordinates() {
        let invalid = decode(#"\u12G4"#)
        #expect(invalid.issues.first?.range == NSRange(location:4,length:1))
        #expect(invalid.issues.first?.related == NSRange(location:0,length:1))
        #expect(invalid.issues.first?.column == 5)
        let eof = decode(#"\u12"#)
        #expect(eof.issues.first?.range == NSRange(location:4,length:0))
        let opening = decode("  \"😀e\u{301}", representation:.quoted)
        #expect(opening.issues.first?.range == NSRange(location:7,length:0))
        #expect(opening.issues.first?.related == NSRange(location:2,length:1))
        #expect(opening.issues.first?.column == 8)
        let crlf = decode(" \r\n\"😀e\u{301}\\u12",representation:.quoted)
        #expect(crlf.issues.first?.line == 2)
        #expect(crlf.issues.first?.column == 10)
        let brokenLine = decode("\"a\r\n\"",representation:.quoted)
        #expect(brokenLine.issues.first?.range == NSRange(location:2,length:1))
        #expect(brokenLine.issues.first?.line == 1)
        let js = decode("\"a\\\r\nb\\uG\"",.javascript,representation:.quoted)
        #expect(js.issues.first { $0.severity == .error }?.line == 2)
        #expect(js.issues.first { $0.severity == .error }?.column == 4)
    }
    @Test func deterministicEscapingPolicies() {
        let text = "\u{0}8\u{8}\u{B}\u{C}\t\r\n\"'\\😀é\u{202E}"
        for language in StringEscapeLanguage.allCases {
            for quote in StringEscapeQuote.allCases {
                for representation in StringEscapeRepresentation.allCases {
                    for nonASCII in [false,true] {
                        let options = StringEscapeOptions(language:language,representation:representation,quote:quote,nonASCII:nonASCII)
                        let escaped = StringEscapeProcessor.process(text,options:options)
                        #expect(escaped.status == .success)
                        var inverse = options; inverse.direction = .unescape
                        #expect(exact(StringEscapeProcessor.process(escaped.artifact!.text,options:inverse),text))
                    }
                }
            }
        }
        #expect(exact(StringEscapeProcessor.process("😀",options:.init(nonASCII:true)), #""\uD83D\uDE00""#))
        #expect(exact(StringEscapeProcessor.process("😀",options:.init(language:.swift,nonASCII:true)), #""\u{1F600}""#))
        #expect(exact(StringEscapeProcessor.process(#"\(name)"#,options:.init(language:.swift)), #""\\(name)""#))
        #expect(exact(StringEscapeProcessor.process("\u{0}8",options:.init(language:.javascript)), #""\x008""#))
    }
    @Test func generatedScalarRoundTripsAndJSONOracle() throws {
        var text = "e\u{301}é\r\n🇨🇿👩‍💻", seed: UInt64 = 0x17
        for n in Array(0...255) + [0x061C,0x200E,0x2029,0x2069,0xD7FF,0xE000,0xFFFF,0x10FFFF] {
            text.unicodeScalars.append(Unicode.Scalar(n)!)
        }
        for _ in 0..<1500 {
            seed = seed &* 6364136223846793005 &+ 1
            let n = UInt32(seed % 0x110000)
            if let scalar = Unicode.Scalar(n) { text.unicodeScalars.append(scalar) }
        }
        for language in StringEscapeLanguage.allCases {
            for nonASCII in [false,true] {
                for quote in StringEscapeQuote.allCases {
                    var options = StringEscapeOptions(language:language,quote:quote,nonASCII:nonASCII)
                    let encoded = StringEscapeProcessor.process(text,options:options).artifact!.text
                    options.direction = .unescape
                    #expect(exact(StringEscapeProcessor.process(encoded,options:options),text))
                    if language == .json {
                        let oracle = try JSONDecoder().decode(String.self,from:Data(encoded.utf8))
                        #expect(oracle.utf16.elementsEqual(text.utf16))
                    }
                }
            }
        }
    }
    @Test func limitsCheckParityWarningsAndLongHex() {
        let budget = StringEscapeLimits(inputUTF16:12,outputUTF16:6)
        for intent in [StringEscapeIntent.check,.convert] {
            #expect(StringEscapeProcessor.process("abcd",intent:intent,limits:budget).status == .success)
            #expect(StringEscapeProcessor.process("abcde",intent:intent,limits:budget).status == .resourceLimit)
            #expect(StringEscapeProcessor.process(String(repeating:"a",count:13),intent:intent,limits:budget).issues.first?.code == .inputLimit)
            let decodeOptions = StringEscapeOptions(direction:.unescape,representation:.contents)
            let checked = StringEscapeProcessor.process(#"\u0041"#,options:decodeOptions,intent:intent,limits:budget)
            #expect(checked.outputCount == 1)
            #expect((checked.artifact == nil) == (intent == .check))
        }
        let zeros = #"\u{"# + String(repeating:"0",count:262_138) + "41}"
        #expect(exact(decode(zeros,.javascript), "A"))
        let warnings = decode(String(repeating:#"\q"#,count:100)+#"\xG0"#,.javascript)
        #expect(warnings.status == .invalidSyntax)
        #expect(warnings.issues.first?.occurrences == 100)
        #expect(warnings.issueCount == 101)
        #expect(warnings.issues.first { $0.severity == .error }?.code == .hexDigit)
        #expect(StringEscapeProcessor.process(String(repeating:"a",count:262_145)).issues.first?.code == .inputLimit)
        let limits = StringEscapeProcessor.process(String(repeating:"a",count:262_144))
        #expect(limits.status == .resourceLimit && limits.artifact == nil)
        #expect(StringEscapeProcessor.process(String(repeating:"a",count:262_142)).outputCount == 262_144)
    }
    @Test func prefixesSafeContextAndCancellation() async {
        for (source,language) in [(#"\u1234"#,StringEscapeLanguage.json),(#"\u{1F600}"#,.swift),(#"\x41"#,.javascript)] {
            for n in 1..<source.count {
                let result = decode(String(source.prefix(n)),language)
                #expect(result.artifact == nil)
                #expect(result.issues.first?.range?.location == n)
            }
        }
        let source = "a"+String(repeating:"\u{301}",count:300)+#"\uG000"#
        #expect(decode(source).issues.first?.context?.contains("Long grapheme") == true)
        let bidi = decode("\u{202E}\\uG000")
        #expect(bidi.issues.first?.context?.contains("\u{202E}") == false)
        let task = Task.detached { StringEscapeProcessor.process(String(repeating:"a",count:262_142)) }
        task.cancel(); #expect(await task.value.status == .cancelled)
    }
}
