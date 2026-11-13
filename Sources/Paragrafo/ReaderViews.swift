import SwiftUI

@MainActor
enum ReaderStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.55, green: 0.76, blue: 0.65, alpha: 1)
            : NSColor(srgbRed: 0.22, green: 0.40, blue: 0.33, alpha: 1)
    })
    static let paper = Color(nsColor: .textBackgroundColor)

    static func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.3)
    }
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case parallel, translation, original
    var id: String { rawValue }
    var title: String {
        switch self {
        case .parallel: "Lado a lado"
        case .translation: "Tradução"
        case .original: "PDF original"
        }
    }
}

// MARK: Start screen

struct EmptyReader: View {
    @ObservedObject var model: ReaderModel
    let open: () -> Void
    private static let logo = Bundle.main.url(forResource: "paragrafo-logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let logo = Self.logo {
                    Image(nsImage: logo).resizable().renderingMode(.template).scaledToFit().frame(width: 150, height: 150)
                        .foregroundStyle(ReaderStyle.accent).accessibilityLabel("Parágrafo")
                } else {
                    Image(systemName: "text.book.closed").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(ReaderStyle.accent).padding(28)
                }
                Text("Leia, traduza e pergunte.\nTudo no mesmo documento.")
                    .font(.system(size: 32, weight: .regular, design: .serif)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Abra um PDF para ler o original ao lado da tradução\ne fazer perguntas que apontam para o trecho exato.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .lineSpacing(4).padding(.top, 14).fixedSize(horizontal: false, vertical: true)
                if model.phase == .importing {
                    VStack(spacing: 10) {
                        ProgressView(value: model.importProgress).frame(width: 260)
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                        Button("Cancelar") { model.stop() }.disabled(model.stopping)
                    }.padding(.top, 30)
                } else {
                    Button(action: open) {
                        Label("Escolher PDF", systemImage: "plus").padding(.horizontal, 16).padding(.vertical, 6)
                    }.readerPrimaryAction().controlSize(.large).padding(.top, 26)
                    Text("ou arraste um PDF para esta janela").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                }
                if !model.recents.isEmpty && model.phase != .importing {
                    VStack(alignment: .leading, spacing: 6) {
                        ReaderStyle.label("Continuar de onde parou").foregroundStyle(.secondary).padding(.leading, 12)
                        VStack(spacing: 0) {
                            ForEach(model.recents.prefix(5)) { recent in
                                RecentRow(recent: recent, open: { model.open(recent) }, forget: { model.forget(recent) })
                                if recent != model.recents.prefix(5).last { Divider().padding(.leading, 46) }
                            }
                        }
                        .background(ReaderStyle.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
                    }.frame(maxWidth: 460).padding(.top, 36)
                }
                HStack(spacing: 26) {
                    Label("Original e tradução lado a lado", systemImage: "rectangle.split.2x1")
                    Label("Perguntas com Llama local", systemImage: "sparkles")
                    Label("Nada sai do seu Mac", systemImage: "lock.shield")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 36)
            }
            .padding(40).frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in max(length, 0) }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct RecentRow: View {
    let recent: RecentDocument
    let open: () -> Void
    let forget: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.title3).foregroundStyle(ReaderStyle.accent).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(recent.opened, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.05) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { Button("Remover dos recentes", systemImage: "trash", role: .destructive, action: forget) }
    }

    private var detail: String {
        let percent = recent.paragraphs > 0 ? recent.completed * 100 / recent.paragraphs : 0
        return "\(recent.pages) páginas · " + (percent == 0 ? "não traduzido" : percent == 100 ? "tradução concluída" : "\(percent)% traduzido")
    }
}

// MARK: Reading

struct BilingualPage: View {
    @ObservedObject var model: ReaderModel
    let translationOnly: Bool
    let fontSize: Double
    let ask: (Int) -> Void
    let showInPDF: (Int) -> Void
    @ViewState private var width: CGFloat = 900

