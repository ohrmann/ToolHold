import Foundation
import Testing
@testable import EncodingCore

struct Base64TextCodecTests {
    @Test func exactUnicodeBOMAndControlRoundTrips() {
        for source in ["😀", "é", "e\u{301}", "\u{feff}A", "\0", " before\r\n after\t ", "a\u{202e}b", "�"] {
            for encoding in [Base64TextEncoding.utf8, .utf16LE, .utf16BE] {
                let encoded = Base64Processor.process(source, options: .init(direction: .encode, encoding: encoding))
                let decoded = Base64Processor.process(encoded.artifact!.text!, options: .init(encoding: encoding))
                #expect(decoded.artifact!.text!.utf16.elementsEqual(source.utf16))
                #expect(decoded.artifact?.decodedBytes == (try? Base64TextCodec.encode(source, encoding: encoding, limit: 1_000)))
            }
        }
        #expect(Base64Processor.process("😀", options: .init(direction: .encode)).artifact?.text == "8J+YgA==")
        #expect(Base64Processor.process("é", options: .init(direction: .encode)).artifact?.text != Base64Processor.process("e\u{301}", options: .init(direction: .encode)).artifact?.text)
        #expect(Base64Processor.process("77u/QQ==").artifact?.text?.unicodeScalars.first?.value == 0xFEFF)
        #expect(Base64Processor.process("77u/QQ==").issues.first?.code == .leadingBOM)
        #expect(Base64Processor.process("AA==").issues.contains { $0.code == .controls })
    }
    @Test func malformedUnicodeIsBytesOnly() {
        for bytes: [UInt8] in [[255],[0xC0,0xAF],[0xED,0xA0,0x80],[0xF0,0x9F,0x98],[0xF4,0x90,0x80,0x80]] {
            let source = Data(bytes).base64EncodedString()
            let result = Base64Processor.process(source)
            #expect(result.status == .bytesOnly && result.artifact?.decodedBytes == Data(bytes))
            #expect(result.artifact?.text == nil && result.issues.first?.range == nil)
        }
        for encoding in [Base64TextEncoding.utf16LE,.utf16BE] {
            for bytes in [[UInt8(65)], encoding == .utf16LE ? [0,0xD8] : [0xD8,0], encoding == .utf16LE ? [0,0xDC] : [0xDC,0]] {
                #expect(Base64Processor.process(Data(bytes).base64EncodedString(), options: .init(encoding: encoding)).status == .bytesOnly)
            }
        }
        #expect(Base64Processor.process("QQA=", options: .init(encoding: .utf16LE)).artifact?.text == "A")
        #expect(Base64Processor.process("AEE=", options: .init(encoding: .utf16BE)).artifact?.text == "A")
    }
    @Test func singleByteEncodingsNeverSubstitute() {
        let bytes = Data((0...255).map(UInt8.init))
        let result = Base64Processor.process(bytes.base64EncodedString(), options: .init(encoding: .latin1))
        #expect(result.status == .success)
        #expect(result.artifact?.text?.unicodeScalars.map(\.value) == (0...255).map(UInt32.init))
        #expect(Base64Processor.process(result.artifact!.text!, options: .init(direction: .encode, encoding: .latin1)).artifact?.text == bytes.base64EncodedString())
        #expect(Base64Processor.process("/w==", options: .init(encoding: .latin1)).artifact?.text == "ÿ")
        #expect(Base64Processor.process("gA==", options: .init(encoding: .ascii)).status == .bytesOnly)
        for (source, encoding, offset) in [("é", Base64TextEncoding.ascii,0),("e\u{301}",.latin1,1),("€",.latin1,0),("a😀",.ascii,1)] {
            let result = Base64Processor.process(source, options: .init(direction: .encode, encoding: encoding))
            #expect(result.status == .unrepresentableText && result.issues.first?.range?.location == offset)
        }
    }
    @Test func deterministicByteProperties() {
        var seed: UInt64 = 42
        for count in 0..<160 {
            let bytes = Data((0..<count).map { _ in seed = seed &* 6364136223846793005 &+ 1; return UInt8(truncatingIfNeeded: seed >> 32) })
            for alphabet in Base64Alphabet.allCases {
                var source = bytes.base64EncodedString()
                if alphabet == .urlSafe { source = source.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
                let decoded = Base64Processor.process(source, options: .init(alphabet: alphabet, encoding: .latin1))
                #expect(decoded.artifact?.decodedBytes == bytes)
                let encoded = Base64Processor.process(decoded.artifact!.text!, options: .init(direction: .encode, alphabet: alphabet, encoding: .latin1))
                #expect(encoded.artifact?.text == source)
            }
        }
    }
}
