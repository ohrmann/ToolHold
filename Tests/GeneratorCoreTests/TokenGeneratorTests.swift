import Foundation
import Testing
@testable import GeneratorCore

struct TokenGeneratorTests {
    @Test func defaultEncodingAndExactBytes() throws {
        let options = TokenOptions()
        #expect(options.bytes == 32 && options.count == 1 && options.encoding == .base64URL)
        for length in [1,2,3,16,32,64,1024] {
            let expected = Data((0..<length).map { UInt8($0 & 255) })
            let batch = try #require(TokenGenerator.generate(.init(bytes: length), random: { (0..<$0).map { UInt8($0 & 255) } }).batch)
            #expect(batch.bytes == [expected])
            for encoding in TokenEncoding.allCases {
                let p = try TokenGenerator.present(batch, encoding: encoding, uppercase: false)
                #expect(p.values[0].count == encoding.length(length))
                switch encoding {
                case .hex: #expect(p.values[0].hasPrefix("00"))
                case .base64: #expect(Data(base64Encoded: p.values[0]) == expected)
                case .base64URL:
                    #expect(!p.values[0].contains("=")); let s = p.values[0].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    #expect(Data(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4)) == expected)
                }
            }
        }
    }
    @Test func limitsFailuresAndDuplicates() throws {
        for v in [TokenOptions(bytes: 0), .init(bytes: 1025), .init(count: 0), .init(count: 1001)] {
            #expect(TokenGenerator.generate(v, random: { _ in Issue.record("RNG for invalid options"); return [] }).issue?.status == .invalidOptions)
        }
        let batch = try #require(TokenGenerator.generate(.init(bytes: 1024, count: 1000), random: { Array(repeating: 0, count: $0) }).batch)
        #expect(batch.bytes.count == 1000 && batch.bytes[0] == batch.bytes[999])
        let p = try TokenGenerator.present(batch, encoding: .hex, uppercase: true)
        let json = try TokenGenerator.serialize(p, json: true)
        #expect((try JSONDecoder().decode([String].self, from: Data(json.utf8))) == p.values)
        let lines = try TokenGenerator.serialize(p, json: false)
        #expect(!lines.hasSuffix("\n") && lines.split(separator: "\n").count == 1000)
        #expect(TokenGenerator.generate(.init(), random: { _ in [] }).issue?.status == .entropyUnavailable)
        #expect(TokenGenerator.generate(.init(), random: { _ in throw CancellationError() }).issue?.status == .cancelled)
        #expect(TokenGenerator.generate(.init(), deadline: 0).issue?.status == .resourceLimit)
    }
    @Test @MainActor func workspaceFormattingAndPersistence() async throws {
        let name = "Token-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let s = TokenWorkspaceSession(defaults: defaults)
        #expect(s.batch == nil && s.canGenerate && !s.canCopy)
        await s.run()?.value
        let raw = try #require(s.batch?.bytes), id = s.batch?.id
        s.options.encoding = .hex
        for _ in 0..<500 where s.busy { try await Task.sleep(for: .milliseconds(2)) }
        #expect(s.batch?.id == id && s.batch?.bytes == raw)
        #expect(s.presentation?.values[0] == raw[0].map { String(format: "%02x", $0) }.joined())
        var copied = ""
        await s.copyAll(json: true) { copied = $0 }?.value
        #expect(try JSONDecoder().decode([String].self, from: Data(copied.utf8)) == s.presentation?.values)
        s.options.encoding = .base64
        s.bytesText = "64"
        for _ in 0..<500 where s.busy { try await Task.sleep(for: .milliseconds(2)) }
        #expect(s.settingsDiffer && s.batch?.bytes == raw && s.presentation?.encoding == .base64 && s.canCopy)
        s.options.encoding = .hex
        for _ in 0..<500 where s.busy { try await Task.sleep(for: .milliseconds(2)) }
        s.concealSecrets(); #expect(s.hidden)
        let fresh = TokenWorkspaceSession(defaults: defaults)
        #expect(fresh.options.bytes == 64 && fresh.options.encoding == .hex && fresh.batch == nil && fresh.presentation == nil && !fresh.hidden)
        s.clear(); #expect(s.batch == nil && s.rows.isEmpty && !s.canCopy)
        s.resetSettings(); #expect(s.bytesText == "32" && s.countText == "1")
    }
    actor Gate {
        var continuation: CheckedContinuation<TokenResult, Never>?
        var calls = 0
        func result(_ options: TokenOptions) async -> TokenResult {
            calls += 1
            if calls == 1 { return await withCheckedContinuation { continuation = $0 } }
            return TokenGenerator.generate(options, random: { Array(repeating: 2, count: $0) })
        }
        func finish() { continuation?.resume(returning: TokenGenerator.generate(.init(), random: { Array(repeating: 1, count: $0) })); continuation = nil }
    }
    @Test @MainActor func staleWorkerAndClear() async throws {
        let name = "Token-race-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let gate = Gate(), s = TokenWorkspaceSession(defaults: defaults, worker: { await gate.result($0) })
        let task = s.run()
        for _ in 0..<100 where await gate.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        s.bytesText = "64"; s.run(); await gate.finish(); await task?.value
        #expect(s.batch?.size == 64 && s.batch?.bytes.first?.first == 2)
        let clearing = TokenWorkspaceSession(defaults: defaults, worker: { _ in try? await Task.sleep(for: .milliseconds(30)); return .init(batch: .init(bytes: [Data([5])], size: 1)) })
        let old = clearing.run(); clearing.clear(); await old?.value
        #expect(clearing.batch == nil && !clearing.busy)
    }
}
