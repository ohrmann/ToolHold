import Foundation
import Testing
@testable import EncodingCore

struct HexBytesProcessorTests {
    @Test func inputProfilesAndExactMaps() throws {
        let fixtures: [(String,HexBytesInputFormat,[UInt32])] = [
            ("48656c6c6f",.pairs,[0,2,4,6,8]),("48:65-6C 6C\r\n6F",.pairs,[0,3,6,9,13]),
            (" 0x48, 0X65\t0x6C 0x6C\r\n0x6F ",.prefixed,[3,9,14,19,25]),
            (#"\x48\x65 \x6C\x6C\x6F"#,.escaped,[2,6,11,15,19])
        ]
        for (source,format,starts) in fixtures {
            let r = HexBytesProcessor.process(source,options:.init(inputFormat:format))
            #expect(r.status == .success && r.byteCount == 5 && r.artifact?.text == "Hello")
            #expect(r.artifact?.bytes == Data("Hello".utf8))
            #expect(r.artifact?.sourceMap?.digitStarts == starts)
            #expect(r.artifact?.sourceMap?.range(for:-1) == nil && r.artifact?.sourceMap?.range(for:5) == nil)
        }
    }
    @Test func malformedProfilesAndNoRepair() {
        let fixtures: [(HexBytesInputFormat,[String])] = [
            (.pairs,["A","ABC","A B","4G",":41","41:","41::42","41,42","0x41",#"\x41"#,"41\u{a0}42","41\u{200b}42","41\u{202e}42"]),
            (.prefixed,["0x4","0x4142","0x41,","0x41,,0x42","[0x41]","0x410x42","41","0z41","0x41:0x42","0x"]),
            (.escaped,[#"\x4"#,#"\X41"#,#"\u0041"#,#""\x41""#,#"\x41,\x42"#,#"\n"#])
        ]
        for (format,sources) in fixtures {
            for source in sources {
                let r = HexBytesProcessor.process(source,options:.init(inputFormat:format))
                #expect(r.status == .invalidHex && r.artifact == nil)
                #expect(r.issues.first?.domain == .hex && r.issues.first?.severity == .error)
            }
        }
        let priority = HexBytesProcessor.process("FF ZZ")
        #expect(priority.status == .invalidHex && priority.issues.first?.range == NSRange(location:3,length:1))
    }
    @Test func anchorsEOFCRLFAndEmoji() {
        for (s,detection,related) in [("A",NSRange(location:1,length:0),NSRange(location:0,length:1)),
                                      ("ABC",NSRange(location:3,length:0),NSRange(location:2,length:1)),
                                      ("A B",NSRange(location:1,length:1),NSRange(location:0,length:1)),
                                      ("41:",NSRange(location:3,length:0),NSRange(location:2,length:1)),
                                      ("41😀42",NSRange(location:2,length:2),nil)] {
            let issue = HexBytesProcessor.process(s).issues.first
            #expect(issue?.range == detection && issue?.related == related)
        }
        let crlf = HexBytesProcessor.process("41\r\n4G").issues.first
        #expect(crlf?.line == 2 && crlf?.column == 2 && crlf?.range == NSRange(location:5,length:1))
    }
    @Test func allByteValuesEveryFormatAndCase() throws {
        let bytes = Data((0...255).map(UInt8.init))
        for f in HexBytesOutputFormat.allCases {
            for c in HexBytesCase.allCases {
                let source = try HexBytesProcessor.format(bytes,format:f,hexCase:c)
                let r = HexBytesProcessor.process(source,options:.init(inputFormat:f.inputFormat))
                #expect(r.status == .bytesOnly && r.artifact?.bytes == bytes)
                #expect(source.utf16.count == f.length(for:256))
                #expect(r.artifact?.text == nil)
            }
        }
        #expect(try HexBytesProcessor.format(Data([0,0xAB,0xFF]),format:.prefixed,hexCase:.lowercase) == "0x00, 0xab, 0xff")
        #expect(try HexBytesProcessor.format(Data([0xAB,0]),format:.escaped,hexCase:.uppercase) == #"\xAB\x00"#)
        #expect(HexBytesOutputFormat.prefixed.length(for:Int.max) == nil)
    }
    @Test func textExactUnicodeAndControls() {
        for source in ["", " ","\n",#"\n"#,"\u{0}A\u{0}","\u{FEFF}A","\r\n","😀","é","e\u{301}","\u{FFFD}","a\u{202e}b",String(Unicode.Scalar(0xFDD0)!),String(Unicode.Scalar(0x10FFFF)!)] {
            let encoded = HexBytesProcessor.process(source,options:.init(direction:.encode))
            let hex = encoded.artifact!.hex!
            let decoded = HexBytesProcessor.process(hex)
            #expect(encoded.artifact?.bytes == Data(source.utf8))
            #expect(decoded.artifact?.text?.utf16.elementsEqual(source.utf16) == true)
        }
        #expect(HexBytesProcessor.process("\n",options:.init(direction:.encode)).artifact?.hex == "0A")
        #expect(HexBytesProcessor.process(#"\n"#,options:.init(direction:.encode)).artifact?.hex == "5C 6E")
        #expect(HexBytesProcessor.process("00 41 00").issues.first?.code == .nul)
        #expect(HexBytesProcessor.process("EF BB BF 41").issues.first?.code == .leadingBOM)
        #expect(HexBytesProcessor.process("EF BF BD").status == .success)
        #expect(HexBytesProcessor.process("C3 A9").artifact?.bytes != HexBytesProcessor.process("65 CC 81").artifact?.bytes)
    }
    @Test func utf8DetectionRelatedAndNoReplacement() {
        for source in ["FF","80","C0 AF","F5 80 80 80"] {
            let r = HexBytesProcessor.process(source)
            #expect(r.status == .bytesOnly && r.artifact?.text == nil && r.artifact != nil)
            #expect(r.issues.first?.range == NSRange(location:0,length:2))
            #expect(r.issues.first?.byteOffset == 0 && r.issues.first?.related == nil)
        }
        for source in ["E0 80 80","ED A0 80","F0 80 80 80","F4 90 80 80","E2 28 A1"] {
            let r = HexBytesProcessor.process(source), i = r.issues.first
            #expect(r.status == .bytesOnly && i?.byteOffset == 1 && r.artifact?.text == nil)
            #expect(i?.range == NSRange(location:3,length:2) && i?.related == NSRange(location:0,length:2))
        }
        for source in ["F0 9F 98","F0 9F 98 \r\n"] {
            let r = HexBytesProcessor.process(source), i = r.issues.first
            #expect(r.status == .bytesOnly && i?.byteOffset == 3)
            #expect(i?.range == NSRange(location:source.utf16.count,length:0) && i?.related == NSRange(location:0,length:2))
            if source.hasSuffix("\r\n") { #expect(i?.line == 2 && i?.column == 1) }
        }
        let prefixed = HexBytesProcessor.process("0xE2, 0x28, 0xA1",options:.init(inputFormat:.prefixed)).issues.first
        #expect(prefixed?.range == NSRange(location:8,length:2) && prefixed?.related == NSRange(location:2,length:2))
    }
    @Test func utf8BoundaryCorpusAgainstIndependentSystemValidation() throws {
        var corpora: [[UInt8]] = [[],[0],[127],[0xC2,0x80],[0xDF,0xBF],[0xE0,0xA0,0x80],[0xED,0x9F,0xBF],[0xEE,0x80,0x80],
            [0xF0,0x90,0x80,0x80],[0xF4,0x8F,0xBF,0xBF],[0xE0,0x9F,0xBF],[0xED,0xA0,0x80],[0xF4,0x90,0x80,0x80],[0xFF],[0xE2,0x82]]
        for byte in UInt16(0)...255 { corpora.append([UInt8(byte)]) }
        var state: UInt64 = 0xC0FFEE
        for _ in 0..<4000 {
            var bytes = [UInt8]()
            for _ in 0..<8 { state = state &* 6364136223846793005 &+ 1; bytes.append(UInt8(truncatingIfNeeded:state >> 32)) }
            corpora.append(bytes)
        }
        for bytes in corpora {
            let data = Data(bytes)
            let native: String?
            if #available(macOS 15,iOS 18,*) { native = String(validating:data,as:UTF8.self) }
            else { let candidate = String(decoding:data,as:UTF8.self); native = candidate.utf8.elementsEqual(data) ? candidate : nil }
            #expect((try HexUTF8Validator.firstFailure(data)) == nil ? native != nil : native == nil)
        }
    }
    @Test func emptyResultsAndCheckParity() {
        for s in [""," \r\n\t","00","FF","F0 9F","4G","A","EF BB BF"] {
            let checked = HexBytesProcessor.process(s,intent:.check), converted = HexBytesProcessor.process(s)
            #expect(checked.status == converted.status && checked.byteCount == converted.byteCount)
            #expect(checked.issues == converted.issues && checked.artifact == nil)
        }
        #expect(HexBytesProcessor.process("").artifact?.bytes == Data())
        #expect(HexBytesProcessor.process("").artifact?.text == "")
        #expect(HexBytesProcessor.process(" \n\t").byteCount == 0)
    }
    @Test func resourceBoundariesAndCopyFormatIndependence() throws {
        #expect(HexBytesProcessor.process(String(repeating:"0",count:262_144)).artifact?.bytes.count == 131_072)
        #expect(HexBytesProcessor.process(String(repeating:"0",count:262_145)).status == .resourceLimit)
        for (f,fit,overflow) in [(HexBytesOutputFormat.compact,131_072,131_073),(.spaced,87_381,87_382),(.escaped,65_536,65_537),(.prefixed,43_691,43_692)] {
            let opts = HexBytesOptions(direction:.encode,outputFormat:f)
            for intent in [HexBytesIntent.check,.convert] {
                #expect(HexBytesProcessor.process(String(repeating:"A",count:fit),options:opts,intent:intent).status == .success)
                let refused = HexBytesProcessor.process(String(repeating:"A",count:overflow),options:opts,intent:intent)
                #expect(refused.status == .resourceLimit && refused.artifact == nil)
            }
        }
        #expect(HexBytesProcessor.process("4142",limits:.init(bytes:1)).issues.first?.code == .byteLimit)
        #expect(HexBytesProcessor.process("AA",options:.init(direction:.encode),limits:.init(bytes:1)).status == .resourceLimit)
        #expect(HexBytesProcessor.process("4142",limits:.init(outputUTF16:1)).status == .resourceLimit)
        let bytes = HexBytesProcessor.process(String(repeating:"41",count:131_072)).artifact!.bytes
        #expect(throws:(any Error).self) { try HexBytesProcessor.format(bytes,format:.spaced,hexCase:.uppercase) }
        #expect(try HexBytesProcessor.format(bytes,format:.compact,hexCase:.uppercase).count == 262_144)
    }
    @Test func presentationIsSafeBoundedAndRowExact() {
        let r = HexBytesProcessor.process("41\u{202e}00")
        #expect(r.issues.first?.context?.contains("\u{202e}") == false)
        #expect(r.issues.first?.context?.contains("\\u{202E}") == true)
        let long = HexBytesProcessor.process("a"+String(repeating:"\u{301}",count:200_000))
        #expect((long.issues.first?.context?.count ?? Int.max) < 200)
        let row = HexBytesRow(bytes:Data([0,0x41,0x7F,0xFF]),start:0,count:16)
        #expect(row.hex == "00 41 7F FF" && row.ascii == "·A··" && row.offset == "00000000")
        #expect(HexBytesRow(bytes:Data([1,2,3]),start:2,count:16).hex == "03")
        let dense = HexBytesProcessor.process(String(repeating:"00",count:10_000))
        #expect(dense.issueCount == 10_000 && dense.issues.count == 1 && dense.issues.first?.occurrences == 10_000)
    }
    @Test func preCancelledOperationsPublishNothing() async {
        let task = Task.detached { try? await Task.sleep(for:.milliseconds(10)); return HexBytesProcessor.process("4142") }
        task.cancel(); let r = await task.value
        #expect(r.status == .cancelled && r.artifact == nil)
        let formatter = Task.detached { try? await Task.sleep(for:.milliseconds(10)); return try? HexBytesProcessor.format(Data([0]),format:.compact,hexCase:.uppercase) }
        formatter.cancel(); #expect(await formatter.value == nil)
    }
}
