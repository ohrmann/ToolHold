import Foundation
/// Optional, memory-only render data. It never alters the native document or Undo.
struct TextEditorHighlights: Sendable {
    let id:UUID
    let source:String
    let ranges:[NSRange]
    var active:NSRange?
    var capture:NSRange?
}
