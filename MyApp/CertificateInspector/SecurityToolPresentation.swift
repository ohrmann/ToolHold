import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SecurityToolClipboard {
    @MainActor static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
    @MainActor static func paste() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType:.string)
        #else
        UIPasteboard.general.string
        #endif
    }
}

/// Only the two-panel sizing shared by these three tools. Subview identities never change at a breakpoint.
struct SecurityToolPanelLayout: Layout {
    var wide: Bool
    var fraction: Double
    private var collapse: Double
    init(wide: Bool, fraction: Double, collapsed: Bool) { self.wide = wide; self.fraction = fraction; collapse = collapsed ? 1 : 0 }
    var animatableData: AnimatablePair<Double,Double> {
        get { .init(fraction,collapse) }
        set { fraction = newValue.first; collapse = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { .init(width:proposal.width ?? 800,height:proposal.height ?? 600) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let openness = max(0,min(1,1-collapse))
        let gap: CGFloat = 10*openness
        if wide {
            let left = max(220,min(bounds.width-260,bounds.width*fraction))*openness
            subviews[0].place(at:bounds.origin,proposal:.init(width:left,height:bounds.height))
            subviews[1].place(at:.init(x:bounds.minX+left,y:bounds.minY),proposal:.init(width:gap,height:bounds.height))
            subviews[2].place(at:.init(x:bounds.minX+left+gap,y:bounds.minY),proposal:.init(width:max(0,bounds.width-left-gap),height:bounds.height))
        } else {
            let top = max(120,min(bounds.height-160,bounds.height*fraction))*openness
            subviews[0].place(at:bounds.origin,proposal:.init(width:bounds.width,height:top))
            subviews[1].place(at:.init(x:bounds.minX,y:bounds.minY+top),proposal:.init(width:bounds.width,height:gap))
            subviews[2].place(at:.init(x:bounds.minX,y:bounds.minY+top+gap),proposal:.init(width:bounds.width,height:max(0,bounds.height-top-gap)))
        }
    }
}
struct SecurityPanelDivider: View {
    let wide: Bool
    let length: CGFloat
    @Binding var fraction: Double
    @State private var start: Double?
    var body: some View {
        Rectangle().fill(.secondary.opacity(0.16)).frame(width:wide ? 1 : nil,height:wide ? nil : 1)
            .frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:3).onChanged { event in
                if start == nil { start = fraction }
                let delta = wide ? event.translation.width : event.translation.height
                fraction = min(0.7,max(0.25,(start ?? fraction)+delta/max(1,length)))
            }.onEnded { _ in start = nil })
            .accessibilityLabel("Panel proportions").accessibilityAdjustableAction { direction in fraction = min(0.7,max(0.25,fraction+(direction == .increment ? 0.05 : -0.05))) }
    }
}
extension View {
    func securityToolPanel() -> some View { self.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.secondary.opacity(0.24))) }
}
