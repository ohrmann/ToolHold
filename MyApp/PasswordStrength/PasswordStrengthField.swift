import SwiftUI

// Dedicated exact single-line adapter: Basic Auth restrictions do not apply to passwords.
enum PasswordStrengthFieldRole: String { case revealed, concealed }
struct PasswordStrengthIssue { let message: String }
enum PasswordStrengthFieldValidation {
    static func issue(_ text: String) -> PasswordStrengthIssue? {
        if text.utf16.prefix(4097).count > 4096 { return .init(message: "Input rejected: maximum 4,096 UTF-16 units. Previous value unchanged.") }
        if text.unicodeScalars.contains(where: { [0,9,10,13].contains($0.value) }) { return .init(message: "Input rejected: newline, tab and NUL are not supported. Previous value unchanged.") }
        return nil
    }
}


@MainActor final class PasswordStrengthFieldCommands {
    var clear: (() -> Void)?
    var focus: (() -> Void)?
    var paste: (() -> Void)?
    var resignFocus: (() -> Void)?
}

struct PasswordStrengthField {
    @Binding var text: String
    let field: PasswordStrengthFieldRole
    let commands: PasswordStrengthFieldCommands
    var reject: (PasswordStrengthIssue) -> Void
    var submit: () -> Void
    var pasted: () -> Void = {}
    private var name: String { "Password" }
}

#if os(macOS)
import AppKit

/// Keeps the system's secure field editor. Only explicit Paste reads the clipboard.
private final class PasswordStrengthSecureCell: NSSecureTextFieldCell {
    weak var owner: PasswordStrengthMacField?
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        if let view = editor as? NSTextView { owner?.configure(view) }
        return editor
    }
}
private final class PasswordStrengthPlainCell: NSTextFieldCell {
    weak var owner: PasswordStrengthMacField?
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        if let view = editor as? NSTextView { owner?.configure(view) }
        return editor
    }
}
final class PasswordStrengthMacField: NSView {
    let input: NSTextField
    init(secure: Bool) {
        input = secure ? NSSecureTextField() : NSTextField()
        super.init(frame: .zero)
        addSubview(input); input.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([input.leadingAnchor.constraint(equalTo: leadingAnchor), input.trailingAnchor.constraint(equalTo: trailingAnchor), input.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    var stringValue: String { get { input.stringValue } set { input.stringValue = newValue } }
    func currentEditor() -> NSText? { input.currentEditor() }
    var role = PasswordStrengthFieldRole.revealed
    var rejected: ((PasswordStrengthIssue) -> Void)?
    var changed: ((String) -> Void)?
    var pasted: (() -> Void)?
    private var pasteMonitor: Any?
    private var menuTargets: [(NSMenuItem, AnyObject?, Selector?)] = []
    func restorePasteMenu() {
        for (item, target, action) in menuTargets where item.target === self { item.target = target; item.action = action }
        menuTargets.removeAll()
    }
    func routePasteMenu(_ menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items {
            if let submenu = item.submenu { routePasteMenu(submenu) }
            if let action = item.action, ["paste:", "pasteAsPlainText:", "pasteAndMatchStyle:"].contains(NSStringFromSelector(action)), item.target !== self {
                menuTargets.append((item, item.target as AnyObject?, action))
                item.target = self; item.action = #selector(pasteCredentials(_:))
            }
        }
    }
    func allows(_ source: String) -> Bool {
        if let issue = PasswordStrengthFieldValidation.issue(source) { rejected?(issue); return false }
        return true
    }
    func configure(_ editor: NSTextView) {
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false; editor.isGrammarCheckingEnabled = false
        editor.unregisterDraggedTypes() // Credentials accept only validated text entry and explicit Paste.
        let menu = NSMenu()
        if role != .concealed { menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "") }
        let paste = menu.addItem(withTitle: "Paste", action: #selector(pasteCredentials(_:)), keyEquivalent: "")
        paste.target = self
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        editor.menu = menu
        routePasteMenu(NSApp.mainMenu)
        if pasteMonitor == nil {
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let editor = self.currentEditor(), editor === self.window?.firstResponder,
                      event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
                      event.charactersIgnoringModifiers?.lowercased() == "v" || event.keyCode == 9 else { return event }
                self.pasteCredentials(nil); return nil
            }
        }
    }
    @objc func pasteCredentials(_ sender: Any?) {
        guard let value = NSPasteboard.general.string(forType: .string),
              let editor = currentEditor() as? NSTextView else { return }
        guard allows((editor.string as NSString).replacingCharacters(in:editor.selectedRange(),with:value)) else { return }
        editor.insertText(value, replacementRange: editor.selectedRange()); pasted?()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            restorePasteMenu()
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor); self.pasteMonitor = nil }
        }
    }
    func erase() {
        restorePasteMenu()
        window?.endEditing(for: input)
        stringValue = "" // End editing discards this single-line field's native editing session.
        changed?("")
    }
}

