import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

// Disambiguate property wrappers from similarly named macros in newer SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>
typealias ReaderStateObject<Value: ObservableObject> = SwiftUI.StateObject<Value>

/// PDFs opened from Finder ("Abrir com") or dropped on the Dock icon arrive here.
@MainActor
final class OpenRequests: NSObject, NSApplicationDelegate, ObservableObject {
    /// A path given on the command line opens that PDF at launch.
    @Published var pending: URL? = CommandLine.arguments.dropFirst().first { $0.lowercased().hasSuffix(".pdf") }.map { URL(fileURLWithPath: $0) }

    func application(_ application: NSApplication, open urls: [URL]) { request(urls) }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        request(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }
    private func request(_ urls: [URL]) {
        if let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) { pending = url }
    }
}

@main
struct ParagrafoApp: App {
    @NSApplicationDelegateAdaptor private var requests: OpenRequests
    var body: some Scene {
        // One window: a PDF opened from Finder goes to it instead of spawning an empty second one.
        Window("Parágrafo", id: "leitor") { ContentView().frame(minWidth: 880, minHeight: 600) }
            .defaultSize(width: 1400, height: 880)
            .commands { SidebarCommands(); TextSizeCommands() }
    }
}

/// View ▸ Tamanho do texto. ⌘= is what Mac users press to enlarge (the menu shows it as ⌘+).
struct TextSizeCommands: Commands {
    @AppStorage("fontSize") private var fontSize = 17.0
    @AppStorage("readingMode") private var mode = ReadingMode.parallel

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Menu("Tamanho do texto") {
                Button("Aumentar") { fontSize = min(24, fontSize + 1) }
                    .keyboardShortcut("=").disabled(fontSize >= 24 || mode == .original)
                Button("Diminuir") { fontSize = max(14, fontSize - 1) }
                    .keyboardShortcut("-").disabled(fontSize <= 14 || mode == .original)
                Button("Tamanho padrão") { fontSize = 17 }
                    .keyboardShortcut("0").disabled(fontSize == 17 || mode == .original)
            }
        }
    }
}

struct ContentView: View {
    @ReaderStateObject private var model = ReaderModel()
    @ReaderStateObject private var assistant = DocumentAssistant()
    @EnvironmentObject private var requests: OpenRequests
    @ViewState private var importing = false
    @ViewState private var dropTarget = false
    @ViewState private var navigation = PageNavigation()
    @AppStorage("readingMode") private var mode = ReadingMode.parallel
    @AppStorage("fontSize") private var fontSize = 17.0
    @AppStorage("showAssistant") private var showAssistant = true

