import SwiftUI
import Testing
@testable import JSONEditor

struct DelimitedEditorTests {
    @MainActor @Test func base64ContentLabelsDoNotRenameGeneratedCode() {
        let options = JSONEditorOptions(syntax: .plainText)
        let code = JSONTextEditor(text: .constant(""), editable: false, options: options)
        let input = JSONTextEditor(text: .constant(""), options: options, contentName: "Base64URL")
        #expect(code.editorAccessibilityLabel == "Generated code result")
        #expect(input.editorAccessibilityLabel == "Base64URL input")
        #expect(!options.needsTokens)
    }
    @Test func delimitedTextHasNoFakeJSONSyntaxOrPairs() {
        for syntax in [EditorSyntax.csv, .tsv, .xml, .toml, .plainText] {
            let options = JSONEditorOptions(syntax: syntax)
            #expect(!options.needsTokens)
        }
        #expect(JSONEditorOptions().needsTokens)
        #expect(JSONEditorOptions(syntax: .yaml).needsTokens)
        #expect(EditorSyntax.csv.name == "CSV" && EditorSyntax.tsv.name == "TSV")
    }
}
