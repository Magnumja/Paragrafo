import Foundation

func check(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("Falhou: \(name)") }
    print("PASS: \(name)")
}
func unit(_ values: [Float]) -> [Float] {
    let norm = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
    return values.map { $0 / norm }
}
func norm(_ values: [Float]) -> Float { values.reduce(0) { $0 + $1 * $1 }.squareRoot() }
func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
func covered(_ chunks: [Chunk], count: Int) -> Bool {
    let indices = Set(chunks.flatMap { Array($0.paragraphs) })
    let ordered = zip(chunks, chunks.dropFirst()).allSatisfy { $0.paragraphs.lowerBound <= $1.paragraphs.lowerBound && $0.paragraphs.upperBound <= $1.paragraphs.upperBound }
    return indices == Set(0..<count) && ordered && chunks.enumerated().allSatisfy { $0.offset == $0.element.id }
}

// MARK: Chunker

let sentence = "The quarterly report describes how the company performed in every region. "
let medium = String(repeating: sentence, count: 5).trimmingCharacters(in: .whitespaces)   // ~370 characters
var document: [Paragraph] = []
for page in 1...3 { for _ in 0..<6 { document.append(Paragraph(page: page, original: medium)) } }
let grouped = Chunker.chunks(from: document)
check(covered(grouped, count: document.count), "chunker cobre todos os parágrafos em ordem com ids sequenciais")
check(grouped.allSatisfy { chunk in chunk.paragraphs.allSatisfy { document[$0].page == chunk.page } }, "chunker respeita limites de página")
check(grouped.allSatisfy { $0.text.count <= 1600 } && grouped.contains { $0.paragraphs.count > 1 } && grouped.count < document.count, "chunker agrupa até o alvo sem passar do máximo")
check(grouped.allSatisfy { chunk in chunk.paragraphs.allSatisfy { chunk.text.contains(document[$0].original) } }, "chunker preserva o texto original dos parágrafos")
check(Chunker.chunks(from: []).isEmpty, "chunker com documento vazio")
check(Chunker.chunks(from: [Paragraph(page: 1, original: "A"), Paragraph(page: 2, original: "B"), Paragraph(page: 1, original: "C")]).map(\.page) == [1, 2, 1], "chunker não junta páginas iguais não consecutivas")

let long = (1...60).map { "Sentence number \($0) explains one more detail of the agreement between the parties." }.joined(separator: " ")
let withLong = [Paragraph(page: 1, original: "Short introduction."), Paragraph(page: 1, original: long), Paragraph(page: 1, original: "Short conclusion.")]
let splitChunks = Chunker.chunks(from: withLong)
let pieces = splitChunks.filter { $0.paragraphs == 1..<2 }
check(long.count > 1600 && pieces.count >= 3 && pieces.allSatisfy { $0.text.count <= 1600 }, "parágrafo longo é dividido em vários chunks do mesmo parágrafo")
check(pieces.allSatisfy { $0.text.hasSuffix(".") && $0.text.hasPrefix("Sentence number") }, "divisão acontece em fronteiras de frase")
check(pieces.map(\.text).joined(separator: " ") == long, "divisão não perde nem duplica texto")
check(covered(splitChunks, count: 3) && splitChunks.first?.text == "Short introduction." && splitChunks.last?.text == "Short conclusion.", "vizinhos do parágrafo longo continuam cobertos")
let unbroken = String(repeating: "x", count: 4000)
let hard = Chunker.chunks(from: [Paragraph(page: 1, original: unbroken)])
check(hard.count == 3 && hard.allSatisfy { $0.text.count <= 1600 && $0.paragraphs == 0..<1 } && hard.map(\.text).joined() == unbroken, "texto sem frases nem espaços ainda respeita o máximo")
check(Chunker.chunks(from: withLong, targetLength: 200, maxLength: 300).allSatisfy { $0.text.count <= 300 }, "limites personalizados são respeitados")

