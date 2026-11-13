import Foundation
import AppKit
import PDFKit
let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("paragrafo-perf-\(UUID().uuidString).pdf")
defer { try? FileManager.default.removeItem(at: url) }
var rect = CGRect(x: 0, y: 0, width: 600, height: 800)
let context = CGContext(url as CFURL, mediaBox: &rect, nil)!
for page in 1...200 {
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for line in 0..<32 {
        ("Page \(page), line \(line). Revenue in 2025 reached 1250 dollars." as NSString).draw(at: CGPoint(x: 30, y: 750 - line * 22), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
    }
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
}
context.closePDF()
let start = Date()
let result = try PDFExtractor.extract(url: url)
precondition(result.pageCount == 200 && result.paragraphs.map(\.original).joined().contains("1250"))
print(String(format: "200 pages | %d paragraphs | extraction %.3f s", result.paragraphs.count, Date().timeIntervalSince(start)))
