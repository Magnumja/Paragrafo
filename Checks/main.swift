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

check(!TranslationInput.needsTranslation("2025 — 1.250,00 •"), "números e pontuação não exigem tradução")
check(TranslationInput.needsTranslation("The document explains the translation process."), "texto em inglês exige tradução")
check(TranslationInput.needsTranslation("日本語 العربية"), "texto fora do alfabeto latino exige tradução")
check(TranslationInput.detectLanguage(in: [Paragraph(page: 1, original: "2025"), Paragraph(page: 1, original: "The document explains how to translate each paragraph into another language.")]) == "en", "cabeçalho numérico não impede detecção do inglês")
check(TranslationInput.detectLanguage(in: [Paragraph(page: 1, original: "1250")]) == nil, "documento numérico não recebe idioma inventado")
check(TranslationInput.sameLanguage("pt", "pt-BR") && !TranslationInput.sameLanguage("en", "pt-BR"), "origem igual ao destino identificada antes da chamada")

// Hyphenation, highlight bounds and reading-order helpers
check(Paragraphs.group([TextLine(text: "The trans-", x: 10, y: 100, height: 12), TextLine(text: "lation is ready.", x: 10, y: 86, height: 12)]) == ["The translation is ready."], "palavra hifenizada no fim da linha é reunida")
check(Paragraphs.group([TextLine(text: "Intervalo 10-", x: 10, y: 100, height: 12), TextLine(text: "20 unidades.", x: 10, y: 86, height: 12)]) == ["Intervalo 10- 20 unidades."], "hífen entre números não é removido")
let blocks = Paragraphs.blocks([TextLine(text: "Primeira linha", x: 10, y: 100, height: 12, width: 200), TextLine(text: "segunda linha.", x: 10, y: 86, height: 12, width: 150)])
check(blocks.count == 1 && blocks[0].bounds == CGRect(x: 10, y: 86, width: 200, height: 26), "área do parágrafo é a união das linhas")
check(extracted.paragraphs.allSatisfy { ($0.bounds?.width ?? 0) > 0 } && extracted.pageCount == 1 && extracted.fingerprint.count == 64, "extração traz área, contagem de páginas e impressão digital")
check(scanned.paragraphs.allSatisfy { box in box.bounds.map { $0.maxX <= 1200 && $0.maxY <= 800 && $0.width > 50 } ?? false }, "área do OCR em coordenadas da página")

var ordered = DocumentState([Paragraph(page: 1, original: "a"), Paragraph(page: 1, original: "b"), Paragraph(page: 2, original: "c"), Paragraph(page: 3, original: "d")])
check(ordered.pendingOrder(from: 2) == [2, 3, 0, 1], "tradução começa pela página em leitura e depois volta ao início")
ordered.apply("C", at: 2)
check(ordered.pendingOrder(from: 2) == [3, 0, 1] && ordered.completedByPage[2] == 1 && ordered.completedByPage[1] == nil && !ordered.isComplete, "progresso por página")
ordered.clearTranslations()
check(ordered.completedByPage.isEmpty, "limpar zera o progresso por página")

// Saved work
let key = "check-" + UUID().uuidString
Library.save(SavedDocument(name: "a.pdf", path: "/tmp/a.pdf", pages: 3, source: "en", target: "pt", translations: ["Um", "", "Três"]), fingerprint: key)
Library.update(key) { $0.summary = "Síntese" }
let saved = Library.load(key)
check(saved?.translations == ["Um", "", "Três"] && saved?.summary == "Síntese" && saved?.target == "pt", "tradução e síntese salvas são restauradas")
check(Library.recents().first.map { $0.id == key && $0.completed == 2 && $0.paragraphs == 3 } ?? false, "documento salvo aparece nos recentes com o progresso")
Library.saveVectors([[1, 2, 3], [4, 5, 6]], fingerprint: key)
check(Library.loadVectors(fingerprint: key, count: 2, dimension: 3) ?? [] == [[1, 2, 3], [4, 5, 6]], "vetores do índice são restaurados")
check(Library.loadVectors(fingerprint: key, count: 3, dimension: 3) == nil, "índice de tamanho diferente é recusado")
Library.remove(key)
check(Library.load(key) == nil && !Library.recents().contains { $0.id == key }, "remover apaga o documento salvo")