extension PasswordStrengthField: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PasswordStrengthMacField {
        let view = PasswordStrengthMacField(secure: field == .concealed)
        view.role = field
        if field == .concealed {
            let cell = PasswordStrengthSecureCell(textCell: ""); cell.owner = view; view.input.cell = cell
        } else { let cell = PasswordStrengthPlainCell(textCell: ""); cell.owner = view; view.input.cell = cell }
        view.input.isEditable = true; view.input.isSelectable = true; view.input.isBezeled = true; view.input.bezelStyle = .roundedBezel
        view.input.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.input.cell?.isScrollable = true; view.input.maximumNumberOfLines = 1
        view.input.setAccessibilityLabel(name); view.input.setAccessibilityIdentifier("password-strength-input")
        view.input.delegate = context.coordinator; view.stringValue = text
        view.rejected = { [weak coordinator = context.coordinator] issue in coordinator?.parent.reject(issue) }
        view.changed = { [weak coordinator = context.coordinator] source in coordinator?.parent.text = source }
        view.pasted = { [weak coordinator = context.coordinator] in coordinator?.parent.pasted() }
        commands.clear = { [weak view] in view?.erase() }
        commands.focus = { [weak view] in if let view { view.window?.makeFirstResponder(view.input) } }
        commands.paste = { [weak view] in if let view { view.window?.makeFirstResponder(view.input); view.pasteCredentials(nil) } }
        commands.resignFocus = { [weak view] in view?.window?.makeFirstResponder(nil) }
        return view
    }
    func updateNSView(_ view: PasswordStrengthMacField, context: Context) {
        context.coordinator.parent = self
        if !view.stringValue.utf16.elementsEqual(text.utf16), (view.currentEditor() as? NSTextView)?.hasMarkedText() != true { view.stringValue = text }
        view.input.placeholderString = view.currentEditor() == nil ? (field == .concealed ? "Enter password" : "Enter password") : nil
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasswordStrengthField
        init(_ parent: PasswordStrengthField) { self.parent = parent }
        func controlTextDidBeginEditing(_ obj: Notification) { (obj.object as? NSTextField)?.placeholderString = nil }
        func controlTextDidEndEditing(_ obj: Notification) {
            ((obj.object as? NSTextField)?.superview as? PasswordStrengthMacField)?.restorePasteMenu()
            (obj.object as? NSTextField)?.placeholderString = parent.field == .concealed ? "Enter password" : "Enter password"
        }
        func controlTextDidChange(_ obj: Notification) {
            guard let input = obj.object as? NSTextField, let view = input.superview as? PasswordStrengthMacField else { return }
            if let editor = view.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            if view.allows(view.stringValue) { parent.text = view.stringValue }
            else { view.stringValue = parent.text }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if command == #selector(NSResponder.insertNewline(_:)) && !textView.hasMarkedText() { parent.submit(); return true }
            return false
        }
    }
}
#else
import UIKit

