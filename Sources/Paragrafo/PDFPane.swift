import SwiftUI
import PDFKit

/// The original PDF, kept in step with the page being read and able to mark a passage on it.
struct PDFPane: NSViewRepresentable {
    let document: PDFDocument?
    let page: Int
    let highlight: CGRect?
    let token: Int
    let onPage: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPage: onPage) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .underPageBackgroundColor
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPage = onPage
        if view.document !== document {
            coordinator.clearMark()
            view.document = document
            coordinator.token = nil
        }
        guard let document, let target = document.page(at: page - 1) else { return }
        if coordinator.token != token {
            coordinator.token = token
            coordinator.clearMark()
            if let highlight {
                let box = highlight.insetBy(dx: -3, dy: -2)
                let mark = PDFAnnotation(bounds: box, forType: .highlight, withProperties: nil)
                mark.color = NSColor(srgbRed: 0.45, green: 0.80, blue: 0.62, alpha: 0.5)
                // Corners relative to the annotation's own bounds: top-left, top-right, bottom-left, bottom-right.
                mark.quadrilateralPoints = [CGPoint(x: 0, y: box.height), CGPoint(x: box.width, y: box.height), .zero, CGPoint(x: box.width, y: 0)]
                    .map { NSValue(point: $0) }
                target.addAnnotation(mark)
                coordinator.mark = mark
                view.go(to: highlight.insetBy(dx: 0, dy: -120), on: target)
            } else {
                view.go(to: target)
            }
        } else if view.currentPage !== target, coordinator.reported != page {
            // Navigate only for changes that came from the app, not for the echo of the user's own scrolling.
            view.go(to: target)
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.clearMark()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPage: (Int) -> Void
        var token: Int?
        var mark: PDFAnnotation?
        var reported: Int?
        init(onPage: @escaping (Int) -> Void) { self.onPage = onPage }

        func clearMark() {
            if let mark { mark.page?.removeAnnotation(mark) }
            mark = nil
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let current = view.currentPage,
                  let index = view.document?.index(for: current) else { return }
            // Posted while SwiftUI may be updating the view; report on the next turn.
            reported = index + 1
            DispatchQueue.main.async { [weak self] in self?.onPage(index + 1) }
        }
    }
}