let numeric = [
    Paragraph(page: 1, original: "12"), Paragraph(page: 1, original: String(repeating: "a", count: 1000)),
    Paragraph(page: 1, original: "3.450,00"), Paragraph(page: 1, original: String(repeating: "b", count: 1000)), Paragraph(page: 1, original: "— 7 —"),
    Paragraph(page: 2, original: "2025"), Paragraph(page: 2, original: "• 14"),
    Paragraph(page: 3, original: "99"), Paragraph(page: 3, original: long), Paragraph(page: 3, original: "100")
]
let numericChunks = Chunker.chunks(from: numeric)
check(covered(numericChunks, count: numeric.count), "parágrafos numéricos continuam cobertos")
check(numericChunks.filter { $0.page != 2 }.allSatisfy { $0.text.contains(where: \.isLetter) }, "parágrafo sem letras nunca vira chunk isolado")
check(numericChunks.filter { $0.page == 2 } == [Chunk(id: numericChunks.first { $0.page == 2 }!.id, page: 2, paragraphs: 5..<7, text: "2025\n• 14")], "página só com números gera um único chunk")
check(numericChunks.first?.text.hasPrefix("12\n") == true && numericChunks.contains { $0.text.hasSuffix("\n— 7 —") } && numericChunks.contains { $0.text.hasPrefix("99\n") } && numericChunks.last?.text.hasSuffix("\n100") == true, "números se anexam ao vizinho anterior ou seguinte")
check(numericChunks.allSatisfy { $0.text.count <= 1600 }, "anexar números não ultrapassa o máximo")

// MARK: VectorIndex

func chunk(_ id: Int, _ text: String, page: Int = 1) -> Chunk { Chunk(id: id, page: page, paragraphs: id..<id + 1, text: text) }
let corpus = [
    chunk(0, "Revenue grew twelve percent during the fiscal year."),
    chunk(1, "A tradução automática preserva o sentido do texto."),
    chunk(2, "Warranty covers manufacturing defects for two years."),
    chunk(3, "Shipping takes five business days after payment.")
]
let index = VectorIndex(chunks: corpus, vectors: [unit([1, 0, 0, 0]), unit([0, 1, 0, 0]), unit([0.6, 0, 0.8, 0]), unit([0, 0, 0, 1])])
let dense = index.search(queryVector: [2, 0, 0, 0], queryText: "", limit: 6, minimumScore: 0.25)
check(dense.map(\.chunk.id) == [0, 2], "ranking denso ordena por cosseno e descarta abaixo do mínimo")
check(abs(dense[0].score - 1) < 1e-5 && abs(dense[1].score - 0.6) < 1e-5, "score é o cosseno mesmo com consulta não normalizada")
check(index.search(queryVector: [1, 0, 0, 0], queryText: "", minimumScore: 0.7).map(\.chunk.id) == [0], "filtro de score mínimo")
check(index.search(queryVector: [1, 0, 0, 0], queryText: "", limit: 1).count == 1 && index.search(queryVector: [1, 0, 0, 0], queryText: "", limit: 0).isEmpty, "limite de resultados")

let lexicalOnly = index.search(queryVector: [], queryText: "traducao")
check(lexicalOnly.map(\.chunk.id) == [1] && lexicalOnly[0].score == 0, "BM25 ignora acentos e score é 0 sem vetor")
check(index.search(queryVector: [], queryText: "TRADUÇÃO do texto").first?.chunk.id == 1, "BM25 ignora maiúsculas")
check(index.search(queryVector: [], queryText: "de a o que the of").isEmpty && index.search(queryVector: [], queryText: "x y").isEmpty, "stopwords e tokens curtos não casam")
check(index.search(queryVector: [1, 2], queryText: "warranty").map(\.chunk.id) == [2], "vetor de dimensão errada cai para busca lexical")

let rescued = index.search(queryVector: [1, 0, 0, 0], queryText: "shipping payment")
check(rescued.map(\.chunk.id) == [0, 2, 3] && rescued[2].score == 0, "acerto só de palavra resgata o trecho abaixo do score mínimo, sem passar à frente do melhor trecho semântico")
let fused = index.search(queryVector: [0.6, 0, 0.8, 0], queryText: "revenue")
check(fused.map(\.chunk.id) == [0, 2], "RRF combina ranking denso e lexical")
check(index.search(queryVector: [0.6, 0, 0.8, 0], queryText: "nothing matches here").map(\.chunk.id) == [2, 0], "sem acerto lexical vale só o ranking denso")

check(index.search(queryVector: [], queryText: "garantia").isEmpty, "sem extraText a tradução não é encontrada")
let translated = index.search(queryVector: [], queryText: "garantia", extraText: [2: "A garantia cobre defeitos de fabricação por dois anos."])
check(translated.map(\.chunk.id) == [2], "extraText entra no corpus lexical do chunk")
check(index.search(queryVector: [0, 1, 0, 0], queryText: "fabricacao", extraText: [2: "A garantia cobre defeitos de fabricação por dois anos."]).map(\.chunk.id) == [1, 2], "extraText participa da fusão com o ranking denso")
check(VectorIndex(chunks: [], vectors: []).search(queryVector: [1], queryText: "a").isEmpty, "índice vazio")
check(VectorIndex(chunks: corpus, vectors: []).search(queryVector: [1, 0, 0, 0], queryText: "warranty").map(\.chunk.id) == [2], "índice sem vetores ainda responde lexicalmente")

