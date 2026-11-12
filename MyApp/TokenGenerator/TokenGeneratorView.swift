import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TokenGeneratorView: View {
    @Bindable var workspace: TokenWorkspaceSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @State private var scrollRequest = 0
    @State private var scrollTarget: Int?
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var rowHeight = 48.0
    private var animate: Bool { !reduceMotion && !ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.vertical) { form(wide).padding(.bottom, 2) }
                    .frame(height: wide ? 120 : typeSize.isAccessibilitySize ? 320 : 245)
                HStack {
                    Text(workspace.status).font(.caption).lineLimit(2).accessibilityIdentifier("token-status")
                    Spacer()
                    if workspace.busy || workspace.copying { Button("Cancel") { workspace.cancel() }.keyboardShortcut(.cancelAction) }
                }.frame(minHeight: 30)
                HStack {
                    Text("Results").font(.headline)
                    Spacer()
                    Button(workspace.hidden ? "Reveal" : "Hide", systemImage: workspace.hidden ? "eye" : "eye.slash") { workspace.toggleVisibility() }
                        .disabled(workspace.batch == nil).accessibilityIdentifier("token-visibility")
                    Menu {
                        Button("One per line") { workspace.copyAll(json: false, publish: publish) }
                        Button("JSON array") { workspace.copyAll(json: true, publish: publish) }
                    } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Copy All").disabled(!workspace.canCopy).accessibilityIdentifier("token-copy-all")
                }
                result.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
                if let batch = workspace.batch {
                    Text("\(batch.size) bytes per token · \(batch.size * 8) bits of generator entropy per token · \(batch.bytes.count) result(s)")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("token-metadata")
                }
                if let selected = workspace.selection, let p = workspace.presentation, p.values.count > 1, p.values.indices.contains(selected) {
                    Button { workspace.details.toggle() } label: { Label("Selected result \(selected + 1)", systemImage: workspace.details ? "chevron.down" : "chevron.right") }
                        .accessibilityIdentifier("token-details-toggle")
                    if workspace.details {
                        ScrollView { value(p.values[selected]).padding(8) }.frame(height: 100)
                        Button("Copy Selected") { workspace.copy(selected, publish: publish) }.disabled(!workspace.canCopy).accessibilityIdentifier("token-copy-selected")
                    }
                }
            }.padding(14).animation(animate ? .easeInOut(duration: 0.2) : nil, value: workspace.details)
        }.navigationTitle("Random Token / Secret Generator")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
        #endif
        .onChange(of: phase) { _, phase in if phase == .background { workspace.concealSecrets() } }
    }
    private func form(_ wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                let numbers = wide ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                numbers {
                    number("Bytes", text: $workspace.bytesText, range: 1...1024, id: "token-bytes")
                    number("Count", text: $workspace.countText, range: 1...1000, id: "token-count")
                }
                HStack {
                    Button("Generate", systemImage: "sparkles") { workspace.run(); copied = false }.keyboardShortcut(.return, modifiers: .command)
                        .disabled(!workspace.canGenerate).accessibilityIdentifier("token-generate")
                    Button("Clear", systemImage: "trash") { workspace.clear(); copied = false }.accessibilityIdentifier("token-clear")
                }
            }
            HStack {
                Picker("Encoding", selection: $workspace.options.encoding) { ForEach(TokenEncoding.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .pickerStyle(.menu).accessibilityIdentifier("token-encoding")
                if workspace.options.encoding == .hex { Toggle("Uppercase", isOn: $workspace.options.uppercase).font(.caption) }
                Menu {
                    ForEach([16,32,64], id: \.self) { size in Button("\(size) bytes") { workspace.bytesText = String(size) } }
                    Button("Reset Settings") { workspace.resetSettings() }
                } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Token presets")
            }
            Text("\(workspace.options.encoding.length(TokenWorkspaceSession.number(workspace.bytesText).flatMap { (1...1024).contains($0) ? $0 : nil } ?? 32)) characters per token · encoding does not add entropy.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func number(_ label: String, text: Binding<String>, range: ClosedRange<Int>, id: String) -> some View {
        HStack(spacing: 4) {
            Text(label).fixedSize()
            TextField("\(range.lowerBound)–\(range.upperBound)", text: text).textFieldStyle(.roundedBorder).frame(width: 64)
                .accessibilityLabel(label).accessibilityIdentifier(id)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Stepper(label, onIncrement: { step(text, range, 1) }, onDecrement: { step(text, range, -1) }).labelsHidden().fixedSize()
        }
    }
    private func step(_ text: Binding<String>, _ range: ClosedRange<Int>, _ delta: Int) { text.wrappedValue = String(min(range.upperBound, max(range.lowerBound, (TokenWorkspaceSession.number(text.wrappedValue) ?? range.lowerBound) + delta))) }
    @ViewBuilder private var result: some View {
        if let p = workspace.presentation, p.values.count == 1 {
            ScrollView { VStack(alignment: .leading, spacing: 12) { value(p.values[0]); Button("Copy", systemImage: copied ? "checkmark" : "doc.on.doc") { workspace.copy(0, publish: publish) }.disabled(!workspace.canCopy).accessibilityIdentifier("token-copy-single") }.padding(12).frame(maxWidth: .infinity, alignment: .leading) }
        } else {
            ZStack {
                JSONTreeTable(rows: workspace.rows, rowNumbers: workspace.rowNumbers, version: workspace.renderVersion, rowsVersion: workspace.rowsVersion,
                    changes: nil, animate: animate, selection: workspace.selection, scrollRequest: scrollRequest, scrollTarget: scrollTarget,
                    row: { AnyView(row($0)) }, select: { workspace.selection = $0 }, key: key,
                    preferredRowHeight: max(48, rowHeight), tableIdentifier: "token-results", suppressSoftwareKeyboard: true,
                    heightForID: { _ in max(48, rowHeight) }, smoothScrolling: true,
                    fadeReplacements: workspace.batch != nil && !workspace.hidden, alwaysShowScrollers: true,
                    accessibilityScrollName: "generated tokens", clearsOffscreenRowContent: true)
                if workspace.batch == nil { ContentUnavailableView("Generate a token", systemImage: "key.fill", description: Text("Secure random bytes, encoded for your use. Results stay in memory.")) }
            }
        }
    }
    @ViewBuilder private func value(_ text: String) -> some View {
        if workspace.hidden { Text("••••••••").font(.body.monospaced()).accessibilityLabel("Token hidden") }
        else { Text(text).font(.body.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("token-value") }
    }
    @ViewBuilder private func row(_ index: Int) -> some View {
        if let p = workspace.presentation, p.values.indices.contains(index) {
            HStack(spacing: 8) {
                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24)
                Text(workspace.hidden ? "••••••••" : String(p.values[index].prefix(64)) + (p.values[index].count > 64 ? "…" : ""))
                    .font(.body.monospaced()).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(workspace.hidden ? "Token hidden" : p.values[index])
                Button { workspace.copy(index, publish: publish) } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).disabled(!workspace.canCopy).accessibilityLabel("Copy token \(index + 1)")
            }.padding(.horizontal, 8).frame(minHeight: max(48, rowHeight))
                .background(workspace.selection == index ? Color.green.opacity(0.14) : .clear)
                .contentShape(Rectangle()).onTapGesture { workspace.selection = index }
                .accessibilityIdentifier("token-row-\(index)")
                .contextMenu { Button("Copy") { workspace.copy(index, publish: publish) }.disabled(!workspace.canCopy) }
        }
    }
    private func key(_ key: JSONTreeTable.TreeKey) {
        switch key {
        case .copy: if let selected = workspace.selection { workspace.copy(selected, publish: publish) }
        case .up, .down:
            guard !workspace.rows.isEmpty else { return }
            let selected = workspace.selection ?? (key == .down ? -1 : workspace.rows.count)
            let next = max(0, min(workspace.rows.count - 1, selected + (key == .down ? 1 : -1)))
            workspace.selection = next; scrollTarget = next; scrollRequest &+= 1
        default: break
        }
    }
    private func publish(_ text: String) { SecretClipboard.copy(text); copied = true }
}
