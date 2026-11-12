import Foundation
import Testing
@testable import EncodingCore

struct URLPercentProcessorTests {
    private func run(_ text: String, _ direction: URLPercentDirection = .encode,
                     _ profile: URLPercentProfile = .component, preserve: Bool = true) -> URLPercentResult {
        URLPercentProcessor.process(text, options: .init(direction: direction, profile: profile, preserveExistingEscapes: preserve))
    }
    @Test func goldenProfilesAndSinglePass() {
        let fixtures: [(String,URLPercentDirection,URLPercentProfile,Bool,String)] = [
            ("a b+c/d?e=f&g#h",.encode,.component,true,"a%20b%2Bc%2Fd%3Fe%3Df%26g%23h"),
            ("a b+c~*",.encode,.formField,true,"a+b%2Bc%7E*"),
            ("a+b%2Bc%20d",.decode,.component,true,"a+b+c d"),
            ("a+b%2Bc%20d",.decode,.uriText,true,"a+b+c d"),
            ("a+b%2Bc%20d",.decode,.formField,true,"a b+c d"),
            ("%2F",.encode,.component,true,"%252F"), ("%2F",.encode,.formField,true,"%252F"),
            ("%252F",.decode,.component,true,"%2F"),
            ("https://example.test/a b?q=x%2fy&x=1#part",.encode,.uriText,true,"https://example.test/a%20b?q=x%2fy&x=1#part"),
            ("/a%2fb",.encode,.uriText,false,"/a%252fb"),
            ("!*'()~",.encode,.component,true,"%21%2A%27%28%29~"),
            ("!*'()~",.encode,.formField,true,"%21*%27%28%29%7E"),
            ("/a%2Fb?x=%26",.decode,.uriText,true,"/a/b?x=&"),
            ("%0A%202",.decode,.component,true,"\n 2"),
            ("%G1",.encode,.component,true,"%25G1"), ("%G1",.encode,.formField,true,"%25G1")
        ]
        for (source,direction,profile,preserve,expected) in fixtures {
            let result = run(source,direction,profile,preserve:preserve)
            #expect(result.status == .success)
            #expect(result.artifact?.text?.utf16.elementsEqual(expected.utf16) == true)
        }
        #expect(run("%2f%26",.decode,.uriText).issues.contains { $0.code == .decodedDelimiter })
        #expect(run("%41",.decode,.uriText).issues.isEmpty)
        #expect(run("%FF",.encode,.uriText).artifact?.text == "%FF")
    }
    @Test func unicodeLexemesAndExactRoundTrips() {
        for source in ["é","e\u{301}","😀","\u{FEFF}\0\r\n","a\u{202E}z","\u{FFFD}","+% /?#&="] {
            for profile in URLPercentProfile.allCases {
                let encoded = run(source,.encode,profile,preserve:false)
                let decoded = run(encoded.artifact!.text!,.decode,profile)
                #expect(decoded.artifact?.text?.utf16.elementsEqual(source.utf16) == true)
            }
        }
        #expect(run("é").artifact?.text == "%C3%A9")
        #expect(run("e\u{301}").artifact?.text == "e%CC%81")
        #expect(run("😀").artifact?.text == "%F0%9F%98%80")
        #expect(run("%EF%BF%BD",.decode).status == .success)
        let bom = run("%EF%BB%BF%00%0D%0A",.decode)
        #expect(bom.artifact?.text == "\u{FEFF}\0\r\n")
        #expect(Set(bom.issues.map(\.code)) == [.leadingBOM,.controls])
    }
    @Test func allASCIIAndIndependentFoundationOracle() {
        let source = String(String.UnicodeScalarView((0...127).map { Unicode.Scalar($0)! }))
        let allowed = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = run(source)
        #expect(encoded.artifact?.text == source.addingPercentEncoding(withAllowedCharacters:allowed))
        #expect(run(encoded.artifact!.text!,.decode).artifact?.text == source)
        for byte in 0...127 {
            let escape = String(format:"%%%02x",byte)
            #expect(run(escape,.decode).artifact?.text == String(Unicode.Scalar(byte)!))
        }
    }
    @Test func invalidUTF8IsBytesNotRepairedText() {
        for source in ["%FF","%C0%AF","%ED%A0%80","%F4%90%80%80","%E2%82","%80","%FE"] {
            let result = run(source,.decode)
            #expect(result.status == .bytesOnly && result.artifact?.text == nil)
            #expect(result.issues.first?.code == .invalidUTF8 && result.issues.first?.range == nil)
            #expect(!result.preview.isEmpty)
        }
        let long = run(String(repeating:"%FF",count:100),.decode)
        #expect(long.byteCount == 100 && long.preview.split(separator:" ").count == 64)
    }
    @Test func detectionAnchorsAndSafeContext() {
        for profile in URLPercentProfile.allCases {
            let invalid = run("😀\r\n%G1",.decode,profile)
            #expect(invalid.status == .invalidPercentEncoding && invalid.artifact == nil)
            #expect(invalid.issues.first?.range == NSRange(location:4,length:3))
            #expect(invalid.issues.first?.line == 2 && invalid.issues.first?.column == 1)
            let eof = run("😀\r\n%A",.decode,profile)
            #expect(eof.issues.first?.range == NSRange(location:6,length:0))
            #expect(eof.issues.first?.line == 2 && eof.issues.first?.column == 3)
            #expect(eof.issues.first?.context?.contains("│ EOF") == true)
        }
        for source in ["%","%A","%G1","%😀A"] {
            #expect(run(source,.encode,.uriText).status == .invalidPercentEncoding)
            #expect(run(source,.encode,.uriText,preserve:false).status == .success)
        }
        let context = run(String(repeating:"x",count:100) + "e\u{301}\u{202E}%G1" + String(repeating:"x",count:100),.decode).issues[0].context!
        #expect(context.hasPrefix("…") && context.hasSuffix("…"))
        #expect(context.contains("e\u{301}") && context.contains("\\u{202E}") && !context.contains("\u{202E}"))
        #expect(context.contains("⟦%G1⟧"))
        let combining = run("e\u{301}%G1",.decode).issues[0]
        #expect(combining.range == NSRange(location:2,length:3) && combining.column == 3)
        let giant = run("e" + String(repeating:"\u{301}",count:10_000) + "%",.decode)
        #expect(giant.issues[0].context!.utf16.count < 200)
    }
    @Test func resourceBoundariesAndCheckParity() {
        #expect(run(String(repeating:"a",count:262_144)).status == .success)
        #expect(run(String(repeating:"a",count:262_145)).status == .resourceLimit)
        #expect(run(String(repeating:" ",count:87_381)).artifact?.text?.utf16.count == 262_143)
        #expect(run(String(repeating:" ",count:87_382)).status == .resourceLimit)
        let limits = URLPercentLimits(inputUTF16:3,outputUTF16:2,bytes:1)
        let result = URLPercentProcessor.process("%FF",options:.init(direction:.decode),limits:limits)
        #expect(result.status == .bytesOnly)
        #expect(URLPercentProcessor.process("ab",options:.init(direction:.decode),limits:limits).status == .resourceLimit)
        for source in ["","abc","%FF","%A",String(repeating:" ",count:87_382)] {
            for direction in URLPercentDirection.allCases {
                let options = URLPercentOptions(direction:direction)
                let check = URLPercentProcessor.process(source,options:options,intent:.check)
                let converted = URLPercentProcessor.process(source,options:options)
                #expect(check.status == converted.status && check.byteCount == converted.byteCount)
                #expect(check.artifact == nil)
            }
        }
        #expect(run("").artifact?.text == "")
    }
    @Test func cancellationHasNoPartialArtifact() async {
        let work = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return URLPercentProcessor.process(String(repeating:"x",count:262_144))
        }
        let result = await work.value
        #expect(result.status == .cancelled && result.artifact == nil && result.issues.isEmpty)
    }
}
