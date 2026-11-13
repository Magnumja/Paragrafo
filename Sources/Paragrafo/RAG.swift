import Foundation
import Accelerate

struct Chunk: Identifiable, Sendable, Equatable {
    let id: Int
    let page: Int
    let paragraphs: Range<Int>
    let text: String
}

enum Chunker {
    /// Groups consecutive paragraphs of the SAME page until ~targetLength characters; never exceeds maxLength unless a single
    /// paragraph is longer, in which case that paragraph is split on sentence boundaries into several chunks that all carry the same one-paragraph range.
    /// Paragraphs without any letters are attached to a neighbour, never a chunk on their own unless nothing else exists on the page.
    /// Every paragraph index is covered by at least one chunk, in order.
    static func chunks(from paragraphs: [Paragraph], targetLength: Int = 900, maxLength: Int = 1600) -> [Chunk] {
        let maxLength = max(1, maxLength)
        let targetLength = min(max(1, targetLength), maxLength)
        var drafts: [Draft] = []
        var index = 0
        while index < paragraphs.count {
            let page = paragraphs[index].page
            let pageStart = drafts.count
            var current: Draft?
            while index < paragraphs.count, paragraphs[index].page == page {
                let text = paragraphs[index].original.trimmingCharacters(in: .whitespacesAndNewlines)
                let length = text.count
                let letters = text.contains(where: \.isLetter)
                defer { index += 1 }
                if length > maxLength {
                    var pieces = split(text, targetLength: targetLength, maxLength: maxLength)
                    var start = index
                    if let pending = current {
                        // A letterless run right before the long paragraph rides on its first piece when it fits.
                        if !pending.letters, pending.length + 1 + pieces[0].count <= maxLength {
                            pieces[0] = pending.text + "\n" + pieces[0]
                            start = pending.start
                        } else {
                            drafts.append(pending)
                        }
                        current = nil
                    }
                    for (offset, piece) in pieces.enumerated() {
                        drafts.append(Draft(page: page, start: offset == 0 ? start : index, end: index + 1, text: piece, length: piece.count, letters: true))
                    }
                    continue
                }
                guard var open = current else {
                    current = Draft(page: page, start: index, end: index + 1, text: text, length: length, letters: letters)
                    continue
                }
                let joined = open.length + (open.text.isEmpty || text.isEmpty ? 0 : 1) + length
                if joined <= maxLength, open.length < targetLength || !letters || !open.letters {
                    if !open.text.isEmpty, !text.isEmpty { open.text += "\n" }
                    open.text += text
                    open.length = joined
                    open.end = index + 1
                    open.letters = open.letters || letters
                    current = open
                } else {
                    drafts.append(open)
                    current = Draft(page: page, start: index, end: index + 1, text: text, length: length, letters: letters)
                }
            }
            if let last = current {
                // A trailing letterless run joins the previous chunk of this page when it fits.
                if !last.letters, drafts.count > pageStart, drafts[drafts.count - 1].length + 1 + last.length <= maxLength {
                    var previous = drafts[drafts.count - 1]
                    if !last.text.isEmpty {
                        previous.text += "\n" + last.text
                        previous.length += 1 + last.length
                    }
                    previous.end = last.end
                    drafts[drafts.count - 1] = previous
                } else {
                    drafts.append(last)
                }
            }
        }
        return drafts.enumerated().map { Chunk(id: $0.offset, page: $0.element.page, paragraphs: $0.element.start..<$0.element.end, text: $0.element.text) }
    }

    private struct Draft {
        let page: Int
        var start: Int
        var end: Int
        var text: String
        var length: Int
        var letters: Bool
    }

    /// Packs sentences up to ~targetLength; every piece is at most maxLength characters.
    private static func split(_ text: String, targetLength: Int, maxLength: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        var currentLength = 0
        for sentence in sentences(in: text).flatMap({ hardSplit($0, maxLength: maxLength) }) {
            let length = sentence.count
            if currentLength > 0, currentLength + 1 + length > targetLength {
                pieces.append(current)
                current = ""
                currentLength = 0
            }
            if currentLength > 0 { current += " "; currentLength += 1 }
            current += sentence
            currentLength += length
        }
        if currentLength > 0 {
            // Avoid a stub at the end when it fits in the previous piece.
            if let previous = pieces.last, currentLength < targetLength / 4, previous.count + 1 + currentLength <= maxLength {
                pieces[pieces.count - 1] = previous + " " + current
            } else {
                pieces.append(current)
            }
        }
        return pieces.isEmpty ? [text] : pieces
    }

