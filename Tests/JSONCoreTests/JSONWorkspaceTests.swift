import Foundation
import Testing
@testable import JSONCore

@MainActor
struct JSONWorkspaceTests {
    private func session() -> JSONWorkspaceSession {
        let defaults = UserDefaults(suiteName: "JSONWorkspaceTests.\(UUID())")!
        return JSONWorkspaceSession(repository: .init(defaults: defaults))
    }

    @Test func exactUnicodeEditsInvalidateOutputAndDiagnostics() async throws {
        // The Angstrom pair even has the same UTF-16 length. Neither String ==
        // nor a length comparison can establish the identity of a JSON snapshot.
        for (first, second) in [("\u{00E9}", "e\u{0301}"), ("\u{00C5}", "\u{212B}"),
                                ("\u{AC00}", "\u{1100}\u{1161}")] {
            let source = "{\"name\":\"👩🏽‍💻\(first)\"}"
            let edited = "{\"name\":\"👩🏽‍💻\(second)\"}"
            #expect(source == edited)
            #expect(!source.utf16.elementsEqual(edited.utf16))
            let model = session()
            model.input = source
            await model.run(.format).value
            let originalOutput = try #require(model.output)
            model.input = source
            #expect(model.output?.utf16.elementsEqual(originalOutput.utf16) == true)

            model.input = edited
            #expect(model.input.utf16.elementsEqual(edited.utf16))
            #expect(model.output == nil && model.result == nil && model.context == nil)
            #expect(!model.busy && !model.wasCancelled)
            await model.run(.minify).value
            #expect(model.output?.utf16.elementsEqual(edited.utf16) == true)
            await model.run(.format).value
            let expected = "{\n  \"name\": \"👩🏽‍💻\(second)\"\n}"
            #expect(model.output?.utf16.elementsEqual(expected.utf16) == true)
            await model.run(.validate).value
            #expect(model.output?.utf16.elementsEqual(expected.utf16) == true)

            // Invalid source also has source-scoped coordinates/context to clear.
            model.input = String(source.dropLast())
            await model.run(.validate).value
            #expect(model.result?.status == .invalid && model.context != nil)
            model.input = String(edited.dropLast())
            #expect(model.result == nil && model.context == nil && model.output == nil)
        }
    }

    @Test func exactUnicodeEditCancelsPendingSourceSnapshot() async {
        let model = session()
        model.input = "{\"name\":\"\u{00E9}\"}"
        let pending = model.run(.format)
        model.input = "{\"name\":\"e\u{0301}\"}"
        await pending.value
        #expect(model.output == nil && model.result == nil && model.context == nil)
        #expect(!model.busy && !model.wasCancelled)
        await model.didPaste()?.value
        #expect(model.result?.status == .valid && model.output == nil)
    }

    @Test func validateAndCancelKeepFreshOutputButEditingInvalidatesIt() async {
        let model = session()
        model.input = #"{"n":9007199254740993}"#
        await model.run(.format).value
        let output = model.output
        #expect(output != nil)
        await model.run(.validate).value
        #expect(model.output == output)
        #expect(model.result?.isValid == true)
        let operation = model.run(.minify)
        model.cancel()
        await operation.value
        #expect(model.wasCancelled)
        #expect(model.output == output)
        model.input += " "
        #expect(model.output == nil)
        #expect(model.result == nil)
        #expect(model.context == nil)
        #expect(!model.wasCancelled)
    }

    @Test func pasteOnlyValidatesAndNeverChangesInputOrOutput() async {
        let model = session()
        model.input = #"{"x":1}"#
        #expect(!model.busy)
        #expect(model.result == nil) // ordinary typing / binding updates do not validate
        let paste = model.didPaste()
        #expect(model.busy)
        await paste?.value
        #expect(model.result?.isValid == true)
        #expect(model.output == nil)
        #expect(model.input == #"{"x":1}"#)
        model.preferences.validateOnPaste = false
        model.input = "invalid"
        model.didPaste()
        #expect(!model.busy)
        #expect(model.result == nil)
    }

    @Test func staleRequestsCannotPublishAfterEditOrClear() async {
        let model = session()
        model.input = "[" + Array(repeating: "123", count: 20_000).joined(separator: ",") + "]"
        let old = model.run(.format)
        model.input = "broken"
        let current = model.run(.validate)
        await old.value
        await current.value
        #expect(model.output == nil)
        #expect(model.result?.isValid == false)
        let pending = model.run(.validate)
        model.clear()
        await pending.value
        #expect(model.input.isEmpty)
        #expect(model.output == nil)
        #expect(model.result == nil)
        #expect(!model.busy)
    }

    @Test func resourceLimitsAreNotReportedAsSyntaxErrors() async {
        let model = session()
        for source in [String(repeating: "x", count: JSONProcessor.maximumUTF16Length + 1),
                       String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)] {
            model.input = source
            await model.run(.validate).value
            #expect(model.resourceLimited)
            #expect(model.output == nil)
        }
    }

    @Test func preferencesPersistButNewSessionsContainNoWorkingData() async throws {
        let domain = "JSONPreferencesTests.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let repository = JSONPreferencesRepository(defaults: defaults)
        let model = JSONWorkspaceSession(repository: repository)
        #expect(model.preferences.indentation == .two)
        #expect(model.preferences.validateOnPaste)
        #expect(model.preferences.syntaxHighlighting && model.preferences.rainbowBrackets && model.preferences.matchingBrackets && model.preferences.wordWrap)
        model.preferences.indentation = .four
        model.preferences.validateOnPaste = false
        model.preferences.syntaxHighlighting = false
        model.preferences.rainbowBrackets = false
        model.preferences.matchingBrackets = false
        model.preferences.wordWrap = false
        model.input = #"{"secret":"ephemeral"}"#
        await model.run(.format).value
        #expect(model.output == "{\n    \"secret\": \"ephemeral\"\n}")
        let restored = JSONWorkspaceSession(repository: repository)
        #expect(restored.preferences == model.preferences)
        #expect(restored.input.isEmpty)
        #expect(restored.output == nil)
        #expect(restored.result == nil)
        let data = try #require(defaults.data(forKey: JSONPreferencesRepository.key))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["indentation", "validateOnPaste", "syntaxHighlighting", "rainbowBrackets", "matchingBrackets", "wordWrap", "schemaValidateFormats", "schemaAssumedDialect", "modelLanguage"])
        #expect(defaults.persistentDomain(forName: domain)?.count == 1)
        defaults.set(Data(#"{"indentation":8,"validateOnPaste":"unknown"}"#.utf8), forKey: JSONPreferencesRepository.key)
        #expect(repository.load() == JSONToolPreferences())
    }
}
