import Foundation
import NaturalLanguage

enum TranslationInput {
    static func needsTranslation(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    static func detectLanguage(in paragraphs: [Paragraph]) -> String? {
        var sample = ""
        for paragraph in paragraphs where needsTranslation(paragraph.original) {
            sample += String(paragraph.original.prefix(2000)) + "\n"
            if sample.count >= 12000 { break }
        }
        guard !sample.isEmpty else { return nil }
        return NLLanguageRecognizer.dominantLanguage(for: sample)?.rawValue
    }

    static func sameLanguage(_ source: String, _ target: String) -> Bool {
        let a = Locale.Language(identifier: source)
        let b = Locale.Language(identifier: target)
        return a.languageCode == b.languageCode && a.script == b.script
    }
}
