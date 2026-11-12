import SwiftUI

/// Native List recycles rows; each row formats at most 16 bytes. No eager document-wide views.
struct HexBytesInspector: View {
    let artifact: HexBytesArtifact
    let hexCase: HexBytesCase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12
    @State private var viewport = Viewport()
    private final class Viewport { var firstByte = 0; var request = UUID() }
    private struct Frames: PreferenceKey {
        static let defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
    }
    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 4) {
            Text("Byte offset · hexadecimal · \(artifact.bytes.count) bytes")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            if artifact.bytes.isEmpty {
                ContentUnavailableView("0 bytes", systemImage: "number.square", description: Text("The result is an empty byte sequence."))
            } else {
                HexBytesNativeList(artifact: artifact, hexCase: hexCase, fontSize: fontSize)
            }
        }
        #else
        GeometryReader { geometry in
            let columns = geometry.size.width >= CGFloat(fontSize) * 37 ? 16 : geometry.size.width >= CGFloat(fontSize) * 23 ? 8 : 4
            let ascii = geometry.size.width >= CGFloat(fontSize) * (12 + CGFloat(columns) * 2.6)
            let count = (artifact.bytes.count + columns - 1) / columns
            VStack(alignment: .leading, spacing: 4) {
                Text("Byte offset · hexadecimal · \(artifact.bytes.count) bytes")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal, 8)
                if count == 0 {
                    ContentUnavailableView("0 bytes", systemImage: "number.square", description: Text("The result is an empty byte sequence."))
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(Array(stride(from: 0, to: artifact.bytes.count, by: columns)), id: \.self) { start in
                                byteRow(start: start, columns: columns, ascii: ascii)
                                    .background(GeometryReader { rowGeometry in
                                        Color.clear.preference(key: Frames.self, value: [start: rowGeometry.frame(in: .global)])
                                    })
                            }
                        }
                        .listStyle(.plain).scrollIndicators(.visible).accessibilityIdentifier("hex-bytes-inspector")
                        .onPreferenceChange(Frames.self) { frames in
                            let bounds = geometry.frame(in: .global)
                            if let first = frames.filter({ $0.value.maxY > bounds.minY + 22 && $0.value.minY < bounds.maxY }).min(by: { $0.key < $1.key }) {
                                viewport.firstByte = first.key
                            }
                        }
                        .onChange(of: columns) { _, new in
                            let anchor = viewport.firstByte / new * new
                            // Do not reenter NSTableView's layout delegate through scrollTo.
                            // Keep only the latest resize request; source changes destroy this viewport.
                            let request = UUID(); viewport.request = request
                            DispatchQueue.main.async {
                                guard viewport.request == request else { return }
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .id(artifact.id)
        #endif
    }
    private func byteRow(start: Int, columns: Int, ascii: Bool) -> some View {
        let row = HexBytesRow(bytes: artifact.bytes, start: start, count: columns, hexCase: hexCase)
        return ScrollView(.horizontal) {
            HStack(spacing: 12) {
                Text(row.offset).foregroundStyle(.secondary)
                Text(row.hex).foregroundStyle(.primary)
                if ascii { Text(row.ascii).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .font(.system(size: fontSize, design: .monospaced)).fixedSize(horizontal: true, vertical: false)
        }
        .scrollIndicators(.visible).frame(minHeight: 28)
        .listRowInsets(.init(top: 2, leading: 8, bottom: 2, trailing: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Byte offset \(start), hexadecimal \(row.offset). \(row.hex). ASCII \(row.ascii)")
        .accessibilityIdentifier("hex-bytes-row-\(start)")
    }
}
