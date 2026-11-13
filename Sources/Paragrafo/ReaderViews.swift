import SwiftUI
import PDFKit

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
    var dropTarget = false
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The drop target is visible before anything is dragged, and answers when a PDF hovers over the window.
    private var dropZone: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 12) {
            Image(systemName: dropTarget ? "arrow.down.doc.fill" : "doc.badge.plus")
                .font(.system(size: 26, weight: .light)).foregroundStyle(ReaderStyle.accent)
                .contentTransition(.symbolEffect(.replace))
            Button(action: open) {
                Label("Escolher PDF", systemImage: "plus").padding(.horizontal, 16).padding(.vertical, 6)
            }.readerPrimaryAction().controlSize(.large)
            Text(dropTarget ? "Solte para abrir" : "ou arraste um PDF para cá")
                .font(.caption).foregroundStyle(dropTarget ? ReaderStyle.accent : .secondary)
        }
        .padding(.vertical, 24).frame(maxWidth: 460)
        .readerGlass(in: shape)
        .overlay(shape.strokeBorder(dropTarget ? ReaderStyle.accent : Color.primary.opacity(0.16),
                                    style: StrokeStyle(lineWidth: dropTarget ? 2 : 1.2, dash: [7, 5])))
        .scaleEffect(dropTarget && !reduceMotion ? 1.02 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: dropTarget)
    }

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
                    dropZone.padding(.top, 28)
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
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .readerGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    Text(recent.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle).help(recent.name)
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
    /// Switches the whole reader to the original PDF at this paragraph (offered from the peek).
    let openInPDF: (Int) -> Void
    @ViewState private var width: CGFloat = 900
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The new page slides in from the side it comes from; the old one only fades, so its direction never matters.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(x: model.pageForward ? 80 : -80).combined(with: .opacity),
                           removal: .opacity)
    }

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
                                     pdf: model.pdf, ask: { ask(index) }, openInPDF: { openInPDF(index) })
                            .id(index)
                        if index != range.upperBound - 1 { Divider().padding(.leading, 46) }
                    }
                    pager
                }
                .padding(.horizontal, 28).padding(.vertical, 26)
                .frame(maxWidth: translationOnly ? 760 : 1180).frame(maxWidth: .infinity)
            }
            .id(model.selectedPage)
            .transition(pageTransition)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onChange(of: model.revealToken, initial: true) { _, _ in
                guard let index = model.highlighted?.lowerBound, range.contains(index) else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .top) }
                }
            }
        }
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.3), value: model.selectedPage)
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
                .help("Também com ← ou deslizando dois dedos para a direita")
            Spacer()
            Text("← → mudam de página").font(.caption2).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Spacer()
            Button { model.movePage(1) } label: { Label("Próxima página", systemImage: "chevron.right").labelStyle(TrailingIcon()) }
                .disabled(model.selectedPage == model.document.pages.last)
                .help("Também com → ou deslizando dois dedos para a esquerda")
        }
        .buttonStyle(GlassCapsuleButtonStyle())
        .padding(.top, 28).padding(.horizontal, 12)
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon }
    }
}

/// The original page, with the paragraph marked, shown over the reading view. Esc or "Fechar" returns to reading.
private struct PDFPeek: View {
    let pdf: PDFDocument
    let paragraph: Paragraph
    let number: Int
    let close: () -> Void
    let openFull: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Página \(paragraph.page) · PDF original").font(.headline)
                    Text(paragraph.bounds == nil ? "Trecho sem posição no PDF" : "Parágrafo \(number) marcado")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abrir no modo PDF", systemImage: "arrow.up.left.and.arrow.down.right", action: openFull)
                    .buttonStyle(GlassCapsuleButtonStyle())
                    .help("Trocar a leitura para o PDF original neste trecho")
                Button("Fechar", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly).buttonStyle(GlassCapsuleButtonStyle())
                    .keyboardShortcut(.cancelAction).help("Fechar (Esc)")
            }
            .padding(12)
            Divider()
            PDFPane(document: pdf, page: paragraph.page, highlight: paragraph.bounds, token: 1, onPage: { _ in })
        }
        .frame(width: 560, height: 640)
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
    let pdf: PDFDocument?
    let ask: () -> Void
    let openInPDF: () -> Void
    @ViewState private var hovering = false
    @ViewState private var copied = false
    @ViewState private var peeking = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pending: Bool { paragraph.translated.isEmpty }
    /// The action bar shows for the mouse (hover) and for the keyboard (focus).
    private var showsActions: Bool { hovering || focused }

    /// Peek at the passage in the original without leaving the reading mode; full PDF mode if there is no document.
    private func showInPDF() {
        if pdf != nil { peeking = true } else { openInPDF() }
    }

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
        .background(highlighted ? ReaderStyle.accent.opacity(0.14) : showsActions ? Color.primary.opacity(0.035) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(ReaderStyle.accent.opacity(focused ? 0.8 : 0), lineWidth: 2)
        }
        // Floats on the row's top edge (over the divider), so it never covers the first line of text.
        .overlay(alignment: .topTrailing) {
            actions.offset(x: -8, y: -13)
                .opacity(showsActions ? 1 : 0).scaleEffect(showsActions || reduceMotion ? 1 : 0.94, anchor: .topTrailing)
                .allowsHitTesting(showsActions).accessibilityHidden(true)
        }
        .zIndex(showsActions ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showsActions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: highlighted)
        .onHover { hovering = $0 }
        // Reachable with Tab when Full Keyboard Access is on; a click still selects text instead of focusing.
        .focusable(interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) { showInPDF(); return .handled }
        .onCopyCommand { [NSItemProvider(object: (pending ? paragraph.original : paragraph.translated) as NSString)] }
        .popover(isPresented: $peeking, arrowEdge: .leading) {
            if let pdf {
                PDFPeek(pdf: pdf, paragraph: paragraph, number: number,
                        close: { peeking = false }, openFull: { peeking = false; openInPDF() })
            }
        }
        .contextMenu {
            Button("Copiar tradução", systemImage: "doc.on.doc") { copy(paragraph.translated) }.disabled(pending)
            Button("Copiar original", systemImage: "doc.on.doc") { copy(paragraph.original) }
            Divider()
            Button("Perguntar sobre este trecho", systemImage: "sparkles", action: ask)
            Button("Mostrar no PDF original", systemImage: "doc.viewfinder", action: showInPDF)
            Button("Abrir no modo PDF original", systemImage: "arrow.up.left.and.arrow.down.right", action: openInPDF)
        }
        // The hover bar is hidden from VoiceOver; offer the same actions on the paragraph itself.
        .accessibilityActions {
            if !pending { Button("Copiar tradução") { copy(paragraph.translated) } }
            Button("Copiar original") { copy(paragraph.original) }
            Button("Perguntar sobre este trecho", action: ask)
            Button("Mostrar no PDF original", action: showInPDF)
            Button("Abrir no modo PDF original", action: openInPDF)
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
        .readerGlass(in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
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
