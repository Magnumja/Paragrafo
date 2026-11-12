import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

// Disambiguate property wrappers from similarly named macros in newer SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>
typealias ReaderStateObject<Value: ObservableObject> = SwiftUI.StateObject<Value>

@main
struct ParagrafoApp: App {
    var body: some Scene {
        WindowGroup { ContentView().frame(minWidth: 780, minHeight: 580) }
            .defaultSize(width: 1160, height: 800)
    }
}

struct ContentView: View {
    @ReaderStateObject private var model = ReaderModel()
    @ViewState private var importing = false
    @ViewState private var translationOnly = false
    @ViewState private var fontSize = 17.0
    @ViewState private var dropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            if model.document.isEmpty {
                EmptyReader(importing: model.phase == .importing, open: { importing = true })
            } else {
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    readingPane
                }
            }
            statusBar
        }
        .background(ReaderStyle.canvas)
        .tint(ReaderStyle.accent)
        .navigationTitle("Parágrafo")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Abrir PDF", systemImage: "folder") { importing = true }
                    .keyboardShortcut("o").disabled(model.busy)
                Button("Exportar", systemImage: "square.and.arrow.up") { model.export() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.document.completed == 0 || model.busy)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): model.load(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.busy, let url = urls.first, url.pathExtension.lowercased() == "pdf" else { return false }
            model.load(url)
            return true
        } isTargeted: { dropTarget = $0 }
        .overlay {
            if dropTarget && !model.busy {
                RoundedRectangle(cornerRadius: 12).strokeBorder(ReaderStyle.accent, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task { await model.loadLanguages() }
        .translationTask(model.configuration) { session in await model.translate(using: session) }
        .onChange(of: model.target) { _, _ in model.changeTarget() }
        .onChange(of: model.source) { _, _ in model.changeTarget() }
        .onDisappear { if model.busy { model.stop() } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.title2).foregroundStyle(ReaderStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.filename).font(.headline).lineLimit(2).help(model.filename)
                    Text("\(model.document.pages.count) páginas com texto").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("IDIOMA DE ORIGEM")
                Picker("Idioma de origem", selection: $model.source) {
                    Text(model.detectedSource.map { "Automático · " + languageName($0) } ?? "Detectar automaticamente").tag("auto")
                    ForEach(model.languages, id: \.minimalIdentifier) { language in
                        Text(languageName(language.minimalIdentifier)).tag(language.minimalIdentifier)
                    }
                }.labelsHidden().disabled(model.busy).frame(maxWidth: .infinity)
                sectionTitle("IDIOMA DE DESTINO")
                Picker("Idioma de destino", selection: $model.target) {
                    if model.languages.isEmpty { Text("Português").tag("pt") }
                    ForEach(model.languages, id: \.minimalIdentifier) { language in
                        Text(languageName(language.minimalIdentifier)).tag(language.minimalIdentifier)
                    }
                }.labelsHidden().disabled(model.busy).frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("TRADUÇÃO")
                    Spacer()
                    Text("\(Int(progress * 100))%") .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: progress).accessibilityLabel("Progresso da tradução")
                Text("\(model.document.completed) de \(model.document.count) parágrafos").font(.caption).foregroundStyle(.secondary)
                if model.busy {
                    Button(model.stopping ? "Aguarde…" : "Pausar", systemImage: "pause.fill") { model.stop() }
                        .disabled(model.stopping).frame(maxWidth: .infinity)
                } else {
                    Button(model.document.completed == model.document.count ? "Concluído" : model.document.completed > 0 ? "Continuar tradução" : "Traduzir documento", systemImage: model.document.completed == model.document.count ? "checkmark" : "character.bubble") {
                        model.startTranslation()
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.document.completed == model.document.count)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("LEITURA")
                Toggle("Só tradução", isOn: $translationOnly).toggleStyle(.switch).controlSize(.small)
                HStack {
                    Text("Texto").foregroundStyle(.secondary)
                    Spacer()
                    Button { fontSize = max(14, fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                        .accessibilityLabel("Diminuir texto").disabled(fontSize <= 14)
                    Text("\(Int(fontSize))").font(.caption.monospacedDigit()).frame(width: 20)
                    Button { fontSize = min(24, fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                        .accessibilityLabel("Aumentar texto").disabled(fontSize >= 24)
                }
            }.font(.callout)
            Spacer(minLength: 10)
            Label("Processado no Mac", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
            Text("A tradução automática pode conter erros. Compare os trechos antes de usar.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 250).frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var readingPane: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(translationOnly ? "Sua tradução" : "Uma leitura, dois idiomas.")
                        .font(.system(size: 23, weight: .medium, design: .serif))
                    Text(translationOnly ? "Leitura contínua, parágrafo por parágrafo." : "O original sempre ao alcance dos olhos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                pageNavigation
            }.padding(24)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !model.notice.isEmpty {
                        Label(model.notice, systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary).padding(.bottom, 2)
                    }
                    ForEach(model.document.pageRanges[model.selectedPage] ?? 0..<0, id: \.self) { index in
                        ParagraphCard(paragraph: model.document.paragraphs[index], number: index + 1,
                                      targetName: languageName(model.target), translationOnly: translationOnly, fontSize: fontSize)
                    }
                }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.id(model.selectedPage)
        }
    }

    private var pageNavigation: some View {
        HStack(spacing: 8) {
            Button { movePage(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Página anterior").disabled(model.selectedPage == model.document.pages.first)
            Picker("Página", selection: $model.selectedPage) {
                ForEach(model.document.pages, id: \.self) { Text("Página \($0)").tag($0) }
            }.labelsHidden().frame(width: 115)
            Button { movePage(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Próxima página").disabled(model.selectedPage == model.document.pages.last)
        }.controlSize(.small)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(ReaderStyle.accent) }
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.phase == .importing {
                    ProgressView(value: model.importProgress).frame(width: 100)
                    Button("Cancelar") { model.stop() }.disabled(model.stopping).controlSize(.small)
                }
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var progress: Double { Double(model.document.completed) / Double(max(1, model.document.count)) }
    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
    }
    private func movePage(_ offset: Int) {
        guard let index = model.document.pages.firstIndex(of: model.selectedPage), model.document.pages.indices.contains(index + offset) else { return }
        model.selectedPage = model.document.pages[index + offset]
    }
}
