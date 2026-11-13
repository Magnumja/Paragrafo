import AppKit

/// Page turning without the mouse in the bilingual reader:
/// ← → and Page Up / Page Down move one page, Home / End jump to the first / last page,
/// and a horizontal two-finger swipe over the text turns the page (finger to the left = next).
///
/// Keys are ignored while the user is typing (the assistant's composer, any editable field),
/// when a modifier is held (so ⇧← still extends a selection and ⌘← still works in text),
/// in the PDF mode (PDFView pages on its own) and in other windows such as the PDF peek popover.
@MainActor
final class PageNavigation {
    var enabled = false
    /// The reading column in SwiftUI's global space (window content, top-left origin).
    var readingFrame: CGRect = .zero

    private weak var model: ReaderModel?
    private var monitors: [Any] = []
    private var swipe: CGFloat = 0
    private var swiped = false

    /// Horizontal travel, in points, that turns the page.
    private static let swipeThreshold: CGFloat = 110

    func install(model: ReaderModel) {
        self.model = model
        guard monitors.isEmpty else { return }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let handled = MainActor.assumeIsolated { [weak self] in self?.key(event) ?? false }
            return handled ? nil : event
        }) { monitors.append(keys) }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { event in
            let handled = MainActor.assumeIsolated { [weak self] in self?.scroll(event) ?? false }
            return handled ? nil : event
        }) { monitors.append(scroll) }
    }

    func uninstall() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    // MARK: Keyboard

    private func key(_ event: NSEvent) -> Bool {
        guard ready(for: event), !isTyping(in: event.window),
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 123, 116: return turn(-1)                // ←, Page Up
        case 124, 121: return turn(1)                 // →, Page Down
        case 115: return jump(to: model?.document.pages.first)   // Home
        case 119: return jump(to: model?.document.pages.last)    // End
        default: return false
        }
    }

    private func isTyping(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if let text = responder as? NSTextView { return text.isEditable }
        // Controls that use ← → themselves when focused with Full Keyboard Access (e.g. the reading-mode picker).
        return responder is NSTextField || responder is NSSegmentedControl || responder is NSSlider
    }

    // MARK: Trackpad

    private func scroll(_ event: NSEvent) -> Bool {
        // Only real trackpad gestures; momentum after lifting the fingers never turns a second page.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return false }
        if event.phase.contains(.began) { swipe = 0; swiped = false }
        defer { if event.phase.contains(.ended) || event.phase.contains(.cancelled) { swipe = 0; swiped = false } }
        guard ready(for: event), contains(event) else { return false }

        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) * 1.5 else { return false }
        // Follow the fingers whatever the "natural scrolling" setting is.
        swipe += event.isDirectionInvertedFromDevice ? dx : -dx
        if !swiped, abs(swipe) > Self.swipeThreshold {
            swiped = true
            _ = turn(swipe > 0 ? -1 : 1)   // fingers to the right = previous page, like going back in Safari
        }
        return true
    }

    private func contains(_ event: NSEvent) -> Bool {
        guard let height = event.window?.contentView?.bounds.height else { return false }
        let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        return readingFrame.contains(point)
    }

    // MARK: Paging

    private func ready(for event: NSEvent) -> Bool {
        guard enabled, let model, !model.document.isEmpty, let window = event.window else { return false }
        // The main reader window only: the PDF peek popover and sheets handle their own keys.
        return window === NSApp.mainWindow && window.attachedSheet == nil
    }

    private func turn(_ offset: Int) -> Bool {
        guard let model else { return false }
        model.movePage(offset)
        return true
    }

    private func jump(to page: Int?) -> Bool {
        guard let model, let page else { return false }
        model.selectedPage = page
        return true
    }
}
