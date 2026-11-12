import SwiftUI

/// User commands have independent identity; normal body updates preserve zoom and scroll.
struct QRImageViewCommand: Equatable {
    enum Action: Equatable { case fit, zoomIn, zoomOut, reveal(CGRect) }
    var id = UUID()
    var action: Action = .fit
}
#if os(macOS)
import AppKit

struct QRCodeImageViewport: NSViewRepresentable {
    let image: CGImage?
    let sourceID: UUID?
    let items: [QRDecodedItem]
    let selectedID: Int?
    let command: QRImageViewCommand
    let reducedMotion: Bool
    let select: (Int,Bool) -> Void
    let paste: () -> Void
    var interaction: () -> Void = {}
    func makeNSView(context: Context) -> QRDecoderScrollView {
        let scroll = QRDecoderScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false; scroll.borderType = .noBorder
        scroll.drawsBackground = true; scroll.backgroundColor = .controlBackgroundColor
        scroll.allowsMagnification = true; scroll.minMagnification = 0.01; scroll.maxMagnification = 8
        scroll.contentView = QRDecoderClipView()
        let canvas = QRDecoderCanvas(frame:.zero)
        scroll.documentView = canvas; scroll.setAccessibilityIdentifier("qr-decoder-viewport")
        return scroll
    }
    func updateNSView(_ scroll: QRDecoderScrollView, context: Context) {
        guard let canvas = scroll.documentView as? QRDecoderCanvas else { return }
        canvas.select = select; canvas.interaction = interaction; scroll.interaction = interaction; scroll.pasteImage = paste
        canvas.items = items; canvas.selectedID = selectedID
        let changed = scroll.sourceID != sourceID
        if changed {
            scroll.sourceID = sourceID; canvas.image = image
            canvas.frame = CGRect(x:0,y:0,width:image?.width ?? 1,height:image?.height ?? 1)
            scroll.needsFit = true
        } else { canvas.image = image }
        canvas.needsDisplay = true
        if scroll.commandID != command.id {
            scroll.commandID = command.id
            scroll.perform(command.action,reduced:reducedMotion)
        }
        scroll.layoutSubtreeIfNeeded()
    }
}
final class QRDecoderClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return result }
        if result.width > documentView.frame.width { result.origin.x = documentView.frame.midX-result.width/2 }
        if result.height > documentView.frame.height { result.origin.y = documentView.frame.midY-result.height/2 }
        return result
    }
}
final class QRDecoderScrollView: NSScrollView {
    var sourceID: UUID?
    var commandID: UUID?
    var needsFit = true
    var pasteImage: (() -> Void)?
    var interaction: () -> Void = {}
    override var acceptsFirstResponder: Bool { true }
    @objc func paste(_ sender: Any?) { pasteImage?() }
    override func layout() {
        super.layout()
        if needsFit, documentView?.frame.width ?? 0 > 1, contentSize.width > 1, contentSize.height > 1 {
            needsFit = false; fit()
        }
    }
    var fitScale: CGFloat {
        guard let view = documentView else { return 1 }
        return max(0.01,min(contentSize.width/max(1,view.frame.width),contentSize.height/max(1,view.frame.height)))
    }
    func fit() {
        minMagnification = min(1,fitScale); maxMagnification = max(1,fitScale*8)
        magnification = fitScale
        contentView.scroll(to:.zero); reflectScrolledClipView(contentView)
    }
    func perform(_ action: QRImageViewCommand.Action, reduced: Bool) {
        guard let view = documentView, view.frame.width > 1 else { return }
        let target: CGFloat, center: CGPoint
        let visible = view.visibleRect
        switch action {
        case .fit: target = fitScale; center = CGPoint(x:view.bounds.midX,y:view.bounds.midY)
        case .zoomIn: target = min(maxMagnification,magnification*1.5); center = CGPoint(x:visible.midX,y:visible.midY)
        case .zoomOut: target = max(minMagnification,magnification/1.5); center = CGPoint(x:visible.midX,y:visible.midY)
        case .reveal(let rect):
            target = min(maxMagnification,max(fitScale,min(contentSize.width/max(1,rect.width+40),contentSize.height/max(1,rect.height+40))))
            center = CGPoint(x:rect.midX,y:rect.midY)
        }
        // AppKit's magnification animation interpolates the viewport, including offscreen targets.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduced ? 0 : 0.2
            if reduced { self.setMagnification(target,centeredAt:center) }
            else { self.animator().setMagnification(target,centeredAt:center) }
        }
    }
    override func scrollWheel(with event: NSEvent) { interaction(); layer?.removeAllAnimations(); contentView.layer?.removeAllAnimations(); super.scrollWheel(with:event) }
}
final class QRDecoderCanvas: NSView {
    var image: CGImage?
    var items: [QRDecodedItem] = []
    var selectedID: Int?
    var select: (Int,Bool) -> Void = { _,_ in }
    var interaction: () -> Void = {}
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        NSImage(cgImage:image,size:bounds.size).draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.none])
        let scale = max(0.01,enclosingScrollView?.magnification ?? 1)
        for item in items {
            let active = selectedID == item.id
            let path = NSBezierPath(); guard let first = item.corners.first else { continue }; path.move(to:first)
            for p in item.corners.dropFirst() { path.line(to:p) }; path.close()
            NSColor.black.withAlphaComponent(0.8).setStroke(); path.lineWidth = (active ? 5 : 4)/scale; path.stroke()
            (active ? NSColor.systemGreen : NSColor.white).setStroke(); path.lineWidth = (active ? 3 : 2)/scale; path.stroke()
            let rect = CGRect(x:item.bounds.minX,y:item.bounds.minY,width:26/scale,height:23/scale)
            NSColor.black.withAlphaComponent(0.85).setFill(); NSBezierPath(roundedRect:rect,xRadius:3/scale,yRadius:3/scale).fill()
            ("\(item.id+1)" as NSString).draw(in:rect.insetBy(dx:3/scale,dy:2/scale),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:14/scale,weight:.semibold),.foregroundColor:NSColor.white])
        }
    }
    override func mouseDown(with event: NSEvent) {
        interaction()
        window?.makeFirstResponder(enclosingScrollView)
        let point = convert(event.locationInWindow,from:nil)
        if let item = items.first(where:{ $0.bounds.insetBy(dx:-5,dy:-5).contains(point) }) { select(item.id,event.clickCount > 1) }
    }
    override func keyDown(with event: NSEvent) { nextResponder?.keyDown(with:event) }
}
#else
import UIKit

