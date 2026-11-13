import Foundation
import CryptoKit

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    enum Stage: Equatable { case searching, reading(Int, Int), writing, done, failed }
    let id = UUID()
    var role: Role
    var text: String
    var sources: [Retrieved] = []
    var cited: [Int] = []
    var stage: Stage = .done
    var isOverview = false
    var note: String?
}

/// Answers questions about the open document with a local Llama model, grounded in passages retrieved from it.
@MainActor
final class DocumentAssistant: ObservableObject {
    enum Availability: Equatable { case unknown, checking, ready, serverOff, missing([String]), pulling(String, Double) }
    enum IndexState: Equatable { case empty, indexing(Int, Int), ready, failed(String) }

    static let embeddingModel = "bge-m3"
    static let defaultChatModel = "llama3.2:3b"
    static let overviewQuestion = "Faça uma síntese geral deste documento."

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var indexState: IndexState = .empty
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var chatModels: [String] = []
    @Published private(set) var busy = false
    @Published var chatModel = UserDefaults.standard.string(forKey: "chatModel") ?? DocumentAssistant.defaultChatModel {
        didSet { UserDefaults.standard.set(chatModel, forKey: "chatModel") }
    }

    /// Documents up to this many characters are synthesized in one pass; longer ones part by part.
    var singlePassLimit = 14000
    private let client = OllamaClient()
    private(set) var fingerprint = ""
    private var chunks: [Chunk] = []
    private var paragraphs: [Paragraph] = []
    private var index: VectorIndex?
    private var indexTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var generation = 0
    private var checking: Task<Void, Never>?

    var hasDocument: Bool { !chunks.isEmpty }

    /// Point the assistant at a new document. Nothing is computed until `prepare()`.
    func attach(paragraphs: [Paragraph], fingerprint: String) {
        indexTask?.cancel()
        answerTask?.cancel()
        indexTask = nil
        answerTask = nil
        generation += 1
        busy = false
        messages = []
        index = nil
        indexState = .empty
        self.fingerprint = fingerprint
        self.paragraphs = paragraphs
        chunks = Chunker.chunks(from: paragraphs)
    }

    /// Makes sure Ollama and the models are there, then builds (or restores) the search index.
    func prepare() async {
        guard hasDocument else { return }
        if availability != .ready { await checkAvailability() }
        guard availability == .ready, index == nil, indexTask == nil else { return }
        startIndexing()
    }

    /// One check at a time, in its own task: a view that goes away mid-check must not leave a wrong answer behind.
    func checkAvailability(launch: Bool = true) async {
        if let checking { await checking.value; return }
        let task = Task { await performCheck(launch: launch) }
        checking = task
        await task.value
        checking = nil
    }

    private func performCheck(launch: Bool) async {
        if case .pulling = availability { return }
        availability = .checking
        var running = await client.isRunning()
        if !running, launch, await Task.detached(operation: { OllamaClient.launchServer() }).value {
            for _ in 0..<25 where !running {
                try? await Task.sleep(for: .milliseconds(400))
                running = await client.isRunning()
            }
        }
        guard running else { availability = .serverOff; return }
        // A failed listing says nothing about which models exist; do not touch the saved choice.
        guard let installed = try? await client.models() else { availability = .serverOff; return }
        chatModels = installed.filter { name in !["embed", "bge", "minilm", "e5"].contains { name.lowercased().contains($0) } }.sorted()
        if !OllamaClient.hasModel(chatModel, in: chatModels) {
            chatModel = chatModels.first { $0.lowercased().contains("llama") } ?? chatModels.first ?? Self.defaultChatModel
        }
        var missing: [String] = []
        if !OllamaClient.hasModel(Self.embeddingModel, in: installed) { missing.append(Self.embeddingModel) }
        if chatModels.isEmpty { missing.append(Self.defaultChatModel) }
        availability = missing.isEmpty ? .ready : .missing(missing)
    }

    func download(_ models: [String]) {
        guard case .missing = availability else { return }
        Task {
            do {
                for model in models {
                    availability = .pulling(model, 0)
                    for try await progress in client.pull(model: model) { availability = .pulling(model, progress) }
                }
                availability = .unknown
                await prepare()
            } catch {
                availability = .unknown
                await checkAvailability(launch: false)
                indexState = .failed(error.localizedDescription)
            }
        }
    }

