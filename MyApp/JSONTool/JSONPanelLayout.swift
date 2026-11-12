import SwiftUI

/// Keeps both native editors at stable identities when changing axis or proportions.
struct JSONPanelLayout: Layout {
    var horizontal: Bool
    var fraction: Double
    var collapseProgress: Double
    init(horizontal: Bool, fraction: Double, collapsed: Bool) {
        self.horizontal = horizontal; self.fraction = fraction; collapseProgress = collapsed ? 1 : 0
    }
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fraction, collapseProgress) }
        set { fraction = newValue.first; collapseProgress = newValue.second }
    }
    static let divider: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 600, height: 400))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let length = horizontal ? bounds.width : bounds.height
        let available = max(0, length - Self.divider)
        let expanded = available * min(0.75, max(0.25, fraction))
        let first = expanded + (max(0, available - 36) - expanded) * collapseProgress
        func place(_ index: Int, offset: CGFloat, length: CGFloat) {
            let origin = CGPoint(x: bounds.minX + (horizontal ? offset : 0),
                                 y: bounds.minY + (horizontal ? 0 : offset))
            let size = CGSize(width: horizontal ? length : bounds.width,
                              height: horizontal ? bounds.height : length)
            subviews[index].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size))
        }
        place(0, offset: 0, length: first)
        place(1, offset: first, length: Self.divider)
        place(2, offset: first + Self.divider, length: available - first)
    }
}
