import XCTest
@testable import Paragrafo

final class ParagraphTests: XCTestCase {

func test_joinsWrappedLinesAndPreservesNumbers() {
    let lines = [TextLine(text: "Receita de 2025:", x: 10, y: 100, height: 12), TextLine(text: "R$ 1.250,00.", x: 10, y: 86, height: 12)]
    XCTAssertTrue(Paragraphs.group(lines) == ["Receita de 2025: R$ 1.250,00."])
}
func test_separatesParagraphGap() {
    let lines = [TextLine(text: "Primeiro.", x: 10, y: 100, height: 12), TextLine(text: "Segundo.", x: 10, y: 65, height: 12)]
    XCTAssertTrue(Paragraphs.group(lines) == ["Primeiro.", "Segundo."])
}
func test_retainsUnicodeAndListBoundaries() {
    let lines = [TextLine(text: "日本語 العربية", x: 10, y: 100, height: 12), TextLine(text: "• café", x: 10, y: 86, height: 12)]
    XCTAssertTrue(Paragraphs.group(lines) == ["日本語 العربية", "• café"])
}
func test_ignoresBlankLines() {
    XCTAssertTrue(Paragraphs.group([TextLine(text: "  ", x: 0, y: 0, height: 12)]).isEmpty)
}

}
