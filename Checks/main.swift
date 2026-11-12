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

var document = DocumentState([
    Paragraph(page: 1, original: "One"), Paragraph(page: 1, original: "Two"),
    Paragraph(page: 3, original: "Three")
])
check(document.pages == [1, 3] && document.pageRanges[1] == 0..<2 && document.pageRanges[3] == 2..<3, "navegação preserva páginas sem texto e ordem")
document.apply("Três", at: 2)
document.apply("Um", at: 0)
document.apply("Um revisado", at: 0)
check(document.completed == 2 && document.paragraphs[2].translated == "Três", "contagem exata com respostas fora de ordem e atualizações repetidas")
document.apply("", at: 1)
document.apply("Inválido", at: 99)
check(document.completed == 2, "respostas vazias e índices inválidos não alteram progresso")
document.clearTranslations()
check(document.completed == 0 && document.paragraphs.allSatisfy { $0.translated.isEmpty }, "trocar destino limpa todo o progresso")
check(DocumentState().pages.isEmpty && DocumentState().completed == 0, "documento vazio")

let cancellation = Task.detached {
    while !Task.isCancelled { await Task.yield() }
    return try PDFExtractor.extract(url: url)
}
cancellation.cancel()
do {
    _ = try await cancellation.value
    fatalError("Importação cancelada não deve concluir")
} catch is CancellationError {
    print("PASS: cancelamento da tarefa de importação")
}
if let fixture = ProcessInfo.processInfo.environment["PARAGRAFO_FIXTURE"] {
    try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: fixture))
}

let scanURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
defer { try? FileManager.default.removeItem(at: scanURL) }
let bitmap = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.setFillColor(NSColor.white.cgColor)
bitmap.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
("Revenue in 2025: 1250 dollars." as NSString).draw(at: CGPoint(x: 70, y: 600), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
NSGraphicsContext.restoreGraphicsState()
let raster = NSImage(cgImage: bitmap.makeImage()!, size: NSSize(width: 1200, height: 800))
let scannedPDF = PDFDocument()
scannedPDF.insert(PDFPage(image: raster)!, at: 0)
check(scannedPDF.write(to: scanURL), "criação do PDF digitalizado de teste")
let scanned = try PDFExtractor.extract(url: scanURL)
check(scanned.ocrPages == 1 && scanned.paragraphs.contains { $0.original.contains("1250") }, "OCR real reconhece texto e números")