    private static let terminators: Set<Character> = [".", "!", "?", "…", ";", "。", "！", "？", "；"]
    private static let wideTerminators: Set<Character> = ["。", "！", "？", "；"]

    private static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
            current = ""
        }
        for character in text {
            if let previous, !current.isEmpty,
               character.isNewline || wideTerminators.contains(previous) && !terminators.contains(character)
                || character.isWhitespace && terminators.contains(previous) {
                flush()
            }
            current.append(character)
            previous = character
        }
        flush()
        return result
    }

    /// Breaks a sentence longer than maxLength at word boundaries (or mid-word when there is no whitespace).
    private static func hardSplit(_ sentence: String, maxLength: Int) -> [String] {
        guard sentence.count > maxLength else { return [sentence] }
        var result: [String] = []
        var current = ""
        var currentLength = 0
        for word in sentence.split(whereSeparator: \.isWhitespace) {
            var word = Substring(word)
            while true {
                let length = word.count
                if currentLength > 0, currentLength + 1 + length <= maxLength {
                    current += " " + word
                    currentLength += 1 + length
                    break
                }
                if currentLength > 0 {
                    result.append(current)
                    current = ""
                    currentLength = 0
                }
                if length <= maxLength {
                    current = String(word)
                    currentLength = length
                    break
                }
                result.append(String(word.prefix(maxLength)))
                word = word.dropFirst(maxLength)
            }
        }
        if currentLength > 0 { result.append(current) }
        return result
    }
}

struct Retrieved: Sendable, Equatable {
    let chunk: Chunk
    let score: Float
}

struct VectorIndex: Sendable {
    let chunks: [Chunk]
    let vectors: [[Float]]

    private let dimension: Int
    private let matrix: [Float]              // chunks.count rows × dimension, row-major
    private let termCounts: [[String: Int]]  // lexical corpus of each chunk's own text
    private let lengths: [Int]

    init(chunks: [Chunk], vectors: [[Float]]) {
        self.chunks = chunks
        self.vectors = vectors
        let dimension = vectors.first(where: { !$0.isEmpty })?.count ?? 0
        var matrix = [Float](repeating: 0, count: chunks.count * dimension)
        // Rows without a usable vector stay zero and are only reachable lexically.
        for row in 0..<min(chunks.count, vectors.count) where vectors[row].count == dimension && dimension > 0 {
            matrix.replaceSubrange(row * dimension..<(row + 1) * dimension, with: vectors[row])
        }
        self.dimension = dimension
        self.matrix = matrix
        let tokens = chunks.map { Lexical.tokens($0.text) }
        termCounts = tokens.map(Lexical.counts)
        lengths = tokens.map(\.count)
    }

    /// Hybrid retrieval: dense cosine (vDSP dot products) + BM25 over tokens (lowercased, diacritic-folded, tokens of length>=2, light stopword list for pt/en/es),
    /// fused with Reciprocal Rank Fusion (k=60). Lexical ranks only count for chunks with BM25 > 0. `extraText[chunkID]` (e.g. the translation of the chunk) is appended to the lexical corpus for that chunk.
    /// Results sorted best-first, at most `limit`, dropping dense hits with cosine < minimumScore unless they also matched lexically.
    func search(queryVector: [Float], queryText: String, extraText: [Int: String] = [:], limit: Int = 6, minimumScore: Float = 0.25) -> [Retrieved] {
        let count = chunks.count
        guard count > 0, limit > 0 else { return [] }

        let cosine = cosines(queryVector)
        let lexical = bm25(queryText, extraText: extraText)

        // Plain RRF lets any chunk sharing one word with the question outrank the best semantic match, which hurts
        // most when the question and the document are in different languages. So: only the top of each list counts,
        // weak word matches are ignored, the lexical list weighs half, and the best semantic matches always keep a seat.
        var fused = [Float](repeating: 0, count: count)
        var candidate = [Bool](repeating: false, count: count)
        let k: Float = 60, depth = 30, lexicalWeight: Float = 0.5
        var pinned: [Int] = []
        if let cosine {
            let order = (0..<count).sorted { cosine[$0] != cosine[$1] ? cosine[$0] > cosine[$1] : $0 < $1 }
            for (rank, row) in order.enumerated() where cosine[row] >= minimumScore {
                candidate[row] = true
                if rank < depth { fused[row] += 1 / (k + Float(rank + 1)) }
                if rank < max(1, limit / 2) { pinned.append(row) }
            }
        }
        let matched = (0..<count).filter { lexical[$0] > 0 }.sorted { lexical[$0] != lexical[$1] ? lexical[$0] > lexical[$1] : $0 < $1 }
        let strongest = matched.first.map { lexical[$0] } ?? 0
        for (rank, row) in matched.prefix(depth).enumerated() where lexical[row] >= 0.4 * strongest {
            fused[row] += lexicalWeight / (k + Float(rank + 1))
            candidate[row] = true
        }

        let better: (Int, Int) -> Bool = {
            if fused[$0] != fused[$1] { return fused[$0] > fused[$1] }
            let a = cosine?[$0] ?? 0, b = cosine?[$1] ?? 0
            return a != b ? a > b : $0 < $1
        }
        var chosen = Array((0..<count).filter { candidate[$0] }.sorted(by: better).prefix(limit))
        for row in pinned where !chosen.contains(row) {
            if let weakest = chosen.lastIndex(where: { !pinned.contains($0) }) { chosen[weakest] = row }
        }
        return chosen.sorted(by: better).map { Retrieved(chunk: chunks[$0], score: cosine?[$0] ?? 0) }
    }

