import SwiftUI

/// The "ask the document" side panel.
struct AssistantPanel: View {
    @ObservedObject var assistant: DocumentAssistant
    let translations: () -> [String]
    let open: (AnswerFormatter.Destination, ChatMessage) -> Void
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            composer
        }
        .task(id: assistant.fingerprint) { await assistant.prepare() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Perguntar ao documento").font(.headline)
                statusLine
            }
            Spacer()
            Menu {
                Picker("Modelo", selection: $assistant.chatModel) {
                    ForEach(assistant.chatModels, id: \.self) { Text($0).tag($0) }
                }
                Divider()
                Button("Nova conversa", systemImage: "square.and.pencil") { assistant.clear() }
                    .disabled(assistant.messages.isEmpty || assistant.busy)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Opções do assistente")
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var statusLine: some View {
        switch (assistant.availability, assistant.indexState) {
        case (.checking, _), (.unknown, _):
            Text("Verificando o Ollama…").font(.caption).foregroundStyle(.secondary)
        case (.ready, .indexing(let done, let total)):
            HStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 70)
                Text("Indexando \(done) de \(total) trechos").font(.caption).foregroundStyle(.secondary)
            }
        case (.ready, .ready):
            Label(assistant.chatModel + " · local", systemImage: "circle.fill")
                .labelStyle(StatusDot(color: ReaderStyle.accent)).font(.caption).foregroundStyle(.secondary)
        case (.ready, .failed):
            Label("Índice indisponível", systemImage: "circle.fill").labelStyle(StatusDot(color: .orange)).font(.caption).foregroundStyle(.secondary)
        case (.ready, .empty):
            Text("Preparando…").font(.caption).foregroundStyle(.secondary)
        default:
            Label("Assistente indisponível", systemImage: "circle.fill").labelStyle(StatusDot(color: .orange)).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch assistant.availability {
        case .serverOff:
            SetupCard(symbol: "bolt.slash", title: "O Ollama não está em execução",
                      message: "O assistente responde com um modelo Llama que roda no seu Mac pelo Ollama. Abra o Ollama e tente de novo.") {
                Button("Tentar novamente") { Task { await assistant.checkAvailability(); await assistant.prepare() } }.readerPrimaryAction()
                Link("Instalar o Ollama", destination: URL(string: "https://ollama.com/download")!).font(.callout)
            }
        case .missing(let models):
            SetupCard(symbol: "arrow.down.circle", title: "Falta baixar \(models.count == 1 ? "um modelo" : "os modelos")",
                      message: "Necessário uma única vez: \(models.joined(separator: " e ")). O download fica guardado no Ollama.") {
                Button("Baixar agora") { assistant.download(models) }.readerPrimaryAction()
            }
        case .pulling(let model, let progress):
            SetupCard(symbol: "arrow.down.circle", title: "Baixando \(model)", message: "Você pode continuar lendo enquanto isso.") {
                ProgressView(value: progress).frame(width: 200)
                Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        default:
            if assistant.messages.isEmpty { suggestions } else { conversation }
        }
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 26, weight: .light)).foregroundStyle(ReaderStyle.accent)
                Text("O que você quer saber?").font(.system(size: 20, weight: .medium, design: .serif))
                Text("As respostas vêm do próprio documento e indicam a página e o trecho de onde saíram. Clique em uma fonte para ir até ela.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    suggestion("text.justify.left", "Síntese geral do documento") { assistant.summarize() }
                    suggestion("list.bullet", "Quais são os pontos principais?") { send("Quais são os pontos principais?") }
                    suggestion("number", "Quais números e datas importantes aparecem?") { send("Quais números e datas importantes aparecem?") }
                    suggestion("magnifyingglass", "Onde o documento fala sobre…") { draft = "Onde o documento fala sobre "; focused = true }
                }.padding(.top, 8)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func suggestion(_ symbol: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(ReaderStyle.accent).frame(width: 18)
                Text(title).font(.callout).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(assistant.busy)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(assistant.messages) { message in
                        MessageView(message: message, busy: assistant.busy,
                                    open: { open($0, message) }, regenerate: { assistant.regenerate(message.id) })
                    }
                    Color.clear.frame(height: 1).id("fim")
                }.padding(16)
            }
            .onChange(of: assistant.messages.last) { _, _ in proxy.scrollTo("fim", anchor: .bottom) }
            .onAppear { proxy.scrollTo("fim", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Pergunte sobre este documento…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...6).focused($focused)
                    .onSubmit { send(draft) }
                if assistant.busy {
                    Button { assistant.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Parar resposta").accessibilityLabel("Parar resposta")
                } else {
                    Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.plain).foregroundStyle(canSend ? ReaderStyle.accent : Color.secondary.opacity(0.4))
                        .disabled(!canSend).help("Enviar pergunta").accessibilityLabel("Enviar pergunta")
                }
            }
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
            .background(ReaderStyle.paper, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused ? ReaderStyle.accent.opacity(0.6) : Color.primary.opacity(0.12)))
            Text("Gerado no seu Mac. Confira nos trechos citados.").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
    }

    private var canSend: Bool {
        assistant.hasDocument && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ question: String) {
        guard !assistant.busy, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        assistant.ask(question, translations: translations())
        draft = ""
    }
}

