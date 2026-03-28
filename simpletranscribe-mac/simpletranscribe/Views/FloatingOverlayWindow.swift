import AppKit
import SwiftUI

final class FloatingOverlayWindow {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(state: OverlayState) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        let hostingView = NSHostingView(rootView: FloatingOverlayView(state: state))
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = getOrCreatePanel()
        panel.contentView = hostingView

        // Size to fit content
        let size = hostingView.fittingSize
        positionPanel(panel, size: size)

        panel.orderFrontRegardless()
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
    }

    func showDone() {
        show(state: .done)
        autoDismiss(after: 1.5)
    }

    func showError(_ message: String) {
        show(state: .error(message))
        autoDismiss(after: 3.0)
    }

    // MARK: - Private

    private func getOrCreatePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false

        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let visibleFrame = screen.visibleFrame

        let x = visibleFrame.maxX - size.width - margin
        let y = visibleFrame.maxY - size.height - margin
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    private func autoDismiss(after seconds: TimeInterval) {
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