    /// Cosine of every row against the query, or nil when there is no comparable query vector.
    private func cosines(_ query: [Float]) -> [Float]? {
        guard dimension > 0, query.count == dimension, query.allSatisfy(\.isFinite) else { return nil }
        let norm = vDSP.sumOfSquares(query).squareRoot()
        guard norm > 0 else { return nil }
        let unit = vDSP.divide(query, norm)
        var result = [Float](repeating: 0, count: chunks.count)
        matrix.withUnsafeBufferPointer { rows in
            unit.withUnsafeBufferPointer { column in
                result.withUnsafeMutableBufferPointer { output in
                    vDSP_mmul(rows.baseAddress!, 1, column.baseAddress!, 1, output.baseAddress!, 1,
                              vDSP_Length(chunks.count), 1, vDSP_Length(dimension))
                }
            }
        }
        return result
    }

    private func bm25(_ query: String, extraText: [Int: String]) -> [Float] {
        let count = chunks.count
        var scores = [Float](repeating: 0, count: count)
        let terms = Set(Lexical.tokens(query))
        guard !terms.isEmpty else { return scores }

        var extraCounts: [Int: [String: Int]] = [:]
        var lengths = lengths
        for (index, chunk) in chunks.enumerated() {
            guard let extra = extraText[chunk.id], !extra.isEmpty else { continue }
            let tokens = Lexical.tokens(extra)
            extraCounts[index] = Lexical.counts(tokens)
            lengths[index] += tokens.count
        }
        let average = max(Float(lengths.reduce(0, +)) / Float(count), 1)
        let k1: Float = 1.2, b: Float = 0.75
        for term in terms {
            var frequencies: [(row: Int, value: Float)] = []
            for row in 0..<count {
                let frequency = (termCounts[row][term] ?? 0) + (extraCounts[row]?[term] ?? 0)
                if frequency > 0 { frequencies.append((row, Float(frequency))) }
            }
            guard !frequencies.isEmpty else { continue }
            let df = Float(frequencies.count)
            let idf = log(1 + (Float(count) - df + 0.5) / (df + 0.5))
            for (row, frequency) in frequencies {
                let normalization = k1 * (1 - b + b * Float(lengths[row]) / average)
                scores[row] += idf * frequency * (k1 + 1) / (frequency + normalization)
            }
        }
        return scores
    }
}