// MARK: RAGPrompt

check(RAGPrompt.citations(in: "A entrega leva cinco dias [2]. Veja também [1, 3] e [1][4].", sourceCount: 4) == [1, 2, 3, 4], "citações simples, em lista e adjacentes")
check(RAGPrompt.citations(in: "Fora do intervalo [0], [7] e [2].", sourceCount: 3) == [2], "citações fora do intervalo são ignoradas")
check(RAGPrompt.citations(in: "Texto [nota], [a1], [], [ 3 ] e [2;1].", sourceCount: 3) == [1, 2, 3], "colchetes sem número não são citações")
check(RAGPrompt.citations(in: "Resumo [1-3].", sourceCount: 5) == [1, 2, 3] && RAGPrompt.citations(in: "Sem fontes.", sourceCount: 3).isEmpty && RAGPrompt.citations(in: "[1]", sourceCount: 0).isEmpty, "intervalos, resposta sem citações e zero fontes")

let sources = [Retrieved(chunk: chunk(3, "Shipping takes five business days.", page: 7), score: 0.8), Retrieved(chunk: chunk(0, "Revenue grew.", page: 2), score: 0.5)]
let history = (1...6).map { OllamaMessage(role: $0 % 2 == 1 ? "user" : "assistant", content: "h\($0)") }
let prompt = RAGPrompt.messages(question: "Qual é o prazo?", sources: sources, history: history)
check(prompt.count == 6 && prompt.first == OllamaMessage(role: "system", content: RAGPrompt.system) && prompt.last?.role == "user", "messages(): system, histórico e pergunta")
check(prompt[1...4].map(\.content) == ["h3", "h4", "h5", "h6"], "messages(): só as 4 últimas mensagens do histórico")
let userContent = prompt.last!.content
check(userContent.contains("[1] (página 7)\nShipping takes five business days.") && userContent.contains("[2] (página 2)\nRevenue grew."), "messages(): trechos numerados com página")
check(userContent.range(of: "Qual é o prazo?")!.lowerBound > userContent.range(of: "Revenue grew.")!.upperBound, "messages(): pergunta vem depois dos trechos")
check(RAGPrompt.messages(question: "Oi", sources: [], history: []).count == 2 && !RAGPrompt.system.isEmpty, "messages(): sem histórico nem fontes")

// MARK: OllamaClient (offline)

let installed = ["llama3.2:3b", "bge-m3:latest"]
check(OllamaClient.hasModel("bge-m3", in: installed) && OllamaClient.hasModel("bge-m3:latest", in: installed) && OllamaClient.hasModel("llama3.2:3b", in: installed), "hasModel: sem tag casa qualquer tag e com tag casa exato")
check(OllamaClient.hasModel("llama3.2", in: installed) && !OllamaClient.hasModel("llama3.2:1b", in: installed) && !OllamaClient.hasModel("llama3", in: installed) && !OllamaClient.hasModel("bge", in: installed) && !OllamaClient.hasModel("", in: installed) && !OllamaClient.hasModel("bge-m3", in: []), "hasModel: tag diferente, prefixo e vazio não casam")
check(OllamaError.modelMissing("x") != OllamaError.notRunning && [OllamaError.notRunning, .modelMissing("bge-m3"), .server("falha")].allSatisfy { !($0.errorDescription ?? "").isEmpty }, "OllamaError tem mensagens e é comparável")


check(OllamaClient.isLocalEndpoint(URL(string: "http://127.0.0.1:11434")!) && !OllamaClient.isLocalEndpoint(URL(string: "https://example.com")!), "Ollama aceita apenas endpoint loopback")
check(!OllamaClient.isLocalModel("llama:cloud") && OllamaClient.isLocalModel("llama3.2:3b"), "modelos cloud são recusados")
let remote = OllamaClient(baseURL: URL(string: "https://example.com")!)
let remoteRunning = await remote.isRunning()
check(!remoteRunning, "endpoint remoto não recebe requisição de disponibilidade")

