import Foundation
import Testing
@testable import EncodingCore

struct HTMLEntityProcessorTests {
    private func decode(_ text: String, _ context: HTMLEntityContext = .text, strict: Bool = false) -> HTMLEntityResult {
        HTMLEntityProcessor.process(text, options: .init(direction: .decode, context: context, policy: strict ? .strict : .htmlCompatible))
    }
    @Test func officialTableParityAndAllNamedReferences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        struct Entry: Decodable { let codepoints: [UInt32]; let characters: String }
        let data = try Data(contentsOf: root.appendingPathComponent("ThirdPartyNotices/WHATWGHTML/entities.json"))
        let official = try JSONDecoder().decode([String: Entry].self, from: data)
        #expect(official.count == 2231 && HTMLEntityTable.entries.count == official.count)
        for (name, entry) in official {
            let expected = entry.codepoints
            #expect(entry.characters.unicodeScalars.map(\.value) == expected)
            let result = decode(name)
            #expect(result.artifact?.text.unicodeScalars.map(\.value) == expected, "\(name)")
            #expect(result.status == (name.hasSuffix(";") ? .success : .successWithWarnings))
            #expect(HTMLEntityTable.entries[String(name.dropFirst())]?.unicodeScalars.map(\.value) == expected)
        }
    }
    @Test func legacyNamesAndAttributeException() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("ThirdPartyNotices/WHATWGHTML/entities.json"))
        let official = try JSONSerialization.jsonObject(with: data) as! [String: [String: Any]]
        for (name, entry) in official where !name.hasSuffix(";") {
            let value = entry["characters"] as! String
            for suffix in ["=", "9", "z"] {
                for context in [HTMLEntityContext.doubleQuoted, .singleQuoted] {
                    let result = decode(name + suffix, context, strict: true)
                    #expect(result.artifact?.text == name + suffix && result.issueCount == 0)
                }
                #expect(decode(name + suffix).artifact?.text == value + suffix)
            }
            #expect(decode(name + "!").artifact?.text == value + "!")
        }
    }
    @Test func decodeGoldenContextsAndSinglePass() {
        for (source, expected, warnings) in [
            ("&amp;lt;", "&lt;", false), ("&#38;lt;", "&lt;", false), ("&amp;amp;", "&amp;", false),
            ("&notin;", "∉", false), ("&notit;", "¬it;", true), ("&copy=1", "©=1", true),
            ("&copy", "©", true), ("&bogus;", "&bogus;", true), ("AT&T", "AT&T", false),
            ("&#x;", "&#x;", true), ("&#;", "&#;", true), ("&", "&", false),
            ("<b>&amp;</b>", "<b>&</b>", false), ("&#65;&#x1F600;", "A😀", false),
            ("&NotEqualTilde;", "\u{2242}\u{0338}", false), ("&AMP;&Amp;", "&&Amp;", true),
            ("&#12z;", "\u{C}z;", true), ("&#X1f600;", "😀", false)
        ] {
            let result = decode(source)
            #expect(result.artifact?.text.utf16.elementsEqual(expected.utf16) == true, "\(source)")
            #expect(result.status == (warnings ? .successWithWarnings : .success))
            let strict = decode(source, strict: true)
            #expect(strict.status == (warnings ? .invalidReferences : .success))
            #expect(warnings ? strict.artifact == nil : strict.artifact?.text == expected)
        }
        #expect(decode("&notit;", .doubleQuoted).artifact?.text == "&notit;")
        #expect(decode("&copy=1", .singleQuoted).artifact?.text == "&copy=1")
        #expect(decode("&#65=1", .doubleQuoted).artifact?.text == "A=1")
    }
    @Test func numericScalarValidityAndControls() {
        for source in ["&#0;", "&#xD800;", "&#xDFFF;", "&#x110000;", "&#999999999999999999999999999999;"] {
            let result = decode(source)
            #expect(result.artifact?.text == "�" && result.issueCount == 1)
            #expect(decode(source, strict: true).artifact == nil)
        }
        #expect(decode("&#xD83D;&#xDE00;").artifact?.text == "��")
        #expect(decode("&#x10FFFF;").artifact?.text.unicodeScalars.first?.value == 0x10FFFF)
        #expect(decode("&#xFDD0;").issues.first?.code == .noncharacterReference)
        for value in [0xD, 0x1, 0x7F, 0x81, 0x9D] {
            let result = decode("&#\(value);")
            #expect(result.artifact?.text.unicodeScalars.first?.value == UInt32(value))
            #expect(result.issues.first?.code == .controlReference)
        }
        for value in [9,10,12,32] { #expect(decode("&#\(value);").status == .success) }
    }
    @Test func everyC1RemapIsExplicit() {
        let pairs: [(Int,UInt32)] = [(128,0x20AC),(130,0x201A),(131,0x0192),(132,0x201E),(133,0x2026),(134,0x2020),(135,0x2021),(136,0x02C6),(137,0x2030),(138,0x0160),(139,0x2039),(140,0x0152),(142,0x017D),(145,0x2018),(146,0x2019),(147,0x201C),(148,0x201D),(149,0x2022),(150,0x2013),(151,0x2014),(152,0x02DC),(153,0x2122),(154,0x0161),(155,0x203A),(156,0x0153),(158,0x017E),(159,0x0178)]
        for (number, expected) in pairs {
            let result = decode("&#\(number);")
            #expect(result.artifact?.text.unicodeScalars.first?.value == expected)
            #expect(result.issues.first?.code == .remappedControl)
            #expect(decode("&#\(number);", strict: true).status == .invalidReferences)
            let source = String(Unicode.Scalar(UInt32(number))!)
            #expect(HTMLEntityProcessor.process(source).artifact?.text == source)
            for notation in HTMLEntityNotation.allCases {
                let result = HTMLEntityProcessor.process(source, options: .init(scope: .nonASCII, notation: notation))
                #expect(result.status == .invalidReferences && result.artifact == nil)
            }
        }
    }
    @Test func encodeContextsAndNotations() {
        let text = "A & B < C > D \"'"
        #expect(HTMLEntityProcessor.process(text).artifact?.text == "A &amp; B &lt; C &gt; D \"'")
        #expect(HTMLEntityProcessor.process("\"'", options: .init(context: .doubleQuoted)).artifact?.text == "&quot;'")
        #expect(HTMLEntityProcessor.process("\"'", options: .init(context: .singleQuoted)).artifact?.text == "\"&apos;")
        #expect(HTMLEntityProcessor.process("😀&", options: .init(scope: .nonASCII, notation: .decimal)).artifact?.text == "&#128512;&#38;")
        #expect(HTMLEntityProcessor.process("😀&", options: .init(scope: .nonASCII, notation: .hexadecimal)).artifact?.text == "&#x1F600;&#x26;")
        #expect(HTMLEntityProcessor.process("é", options: .init(scope: .nonASCII)).artifact?.text == "&eacute;")
        #expect(HTMLEntityProcessor.process(" A\n", options: .init(scope: .everyCharacter, notation: .decimal)).artifact?.text == "&#32;&#65;&#10;")
    }
    @Test func preserveOnlyCompleteCleanReferences() {
        let source = "&amp;&copy;&#65;&#x41;&bogus;&copy &#128;&#0;"
        let result = HTMLEntityProcessor.process(source, options: .init(preserveExistingReferences: true))
        #expect(result.artifact?.text == "&amp;&copy;&#65;&#x41;&amp;bogus;&amp;copy &amp;#128;&amp;#0;")
        #expect(result.preservedCount == 4 && result.issueCount == 0)
        #expect(HTMLEntityProcessor.process("&amp;").artifact?.text == "&amp;amp;")
        let every = HTMLEntityProcessor.process("&amp;A", options: .init(scope: .everyCharacter, notation: .decimal, preserveExistingReferences: true))
        #expect(every.artifact?.text == "&amp;&#65;")
        #expect(HTMLEntityProcessor.process(result.artifact!.text, options: .init(preserveExistingReferences: true)).artifact?.text == result.artifact?.text)
    }
    @Test func exactScalarRoundTripsWithoutNormalization() {
        let values = ["", "\r\n\t", "é e\u{301}", "👨‍👩‍👧‍👦😀", "<>&\"'", "a\u{202E}\u{2066}z", "\u{FEFF}line\r\n"]
        for context in HTMLEntityContext.allCases {
            for scope in HTMLEntityScope.allCases {
                for notation in HTMLEntityNotation.allCases {
                    for source in values {
                        let encoded = HTMLEntityProcessor.process(source, options: .init(context: context, scope: scope, notation: notation))
                        let decoded = decode(encoded.artifact!.text, context)
                        #expect(decoded.artifact?.text.utf16.elementsEqual(source.utf16) == true)
                    }
                }
            }
        }
        #expect(HTMLEntityProcessor.process("x\0y").status == .invalidReferences)
    }
    @Test func exactUTF16AnchorsCRLFAndEOF() {
        let source = "😀e\u{301}\r\n&bogus; &copy"
        let result = decode(source)
        #expect(result.issues.count == 2)
        #expect(result.issues[0].range == NSRange(location: 6,length: 7))
        #expect(result.issues[0].line == 2 && result.issues[0].column == 1)
        #expect(result.issues[1].range == NSRange(location: source.utf16.count,length: 0))
        #expect(result.issues[1].line == 2 && result.issues[1].column == 14)
        for source in ["&#", "&#x", "&copy"] {
            #expect(decode(source).issues[0].range == NSRange(location: source.utf16.count,length: 0))
        }
        #expect(decode("&#0;").issues[0].range == NSRange(location:0,length:4))
    }
    @Test func checkAndConvertHaveIdenticalOutcomesWithoutArtifact() {
        for direction in HTMLEntityDirection.allCases {
            for policy in HTMLEntityPolicy.allCases {
                let options = HTMLEntityOptions(direction: direction, scope: .everyCharacter, policy: policy)
                let convert = HTMLEntityProcessor.process("&notit; 😀 &#0;", options: options)
                let check = HTMLEntityProcessor.process("&notit; 😀 &#0;", options: options, intent: .check)
                #expect(check.artifact == nil && check.status == convert.status && check.issues == convert.issues)
                #expect(check.outputCount == convert.outputCount && check.convertedCount == convert.convertedCount)
            }
        }
    }
    @Test func inputOutputBoundariesAndNoPartialArtifacts() {
        for count in [262_143,262_144,262_145] {
            let result = HTMLEntityProcessor.process(String(repeating:"a",count:count))
            #expect(result.status == (count <= 262_144 ? .success : .resourceLimit))
            #expect(count <= 262_144 ? result.artifact?.text.count == count : result.artifact == nil)
        }
        for count in [7,8,9] {
            let result = HTMLEntityProcessor.process(String(repeating:"&",count:count), limits:.init(outputUTF16:40))
            #expect(result.status == (count <= 8 ? .success : .resourceLimit))
            if count > 8 { #expect(result.artifact == nil) }
        }
        #expect(HTMLEntityProcessor.process("&&",intent:.check,limits:.init(outputUTF16:9)).status == .resourceLimit)
        #expect(decode("&#" + String(repeating:"9",count:262_141) + ";").artifact?.text == "�")
        #expect(decode("&" + String(repeating:"z",count:262_142) + ";").issueCount == 1)
    }
    @Test func issuesBoundedWithoutHidingValidityAndSafeContext() {
        for count in [32,33,1000] {
            let result = decode(String(repeating:"&bogus;",count:count))
            #expect(result.issues.count == min(count,32) && result.issueCount == count)
            #expect(decode(String(repeating:"&bogus;",count:count),strict:true).status == .invalidReferences)
        }
        let lateError = HTMLEntityProcessor.process(String(repeating:"\u{81}",count:40) + "\0")
        #expect(lateError.status == .invalidReferences && lateError.issueCount == 41)
        #expect(lateError.issues.contains { $0.severity == .error && $0.code == .unrepresentableScalar })
        let source = "\u{202E}\t\t  &bogus;\r\n"
        let context = decode(source).issues.first!.context!
        #expect(context.contains("\\u{202E}") && !context.contains("\u{202E}") && !context.contains("\t"))
        let long = "e" + String(repeating:"\u{301}",count:20_000) + "&bogus;"
        #expect(decode(long).issues.first!.context!.count < 200)
    }
    @Test func cancellationIsNotInvalidJSON() async {
        let task = Task.detached { HTMLEntityProcessor.process(String(repeating:"&notit;",count:37_000), options:.init(direction:.decode)) }
        task.cancel()
        #expect(await task.value.status == .cancelled)
    }
}
