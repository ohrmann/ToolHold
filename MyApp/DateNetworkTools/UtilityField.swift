import SwiftUI

#if os(macOS)
  import AppKit
  /// Native single-line input. Publish only committed text, so composition never launches calculations.
  struct UtilityField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    var focusToken: Int = 0
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
      let field = NSTextField(string: text)
      field.placeholderString = title
      field.delegate = context.coordinator
      field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
      field.setAccessibilityLabel(title)
      field.lineBreakMode = .byTruncatingTail
      field.cell?.isScrollable = true
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
      context.coordinator.parent = self
      let marked = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
      if !marked && !field.stringValue.utf16.elementsEqual(text.utf16) { field.stringValue = text }
      if context.coordinator.focus != focusToken {
        context.coordinator.focus = focusToken
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
      }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
      var parent: UtilityField
      var focus = 0
      init(_ parent: UtilityField) { self.parent = parent }
      func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
          !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false)
        else { return }
        parent.text = field.stringValue
      }
      func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField { parent.text = field.stringValue }
      }
    }
  }
#else
  import UIKit
  struct UtilityField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    var focusToken: Int = 0
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
      let field = UITextField()
      field.text = text
      field.placeholder = title
      field.borderStyle = .roundedRect
      field.font = UIFontMetrics.default.scaledFont(
        for: .monospacedSystemFont(ofSize: 15, weight: .regular))
      field.adjustsFontForContentSizeCategory = true
      field.textColor = .label
      field.accessibilityLabel = title
      field.autocorrectionType = .no
      field.autocapitalizationType = .none
      field.smartQuotesType = .no
      field.smartDashesType = .no
      field.addTarget(
        context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
      context.coordinator.parent = self
      if field.markedTextRange == nil && !(field.text ?? "").utf16.elementsEqual(text.utf16) {
        field.text = text
      }
      if context.coordinator.focus != focusToken {
        context.coordinator.focus = focusToken
        DispatchQueue.main.async { field.becomeFirstResponder() }
      }
    }
    final class Coordinator: NSObject {
      var parent: UtilityField
      var focus = 0
      init(_ parent: UtilityField) { self.parent = parent }
      @objc func changed(_ field: UITextField) {
        guard field.markedTextRange == nil else { return }
        parent.text = field.text ?? ""
      }
    }
  }
#endif

struct UtilityLabeledField: View {
  let title: String
  @Binding var text: String
  var placeholder = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.subheadline.weight(.medium))
      UtilityField(title: placeholder.isEmpty ? title : placeholder, text: $text).frame(
        minHeight: 30)
    }
  }
}
