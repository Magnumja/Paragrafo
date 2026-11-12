import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct ParagrafoApp: App {
    var body: some Scene {
        WindowGroup { ContentView().frame(minWidth: 820, minHeight: 580) }
            .defaultSize(width: 1080, height: 760)
    }
}

struct ContentView: View {
    @ViewState private var paragraphs: [Paragraph] = []
    @ViewState private var filename: String = ""
    @ViewState private var target: String = "pt"
    @ViewState private var languages: [Locale.Language] = []
    @ViewState private var importing: Bool = false
    @ViewState private var busy: Bool = false
    @ViewState private var stopped: Bool = false
    @ViewState private var status: String = "Seus documentos, em outras palavras."
    @ViewState private var error: String?
    @ViewState private var configuration: TranslationSession.Configuration?
    private let accent = Color(red: 0.22, green: 0.40, blue: 0.33)
    private var completed: Int { paragraphs.filter { !$0.translated.isEmpty }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "text.book.closed").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Parágrafo").font(.title3.weight(.semibold))
                    Text(filename.isEmpty ? "Um PDF. Uma leitura sem fronteiras." : filename)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Abrir PDF", systemImage: "plus") { importing = true }
                    .keyboardShortcut("o").disabled(busy)
                Button("Exportar", systemImage: "square.and.arrow.up") { export() }
                    .disabled(completed == 0 || busy)
            }.padding(24)
            Divider()
            if paragraphs.isEmpty {
                Spacer()
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(accent)
                Text("Leia além do idioma.").font(.system(size: 30, weight: .medium, design: .serif)).padding(.top, 16)
                Text("Abra um PDF para comparar cada parágrafo\ncom sua tradução, no seu ritmo.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.top, 6)
                Button("Escolher PDF…") { importing = true }.buttonStyle(.borderedProminent).padding(.top, 20).disabled(busy)
                Text("Texto e documentos digitalizados • Processamento no Mac")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                Spacer()
            } else {
                HStack {
                    Text("TRADUZIR PARA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Idioma de destino", selection: $target) {
                        if languages.isEmpty { Text("Português").tag("pt") }
                        ForEach(languages, id: \.minimalIdentifier) { language in
                            Text(languageName(language.minimalIdentifier)).tag(language.minimalIdentifier)
                        }
                    }.labelsHidden().frame(width: 180).disabled(busy)
                        .onChange(of: target) { _, _ in
                            for index in paragraphs.indices { paragraphs[index].translated = "" }
                        }
                    Spacer()
                    Text("\(completed) / \(paragraphs.count)").monospacedDigit().foregroundStyle(.secondary)
                    if busy {
                        Button("Parar") { stopped = true }.disabled(stopped)
                    } else {
                        Button(completed > 0 ? "Continuar" : "Traduzir") { startTranslation() }
                            .buttonStyle(.borderedProminent).disabled(completed == paragraphs.count)
                    }
                }.padding(20)
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach($paragraphs) { $paragraph in
                            VStack(alignment: .leading, spacing: 14) {
                                Text("PÁGINA \(paragraph.page) · PARÁGRAFO \((paragraphs.firstIndex(where: { $0.id == paragraph.id }) ?? 0) + 1)")
                                    .font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                                HStack(alignment: .top, spacing: 24) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Original").font(.caption).foregroundStyle(.secondary)
                                        Text(paragraph.original).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(languageName(target)).font(.caption).foregroundStyle(accent)
                                        Text(paragraph.translated.isEmpty ? "Aguardando tradução…" : paragraph.translated)
                                            .foregroundStyle(paragraph.translated.isEmpty ? Color.secondary : Color.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }.font(.system(size: 16, design: .serif)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.padding(24).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
            Divider()
            HStack(spacing: 10) {
                if busy { ProgressView().controlSize(.small) }
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor)).tint(accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .task {
            languages = await availableLanguages().sorted { languageName($0.minimalIdentifier) < languageName($1.minimalIdentifier) }
            if !languages.contains(where: { $0.minimalIdentifier == target }), let portuguese = languages.first(where: { $0.languageCode?.identifier == "pt" }) { target = portuguese.minimalIdentifier }
        }
        .translationTask(configuration) { session in
            guard busy, !paragraphs.isEmpty else { return }
            do {
                try await session.prepareTranslation()
                for index in paragraphs.indices {
                    try Task.checkCancellation()
                    if stopped { break }
                    guard paragraphs[index].translated.isEmpty else { continue }
                    status = "Traduzindo parágrafo \(index + 1) de \(paragraphs.count)…"
                    let response = try await session.translate(paragraphs[index].original)
                    paragraphs[index].translated = response.targetText
                }
                status = stopped ? "Tradução pausada. Você pode continuar de onde parou." : "Tradução concluída. Compare com o original antes de usar."
            } catch {
                self.error = "A tradução foi interrompida. O idioma pode não ser compatível ou precisar de download. O progresso foi mantido.\n\n\(error.localizedDescription)"
                status = "Tradução interrompida."
            }
            busy = false
        }
    }

    private func languageName(_ code: String) -> String {
        Locale(identifier: "pt_BR").localizedString(forIdentifier: code) ?? code
    }

    private func startTranslation() {
        stopped = false
        busy = true
        status = "Preparando idiomas…"
        let next = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: target))
        if configuration == next { configuration?.invalidate() } else { configuration = next }
    }

    private func load(_ url: URL) {
        busy = true
        configuration = nil
        status = "Extraindo texto e reconhecendo páginas digitalizadas…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try PDFExtractor.extract(url: url) }.value
                paragraphs = result.paragraphs
                filename = url.lastPathComponent
                status = "\(paragraphs.count) parágrafos · \(result.ocrPages) páginas com OCR. Confira a separação de parágrafos."
                if !result.emptyPages.isEmpty { status += " Páginas sem texto: \(result.emptyPages.map(String.init).joined(separator: ", "))." }
            } catch { self.error = error.localizedDescription; status = "Não foi possível importar o PDF." }
            busy = false
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + " — tradução.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "\(filename)\nTradução para \(languageName(target)) · \(completed)/\(paragraphs.count) parágrafos\n\n" + paragraphs.enumerated().map { index, paragraph in
            "Página \(paragraph.page) · Parágrafo \(index + 1)\n\nORIGINAL\n\(paragraph.original)\n\nTRADUÇÃO\n\(paragraph.translated.isEmpty ? "[Não traduzido]" : paragraph.translated)"
        }.joined(separator: "\n\n————————————\n\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
}

private func availableLanguages() async -> [Locale.Language] {
    await LanguageAvailability().supportedLanguages
}