    var body: some View {
        Group {
            if model.document.isEmpty {
                EmptyReader(model: model, dropTarget: dropTarget && !model.busy, open: { importing = true })
                    .background { ReaderBackdrop() }
            } else {
                workspace
            }
        }
        .tint(ReaderStyle.accent)
        .navigationTitle(model.document.isEmpty ? "Parágrafo" : model.filename)
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
            // The start screen has its own drop zone; the window-wide outline is for an open document.
            if dropTarget && !model.busy && !model.document.isEmpty {
                RoundedRectangle(cornerRadius: 14).strokeBorder(ReaderStyle.accent, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(ReaderStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task { await model.loadLanguages() }
        .translationTask(model.configuration) { session in await model.translate(using: session) }
        .onChange(of: model.fingerprint) { _, fingerprint in
            assistant.attach(paragraphs: model.document.paragraphs, fingerprint: fingerprint)
        }
        .onChange(of: requests.pending, initial: true) { _, _ in openPending() }
        .onChange(of: model.busy) { _, _ in openPending() }
        .onDisappear { if model.busy { model.stop() } }
    }

    private var workspace: some View {
        NavigationSplitView {
            Sidebar(model: model).navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 360)
        } detail: {
            reading
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { navigation.readingFrame = $0 }
                .inspector(isPresented: $showAssistant) {
                    AssistantPanel(assistant: assistant, translations: { model.document.paragraphs.map(\.translated) }, open: follow)
                        .inspectorColumnWidth(min: 300, ideal: 380, max: 540)
                }
        }
        .onAppear { navigation.install(model: model) }
        .onDisappear { navigation.uninstall() }
        .onChange(of: mode, initial: true) { _, mode in navigation.enabled = mode != .original }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Início", systemImage: "house") { model.close() }
                    .help("Voltar à tela inicial. O progresso fica salvo.").disabled(model.busy)
            }
            ToolbarItem(placement: .principal) {
                Picker("Modo de leitura", selection: $mode) {
                    ForEach(ReadingMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).help("Modo de leitura")
            }
            ToolbarItemGroup {
                ControlGroup {
                    Button("Página anterior", systemImage: "chevron.left") { model.movePage(-1) }
                        .keyboardShortcut("[").disabled(model.selectedPage == model.document.pages.first)
                        .help("Página anterior (← ou ⌘[)")
                    Button("Próxima página", systemImage: "chevron.right") { model.movePage(1) }
                        .keyboardShortcut("]").disabled(model.selectedPage == model.document.pages.last)
                        .help("Próxima página (→ ou ⌘])")
                }
                ControlGroup {
                    // Shortcuts live in the View menu (TextSizeCommands) so they are discoverable there.
                    Button("Diminuir texto", systemImage: "textformat.size.smaller") { fontSize = max(14, fontSize - 1) }
                        .disabled(fontSize <= 14 || mode == .original).help("Diminuir texto (⌘−)")
                    Button("Aumentar texto", systemImage: "textformat.size.larger") { fontSize = min(24, fontSize + 1) }
                        .disabled(fontSize >= 24 || mode == .original).help("Aumentar texto (⌘+)")
                }
                Menu("Exportar", systemImage: "square.and.arrow.up") {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.title, systemImage: format.symbol) { model.export(format) }
                    }
                }.disabled(model.document.completed == 0 || model.busy).help("Exportar a tradução").accessibilityLabel("Exportar")
                Button("Abrir PDF", systemImage: "folder") { importing = true }
                    .keyboardShortcut("o").disabled(model.busy)
            }
            ToolbarItem {
                Button("Perguntar", systemImage: "sparkles") { showAssistant.toggle() }
                    .keyboardShortcut("k").help("Mostrar ou ocultar o assistente (⌘K)")
            }
        }
    }

    @ViewBuilder private var reading: some View {
        if mode == .original {
            PDFPane(document: model.pdf, page: model.selectedPage,
                    highlight: model.highlightBounds,
                    token: model.revealToken) { page in
                if page != model.selectedPage, model.document.pageRanges[page] != nil { model.selectedPage = page }
            }
        } else {
            BilingualPage(model: model, translationOnly: mode == .translation, fontSize: fontSize, ask: ask) { index in
                mode = .original
                model.reveal(paragraphs: index..<(index + 1))
            }
        }
    }

    /// A link inside an answer: go to the cited passage or page.
    private func follow(_ destination: AnswerFormatter.Destination, in message: ChatMessage) {
        switch destination {
        case .source(let number):
            guard message.sources.indices.contains(number - 1) else { return }
            model.reveal(paragraphs: message.sources[number - 1].chunk.paragraphs)
        case .page(let page):
            model.reveal(page: page)
        }
    }

    /// A PDF requested from Finder waits for the current import or translation to finish.
    private func openPending() {
        guard let url = requests.pending, !model.busy else { return }
        requests.pending = nil
        model.load(url)
    }

    private func ask(_ index: Int) {
        let paragraph = model.document.paragraphs[index]
        showAssistant = true
        assistant.ask("Explique em linguagem simples este trecho da página \(paragraph.page): «\(paragraph.original.prefix(280))»",
                      translations: model.document.paragraphs.map(\.translated), overview: false)
    }
}