    private func startIndexing() {
        let fingerprint = fingerprint, chunks = chunks, run = generation
        indexTask = Task {
            defer { if generation == run { indexTask = nil } }
            // Vectors are only reused for exactly the text they were computed from.
            let digest = SHA256.hash(data: Data(chunks.map(\.text).joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
            let key = "\(Self.embeddingModel)|chunker-1|\(chunks.count)|\(digest)"
            if let saved = Library.load(fingerprint), saved.indexKey == key, let dimension = saved.dimension,
               let vectors = Library.loadVectors(fingerprint: fingerprint, count: chunks.count, dimension: dimension) {
                let restored = await Task.detached { VectorIndex(chunks: chunks, vectors: vectors) }.value
                guard generation == run else { return }
                index = restored
                indexState = .ready
                return
            }
            indexState = .indexing(0, chunks.count)
            var vectors: [[Float]] = []
            do {
                for start in stride(from: 0, to: chunks.count, by: 16) {
                    try Task.checkCancellation()
                    let batch = chunks[start..<min(start + 16, chunks.count)].map(\.text)
                    let embedded = try await client.embed(model: Self.embeddingModel, inputs: batch)
                    guard generation == run else { return }
                    guard embedded.count == batch.count else { throw OllamaError.server("O modelo de busca devolveu uma resposta incompleta.") }
                    vectors += embedded
                    indexState = .indexing(vectors.count, chunks.count)
                }
                let built = await Task.detached { [vectors] in VectorIndex(chunks: chunks, vectors: vectors) }.value
                guard generation == run else { return }
                index = built
                indexState = .ready
                Library.saveVectors(vectors, fingerprint: fingerprint)
                Library.update(fingerprint) { $0.indexKey = key; $0.dimension = vectors.first?.count }
            } catch {
                guard generation == run else { return }
                if Task.isCancelled { indexState = .empty; return }
                if error as? OllamaError == .notRunning { availability = .serverOff }
                indexState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Questions

    /// `overview` forces or forbids the whole-document synthesis; nil decides from the wording.
    func ask(_ question: String, translations: [String] = [], overview: Bool? = nil) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, hasDocument, !question.isEmpty else { return }
        // Earlier answers go back to the model without their citation numbers (the passages are renumbered every
        // turn) and without whole-document syntheses, which would crowd out the passages.
        let history = messages.filter { $0.stage == .done && !$0.text.isEmpty && !$0.isOverview }.suffix(4).map {
            OllamaMessage(role: $0.role == .user ? "user" : "assistant",
                          content: String($0.text.replacing(#/\s*\[\d+(?:\s*[,;\-]\s*\d+)*\]/#, with: "").prefix(600)))
        }
        let previous = messages.last { $0.role == .user && !Self.wantsOverview($0.text) }?.text
        messages.append(ChatMessage(role: .user, text: question))
        let overview = overview ?? Self.wantsOverview(question)
        let reply = ChatMessage(role: .assistant, text: "", stage: .searching, isOverview: overview)
        messages.append(reply)
        run(reply.id) {
            if overview {
                try await self.overview(reply.id, question: question, force: false)
            } else {
                try await self.answer(reply.id, question: question, previous: previous, history: history, translations: translations)
            }
        }
    }

    func summarize() { ask(Self.overviewQuestion) }

    /// Discards the saved synthesis and writes a new one in place.
    func regenerate(_ id: ChatMessage.ID) {
        guard !busy, let message = messages.first(where: { $0.id == id }), message.isOverview else { return }
        update(id) { $0.text = ""; $0.note = nil; $0.sources = []; $0.cited = []; $0.stage = .searching }
        run(id) { try await self.overview(id, question: Self.overviewQuestion, force: true) }
    }

    func stop() { answerTask?.cancel() }

    func clear() {
        guard !busy else { return }
        messages = []
    }

    private func run(_ id: ChatMessage.ID, _ work: @escaping @MainActor () async throws -> Void) {
        busy = true
        let run = generation
        answerTask = Task {
            do {
                try await work()
            } catch {
                guard generation == run else { return }
                if Task.isCancelled {
                    update(id) { if $0.text.isEmpty { $0.text = "Resposta interrompida." }; $0.stage = .done }
                } else {
                    if error as? OllamaError == .notRunning { availability = .serverOff }
                    update(id) { $0.text = error.localizedDescription; $0.stage = .failed }
                }
            }
            guard generation == run else { return }
            busy = false
            answerTask = nil
        }
    }

    private func ensureIndex() async throws -> VectorIndex {
        if index == nil {
            await prepare()
            // Poll instead of awaiting the indexing task so that "stop" takes effect at once.
            while indexTask != nil {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(60))
            }
        }
        try Task.checkCancellation()
        if let index { return index }
        switch (availability, indexState) {
        case (.serverOff, _): throw OllamaError.notRunning
        case (.missing(let models), _): throw OllamaError.modelMissing(models.joined(separator: ", "))
        case (_, .failed(let reason)): throw OllamaError.server(reason)
        default: throw OllamaError.server("O índice do documento ainda não está pronto. Tente novamente em instantes.")
        }
    }

    private func answer(_ id: ChatMessage.ID, question: String, previous: String?, history: [OllamaMessage], translations: [String]) async throws {
        let index = try await ensureIndex()
        // A short follow-up ("e na Europa?") only makes sense next to the question before it.
        let query = Self.isFollowUp(question) ? [previous, question].compactMap { $0 }.joined(separator: " ") : question
        guard let vector = try await client.embed(model: Self.embeddingModel, inputs: [query]).first else {
            throw OllamaError.server("Não foi possível interpretar a pergunta.")
        }
        var extra: [Int: String] = [:]
        if !translations.isEmpty {
            for chunk in index.chunks {
                let text = chunk.paragraphs.compactMap { translations.indices.contains($0) ? translations[$0] : nil }.joined(separator: " ")
                if !text.isEmpty { extra[chunk.id] = text }
            }
        }
        let lexical = extra
        // Tokenizing the corpus is synchronous; keep it off the main actor for long documents.
        let sources = await Task.detached { index.search(queryVector: vector, queryText: query, extraText: lexical, limit: 6) }.value
        try Task.checkCancellation()
        guard !sources.isEmpty else {
            update(id) { $0.text = "Não encontrei nenhum trecho do documento relacionado a essa pergunta. Tente reformular ou usar termos que aparecem no texto."; $0.stage = .done }
            return
        }
        update(id) { $0.sources = sources; $0.stage = .writing }
        let text = try await stream(id, messages: RAGPrompt.messages(question: question, sources: sources, history: history))
        let cited = RAGPrompt.citations(in: text, sourceCount: sources.count)
        update(id) {
            $0.text = text
            $0.cited = cited
            if cited.isEmpty { $0.note = "A resposta não citou um trecho específico. Confira nos trechos consultados." }
            $0.stage = .done
        }
    }

    /// Whole-document synthesis. Short documents go to the model at once; long ones are read in parts and then combined.
    /// Either way the model writes from numbered passages, so every point links back to where it came from.
    private func overview(_ id: ChatMessage.ID, question: String, force: Bool) async throws {
        if !force, question == Self.overviewQuestion, let saved = Library.load(fingerprint), let text = saved.summary, !text.isEmpty {
            let sources = (saved.summarySources ?? []).enumerated().map { position, source in
                Retrieved(chunk: Chunk(id: position, page: source.page, paragraphs: source.paragraph..<(source.paragraph + 1), text: source.text), score: 0)
            }
            update(id) {
                $0.text = text
                $0.sources = sources
                $0.cited = RAGPrompt.citations(in: text, sourceCount: sources.count)
                $0.note = "Síntese salva deste documento."
                $0.stage = .done
            }
            return
        }
        if availability != .ready { await checkAvailability() }
        if availability == .serverOff { throw OllamaError.notRunning }
        if chatModels.isEmpty { throw OllamaError.modelMissing(Self.defaultChatModel) }

        var note: String?
        var sources: [Retrieved]
        if chunks.reduce(0, { $0 + $1.text.count }) <= singlePassLimit {
            // Smaller passages than the search index uses, so each point has its own passage to cite.
            let fine = Chunker.chunks(from: paragraphs, targetLength: 320, maxLength: 700)
            sources = (fine.count <= 40 ? fine : chunks).map { Retrieved(chunk: $0, score: 0) }
        } else {
            var parts: [(first: Chunk, last: Int, text: String)] = []
            for chunk in chunks {
                let labelled = "[página \(chunk.page)]\n\(chunk.text)"
                if let current = parts.last, current.text.count + labelled.count <= singlePassLimit / 2 {
                    parts[parts.count - 1] = (current.first, chunk.page, current.text + "\n\n" + labelled)
                } else {
                    parts.append((chunk, chunk.page, labelled))
                }
            }
            let limit = 24
            if parts.count > limit {
                let total = parts.count
                parts = (0..<limit).map { parts[$0 * (total - 1) / (limit - 1)] }
                note = "Documento longo: síntese feita a partir de \(limit) de \(total) partes, distribuídas do início ao fim."
            }
            let map = "Você resume um trecho de um documento. Escreva no mesmo idioma desta solicitação: «\(question)». Escreva de 3 a 5 frases objetivas com os fatos, números e conclusões do trecho. Não invente nada."
            sources = []
            for (step, part) in parts.enumerated() {
                try Task.checkCancellation()
                update(id) { $0.stage = .reading(step + 1, parts.count) }
                var text = ""
                for try await delta in client.chat(model: chatModel, messages: [OllamaMessage(role: "system", content: map), OllamaMessage(role: "user", content: part.text)], temperature: 0) {
                    text += delta
                }
                try Task.checkCancellation()
                let pages = "Resumo automático " + (part.first.page == part.last ? "da página \(part.last): " : "das páginas \(part.first.page)–\(part.last): ")
                sources.append(Retrieved(chunk: Chunk(id: step, page: part.first.page, paragraphs: part.first.paragraphs,
                                                      text: pages + text.trimmingCharacters(in: .whitespacesAndNewlines)), score: 0))
            }
        }
        let shown = sources
        update(id) { $0.sources = shown; $0.stage = .writing }
        let request = "\(question) Escreva primeiro um parágrafo de 2 a 3 frases dizendo do que o documento trata. Depois liste de 4 a 7 pontos principais, um por linha começando com \"- \", cada um com a citação do trecho de onde veio."
        let text = try await stream(id, messages: RAGPrompt.messages(question: request, sources: sources, history: []))
        update(id) {
            $0.text = text
            $0.cited = RAGPrompt.citations(in: text, sourceCount: shown.count)
            $0.note = note
            $0.stage = .done
        }
        guard !text.isEmpty, question == Self.overviewQuestion else { return }
        Library.update(fingerprint) {
            $0.summary = text
            $0.summarySources = shown.map { SavedSource(page: $0.chunk.page, paragraph: $0.chunk.paragraphs.lowerBound, text: String($0.chunk.text.prefix(400))) }
        }
    }

    /// Streams a reply into a message, refreshing the UI at most ~15 times a second.
    private func stream(_ id: ChatMessage.ID, messages: [OllamaMessage]) async throws -> String {
        var text = ""
        let clock = ContinuousClock()
        var shown = clock.now
        // Temperature 0: the answer should follow the passages, not vary between runs.
        for try await delta in client.chat(model: chatModel, messages: messages, temperature: 0) {
            text += delta
            if clock.now - shown > .milliseconds(66) {
                shown = clock.now
                update(id) { $0.text = text }
            }
        }
        try Task.checkCancellation()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func update(_ id: ChatMessage.ID, _ change: (inout ChatMessage) -> Void) {
        guard let position = messages.lastIndex(where: { $0.id == id }) else { return }
        change(&messages[position])
    }

    /// A request for the whole document ("resuma o documento"), not for one part of it ("resuma a cláusula 5").
    static func wantsOverview(_ question: String) -> Bool {
        let folded = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard folded.count <= 80, !folded.contains(where: \.isNumber),
              folded.firstMatch(of: #/capitulo|secao|pagina|clausula|trecho|paragrafo|parte |artigo |item |tabela|anexo/#) == nil else { return false }
        let words = folded.split(separator: " ").count
        // "Resuma a política de garantia" names a topic; only a bare request or one about the document itself counts.
        let aboutDocument = folded.firstMatch(of: #/documento|texto|pdf|arquivo|relatorio|livro|artigo|contrato inteiro|tudo|document|file/#) != nil
        if folded.firstMatch(of: #/visao geral|overview|do que (se )?trata|sobre o que (e|fala)|pontos principais|principais pontos|main points/#) != nil {
            return aboutDocument || words <= 6
        }
        if folded.firstMatch(of: #/resum|sintes|sintetiz|summar/#) != nil { return aboutDocument || words <= 3 }
        return false
    }

    /// "E na Europa?" depends on the question before it; "Quem assina o contrato?" does not, however short.
    static func isFollowUp(_ question: String) -> Bool {
        let folded = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        return folded.split(separator: " ").count <= 3
            || folded.firstMatch(of: #/^(e |mas |entao |e quanto|quanto a|nesse|nessa|nisso|disso|dele|dela|isso|ele |ela |esse |essa |and |what about)/#) != nil
    }
}
