import Foundation
import PDFKit
setvbuf(stdout, nil, _IONBF, 0)

// End-to-end: a real multi-page PDF, the real index and a real local model. Skipped when Ollama is not running.
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("Falhou: \(name)") }
    print("PASS: \(name)")
}

let topics: [(String, String)] = [
    ("Company overview", "Northwind Tea Company was founded in 1998 in Porto and sells loose-leaf tea to cafés and restaurants in eleven countries. The company employs 240 people and runs two blending facilities."),
    ("Financial results", "Revenue for fiscal year 2025 reached 48.2 million euros, an increase of 12 percent over the previous year. Net profit was 5.1 million euros, and the board proposed a dividend of 0.40 euros per share."),
    ("Shipping policy", "International orders are dispatched within two business days and delivered within fourteen business days. Orders above 150 euros ship free of charge; otherwise a flat fee of 9 euros applies."),
    ("Warranty and returns", "Brewing equipment is covered by a two-year warranty against manufacturing defects. Unopened tea can be returned within thirty days for a full refund; opened packages cannot be returned."),
    ("Privacy", "Customer data is stored on servers located in Frankfurt and is never sold to third parties. Customers may request deletion of their personal data at any time by writing to the data protection officer."),
    ("Sustainability", "By 2027 all packaging will be compostable. The company buys 80 percent of its tea directly from cooperatives in Sri Lanka and Kenya and pays a premium of 15 percent above market price."),
]
var paragraphs: [Paragraph] = []
for (page, topic) in topics.enumerated() {
    paragraphs.append(Paragraph(page: page + 1, original: topic.0))
    paragraphs.append(Paragraph(page: page + 1, original: topic.1))
    paragraphs.append(Paragraph(page: page + 1, original: "This section is reviewed every year by the management team and published in the annual report of the company."))
}
var english = DocumentState(paragraphs)
for index in paragraphs.indices { english.apply(paragraphs[index].original, at: index) }
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory() + "paragrafo-fixture.pdf")
try Exporter.data(.pdf, filename: "Northwind Annual Report.pdf", targetName: "English", document: english).write(to: url)
let extracted = try PDFExtractor.extract(url: url)
check(extracted.paragraphs.count >= 12, "PDF de teste extraído (\(extracted.paragraphs.count) parágrafos, \(extracted.pageCount) páginas)")

check(DocumentAssistant.wantsOverview("Faça uma síntese geral deste documento.") && DocumentAssistant.wantsOverview("Resuma o documento") && DocumentAssistant.wantsOverview("Do que se trata?"), "pedidos de síntese do documento são reconhecidos")
check(!DocumentAssistant.wantsOverview("Resuma a política de garantia") && DocumentAssistant.wantsOverview("Quais são os pontos principais?") && DocumentAssistant.wantsOverview("Faça um resumo"), "resumo de um assunto não é síntese do documento")
check(!DocumentAssistant.wantsOverview("Resuma a cláusula 5") && !DocumentAssistant.wantsOverview("Quais os pontos principais do capítulo sobre envio?") && !DocumentAssistant.wantsOverview("Qual é o prazo de entrega?"), "pedidos sobre uma parte não viram síntese geral")
check(DocumentAssistant.isFollowUp("E na Europa?") && DocumentAssistant.isFollowUp("E quanto ao frete para pedidos pequenos?") && !DocumentAssistant.isFollowUp("Quem assina o contrato?") && !DocumentAssistant.isFollowUp("Qual é o prazo de entrega?"), "só perguntas de acompanhamento herdam a pergunta anterior")

guard await OllamaClient().isRunning() else {
    print("SKIP: Ollama não está em execução; perguntas reais não foram testadas")
    exit(0)
}

@MainActor func wait(_ assistant: DocumentAssistant, seconds: Double = 180) async {
    let start = Date()
    while assistant.busy && Date().timeIntervalSince(start) < seconds { try? await Task.sleep(for: .milliseconds(100)) }
}

Library.remove(extracted.fingerprint)
let assistant = DocumentAssistant()
assistant.attach(paragraphs: extracted.paragraphs, fingerprint: extracted.fingerprint)
Library.save(SavedDocument(name: "fixture.pdf", path: url.path, pages: extracted.pageCount, source: "en", target: "pt", translations: extracted.paragraphs.map { _ in "" }), fingerprint: extracted.fingerprint)
var clock = Date()
await assistant.prepare()
while assistant.indexState != .ready, Date().timeIntervalSince(clock) < 120 { try? await Task.sleep(for: .milliseconds(100)) }
check(assistant.availability == .ready && assistant.indexState == .ready, "índice construído em \(String(format: "%.2f", Date().timeIntervalSince(clock))) s")

