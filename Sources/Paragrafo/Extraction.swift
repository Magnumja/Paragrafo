import Foundation
import PDFKit
import Vision
import AppKit

struct Paragraph: Identifiable, Sendable {
    let id = UUID()
    let page: Int
    var original: String
    var translated = ""
}

struct TextLine: Sendable {
    let text: String
    let x: Double
    let y: Double
    let height: Double
}

enum Paragraphs {
    // PDF coordinates rise from the bottom. Preserve the extractor's reading order.
    static func group(_ lines: [TextLine]) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: TextLine?
        for line in lines where !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prev = previous {
                let gap = prev.y - line.y
                let boundary = gap > max(prev.height, line.height) * 1.65
                    || gap < -prev.height * 0.6
                    || (line.x - prev.x > line.height * 1.2 && gap > line.height * 0.5)
                    || text.hasPrefix("• ")
                if boundary && !current.isEmpty { result.append(current); current = "" }
            }
            if !current.isEmpty { current += " " }
            current += text
            previous = line
        }
        if !current.isEmpty { result.append(current) }
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
}

enum PDFExtractor {
    static func extract(url: URL) throws -> Extracted {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url) else { throw ImportFailure.invalid }
        guard !pdf.isLocked else { throw ImportFailure.locked }
        var paragraphs: [Paragraph] = []
        var ocrPages = 0
        var emptyPages: [Int] = []
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index) else { emptyPages.append(index + 1); continue }
            var lines = (page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []).compactMap { selection -> TextLine? in
                guard let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let box = selection.bounds(for: page)
                return TextLine(text: text, x: box.minX, y: box.minY, height: box.height)
            }
            if lines.isEmpty {
                ocrPages += 1
                let size = page.bounds(for: .mediaBox).size
                let scale = min(3, 2400 / max(size.width, size.height, 1))
                let image = page.thumbnail(of: NSSize(width: size.width * scale, height: size.height * scale), for: .mediaBox)
                var rect = CGRect(origin: .zero, size: image.size)
                if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.automaticallyDetectsLanguage = true
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                    lines = (request.results ?? []).compactMap { observation in
                        guard let text = observation.topCandidates(1).first?.string else { return nil }
                        let box = observation.boundingBox
                        return TextLine(text: text, x: box.minX, y: box.minY, height: box.height)
                    }
                }
            }
            let blocks = Paragraphs.group(lines)
            if blocks.isEmpty { emptyPages.append(index + 1) }
            paragraphs += blocks.map { Paragraph(page: index + 1, original: $0) }
        }
        guard !paragraphs.isEmpty else { throw ImportFailure.empty }
        return Extracted(paragraphs: paragraphs, ocrPages: ocrPages, emptyPages: emptyPages)
    }
}
