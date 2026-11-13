import Foundation

/// Page offsets and completed count are updated only when document data changes.
struct DocumentState {
    private(set) var paragraphs: [Paragraph] = []
    private(set) var pageRanges: [Int: Range<Int>] = [:]
    private(set) var pages: [Int] = []
    private(set) var completed = 0
    private(set) var completedByPage: [Int: Int] = [:]

    init(_ paragraphs: [Paragraph] = []) {
        self.paragraphs = paragraphs
        for index in paragraphs.indices {
            let page = paragraphs[index].page
            if let range = pageRanges[page] {
                pageRanges[page] = range.lowerBound..<(index + 1)
            } else {
                pages.append(page)
                pageRanges[page] = index..<(index + 1)
            }
            if !paragraphs[index].translated.isEmpty {
                completed += 1
                completedByPage[page, default: 0] += 1
            }
        }
    }

    var isEmpty: Bool { paragraphs.isEmpty }
    var count: Int { paragraphs.count }
    var isComplete: Bool { !isEmpty && completed == count }

    mutating func apply(_ text: String, at index: Int) {
        guard paragraphs.indices.contains(index), !text.isEmpty else { return }
        if paragraphs[index].translated.isEmpty {
            completed += 1
            completedByPage[paragraphs[index].page, default: 0] += 1
        }
        paragraphs[index].translated = text
    }

    mutating func clearTranslations() {
        for index in paragraphs.indices { paragraphs[index].translated = "" }
        completed = 0
        completedByPage = [:]
    }

    /// Pending paragraphs starting at the page being read, then wrapping to the beginning.
    func pendingOrder(from page: Int) -> [Int] {
        let start = pageRanges[page]?.lowerBound ?? 0
        return (Array(start..<count) + Array(0..<start)).filter { paragraphs[$0].translated.isEmpty }
    }
}
