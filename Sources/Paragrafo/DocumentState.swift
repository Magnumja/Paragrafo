import Foundation

/// Page offsets and completed count are updated only when document data changes.
struct DocumentState {
    private(set) var paragraphs: [Paragraph] = []
    private(set) var pageRanges: [Int: Range<Int>] = [:]
    private(set) var pages: [Int] = []
    private(set) var completed = 0

    init(_ paragraphs: [Paragraph] = []) {
        self.paragraphs = paragraphs
        completed = paragraphs.filter { !$0.translated.isEmpty }.count
        for index in paragraphs.indices {
            let page = paragraphs[index].page
            if let range = pageRanges[page] {
                pageRanges[page] = range.lowerBound..<(index + 1)
            } else {
                pages.append(page)
                pageRanges[page] = index..<(index + 1)
            }
        }
    }

    var isEmpty: Bool { paragraphs.isEmpty }
    var count: Int { paragraphs.count }

    mutating func apply(_ text: String, at index: Int) {
        guard paragraphs.indices.contains(index), !text.isEmpty else { return }
        if paragraphs[index].translated.isEmpty { completed += 1 }
        paragraphs[index].translated = text
    }

    mutating func clearTranslations() {
        for index in paragraphs.indices { paragraphs[index].translated = "" }
        completed = 0
    }
}