private enum Lexical {
    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap { $0.count >= 2 && !stopwords.contains(String($0)) ? String($0) : nil }
    }

    static func counts(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    // Already diacritic-folded.
    static let stopwords: Set<String> = [
        // pt
        "de", "da", "do", "das", "dos", "em", "no", "na", "nos", "nas", "um", "uma", "uns", "umas", "os", "as", "ao", "aos",
        "que", "qual", "quais", "quando", "onde", "como", "por", "para", "com", "sem", "se", "ou", "mas", "nao", "sim",
        "ser", "sao", "foi", "era", "esta", "estao", "este", "esse", "essa", "isso", "isto", "ele", "ela", "eles", "elas",
        "seu", "sua", "seus", "suas", "meu", "minha", "mais", "muito", "tambem", "ja", "sobre", "entre", "ate", "pelo", "pela",
        "tem", "ha", "quem", "porque",
        // en
        "the", "an", "and", "or", "of", "to", "in", "on", "at", "is", "are", "was", "were", "be", "been", "it", "its",
        "this", "that", "these", "those", "for", "with", "by", "from", "as", "what", "which", "who", "when", "where", "how",
        "why", "do", "does", "did", "not", "but", "if", "has", "have", "had", "can", "will", "about", "there", "their", "they",
        // es
        "el", "la", "los", "las", "un", "una", "unos", "unas", "del", "al", "en", "es", "son", "fue", "que", "cual", "cuales",
        "cuando", "donde", "por", "con", "sin", "su", "sus", "lo", "le", "les", "pero", "si", "mas", "muy", "tambien", "ya",
        "sobre", "entre", "hasta", "esta", "este", "esto", "ese", "esa", "hay", "quien", "porque"
    ]
}

enum RAGPrompt {
    /// System prompt in Portuguese instructing: answer ONLY from the numbered excerpts; answer in the language of the question; cite sources inline as [1], [2]
    /// right after the sentence they support; if the excerpts do not contain the answer, say so plainly; be concise; never invent page numbers.
    static let system = """
    Você é o assistente de leitura do Parágrafo e responde a perguntas sobre um documento.
    Regras:
    1. Use SOMENTE as informações dos trechos numerados fornecidos na mensagem do usuário. Não use conhecimento externo.
    2. Responda no mesmo idioma da pergunta, mesmo que os trechos estejam em outro idioma.
    3. Cite as fontes no próprio texto, logo após a frase que elas sustentam, usando o número do trecho entre colchetes: [1], [2]. Toda afirmação tirada do documento precisa de citação.
    4. Se os trechos não contiverem a resposta, diga claramente que o documento não traz essa informação. Não tente adivinhar.
    5. Seja conciso: primeiro a resposta direta, depois, se necessário, um detalhe curto de apoio.
    6. Nunca invente números de página, trechos ou citações. Cite apenas números de trechos que existem.
    """

    /// [system] + up to the last 4 history messages + a user message containing the numbered excerpts ("[1] (página 3)\n<text>") followed by the question.
    static func messages(question: String, sources: [Retrieved], history: [OllamaMessage]) -> [OllamaMessage] {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        var content: String
        if sources.isEmpty {
            content = "Trechos do documento: nenhum trecho relevante foi encontrado.\n\n"
        } else {
            content = "Trechos do documento:\n\n"
            for (offset, source) in sources.enumerated() {
                content += "[\(offset + 1)] (página \(source.chunk.page))\n\(source.chunk.text)\n\n"
            }
        }
        content += "Pergunta: \(question)\n\n"
        content += sources.isEmpty
            ? "Responda no idioma da pergunta dizendo que o documento não traz essa informação."
            : "Responda no idioma da pergunta, usando somente os trechos acima, e cite o número do trecho entre colchetes, por exemplo [1], logo após cada frase."
        return [OllamaMessage(role: "system", content: system)] + history.suffix(4) + [OllamaMessage(role: "user", content: content)]
    }

    /// 1-based source numbers actually cited in the answer text ("[2]", "[1, 3]", "[1][2]"), unique, ascending, only those in 1...sourceCount.
    static func citations(in answer: String, sourceCount: Int) -> [Int] {
        guard sourceCount > 0 else { return [] }
        var found = Set<Int>()
        var inside: String?
        for character in answer {
            if character == "[" {
                inside = ""
            } else if character == "]" {
                if let body = inside { numbers(in: body).forEach { found.insert($0) } }
                inside = nil
            } else if inside != nil {
                // Only digits and list separators may appear inside a citation; anything else is ordinary bracketed text.
                if character.isASCII, character.isNumber || character == "," || character == ";" || character == " " || character == "-" {
                    inside?.append(character)
                } else {
                    inside = nil
                }
            }
        }
        return found.filter { (1...sourceCount).contains($0) }.sorted()
    }

    private static func numbers(in body: String) -> [Int] {
        var result: [Int] = []
        for part in body.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }) {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
            if bounds.count == 1, let value = bounds[0] {
                result.append(value)
            } else if bounds.count == 2, let low = bounds[0], let high = bounds[1], low <= high, high - low <= 50 {
                result.append(contentsOf: low...high)
            } else {
                return []
            }
        }
        return result
    }
}
