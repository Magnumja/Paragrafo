import SwiftUI
import PDFKit
import CryptoKit
@preconcurrency import Translation
import UniformTypeIdentifiers

@MainActor
final class ReaderModel: ObservableObject {
    enum Phase { case idle, importing, translating }
    @Published var document = DocumentState()
    @Published var filename = ""
    @Published var target = "pt"
    @Published var source = "auto"
    @Published var detectedSource: String?
    @Published var languages: [Locale.Language] = []
    @Published var selectedPage = 1 {
        didSet { if selectedPage != oldValue { pageForward = selectedPage > oldValue } }
    }
    /// Direction of the last page change, so the reader can slide the new page in from the right side.
    private(set) var pageForward = true
    @Published var phase: Phase = .idle
    @Published var stopping = false
    @Published var status = "Pronto para um novo documento."
    @Published var notice = ""
    @Published var error: String?
    @Published var configuration: TranslationSession.Configuration?
    @Published var importProgress = 0.0
    /// Paragraph being translated right now.
    @Published private(set) var active: Int?
    /// Paragraph the reader was sent to (from an answer's source); `revealToken` changes on every jump.
    @Published private(set) var highlighted: Range<Int>?
    @Published private(set) var revealToken = 0
    @Published private(set) var fingerprint = ""
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var pageCount = 0
    @Published private(set) var recents = Library.recents()
    private var fileURL: URL?
    private var contentKey = ""
    private var importTask: Task<Extracted, Error>?
    private var importID = UUID()
    private var sessionRunning = false
    var busy: Bool { phase != .idle }

