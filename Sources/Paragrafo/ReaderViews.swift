import SwiftUI

@MainActor
enum ReaderStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.55, green: 0.76, blue: 0.65, alpha: 1)
            : NSColor(srgbRed: 0.22, green: 0.40, blue: 0.33, alpha: 1)
    })
}

struct EmptyReader: View {
    let importing: Bool
    let open: () -> Void
    private static let logo = Bundle.main.url(forResource: "paragrafo-logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if let logo = Self.logo {
                Image(nsImage: logo).resizable().renderingMode(.template).scaledToFit().frame(width: 190, height: 190)
                    .foregroundStyle(ReaderStyle.accent).accessibilityLabel("Parágrafo")
            } else {
                Image(systemName: "text.book.closed").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(ReaderStyle.accent).padding(32)
            }
            Text("Seu próximo documento.\nEm um idioma mais próximo.")
                .font(.system(size: 34, weight: .regular, design: .serif)).multilineTextAlignment(.center)
            Text("Traduza PDFs com o original ao lado.\nUm parágrafo de cada vez, sem perder o contexto.")
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .lineSpacing(5).padding(.top, 18)
            Button(action: open) {
                Label(importing ? "Lendo documento…" : "Escolher PDF", systemImage: "plus")
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }.readerPrimaryAction().controlSize(.large).disabled(importing).padding(.top, 28)
            Text("ou arraste um PDF para esta janela")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
            Spacer()
            HStack(spacing: 28) {
                Label("Texto e digitalizações", systemImage: "doc.text.viewfinder")
                Label("Sem conta", systemImage: "person.crop.circle.badge.checkmark")
                Label("No seu Mac", systemImage: "lock.shield")
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ParagraphCard: View {
    let paragraph: Paragraph
    let number: Int
    let targetName: String
    let translationOnly: Bool
    let fontSize: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(format: "%02d", number)).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
                Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
                Label(paragraph.translated.isEmpty ? "Pendente" : "Traduzido", systemImage: paragraph.translated.isEmpty ? "circle.dotted" : "checkmark.circle.fill")
                    .font(.system(size: 10)).foregroundStyle(paragraph.translated.isEmpty ? Color.secondary : ReaderStyle.accent)
            }
            if translationOnly {
                translation
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        original.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                        translation.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 20) { original; Divider(); translation }
                }
            }
        }.padding(24)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }

    private var original: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ORIGINAL").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            text(paragraph.original)
        }
    }
    private var translation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(targetName.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(ReaderStyle.accent)
                Spacer()
                if !paragraph.translated.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(paragraph.translated, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Copiar tradução do parágrafo \(number)").help("Copiar tradução")
                }
            }
            if paragraph.translated.isEmpty {
                Text("A tradução aparecerá aqui.").font(.system(size: fontSize, design: .serif)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else { text(paragraph.translated) }
        }
    }
    private func text(_ value: String) -> some View {
        Text(value).font(.system(size: fontSize, design: .serif)).lineSpacing(7)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