    private var range: Range<Int> { model.document.pageRanges[model.selectedPage] ?? 0..<0 }
    private var stacked: Bool { width < 720 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(range, id: \.self) { index in
                        ParagraphRow(paragraph: model.document.paragraphs[index], number: index + 1,
                                     translationOnly: translationOnly, stacked: stacked, fontSize: fontSize,
                                     active: model.active == index, highlighted: model.highlighted?.contains(index) ?? false,
                                     ask: { ask(index) }, showInPDF: { showInPDF(index) })
                            .id(index)
                        if index != range.upperBound - 1 { Divider().padding(.leading, 46) }
                    }
                    pager
                }
                .padding(.horizontal, 28).padding(.vertical, 26)
                .frame(maxWidth: translationOnly ? 760 : 1180).frame(maxWidth: .infinity)
            }
            .id(model.selectedPage)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onChange(of: model.revealToken, initial: true) { _, _ in
                guard let index = model.highlighted?.lowerBound, range.contains(index) else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .top) }
                }
            }
        }
        .background(ReaderStyle.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Página \(model.selectedPage)").font(.system(size: 26, weight: .medium, design: .serif))
                Text("de \(model.pageCount)").font(.callout).foregroundStyle(.secondary)
                Spacer()
                let done = model.document.completedByPage[model.selectedPage] ?? 0
                if done < range.count, model.phase != .translating, !model.document.isEmpty {
                    Button("Traduzir a partir daqui", systemImage: "translate") { model.startTranslation() }
                        .controlSize(.small).disabled(model.busy)
                }
            }
            if !model.notice.isEmpty {
                Label(model.notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            if !translationOnly && !stacked {
                HStack(spacing: 36) {
                    ReaderStyle.label("Original · " + languageName(model.source == "auto" ? model.detectedSource ?? "" : model.source))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    ReaderStyle.label(languageName(model.target))
                        .foregroundStyle(ReaderStyle.accent).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 34)
            }
        }.padding(.horizontal, 12).padding(.bottom, 10)
    }

    private var pager: some View {
        HStack {
            Button("Página anterior", systemImage: "chevron.left") { model.movePage(-1) }
                .disabled(model.selectedPage == model.document.pages.first)
            Spacer()
            Button { model.movePage(1) } label: { Label("Próxima página", systemImage: "chevron.right").labelStyle(TrailingIcon()) }
                .disabled(model.selectedPage == model.document.pages.last)
        }.padding(.top, 28).padding(.horizontal, 12)
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon }
    }
}

struct ParagraphRow: View {
    let paragraph: Paragraph
    let number: Int
    let translationOnly: Bool
    let stacked: Bool
    let fontSize: Double
    let active: Bool
    let highlighted: Bool
    let ask: () -> Void
    let showInPDF: () -> Void
    @ViewState private var hovering = false
    @ViewState private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pending: Bool { paragraph.translated.isEmpty }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing).accessibilityLabel("Parágrafo \(number)")
            if translationOnly {
                translation
            } else if stacked {
                VStack(alignment: .leading, spacing: 12) { original; translation }
            } else {
                HStack(alignment: .top, spacing: 36) { original; translation }
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 12)
        .background(highlighted ? ReaderStyle.accent.opacity(0.14) : hovering ? Color.primary.opacity(0.035) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) { actions.padding(6).opacity(hovering ? 1 : 0).allowsHitTesting(hovering).accessibilityHidden(true) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: highlighted)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copiar tradução", systemImage: "doc.on.doc") { copy(paragraph.translated) }.disabled(pending)
            Button("Copiar original", systemImage: "doc.on.doc") { copy(paragraph.original) }
            Divider()
            Button("Perguntar sobre este trecho", systemImage: "sparkles", action: ask)
            Button("Mostrar no PDF original", systemImage: "doc.viewfinder", action: showInPDF)
        }
    }

    private var original: some View {
        text(paragraph.original).foregroundStyle(.primary.opacity(translationOnly ? 1 : 0.72))
    }

    @ViewBuilder private var translation: some View {
        if !pending {
            text(paragraph.translated)
        } else if translationOnly {
            // Nothing to show yet: keep the original readable instead of a blank.
            VStack(alignment: .leading, spacing: 6) {
                text(paragraph.original).foregroundStyle(.secondary)
                Label(active ? "Traduzindo…" : "Ainda no idioma original", systemImage: active ? "ellipsis" : "clock")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        } else if stacked {
            Label(active ? "Traduzindo…" : "Tradução pendente", systemImage: active ? "ellipsis" : "clock")
                .font(.caption).foregroundStyle(.tertiary)
        } else {
            text(paragraph.original).redacted(reason: .placeholder).opacity(active ? 0.55 : 0.22)
                .overlay(alignment: .topLeading) {
                    if active { ProgressView().controlSize(.small).padding(.top, 4) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(active ? "Traduzindo" : "Tradução pendente")
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if !pending {
                action(copied ? "checkmark" : "doc.on.doc", "Copiar tradução") { copy(paragraph.translated) }
            }
            action("sparkles", "Perguntar sobre este trecho", ask)
            action("doc.viewfinder", "Mostrar no PDF original", showInPDF)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private func action(_ symbol: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: symbol).font(.system(size: 12)).frame(width: 24, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(title).accessibilityLabel(title)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
    }

    private func text(_ value: String) -> some View {
        Text(value).font(.system(size: fontSize, design: .serif)).lineSpacing(fontSize * 0.38)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
