import SwiftUI

struct JSONDiffRow: View {
    let result: JSONDiffResult
    let change: JSONDiffChange
    let selected: Bool
    let wide: Bool
    let select: () -> Void
    let reveal: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(change.kind.rawValue, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(color)
                Text(pathLabel).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                if result.path(for: change).ambiguous {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("Ambiguous path — duplicate key")
                }
                Spacer(minLength: 0)
            }
            if wide {
                HStack(alignment: .top, spacing: 12) {
                    value(.before).frame(maxWidth: .infinity, alignment: .leading)
                    value(.after).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                value(.before)
                value(.after)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(selected ? Color.green.opacity(scheme == .dark ? 0.22 : 0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: reveal)
        .onTapGesture(perform: select)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(change.kind.rawValue). \(pathLabel). Before: \(accessibleValue(.before)). After: \(accessibleValue(.after))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(.default, select)
        .accessibilityActions { Button("Show Before and After", action: reveal) }
        .accessibilityIdentifier("diff-change-\(change.id)")
    }
    private var pathLabel: String {
        let pointer = result.path(for: change).pointer
        return pointer.isEmpty ? "Root" : JSONTreePreview.make(pointer).text
    }
    @ViewBuilder private func value(_ side: JSONDiffSide) -> some View {
        let document = side == .before ? result.before : result.after
        let id = side == .before ? change.before : change.after
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(side.rawValue).font(.caption2).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            if let id {
                let node = document.nodes[id]
                Text(node.kind.rawValue).font(.caption2).foregroundStyle(.secondary)
                if let preview = side == .before ? change.beforeText : change.afterText {
                    Text(highlight(preview, kind: node.kind)).font(.system(.callout, design: .monospaced)).lineLimit(1)
                } else { Text(node.summary).font(.system(.callout, design: .monospaced)).lineLimit(1) }
            } else { Text("Missing").font(.callout).foregroundStyle(.secondary) }
        }
    }
    private func accessibleValue(_ side: JSONDiffSide) -> String {
        let document = side == .before ? result.before : result.after
        guard let id = side == .before ? change.before : change.after else { return "Missing" }
        let preview = side == .before ? change.beforeText : change.afterText
        return document.nodes[id].kind.rawValue + " " + (preview?.preview.text ?? document.nodes[id].summary)
    }
    private func highlight(_ text: JSONDiffText, kind: JSONStructureNode.Kind) -> AttributedString {
        var result = AttributedString(text.preview.text.isEmpty ? "\"\"" : text.preview.text)
        result.foregroundColor = contrast == .increased ? .primary : syntaxColor(kind)
        if let difference = text.difference {
            for display in text.preview.displayRanges(for: difference) {
                if let source = Range(display, in: text.preview.text), let range = Range(source, in: result) {
                    result[range].backgroundColor = Color.yellow.opacity(scheme == .dark ? 0.22 : 0.26)
                    result[range].underlineStyle = .single
                }
            }
        }
        return result
    }
    private func syntaxColor(_ kind: JSONStructureNode.Kind) -> Color {
        switch kind {
        case .string: return scheme == .dark ? Color(red: 0.6, green: 0.84, blue: 0.65) : Color(red: 0.17, green: 0.43, blue: 0.25)
        case .number: return scheme == .dark ? .orange : .brown
        case .boolean, .null: return .purple
        default: return .primary
        }
    }
    private var symbol: String {
        switch change.kind { case .added: return "plus.circle"; case .removed: return "minus.circle"; default: return "arrow.left.arrow.right.circle" }
    }
    private var color: Color {
        if contrast == .increased { return .primary }
        switch change.kind { case .added: return .green; case .removed: return .red; default: return .orange }
    }
    static func safeFullText(_ source: String) -> String {
        source.unicodeScalars.map { scalar in
            switch scalar.value {
            case 9, 10, 13: return String(scalar)
            case 0...31, 127...159, 0x061C, 0x200E...0x200F, 0x2028...0x202E, 0x2066...0x2069:
                return String(format: "\\u{%04X}", scalar.value)
            default: return String(scalar)
            }
        }.joined()
    }
}
