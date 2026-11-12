import Foundation
import AppKit
import PDFKit

func check(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("Falhou: \(name)") }
    print("PASS: \(name)")
}
check(Paragraphs.group([TextLine(text: "Receita de 2025:", x: 10, y: 100, height: 12), TextLine(text: "R$ 1.250,00.", x: 10, y: 86, height: 12)]) == ["Receita de 2025: R$ 1.250,00."], "quebras de linha e números")
check(Paragraphs.group([TextLine(text: "Primeiro.", x: 10, y: 100, height: 12), TextLine(text: "Segundo.", x: 10, y: 65, height: 12)]) == ["Primeiro.", "Segundo."], "parágrafos separados")
check(Paragraphs.group([TextLine(text: "日本語 العربية", x: 10, y: 100, height: 12), TextLine(text: "• café", x: 10, y: 86, height: 12)]) == ["日本語 العربية", "• café"], "Unicode e listas")
check(Paragraphs.group([TextLine(text: "  ", x: 0, y: 0, height: 12)]).isEmpty, "linhas vazias")
let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
defer { try? FileManager.default.removeItem(at: url) }
var bounds = CGRect(x: 0, y: 0, width: 500, height: 700)
let context = CGContext(url as CFURL, mediaBox: &bounds, nil)!
context.beginPDFPage(nil)
let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
("Hello world. Revenue: 1250." as NSString).draw(at: CGPoint(x: 40, y: 600), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
("Second paragraph." as NSString).draw(at: CGPoint(x: 40, y: 540), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
NSGraphicsContext.restoreGraphicsState()
context.endPDFPage()
context.closePDF()
let extracted = try PDFExtractor.extract(url: url)
check(extracted.paragraphs.count == 2, "extração de PDF real com dois parágrafos")
check(extracted.paragraphs[0].original.contains("1250"), "números preservados no PDF")
check(extracted.ocrPages == 0, "PDF textual dispensa OCR")
