import Foundation

/// Turns a model answer into text whose citations ("[2]") and page mentions ("p. 12") are links back into the document.
enum AnswerFormatter {
    static let scheme = "paragrafo"

    /// `pages`, when given, limits page links to pages that really back the answer.
    static func markdown(_ text: String, sourceCount: Int, pages: Set<Int>? = nil) -> String {
        var lines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            var line = raw
            if let match = line.firstMatch(of: #/^\s*#{1,6}\s+(.+?)\s*#*\s*$/#) {
                line = "**\(match.1.replacing("**", with: ""))**"
            } else if let match = line.firstMatch(of: #/^(\s*)(?:[*\-•]\s+)+(.*)$/#) {
                line = "\(match.1)• \(match.2)"
            }
            lines.append(line)
        }
        var out = lines.joined(separator: "\n")
        out = out.replacing(#/\[(\d{1,2}(?:\s*[,;]\s*\d{1,2})*)\]/#) { match in
            match.1.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                .filter { (1...max(sourceCount, 1)).contains($0) && sourceCount > 0 }
                .map { "[\\[\($0)\\]](\(scheme)://fonte/\($0))" }.joined(separator: " ")
        }
        out = out.replacing(#/(?i)\b(páginas?|paginas?|pág\.|pag\.|p\.|pages?)\s*(\d{1,4})\b/#) { match in
            guard let page = Int(match.2), pages?.contains(page) ?? true else { return String(match.0) }
            return "[\(match.1) \(match.2)](\(scheme)://pagina/\(page))"
        }
        return out
    }

    static func attributed(_ text: String, sourceCount: Int, pages: Set<Int>? = nil) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: markdown(text, sourceCount: sourceCount, pages: pages), options: options)) ?? AttributedString(text)
    }

    enum Destination: Equatable { case source(Int), page(Int) }

    static func destination(_ url: URL) -> Destination? {
        guard url.scheme == scheme, let number = Int(url.lastPathComponent), number > 0 else { return nil }
        switch url.host {
        case "fonte": return .source(number)
        case "pagina": return .page(number)
        default: return nil
        }
    }
}