// Answers that point back into the document
let linked = AnswerFormatter.markdown("## Resumo\n- O prazo é de 14 dias [1, 3].\n- Veja a página 12 e (p. 4) [9]", sourceCount: 3)
check(linked.contains("**Resumo**") && linked.contains("• O prazo"), "títulos e listas do modelo viram texto limpo")
check(linked.contains("[\\[1\\]](paragrafo://fonte/1) [\\[3\\]](paragrafo://fonte/3)") && !linked.contains("fonte/9"), "citações viram links e as inválidas somem")
check(linked.contains("(paragrafo://pagina/12)") && linked.contains("(paragrafo://pagina/4)"), "menções a páginas viram links")
check(AnswerFormatter.destination(URL(string: "paragrafo://fonte/2")!) == .source(2) && AnswerFormatter.destination(URL(string: "paragrafo://pagina/7")!) == .page(7) && AnswerFormatter.destination(URL(string: "https://example.com/3")!) == nil, "links internos são interpretados")
check(String(AnswerFormatter.attributed("Prazo de **14 dias** [1].", sourceCount: 1).characters) == "Prazo de 14 dias [1].", "texto formatado preserva o conteúdo")

// Exports
var exported = DocumentState([Paragraph(page: 1, original: "Hello."), Paragraph(page: 2, original: "Pending.")])
exported.apply("Olá.", at: 0)
let pdfData = Exporter.data(.pdf, filename: "doc.pdf", targetName: "Português", document: exported)
let rendered = PDFDocument(data: pdfData)
check(rendered?.pageCount == 1 && (rendered?.string ?? "").contains("Olá.") && (rendered?.string ?? "").contains("Pending."), "PDF exportado contém a tradução e mantém o original pendente")
let md = Exporter.markdown(filename: "doc.pdf", targetName: "Português", document: exported)
check(md.contains("## Página 2") && md.contains("> Hello.") && md.contains("_[Não traduzido]_"), "Markdown bilíngue por página")
var long = DocumentState((0..<400).map { Paragraph(page: $0 / 10 + 1, original: "Parágrafo \($0) " + String(repeating: "texto ", count: 60)) })
for index in 0..<400 { long.apply("Tradução \(index) " + String(repeating: "texto ", count: 60), at: index) }
let longPDF = PDFDocument(data: Exporter.data(.pdf, filename: "longo.pdf", targetName: "Português", document: long))
check((longPDF?.pageCount ?? 0) > 20 && (longPDF?.string ?? "").contains("Tradução 399"), "PDF longo pagina até o último parágrafo")
let sized = [TextLine(text: "Financial results", x: 10, y: 100, height: 24), TextLine(text: "Revenue reached 48.2 million", x: 10, y: 80, height: 14), TextLine(text: "euros in 2025.", x: 10, y: 64, height: 14)]
check(Paragraphs.blocks(sized, splitOnSizeChange: true).map(\.text) == ["Financial results", "Revenue reached 48.2 million euros in 2025."], "título em fonte maior não se funde ao parágrafo")
check(Paragraphs.blocks(sized).count == 1, "OCR não separa por altura de linha")
check(AnswerFormatter.markdown("- - Ponto duplo\n• - Outro\n* Simples", sourceCount: 0) == "• Ponto duplo\n• Outro\n• Simples", "marcadores repetidos do modelo viram um só")

// Security: derived storage paths must stay inside the library, including symlink targets.
let sentinel = Library.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".json")
try Data("preserve me".utf8).write(to: sentinel)
defer { try? FileManager.default.removeItem(at: sentinel) }
Library.remove("../" + sentinel.deletingPathExtension().lastPathComponent)
check(FileManager.default.fileExists(atPath: sentinel.path), "remoção recusa travessia fora da biblioteca")
let linkName = "symlink-test"
try FileManager.default.createSymbolicLink(at: Library.directory.appendingPathComponent(linkName + ".json"), withDestinationURL: sentinel)
Library.remove(linkName)
check(FileManager.default.fileExists(atPath: sentinel.path) && Library.load(linkName) == nil, "biblioteca recusa symlink para fora da pasta")
check(Library.loadVectors(fingerprint: key, count: Int.max, dimension: Int.max) == nil, "dimensões malformadas não causam overflow")
check(AnswerFormatter.destination(URL(string: "paragrafo://fonte/-1")!) == nil, "citações negativas são recusadas")
