import Testing
import Foundation
import Contacts
import Vision
@testable import QRCodeCore

struct QRCodeContentTests {
    @Test func uriProfilesAndEscaping() throws {
        var f = QRContentFields()
        f.url = "https://example.com/a?x=%2F&b=é#part"
        #expect(try QRCodeContent.make(.url,text:"",fields:f) == "https://example.com/a?x=%2F&b=%C3%A9#part")
        f.emailAddress = "first+tag@example.com"; f.emailSubject = "A & B? 🌍"; f.emailBody = "one\ntwo & bcc=none"
        let mail = try QRCodeContent.make(.email,text:"",fields:f)
        #expect(mail.hasPrefix("mailto:first%2Btag@example.com?subject="))
        let query = try #require(URLComponents(string:mail)?.queryItems)
        #expect(query.count == 2 && query[0].value == f.emailSubject && query[1].value == "one\r\ntwo & bcc=none")
        f.phoneNumber = "+420 (123) 456-789"; f.smsNumber = "+420.123.456.789"; f.smsBody = "Hi & ? 🌍"
        #expect(try QRCodeContent.make(.phone,text:"",fields:f) == "tel:+420123456789")
        #expect(try QRCodeContent.make(.sms,text:"",fields:f) == "sms:+420123456789?body=Hi%20%26%20%3F%20%F0%9F%8C%8D")
        let raw = "  é\r\n\u{0}"
        #expect(try QRCodeContent.make(.freeText,text:raw,fields:f).utf8.elementsEqual(raw.utf8))
    }
    @Test func urlSerializationAndDecodedReaderText() throws {
        let fixtures = [
            ("https://example.com", "https://example.com"),
            ("https://münich.example/путь?q=é#🌍", "https://xn--mnich-kva.example/%D0%BF%D1%83%D1%82%D1%8C?q=%C3%A9#%F0%9F%8C%8D"),
            ("https://example.com/a%2Fb?x=%25&y=1+2", "https://example.com/a%2Fb?x=%25&y=1+2"),
            ("https://example.com:8443/a?x=1&y=2", "https://example.com:8443/a?x=1&y=2")
        ]
        for (input,expected) in fixtures {
            var f = QRContentFields(); f.url = input
            let source = try QRCodeContent.make(.url,text:"",fields:f)
            #expect(source == expected)
            for style in QRModuleStyle.allCases {
                var p = QRPreferences(); p.style = style
                let artifact = try QRCodeProcessor.generate(source:source,preferences:p,logo:nil)
                #expect(artifact.verification.passed)
                // Verify actual reader text, not only codeword equality to the pristine QR.
                let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
                try VNImageRequestHandler(cgImage:artifact.image).perform([request])
                let decoded = try #require(request.results?.first?.payloadStringValue)
                #expect(decoded == expected,"URL reader text / \(style.rawValue)")
                #expect(URL(string:decoded)?.host != nil)
            }
        }
        for input in ["https:example.com", "https://", "https://example.com/%", "https://example.com/%GG", "www.example.com", "https://example.com/\n"] {
            var f = QRContentFields(); f.url = input
            #expect(throws:QRIssue.self) { try QRCodeContent.make(.url,text:"",fields:f) }
        }
    }
    @Test func wifiProfilesAndExactEscapes() throws {
        var f = QRContentFields(); f.ssid = "a;b,c:Z\"\\"; f.password = "p;:\\"; f.hiddenNetwork = true
        #expect(try QRCodeContent.make(.wifi,text:"",fields:f) == "WIFI:T:WPA;S:a\\;b\\,c\\:Z\\\"\\\\;P:p\\;\\:\\\\;H:true;;")
        f.security = .open
        let open = try QRCodeContent.make(.wifi,text:"",fields:f)
        #expect(open.hasPrefix("WIFI:T:nopass;") && !open.contains("P:"))
        f.security = .wep
        #expect(try QRCodeContent.make(.wifi,text:"",fields:f).hasPrefix("WIFI:T:WEP;"))
        f.ssid = String(repeating:"🌍",count:9)
        #expect(throws:QRIssue.self) { try QRCodeContent.make(.wifi,text:"",fields:f) }
    }
    @Test func vCardParsesWithoutPropertyInjectionAndFoldsUTF8() throws {
        var f = QRContentFields(); f.firstName = "Zoë 🌍"; f.lastName = "Name;Comma,\\\nTEL:injected"
        f.organization = String(repeating:"é中文🌍",count:20); f.contactEmail = "person@example.com"; f.contactPhone = "+420123456789"
        f.street = "One; Two, Three"; f.city = "Prague"; f.country = "Czechia"
        let card = try QRCodeContent.make(.contact,text:"",fields:f)
        #expect(card.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0\r\n")); #expect(card.hasSuffix("END:VCARD\r\n"))
        for line in card.components(separatedBy:"\r\n") { #expect(line.utf8.count <= 75) }
        let parsed = try CNContactVCardSerialization.contacts(with:Data(card.utf8))
        let contact = try #require(parsed.first)
        #expect(parsed.count == 1 && contact.givenName == f.firstName && contact.familyName == f.lastName)
        #expect(contact.organizationName == f.organization)
        #expect(contact.phoneNumbers.count == 1 && contact.phoneNumbers[0].value.stringValue == f.contactPhone)
        #expect(contact.postalAddresses.first?.value.street == f.street)
    }
    @Test func incompleteOrInjectedFieldsHaveSpecificErrors() throws {
        for kind in QRContentKind.allCases where kind != .freeText {
            #expect(throws:QRIssue.self) { try QRCodeContent.make(kind,text:"",fields:.init()) }
        }
        var f = QRContentFields(); f.url = "https://example.com/space here"
        #expect(throws:QRIssue.self) { try QRCodeContent.make(.url,text:"",fields:f) }
        f.emailAddress = "a@example.com?bcc=x"; f.emailSubject = "line\r\nBcc: injected"
        #expect(throws:QRIssue.self) { try QRCodeContent.make(.email,text:"",fields:f) }
        f.phoneNumber = "12345"
        #expect(throws:QRIssue.self) { try QRCodeContent.make(.phone,text:"",fields:f) }
    }
    @Test func structuredProfilesWithDecoratedEyesRoundTrip() throws {
        var f = QRContentFields(); f.url = "https://example.com/a?x=1&y=2"
        f.firstName = "Ada"; f.lastName = "Lovelace"; f.contactEmail = "ada@example.com"
        f.ssid = "Local WiFi"; f.password = "synthetic;password"
        f.emailAddress = "name@example.com"; f.emailSubject = "Hello 🌍"; f.emailBody = "Some text"
        f.phoneNumber = "+420123456789"; f.smsNumber = f.phoneNumber; f.smsBody = "Hello"
        for kind in QRContentKind.allCases {
            let source = try QRCodeContent.make(kind,text:"free text",fields:f)
            for style in QRModuleStyle.allCases {
                var p = QRPreferences(); p.style = style
                let a = try QRCodeProcessor.generate(source:source,preferences:p,logo:nil)
                #expect(a.verification.passed,"\(kind.rawValue)/\(style.rawValue)")
                #expect(a.matrix.payload == Data(source.utf8))
                let export = try QRCodeProcessor.export(a,format:.svg)
                #expect(!export.data.isEmpty)
            }
        }
    }
}

extension QRCodeSessionTests {
    @Test func contentDraftsAreIndependentAndNeverPersisted() async throws {
        let name = "qr-forms-"+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let s = QRCodeWorkspaceSession(defaults:defaults)
        s.input = "free draft"; s.contentKind = .wifi
        #expect(s.payload.isEmpty && !s.canOutput)
        s.fields.ssid = "synthetic network"; s.fields.password = "sensitive-password"; s.generate(); try await wait(s)
        #expect(s.canOutput && String(decoding:s.artifact!.matrix.payload,as:UTF8.self).contains("sensitive-password"))
        s.contentKind = .url; #expect(!s.canOutput)
        s.fields.url = "https://example.com/first"; s.generate(); try await wait(s)
        #expect(s.payload == s.fields.url && s.canOutput)
        s.contentKind = .freeText; #expect(s.input == "free draft" && s.payload == "free draft")
        s.contentKind = .wifi; #expect(s.fields.password == "sensitive-password")
        s.preferences.style = .dots
        let fresh = QRCodeWorkspaceSession(defaults:defaults)
        #expect(fresh.contentKind == .freeText && fresh.payload.isEmpty && fresh.fields.password.isEmpty && fresh.fields.url.isEmpty)
        let stored = String(decoding:defaults.data(forKey:QRCodeWorkspaceSession.key)!,as:UTF8.self)
        #expect(!stored.contains("sensitive-password") && !stored.contains("synthetic network") && !stored.contains("example.com"))
        s.clear(); #expect(s.payload.isEmpty && s.input.isEmpty && s.fields.password.isEmpty && s.fields.url.isEmpty)
    }
}