clock = Date()
assistant.ask("Qual é o prazo de entrega para pedidos internacionais?")
await wait(assistant)
var reply = assistant.messages.last!
print("INFO: resposta em \(String(format: "%.1f", Date().timeIntervalSince(clock))) s: \(reply.text)")
check(reply.stage == .done && !reply.sources.isEmpty, "pergunta em português recebe resposta com trechos")
let shipping = extracted.paragraphs.firstIndex { $0.original.contains("fourteen business days") }!
check(reply.sources.prefix(3).contains { $0.chunk.paragraphs.contains(shipping) }, "o trecho sobre entrega está entre as três primeiras fontes")
check(!reply.cited.isEmpty && reply.cited.contains { reply.sources[$0 - 1].chunk.paragraphs.contains(shipping) }, "a resposta cita o trecho correto")
check(reply.text.contains("14") || reply.text.lowercased().contains("quatorze") || reply.text.lowercased().contains("catorze"), "a resposta traz o prazo do documento")

assistant.ask("E a receita?")
await wait(assistant)
reply = assistant.messages.last!
print("INFO: \(reply.text)")
check(reply.text.contains("48"), "pergunta de acompanhamento encontra a receita")

assistant.ask("Qual é a capital da Austrália segundo o documento?")
await wait(assistant)
reply = assistant.messages.last!
print("INFO: \(reply.text)")
check(!reply.text.lowercased().contains("canberra") && !reply.text.lowercased().contains("camberra"), "não responde com conhecimento de fora do documento")

clock = Date()
assistant.summarize()
await wait(assistant, seconds: 300)
reply = assistant.messages.last!
print("INFO: síntese em \(String(format: "%.1f", Date().timeIntervalSince(clock))) s:\n\(reply.text)")
check(reply.stage == .done && reply.isOverview && reply.text.count > 200, "síntese geral gerada")
let numbers = reply.text.matches(of: #/\[(\d+)\]/#).compactMap { Int($0.1) }
check(!numbers.isEmpty && numbers.allSatisfy { (1...reply.sources.count).contains($0) }, "toda citação da síntese corresponde a um trecho real (\(reply.sources.count) trechos)")
check(reply.cited.count >= 2 && AnswerFormatter.markdown(reply.text, sourceCount: reply.sources.count).contains("paragrafo://fonte/"), "síntese aponta para trechos clicáveis (\(reply.cited.count) fontes citadas)")
check(Library.load(extracted.fingerprint)?.summary == reply.text, "síntese fica salva com o documento")

assistant.ask("Explique a política de privacidade em detalhes, com todos os pontos.")
try? await Task.sleep(for: .milliseconds(1200))
assistant.stop()
clock = Date()
await wait(assistant, seconds: 10)
check(!assistant.busy && Date().timeIntervalSince(clock) < 3, "parar interrompe a resposta rapidamente")
check(assistant.messages.last!.stage == .done, "resposta interrompida fica em estado final")

assistant.clear()
assistant.summarize()
await wait(assistant, seconds: 10)
check(assistant.messages.last!.text == reply.text && assistant.messages.last!.cited == reply.cited && assistant.messages.last!.note != nil, "síntese salva volta na hora, com as fontes")

assistant.singlePassLimit = 900
clock = Date()
assistant.regenerate(assistant.messages.last!.id)
await wait(assistant, seconds: 300)
reply = assistant.messages.last!
print("INFO: síntese por partes (\(reply.sources.count) partes) em \(String(format: "%.1f", Date().timeIntervalSince(clock))) s:\n\(reply.text)")
check(reply.stage == .done && reply.sources.count >= 3 && !reply.cited.isEmpty && reply.text.count > 200, "documento longo: síntese por partes com fontes")
check(reply.sources.allSatisfy { extracted.paragraphs.indices.contains($0.chunk.paragraphs.lowerBound) }, "cada parte aponta para um parágrafo real")

// Reopening restores the index from disk instead of embedding again.
let again = DocumentAssistant()
again.attach(paragraphs: extracted.paragraphs, fingerprint: extracted.fingerprint)
clock = Date()
await again.prepare()
while again.indexState != .ready, Date().timeIntervalSince(clock) < 30 { try? await Task.sleep(for: .milliseconds(20)) }
check(again.indexState == .ready, "índice restaurado do disco em \(String(format: "%.2f", Date().timeIntervalSince(clock))) s")
Library.remove(extracted.fingerprint)
print("Todas as verificações do assistente passaram.")
