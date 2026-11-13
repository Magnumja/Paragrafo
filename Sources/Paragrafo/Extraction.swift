import Foundation
import PDFKit
import Vision
import AppKit
import CryptoKit

struct Paragraph: Identifiable, Sendable {
    let id = UUID()
    let page: Int
    var original: String
    var translated = ""
    /// Union of the paragraph's lines in PDF page coordinates, used to highlight it in the original.
    var bounds: CGRect? = nil
}

struct TextLine: Sendable {
    let text: String
    let x: Double
    let y: Double
    let height: Double
    var width: Double = 0
}

struct TextBlock: Sendable, Equatable {
    var text: String
    var bounds: CGRect
}

enum Paragraphs {
    static func group(_ lines: [TextLine]) -> [String] { blocks(lines).map(\.text) }

    // PDF coordinates rise from the bottom. Preserve the extractor's reading order.
    /// `splitOnSizeChange` separates headings from body text by line height. Only reliable for
    /// embedded text; OCR line boxes vary with the letters on the line.
    static func blocks(_ lines: [TextLine], splitOnSizeChange: Bool = false) -> [TextBlock] {
        var result: [TextBlock] = []
        var current = ""
        var bounds = CGRect.null
        var previous: TextLine?
        for line in lines where !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prev = previous {
                let gap = prev.y - line.y
                let boundary = gap > max(prev.height, line.height) * 1.65
                    || gap < -prev.height * 0.6
                    || (line.x - prev.x > line.height * 1.2 && gap > line.height * 0.5)
                    || text.hasPrefix("• ")
                    || (splitOnSizeChange && max(prev.height, line.height) > min(prev.height, line.height) * 1.25)
                if boundary && !current.isEmpty {
                    result.append(TextBlock(text: current, bounds: bounds))
                    current = ""
                    bounds = .null
                }
            }
            // A word hyphenated at the end of a line continues in lowercase on the next one.
            if current.hasSuffix("-"), current.dropLast().last?.isLetter == true, text.first?.isLowercase == true {
                current.removeLast()
            } else if !current.isEmpty {
                current += " "
            }
            current += text
            bounds = bounds.union(CGRect(x: line.x, y: line.y, width: line.width, height: line.height))
            previous = line
        }
        if !current.isEmpty { result.append(TextBlock(text: current, bounds: bounds)) }
        return result
    }
}

enum ImportFailure: LocalizedError {
    case invalid, locked, empty
    var errorDescription: String? {
        switch self {
        case .invalid: "Não foi possível abrir este PDF."
        case .locked: "Este PDF está protegido. Abra uma cópia desbloqueada."
        case .empty: "Nenhum texto foi reconhecido neste PDF."
        }
    }
}

struct Extracted: Sendable {
    let paragraphs: [Paragraph]
    let ocrPages: Int
    let emptyPages: [Int]
    var pageCount = 0
    /// SHA-256 of the file, the key for saved translations and the search index.
    var fingerprint = ""
}

enum PDFExtractor {
    static func extract(url: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> Extracted {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url) else { throw ImportFailure.invalid }
        guard !pdf.isLocked else { throw ImportFailure.locked }
        var paragraphs: [Paragraph] = []
        var ocrPages = 0
        var emptyPages: [Int] = []
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            progress(index + 1, pdf.pageCount)
            let pageParagraphs: [Paragraph] = try autoreleasepool {
            guard let page = pdf.page(at: index) else { emptyPages.append(index + 1); return [] }
                let media = page.bounds(for: .mediaBox)
                var lines = (page.selection(for: media)?.selectionsByLine() ?? []).compactMap { selection -> TextLine? in
                    guard let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let box = selection.bounds(for: page)
                    return TextLine(text: text, x: box.minX, y: box.minY, height: box.height, width: box.width)
                }
                let recognized = lines.isEmpty
                if recognized {
                    ocrPages += 1
                    let scale = min(3, 2400 / max(media.width, media.height, 1))
                    let image = page.thumbnail(of: NSSize(width: media.width * scale, height: media.height * scale), for: .mediaBox)
                    var rect = CGRect(origin: .zero, size: image.size)
                    if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.automaticallyDetectsLanguage = true
                        request.usesLanguageCorrection = true
                        try VNImageRequestHandler(cgImage: cgImage).perform([request])
                        lines = (request.results ?? []).compactMap { observation in
                            guard let text = observation.topCandidates(1).first?.string else { return nil }
                            // Vision boxes are normalized; map them to the page so highlights line up.
                            let box = observation.boundingBox
                            return TextLine(text: text, x: media.minX + box.minX * media.width, y: media.minY + box.minY * media.height,
                                            height: box.height * media.height, width: box.width * media.width)
                        }
                    }
                }
                try Task.checkCancellation()
                let blocks = Paragraphs.blocks(lines, splitOnSizeChange: !recognized)
                if blocks.isEmpty { emptyPages.append(index + 1) }
                return blocks.map { Paragraph(page: index + 1, original: $0.text, bounds: $0.bounds.isNull ? nil : $0.bounds) }
            }
            paragraphs += pageParagraphs
        }
        guard !paragraphs.isEmpty else { throw ImportFailure.empty }
        let digest = (try? Data(contentsOf: url, options: .mappedIfSafe)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
        return Extracted(paragraphs: paragraphs, ocrPages: ocrPages, emptyPages: emptyPages, pageCount: pdf.pageCount, fingerprint: digest)
    }
}
