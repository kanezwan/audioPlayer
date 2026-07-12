import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()

            Divider()

            HSplitView {
                SidebarView()
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)
                    .layoutPriority(0)

                MainPlayerView()
                    .frame(minWidth: 400)
                    .layoutPriority(1)
            }

            Divider()

            StatusBarView()
        }
        .environment(viewModel)
        .frame(minWidth: 800, minHeight: 500)
        .background(SplitViewInitializer(sidebarWidth: 200))
    }
}

/// Resets the HSplitView divider position on first appear so the sidebar
/// starts narrow (~200pt) instead of the default 50/50 split.
private struct SplitViewInitializer: NSViewRepresentable {
    let sidebarWidth: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyDividerPosition(in: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyDividerPosition(in: nsView.window)
        }
    }

    private func applyDividerPosition(in window: NSWindow?) {
        guard let window = window,
              let splitView = window.contentView?.findFirstSplitView() else { return }
        let totalWidth = splitView.bounds.width
        guard totalWidth > 0 else { return }
        let sidebarTarget = min(max(sidebarWidth, 160), totalWidth - 400)
        let position = splitView.convert(CGPoint(x: sidebarTarget, y: 0), to: nil).x
        splitView.setPosition(position, ofDividerAt: 0)
    }
}

private extension NSView {
    func findFirstSplitView() -> NSSplitView? {
        if let split = self as? NSSplitView { return split }
        for subview in subviews {
            if let found = subview.findFirstSplitView() { return found }
        }
        return nil
    }
}

#Preview {
    ContentView()
}