final class PasswordStrengthUIKitField: UITextField {
    var role = PasswordStrengthFieldRole.revealed
    var rejected: ((PasswordStrengthIssue) -> Void)?
    var pasted: (() -> Void)?
    let localUndo: UndoManager = { let manager = UndoManager(); manager.levelsOfUndo = 50; return manager }()
    private var committed = ""
    private var restoring = false
    private var beforeSelection: NSRange?
    func captureSelection() {
        if let range = selectedTextRange { beforeSelection = .init(location: offset(from: beginningOfDocument, to: range.start), length: offset(from: range.start, to: range.end)) }
    }
    func synchronize(_ value: String, eraseHistory: Bool = false) {
        text = value; committed = value; beforeSelection = nil
        if eraseHistory { localUndo.removeAllActions() }
    }
    func recordAcceptedEdit() {
        let value = text ?? ""
        guard !restoring, !committed.utf16.elementsEqual(value.utf16) else { return }
        let previous = committed, selection = beforeSelection ?? .init(location: committed.utf16.count, length: 0)
        committed = value; beforeSelection = nil
        localUndo.registerUndo(withTarget: self) { field in field.restore(previous, selection: selection) }
        localUndo.setActionName("Edit Credentials")
    }
    private func restore(_ value: String, selection: NSRange) {
        captureSelection()
        let previous = text ?? "", previousSelection = beforeSelection ?? .init(location: previous.utf16.count, length: 0)
        localUndo.registerUndo(withTarget: self) { field in field.restore(previous, selection: previousSelection) }
        restoring = true; text = value; committed = value; beforeSelection = nil
        if let start = position(from: beginningOfDocument, offset: min(selection.location, value.utf16.count)),
           let end = position(from: start, offset: min(selection.length, value.utf16.count - min(selection.location, value.utf16.count))) {
            selectedTextRange = textRange(from: start, to: end)
        }
        sendActions(for: .editingChanged); restoring = false
    }
    override var undoManager: UndoManager? { localUndo }
    func allows(_ value: String) -> Bool {
        if let issue = PasswordStrengthFieldValidation.issue(value) { rejected?(issue); return false }
        return true
    }
    override func paste(_ sender: Any?) {
        guard let value = UIPasteboard.general.string, let range = selectedTextRange else { return }
        let nsRange = NSRange(location:offset(from:beginningOfDocument,to:range.start),length:offset(from:range.start,to:range.end))
        guard allows(((text ?? "") as NSString).replacingCharacters(in:nsRange,with:value)) else { return }
        captureSelection()
        replace(range, withText: value)
        sendActions(for: .editingChanged); pasted?()
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if role == .concealed && (action == #selector(copy(_:)) || action == #selector(cut(_:))) { return false }
        return super.canPerformAction(action, withSender: sender)
    }
}

extension PasswordStrengthField: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PasswordStrengthUIKitField {
        let view = PasswordStrengthUIKitField()
        view.role = field; view.isSecureTextEntry = field == .concealed
        view.borderStyle = .roundedRect; view.font = .preferredFont(forTextStyle: .body); view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no; view.spellCheckingType = .no; view.autocapitalizationType = .none
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.textContentType = .none; view.keyboardType = .default; view.returnKeyType = .go
        view.accessibilityLabel = name; view.accessibilityIdentifier = "password-strength-input"
        view.synchronize(text); view.delegate = context.coordinator; view.textDropDelegate = context.coordinator
        view.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        view.rejected = { [weak coordinator = context.coordinator] issue in coordinator?.parent.reject(issue) }
        view.pasted = { [weak coordinator = context.coordinator] in coordinator?.parent.pasted() }
        commands.clear = { [weak view] in
            view?.resignFirstResponder(); view?.synchronize("", eraseHistory: true); view?.sendActions(for: .editingChanged)
        }
        commands.focus = { [weak view] in view?.becomeFirstResponder() }
        commands.paste = { [weak view] in view?.becomeFirstResponder(); view?.paste(nil) }
        commands.resignFocus = { [weak view] in view?.resignFirstResponder() }
        return view
    }
    static func dismantleUIView(_ view: PasswordStrengthUIKitField, coordinator: Coordinator) {
        view.localUndo.removeAllActions(); view.delegate = nil; view.rejected = nil
    }
    func updateUIView(_ view: PasswordStrengthUIKitField, context: Context) {
        context.coordinator.parent = self
        if !(view.text ?? "").utf16.elementsEqual(text.utf16), view.markedTextRange == nil { view.synchronize(text) }
        view.placeholder = view.isFirstResponder ? nil : (field == .concealed ? "Enter password" : "Enter password")
    }
    final class Coordinator: NSObject, UITextFieldDelegate, UITextDropDelegate {
        func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
            UITextDropProposal(operation: .cancel)
        }
        var parent: PasswordStrengthField
        init(_ parent: PasswordStrengthField) { self.parent = parent }
        @objc func changed(_ view: PasswordStrengthUIKitField) {
            guard view.markedTextRange == nil else { return }
            let source = view.text ?? ""
            if view.allows(source) { view.recordAcceptedEdit(); parent.text = source } else { view.synchronize(parent.text) }
        }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let view = textField as? PasswordStrengthUIKitField else { return false }
            if view.markedTextRange != nil { return true }
            guard view.allows(string) else { return false }
            view.captureSelection(); return true
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard textField.markedTextRange == nil else { return false }
            parent.submit(); return false
        }
        func textFieldDidBeginEditing(_ textField: UITextField) { textField.placeholder = nil }
        func textFieldDidEndEditing(_ textField: UITextField) { textField.placeholder = parent.field == .concealed ? "Enter password" : "Enter password" }
    }
}
#endif
