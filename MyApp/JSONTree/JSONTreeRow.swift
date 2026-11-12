import SwiftUI

struct JSONTreeRow: View {
    let node: JSONStructureNode
    let number: Int
    let expanded: Bool
    let selected: Bool
    let compact: Bool
    let matches: [JSONTreeMatch]
    let nodeMatches: JSONTreeNodeMatches
    let active: Int?
    let toggle: () -> Void
    let select: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var target: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("\(number)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(minWidth: compact ? 16 : 25, alignment: .trailing)
                folding("gutter")
            }
            .accessibilityHidden(true)
            .help("Tree row \(number), not a source line")
            Rectangle().fill(.quaternary).frame(width: 1).padding(.trailing, 3)
            Color.clear.frame(width: CGFloat(min(node.depth, compact ? 4 : 12)) * (compact ? 7 : 14))
            folding("node")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(highlight(node.key?.isEmpty == true ? "\"\"" : node.name, field: .key, color: .blue)).lineLimit(1)
                    if node.occurrences > 1 {
                        Text("\(node.occurrence)/\(node.occurrences)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 5) {
                    if node.kind == .string { Text("“").foregroundStyle(color) }
                    Text(highlight(node.summary, field: .value, color: color)).lineLimit(1)
                    if node.kind == .string { Text("”").foregroundStyle(color) }
                    if node.scalar != nil { Text(node.kind.rawValue).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .font(.system(.callout, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: target, alignment: .leading)
            .contentShape(Rectangle()).onTapGesture(perform: select)
        }
        .background(selected ? Color.green.opacity(scheme == .dark ? 0.22 : 0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tree row \(number). \(JSONTreePreview.make(node.name).text). \(node.kind.rawValue). \(JSONTreePreview.make(node.summary).text). Level \(node.depth + 1)")
        .accessibilityValue(node.canExpand ? (expanded ? "Expanded" : "Collapsed") : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(.default, select)
        .accessibilityActions {
            if node.canExpand { Button(expanded ? "Collapse" : "Expand", action: toggle) }
        }
        .accessibilityIdentifier("tree-row-\(node.id)")
    }
    @ViewBuilder private func folding(_ zone: String) -> some View {
        if node.canExpand {
            Button(action: toggle) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: target, height: target).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel((expanded ? "Collapse " : "Expand ") + JSONTreePreview.make(node.name).text)
            .accessibilityIdentifier("tree-fold-\(zone)-\(node.id)")
        } else { Color.clear.frame(width: target, height: target).accessibilityHidden(true) }
    }
    private var color: Color {
        if contrast == .increased { return .primary }
        switch node.kind {
        case .string: return scheme == .dark ? Color(red: 0.6, green: 0.84, blue: 0.65) : Color(red: 0.17, green: 0.43, blue: 0.25)
        case .number: return scheme == .dark ? .orange : .brown
        case .boolean, .null: return .purple
        case .object, .array: return .primary
        }
    }
    private func highlight(_ text: String, field: JSONTreeMatch.Field, color: Color) -> AttributedString {
        let hits = field == .key ? nodeMatches.key : nodeMatches.value
        let primary: Int?
        if let active, matches.indices.contains(active), matches[active].nodeID == node.id, matches[active].field == field { primary = active }
        else { primary = hits.first }
        let preview = JSONTreePreview.make(text, around: primary.map { matches[$0].range }, budget: compact ? 65 : 140)
        var attributed = AttributedString(preview.text)
        attributed.foregroundColor = contrast == .increased ? .primary : color
        // Binary-search the small preview window, not all hits in a very long value.
        let lower = preview.spans.first?.source.location ?? 0
        let upper = preview.spans.last.map { NSMaxRange($0.source) } ?? 0
        var low = 0, high = hits.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(matches[hits[mid]].range) <= lower { low = mid + 1 } else { high = mid }
        }
        for index in hits.dropFirst(low) {
            let hit = matches[index]
            if hit.range.location >= upper { break }
            for display in preview.displayRanges(for: hit.range) {
                guard let stringRange = Range(display, in: preview.text), let range = Range(stringRange, in: attributed) else { continue }
                attributed[range].backgroundColor = index == active ? .orange.opacity(0.35) : .yellow.opacity(0.2)
                attributed[range].underlineStyle = .single
                if index == active { attributed[range].font = .system(.callout, design: .monospaced).bold() }
            }
        }
        return attributed
    }
}
