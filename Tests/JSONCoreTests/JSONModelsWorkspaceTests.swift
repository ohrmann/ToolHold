import Foundation
import Testing
@testable import JSONCore

@MainActor struct JSONModelsWorkspaceTests {
    @Test func pasteCheckGenerateCacheAndCurrentOutput() async throws {
        let defaults = UserDefaults(suiteName: "ModelsTests.\(UUID())")!
        let repository = JSONPreferencesRepository(defaults: defaults)
        let session = JSONModelsWorkspaceSession(repository: repository)
        session.input = #"{"price":1.25,"name":"private value"}"#
        #expect(!session.busy && session.result == nil)
        await session.didPaste()?.value
        #expect(session.result?.status == .success && session.output == nil)
        #expect(session.analysisCount == 1)
        await session.run().value
        let output = try #require(session.output)
        #expect(session.canCopy && session.analysisCount == 1)
        await session.run(generate: false).value
        #expect(session.output == output)
        session.language = .java
        await session.run(generate: false).value
        #expect(session.output == nil && !session.canCopy)
        session.language = .swift
        await session.run().value
        let repeatWork = session.run()
        session.cancel()
        await repeatWork.value
        #expect(session.output == output && session.wasCancelled)
        session.input = #"{"name":"é"}"#
        #expect(session.output == nil && session.result == nil && session.analysis == nil)
        await session.run().value
        session.input = #"{"name":"e\u0301"}"#
        #expect(session.output == nil)
        session.preferences.validateOnPaste = false
        #expect(session.didPaste() == nil)
        session.clear()
        #expect(session.input.isEmpty && session.result == nil)
        let stored = try #require(defaults.data(forKey: JSONPreferencesRepository.key))
        let text = String(decoding: stored, as: UTF8.self)
        #expect(!text.contains("private value") && !text.contains("RootModel"))
        #expect(!text.contains("input") && !text.contains("output"))
        let restored = JSONModelsWorkspaceSession(repository: repository)
        #expect(restored.input.isEmpty && restored.output == nil && restored.analysis == nil)
        session.input = "{\r\n\"value\":9007199254740993}"
        session.language = .typeScript
        await session.run().value
        #expect(session.result?.status == .unsupported)
        #expect(session.context != nil && session.sourceLocation?.contains("Line 2") == true)
        session.input = String(repeating: " ", count: JSONProcessor.maximumUTF16Length + 1)
        await session.run().value
        #expect(session.result?.status == .resourceLimit && session.context == nil && session.sourceLocation == nil)
    }

    @Test func optionRendersReuseAnalysisAndPreferencesMigrate() async throws {
        let defaults = UserDefaults(suiteName: "ModelsTests.\(UUID())")!
        defaults.set(Data(#"{"wordWrap":false,"modelLanguage":"futureLanguage"}"#.utf8), forKey: JSONPreferencesRepository.key)
        let session = JSONModelsWorkspaceSession(repository: .init(defaults: defaults))
        #expect(session.language == .swift && !session.preferences.wordWrap)
        session.input = #"{"name":"x"}"#
        await session.run().value
        session.language = .kotlin
        #expect(!session.canCopy)
        await session.run().value
        #expect(session.analysisCount == 1)
        #expect(session.artifact?.fileName == "RootModel.kt")
        #expect(session.output?.contains("@Serializable") == true)
        session.rootName = "SampleRoot"
        await session.run().value
        #expect(session.analysisCount == 1 && session.artifact?.fileName == "SampleRoot.kt")
        let restored = JSONModelsWorkspaceSession(repository: .init(defaults: defaults))
        #expect(restored.language == .kotlin && restored.rootName == "RootModel" && restored.input.isEmpty)
        session.rootName = "../bad"
        await session.run().value
        #expect(session.result?.status == .invalidOptions && session.output == nil)
    }

    @Test func staleNonCooperativeWorkerCannotPublish() async {
        actor Gate {
            var release: CheckedContinuation<Void, Never>?
            var start: CheckedContinuation<Void, Never>?
            var started = false
            func waitForStart() async { if started { return }; await withCheckedContinuation { start = $0 } }
            func pause() async { await withCheckedContinuation { release = $0; started = true; start?.resume(); start = nil } }
            func resume() { release?.resume(); release = nil }
        }
        let gate = Gate()
        let defaults = UserDefaults(suiteName: "ModelsTests.\(UUID())")!
        let session = JSONModelsWorkspaceSession(repository: .init(defaults: defaults), worker: { source, options, cached, generate in
            let analysis = cached ?? JSONModelGenerator.analyze(source)
            let result = JSONModelGenerator.generate(analysis, options: options)
            if source == "1" { await gate.pause() }
            return (analysis, result)
        })
        session.input = "1"
        let stale = session.run()
        await gate.waitForStart()
        session.input = "true"
        session.language = .typeScript
        await session.run().value
        await gate.resume()
        await stale.value
        #expect(session.artifact?.fileName == "RootModel.ts")
        #expect(session.artifact?.rootType == "boolean")
        #expect(session.analysisCount == 1 && session.input == "true")
    }
}
