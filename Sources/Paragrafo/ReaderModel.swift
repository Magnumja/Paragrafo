import SwiftUI
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
    @Published var selectedPage = 1
    @Published var phase: Phase = .idle
    @Published var stopping = false
    @Published var status = "Pronto para um novo documento."
    @Published var notice = ""
    @Published var error: String?
    @Published var configuration: TranslationSession.Configuration?
    @Published var importProgress = 0.0
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
                guard importID == id, !stopping else { return }
                document = DocumentState(result.paragraphs)
                detectedSource = TranslationInput.detectLanguage(in: result.paragraphs)
                selectedPage = document.pages.first ?? 1
                filename = url.lastPathComponent
                status = "\(document.count) parágrafos prontos para traduzir."
                notice = result.ocrPages > 0 ? "OCR usado em \(result.ocrPages) página(s). Confira o texto reconhecido." : "Confira a ordem de leitura em tabelas e documentos com colunas."
                if !result.emptyPages.isEmpty {
                    notice += " Sem texto nas páginas: \(result.emptyPages.map(String.init).joined(separator: ", "))."
                }
            } catch is CancellationError {
                status = "Importação cancelada."
            } catch {
                self.error = error.localizedDescription
                status = "Não foi possível importar o PDF."
            }
        }
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

    func changeTarget() {
        guard !busy else { return }
        document.clearTranslations()
        status = "Idiomas alterados. Pronto para traduzir."
    }

    func startTranslation() {
        guard !busy, !document.isEmpty, document.completed < document.count else { return }
        let origin = source == "auto" ? detectedSource : source
        if let origin, TranslationInput.sameLanguage(origin, target) {
            error = "A origem e o destino são o mesmo idioma. Se o documento está em inglês, escolha Inglês em Idioma de origem e Português no destino."
            status = "Escolha idiomas diferentes para traduzir."
            return
        }
        if origin == nil && document.paragraphs.contains(where: { TranslationInput.needsTranslation($0.original) }) {
            error = "Não foi possível identificar a língua do documento. Escolha o Idioma de origem na barra lateral."
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
        defer { phase = .idle; stopping = false; sessionRunning = false }
        do {
            // Source is inferred from document text or explicitly chosen, not from its first heading.
            // Keeping calls sequential preserves paragraph order and pause boundaries.
            for index in document.paragraphs.indices {
                try Task.checkCancellation()
                if stopping { break }
                guard document.paragraphs[index].translated.isEmpty else { continue }
                status = "Traduzindo parágrafo \(index + 1) de \(document.count)…"
                let response = try await session.translate(document.paragraphs[index].original)
                try Task.checkCancellation()
                document.apply(response.targetText, at: index)
            }
            status = stopping ? "Tradução pausada. Seu progresso foi mantido." : "Tradução concluída. Revise comparando com o original."
        } catch is CancellationError {
            status = "Tradução interrompida. Seu progresso foi mantido."
        } catch let error as CocoaError where error.code == .userCancelled {
            status = "Tradução pausada. Continue quando os idiomas estiverem disponíveis."
        } catch TranslationError.unableToIdentifyLanguage {
            error = "Não foi possível identificar o idioma. Selecione Inglês em Idioma de origem e tente novamente."
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
        if !languages.contains(where: { $0.minimalIdentifier == target }),
           let portuguese = languages.first(where: { $0.languageCode?.identifier == "pt" }) {
            target = portuguese.minimalIdentifier
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + " — tradução.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "\(filename)\nTradução para \(languageName(target)) · \(document.completed)/\(document.count) parágrafos\n\n" + document.paragraphs.enumerated().map { index, paragraph in
            "Página \(paragraph.page) · Parágrafo \(index + 1)\n\nORIGINAL\n\(paragraph.original)\n\nTRADUÇÃO\n\(paragraph.translated.isEmpty ? "[Não traduzido]" : paragraph.translated)"
        }.joined(separator: "\n\n————————————\n\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
}

func languageName(_ code: String) -> String {
    Locale(identifier: "pt_BR").localizedString(forIdentifier: code) ?? code
}

private func availableLanguages() async -> [Locale.Language] {
    await LanguageAvailability().supportedLanguages
}
