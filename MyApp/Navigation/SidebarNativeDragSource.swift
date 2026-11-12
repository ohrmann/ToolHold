#if os(iOS)
  import SwiftUI
  import UIKit

  /// Only the source handle is bridged; SwiftUI owns the list and drop targets.
  struct SidebarNativeDragSource: UIViewRepresentable {
    let preview: SidebarDragPreview
    let begin: () -> SidebarDrag
    let ended: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.backgroundColor = .clear
      let interaction = UIDragInteraction(delegate: context.coordinator)
      interaction.isEnabled = true
      view.addInteraction(interaction)
      return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.source = self }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
      var source: SidebarNativeDragSource
      init(_ source: SidebarNativeDragSource) { self.source = source }

      func dragInteraction(
        _ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession
      )
        -> [UIDragItem]
      {
        // SwiftUI can recycle the source row during live reordering. UIKit keeps
        // this delegate alive through localContext until its session-end callbacks.
        session.localContext = self
        let payload = source.begin()
        let item = UIDragItem(itemProvider: payload.provider())
        return [item]
      }
      func dragInteraction(
        _ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
        session: any UIDragSession
      ) -> UITargetedDragPreview? {
        guard let handle = interaction.view, let window = handle.window else { return nil }
        let renderer = ImageRenderer(
          content: source.preview.environment(\.colorScheme, source.colorScheme))
        renderer.scale = window.screen.scale
        guard let image = renderer.uiImage else { return nil }
        let imageView = UIImageView(image: image)
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: imageView.bounds, cornerRadius: 9)
        var center = handle.convert(
          CGPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: window)
        center.x -= imageView.bounds.width / 2 - handle.bounds.width / 2
        let halfWidth = imageView.bounds.width / 2
        center.x = min(max(center.x, halfWidth + 12), window.bounds.width - halfWidth - 12)
        let target = UIDragPreviewTarget(container: window, center: center)
        return UITargetedDragPreview(view: imageView, parameters: parameters, target: target)
      }
      func dragInteraction(
        _ interaction: UIDragInteraction, prefersFullSizePreviewsFor session: any UIDragSession
      ) -> Bool { true }
      func dragInteraction(
        _ interaction: UIDragInteraction,
        sessionIsRestrictedToDraggingApplication session: any UIDragSession
      ) -> Bool { true }
      func dragInteraction(
        _ interaction: UIDragInteraction, sessionAllowsMoveOperation session: any UIDragSession
      ) -> Bool { true }
      func dragInteraction(
        _ interaction: UIDragInteraction, session: any UIDragSession,
        willEndWith operation: UIDropOperation
      ) {
        // Restore the layout before UIKit's cancellation animation, not after it.
        if operation != .move { source.ended(false) }
      }
      func dragInteraction(
        _ interaction: UIDragInteraction, session: any UIDragSession,
        didEndWith operation: UIDropOperation
      ) {
        source.ended(operation == .move)
      }
    }
  }
#endif

#if os(macOS)
  import AppKit
  import UniformTypeIdentifiers
  import SwiftUI

  struct SidebarNativeDragSource: NSViewRepresentable {
    let preview: SidebarDragPreview
    let begin: () -> SidebarDrag
    let ended: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
      view.preview = preview
      view.scheme = colorScheme
      view.begin = begin
      view.ended = ended
    }

    final class HandleView: NSView, NSDraggingSource {
      var preview: SidebarDragPreview?
      var scheme: ColorScheme = .light
      var begin: (() -> SidebarDrag)?
      var ended: ((Bool) -> Void)?
      private var start: NSPoint?
      private var active = false

      override func mouseDown(with event: NSEvent) { start = event.locationInWindow }
      override func mouseUp(with event: NSEvent) { start = nil }
      override func mouseDragged(with event: NSEvent) {
        guard !active, let start, let preview, let begin,
          hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4
        else { return }
        let renderer = ImageRenderer(content: preview.environment(\.colorScheme, scheme))
        renderer.scale = window?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        let payload = begin()
        let pasteboard = NSPasteboardItem()
        guard let data = try? JSONEncoder().encode(payload) else {
          ended?(false)
          return
        }
        pasteboard.setData(data, forType: .init(SidebarDrag.type.identifier))
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
          CGRect(
            x: point.x - image.size.width + 24, y: point.y - image.size.height / 2,
            width: image.size.width, height: image.size.height), contents: image)
        active = true
        beginDraggingSession(with: [item], event: event, source: self)
      }
      func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
      ) -> NSDragOperation {
        context == .withinApplication ? .move : []
      }
      func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
      ) {
        active = false
        start = nil
        ended?(operation == .move)
      }
    }
  }
#endif
