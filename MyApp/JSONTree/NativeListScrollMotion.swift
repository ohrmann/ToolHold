#if os(macOS)
import AppKit

/// Bounded viewport movement. An opt-in for generated lists; interrupted by any
/// subsequent reveal, wheel event or native scrollbar drag. Never changes focus.
@MainActor final class NativeListScrollMotion {
    private var timer: Timer?
    private var wheelMonitor: Any?
    private var liveScrollObserver: NSObjectProtocol?
    func cancel() {
        timer?.invalidate(); timer = nil
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor); self.wheelMonitor = nil }
        if let liveScrollObserver { NotificationCenter.default.removeObserver(liveScrollObserver); self.liveScrollObserver = nil }
    }
    func reveal(_ rect: CGRect, in scroll: NSScrollView, animated: Bool) {
        cancel()
        let clip = scroll.contentView, current = clip.bounds.origin
        guard !clip.bounds.contains(rect) else { return }
        let proposed = CGRect(x: current.x, y: rect.midY - clip.bounds.height / 2, width: clip.bounds.width, height: clip.bounds.height)
        let target = clip.constrainBoundsRect(proposed).origin
        guard animated, abs(target.y - current.y) > 1 else { clip.scroll(to: target); scroll.reflectScrolledClipView(clip); return }
        let start = ProcessInfo.processInfo.systemUptime
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak scroll] event in
            if let scroll, event.window === scroll.window, event.type != .scrollWheel || scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)) { self?.cancel() }
            return event
        }
        liveScrollObserver = NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self, weak scroll] _ in
            MainActor.assumeIsolated {
                guard let self, let scroll else { return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.2)
                let eased = progress * progress * (3 - 2 * progress)
                let point = CGPoint(x: current.x, y: current.y + (target.y - current.y) * eased)
                scroll.contentView.scroll(to: point); scroll.reflectScrolledClipView(scroll.contentView)
                if progress >= 1 { self.cancel() }
            }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
}
#endif
