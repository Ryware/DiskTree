import SwiftUI
import AppKit

/// Pins the hosting NSWindow's minimum size and grows a restored window that is
/// smaller than that (saved frames can otherwise violate SwiftUI's minWidth and
/// trigger split-view constraint exceptions).
struct WindowSizing: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { apply(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { apply(v.window) }
    }
    private func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.minSize = minSize
        window.contentMinSize = minSize
        var f = window.frame
        if f.width < minSize.width || f.height < minSize.height {
            f.size.width = max(f.width, minSize.width)
            f.size.height = max(f.height, minSize.height)
            if let screen = window.screen?.visibleFrame {
                f.origin.x = min(f.origin.x, screen.maxX - f.width)
                f.origin.y = max(f.origin.y, screen.minY)
            }
            window.setFrame(f, display: true, animate: false)
        }
    }
}
