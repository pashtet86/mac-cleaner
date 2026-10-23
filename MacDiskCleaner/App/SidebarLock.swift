import AppKit
import SwiftUI

/// Keeps the sidebar permanently visible within a width range.
///
/// `NavigationSplitView` is backed by an `NSSplitViewController` on macOS. SwiftUI exposes no way
/// to stop the user dragging the sidebar closed, so this finds the controller's sidebar item and
/// turns collapsing off, with explicit minimum and maximum widths.
struct SidebarLock: NSViewRepresentable {
    var minimum: CGFloat
    var maximum: CGFloat

    func makeNSView(context: Context) -> NSView { ProbeView(minimum: minimum, maximum: maximum) }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ProbeView)?.apply()
    }

    private final class ProbeView: NSView {
        let minimum: CGFloat
        let maximum: CGFloat

        init(minimum: CGFloat, maximum: CGFloat) {
            self.minimum = minimum
            self.maximum = maximum
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The split view is set up after this view joins the window; try again shortly after.
            for delay in [0.0, 0.3, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() }
            }
        }

        func apply() {
            guard let window else { return }
            let split =
                window.contentViewController.flatMap(Self.splitController(in:))
                ?? window.contentView.flatMap(Self.splitView(in:)).flatMap { $0.delegate as? NSSplitViewController }
            guard let split,
                let item = split.splitViewItems.first(where: { $0.behavior == .sidebar }) ?? split.splitViewItems.first
            else { return }
            item.canCollapse = false
            item.minimumThickness = minimum
            item.maximumThickness = maximum
            if item.isCollapsed { item.isCollapsed = false }
        }

        private static func splitView(in view: NSView) -> NSSplitView? {
            if let split = view as? NSSplitView { return split }
            for subview in view.subviews {
                if let found = splitView(in: subview) { return found }
            }
            return nil
        }

        private static func splitController(in controller: NSViewController) -> NSSplitViewController? {
            if let split = controller as? NSSplitViewController { return split }
            for child in controller.children {
                if let found = splitController(in: child) { return found }
            }
            return nil
        }
    }
}