private struct StatusDot: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(color)
            configuration.title
        }
    }
}

private struct SetupCard<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            actions
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MessageView: View {
    let message: ChatMessage
    let busy: Bool
    let open: (AnswerFormatter.Destination) -> Void
    let regenerate: () -> Void
    @ViewState private var copied = false
    @ViewState private var expanded = false

    var body: some View {
        if message.role == .user {
            Text(message.text).font(.callout).textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(ReaderStyle.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 36)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let progress { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(progress).font(.callout).foregroundStyle(.secondary) } }
                if !message.text.isEmpty {
                    if message.stage == .failed {
                        Label(message.text, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(AnswerFormatter.attributed(message.text, sourceCount: message.sources.count, pages: Set(message.sources.map(\.chunk.page))))
                            .font(.callout).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .environment(\.openURL, OpenURLAction { url in
                                guard let destination = AnswerFormatter.destination(url) else { return .discarded }
                                open(destination)
                                return .handled
                            })
                    }
                }
                if !shownSources.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ReaderStyle.label(message.cited.isEmpty ? "Trechos consultados" : "Fontes no documento").foregroundStyle(.secondary)
                        ForEach(expanded ? shownSources : Array(shownSources.prefix(3)), id: \.self) { number in
                            SourceRow(number: number, source: message.sources[number - 1]) { open(.source(number)) }
                        }
                        if shownSources.count > 3 {
                            Button(expanded ? "Mostrar menos" : "Ver as \(shownSources.count) fontes", systemImage: expanded ? "chevron.up" : "chevron.down") { expanded.toggle() }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(ReaderStyle.accent).padding(.top, 2)
                        }
                    }
                }
                if let note = message.note { Text(note).font(.caption).foregroundStyle(.tertiary) }
                if message.stage == .done {
                    HStack(spacing: 12) {
                        Button(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                        }
                        if message.isOverview {
                            Button("Gerar novamente", systemImage: "arrow.clockwise", action: regenerate).disabled(busy)
                        }
                    }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progress: String? {
        switch message.stage {
        case .searching: "Procurando no documento…"
        case .reading(let part, let total): "Lendo o documento · parte \(part) de \(total)"
        case .writing: message.text.isEmpty ? "Preparando a resposta…" : nil
        case .done, .failed: nil
        }
    }

    /// Cited passages once the answer is complete; the best matches while it is being written.
    private var shownSources: [Int] {
        guard !message.sources.isEmpty else { return [] }
        let cited = message.cited.filter { message.sources.indices.contains($0 - 1) }
        if !cited.isEmpty { return cited }
        return Array(1...min(3, message.sources.count))
    }
}

private struct SourceRow: View {
    let number: Int
    let source: Retrieved
    let open: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)").font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(ReaderStyle.accent)
                    .frame(width: 18, height: 18).background(ReaderStyle.accent.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Página \(source.chunk.page)").font(.caption.weight(.semibold))
                    Text(source.chunk.text).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(9).contentShape(Rectangle())
            .background(Color.primary.opacity(hovering ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help("Ir para este trecho na página \(source.chunk.page)")
        .accessibilityLabel("Fonte \(number), página \(source.chunk.page). Ir para o trecho.")
    }
}