struct QRCodeImageViewport: UIViewRepresentable {
    let image: CGImage?
    let sourceID: UUID?
    let items: [QRDecodedItem]
    let selectedID: Int?
    let command: QRImageViewCommand
    let reducedMotion: Bool
    let select: (Int,Bool) -> Void
    let paste: () -> Void
    var interaction: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> QRDecoderScrollView {
        let scroll = QRDecoderScrollView()
        scroll.delegate = context.coordinator; scroll.showsVerticalScrollIndicator = true; scroll.showsHorizontalScrollIndicator = true
        scroll.minimumZoomScale = 0.01; scroll.maximumZoomScale = 8; scroll.backgroundColor = .secondarySystemBackground
        let canvas = QRDecoderCanvas(); scroll.addSubview(canvas); scroll.canvas = canvas
        let tap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:))); canvas.addGestureRecognizer(tap)
        let double = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.doubleTap(_:))); double.numberOfTapsRequired = 2; canvas.addGestureRecognizer(double); tap.require(toFail:double)
        context.coordinator.scroll = scroll; scroll.accessibilityIdentifier = "qr-decoder-viewport"
        return scroll
    }
    func updateUIView(_ scroll: QRDecoderScrollView, context: Context) {
        scroll.pasteImage = paste; scroll.interaction = interaction; context.coordinator.select = select
        guard let canvas = scroll.canvas else { return }
        let changed = scroll.sourceID != sourceID
        if changed {
            scroll.sourceID = sourceID; scroll.setZoomScale(1,animated:false)
            canvas.frame = CGRect(x:0,y:0,width:image?.width ?? 1,height:image?.height ?? 1)
            scroll.contentSize = canvas.bounds.size; scroll.needsFit = true
        }
        canvas.image = image; canvas.items = items; canvas.selectedID = selectedID; canvas.refresh()
        if scroll.commandID != command.id { scroll.commandID = command.id; scroll.perform(command.action,animated:!reducedMotion) }
        scroll.setNeedsLayout()
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scroll: QRDecoderScrollView?
        var select: (Int,Bool) -> Void = { _,_ in }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { scroll?.canvas }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { scroll?.interaction() }
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            // This delegate also runs during updateUIView's programmatic zoom. Only a real gesture can mutate SwiftUI state.
            if scrollView.pinchGestureRecognizer?.state == .began { scroll?.interaction() }
        }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { scroll?.centerContent(); scroll?.canvas?.refreshScale() }
        @objc func tap(_ gesture: UITapGestureRecognizer) { hit(gesture,double:false) }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) { hit(gesture,double:true) }
        func hit(_ gesture: UITapGestureRecognizer,double: Bool) {
            guard let canvas = scroll?.canvas else { return }; scroll?.becomeFirstResponder()
            if let item = canvas.items.first(where:{ $0.bounds.insetBy(dx:-8,dy:-8).contains(gesture.location(in:canvas)) }) { select(item.id,double) }
        }
    }
}
final class QRDecoderScrollView: UIScrollView {
    var canvas: QRDecoderCanvas?
    var sourceID: UUID?
    var commandID: UUID?
    var needsFit = true
    var pasteImage: (() -> Void)?
    var interaction: () -> Void = {}
    override var canBecomeFirstResponder: Bool { true }
    override func paste(_ sender: Any?) { pasteImage?() }
    override func layoutSubviews() {
        super.layoutSubviews()
        if needsFit, let canvas, canvas.bounds.width > 1, bounds.width > 1, bounds.height > 1 {
            needsFit = false
            let fit = fitScale; minimumZoomScale = fit; maximumZoomScale = fit*8; setZoomScale(fit,animated:false)
        }
        centerContent()
    }
    func centerContent() {
        guard let canvas else { return }
        canvas.center = CGPoint(x:max(contentSize.width,bounds.width)/2,y:max(contentSize.height,bounds.height)/2)
    }
    var fitScale: CGFloat { guard let canvas else { return 1 }; return max(0.01,min(bounds.width/max(1,canvas.bounds.width),bounds.height/max(1,canvas.bounds.height))) }
    func perform(_ action: QRImageViewCommand.Action, animated: Bool) {
        guard let canvas, canvas.bounds.width > 1 else { return }
        switch action {
        case .fit: setZoomScale(fitScale,animated:animated); setContentOffset(.zero,animated:animated)
        case .zoomIn: setZoomScale(min(maximumZoomScale,zoomScale*1.5),animated:animated)
        case .zoomOut: setZoomScale(max(minimumZoomScale,zoomScale/1.5),animated:animated)
        case .reveal(let rect): zoom(to:rect.insetBy(dx:-20,dy:-20),animated:animated)
        }
    }
}
final class QRDecoderCanvas: UIView {
    var image: CGImage?
    var items: [QRDecodedItem] = []
    var selectedID: Int?
    private var records: [(outline:CAShapeLayer,stroke:CAShapeLayer,label:CATextLayer)] = []
    private var geometry: [[CGPoint]] = []
    /// Keep the CGImage as layer contents: no 4096-point Retina draw backing bitmap.
    func refresh() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.contents = image; layer.contentsGravity = .resize; layer.contentsScale = 1
        if geometry != items.map(\.corners) {
            records.forEach { $0.outline.removeFromSuperlayer(); $0.stroke.removeFromSuperlayer(); $0.label.removeFromSuperlayer() }
            geometry = items.map(\.corners)
            records = items.map { item in
                let path = CGMutablePath()
                if let first = item.corners.first { path.move(to:first); item.corners.dropFirst().forEach { path.addLine(to:$0) }; path.closeSubpath() }
                let outline = CAShapeLayer(), stroke = CAShapeLayer(), label = CATextLayer()
                for shape in [outline,stroke] { shape.path = path; shape.fillColor = UIColor.clear.cgColor; layer.addSublayer(shape) }
                outline.strokeColor = UIColor.black.cgColor
                label.string = "\(item.id+1)"; label.alignmentMode = .center; label.foregroundColor = UIColor.white.cgColor
                label.backgroundColor = UIColor.black.withAlphaComponent(0.85).cgColor
                label.contentsScale = window?.screen.scale ?? 3; layer.addSublayer(label)
                return (outline,stroke,label)
            }
        }
        for (index,item) in items.enumerated() where index < records.count {
            records[index].stroke.strokeColor = (item.id == selectedID ? UIColor.systemGreen : UIColor.white).cgColor
        }
        refreshScale(); CATransaction.commit()
    }
    func refreshScale() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let scale = max(0.01,(superview as? UIScrollView)?.zoomScale ?? 1)
        for (index,item) in items.enumerated() where index < records.count {
            let layers = records[index]
            layers.outline.lineWidth = 5/scale; layers.stroke.lineWidth = 3/scale
            layers.label.fontSize = 14/scale; layers.label.cornerRadius = 3/scale
            layers.label.frame = CGRect(x:item.bounds.minX,y:item.bounds.minY,width:26/scale,height:23/scale)
        }
        CATransaction.commit()
    }
}
#endif
