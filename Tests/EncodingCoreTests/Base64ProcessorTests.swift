import Foundation
import Testing
@testable import EncodingCore

struct Base64ProcessorTests {
    @Test func rfcVectorsAndURLRoundTrips() {
        let vectors = [("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy")]
        for (plain, encoded) in vectors {
            for alphabet in Base64Alphabet.allCases {
                for padded in [false,true] {
                    let encode = Base64Options(direction: .encode, alphabet: alphabet, urlPadding: padded)
                    let result = Base64Processor.process(plain, options: encode)
                    #expect(result.status == .success)
                    let expected = alphabet == .urlSafe && !padded ? encoded.replacingOccurrences(of: "=", with: "") : encoded
                    #expect(result.artifact?.text == expected)
                    let decoded = Base64Processor.process(expected, options: .init(alphabet: alphabet))
                    #expect(decoded.status == .success && decoded.artifact?.text == plain)
                }
            }
        }
        #expect(Base64Processor.process("\u{ff}", options: .init(direction: .encode, alphabet: .urlSafe, encoding: .latin1)).artifact?.text == "_w")
    }
    @Test func strictAndForgivingGoldenAnchors() {
        let bad: [(String, Base64Issue.Code, NSRange)] = [
            ("YQ=", .invalidPadding, .init(location: 3, length: 0)),
            ("YQ===", .invalidPadding, .init(location: 4, length: 1)),
            ("Y===", .invalidPadding, .init(location: 1, length: 1)),
            ("YW=Jj", .invalidPadding, .init(location: 3, length: 1)),
            ("AAAA====", .invalidPadding, .init(location: 4, length: 1)),
            ("A", .invalidLength, .init(location: 1, length: 0)),
            ("YQ==YQ==", .invalidPadding, .init(location: 4, length: 1)),
            ("YQ==😀", .invalidSymbol, .init(location: 4, length: 2)),
            ("YQ%3D%3D", .invalidSymbol, .init(location: 2, length: 1)),
            ("data:text/plain;base64,YQ==", .invalidSymbol, .init(location: 4, length: 1)),
            ("YQ.Yg.Yw", .invalidSymbol, .init(location: 2, length: 1)),
            ("YQ\u{b}==", .invalidSymbol, .init(location: 2, length: 1)),
            ("YQ==\u{a0}", .invalidSymbol, .init(location: 4, length: 1)),
            ("\u{feff}YQ==", .invalidSymbol, .init(location: 0, length: 1))]
        for (source, code, range) in bad {
            for alphabet in Base64Alphabet.allCases {
                for mode in Base64DecodeMode.allCases {
                    let result = Base64Processor.process(source, options: .init(alphabet: alphabet, decodeMode: mode))
                    #expect(result.status == .invalidBase64, "\(source.debugDescription) / \(alphabet) / \(mode)")
                    #expect(result.issues.first?.code == code)
                    #expect(result.issues.first?.range == range)
                    #expect(result.artifact == nil)
                }
            }
        }
        for source in ["YQ", "YWI"] {
            #expect(Base64Processor.process(source).issues.first?.code == .missingPadding)
            for options in [Base64Options(alphabet: .urlSafe), .init(decodeMode: .forgiving)] {
                #expect(Base64Processor.process(source, options: options).status == .success)
            }
        }
        for (source, expected) in [("Zh==", "f"), ("Zm9=", "fo")] {
            let strict = Base64Processor.process(source)
            #expect(strict.issues.first?.code == .nonCanonicalPadBits)
            #expect(strict.issues.first?.range?.location == (source == "Zh==" ? 1 : 2))
            let forgiving = Base64Processor.process(source, options: .init(decodeMode: .forgiving))
            #expect(forgiving.artifact?.text == expected)
            #expect(forgiving.issues.contains { $0.code == .nonCanonicalPadBits })
        }
    }
    @Test func whitespaceAndSourceMapping() {
        let source = " \tY\r\nQ\u{c}==\n"
        #expect(Base64Processor.process(source).issues.first?.range == .init(location: 0, length: 1))
        let decoded = Base64Processor.process(source, options: .init(decodeMode: .forgiving))
        #expect(decoded.artifact?.text == "a" && decoded.issues.count == 1)
        let invalid = Base64Processor.process("\r\n Y\tQ==😀", options: .init(decodeMode: .forgiving))
        #expect(invalid.issues.first?.range == .init(location: 8, length: 2))
        #expect(invalid.issues.first?.line == 2 && invalid.issues.first?.column == 7)
        let bits = Base64Processor.process("\r\n Z\th==", options: .init(decodeMode: .forgiving))
        #expect(bits.artifact?.text == "f" && bits.issues.count == 2)
        for (source, alphabet) in [("/w==", Base64Alphabet.urlSafe), ("+w==", .urlSafe), ("_w", .standard), ("-w", .standard), ("+_8=", .standard), ("+_8=", .urlSafe)] {
            #expect(Base64Processor.process(source, options: .init(alphabet: alphabet)).issues.first?.code == .wrongAlphabet)
        }
        #expect(Base64Processor.process(" \r\n", options: .init(decodeMode: .forgiving)).artifact?.text == "")
    }
    @Test func emptyCheckAndBinaryResult() {
        #expect(Base64Processor.process("").artifact?.decodedBytes == Data())
        let check = Base64Processor.process("YQ==", intent: .check)
        #expect(check.status == .success && check.artifact == nil && check.byteCount == 1)
        let binary = Base64Processor.process("/w==")
        #expect(binary.status == .bytesOnly && binary.artifact?.text == nil)
        #expect(binary.artifact?.decodedBytes == Data([255]) && binary.preview == "FF")
        #expect(binary.issues.first?.range == nil)
        let many = Data(repeating: 255, count: 100).base64EncodedString()
        #expect(Base64Processor.process(many).preview.split(separator: " ").count == 64)
    }
    @Test func processingBudgets() async {
        let boundary = String(repeating: "a", count: 196_608)
        let result = Base64Processor.process(boundary, options: .init(direction: .encode))
        #expect(result.status == .success && result.artifact?.text?.utf16.count == 262_144)
        #expect(Base64Processor.process(result.artifact!.text!).artifact?.text == boundary)
        #expect(Base64Processor.process(boundary + "a", options: .init(direction: .encode)).status == .resourceLimit)
        #expect(Base64Processor.process(String(repeating: "界", count: 65_536), options: .init(direction: .encode)).status == .success)
        #expect(Base64Processor.process(String(repeating: "界", count: 65_537), options: .init(direction: .encode)).status == .resourceLimit)
        let large = Base64Processor.process(String(repeating: " ", count: 262_145), options: .init(decodeMode: .forgiving))
        #expect(large.status == .resourceLimit && large.artifact == nil && large.issues.first?.range == nil)
        #expect(Base64Processor.process("YWJj", limits: .init(inputUTF16: 8, outputUTF16: 2, bytes: 8)).status == .resourceLimit)
        let task = Task { while !Task.isCancelled { await Task.yield() }; return Base64Processor.process("YQ==") }
        task.cancel()
        #expect(await task.value.status == .cancelled)
    }
}
