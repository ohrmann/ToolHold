import SwiftUI

/// Retains Input identity while its panel collapses; editor roles never change.
struct URLQueryPanelLayout: Layout {
    var horizontal: Bool
    var fraction: Double
    var progress: Double
    var animatableData: AnimatablePair<Double,Double> {
        get { .init(fraction,progress) }
        set { fraction = newValue.first; progress = newValue.second }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by:.init(width:700,height:600))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let available = max(0,(horizontal ? bounds.width : bounds.height)-12)
        let input = available * min(0.7,max(0.25,fraction)) * (1-progress)
        func place(_ index: Int, _ offset: CGFloat, _ length: CGFloat) {
            subviews[index].place(at:.init(x:bounds.minX+(horizontal ? offset : 0),y:bounds.minY+(horizontal ? 0 : offset)),anchor:.topLeading,
                proposal:.init(width:horizontal ? length : bounds.width,height:horizontal ? bounds.height : length))
        }
        place(0,0,input); place(1,input,12); place(2,input+12,available-input)
    }
}
