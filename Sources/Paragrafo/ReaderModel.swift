import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

@MainActor
final class ReaderModel: ObservableObject {
    enum Phase { case idle, importing, translating }
    @Published var document = DocumentState()
    @Published var filename = ""
    @Published var target = "pt"
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
    var busy: Bool { phase != .idle }

    func load(_ url: URL) {
        guard !busy else { return }
        let id = UUID()
        importID = id
        phase = .importing
        stopping = false
        importProgress = 0
        configuration = nil
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
        } else {
            status = "Pausando após o parágrafo atual…"
        }
    }

    func changeTarget() {
        guard !busy else { return }
        configuration = nil
        document.clearTranslations()
        status = "Destino alterado. Pronto para traduzir."
    }

    func startTranslation() {
        guard !busy, !document.isEmpty, document.completed < document.count else { return }
        phase = .translating
        stopping = false
        status = "Preparando tradução…"
        let next = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: target))
        if configuration == next { configuration?.invalidate() } else { configuration = next }
    }

    func translate(using session: TranslationSession) async {
        guard phase == .translating else { return }
        defer { phase = .idle; stopping = false }
        do {
            // translate detects the source and requests language downloads as needed.
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
        } catch {
            self.error = "O progresso foi mantido. Verifique se o idioma é compatível e se os modelos foram baixados.\n\n\(error.localizedDescription)"
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