let dead = OllamaClient(baseURL: URL(string: "http://127.0.0.1:9")!)
let deadRunning = await dead.isRunning()
check(!deadRunning, "cliente em porta fechada: isRunning() é falso")
do {
    _ = try await dead.embed(model: "bge-m3", inputs: ["a"])
    fatalError("Falhou: embed em porta fechada deveria lançar")
} catch {
    check(error as? OllamaError == .notRunning, "cliente em porta fechada: embed lança .notRunning")
}
do {
    for try await _ in dead.chat(model: "llama3.2:3b", messages: [OllamaMessage(role: "user", content: "oi")]) {}
    fatalError("Falhou: chat em porta fechada deveria lançar")
} catch {
    check(error as? OllamaError == .notRunning, "cliente em porta fechada: chat lança .notRunning")
}

// MARK: Live

let client = OllamaClient()
guard await client.isRunning() else {
    print("SKIP: Ollama não está em execução; verificações ao vivo ignoradas (inicie com `ollama serve`)")
    exit(0)
}
let available = try await client.models()
check(!available.isEmpty, "models() lista os modelos instalados")
guard OllamaClient.hasModel("bge-m3", in: available), OllamaClient.hasModel("llama3.2:3b", in: available) else {
    print("SKIP: modelos bge-m3 e llama3.2:3b não instalados; verificações ao vivo ignoradas")
    exit(0)
}
let clock = ContinuousClock()

let three = try await client.embed(model: "bge-m3", inputs: ["Hello world.", "Olá, mundo.", "The warranty lasts two years."])
check(three.count == 3 && three[0].count > 0 && three.allSatisfy { $0.count == three[0].count && abs(norm($0) - 1) < 1e-3 }, "embed devolve 3 vetores normalizados de mesma dimensão (\(three[0].count))")
let noInputs = try await client.embed(model: "bge-m3", inputs: [])
check(noInputs.isEmpty, "embed sem entradas devolve vazio")

let topics = [
    "Total revenue for the fiscal year reached 4.2 million dollars, an increase of twelve percent over the previous year.",
    "Our privacy policy states that personal data is never sold to third parties and is stored encrypted on servers in the European Union.",
    "Orders are shipped within two business days and delivery takes at most ten business days after payment is confirmed.",
    "The product warranty covers manufacturing defects for twenty-four months from the date of purchase.",
    "Employees are entitled to thirty days of paid vacation per year, which must be scheduled with their manager.",
    "The software requires at least 8 GB of memory and runs on macOS 15 or later.",
    "Customer support is available by email from Monday to Friday, between nine in the morning and six in the evening.",
    "The board of directors meets quarterly to review strategy and approve the annual budget."
].enumerated().map { Paragraph(page: $0.offset + 1, original: $0.element) }
let liveChunks = Chunker.chunks(from: topics)
check(liveChunks.count == topics.count, "um chunk por página no documento de teste")
var started = clock.now
let liveVectors = try await client.embed(model: "bge-m3", inputs: liveChunks.map(\.text))
let embedBatch = seconds(clock.now - started)
let question = "Qual é o prazo de entrega?"
started = clock.now
let queryVector = try await client.embed(model: "bge-m3", inputs: [question])[0]
let embedQuery = seconds(clock.now - started)
let liveIndex = VectorIndex(chunks: liveChunks, vectors: liveVectors)
let hits = liveIndex.search(queryVector: queryVector, queryText: question)
check(hits.first?.chunk.text.contains("shipped") == true, "recuperação multilíngue: pergunta em português encontra o trecho de entrega em inglês")
check(hits.first.map { $0.score > 0.4 } == true && zip(hits, hits.dropFirst()).allSatisfy { $0.score >= $1.score }, "resultados densos em ordem decrescente de cosseno")
print(String(format: "INFO: embed de %d chunks em %.3f s; embed da pergunta em %.3f s; cosseno do melhor trecho %.3f", liveChunks.count, embedBatch, embedQuery, hits[0].score))

var answer = ""
var deltas = 0
var firstToken: Double?
started = clock.now
for try await delta in client.chat(model: "llama3.2:3b", messages: RAGPrompt.messages(question: question, sources: hits, history: []), temperature: 0) {
    if firstToken == nil { firstToken = seconds(clock.now - started) }
    deltas += 1
    answer += delta
}
let chatTotal = seconds(clock.now - started)
print("INFO: resposta: \(answer.replacingOccurrences(of: "\n", with: " "))")
print(String(format: "INFO: chat com %d deltas; primeiro token em %.3f s; total %.3f s", deltas, firstToken ?? -1, chatTotal))
check(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && deltas > 1, "chat em streaming produz resposta em mais de um delta")
let cited = RAGPrompt.citations(in: answer, sourceCount: hits.count)
check(!cited.isEmpty, "resposta cita as fontes \(cited)")
check(cited.contains(1) && (answer.contains("dez") || answer.contains("10")), "resposta usa o trecho de entrega e responde em português")

