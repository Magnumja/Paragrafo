import AppKit
import CoreText
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, markdown, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: "PDF traduzido"
        case .markdown: "Markdown bilíngue"
        case .text: "Texto bilíngue"
        }
    }
    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .markdown: "text.badge.checkmark"
        case .text: "doc.plaintext"
        }
    }
    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .markdown: "md"
        case .text: "txt"
        }
    }
    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .text: .plainText
        }
    }
}

enum Exporter {
    static func data(_ format: ExportFormat, filename: String, targetName: String, document: DocumentState) -> Data {
        switch format {
        case .text: Data(text(filename: filename, targetName: targetName, document: document).utf8)
        case .markdown: Data(markdown(filename: filename, targetName: targetName, document: document).utf8)
        case .pdf: pdf(filename: filename, targetName: targetName, document: document)
        }
    }

    static func text(filename: String, targetName: String, document: DocumentState) -> String {
        "\(filename)\nTradução para \(targetName) · \(document.completed)/\(document.count) parágrafos\n\n"
            + document.paragraphs.enumerated().map { index, paragraph in
                "Página \(paragraph.page) · Parágrafo \(index + 1)\n\nORIGINAL\n\(paragraph.original)\n\nTRADUÇÃO\n\(paragraph.translated.isEmpty ? "[Não traduzido]" : paragraph.translated)"
            }.joined(separator: "\n\n————————————\n\n")
    }

    static func markdown(filename: String, targetName: String, document: DocumentState) -> String {
        var out = "# \(filename)\n\nTradução para \(targetName) · \(document.completed)/\(document.count) parágrafos\n"
        for page in document.pages {
            out += "\n## Página \(page)\n"
            for index in document.pageRanges[page] ?? 0..<0 {
                let paragraph = document.paragraphs[index]
                out += "\n\(paragraph.translated.isEmpty ? "_[Não traduzido]_" : paragraph.translated)\n\n"
                out += paragraph.original.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n") + "\n"
            }
        }
        return out
    }

    /// A clean reading copy of the translation on A4. Untranslated passages stay in the original, in gray.
    static func pdf(filename: String, targetName: String, document: DocumentState) -> Data {
        let serif = { (size: CGFloat, weight: NSFont.Weight) -> NSFont in
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        let body = NSMutableParagraphStyle()
        body.lineSpacing = 4
        body.paragraphSpacing = 11
        let heading = NSMutableParagraphStyle()
        heading.paragraphSpacingBefore = 14
        heading.paragraphSpacing = 8
        let ink = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let muted = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.45, alpha: 1)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + "\n",
                                       attributes: [.font: serif(22, .semibold), .foregroundColor: ink, .paragraphStyle: heading]))
        text.append(NSAttributedString(string: "Tradução para \(targetName) · \(document.completed) de \(document.count) parágrafos\n",
                                       attributes: [.font: NSFont.systemFont(ofSize: 9.5), .foregroundColor: muted, .paragraphStyle: heading]))
        for page in document.pages {
            text.append(NSAttributedString(string: "PÁGINA \(page)\n",
                                           attributes: [.font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: muted, .kern: 1.2, .paragraphStyle: heading]))
            for index in document.pageRanges[page] ?? 0..<0 {
                let paragraph = document.paragraphs[index]
                let pending = paragraph.translated.isEmpty
                text.append(NSAttributedString(string: (pending ? paragraph.original : paragraph.translated) + "\n",
                                               attributes: [.font: serif(11.5, .regular), .foregroundColor: pending ? muted : ink, .paragraphStyle: body]))
            }
        }

        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let frameRect = box.insetBy(dx: 76, dy: 78)
        var location = 0
        var number = 1
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: location, length: 0), CGPath(rect: frameRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let footer = CTLineCreateWithAttributedString(NSAttributedString(string: "\(number)", attributes: [.font: NSFont.systemFont(ofSize: 8.5), .foregroundColor: muted]))
            context.textPosition = CGPoint(x: box.midX - CTLineGetTypographicBounds(footer, nil, nil, nil) / 2, y: 42)
            CTLineDraw(footer, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            location += visible.length
            number += 1
        } while location < text.length
        context.closePDF()
        return data as Data
    }
}