    func load(_ url: URL) {
        guard !busy else { return }
        let id = UUID()
        importID = id
        phase = .importing
        stopping = false
        importProgress = 0
        status = "Abrindo \(url.lastPathComponent)…"
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            try PDFExtractor.extract(url: url) { [weak self] page, total in
                Task { @MainActor [weak self] in
                    guard let self, self.importID == id, self.phase == .importing, !self.stopping else { return }
                    self.importProgress = Double(page) / Double(max(total, 1))
                    self.status = "Lendo página \(page) de \(total)…"
                }
            }
        }
        importTask = worker
        Task {
            defer { if importID == id { phase = .idle; importTask = nil; stopping = false } }
            do {
                let result = try await worker.value
                try Task.checkCancellation()
                guard importID == id, !stopping else { status = "Importação cancelada."; return }
                var paragraphs = result.paragraphs
                detectedSource = TranslationInput.detectLanguage(in: paragraphs)
                // Reopening the same file brings back the work already done.
                let saved = Library.load(result.fingerprint)
                var restored = 0
                let key = Self.contentKey(paragraphs)
                if let saved, saved.contentKey == key, saved.translations.count == paragraphs.count {
                    for index in paragraphs.indices { paragraphs[index].translated = saved.translations[index] }
                    restored = saved.translations.lazy.filter { !$0.isEmpty }.count
                    source = saved.source
                    target = saved.target
                } else {
                    source = "auto"
                    // Same file, different extraction: what was saved no longer lines up with the text.
                    if saved != nil { Library.remove(result.fingerprint) }
                }
                contentKey = key
                document = DocumentState(paragraphs)
                selectedPage = document.pages.first ?? 1
                highlighted = nil
                filename = url.lastPathComponent
                fileURL = url
                pageCount = result.pageCount
                pdf = PDFDocument(url: url)
                fingerprint = result.fingerprint
                status = restored > 0 ? "\(restored) de \(document.count) parágrafos já traduzidos foram restaurados."
                    : "\(document.count) parágrafos prontos para traduzir."
                notice = result.ocrPages > 0 ? "OCR usado em \(result.ocrPages) página(s). Confira o texto reconhecido." : ""
                if !result.emptyPages.isEmpty {
                    notice += (notice.isEmpty ? "" : " ") + "Sem texto nas páginas: \(result.emptyPages.map(String.init).joined(separator: ", "))."
                }
                persist()
            } catch is CancellationError {
                status = "Importação cancelada."
            } catch {
                self.error = error.localizedDescription
                status = "Não foi possível importar o PDF."
            }
        }
    }

    func open(_ recent: RecentDocument) {
        let url = URL(fileURLWithPath: recent.path)
        guard FileManager.default.fileExists(atPath: recent.path) else {
            Library.remove(recent.id)
            recents = Library.recents()
            error = "“\(recent.name)” não está mais em \(url.deletingLastPathComponent().path). Abra o arquivo novamente."
            return
        }
        load(url)
    }

    func forget(_ recent: RecentDocument) {
        Library.remove(recent.id)
        recents = Library.recents()
    }

    /// Back to the start screen. The work stays saved.
    func close() {
        guard !busy else { return }
        persist()
        document = DocumentState()
        filename = ""
        fingerprint = ""
        pdf = nil
        fileURL = nil
        highlighted = nil
        notice = ""
        status = "Pronto para um novo documento."
    }

    func stop() {
        stopping = true
        if phase == .importing {
            importTask?.cancel()
            status = "Cancelando após a página atual…"
        } else if !sessionRunning {
            phase = .idle
            stopping = false
            status = "Tradução pausada. Você pode tentar novamente."
        } else {
            status = "Pausando após o parágrafo atual…"
        }
    }

    func choose(source: String) {
        guard !busy, source != self.source else { return }
        self.source = source
        changeTarget()
    }

    func choose(target: String) {
        guard !busy, target != self.target else { return }
        self.target = target
        changeTarget()
    }

    func changeTarget() {
        guard !busy else { return }
        document.clearTranslations()
        status = "Idiomas alterados. Pronto para traduzir."
        persist()
    }

    func startTranslation() {
        guard !busy, !document.isEmpty, document.completed < document.count else { return }
        let origin = source == "auto" ? detectedSource : source
        if let origin, TranslationInput.sameLanguage(origin, target) {
            error = "A origem e o destino são o mesmo idioma. Se o documento está em inglês, escolha Inglês como origem e Português como destino."
            status = "Escolha idiomas diferentes para traduzir."
            return
        }
        if origin == nil && document.paragraphs.contains(where: { TranslationInput.needsTranslation($0.original) }) {
            error = "Não foi possível identificar a língua do documento. Escolha o idioma de origem na barra lateral."
            return
        }
        // Preserve numbers/punctuation without asking the language detector to classify them.
        for index in document.paragraphs.indices where !TranslationInput.needsTranslation(document.paragraphs[index].original) {
            document.apply(document.paragraphs[index].original, at: index)
        }
        guard document.completed < document.count else {
            status = "Documento sem texto para traduzir. Números e símbolos foram preservados."
            return
        }
        guard let origin else { return }
        phase = .translating
        stopping = false
        error = nil
        status = "Preparando \(languageName(origin)) → \(languageName(target))…"
        let next = TranslationSession.Configuration(source: Locale.Language(identifier: origin), target: Locale.Language(identifier: target))
        if configuration?.source == next.source && configuration?.target == next.target {
            configuration?.invalidate()
        } else { configuration = next }
    }

    func translate(using session: TranslationSession) async {
        guard phase == .translating else { return }
        sessionRunning = true
        defer { phase = .idle; stopping = false; sessionRunning = false; active = nil; persist() }
        do {
            // Measured: batches and parallel sessions do not speed up the system engine (see PERF.md).
            // Sequential calls keep pause boundaries exact; the page being read goes first.
            for (step, index) in document.pendingOrder(from: selectedPage).enumerated() {
                try Task.checkCancellation()
                if stopping { break }
                active = index
                status = "Traduzindo · \(document.completed + 1) de \(document.count)"
                let response = try await session.translate(document.paragraphs[index].original)
                try Task.checkCancellation()
                document.apply(response.targetText, at: index)
                if step % 20 == 19 { persist() }
            }
            status = stopping ? "Tradução pausada. Seu progresso foi mantido." : "Tradução concluída. Revise comparando com o original."
        } catch is CancellationError {
            status = "Tradução interrompida. Seu progresso foi mantido."
        } catch let error as CocoaError where error.code == .userCancelled {
            status = "Tradução pausada. Continue quando os idiomas estiverem disponíveis."
        } catch TranslationError.unableToIdentifyLanguage {
            error = "Não foi possível identificar o idioma. Selecione o idioma de origem e tente novamente."
            status = "Escolha o idioma de origem."
        } catch TranslationError.unsupportedSourceLanguage {
            error = "O idioma de origem não é suportado pelo tradutor do macOS. Confira o idioma selecionado."
            status = "Idioma de origem indisponível."
        } catch TranslationError.unsupportedLanguagePairing {
            error = "O macOS não oferece tradução entre esses idiomas. Selecione a origem correta e um destino diferente."
            status = "Combinação de idiomas indisponível."
        } catch {
            let details = error as NSError
            self.error = "Não foi possível traduzir. O progresso foi mantido. Confira o idioma de origem e tente novamente.\n\n\(error.localizedDescription)\nCódigo: \(details.domain) / \(details.code)"
            status = "Não foi possível concluir a tradução."
        }
    }

    func loadLanguages() async {
        let supported = await availableLanguages()
        languages = supported.sorted { languageName($0.minimalIdentifier) < languageName($1.minimalIdentifier) }
        if document.isEmpty, !languages.contains(where: { $0.minimalIdentifier == target }),
           let portuguese = languages.first(where: { $0.languageCode?.identifier == "pt" }) {
            target = portuguese.minimalIdentifier
        }
    }

    /// Jump to a passage and mark it, e.g. from a source cited in an answer.
    func reveal(paragraphs range: Range<Int>) {
        let range = range.clamped(to: 0..<document.count)
        guard !range.isEmpty else { return }
        selectedPage = document.paragraphs[range.lowerBound].page
        highlighted = range
        revealToken += 1
    }

    func reveal(page: Int) {
        guard document.pageRanges[page] != nil else { return }
        selectedPage = page
        highlighted = nil
        revealToken += 1
    }

    /// Area of the marked passage on the page being shown, for the original PDF.
    var highlightBounds: CGRect? {
        guard let highlighted else { return nil }
        let area = highlighted.compactMap { document.paragraphs[$0].page == selectedPage ? document.paragraphs[$0].bounds : nil }
            .reduce(CGRect.null) { $0.union($1) }
        return area.isNull ? nil : area
    }

    func movePage(_ offset: Int) {
        guard let index = document.pages.firstIndex(of: selectedPage), document.pages.indices.contains(index + offset) else { return }
        selectedPage = document.pages[index + offset]
    }

    func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + " — tradução." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = Exporter.data(format, filename: filename, targetName: languageName(target), document: document)
            guard !data.isEmpty else { error = "Não foi possível gerar o arquivo."; return }
            try data.write(to: url, options: .atomic)
            status = "Exportado para \(url.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }

    private static func contentKey(_ paragraphs: [Paragraph]) -> String {
        SHA256.hash(data: Data(paragraphs.map(\.original).joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func persist() {
        guard !fingerprint.isEmpty, !document.isEmpty else { return }
        var saved = Library.load(fingerprint) ?? SavedDocument(name: filename, path: fileURL?.path ?? "", pages: pageCount,
                                                              source: source, target: target, translations: [])
        saved.name = filename
        saved.path = fileURL?.path ?? saved.path
        saved.pages = pageCount
        saved.source = source
        saved.target = target
        saved.translations = document.paragraphs.map(\.translated)
        saved.contentKey = contentKey
        saved.opened = Date()
        Library.save(saved, fingerprint: fingerprint)
        recents = Library.recents()
    }
}

func languageName(_ code: String) -> String {
    Locale(identifier: "pt_BR").localizedString(forIdentifier: code)?.capitalized(with: Locale(identifier: "pt_BR")) ?? code
}

private func availableLanguages() async -> [Locale.Language] {
    await LanguageAvailability().supportedLanguages
}
