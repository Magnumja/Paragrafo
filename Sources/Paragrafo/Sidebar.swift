import SwiftUI

struct Sidebar: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: Binding(get: { Optional(model.selectedPage) }, set: { if let page = $0 { model.selectedPage = page } })) {
                Section("Páginas") {
                    ForEach(model.document.pages, id: \.self) { page in
                        PageRow(page: page, snippet: snippet(page), done: model.document.completedByPage[page] ?? 0,
                                total: model.document.pageRanges[page]?.count ?? 0)
                            .tag(page).id(page)
                    }
                }
            }
            .onChange(of: model.selectedPage) { _, page in proxy.scrollTo(page) }
        }
        .safeAreaInset(edge: .top, spacing: 0) { controls }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.filename).font(.headline).lineLimit(2).help(model.filename)
                Text("\(model.pageCount) páginas · \(model.document.count) parágrafos")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("De").font(.caption).foregroundStyle(.secondary)
                    Picker("Idioma de origem", selection: Binding(get: { model.source }, set: { model.choose(source: $0) })) {
                        Text(model.detectedSource.map { "Automático · " + languageName($0) } ?? "Detectar automaticamente").tag("auto")
                        Divider()
                        ForEach(model.languages, id: \.minimalIdentifier) { Text(languageName($0.minimalIdentifier)).tag($0.minimalIdentifier) }
                    }.labelsHidden()
                }
                GridRow {
                    Text("Para").font(.caption).foregroundStyle(.secondary)
                    Picker("Idioma de destino", selection: Binding(get: { model.target }, set: { model.choose(target: $0) })) {
                        if !model.languages.contains(where: { $0.minimalIdentifier == model.target }) { Text(languageName(model.target)).tag(model.target) }
                        ForEach(model.languages, id: \.minimalIdentifier) { Text(languageName($0.minimalIdentifier)).tag($0.minimalIdentifier) }
                    }.labelsHidden()
                }
            }.disabled(model.busy)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress).accessibilityLabel("Progresso da tradução")
                HStack {
                    Text("\(model.document.completed) de \(model.document.count) parágrafos")
                    Spacer()
                    Text("\(Int(progress * 100))%").monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }
            if model.phase == .translating {
                Button(model.stopping ? "Aguarde…" : "Pausar", systemImage: "pause.fill") { model.stop() }
                    .controlSize(.large).disabled(model.stopping).frame(maxWidth: .infinity)
            } else {
                Button { model.startTranslation() } label: {
                    Label(model.document.isComplete ? "Tradução concluída" : model.document.completed > 0 ? "Continuar tradução" : "Traduzir documento",
                          systemImage: model.document.isComplete ? "checkmark" : "translate").frame(maxWidth: .infinity)
                }
                .readerPrimaryAction().controlSize(.large)
                .disabled(model.document.isComplete || model.busy)
                .help("Começa pela página que você está lendo")
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.phase == .importing {
                ProgressView(value: model.importProgress)
                Button("Cancelar importação") { model.stop() }.controlSize(.small).disabled(model.stopping)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if model.busy { ProgressView().controlSize(.mini) }
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Label("Tudo é processado neste Mac", systemImage: "lock.shield").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var progress: Double { Double(model.document.completed) / Double(max(1, model.document.count)) }

    private func snippet(_ page: Int) -> String {
        guard let first = model.document.pageRanges[page]?.lowerBound else { return "" }
        let paragraph = model.document.paragraphs[first]
        return String((paragraph.translated.isEmpty ? paragraph.original : paragraph.translated).prefix(80))
    }
}

private struct PageRow: View {
    let page: Int
    let snippet: String
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Página \(page)").font(.callout.weight(.medium))
                Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if total > 0 && done >= total {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ReaderStyle.accent).font(.caption)
            } else if done > 0 {
                Text("\(done)/\(total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Página \(page), \(done) de \(total) parágrafos traduzidos")
    }
}