let streaming = Task { () -> Int in
    var received = 0
    let essay = [OllamaMessage(role: "user", content: "Escreva um texto de 800 palavras sobre a história da navegação.")]
    for try await _ in client.chat(model: "llama3.2:3b", messages: essay) {
        received += 1
        if received == 5 { withUnsafeCurrentTask { $0?.cancel() } }
    }
    return received
}
started = clock.now
let received = (try? await streaming.value) ?? -1
let afterSelfCancel = seconds(clock.now - started)
check(received >= 5 && received < 200, "cancelar a tarefa consumidora encerra o stream de chat (\(received) deltas)")

let gate = AsyncStream<Void>.makeStream()
let external = Task {
    var received = 0
    for try await _ in client.chat(model: "llama3.2:3b", messages: [OllamaMessage(role: "user", content: "Escreva um texto de 800 palavras sobre a história da aviação.")]) {
        received += 1
        if received == 3 { gate.continuation.yield() }
    }
    return received
}
for await _ in gate.stream { break }
started = clock.now
external.cancel()
let partial = (try? await external.value) ?? -1
let cancelLatency = seconds(clock.now - started)
check(cancelLatency < 3 && partial < 200, "cancelamento externo no meio do chat retorna rápido")
print(String(format: "INFO: cancelamento externo retornou em %.3f s (%d deltas); auto-cancelamento levou %.3f s no total", cancelLatency, partial, afterSelfCancel))
started = clock.now
_ = try await client.embed(model: "bge-m3", inputs: ["ping"])
check(seconds(clock.now - started) < 10, "servidor continua responsivo depois do cancelamento")

do {
    _ = try await client.embed(model: "modelo-inexistente-xyz", inputs: ["a"])
    fatalError("Falhou: embed com modelo inexistente deveria lançar")
} catch {
    check(error as? OllamaError == .modelMissing("modelo-inexistente-xyz"), "embed com modelo inexistente lança .modelMissing")
}
do {
    for try await _ in client.chat(model: "modelo-inexistente-xyz", messages: [OllamaMessage(role: "user", content: "oi")]) {}
    fatalError("Falhou: chat com modelo inexistente deveria lançar")
} catch {
    check(error as? OllamaError == .modelMissing("modelo-inexistente-xyz"), "chat com modelo inexistente lança .modelMissing")
}
var pullProgress: [Double] = []
for try await value in client.pull(model: "bge-m3") { pullProgress.append(value) }
check(pullProgress.last == 1 && pullProgress == pullProgress.sorted() && pullProgress.allSatisfy { (0...1).contains($0) }, "pull de modelo já instalado termina em 1 com progresso crescente")
print("Todas as verificações do RAG passaram.")

// Regression: many chunks sharing one word with the question must not push out the best semantic match.
do {
    var texts = (0..<40).map { "Unrelated passage number \($0) about something else entirely." }
    for row in 10..<18 { texts[row] = "The total for item \(row) is listed here, total again." }
    texts[0] = "Sales grew strongly in the northern region last year."
    let crowd = (0..<40).map { Chunk(id: $0, page: 1, paragraphs: $0..<($0 + 1), text: texts[$0]) }
    // Chunk 0 points at the query; the "total" chunks are the next closest, the rest further away.
    let vectors: [[Float]] = (0..<40).map { row in
        let c: Float = row == 0 ? 1 : (10..<18).contains(row) ? 0.6 - Float(row) * 0.01 : 0.3
        return [c, (1 - c * c).squareRoot()]
    }
    let hits = VectorIndex(chunks: crowd, vectors: vectors).search(queryVector: [1, 0], queryText: "qual foi o total de vendas", limit: 6)
    check(hits.count == 6 && hits.contains { $0.chunk.id == 0 }, "o melhor trecho semântico continua entre os enviados ao modelo mesmo com oito acertos de palavra")
    check(hits.contains { (10..<18).contains($0.chunk.id) }, "acertos de palavra continuam participando do resultado")
}
